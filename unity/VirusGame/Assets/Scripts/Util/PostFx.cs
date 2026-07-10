using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Virus.Util
{
    // Пост-процессинг URP в духе REPO/RV There Yet: РЕЗКАЯ картинка
    // (никакого FXAA — он мылит, геометрию сглаживает MSAA 4), высокий
    // контраст, плотный чёрный, узкий блюм только на ярких эмиссивах.
    // Без URP тихо выключается.
    public static class PostFx
    {
        public static void AttachCamera(Camera cam)
        {
            if (GraphicsSettings.currentRenderPipeline == null || cam == null) return;
            var data = cam.GetUniversalAdditionalCameraData();
            if (data == null) return;
            data.renderPostProcessing = true;
            data.antialiasing = AntialiasingMode.None;   // резкость: только MSAA
        }

        public static void EnsureVolume()
        {
            if (GraphicsSettings.currentRenderPipeline == null) return;
            if (Object.FindFirstObjectByType<Volume>() != null) return;

            var go = new GameObject("PostFxVolume");
            var vol = go.AddComponent<Volume>();
            vol.isGlobal = true;
            var profile = ScriptableObject.CreateInstance<VolumeProfile>();

            // узкий блюм: только по-настоящему яркие эмиссивы, без «дымки»
            var bloom = profile.Add<Bloom>(true);
            bloom.intensity.value = 0.4f;
            bloom.threshold.value = 1.35f;
            bloom.scatter.value = 0.4f;

            var vig = profile.Add<Vignette>(true);
            vig.intensity.value = 0.16f;
            vig.smoothness.value = 0.5f;

            // контрастный грейдинг: света ярче, тени глубже, цвет живее
            var ca = profile.Add<ColorAdjustments>(true);
            ca.postExposure.value = 0.3f;
            ca.saturation.value = 10f;
            ca.contrast.value = 22f;

            var tone = profile.Add<Tonemapping>(true);
            tone.mode.value = TonemappingMode.ACES;

            vol.profile = profile;
        }
    }
}
