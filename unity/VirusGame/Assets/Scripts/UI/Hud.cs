using UnityEngine;
using UnityEngine.UI;
using Virus.Core;
using Virus.Util;

namespace Virus.UI
{
    // Порт grid_hud.gd: экранный HUD на uGUI (legacy Text + шрифт ОС, без TMP).
    public class Hud : MonoBehaviour
    {
        Text _prompt, _res, _progress;

        void Awake()
        {
            var canvasGo = new GameObject("HudCanvas", typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
            var canvas = canvasGo.GetComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            var scaler = canvasGo.GetComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1600, 900);

            _res      = MakeText(canvasGo.transform, new Vector2(0, 0),   new Vector2(0, 0), TextAnchor.LowerLeft, 20);
            _progress = MakeText(canvasGo.transform, new Vector2(0, 1),   new Vector2(0, 1), TextAnchor.UpperLeft, 20);
            _prompt   = MakeText(canvasGo.transform, new Vector2(0.5f, 0),new Vector2(0.5f, 0), TextAnchor.LowerCenter, 26);
        }

        static Text MakeText(Transform parent, Vector2 anchorMin, Vector2 anchorMax, TextAnchor align, int size)
        {
            var go = new GameObject("txt", typeof(RectTransform));
            go.transform.SetParent(parent, false);
            var t = go.AddComponent<Text>();
            t.font = Build.UIFont;
            t.fontSize = size;
            t.alignment = align;
            t.color = new Color(0.88f, 0.95f, 1f);
            t.horizontalOverflow = HorizontalWrapMode.Overflow;
            t.verticalOverflow = VerticalWrapMode.Overflow;
            var rt = t.rectTransform;
            rt.anchorMin = anchorMin; rt.anchorMax = anchorMax;
            rt.pivot = new Vector2(anchorMin.x, anchorMin.y);
            rt.anchoredPosition = new Vector2(anchorMin.x == 0.5f ? 0 : 28, align == TextAnchor.UpperLeft ? -28 : 28);
            rt.sizeDelta = new Vector2(1400, 60);
            return t;
        }

        void Update()
        {
            var s = GameState.I;
            if (s == null) return;
            var r = s.resources;
            if (_res != null)
                _res.text = $"Data {r["data_fragments"]}   Code {r["code_samples"]}   Mutagen {r["mutagen"]}";
            if (_progress != null)
                _progress.text = $"ЗАРАЖЕНИЕ ГРИДА: {s.InfectedTotal()} / {s.TotalNodes()} серверов";
        }

        public void SetPrompt(string text) { if (_prompt != null) _prompt.text = text; }
    }
}
