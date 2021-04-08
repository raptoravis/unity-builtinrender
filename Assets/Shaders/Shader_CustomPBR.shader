// Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'
// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "Physically-Based-Lighting" {
    Properties { 
        _Color ("Main Color", Color) = (1,1,1,1)                    //diffuse Color
        _SpecularColor ("Specular Color", Color) = (1,1,1,1)        //Specular Color (Not Used)
        _Glossiness("Smoothness",Range(0,1)) = 1                    //My Smoothness
        _Metallic("Metalness",Range(0,1)) = 0                    //My Metal Value      


                                                                 // future shader properties will go here!! Will be referred to as Shader Property Section
        _Anisotropic("Anisotropic",  Range(-20,1)) = 0
        _Ior("Ior",  Range(1,4)) = 1.5
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
#define sqr(x) (x * x)

        float4 _Color;
        float4 _SpecularColor;
        float _Glossiness;
        float _Metallic;

        //future public variables will go here! Public Variables Section
        float _Anisotropic;
        float _Ior;


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

        float GGXNormalDistribution(float roughness, float NdotH)
        {
            float roughnessSqr = roughness*roughness;
            float NdotHSqr = NdotH*NdotH;
            float TanNdotHSqr = (1-NdotHSqr)/NdotHSqr;
            return (1.0/3.1415926535) * sqr(roughness/(NdotHSqr * (roughnessSqr + TanNdotHSqr)));
        }
        
        float TrowbridgeReitzNormalDistribution(float NdotH, float roughness){
            float roughnessSqr = roughness*roughness;
            float Distribution = NdotH*NdotH * (roughnessSqr-1.0) + 1.0;
            return roughnessSqr / (3.1415926535 * Distribution*Distribution);
        }

        float TrowbridgeReitzAnisotropicNormalDistribution(float anisotropic, float NdotH, float HdotX, float HdotY){

            float aspect = sqrt(1.0h-anisotropic * 0.9h);
            float X = max(.001, sqr(1.0-_Glossiness)/aspect) * 5;
            float Y = max(.001, sqr(1.0-_Glossiness)*aspect) * 5;

            return 1.0 / (3.1415926535 * X*Y * sqr(sqr(HdotX/X) + sqr(HdotY/Y) + NdotH*NdotH));
        }

        float WardAnisotropicNormalDistribution(float anisotropic, float NdotL,
            float NdotV, float NdotH, float HdotX, float HdotY){
            float aspect = sqrt(1.0h-anisotropic * 0.9h);
            float X = max(.001, sqr(1.0-_Glossiness)/aspect) * 5;
            float Y = max(.001, sqr(1.0-_Glossiness)*aspect) * 5;
            float exponent = -(sqr(HdotX/X) + sqr(HdotY/Y)) / sqr(NdotH);
            float Distribution = 1.0 / (4.0 * 3.14159265 * X * Y * sqrt(NdotL * NdotV));
            Distribution *= exp(exponent);
            return Distribution;
        }


        float ImplicitGeometricShadowingFunction (float NdotL, float NdotV){
            float Gs =  (NdotL*NdotV);       
            return Gs;
        }

        float AshikhminShirleyGSF (float NdotL, float NdotV, float LdotH){
            float Gs = NdotL*NdotV/(LdotH*max(NdotL,NdotV));
            return  (Gs);
        }

        float AshikhminPremozeGeometricShadowingFunction (float NdotL, float NdotV){
            float Gs = NdotL*NdotV/(NdotL+NdotV - NdotL*NdotV);
            return  (Gs);
        }

        float DuerGeometricShadowingFunction (float3 lightDirection,float3 viewDirection, 
            float3 normalDirection,float NdotL, float NdotV){
            float3 LpV = lightDirection + viewDirection;
            float Gs = dot(LpV,LpV) * pow(dot(LpV,normalDirection),-4);
            return  (Gs);
        }

        float NeumannGeometricShadowingFunction (float NdotL, float NdotV){
            float Gs = (NdotL*NdotV)/max(NdotL, NdotV);       
            return  (Gs);
        }

        float KelemenGeometricShadowingFunction (float NdotL, float NdotV, 
            float LdotV, float VdotH){
            float Gs = (NdotL*NdotV)/(VdotH * VdotH); 
            return   (Gs);
        }

        float ModifiedKelemenGeometricShadowingFunction (float NdotV, float NdotL,
            float roughness)
        {
            float c = 0.797884560802865;    // c = sqrt(2 / Pi)
            float k = roughness * roughness * c;
            float gH = NdotV  * k +(1-k);
            return (gH * gH * NdotL);
        }

        float CookTorrenceGeometricShadowingFunction (float NdotL, float NdotV, 
            float VdotH, float NdotH){
            float Gs = min(1.0, min(2*NdotH*NdotV / VdotH, 
                2*NdotH*NdotL / VdotH));
            return  (Gs);
        }

        float WardGeometricShadowingFunction (float NdotL, float NdotV, 
            float VdotH, float NdotH){
            float Gs = pow( NdotL * NdotV, 0.5);
            return  (Gs);
        }

        float KurtGeometricShadowingFunction (float NdotL, float NdotV, 
            float VdotH, float roughness){
            float Gs =  NdotL*NdotV/(VdotH*pow(NdotL*NdotV, roughness));
            return  (Gs);
        }

        float WalterEtAlGeometricShadowingFunction (float NdotL, float NdotV, float alpha){
            float alphaSqr = alpha*alpha;
            float NdotLSqr = NdotL*NdotL;
            float NdotVSqr = NdotV*NdotV;

            float SmithL = 2/(1 + sqrt(1 + alphaSqr * (1-NdotLSqr)/(NdotLSqr)));
            float SmithV = 2/(1 + sqrt(1 + alphaSqr * (1-NdotVSqr)/(NdotVSqr)));


            float Gs =  (SmithL * SmithV);
            return Gs;
        }

        float BeckmanGeometricShadowingFunction (float NdotL, float NdotV, float roughness){
            float roughnessSqr = roughness*roughness;
            float NdotLSqr = NdotL*NdotL;
            float NdotVSqr = NdotV*NdotV;


            float calulationL = (NdotL)/(roughnessSqr * sqrt(1- NdotLSqr));
            float calulationV = (NdotV)/(roughnessSqr * sqrt(1- NdotVSqr));


            float SmithL = calulationL < 1.6 ? (((3.535 * calulationL)
                + (2.181 * calulationL * calulationL))/(1 + (2.276 * calulationL) + 
                    (2.577 * calulationL * calulationL))) : 1.0;
            float SmithV = calulationV < 1.6 ? (((3.535 * calulationV) 
                + (2.181 * calulationV * calulationV))/(1 + (2.276 * calulationV) +
                    (2.577 * calulationV * calulationV))) : 1.0;


            float Gs =  (SmithL * SmithV);
            return Gs;
        }

        float GGXGeometricShadowingFunction (float NdotL, float NdotV, float roughness){
            float roughnessSqr = roughness*roughness;
            float NdotLSqr = NdotL*NdotL;
            float NdotVSqr = NdotV*NdotV;


            float SmithL = (2 * NdotL)/ (NdotL + sqrt(roughnessSqr +
                ( 1-roughnessSqr) * NdotLSqr));
            float SmithV = (2 * NdotV)/ (NdotV + sqrt(roughnessSqr + 
                ( 1-roughnessSqr) * NdotVSqr));


            float Gs =  (SmithL * SmithV);
            return Gs;
        }

        float SchlickGeometricShadowingFunction (float NdotL, float NdotV, float roughness)
        {
            float roughnessSqr = roughness*roughness;


            float SmithL = (NdotL)/(NdotL * (1-roughnessSqr) + roughnessSqr);
            float SmithV = (NdotV)/(NdotV * (1-roughnessSqr) + roughnessSqr);


            return (SmithL * SmithV); 
        }

        float SchlickBeckmanGeometricShadowingFunction (float NdotL, float NdotV,
            float roughness){
            float roughnessSqr = roughness*roughness;
            float k = roughnessSqr * 0.797884560802865;


            float SmithL = (NdotL)/ (NdotL * (1- k) + k);
            float SmithV = (NdotV)/ (NdotV * (1- k) + k);


            float Gs =  (SmithL * SmithV);
            return Gs;
        }

        float SchlickGGXGeometricShadowingFunction (float NdotL, float NdotV, float roughness){
            float k = roughness / 2;


            float SmithL = (NdotL)/ (NdotL * (1- k) + k);
            float SmithV = (NdotV)/ (NdotV * (1- k) + k);


            float Gs =  (SmithL * SmithV);
            return Gs;
        }


        float MixFunction(float i, float j, float x) {
            return  j * x + i * (1.0 - x);
        }

        float SchlickFresnel(float i){
            float x = clamp(1.0-i, 0.0, 1.0);
            float x2 = x*x;
            return x2*x2*x;
        }

        //normal incidence reflection calculation
        float F0 (float NdotL, float NdotV, float LdotH, float roughness){
            float FresnelLight = SchlickFresnel(NdotL); 
            float FresnelView = SchlickFresnel(NdotV);
            float FresnelDiffuse90 = 0.5 + 2.0 * LdotH*LdotH * roughness;
            return  MixFunction(1, FresnelDiffuse90, FresnelLight) * MixFunction(1, FresnelDiffuse90, FresnelView);
        }

        float3 SchlickFresnelFunction(float3 SpecularColor,float LdotH){
            return SpecularColor + (1 - SpecularColor)* SchlickFresnel(LdotH);
        }

        float SchlickIORFresnelFunction(float ior ,float LdotH){
            float f0 = pow(ior-1,2)/pow(ior+1, 2);
            return f0 + (1-f0) * SchlickFresnel(LdotH);
        }

        float SphericalGaussianFresnelFunction(float LdotH,float SpecularColor)
        {	
            float power = ((-5.55473 * LdotH) - 6.98316) * LdotH;
            return SpecularColor + (1 - SpecularColor) * pow(2,power);
        }

        UnityGI GetUnityGI(float3 lightColor, float3 lightDirection, float3 normalDirection,float3 viewDirection, 
            float3 viewReflectDirection, float attenuation, float roughness, float3 worldPos){
            //Unity light Setup ::
            UnityLight light;
            light.color = lightColor;
            light.dir = lightDirection;
            light.ndotl = max(0.0h,dot( normalDirection, lightDirection));
            UnityGIInput d;
            d.light = light;
            d.worldPos = worldPos;
            d.worldViewDir = viewDirection;
            d.atten = attenuation;
            d.ambient = 0.0h;
            d.boxMax[0] = unity_SpecCube0_BoxMax;
            d.boxMin[0] = unity_SpecCube0_BoxMin;
            d.probePosition[0] = unity_SpecCube0_ProbePosition;
            d.probeHDR[0] = unity_SpecCube0_HDR;
            d.boxMax[1] = unity_SpecCube1_BoxMax;
            d.boxMin[1] = unity_SpecCube1_BoxMin;
            d.probePosition[1] = unity_SpecCube1_ProbePosition;
            d.probeHDR[1] = unity_SpecCube1_HDR;
            Unity_GlossyEnvironmentData ugls_en_data;
            ugls_en_data.roughness = roughness;
            ugls_en_data.reflUVW = viewReflectDirection;
            UnityGI gi = UnityGlobalIllumination(d, 1.0h, normalDirection, ugls_en_data );
            return gi;
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
            float GeometricShadow = 1;
            float3 FresnelFunction = 1;

            //the algorithm implementations will go here
            //SpecularDistribution *=  BlinnPhongNormalDistribution(NdotH, _Glossiness,  max(1,_Glossiness * 40));
            //SpecularDistribution *=  PhongNormalDistribution(RdotV, _Glossiness, max(1,_Glossiness * 40));
            //SpecularDistribution *=  BeckmannNormalDistribution(roughness, NdotH);
            //SpecularDistribution *=  GaussianNormalDistribution(roughness, NdotH);
            SpecularDistribution *=  GGXNormalDistribution(roughness, NdotH);
            //SpecularDistribution *=  TrowbridgeReitzNormalDistribution(NdotH, roughness);
            //SpecularDistribution *=  TrowbridgeReitzAnisotropicNormalDistribution(_Anisotropic,NdotH, 
            //    dot(halfDirection, i.tangentDir), 
            //    dot(halfDirection,  i.bitangentDir));
            //SpecularDistribution *=  WardAnisotropicNormalDistribution(_Anisotropic,NdotL, NdotV, NdotH, 
            //    dot(halfDirection, i.tangentDir), 
            //    dot(halfDirection,  i.bitangentDir));


            //GeometricShadow *= ImplicitGeometricShadowingFunction (NdotL, NdotV);
            //GeometricShadow *= AshikhminShirleyGSF (NdotL, NdotV, LdotH);
            //GeometricShadow *= AshikhminPremozeGeometricShadowingFunction (NdotL, NdotV);
            //GeometricShadow *= CookTorrenceGeometricShadowingFunction (NdotL, NdotV, VdotH, NdotH);
            GeometricShadow *= SchlickGGXGeometricShadowingFunction (NdotL, NdotV, roughness);


            FresnelFunction *=  SchlickFresnelFunction(specColor, LdotH);
            //FresnelFunction *=  SchlickIORFresnelFunction(_Ior, LdotH);
            //FresnelFunction *= SphericalGaussianFresnelFunction(LdotH, specColor);

            //return float4(float3(1,1,1) * SpecularDistribution.rgb,1);
            //return float4(float3(1,1,1) * GeometricShadow,1);
            float3 specularity = (SpecularDistribution * FresnelFunction * GeometricShadow) / (4 * (  NdotL * NdotV));

            UnityGI gi =  GetUnityGI(_LightColor0.rgb, lightDirection, 
                normalDirection, viewDirection, viewReflectDirection, attenuation, 1- _Glossiness, i.posWorld.xyz);

            float3 indirectDiffuse = gi.indirect.diffuse.rgb ;
            float3 indirectSpecular = gi.indirect.specular.rgb;

            float grazingTerm = saturate(roughness + _Metallic);
            float3 unityIndirectSpecularity =  indirectSpecular * FresnelLerp(specColor,grazingTerm,NdotV) * 
                max(0.15,_Metallic) * (1-roughness*roughness* roughness);

            //float3 lightingModel = (diffuseColor + specularity 
            //    + (unityIndirectSpecularity *_UnityLightingContribution));

            float3 lightingModel = (diffuseColor + specularity);
            lightingModel *= NdotL;

            float3 indirect = saturate(indirectDiffuse + unityIndirectSpecularity);

            lightingModel += indirect;

            float4 finalDiffuse = float4(lightingModel * attenColor,1);


            return finalDiffuse;
        }
        ENDCG
       }
    }

    FallBack "Legacy Shaders/Diffuse"
}