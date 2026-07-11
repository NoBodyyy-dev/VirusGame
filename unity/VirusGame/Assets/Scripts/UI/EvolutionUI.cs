using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;
using Virus.Core;
using Virus.Util;

namespace Virus.UI
{
    // Порт evolution_ui.gd: дерево эволюции в стиле созвездия — тёмное полотно,
    // орбы-узлы, светящиеся связи, ветки по кругу, панель атрибутов справа.
    // Колесо мыши — зум, наведение — тултип, клик — прокачка/откат. [Tab]/[Esc] — закрыть.
    public class EvolutionUI : MonoBehaviour
    {
        public static bool IsOpen { get; private set; }

        static readonly Color BgTop = new(0.10f, 0.03f, 0.14f);
        static readonly Color BgBottom = new(0.03f, 0.01f, 0.06f);
        static readonly Color EdgeDim = new(0.45f, 0.25f, 0.12f, 0.5f);

        readonly EvolutionTree _tree = new();
        float _zoom = 1f, _t, _openTime;
        int _hoverId = -1;
        GameObject _root;
        TreeGraphic _graphic;
        RectTransform _rect;
        Player.VirusPlayer _player;

        // звёзды фона: нормированные координаты [0..1]
        struct Star { public Vector2 pos; public float r, a, ph; }
        readonly List<Star> _stars = new();

        // текстовые элементы (обновляются каждый кадр)
        readonly List<Text> _glyphs = new();
        readonly List<Text> _branchLabels = new();
        Text _statsValues, _resText, _footer, _hint, _tipTitle, _tipBody;
        Image _tipPanel;

        public static void Toggle()
        {
            if (IsOpen)
            {
                var ui = FindFirstObjectByType<EvolutionUI>();
                if (ui != null) ui.Close();
                return;
            }
            if (PuzzleUI.IsOpen) return;
            new GameObject("EvolutionUI", typeof(EvolutionUI));
        }

        void Awake()
        {
            IsOpen = true;
            _openTime = Time.unscaledTime;
            _tree.Build();
            var rng = new System.Random(7);
            for (int i = 0; i < 90; i++)
                _stars.Add(new Star {
                    pos = new Vector2((float)rng.NextDouble(), (float)rng.NextDouble()),
                    r = Mathf.Lerp(1f, 3.2f, (float)rng.NextDouble()),
                    a = Mathf.Lerp(0.05f, 0.3f, (float)rng.NextDouble()),
                    ph = (float)rng.NextDouble() * Mathf.PI * 2f,
                });

            _player = FindFirstObjectByType<Player.VirusPlayer>();
            if (_player != null) _player.controlEnabled = false;
            Cursor.lockState = CursorLockMode.None;
            Cursor.visible = true;

            BuildCanvas();
        }

        void BuildCanvas()
        {
            _root = new GameObject("EvoCanvas", typeof(Canvas), typeof(CanvasScaler));
            var canvas = _root.GetComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = 70;
            var scaler = _root.GetComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1600, 900);

            var gGo = new GameObject("Tree", typeof(RectTransform));
            gGo.transform.SetParent(_root.transform, false);
            _rect = gGo.GetComponent<RectTransform>();
            _rect.anchorMin = Vector2.zero; _rect.anchorMax = Vector2.one;
            _rect.offsetMin = Vector2.zero; _rect.offsetMax = Vector2.zero;
            _graphic = gGo.AddComponent<TreeGraphic>();
            _graphic.owner = this;
            _graphic.raycastTarget = false;

            // глифы орбов
            foreach (var n in _tree.nodes)
                _glyphs.Add(MakeText("", 14, TextAnchor.MiddleCenter));
            // подписи веток
            foreach (var n in _tree.nodes)
                if (n.kind == TreeNodeKind.Branch) _branchLabels.Add(MakeText("", 19, TextAnchor.MiddleCenter));

            _resText     = MakeText("", 22, TextAnchor.MiddleLeft);
            _statsValues = MakeText("", 24, TextAnchor.UpperRight);
            _footer      = MakeText("", 17, TextAnchor.MiddleRight);
            _hint        = MakeText("", 17, TextAnchor.MiddleLeft);

            // тултип
            var tipGo = new GameObject("tip", typeof(RectTransform));
            tipGo.transform.SetParent(_root.transform, false);
            _tipPanel = tipGo.AddComponent<Image>();
            _tipPanel.sprite = UIKit.Rounded;
            _tipPanel.type = Image.Type.Sliced;
            _tipPanel.color = new Color(0.06f, 0.03f, 0.1f, 0.94f);
            _tipPanel.raycastTarget = false;
            _tipTitle = MakeText("", 19, TextAnchor.UpperLeft, tipGo.transform);
            _tipBody  = MakeText("", 15, TextAnchor.UpperLeft, tipGo.transform);
            _tipTitle.color = new Color(1f, 0.85f, 0.5f);
            _tipBody.color = new Color(0.85f, 0.82f, 0.95f);
            _tipPanel.gameObject.SetActive(false);
        }

        Text MakeText(string s, int size, TextAnchor align, Transform parent = null)
        {
            var go = new GameObject("txt", typeof(RectTransform));
            go.transform.SetParent(parent != null ? parent : _root.transform, false);
            var t = go.AddComponent<Text>();
            t.font = Build.UIFont;
            t.text = s; t.fontSize = size; t.alignment = align;
            t.color = new Color(0.95f, 0.92f, 1f);
            t.horizontalOverflow = HorizontalWrapMode.Overflow;
            t.verticalOverflow = VerticalWrapMode.Overflow;
            t.raycastTarget = false;
            var rt = t.rectTransform;
            rt.anchorMin = new Vector2(0.5f, 0.5f); rt.anchorMax = new Vector2(0.5f, 0.5f);
            rt.sizeDelta = new Vector2(10, 10);
            return t;
        }

        // экранная позиция узла в локальных координатах полотна (центр = 0,0);
        // ось Y дерева Godot смотрит вниз — инвертируем
        public Vector2 NodePos(TreeNode n) => new(n.pos.x * _zoom, -n.pos.y * _zoom);

        Vector2 MouseLocal()
        {
            RectTransformUtility.ScreenPointToLocalPointInRectangle(
                _rect, Input.mousePosition, null, out var lp);
            return lp;
        }

        int PickNode(Vector2 mp)
        {
            int best = -1;
            float bestD = 999f;
            foreach (var n in _tree.nodes)
            {
                float d = Vector2.Distance(mp, NodePos(n));
                if (d < Mathf.Max(n.r * _zoom + 8f, 16f) && d < bestD) { bestD = d; best = n.id; }
            }
            return best;
        }

        void Update()
        {
            _t += Time.unscaledDeltaTime;

            if (Time.unscaledTime - _openTime > 0.2f &&
                (Input.GetKeyDown(KeyCode.Tab) || Input.GetKeyDown(KeyCode.Escape)))
            { Close(); return; }

            float wheel = Input.GetAxis("Mouse ScrollWheel");
            if (wheel > 0.01f) _zoom = Mathf.Clamp(_zoom * 1.1f, 0.55f, 1.7f);
            else if (wheel < -0.01f) _zoom = Mathf.Clamp(_zoom / 1.1f, 0.55f, 1.7f);

            var mp = MouseLocal();
            _hoverId = PickNode(mp);
            if (Input.GetMouseButtonDown(0) && _hoverId >= 0)
            {
                var res = _tree.Click(_tree.nodes[_hoverId]);
                Sfx.Play(res == TreeClickResult.Upgraded ? "win"
                    : res == TreeClickResult.Unequipped ? "deposit" : "ui",
                    res == TreeClickResult.Upgraded ? 0.35f : 0.25f);
            }

            _graphic.SetVerticesDirty();
            UpdateTexts(mp);
        }

        void UpdateTexts(Vector2 mp)
        {
            var s = GameState.I;
            var rect = _rect.rect;

            // глифы орбов
            for (int i = 0; i < _tree.nodes.Count; i++)
            {
                var n = _tree.nodes[i];
                var st = _tree.NodeState(n);
                var t = _glyphs[i];
                t.text = _tree.Glyph(n);
                t.fontSize = Mathf.Max((int)(n.r * _zoom * 0.95f), 10);
                t.color = st != TreeNodeState.Locked
                    ? new Color(0.08f, 0.05f, 0.1f) : new Color(0.35f, 0.35f, 0.4f);
                t.rectTransform.anchoredPosition = NodePos(n);
            }

            // подписи веток по кругу
            int li = 0;
            foreach (var n in _tree.nodes)
            {
                if (n.kind != TreeNodeKind.Branch) continue;
                var info = GameData.CLASSES[n.cls];
                bool active = _tree.MyBranchActive(n.cls);
                var t = _branchLabels[li++];
                t.text = info.name;
                t.color = active || s.branch == "" ? info.color : new Color(0.4f, 0.38f, 0.45f);
                var dir = NodePos(n).normalized;
                t.rectTransform.anchoredPosition = NodePos(n) + dir * (34f * _zoom + 26f);
            }

            // ресурсы слева сверху (возле монетки)
            var r = s.resources;
            _resText.text = $"{r["data_fragments"]} ◈  ·  {r["code_samples"]} ◇  ·  {r["mutagen"]} ✦";
            _resText.rectTransform.anchoredPosition = new Vector2(-rect.width * 0.5f + 70, rect.height * 0.5f - 44);

            // атрибуты справа, как в референсе (rich text: подпись мелко, значение крупно)
            var info2 = s.MyClassInfo();
            string Row(string label, string value) =>
                $"<size=15><color=#a69ac0>{label}</color></size>\n{value}\n";
            _statsValues.text =
                Row("ШТАММ", info2.name) + Row("УРОВЕНЬ", s.virusLevel.ToString()) + "\n" +
                Row("СИЛА", info2.str.ToString()) + Row("ЛОВКОСТЬ", info2.dex.ToString()) +
                Row("ИНТЕЛЛЕКТ", info2.intel.ToString()) + "\n" +
                Row("СКОРОСТЬ", $"+{s.EvoBonus("speed"):0.0}") +
                Row("СКРЫТНОСТЬ", $"+{(int)(s.EvoBonus("stealth") * 100)}%") +
                Row("BANDWIDTH", $"+{(int)s.EvoBonus("bw")}") +
                Row("HP", $"+{(int)s.EvoBonus("vitality")}");
            _statsValues.rectTransform.anchoredPosition = new Vector2(rect.width * 0.5f - 40, rect.height * 0.5f - 40);

            // футер и подсказка
            _footer.text = "колесо — зум · клик — прокачка · клик по взятому умению — откат · ESC/Tab — закрыть";
            _footer.color = new Color(0.75f, 0.7f, 0.85f);
            _footer.rectTransform.anchoredPosition = new Vector2(rect.width * 0.5f - 480, -rect.height * 0.5f + 24);
            _hint.text = s.branch == "" ? "выбери направленность: кликни большой узел ветки" : "";
            _hint.color = new Color(0.9f, 0.7f, 0.4f);
            _hint.rectTransform.anchoredPosition = new Vector2(-rect.width * 0.5f + 200, -rect.height * 0.5f + 24);

            UpdateTooltip(mp, rect);
        }

        void UpdateTooltip(Vector2 mp, Rect rect)
        {
            if (_hoverId < 0)
            {
                _tipPanel.gameObject.SetActive(false);
                return;
            }
            var n = _tree.nodes[_hoverId];
            var lines = _tree.TooltipLines(n);
            _tipPanel.gameObject.SetActive(true);
            float w = 400f, h = 48f + lines.Count * 24f;
            var p = mp + new Vector2(24f + w * 0.5f, 0);
            p.x = Mathf.Clamp(p.x, -rect.width * 0.5f + w * 0.5f + 10, rect.width * 0.5f - w * 0.5f - 10);
            p.y = Mathf.Clamp(p.y, -rect.height * 0.5f + h * 0.5f + 10, rect.height * 0.5f - h * 0.5f - 10);
            var rt = _tipPanel.rectTransform;
            rt.anchorMin = new Vector2(0.5f, 0.5f); rt.anchorMax = new Vector2(0.5f, 0.5f);
            rt.sizeDelta = new Vector2(w, h);
            rt.anchoredPosition = p;
            _tipTitle.text = _tree.TooltipTitle(n);
            _tipTitle.rectTransform.anchoredPosition = new Vector2(-w * 0.5f + 14, h * 0.5f - 16);
            _tipBody.text = string.Join("\n", lines);
            _tipBody.rectTransform.anchoredPosition = new Vector2(-w * 0.5f + 14, h * 0.5f - 44);
        }

        void Close()
        {
            IsOpen = false;
            if (_player != null) _player.controlEnabled = true;
            Cursor.lockState = CursorLockMode.Locked;
            Cursor.visible = false;
            Destroy(_root);
            Destroy(gameObject);
        }

        void OnDestroy() { if (IsOpen) IsOpen = false; }

        // ── отрисовка полотна (вызывает TreeGraphic) ──
        public void Populate(VertexHelper vh, Rect rect)
        {
            float hw = rect.width * 0.5f, hh = rect.height * 0.5f;

            // фон: тёмно-фиолетовый градиент
            AddQuad(vh, new Vector2(-hw, -hh), new Vector2(hw, hh), BgBottom, BgBottom);
            int steps = 14;
            for (int i = 0; i < steps; i++)
            {
                float f = (float)i / steps;
                var col = Color.Lerp(BgTop, BgBottom, f);
                col.a = 0.5f;
                float y0 = hh - rect.height * f / 1.6f;
                AddQuad(vh, new Vector2(-hw, y0 - rect.height / steps), new Vector2(hw, y0), col, col);
            }
            // звёзды
            foreach (var st in _stars)
            {
                float a = st.a * (0.6f + 0.4f * Mathf.Sin(_t * 1.4f + st.ph));
                var p = new Vector2(st.pos.x * rect.width - hw, st.pos.y * rect.height - hh);
                AddCircle(vh, p, st.r, new Color(0.7f, 0.6f, 0.9f, a), 6);
            }
            // золотая арка сверху (как в референсе)
            AddArc(vh, new Vector2(0, hh * 1.9f), hh * 1.34f, Mathf.PI * 1.28f, Mathf.PI * 1.72f,
                new Color(0.85f, 0.65f, 0.3f, 0.35f), 3f, 60);

            // связи
            foreach (var n in _tree.nodes)
            {
                if (n.link < 0) continue;
                var a = NodePos(_tree.nodes[n.link]);
                var b = NodePos(n);
                var st = _tree.NodeState(n);
                bool active = st == TreeNodeState.Done;
                var col = EdgeDim;
                float w = 2f;
                if (active)
                {
                    var cc = _tree.NodeColor(n, st);
                    col = new Color(cc.r, cc.g, cc.b, 0.9f);
                    w = 3.5f;
                }
                else if (st == TreeNodeState.Open)
                {
                    col = new Color(0.9f, 0.65f, 0.3f, 0.75f);
                    w = 2.5f;
                }
                AddLine(vh, a, b, w + 4f, new Color(col.r, col.g, col.b, col.a * 0.35f));
                AddLine(vh, a, b, w, col);
                if (active)   // бегущая искра по активным связям
                {
                    float f = Mathf.Repeat(_t * 0.6f + n.id * 0.13f, 1f);
                    AddCircle(vh, Vector2.Lerp(a, b, f), 3f, new Color(1f, 0.85f, 0.5f, 0.9f), 8);
                }
            }

            // узлы-орбы
            foreach (var n in _tree.nodes)
            {
                var p = NodePos(n);
                var st = _tree.NodeState(n);
                var col = _tree.NodeColor(n, st);
                float r = n.r * _zoom;
                // свечение
                if (st != TreeNodeState.Locked)
                {
                    float pulse = 1f + 0.12f * Mathf.Sin(_t * 2.4f + n.id);
                    AddCircle(vh, p, r * 1.7f * pulse, new Color(col.r, col.g, col.b, 0.10f), 24);
                    AddCircle(vh, p, r * 1.32f * pulse, new Color(col.r, col.g, col.b, 0.16f), 24);
                }
                // тело орба с бликом
                AddCircle(vh, p, r, Darken(col, 0.35f), 28);
                AddCircle(vh, p, r * 0.86f, col, 28);
                AddCircle(vh, p + new Vector2(-r * 0.25f, r * 0.3f), r * 0.34f,
                    new Color(1, 1, 1, st != TreeNodeState.Locked ? 0.28f : 0.08f), 12);
                // кольца выделения
                if (st == TreeNodeState.Done)
                    AddArc(vh, p, r + 3f * _zoom, 0, Mathf.PI * 2f, new Color(col.r, col.g, col.b, 0.9f), 2f, 36);
                if (st == TreeNodeState.Open)
                    AddArc(vh, p, r + 4f * _zoom + Mathf.Sin(_t * 3f) * 1.5f, 0, Mathf.PI * 2f,
                        new Color(1f, 0.8f, 0.4f, 0.8f), 2f, 36);
                if (n.id == _hoverId)
                    AddArc(vh, p, r + 7f * _zoom, 0, Mathf.PI * 2f, new Color(1, 1, 1, 0.85f), 2f, 36);
            }

            // монетка ресурсов слева сверху
            var coin = new Vector2(-hw + 46, hh - 44);
            AddCircle(vh, coin, 15f, new Color(0.9f, 0.7f, 0.3f), 20);
            AddCircle(vh, coin, 11f, new Color(0.65f, 0.45f, 0.15f), 20);
        }

        static Color Darken(Color c, float k) => new(c.r * (1 - k), c.g * (1 - k), c.b * (1 - k), c.a);

        // ── примитивы вершинной геометрии ──
        static void AddQuad(VertexHelper vh, Vector2 min, Vector2 max, Color cBottom, Color cTop)
        {
            int i = vh.currentVertCount;
            var v = UIVertex.simpleVert;
            v.position = new Vector3(min.x, min.y); v.color = cBottom; vh.AddVert(v);
            v.position = new Vector3(min.x, max.y); v.color = cTop; vh.AddVert(v);
            v.position = new Vector3(max.x, max.y); v.color = cTop; vh.AddVert(v);
            v.position = new Vector3(max.x, min.y); v.color = cBottom; vh.AddVert(v);
            vh.AddTriangle(i, i + 1, i + 2);
            vh.AddTriangle(i, i + 2, i + 3);
        }

        static void AddLine(VertexHelper vh, Vector2 a, Vector2 b, float w, Color c)
        {
            var dir = (b - a).normalized;
            var n = new Vector2(-dir.y, dir.x) * (w * 0.5f);
            int i = vh.currentVertCount;
            var v = UIVertex.simpleVert; v.color = c;
            v.position = a - n; vh.AddVert(v);
            v.position = a + n; vh.AddVert(v);
            v.position = b + n; vh.AddVert(v);
            v.position = b - n; vh.AddVert(v);
            vh.AddTriangle(i, i + 1, i + 2);
            vh.AddTriangle(i, i + 2, i + 3);
        }

        static void AddCircle(VertexHelper vh, Vector2 c, float r, Color col, int seg)
        {
            int center = vh.currentVertCount;
            var v = UIVertex.simpleVert; v.color = col;
            v.position = c; vh.AddVert(v);
            for (int i = 0; i <= seg; i++)
            {
                float a = Mathf.PI * 2f * i / seg;
                v.position = c + new Vector2(Mathf.Cos(a), Mathf.Sin(a)) * r;
                vh.AddVert(v);
                if (i > 0) vh.AddTriangle(center, center + i, center + i + 1);
            }
        }

        static void AddArc(VertexHelper vh, Vector2 c, float r, float a0, float a1, Color col, float w, int seg)
        {
            var v = UIVertex.simpleVert; v.color = col;
            int start = vh.currentVertCount;
            for (int i = 0; i <= seg; i++)
            {
                float a = Mathf.Lerp(a0, a1, (float)i / seg);
                var dir = new Vector2(Mathf.Cos(a), Mathf.Sin(a));
                v.position = c + dir * (r - w * 0.5f); vh.AddVert(v);
                v.position = c + dir * (r + w * 0.5f); vh.AddVert(v);
                if (i > 0)
                {
                    int k = start + i * 2;
                    vh.AddTriangle(k - 2, k - 1, k + 1);
                    vh.AddTriangle(k - 2, k + 1, k);
                }
            }
        }
    }

    // полотно дерева: вся геометрия рисуется одним Graphic-мешем
    public class TreeGraphic : MaskableGraphic
    {
        public EvolutionUI owner;

        protected override void OnPopulateMesh(VertexHelper vh)
        {
            vh.Clear();
            if (owner != null) owner.Populate(vh, rectTransform.rect);
        }
    }
}
