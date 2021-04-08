// Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'
// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "Physically-Based-Lighting" {
    Properties { 
        _Color ("Main Color", Color) = (1,1,1,1)                    //diffuse Color
        _SpecularColor ("Specular Color", Color) = (1,1,1,1)        //Specular Color (Not Used)
        _Glossiness("Smoothness",Range(0,1)) = 1                    //My Smoothness
        _Metallic("Metalness",Range(0,1)) = 0                    //My Metal Value      


                                                                 // future shader properties will go here!! Will be referred to as Shader Property Section
    }

        SubShader {
        Tags {
                "RenderType"="Opaque"  "Queue"="Geometry"
        } 
        Pass {
                Name "FORWARD"
                Tags {
                "LightMode"="ForwardBase"
        }
        CGPROGRAM
#pragma vertex vert
#pragma fragment frag
#define UNITY_PASS_FORWARDBASE
#include "UnityCG.cginc"
#include "AutoLight.cginc"
#include "Lighting.cginc"
#pragma multi_compile_fwdbase_fullshadows  
#pragma target 3.0

        float4 _Color;
        float4 _SpecularColor;
        float _Glossiness;
        float _Metallic;

        //future public variables will go here! Public Variables Section

        struct VertexInput {
            float4 vertex : POSITION;       //local vertex position
            float3 normal : NORMAL;         //normal direction
            float4 tangent : TANGENT;       //tangent direction    
            float2 texcoord0 : TEXCOORD0;   //uv coordinates
            float2 texcoord1 : TEXCOORD1;   //lightmap uv coordinates
        };

        struct VertexOutput {
            float4 pos : SV_POSITION;              //screen clip space position and depth
            float2 uv0 : TEXCOORD0;                //uv coordinates
            float2 uv1 : TEXCOORD1;                //lightmap uv coordinates

                                                   //below we create our own variables with the texcoord semantic. 
            float3 normalDir : TEXCOORD3;          //normal direction   
            float3 posWorld : TEXCOORD4;          //normal direction   
            float3 tangentDir : TEXCOORD5;
            float3 bitangentDir : TEXCOORD6;
            LIGHTING_COORDS(7,8)                   //this initializes the unity lighting and shadow
            UNITY_FOG_COORDS(9)                    //this initializes the unity fog
        };

        VertexOutput vert (VertexInput v) {
            VertexOutput o = (VertexOutput)0;           
            o.uv0 = v.texcoord0;
            o.uv1 = v.texcoord1;
            o.normalDir = UnityObjectToWorldNormal(v.normal);
            o.tangentDir = normalize( mul( unity_ObjectToWorld, float4( v.tangent.xyz, 0.0 ) ).xyz );
            o.bitangentDir = normalize(cross(o.normalDir, o.tangentDir) * v.tangent.w);
            o.pos = UnityObjectToClipPos(v.vertex);
            o.posWorld = mul(unity_ObjectToWorld, v.vertex);
            UNITY_TRANSFER_FOG(o,o.pos);
            TRANSFER_VERTEX_TO_FRAGMENT(o)
            return o;
        }    

        //helper functions will go here!!! Helper Function Section


        //algorithms we build will be placed here!!! Algorithm Section
        float BlinnPhongNormalDistribution(float NdotH, float specularpower, float speculargloss){
            float Distribution = pow(NdotH,speculargloss) * specularpower;
            Distribution *= (2+specularpower) / (2*3.1415926535);
            return Distribution;
        }

        float PhongNormalDistribution(float RdotV, float specularpower, float speculargloss){
            float Distribution = pow(RdotV,speculargloss) * specularpower;
            Distribution *= (2+specularpower) / (2*3.1415926535);
            return Distribution;
        }

        float BeckmannNormalDistribution(float roughness, float NdotH)
        {
            float roughnessSqr = roughness*roughness;
            float NdotHSqr = NdotH*NdotH;
            return max(0.000001,(1.0 / (3.1415926535*roughnessSqr*NdotHSqr*NdotHSqr))
                * exp((NdotHSqr-1)/(roughnessSqr*NdotHSqr)));
        }

        float GaussianNormalDistribution(float roughness, float NdotH)
        {
            float roughnessSqr = roughness*roughness;
            float thetaH = acos(NdotH);
            return exp(-thetaH*thetaH/roughnessSqr);
        }

        float4 frag(VertexOutput i) : COLOR {

            //normal direction calculations
            float3 normalDirection = normalize(i.normalDir);

            float3 lightDirection = normalize(lerp(_WorldSpaceLightPos0.xyz, _WorldSpaceLightPos0.xyz - i.posWorld.xyz,_WorldSpaceLightPos0.w));

            float3 lightReflectDirection = reflect( -lightDirection, normalDirection );

            float3 viewDirection = normalize(_WorldSpaceCameraPos.xyz - i.posWorld.xyz);

            float3 viewReflectDirection = normalize(reflect( -viewDirection, normalDirection ));

            float3 halfDirection = normalize(viewDirection+lightDirection); 

            float NdotL = max(0.0, dot( normalDirection, lightDirection ));

            float NdotH =  max(0.0,dot( normalDirection, halfDirection));

            float NdotV =  max(0.0,dot( normalDirection, viewDirection));

            float VdotH = max(0.0,dot( viewDirection, halfDirection));

            float LdotH =  max(0.0,dot(lightDirection, halfDirection));

            float LdotV = max(0.0,dot(lightDirection, viewDirection)); 

            float RdotV = max(0.0, dot( lightReflectDirection, viewDirection ));

            float attenuation = LIGHT_ATTENUATION(i);

            float3 attenColor = attenuation * _LightColor0.rgb;

            float roughness = 1- (_Glossiness * _Glossiness);   // 1 - smoothness*smoothness

            roughness = roughness * roughness;

            float3 diffuseColor = _Color.rgb * (1-_Metallic) ;

            float3 specColor = lerp(_SpecularColor.rgb, _Color.rgb, _Metallic * 0.5);

            //future code will go here!    Fragment Section
            float3 SpecularDistribution = specColor;

            //the algorithm implementations will go here
            //SpecularDistribution *=  BlinnPhongNormalDistribution(NdotH, _Glossiness,  max(1,_Glossiness * 40));
            //SpecularDistribution *=  PhongNormalDistribution(RdotV, _Glossiness, max(1,_Glossiness * 40));
            //SpecularDistribution *=  BeckmannNormalDistribution(roughness, NdotH);
            SpecularDistribution *=  GaussianNormalDistribution(roughness, NdotH);

            return float4(float3(1,1,1) * SpecularDistribution.rgb,1);
        }
        ENDCG
       }
    }

    FallBack "Legacy Shaders/Diffuse"
}