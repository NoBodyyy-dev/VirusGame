using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Virus.Util
{
    // Кинематографичный пост-процессинг URP: bloom заставляет неон светиться,
    // виньетка и ACES дают «плёночную» картинку. Без URP тихо выключается.
    public static class PostFx
    {
        public static void AttachCamera(Camera cam)
        {
            if (GraphicsSettings.currentRenderPipeline == null || cam == null) return;
            var data = cam.GetUniversalAdditionalCameraData();
            if (data == null) return;
            data.renderPostProcessing = true;
            data.antialiasing = AntialiasingMode.FastApproximateAntialiasing;
        }

        public static void EnsureVolume()
        {
            if (GraphicsSettings.currentRenderPipeline == null) return;
            if (Object.FindFirstObjectByType<Volume>() != null) return;

            var go = new GameObject("PostFxVolume");
            var vol = go.AddComponent<Volume>();
            vol.isGlobal = true;
            var profile = ScriptableObject.CreateInstance<VolumeProfile>();

            // мягкий блюм: светятся только по-настоящему яркие эмиссивы,
            // а не каждый светлый пиксель (иначе скины — «снежки»)
            var bloom = profile.Add<Bloom>(true);
            bloom.intensity.value = 0.65f;
            bloom.threshold.value = 1.15f;
            bloom.scatter.value = 0.55f;

            var vig = profile.Add<Vignette>(true);
            vig.intensity.value = 0.22f;
            vig.smoothness.value = 0.42f;

            var ca = profile.Add<ColorAdjustments>(true);
            ca.postExposure.value = 0.12f;
            ca.saturation.value = 4f;
            ca.contrast.value = 4f;

            var tone = profile.Add<Tonemapping>(true);
            tone.mode.value = TonemappingMode.ACES;

            vol.profile = profile;
        }
    }
}
