using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class Test : MonoBehaviour
{
    private RenderTexture rt;
    public Transform cubeTransform;
    public Mesh cubeMesh;
    public Material pureColorMaterial;

    void Start()
    {
        rt = new RenderTexture(Screen.width, Screen.height, 24);
    }

    public void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        Camera cam = Camera.current;
        Graphics.SetRenderTarget(rt);
        GL.Clear(true, true, Color.grey);

        //start drawcall
        pureColorMaterial.color = new Color(0, 0.5f, 0.8f);
        pureColorMaterial.SetPass(0);
        Graphics.DrawMeshNow(cubeMesh, cubeTransform.localToWorldMatrix);
        //end drawcall

        //Graphics.Blit(rt, destination);
        Graphics.Blit(rt, cam.targetTexture);
    }

    private void OnPostRender2()
    {
        Camera cam = Camera.current;
        Graphics.SetRenderTarget(rt);
        GL.Clear(true, true, Color.grey);

        //start drawcall
        pureColorMaterial.color = new Color(0, 0.5f, 0.8f);
        pureColorMaterial.SetPass(0);
        Graphics.DrawMeshNow(cubeMesh, cubeTransform.localToWorldMatrix);
        //end drawcall

        Graphics.Blit(rt, cam.targetTexture);
    }
}
