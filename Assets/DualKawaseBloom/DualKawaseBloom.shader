Shader "Hidden/PostEffect/DualKawaseBloom"
{
	HLSLINCLUDE
	#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
    
    struct AttributesDefault
    {
        float3 vertex : POSITION;
    };

    struct v2f_PreFilter
    {
        float4 vertex: SV_POSITION;
    };

	float4 _SourceTex_TexelSize;
	TEXTURE2D(_SourceTex);
	SAMPLER(sampler_LinearClamp);
    float _Threshold;
    
    v2f_PreFilter Vert_PreFilter(AttributesDefault v) {
        v2f_PreFilter o = (v2f_PreFilter)0;
        o.vertex = TransformWorldToHClip(v.vertex);
        return o;
    }
    
    half4 Frag_PreFilter(v2f_PreFilter v) : SV_Target {
        float2 uv = v.vertex.xy / (_SourceTex_TexelSize.zw * 0.5);
        half4 color = _SourceTex.SampleLevel(sampler_LinearClamp, uv, 0);
        
        float br = max(max(color.r, color.g), color.b);
        br = max(0.0f, br - _Threshold) / max(br, 1e-5);
        color.rgb *= br;
        color = max(color, 0);
        return color;
    }
    ENDHLSL
    
    SubShader
    {
        Cull Off ZWrite Off ZTest Always
        Pass
        {
            HLSLPROGRAM
            
            #pragma vertex Vert_PreFilter
			#pragma fragment Frag_PreFilter
            
            ENDHLSL
        }
    }
}
