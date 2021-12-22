using System;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class DualKawaseBloom : ScriptableRendererFeature
{
    [SerializeField]
    BloomSetting setting;
    
    [Serializable]
    public class BloomSetting
    {
        [Range(0f, 10f)]
        public float threshold = 1f;
        [Range(1,9)]
        public int iteration = 3;
        [Range(-1f, 10.0f)]
        public float blurRadius;
        [Range(0f, 32f)]
        public float intensity;
    }
    
    class CustomRenderPass : ScriptableRenderPass
    {
        readonly GraphicsFormat m_DefaultHDRFormat;
        bool m_UseRGBM;
        public static int[] _BloomMipUp;
        public static int[] _BloomMipDown;
        const int k_MaxPyramidSize = 10;
        private Material bloomMat;
        private DualKawaseBloom bloom;
        
        public CustomRenderPass(DualKawaseBloom dualKawaseBloom)
        {
            bloom = dualKawaseBloom;
            
            Shader shader = Shader.Find("Hidden/PostEffect/DualKawaseBloom");
            bloomMat = new Material(shader);
            
            // Texture format pre-lookup
            if (SystemInfo.IsFormatSupported(GraphicsFormat.B10G11R11_UFloatPack32, FormatUsage.Linear | FormatUsage.Render))
            {
                m_DefaultHDRFormat = GraphicsFormat.B10G11R11_UFloatPack32;
                m_UseRGBM = false;
            }
            else
            {
                m_DefaultHDRFormat = QualitySettings.activeColorSpace == ColorSpace.Linear
                    ? GraphicsFormat.R8G8B8A8_SRGB
                    : GraphicsFormat.R8G8B8A8_UNorm;
                m_UseRGBM = true;
            }
            CoreUtils.SetKeyword(bloomMat, ShaderKeywordStrings.UseRGBM, m_UseRGBM);
            
            _BloomMipUp = new int[k_MaxPyramidSize];
            _BloomMipDown = new int[k_MaxPyramidSize];

            for (int i = 0; i < k_MaxPyramidSize; i++)
            {
                _BloomMipUp[i] = Shader.PropertyToID("_BloomMipUp" + i);
                _BloomMipDown[i] = Shader.PropertyToID("_BloomMipDown" + i);
            }

            UpdateMaterial();
        }

        public void UpdateMaterial()
        {
            bloomMat.SetFloat(Threshold, Mathf.GammaToLinearSpace(bloom.setting.threshold));
            bloomMat.SetFloat(Offset, bloom.setting.blurRadius);
            bloomMat.SetFloat(Intensity, bloom.setting.intensity);
        }
        
        // This method is called before executing the render pass.
        // It can be used to configure render targets and their clear state. Also to create temporary render target textures.
        // When empty this render pass will render to the active camera render target.
        // You should never call CommandBuffer.SetRenderTarget. Instead call <c>ConfigureTarget</c> and <c>ConfigureClear</c>.
        // The render pipeline will ensure target setup and clearing happens in a performant manner.
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var sourceTargetDescriptor = renderingData.cameraData.cameraTargetDescriptor;
            int width = sourceTargetDescriptor.width >> 1;
            int height = sourceTargetDescriptor.height >> 1;
            var desc = GetCompatibleDescriptor(sourceTargetDescriptor, 
                width, height, m_DefaultHDRFormat);
            cmd.GetTemporaryRT(_BloomMipDown[0], desc, FilterMode.Bilinear);
            // cmd.GetTemporaryRT(_BloomMipUp[0], desc, FilterMode.Bilinear);
        }
        
        RenderTextureDescriptor GetCompatibleDescriptor(RenderTextureDescriptor sourceTargetDescriptor, 
            int width, int height, GraphicsFormat format, int depthBufferBits = 0)
        {
            var desc = sourceTargetDescriptor;
            desc.depthBufferBits = depthBufferBits;
            desc.msaaSamples = 1;
            desc.width = width;
            desc.height = height;
            desc.graphicsFormat = format;
            return desc;
        }

        // Here you can implement the rendering logic.
        // Use <c>ScriptableRenderContext</c> to issue drawing commands or execute command buffers
        // https://docs.unity3d.com/ScriptReference/Rendering.ScriptableRenderContext.html
        // You don't have to call ScriptableRenderContext.submit, the render pipeline will call it at specific points in the pipeline.
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get("DualKawaseBloom");
            cmd.Clear();
            
            cmd.Blit( renderingData.cameraData.renderer.cameraColorTarget, 
                _BloomMipDown[0], bloomMat, 0);
            
            var sourceTargetDescriptor = renderingData.cameraData.cameraTargetDescriptor;
            int width = sourceTargetDescriptor.width >> 1;
            int height = sourceTargetDescriptor.height >> 1;
            int lastDown = _BloomMipDown[0];
            for (int i = 1; i < bloom.setting.iteration; i++)
            {
                int mipDown = _BloomMipDown[i];
                width = Mathf.Max(1, width >> 1);
                height = Mathf.Max(1, height >> 1);
                var desc = GetCompatibleDescriptor(sourceTargetDescriptor, 
                    width, height, m_DefaultHDRFormat);
                cmd.GetTemporaryRT(mipDown, desc, FilterMode.Bilinear);
                cmd.SetGlobalTexture("_SourceTex", lastDown);
                cmd.Blit(lastDown, mipDown, bloomMat, 1);
                lastDown = mipDown;
            }

            for (int i = bloom.setting.iteration - 1; i >= 0; i--)
            {
                int mipUp = _BloomMipUp[i];
                var desc = GetCompatibleDescriptor(sourceTargetDescriptor, 
                    width, height, m_DefaultHDRFormat);
                cmd.GetTemporaryRT(mipUp, desc, FilterMode.Bilinear);
                cmd.SetGlobalTexture("_SourceTex", lastDown);
                cmd.Blit(lastDown, 
                    BlitDstDiscardContent(cmd,mipUp), bloomMat, 2);
                width = Mathf.Max(1, width << 1);
                height = Mathf.Max(1, height << 1);
                lastDown = mipUp;
            }
            cmd.SetGlobalTexture("_SourceTex", lastDown);
            cmd.SetGlobalTexture("_BaseTex", renderingData.cameraData.renderer.cameraColorTarget);
            cmd.SetViewProjectionMatrices(Matrix4x4.identity, Matrix4x4.identity);
            cmd.SetRenderTarget(renderingData.cameraData.renderer.cameraColorTarget);
            cmd.DrawMesh(RenderingUtils.fullscreenMesh, Matrix4x4.identity, bloomMat, 0, 3);
            cmd.SetViewProjectionMatrices(renderingData.cameraData.camera.worldToCameraMatrix,
                renderingData.cameraData.camera.projectionMatrix);
            
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
        
        private BuiltinRenderTextureType BlitDstDiscardContent(CommandBuffer cmd, RenderTargetIdentifier rt)
        {
            // We set depth to DontCare because rt might be the source of PostProcessing used as a temporary target
            // Source typically comes with a depth buffer and right now we don't have a way to only bind the color attachment of a RenderTargetIdentifier
            cmd.SetRenderTarget(new RenderTargetIdentifier(rt, 0, CubemapFace.Unknown, -1),
                RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store,
                RenderBufferLoadAction.DontCare, RenderBufferStoreAction.DontCare);
            return BuiltinRenderTextureType.CurrentActive;
        }

        // Cleanup any allocated resources that were created during the execution of this render pass.
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            for (int i = 0; i < bloom.setting.iteration; i++)
            {
                cmd.ReleaseTemporaryRT(_BloomMipDown[i]);
                cmd.ReleaseTemporaryRT(_BloomMipUp[i]);
            }
            // cmd.ReleaseTemporaryRT(_BloomMipDown[bloom.setting.iteration]);
        }
    }

    CustomRenderPass m_ScriptablePass;
    private static readonly int Threshold = Shader.PropertyToID("_Threshold");
    private static readonly int Offset = Shader.PropertyToID("_Offset");
    private static readonly int Intensity = Shader.PropertyToID("_Intensity");

    /// <inheritdoc/>
    public override void Create()
    {
        m_ScriptablePass = new CustomRenderPass(this);

        // Configures where the render pass should be injected.
        m_ScriptablePass.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
    }

    // Here you can inject one or multiple render passes in the renderer.
    // This method is called when setting up the renderer once per-camera.
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(m_ScriptablePass);
    }
}


