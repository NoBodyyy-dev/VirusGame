using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;
using Virus.Util;

namespace Virus.UI
{
    // Пул мини-головоломок взлома. Раньше была одна («Саймон» 4×4) — после
    // пятого рейда приедалась. Теперь у каждой двери/консоли свой тип:
    //  • pipes — МАРШРУТ ПАКЕТА: поверни трубки, соедини вход с выходом;
    //  • code  — ПОДБОР КЛЮЧА: мастермайнд по глифам с уликами «на месте/не там»;
    //  • wires — КОММУТАЦИЯ: расшифруй легенду и соедини порты парами.
    // Оболочка (канвас/панель/статус/выход/блокировка игрока) общая.
    public abstract class PuzzleBase : MonoBehaviour
    {
        protected static readonly Color Accent = new(0.21f, 0.85f, 1f);
        protected static readonly Color Good = new(0.16f, 0.95f, 0.75f);
        protected static readonly Color Warn = new(1f, 0.7f, 0.35f);
        protected static readonly Color Bad = new(1f, 0.3f, 0.4f);
        protected static readonly Color Idle = new(0.06f, 0.14f, 0.2f, 0.95f);

        protected int difficulty;
        protected Text status;
        protected GameObject panel;
        protected readonly System.Random rng = new();

        Action _onSolved;
        GameObject _root;
        Player.VirusPlayer _player;
        bool _done;

        protected void Shell(int diff, string title, Vector2 size, Action onSolved)
        {
            PuzzleUI.MarkOpen(true);
            difficulty = Mathf.Clamp(diff, 1, 5);
            _onSolved = onSolved;
            _player = FindFirstObjectByType<Player.VirusPlayer>();
            if (_player != null) _player.controlEnabled = false;
            Cursor.lockState = CursorLockMode.None;
            Cursor.visible = true;

            var canvasGo = new GameObject("PuzzleCanvas", typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
            _root = canvasGo;
            var canvas = canvasGo.GetComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = 50;
            var scaler = canvasGo.GetComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1600, 900);

            var dim = NewRect(canvasGo.transform, Vector2.zero, Vector2.one, Vector2.zero);
            dim.AddComponent<Image>().color = new Color(0, 0.006f, 0.014f, 0.82f);

            panel = NewRect(canvasGo.transform, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), size);
            var panelImg = panel.AddComponent<Image>();
            panelImg.sprite = UIKit.Rounded;
            panelImg.type = Image.Type.Sliced;
            panelImg.color = UIKit.PanelBg2;

            MakeText(panel.transform, title, new Vector2(0, size.y * 0.5f - 40f), 26, Accent);
            status = MakeText(panel.transform, "", new Vector2(0, size.y * 0.5f - 78f), 18, Warn);

            UIKit.MakeButton(panel.transform, "ОТОЙТИ ОТ ТЕРМИНАЛА",
                new Vector2(0, -size.y * 0.5f + 42f), new Vector2(340, 46),
                () => Close(false), Bad);
        }

        protected static GameObject NewRect(Transform parent, Vector2 aMin, Vector2 aMax, Vector2 size)
        {
            var go = new GameObject("rect", typeof(RectTransform));
            go.transform.SetParent(parent, false);
            var rt = go.GetComponent<RectTransform>();
            rt.anchorMin = aMin; rt.anchorMax = aMax;
            rt.sizeDelta = size;
            if (aMin == Vector2.zero && aMax == Vector2.one) { rt.offsetMin = Vector2.zero; rt.offsetMax = Vector2.zero; }
            return go;
        }

        protected static Text MakeText(Transform parent, string s, Vector2 pos, int size, Color c)
        {
            var go = new GameObject("txt", typeof(RectTransform));
            go.transform.SetParent(parent, false);
            var t = go.AddComponent<Text>();
            t.font = Build.UIFont; t.text = s; t.fontSize = size; t.color = c;
            t.alignment = TextAnchor.MiddleCenter;
            t.horizontalOverflow = HorizontalWrapMode.Overflow;
            t.verticalOverflow = VerticalWrapMode.Overflow;
            var rt = t.rectTransform;
            rt.anchoredPosition = pos; rt.sizeDelta = new Vector2(460, 40);
            return t;
        }

        protected Image MakeCell(Transform parent, Vector2 pos, Vector2 size, Action onClick)
        {
            var go = NewRect(parent, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), size);
            go.GetComponent<RectTransform>().anchoredPosition = pos;
            var img = go.AddComponent<Image>();
            img.sprite = UIKit.Rounded;
            img.type = Image.Type.Sliced;
            img.color = Idle;
            if (onClick != null)
                go.AddComponent<Button>().onClick.AddListener(() => onClick());
            return img;
        }

        // головоломка решена: зелёный статус, звук, закрытие с паузой
        protected void Solve(string doneMsg = "// ДОСТУП РАЗРЕШЁН //")
        {
            if (_done) return;
            _done = true;
            status.text = doneMsg;
            status.color = Good;
            Sfx.Play("win", 0.35f);
            StartCoroutine(CloseSoon());
        }

        protected bool Solved => _done;

        IEnumerator CloseSoon()
        {
            yield return new WaitForSeconds(0.55f);
            Close(true);
        }

        protected virtual void Update()
        {
            if (Input.GetKeyDown(KeyCode.Escape)) Close(false);
        }

        protected void Close(bool success)
        {
            PuzzleUI.MarkOpen(false);
            if (_player != null) _player.controlEnabled = true;
            Cursor.lockState = CursorLockMode.Locked;
            Cursor.visible = false;
            if (success) _onSolved?.Invoke();
            Destroy(_root);
            Destroy(gameObject);
        }
    }

    // ── МАРШРУТ ПАКЕТА: сетка трубок, соедини вход (слева) с выходом (справа) ──
    public class PipesPuzzle : PuzzleBase
    {
        // биты соединений: 1=N, 2=E, 4=S, 8=W; поворот по часовой сдвигает биты
        const int N = 1, E = 2, S = 4, W = 8;
        static int RotCW(int m) => ((m << 1) | (m >> 3)) & 15;

        int _gw, _gh;
        int[] _mask;                 // текущая маска клетки (уже с поворотами)
        Image[] _cells;
        readonly List<Image>[] _barsOf = new List<Image>[36];
        RectTransform[] _rotors;
        int _inRow, _outRow;
        const float CellSz = 82f, CellGap = 92f;

        public static void Spawn(int difficulty, string title, Action onSolved)
        {
            var go = new GameObject("PipesPuzzle");
            var p = go.AddComponent<PipesPuzzle>();
            p.Init(difficulty, title, onSolved);
        }

        void Init(int diff, string title, Action onSolved)
        {
            _gw = 5;
            _gh = diff >= 3 ? 4 : 3;
            Shell(diff, title, new Vector2(560, 640), onSolved);
            status.text = "ПОВЕРНИ ТРУБКИ: проведи пакет от входа к выходу";
            Generate();
            BuildGrid();
            Reflow();
        }

        void Generate()
        {
            _mask = new int[_gw * _gh];
            // гарантированный маршрут: случайное блуждание слева направо
            int row = rng.Next(_gh);
            _inRow = row;
            int col = 0, guard = 0;
            var path = new List<int> { row * _gw };
            int straightRun = 0;
            while (col < _gw - 1 && guard++ < 200)
            {
                bool vert = rng.NextDouble() < 0.45;
                if (vert)
                {
                    int dr = rng.NextDouble() < 0.5 ? -1 : 1;
                    int nr = row + dr;
                    int ni = nr * _gw + col;
                    if (nr >= 0 && nr < _gh && !path.Contains(ni))
                    {
                        Link(row * _gw + col, ni);
                        row = nr;
                        path.Add(ni);
                        continue;
                    }
                }
                int next = row * _gw + col + 1;
                Link(row * _gw + col, next);
                col++;
                path.Add(next);
                straightRun++;
            }
            _outRow = row;
            _mask[_inRow * _gw] |= W;                 // вход слева
            _mask[_outRow * _gw + _gw - 1] |= E;      // выход справа
            // клетки вне маршрута — обманки из прямых и уголков
            int[] decoys = { N | S, E | W, N | E, E | S, S | W, W | N };
            for (int i = 0; i < _mask.Length; i++)
                if (_mask[i] == 0) _mask[i] = decoys[rng.Next(decoys.Length)];
            // перемешать: каждый повёрнут случайно
            for (int i = 0; i < _mask.Length; i++)
            {
                int spins = rng.Next(4);
                for (int k = 0; k < spins; k++) _mask[i] = RotCW(_mask[i]);
            }
        }

        void Link(int a, int b)
        {
            int ax = a % _gw, ay = a / _gw, bx = b % _gw, by = b / _gw;
            if (bx > ax) { _mask[a] |= E; _mask[b] |= W; }
            else if (bx < ax) { _mask[a] |= W; _mask[b] |= E; }
            else if (by > ay) { _mask[a] |= S; _mask[b] |= N; }
            else { _mask[a] |= N; _mask[b] |= S; }
        }

        void BuildGrid()
        {
            _cells = new Image[_gw * _gh];
            _rotors = new RectTransform[_gw * _gh];
            float x0 = -(_gw - 1) * CellGap * 0.5f;
            float y0 = (_gh - 1) * CellGap * 0.5f + 10f;
            for (int i = 0; i < _gw * _gh; i++)
            {
                int idx = i;
                int cx = i % _gw, cy = i / _gw;
                var pos = new Vector2(x0 + cx * CellGap, y0 - cy * CellGap);
                _cells[i] = MakeCell(panel.transform, pos, new Vector2(CellSz, CellSz), () => OnCell(idx));
                // ротор: бары соединений вращаются одним контейнером
                var rotGo = NewRect(_cells[i].transform, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), new Vector2(CellSz, CellSz));
                _rotors[i] = rotGo.GetComponent<RectTransform>();
                _barsOf[i] = new List<Image>();
                int m = _mask[i];
                foreach (var (bit, bpos, bsize) in new (int, Vector2, Vector2)[]
                {
                    (N, new Vector2(0, CellSz * 0.25f), new Vector2(12, CellSz * 0.5f)),
                    (E, new Vector2(CellSz * 0.25f, 0), new Vector2(CellSz * 0.5f, 12)),
                    (S, new Vector2(0, -CellSz * 0.25f), new Vector2(12, CellSz * 0.5f)),
                    (W, new Vector2(-CellSz * 0.25f, 0), new Vector2(CellSz * 0.5f, 12)),
                })
                {
                    if ((m & bit) == 0) continue;
                    var bar = NewRect(_rotors[i], new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), bsize);
                    bar.GetComponent<RectTransform>().anchoredPosition = bpos;
                    _barsOf[i].Add(bar.AddComponent<Image>());
                }
                var hub = NewRect(_rotors[i], new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), new Vector2(18, 18));
                _barsOf[i].Add(hub.AddComponent<Image>());
                // повернуть ротор в текущее (перемешанное) состояние нельзя —
                // бары уже нарисованы ПО текущей маске; ротор стоит на нуле
            }
            // стрелки входа/выхода
            float inY = y0 - _inRow * CellGap, outY = y0 - _outRow * CellGap;
            MakeText(panel.transform, "→", new Vector2(x0 - CellGap * 0.72f, inY), 30, Good);
            MakeText(panel.transform, "→", new Vector2(-x0 + CellGap * 0.72f, outY), 30, Good);
        }

        void OnCell(int idx)
        {
            if (Solved) return;
            _mask[idx] = RotCW(_mask[idx]);
            var r = _rotors[idx];
            r.localEulerAngles = new Vector3(0, 0, r.localEulerAngles.z - 90f);
            Sfx.Play("ui", 0.2f);
            Reflow();
        }

        // поток: BFS от входа; соединение = встречные биты у соседей
        void Reflow()
        {
            var lit = new bool[_gw * _gh];
            int start = _inRow * _gw;
            if ((_mask[start] & W) != 0)
            {
                var q = new Queue<int>();
                q.Enqueue(start);
                lit[start] = true;
                while (q.Count > 0)
                {
                    int c = q.Dequeue();
                    int cx = c % _gw, cy = c / _gw;
                    foreach (var (bit, dx, dy, opp) in new (int, int, int, int)[]
                        { (N, 0, -1, S), (E, 1, 0, W), (S, 0, 1, N), (W, -1, 0, E) })
                    {
                        if ((_mask[c] & bit) == 0) continue;
                        int nx = cx + dx, ny = cy + dy;
                        if (nx < 0 || nx >= _gw || ny < 0 || ny >= _gh) continue;
                        int n = ny * _gw + nx;
                        if (lit[n] || (_mask[n] & opp) == 0) continue;
                        lit[n] = true;
                        q.Enqueue(n);
                    }
                }
            }
            for (int i = 0; i < _cells.Length; i++)
            {
                var barCol = lit[i] ? Good : new Color(0.3f, 0.45f, 0.55f);
                foreach (var b in _barsOf[i]) if (b != null) b.color = barCol;
            }
            int outIdx = _outRow * _gw + _gw - 1;
            if (lit[outIdx] && (_mask[outIdx] & E) != 0)
                Solve("// ПАКЕТ ДОСТАВЛЕН — ДОСТУП РАЗРЕШЁН //");
            else
                status.text = "ПОВЕРНИ ТРУБКИ: проведи пакет от входа к выходу";
        }
    }

    // ── ПОДБОР КЛЮЧА: мастермайнд по глифам ──
    public class CodeLockPuzzle : PuzzleBase
    {
        static readonly string[] Glyphs = { "Δ", "Ω", "Ψ", "λ", "π", "∑" };
        const int CodeLen = 4;

        int[] _secret;
        readonly List<int> _guess = new();
        int _attemptsLeft;
        Text[] _slots;
        readonly List<Text> _history = new();
        Transform _historyRoot;
        int _glyphCount;

        public static void Spawn(int difficulty, string title, Action onSolved)
        {
            var go = new GameObject("CodeLockPuzzle");
            var p = go.AddComponent<CodeLockPuzzle>();
            p.Init(difficulty, title, onSolved);
        }

        void Init(int diff, string title, Action onSolved)
        {
            Shell(diff, title, new Vector2(520, 660), onSolved);
            _glyphCount = diff >= 3 ? 6 : 5;
            _attemptsLeft = Mathf.Max(9 - diff, 5);
            NewSecret();

            // слоты текущего ввода
            _slots = new Text[CodeLen];
            for (int i = 0; i < CodeLen; i++)
            {
                var cell = MakeCell(panel.transform, new Vector2((i - 1.5f) * 78f, 178f), new Vector2(66, 66), null);
                _slots[i] = MakeText(cell.transform, "·", Vector2.zero, 34, Accent);
            }
            // клавиатура глифов
            for (int i = 0; i < _glyphCount; i++)
            {
                int gi = i;
                var key = MakeCell(panel.transform, new Vector2((i - (_glyphCount - 1) * 0.5f) * 72f, 96f),
                    new Vector2(62, 62), () => PressGlyph(gi));
                MakeText(key.transform, Glyphs[i], Vector2.zero, 30, new Color(0.85f, 0.93f, 1f));
            }
            UIKit.MakeButton(panel.transform, "СТЕРЕТЬ", new Vector2(-105, 28), new Vector2(170, 44), Backspace, Warn);
            UIKit.MakeButton(panel.transform, "ВВОД", new Vector2(105, 28), new Vector2(170, 44), Submit, Good);
            // история попыток
            _historyRoot = NewRect(panel.transform, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), new Vector2(460, 220)).transform;
            _historyRoot.GetComponent<RectTransform>().anchoredPosition = new Vector2(0, -128);
            MakeText(panel.transform, "● — глиф на месте · ○ — есть, но не там", new Vector2(0, -252), 14,
                new Color(0.55f, 0.65f, 0.75f));
            RefreshStatus();
        }

        void NewSecret()
        {
            _secret = new int[CodeLen];
            for (int i = 0; i < CodeLen; i++) _secret[i] = rng.Next(_glyphCount);
        }

        void RefreshStatus() =>
            status.text = $"ПОДБЕРИ КЛЮЧ ИЗ {CodeLen} ГЛИФОВ · попыток: {_attemptsLeft}";

        void PressGlyph(int gi)
        {
            if (Solved || _guess.Count >= CodeLen) return;
            _guess.Add(gi);
            Sfx.Play("ui", 0.2f);
            RedrawGuess();
        }

        void Backspace()
        {
            if (Solved || _guess.Count == 0) return;
            _guess.RemoveAt(_guess.Count - 1);
            RedrawGuess();
        }

        void RedrawGuess()
        {
            for (int i = 0; i < CodeLen; i++)
                _slots[i].text = i < _guess.Count ? Glyphs[_guess[i]] : "·";
        }

        void Submit()
        {
            if (Solved || _guess.Count < CodeLen) return;
            int exact = 0;
            var secretLeft = new List<int>();
            var guessLeft = new List<int>();
            for (int i = 0; i < CodeLen; i++)
            {
                if (_guess[i] == _secret[i]) exact++;
                else { secretLeft.Add(_secret[i]); guessLeft.Add(_guess[i]); }
            }
            int near = 0;
            foreach (var g in guessLeft)
                if (secretLeft.Remove(g)) near++;

            string line = "";
            foreach (var g in _guess) line += Glyphs[g] + " ";
            var t = MakeText(_historyRoot, $"{line}→  ●{exact}  ○{near}", Vector2.zero, 20,
                exact == CodeLen ? Good : new Color(0.75f, 0.85f, 0.95f));
            _history.Add(t);
            for (int i = 0; i < _history.Count; i++)
                _history[i].rectTransform.anchoredPosition = new Vector2(0, 96 - (_history.Count - 1 - i) * 34f);
            if (_history.Count > 6) { Destroy(_history[0].gameObject); _history.RemoveAt(0); }

            _guess.Clear();
            RedrawGuess();

            if (exact == CodeLen) { Solve("// КЛЮЧ ПРИНЯТ — ДОСТУП РАЗРЕШЁН //"); return; }
            _attemptsLeft--;
            if (_attemptsLeft <= 0)
            {
                NewSecret();
                _attemptsLeft = Mathf.Max(9 - difficulty, 5);
                foreach (var h in _history) Destroy(h.gameObject);
                _history.Clear();
                status.color = Bad;
                status.text = "КЛЮЧ СМЕНИЛСЯ — система перегенерировала пароль";
                Sfx.Play("trap", 0.25f);
                return;
            }
            status.color = Warn;
            RefreshStatus();
        }
    }

    // ── КОММУТАЦИЯ: соедини порты по шифро-легенде ──
    public class WiresPuzzle : PuzzleBase
    {
        static readonly string[] Glyphs = { "Δ", "Ω", "Ψ", "λ", "π", "∑" };
        static readonly string[] Cipher = { "#", "%", "&", "@", "?", "!" };
        static readonly Color[] Cols =
        {
            new(0.21f, 0.85f, 1f), new(1f, 0.45f, 0.55f), new(0.35f, 0.95f, 0.6f),
            new(1f, 0.8f, 0.3f), new(0.75f, 0.55f, 1f), new(1f, 0.6f, 0.3f),
        };

        int _pairs;
        int[] _map;                  // глиф i шифруется как Cipher[_map[i]]
        int[] _rightGlyph;           // какой (расшифрованный) глиф у правого порта j
        bool[] _linked;
        int _selLeft = -1, _errors;
        Image[] _leftCells, _rightCells;
        Text _legend;

        public static void Spawn(int difficulty, string title, Action onSolved)
        {
            var go = new GameObject("WiresPuzzle");
            var p = go.AddComponent<WiresPuzzle>();
            p.Init(difficulty, title, onSolved);
        }

        void Init(int diff, string title, Action onSolved)
        {
            _pairs = Mathf.Clamp(4 + (diff >= 2 ? 1 : 0) + (diff >= 4 ? 1 : 0), 4, 6);
            Shell(diff, title, new Vector2(560, 640), onSolved);
            status.text = "СОЕДИНИ ПОРТЫ: слева глиф — справа его шифр из легенды";

            _map = ShuffledIndices(_pairs);
            _rightGlyph = ShuffledIndices(_pairs);
            _linked = new bool[_pairs];

            _legend = MakeText(panel.transform, LegendText(), new Vector2(0, 210), 21, new Color(0.85f, 0.93f, 1f));

            _leftCells = new Image[_pairs];
            _rightCells = new Image[_pairs];
            float y0 = 140f, step = 66f;
            for (int i = 0; i < _pairs; i++)
            {
                int li = i, ri = i;
                _leftCells[i] = MakeCell(panel.transform, new Vector2(-158, y0 - i * step), new Vector2(96, 54), () => PickLeft(li));
                MakeText(_leftCells[i].transform, Glyphs[i], Vector2.zero, 26, Cols[i]);
                _rightCells[i] = MakeCell(panel.transform, new Vector2(158, y0 - i * step), new Vector2(96, 54), () => PickRight(ri));
                MakeText(_rightCells[i].transform, Cipher[_map[_rightGlyph[i]]], Vector2.zero, 26,
                    new Color(0.7f, 0.78f, 0.86f));
            }
        }

        string LegendText()
        {
            string s = "ЛЕГЕНДА:  ";
            for (int i = 0; i < _pairs; i++) s += $"{Glyphs[i]}→{Cipher[_map[i]]}   ";
            return s;
        }

        int[] ShuffledIndices(int n)
        {
            var a = new int[n];
            for (int i = 0; i < n; i++) a[i] = i;
            for (int i = n - 1; i > 0; i--)
            {
                int j = rng.Next(i + 1);
                (a[i], a[j]) = (a[j], a[i]);
            }
            return a;
        }

        void PickLeft(int i)
        {
            if (Solved || _linked[i]) return;
            _selLeft = i;
            Sfx.Play("ui", 0.2f);
            for (int k = 0; k < _pairs; k++)
                if (!_linked[k]) _leftCells[k].color = k == i ? new Color(0.1f, 0.3f, 0.42f) : Idle;
        }

        void PickRight(int j)
        {
            if (Solved || _selLeft < 0) return;
            int rightIdx = _rightGlyph[j];
            bool already = false;
            for (int k = 0; k < _pairs; k++) if (_linked[k] && _rightGlyph[j] == k) already = true;
            if (already) return;
            if (rightIdx == _selLeft)
            {
                _linked[_selLeft] = true;
                var col = Cols[_selLeft];
                _leftCells[_selLeft].color = new Color(col.r * 0.25f, col.g * 0.25f, col.b * 0.25f);
                _rightCells[j].color = new Color(col.r * 0.25f, col.g * 0.25f, col.b * 0.25f);
                DrawLink(_selLeft, j, col);
                _selLeft = -1;
                Sfx.Play("deposit", 0.25f);
                bool all = true;
                foreach (var l in _linked) if (!l) all = false;
                if (all) Solve("// КОММУТАЦИЯ ЗАМКНУТА — ДОСТУП РАЗРЕШЁН //");
            }
            else
            {
                _errors++;
                Sfx.Play("trap", 0.25f);
                status.color = Bad;
                if (_errors >= 3)
                {
                    // три промаха — система меняет шифр и рвёт все линии
                    _errors = 0;
                    status.text = "ШИФР СМЕНЁН: три ошибки — коммутация сброшена";
                    ResetBoard();
                }
                else status.text = $"НЕВЕРНЫЙ ПОРТ ({_errors}/3 до смены шифра)";
                _selLeft = -1;
                for (int k = 0; k < _pairs; k++) if (!_linked[k]) _leftCells[k].color = Idle;
            }
        }

        readonly List<GameObject> _links = new();

        void DrawLink(int li, int rj, Color col)
        {
            float y0 = 140f, step = 66f;
            var a = new Vector2(-110, y0 - li * step);
            var b = new Vector2(110, y0 - rj * step);
            var mid = (a + b) * 0.5f;
            var d = b - a;
            var go = NewRect(panel.transform, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f),
                new Vector2(d.magnitude, 5f));
            var rt = go.GetComponent<RectTransform>();
            rt.anchoredPosition = mid;
            rt.localEulerAngles = new Vector3(0, 0, Mathf.Atan2(d.y, d.x) * Mathf.Rad2Deg);
            go.AddComponent<Image>().color = col;
            _links.Add(go);
        }

        void ResetBoard()
        {
            foreach (var l in _links) Destroy(l);
            _links.Clear();
            _map = ShuffledIndices(_pairs);
            _legend.text = LegendText();
            for (int k = 0; k < _pairs; k++)
            {
                _linked[k] = false;
                _leftCells[k].color = Idle;
                _rightCells[k].color = Idle;
                var t = _rightCells[k].GetComponentInChildren<Text>();
                if (t != null) t.text = Cipher[_map[_rightGlyph[k]]];
            }
        }
    }
}
