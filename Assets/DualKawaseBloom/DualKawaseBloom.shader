Shader "Hidden/PostEffect/DualKawaseBloom"
{
	HLSLINCLUDE
	#pragma multi_compile_local _ _USE_RGBM
	#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
	#include "Packages/com.unity.render-pipelines.universal/Shaders/PostProcessing/Common.hlsl"
    
    struct AttributesDefault
    {
        float3 vertex : POSITION;
		float2 texcoord: TEXCOORD0;
    };

    struct v2f_PreFilter
    {
        float4 vertex: SV_POSITION;
    	float2 uv: TEXCOORD0;
    	float4 uv01: TEXCOORD1;
		float4 uv23: TEXCOORD2;
    };

	struct v2f_DownSample
	{
		float4 vertex: SV_POSITION;
		float2 uv: TEXCOORD0;
		float4 uv01: TEXCOORD1;
		float4 uv23: TEXCOORD2;
	};
	
	
	struct v2f_UpSample
	{
		float4 vertex: SV_POSITION;
		float4 uv01: TEXCOORD0;
		float4 uv23: TEXCOORD1;
		float4 uv45: TEXCOORD2;
		float4 uv67: TEXCOORD3;
	};

	struct v2f_Combine
	{
		float4 vertex: SV_POSITION;
		float2 uv: TEXCOORD0;
	};

	TEXTURE2D(_SourceTex);
	TEXTURE2D(_BaseTex);
	float4 _SourceTex_TexelSize;
	// SAMPLER(sampler_LinearClamp);
    float _Threshold;
	half _Offset;
	float _Intensity;

	half4 EncodeHDR(half3 color)
    {
    #if _USE_RGBM
        half4 outColor = EncodeRGBM(color);
    #else
        half4 outColor = half4(color, 1.0);
    #endif

    #if UNITY_COLORSPACE_GAMMA
        return half4(sqrt(outColor.xyz), outColor.w); // linear to γ
    #else
        return outColor;
    #endif
    }

	 half3 DecodeHDR(half4 color)
    {
    #if UNITY_COLORSPACE_GAMMA
        color.xyz *= color.xyz; // γ to linear
    #endif

    #if _USE_RGBM
        return DecodeRGBM(color);
    #else
        return color.xyz;
    #endif
    }
    
    v2f_PreFilter Vert_PreFilter(AttributesDefault v) {
        v2f_PreFilter o = (v2f_PreFilter)0;
        o.vertex = TransformWorldToHClip(v.vertex);
		
		float2 uv = v.texcoord;
		_SourceTex_TexelSize *= 0.5;
		o.uv = uv;
		o.uv01.xy = uv - _SourceTex_TexelSize.xy * float2(1.0 + _Offset, 1.0 + _Offset);//top right
		o.uv01.zw = uv + _SourceTex_TexelSize.xy * float2(1.0 + _Offset, 1.0 + _Offset);//bottom left
		o.uv23.xy = uv - float2(_SourceTex_TexelSize.x, -_SourceTex_TexelSize.y) * float2(1.0 + _Offset, 1.0 + _Offset);//top left
		o.uv23.zw = uv + float2(_SourceTex_TexelSize.x, -_SourceTex_TexelSize.y) * float2(1.0 + _Offset, 1.0 + _Offset);//bottom right
        return o;
    }

	v2f_Combine Vert_Combine(AttributesDefault v)
	{
		v2f_Combine o = (v2f_Combine)0;
        o.vertex = TransformWorldToHClip(v.vertex);
    	o.uv = v.texcoord;
        return o;
	}
    
    half4 Frag_PreFilter(v2f_PreFilter v) : SV_Target {
        // float2 uv = v.vertex.xy / (_SourceTex_TexelSize.zw);
    	// float2 uv = v.texcoord;
    	UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
    	// float2 uv = UnityStereoTransformScreenSpaceTex(v.uv);

    	half3 sum = DecodeHDR(SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, v.uv)) * 4;
		sum += DecodeHDR(SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, v.uv01.xy));
		sum += DecodeHDR(SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, v.uv01.zw));
		sum += DecodeHDR(SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, v.uv23.xy));
		sum += DecodeHDR(SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, v.uv23.zw));
    	half3 color = sum * 0.125;
    	
    	// half3 color = SAMPLE_TEXTURE2D_X(_SourceTex, sampler_LinearClamp, uv).xyz;
        // half4 color = _SourceTex.SampleLevel(sampler_LinearClamp, uv, 0);
        color = min(65472.0, color);
        // float br = max(max(color.r, color.g), color.b);
        // br = max(0.0f, br - _Threshold) / max(br, 1e-5);
        // color.rgb *= br;
    	float ThresholdKnee = _Threshold * 0.5;
		half brightness = Max3(color.r, color.g, color.b);
        half softness = clamp(brightness - _Threshold + ThresholdKnee, 0.0, 2.0 * ThresholdKnee);
        softness = (softness * softness) / (4.0 * ThresholdKnee + 1e-4);
        half multiplier = max(brightness - _Threshold, softness) / max(brightness, 1e-4);
        color *= multiplier;
    	color = max(color, 0);
        return EncodeHDR(color);
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
		
		// #if UNITY_UV_STARTS_AT_TOP
		// 	o.texcoord = o.texcoord * float2(1.0, -1.0) + float2(0.0, 1.0);
		// #endif
		float2 uv = v.texcoord;
		
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
		half3 sum = DecodeHDR(SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.uv)) * 4;
		sum += DecodeHDR(SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.uv01.xy));
		sum += DecodeHDR(SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.uv01.zw));
		sum += DecodeHDR(SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.uv23.xy));
		sum += DecodeHDR(SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.uv23.zw));

		return EncodeHDR(sum * 0.125);
	}
	
	
	v2f_UpSample Vert_UpSample(AttributesDefault v)
	{
		v2f_UpSample o;
		// o.vertex = float4(v.vertex.xy, 0.0, 1.0);
		// o.texcoord = TransformTriangleVertexToUV(v.vertex.xy);
    	o.vertex = TransformWorldToHClip(v.vertex);
		
		// #if UNITY_UV_STARTS_AT_TOP
		// 	o.texcoord = o.texcoord * float2(1.0, -1.0) + float2(0.0, 1.0);
		// #endif
		float2 uv = v.texcoord;
		
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
		half3 sum = 0;
		sum += DecodeHDR(SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.uv01.xy));
		sum += DecodeHDR(SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.uv01.zw)) * 2;
		sum += DecodeHDR(SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.uv23.xy));
		sum += DecodeHDR(SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.uv23.zw)) * 2;
		sum += DecodeHDR(SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.uv45.xy));
		sum += DecodeHDR(SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.uv45.zw)) * 2;
		sum += DecodeHDR(SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.uv67.xy));
		sum += DecodeHDR(SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.uv67.zw)) * 2;
		
		return EncodeHDR(sum * 0.0833);
	}

	half4 Frag_Combine(v2f_Combine i): SV_Target
	{
		half3 baseColor = DecodeHDR(SAMPLE_TEXTURE2D(_BaseTex, sampler_LinearClamp, i.uv));
		half3 bloomColor = DecodeHDR(SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.uv));
		half3 finalColor = baseColor.rgb + bloomColor.rgb * _Intensity;
		return EncodeHDR(finalColor);
	}
	
    ENDHLSL
    
    SubShader
    {
        Cull Off ZWrite Off ZTest Always
        Pass
        {
            HLSLPROGRAM
            
            #pragma vertex FullscreenVert
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
    	
    	Pass {
    		HLSLPROGRAM
    		#pragma vertex Vert_Combine
			#pragma fragment Frag_Combine
    		ENDHLSL
        }
    }
}
