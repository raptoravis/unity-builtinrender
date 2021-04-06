using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using System.Runtime.InteropServices;

struct CD_DIM
{
    public float fieldOfViewY;
    public float zNear;
    public float zFar;

    public float sD;
    public float logDimY;
    public float logDepth;

    public int clusterDimX;
    public int clusterDimY;
    public int clusterDimZ;
    public int clusterDimXYZ;
};

struct AABB
{
    Vector4 min;
    Vector4 max;
};

[ExecuteInEditMode]
[ImageEffectAllowedInSceneView]
public class Script_ClusterBasedLighting : MonoBehaviour
{
    public GameObject go_SceneListParent;
    private List<Material> lst_Mtl;
    private List<Mesh> lst_Mesh;
    private List<Transform> lst_TF;

    private Camera _camera;
    private RenderTexture _rtColor;
    private RenderTexture _rtDepth;

    public int m_ClusterGridBlockSize = 32;
    public ComputeShader cs_ComputeClusterAABB;
    public ComputeShader cs_AssignLightsToClusts;
    public Material mtlDebugCluster;

    CD_DIM m_DimData;


    const int MaxLightsCount = 10000;
    const int m_AVERAGE_OVERLAPPING_LIGHTS_PER_CLUSTER = 200;

    private ComputeBuffer cb_ClusterAABBs;
    private ComputeBuffer cb_PointLightPosRadius;

    private ComputeBuffer cb_ClusterPointLightIndexCounter;
    private ComputeBuffer cb_ClusterPointLightGrid;
    private ComputeBuffer cb_ClusterPointLightIndexList;

    private ComputeBuffer cb_UniqueClusterCount;
    private ComputeBuffer cb_IAB_AssignLightsToClusters;
    private ComputeBuffer cb_IAB_DrawDebugClusters;

    private ComputeBuffer cb_ClusterFlag;
    private ComputeBuffer cb_UniqueClusters;

    private List<Light> lightList;

    void CalculateMDim(Camera cam)
    {
        // The half-angle of the field of view in the Y-direction.
        float fieldOfViewY = cam.fieldOfView * Mathf.Deg2Rad * 0.5f;//Degree 2 Radiance:  Param.CameraInfo.Property.Perspective.fFovAngleY * 0.5f;
        float zNear = cam.nearClipPlane;// Param.CameraInfo.Property.Perspective.fMinVisibleDistance;
        float zFar = cam.farClipPlane;// Param.CameraInfo.Property.Perspective.fMaxVisibleDistance;

        // Number of clusters in the screen X direction.
        int clusterDimX = Mathf.CeilToInt(Screen.width / (float)m_ClusterGridBlockSize);
        // Number of clusters in the screen Y direction.
        int clusterDimY = Mathf.CeilToInt(Screen.height / (float)m_ClusterGridBlockSize);

        // The depth of the cluster grid during clustered rendering is dependent on the 
        // number of clusters subdivisions in the screen Y direction.
        // Source: Clustered Deferred and Forward Shading (2012) (Ola Olsson, Markus Billeter, Ulf Assarsson).
        float sD = 2.0f * Mathf.Tan(fieldOfViewY) / (float)clusterDimY;
        float logDimY = 1.0f / Mathf.Log(1.0f + sD);

        float logDepth = Mathf.Log(zFar / zNear);
        int clusterDimZ = Mathf.FloorToInt(logDepth * logDimY);

        m_DimData.zNear = zNear;
        m_DimData.zFar = zFar;
        m_DimData.sD = sD;
        m_DimData.fieldOfViewY = fieldOfViewY;
        m_DimData.logDepth = logDepth;
        m_DimData.logDimY = logDimY;
        m_DimData.clusterDimX = clusterDimX;
        m_DimData.clusterDimY = clusterDimY;
        m_DimData.clusterDimZ = clusterDimZ;
        m_DimData.clusterDimXYZ = clusterDimX * clusterDimY * clusterDimZ;
    }
    void InitClusterBuffers()
    {
        cb_ClusterPointLightIndexCounter = new ComputeBuffer(1, sizeof(uint));
        cb_UniqueClusterCount = new ComputeBuffer(1, sizeof(uint), ComputeBufferType.Raw);
        cb_IAB_AssignLightsToClusters = new ComputeBuffer(1, sizeof(uint) * 3, ComputeBufferType.IndirectArguments);
        cb_IAB_DrawDebugClusters = new ComputeBuffer(1, sizeof(uint) * 4, ComputeBufferType.IndirectArguments);


        cb_ClusterPointLightGrid = new ComputeBuffer(m_DimData.clusterDimXYZ, sizeof(uint) * 2);
        cb_ClusterPointLightIndexList = new ComputeBuffer(m_DimData.clusterDimXYZ * m_AVERAGE_OVERLAPPING_LIGHTS_PER_CLUSTER, sizeof(uint));

        cb_ClusterFlag = new ComputeBuffer(m_DimData.clusterDimXYZ, sizeof(float));
        cb_UniqueClusters = new ComputeBuffer(m_DimData.clusterDimXYZ, sizeof(uint), ComputeBufferType.Counter);
    }

    void Start()
    {
        _rtColor = new RenderTexture(Screen.width, Screen.height, 24);
        _rtDepth = new RenderTexture(Screen.width, Screen.height, 24, RenderTextureFormat.Depth, RenderTextureReadWrite.Linear);

        _camera = this.gameObject.GetComponent<Camera>();

        if (_camera != null)
        {
            InitSceneObject();

            //_camera = Camera.current;
            CalculateMDim(_camera);

            InitClusterBuffers();

            int stride = Marshal.SizeOf(typeof(AABB));
            cb_ClusterAABBs = new ComputeBuffer(m_DimData.clusterDimXYZ, stride);

            cb_ClusterPointLightGrid = new ComputeBuffer(MaxLightsCount, Marshal.SizeOf(typeof(Vector4)));

            Pass_ComputeClusterAABB();
        }
    }

    void UpdateClusterCBuffer(ComputeShader cs)
    {
        int[] gridDims = { m_DimData.clusterDimX, m_DimData.clusterDimY, m_DimData.clusterDimZ };
        int[] sizes = { m_ClusterGridBlockSize, m_ClusterGridBlockSize };
        Vector4 screenDim = new Vector4((float)Screen.width, (float)Screen.height, 1.0f / Screen.width, 1.0f / Screen.height);
        float viewNear = m_DimData.zNear;

        cs.SetInts("ClusterCB_GridDim", gridDims);
        cs.SetFloat("ClusterCB_ViewNear", viewNear);
        cs.SetInts("ClusterCB_Size", sizes);
        cs.SetFloat("ClusterCB_NearK", 1.0f + m_DimData.sD);
        cs.SetFloat("ClusterCB_LogGridDimY", m_DimData.logDimY);
        cs.SetVector("ClusterCB_ScreenDimensions", screenDim);
    }
    void Pass_ComputeClusterAABB()
    {
        var projectionMatrix = GL.GetGPUProjectionMatrix(_camera.projectionMatrix, false);
        var projectionMatrixInvers = projectionMatrix.inverse;
        cs_ComputeClusterAABB.SetMatrix("_InverseProjectionMatrix", projectionMatrixInvers);

        UpdateClusterCBuffer(cs_ComputeClusterAABB);

        int threadGroups = Mathf.CeilToInt(m_DimData.clusterDimXYZ / 1024.0f);

        int kernel = cs_ComputeClusterAABB.FindKernel("CSMain");
        cs_ComputeClusterAABB.SetBuffer(kernel, "RWClusterAABBs", cb_ClusterAABBs);
        cs_ComputeClusterAABB.Dispatch(kernel, threadGroups, 1, 1);
    }

    void Pass_DebugCluster()
    {
        GL.wireframe = true;

        mtlDebugCluster.SetBuffer("ClusterAABBs", cb_ClusterAABBs);
        mtlDebugCluster.SetBuffer("PointLightGrid_Cluster", cb_ClusterPointLightGrid);

        mtlDebugCluster.SetPass(0);

        mtlDebugCluster.SetMatrix("_CameraWorldMatrix", _camera.transform.localToWorldMatrix);

        Graphics.DrawProceduralNow(MeshTopology.Points, m_DimData.clusterDimXYZ);

        GL.wireframe = false;
    }

    void UpdateLightBuffer()
    {
        List<Vector4> lightPosRatioList = new List<Vector4>();
        foreach (var lit in lightList)
        {
            lightPosRatioList.Add(new Vector4(lit.transform.position.x, lit.transform.position.y, lit.transform.position.z, lit.range));
        }

        cb_PointLightPosRadius.SetData(lightPosRatioList);
    }

    void ClearLightGirdIndexCounter()
    { 
    }


    void Pass_AssignLightsToClusts()
    {
        ClearLightGirdIndexCounter();

        int kernel = cs_AssignLightsToClusts.FindKernel("CSMain");

        //Output
        cs_AssignLightsToClusts.SetBuffer(kernel, "RWPointLightIndexCounter_Cluster", cb_ClusterPointLightIndexCounter);
        cs_AssignLightsToClusts.SetBuffer(kernel, "RWPointLightGrid_Cluster", cb_ClusterPointLightGrid);
        cs_AssignLightsToClusts.SetBuffer(kernel, "RWPointLightIndexList_Cluster", cb_ClusterPointLightIndexList);

        //Input
        cs_AssignLightsToClusts.SetInt("PointLightCount", lightList.Count);
        cs_AssignLightsToClusts.SetMatrix("_CameraLastViewMatrix", _camera.transform.worldToLocalMatrix);
        cs_AssignLightsToClusts.SetBuffer(kernel, "PointLights", cb_PointLightPosRadius);
        cs_AssignLightsToClusts.SetBuffer(kernel, "ClusterAABBs", cb_ClusterAABBs);

        cs_AssignLightsToClusts.SetMatrix("_CameraLastViewMatrix", _camera.transform.worldToLocalMatrix);

        cs_AssignLightsToClusts.Dispatch(kernel, m_DimData.clusterDimXYZ, 1, 1);
    }

    void InitSceneObject()
    {
        if (Application.isPlaying)
        {
            lst_Mesh = new List<Mesh>();
            lst_TF = new List<Transform>();
            lst_Mtl = new List<Material>();

            MeshFilter[] mf_Parent = go_SceneListParent.GetComponentsInChildren<MeshFilter>();
            foreach (MeshFilter mf in mf_Parent)
            {
                lst_Mesh.Add(mf.mesh);
            }

            Transform[] tf_Parent = go_SceneListParent.GetComponentsInChildren<Transform>();
            foreach (Transform tf in tf_Parent)
            {
                lst_TF.Add(tf);
            }

            MeshRenderer[] mr_Parent = go_SceneListParent.GetComponentsInChildren<MeshRenderer>();
            foreach (MeshRenderer mr in mr_Parent)
            {
                Material mtl = new Material(Shader.Find("Unlit/Texture"));
                mtl.SetTexture("_MainTex", mr.material.GetTexture("_MainTex"));
                lst_Mtl.Add(mtl);
            }
        }
    }

    void Pass_DrawSceneColor()
    {
        if (lst_Mesh != null)
        {
            //GL.wireframe = true;
            for (int i = 0; i < lst_Mesh.Count; i++)
            {
                lst_Mtl[i].SetPass(0);
                Graphics.DrawMeshNow(lst_Mesh[i], lst_TF[i].localToWorldMatrix);
            }
        }
        //GL.wireframe = false;
    }

    void OnRenderImage(RenderTexture sourceTexture, RenderTexture destTexture)
    {
        if (Application.isPlaying)
        {
            Graphics.SetRenderTarget(_rtColor.colorBuffer, _rtDepth.depthBuffer);
            GL.Clear(true, true, Color.gray);

            Pass_DrawSceneColor();
            //Pass_DebugCluster();

            Graphics.Blit(_rtColor, destTexture);
        }
    }
   
}
