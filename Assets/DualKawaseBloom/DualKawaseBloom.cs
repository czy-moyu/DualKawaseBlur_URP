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
    }
    
    class CustomRenderPass : ScriptableRenderPass
    {
        readonly GraphicsFormat m_DefaultHDRFormat;
        bool m_UseRGBM;
        public static int[] _BloomMipUp;
        public static int[] _BloomMipDown;
        const int k_MaxPyramidSize = 16;
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
            
            _BloomMipUp = new int[k_MaxPyramidSize];
            _BloomMipDown = new int[k_MaxPyramidSize];

            for (int i = 0; i < k_MaxPyramidSize; i++)
            {
                _BloomMipUp[i] = Shader.PropertyToID("_BloomMipUp" + i);
                _BloomMipDown[i] = Shader.PropertyToID("_BloomMipDown" + i);
            }
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
            cmd.GetTemporaryRT(_BloomMipUp[0], desc, FilterMode.Bilinear);
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
            bloomMat.SetFloat(Threshold, bloom.setting.threshold);
            cmd.Blit( renderingData.cameraData.renderer.cameraColorTarget, 
                _BloomMipDown[0], bloomMat, 0);
            cmd.Blit(_BloomMipDown[0], renderingData.cameraData.renderer.cameraColorTarget);
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        // Cleanup any allocated resources that were created during the execution of this render pass.
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            cmd.ReleaseTemporaryRT(_BloomMipDown[0]);
            cmd.ReleaseTemporaryRT(_BloomMipUp[0]);
        }
    }

    CustomRenderPass m_ScriptablePass;
    private static readonly int Threshold = Shader.PropertyToID("_Threshold");

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


