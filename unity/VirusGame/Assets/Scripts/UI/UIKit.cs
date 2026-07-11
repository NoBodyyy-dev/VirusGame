using UnityEngine;
using UnityEngine.UI;
using Virus.Util;

namespace Virus.UI
{
    // Единый UI-кит: скруглённые панели (процедурный 9-slice спрайт),
    // полосы-заполнители, чипы-подписи, пипсы HP. Без внешних ассетов.
    public static class UIKit
    {
        // ── палитра ──
        public static readonly Color PanelBg = new(0.04f, 0.07f, 0.11f, 0.82f);
        public static readonly Color PanelBg2 = new(0.03f, 0.05f, 0.08f, 0.92f);
        public static readonly Color BarBack = new(0.10f, 0.13f, 0.18f, 0.9f);
        public static readonly Color TextMain = new(0.88f, 0.95f, 1f);
        public static readonly Color TextDim = new(0.55f, 0.65f, 0.75f);
        public static readonly Color Accent = new(0.21f, 0.85f, 1f);
        public static readonly Color Good = new(0.16f, 0.95f, 0.75f);
        public static readonly Color Warn = new(1f, 0.72f, 0.25f);
        public static readonly Color Bad = new(1f, 0.32f, 0.42f);

        // ── скруглённый 9-slice спрайт (генерируется один раз) ──
        static Sprite _rounded;
        public static Sprite Rounded
        {
            get
            {
                if (_rounded != null) return _rounded;
                const int N = 40, R2 = 14;
                var tex = new Texture2D(N, N, TextureFormat.RGBA32, false) { wrapMode = TextureWrapMode.Clamp };
                var px = new Color[N * N];
                for (int y = 0; y < N; y++)
                    for (int x = 0; x < N; x++)
                    {
                        // расстояние до ближайшего углового центра (мягкая кромка 1.5px)
                        float cx = Mathf.Clamp(x + 0.5f, R2, N - R2);
                        float cy = Mathf.Clamp(y + 0.5f, R2, N - R2);
                        float d = Mathf.Sqrt((x + 0.5f - cx) * (x + 0.5f - cx) + (y + 0.5f - cy) * (y + 0.5f - cy));
                        float a = Mathf.Clamp01((R2 - d) / 1.5f + 1f);
                        px[y * N + x] = new Color(1f, 1f, 1f, a);
                    }
                tex.SetPixels(px);
                tex.Apply();
                _rounded = Sprite.Create(tex, new Rect(0, 0, N, N), new Vector2(0.5f, 0.5f),
                    100f, 0, SpriteMeshType.FullRect, new Vector4(16, 16, 16, 16));
                return _rounded;
            }
        }

        // ── базовые элементы ──
        public static Image Panel(Transform parent, Vector2 anchor, Vector2 pos, Vector2 size, Color c)
        {
            var go = new GameObject("panel", typeof(RectTransform));
            go.transform.SetParent(parent, false);
            var img = go.AddComponent<Image>();
            img.sprite = Rounded;
            img.type = Image.Type.Sliced;
            img.color = c;
            img.raycastTarget = false;
            var rt = img.rectTransform;
            rt.anchorMin = anchor; rt.anchorMax = anchor; rt.pivot = anchor;
            rt.anchoredPosition = pos;
            rt.sizeDelta = size;
            return img;
        }

        public static Text Label(Transform parent, string s, Vector2 anchor, Vector2 pos, int size,
                                 Color c, TextAnchor align = TextAnchor.MiddleLeft, bool bold = false)
        {
            var go = new GameObject("txt", typeof(RectTransform));
            go.transform.SetParent(parent, false);
            var t = go.AddComponent<Text>();
            t.font = Build.UIFont;
            t.text = s;
            t.fontSize = size;
            t.fontStyle = bold ? FontStyle.Bold : FontStyle.Normal;
            t.alignment = align;
            t.color = c;
            t.horizontalOverflow = HorizontalWrapMode.Overflow;
            t.verticalOverflow = VerticalWrapMode.Overflow;
            t.raycastTarget = false;
            var rt = t.rectTransform;
            rt.anchorMin = anchor; rt.anchorMax = anchor; rt.pivot = anchor;
            rt.anchoredPosition = pos;
            rt.sizeDelta = new Vector2(10, 10);
            return t;
        }

        // полоса-заполнитель: тёмная подложка + цветная заливка слева направо
        public class Bar
        {
            public Image back, fill;
            public Text caption, value;
            public float width;

            public void Set(float pct, Color? col = null)
            {
                pct = Mathf.Clamp01(pct);
                fill.rectTransform.sizeDelta = new Vector2(Mathf.Max((width - 6f) * pct, 0.01f), fill.rectTransform.sizeDelta.y);
                if (col.HasValue) fill.color = col.Value;
            }
        }

        public static Bar MakeBar(Transform parent, Vector2 pos, float width, float height,
                                  string caption, Color fillCol)
        {
            var bar = new Bar { width = width };
            bar.back = Panel(parent, new Vector2(0, 1), pos, new Vector2(width, height), BarBack);
            bar.fill = Panel(bar.back.transform, new Vector2(0, 0.5f), new Vector2(3, 0),
                new Vector2(width - 6f, height - 6f), fillCol);
            if (!string.IsNullOrEmpty(caption))
                bar.caption = Label(bar.back.transform, caption, new Vector2(0, 0.5f), new Vector2(8, 0), (int)(height * 0.52f), TextMain, TextAnchor.MiddleLeft, true);
            bar.value = Label(bar.back.transform, "", new Vector2(1, 0.5f), new Vector2(-8, 0), (int)(height * 0.52f), TextMain, TextAnchor.MiddleRight);
            return bar;
        }

        // пипсы HP: ромбы-квадраты, залитые/пустые
        public class Pips
        {
            public readonly System.Collections.Generic.List<Image> items = new();
            public Transform parent;
            public Vector2 pos;

            public void Set(int cur, int max)
            {
                while (items.Count < max)
                {
                    var p = Panel(parent, new Vector2(0, 1), pos + new Vector2(items.Count * 22f, 0), new Vector2(16, 16), Bad);
                    p.transform.localRotation = Quaternion.Euler(0, 0, 45);
                    items.Add(p);
                }
                for (int i = 0; i < items.Count; i++)
                {
                    items[i].gameObject.SetActive(i < max);
                    items[i].color = i < cur ? Bad : new Color(0.25f, 0.16f, 0.2f, 0.85f);
                }
            }
        }

        public static Pips MakePips(Transform parent, Vector2 pos) => new() { parent = parent, pos = pos };

        // чип: скруглённая плашка с текстом, авто-скрытие при пустой строке
        public class Chip
        {
            public Image bg;
            public Text text;

            public void Set(string s)
            {
                bool on = !string.IsNullOrEmpty(s);
                if (bg.gameObject.activeSelf != on) bg.gameObject.SetActive(on);
                if (on && text.text != s)
                {
                    text.text = s;
                    // ширина по содержимому (грубая оценка: 0.52 ширины кегля на символ)
                    float w = Mathf.Max(s.Length * text.fontSize * 0.52f + 36f, 60f);
                    bg.rectTransform.sizeDelta = new Vector2(w, bg.rectTransform.sizeDelta.y);
                }
            }
        }

        public static Chip MakeChip(Transform parent, Vector2 anchor, Vector2 pos, float height,
                                    int fontSize, Color textCol, Color? bgCol = null)
        {
            var chip = new Chip();
            chip.bg = Panel(parent, anchor, pos, new Vector2(120, height), bgCol ?? PanelBg);
            chip.text = Label(chip.bg.transform, "", new Vector2(0.5f, 0.5f), Vector2.zero, fontSize, textCol, TextAnchor.MiddleCenter);
            chip.bg.gameObject.SetActive(false);
            return chip;
        }

        // кнопка меню: скруглённая, с реакцией на наведение
        public static Button MakeButton(Transform parent, string label, Vector2 pos, Vector2 size,
                                        UnityEngine.Events.UnityAction action, Color? accent = null)
        {
            var go = new GameObject("btn", typeof(RectTransform));
            go.transform.SetParent(parent, false);
            var img = go.AddComponent<Image>();
            img.sprite = Rounded;
            img.type = Image.Type.Sliced;
            img.color = PanelBg2;
            var rt = img.rectTransform;
            rt.anchorMin = new Vector2(0.5f, 0.5f); rt.anchorMax = new Vector2(0.5f, 0.5f);
            rt.anchoredPosition = pos;
            rt.sizeDelta = size;
            var btn = go.AddComponent<Button>();
            btn.targetGraphic = img;
            var colors = btn.colors;
            colors.normalColor = Color.white;
            colors.highlightedColor = new Color(1.5f, 1.7f, 1.9f, 1f);
            colors.pressedColor = new Color(0.7f, 0.8f, 0.9f, 1f);
            btn.colors = colors;
            btn.onClick.AddListener(() => Debug.Log($"[UI] button '{label}' pressed"));
            btn.onClick.AddListener(action);
            Label(go.transform, label, new Vector2(0.5f, 0.5f), Vector2.zero, (int)(size.y * 0.42f),
                accent ?? Accent, TextAnchor.MiddleCenter, true);
            return btn;
        }
    }
}
