Shader "ClusterBasedLightingGit/Shader_Color"
{
	Properties
	{
		_MainTex("Texture", 2D) = "white" {}
	}
		SubShader
	{
		Tags { "RenderType" = "Opaque" }
		LOD 100

		Pass
		{
			CGPROGRAM
#pragma vertex vert
#pragma fragment frag

#include "UnityCG.cginc"

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
				float3 normal : NORMAL;
			};

			struct v2f
			{
				float4 vertex	: SV_POSITION;
				float4 posWorld : WORLDPOS;
				float2 uv		: TEXCOORD0;
				float3 normal	: TEXCOORD1;
			};

			sampler2D _MainTex;
			float4 _MainTex_ST;

			v2f vert(appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.posWorld = mul(unity_ObjectToWorld, v.vertex);
				o.uv = TRANSFORM_TEX(v.uv, _MainTex);
				o.normal = UnityObjectToWorldNormal(v.normal);
				return o;
			}

			StructuredBuffer<uint2>		PointLightGrid_Cluster;
			StructuredBuffer<uint>		PointLightIndexList_Cluster;
			StructuredBuffer<float4>	PointLights;
			StructuredBuffer<float4>	PointLightsColors;

			float3 ACESFilm(float3 x)
			{
				float a = 2.51f;
				float b = 0.03f;
				float c = 2.43f;
				float d = 0.59f;
				float e = 0.14f;
				return saturate((x*(a*x + b)) / (x*(c*x + d) + e));
			}

			fixed4 frag(v2f psInput) : SV_Target
			{
				// sample the texture
				fixed4 col = tex2D(_MainTex, psInput.uv);

			float3 normal = normalize(psInput.normal);

			uint clusterIndex1D = ComputeClusterIndex1D(psInput.vertex.xy, psInput.vertex.w);

			// Get the start position and offset of the light in the light index list.
			uint startOffset = PointLightGrid_Cluster[clusterIndex1D].x;
			uint lightCount = PointLightGrid_Cluster[clusterIndex1D].y;

			float4 pointLightFinal = 0;
			// Iterate point lights.
			for (uint i = 0; i < lightCount; ++i)
			{
				uint lightIndex = PointLightIndexList_Cluster[startOffset + i];

				float3	pointLightPos = PointLights[lightIndex].xyz;
				float	pointLightRadius = PointLights[lightIndex].w;
				float4  pointLightColor = PointLightsColors[lightIndex];

				float3 ToLight = psInput.posWorld.xyz - pointLightPos;
				float  disToLight = distance(psInput.posWorld.xyz, pointLightPos);

				float3 lightDirection = normalize(ToLight);
				float NdotL = saturate(dot(normal, lightDirection));

				float disFactor = (saturate(pointLightRadius - disToLight)) / pointLightRadius;
				pointLightFinal += NdotL * col * disFactor * pointLightColor;
			}

			pointLightFinal += col * 0.1;
			pointLightFinal.rgb = ACESFilm(pointLightFinal.rgb);

			return pointLightFinal;
			}
			ENDCG
		}
	}
}