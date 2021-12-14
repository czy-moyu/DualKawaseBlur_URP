Shader "Hidden/PostEffect/DualKawaseBloom"
{
	HLSLINCLUDE
	#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
    
    struct AttributesDefault
    {
        float3 vertex : POSITION;
		float2 texcoord: TEXCOORD0;
    };

    struct v2f_PreFilter
    {
        float4 vertex: SV_POSITION;
    	float2 texcoord: TEXCOORD0;
    };

	struct v2f_DownSample
	{
		float4 vertex: SV_POSITION;
		float2 texcoord: TEXCOORD0;
		float2 uv: TEXCOORD1;
		float4 uv01: TEXCOORD2;
		float4 uv23: TEXCOORD3;
	};
	
	
	struct v2f_UpSample
	{
		float4 vertex: SV_POSITION;
		float2 texcoord: TEXCOORD0;
		float4 uv01: TEXCOORD1;
		float4 uv23: TEXCOORD2;
		float4 uv45: TEXCOORD3;
		float4 uv67: TEXCOORD4;
	};

	float4 _SourceTex_TexelSize;
	TEXTURE2D(_SourceTex);
	SAMPLER(sampler_LinearClamp);
    float _Threshold;
	half _Offset;
    
    v2f_PreFilter Vert_PreFilter(AttributesDefault v) {
        v2f_PreFilter o = (v2f_PreFilter)0;
        o.vertex = TransformWorldToHClip(v.vertex);
    	o.texcoord = v.texcoord;
        return o;
    }
    
    half4 Frag_PreFilter(v2f_PreFilter v) : SV_Target {
        // float2 uv = v.vertex.xy / (_SourceTex_TexelSize.zw);
    	float2 uv = v.texcoord;
        half4 color = _SourceTex.SampleLevel(sampler_LinearClamp, uv, 0);
        
        float br = max(max(color.r, color.g), color.b);
        br = max(0.0f, br - _Threshold) / max(br, 1e-5);
        color.rgb *= br;
        color = max(color, 0);
        return color;
    }

	float2 TransformTriangleVertexToUV(float2 vertex)
	{
	    float2 uv = (vertex + 1.0) * 0.5;
	    return uv;
	}

	v2f_DownSample Vert_DownSample(AttributesDefault v)
	{
		v2f_DownSample o;
		// o.vertex = float4(v.vertex.xy, 0.0, 1.0);
		// o.texcoord = TransformTriangleVertexToUV(v.vertex.xy);
    	o.vertex = TransformWorldToHClip(v.vertex);
    	o.texcoord = v.texcoord;
		
		// #if UNITY_UV_STARTS_AT_TOP
		// 	o.texcoord = o.texcoord * float2(1.0, -1.0) + float2(0.0, 1.0);
		// #endif
		float2 uv = o.texcoord;
		
		_SourceTex_TexelSize *= 0.5;
		o.uv = uv;
		o.uv01.xy = uv - _SourceTex_TexelSize.xy * float2(1.0 + _Offset, 1.0 + _Offset);//top right
		o.uv01.zw = uv + _SourceTex_TexelSize.xy * float2(1.0 + _Offset, 1.0 + _Offset);//bottom left
		o.uv23.xy = uv - float2(_SourceTex_TexelSize.x, -_SourceTex_TexelSize.y) * float2(1.0 + _Offset, 1.0 + _Offset);//top left
		o.uv23.zw = uv + float2(_SourceTex_TexelSize.x, -_SourceTex_TexelSize.y) * float2(1.0 + _Offset, 1.0 + _Offset);//bottom right
		
		return o;
	}
	
	half4 Frag_DownSample(v2f_DownSample i): SV_Target
	{
		half4 sum = SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.uv) * 4;
		sum += SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.uv01.xy);
		sum += SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.uv01.zw);
		sum += SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.uv23.xy);
		sum += SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.uv23.zw);

		return sum * 0.125;
	}
	
	
	v2f_UpSample Vert_UpSample(AttributesDefault v)
	{
		v2f_UpSample o;
		// o.vertex = float4(v.vertex.xy, 0.0, 1.0);
		// o.texcoord = TransformTriangleVertexToUV(v.vertex.xy);
    	o.vertex = TransformWorldToHClip(v.vertex);
    	o.texcoord = v.texcoord;
		
		// #if UNITY_UV_STARTS_AT_TOP
		// 	o.texcoord = o.texcoord * float2(1.0, -1.0) + float2(0.0, 1.0);
		// #endif
		float2 uv = o.texcoord;
		
		_SourceTex_TexelSize *= 0.5;
		_Offset = float2(1.0 + _Offset, 1.0 + _Offset).x;
		
		o.uv01.xy = uv + float2(-_SourceTex_TexelSize.x * 2, 0) * _Offset;
		o.uv01.zw = uv + float2(-_SourceTex_TexelSize.x, _SourceTex_TexelSize.y) * _Offset;
		o.uv23.xy = uv + float2(0, _SourceTex_TexelSize.y * 2) * _Offset;
		o.uv23.zw = uv + _SourceTex_TexelSize.xy * _Offset;
		o.uv45.xy = uv + float2(_SourceTex_TexelSize.x * 2, 0) * _Offset;
		o.uv45.zw = uv + float2(_SourceTex_TexelSize.x, -_SourceTex_TexelSize.y) * _Offset;
		o.uv67.xy = uv + float2(0, -_SourceTex_TexelSize.y * 2) * _Offset;
		o.uv67.zw = uv - _SourceTex_TexelSize.xy * _Offset;
		
		return o;
	}
	
	half4 Frag_UpSample(v2f_UpSample i): SV_Target
	{
		half4 sum = 0;
		sum += SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.uv01.xy);
		sum += SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.uv01.zw) * 2;
		sum += SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.uv23.xy);
		sum += SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.uv23.zw) * 2;
		sum += SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.uv45.xy);
		sum += SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.uv45.zw) * 2;
		sum += SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.uv67.xy);
		sum += SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.uv67.zw) * 2;
		
		return sum * 0.0833;
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
    	
    	Pass
		{
			HLSLPROGRAM
			
			#pragma vertex Vert_DownSample
			#pragma fragment Frag_DownSample
			
			ENDHLSL
			
		}
		
		Pass
		{
			HLSLPROGRAM
			
			#pragma vertex Vert_UpSample
			#pragma fragment Frag_UpSample
			
			ENDHLSL
			
		}
    }
}
