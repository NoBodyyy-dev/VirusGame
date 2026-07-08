using UnityEngine;
using TMPro;
using Virus.Core;

namespace Virus.UI
{
    // Порт grid_hud.gd: экранный HUD на uGUI + TextMeshPro (overlay-канвас).
    public class Hud : MonoBehaviour
    {
        TMP_Text _prompt, _res, _progress;

        void Awake()
        {
            var canvasGo = new GameObject("HudCanvas", typeof(Canvas), typeof(UnityEngine.UI.CanvasScaler));
            var canvas = canvasGo.GetComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            var scaler = canvasGo.GetComponent<UnityEngine.UI.CanvasScaler>();
            scaler.uiScaleMode = UnityEngine.UI.CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1600, 900);

            _res      = MakeText(canvasGo.transform, new Vector2(24, 24),  TextAlignmentOptions.BottomLeft, 20);
            _progress = MakeText(canvasGo.transform, new Vector2(24, -24), TextAlignmentOptions.TopLeft, 20);
            _prompt   = MakeText(canvasGo.transform, new Vector2(0, 120),  TextAlignmentOptions.Bottom, 24);
            _prompt.rectTransform.anchorMin = _prompt.rectTransform.anchorMax = new Vector2(0.5f, 0f);
        }

        static TMP_Text MakeText(Transform parent, Vector2 offset, TextAlignmentOptions align, float size)
        {
            var go = new GameObject("txt", typeof(RectTransform));
            go.transform.SetParent(parent, false);
            var t = go.AddComponent<TextMeshProUGUI>();
            t.fontSize = size; t.alignment = align; t.color = new Color(0.88f, 0.95f, 1f);
            t.rectTransform.anchoredPosition = offset;
            t.rectTransform.sizeDelta = new Vector2(1200, 60);
            return t;
        }

        void Update()
        {
            var s = GameState.I;
            if (s == null) return;
            var r = s.resources;
            _res.text = $"◈ Data {r["data_fragments"]}   ◇ Code {r["code_samples"]}   ✦ Mutagen {r["mutagen"]}";
            _progress.text = $"ЗАРАЖЕНИЕ ГРИДА: {s.InfectedTotal()} / {s.TotalNodes()} серверов";
        }

        public void SetPrompt(string text) { if (_prompt != null) _prompt.text = text; }
    }
}
