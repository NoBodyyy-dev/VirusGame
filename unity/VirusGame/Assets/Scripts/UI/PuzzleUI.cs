using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;
using Virus.Util;

namespace Virus.UI
{
    // Порт puzzle_ui.gd: «СХЕМА ВЗЛОМА» — на сетке 4×4 вспыхивает маршрут,
    // повтори его в том же порядке. Ошибка — новый маршрут, попыток сколько угодно.
    public class PuzzleUI : MonoBehaviour
    {
        const int N = 4;
        const float ShowStep = 0.5f;

        public static bool IsOpen { get; private set; }

        int _difficulty;
        Action _onSolved;
        readonly List<Button> _cells = new();
        readonly List<Image> _cellImgs = new();
        readonly List<int> _seq = new();
        int _inputAt;
        string _phase = "show";
        Text _status;
        GameObject _root;
        Player.VirusPlayer _player;

        public static void Open(int difficulty, string title, Action onSolved)
        {
            if (IsOpen) return;
            var go = new GameObject("PuzzleUI");
            var p = go.AddComponent<PuzzleUI>();
            p._difficulty = Mathf.Clamp(difficulty, 1, 5);
            p._onSolved = onSolved;
            p.BuildUI(title);
        }

        void BuildUI(string title)
        {
            IsOpen = true;
            _player = FindFirstObjectByType<Player.VirusPlayer>();
            if (_player != null) _player.controlEnabled = false;
            Cursor.lockState = CursorLockMode.None;
            Cursor.visible = true;

            var canvasGo = new GameObject("PuzzleCanvas", typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
            _root = canvasGo;
            var canvas = canvasGo.GetComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = 50;
            canvasGo.GetComponent<CanvasScaler>().uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            canvasGo.GetComponent<CanvasScaler>().referenceResolution = new Vector2(1600, 900);

            var dim = NewRect(canvasGo.transform, Vector2.zero, Vector2.one, Vector2.zero);
            dim.AddComponent<Image>().color = new Color(0, 0.006f, 0.014f, 0.82f);

            var panel = NewRect(canvasGo.transform, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), new Vector2(460, 620));
            panel.AddComponent<Image>().color = new Color(0.008f, 0.022f, 0.04f, 0.97f);

            MakeText(panel.transform, title, new Vector2(0, 270), 26, new Color(0.21f, 0.85f, 1f));
            _status = MakeText(panel.transform, "СЛЕДИ ЗА СИГНАЛОМ…", new Vector2(0, 230), 18, new Color(1f, 0.7f, 0.35f));

            for (int i = 0; i < N * N; i++)
            {
                int idx = i;
                var cellGo = NewRect(panel.transform, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), new Vector2(88, 88));
                var rt = cellGo.GetComponent<RectTransform>();
                rt.anchoredPosition = new Vector2((i % N - 1.5f) * 98f, 110f - (i / N) * 98f);
                var img = cellGo.AddComponent<Image>();
                img.color = CellIdle;
                var btn = cellGo.AddComponent<Button>();
                btn.onClick.AddListener(() => OnCell(idx));
                _cells.Add(btn);
                _cellImgs.Add(img);
            }

            var cancelGo = NewRect(panel.transform, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), new Vector2(340, 46));
            cancelGo.GetComponent<RectTransform>().anchoredPosition = new Vector2(0, -270);
            cancelGo.AddComponent<Image>().color = new Color(0.2f, 0.05f, 0.08f, 0.9f);
            var cbtn = cancelGo.AddComponent<Button>();
            cbtn.onClick.AddListener(() => Close(false));
            MakeText(cancelGo.transform, "ОТОЙТИ ОТ ТЕРМИНАЛА", Vector2.zero, 18, new Color(1f, 0.4f, 0.5f));

            NewSequence();
        }

        static readonly Color CellIdle = new(0.06f, 0.14f, 0.2f, 0.95f);
        static readonly Color CellLit = new(0.16f, 0.95f, 0.75f, 1f);

        static GameObject NewRect(Transform parent, Vector2 aMin, Vector2 aMax, Vector2 size)
        {
            var go = new GameObject("rect", typeof(RectTransform));
            go.transform.SetParent(parent, false);
            var rt = go.GetComponent<RectTransform>();
            rt.anchorMin = aMin; rt.anchorMax = aMax;
            rt.sizeDelta = size;
            if (aMin == Vector2.zero && aMax == Vector2.one) { rt.offsetMin = Vector2.zero; rt.offsetMax = Vector2.zero; }
            return go;
        }

        static Text MakeText(Transform parent, string s, Vector2 pos, int size, Color c)
        {
            var go = new GameObject("txt", typeof(RectTransform));
            go.transform.SetParent(parent, false);
            var t = go.AddComponent<Text>();
            t.font = Build.UIFont; t.text = s; t.fontSize = size; t.color = c;
            t.alignment = TextAnchor.MiddleCenter;
            t.horizontalOverflow = HorizontalWrapMode.Overflow;
            t.verticalOverflow = VerticalWrapMode.Overflow;
            var rt = t.rectTransform;
            rt.anchoredPosition = pos; rt.sizeDelta = new Vector2(440, 40);
            return t;
        }

        void NewSequence()
        {
            _seq.Clear();
            int len = 3 + _difficulty;
            int cur = UnityEngine.Random.Range(0, N * N);
            _seq.Add(cur);
            int guard = 0;
            while (_seq.Count < len && guard++ < 200)
            {
                var opts = new List<int>();
                int cx = cur % N, cy = cur / N;
                foreach (var (dx, dy) in new[] { (1, 0), (-1, 0), (0, 1), (0, -1) })
                {
                    int nx = cx + dx, ny = cy + dy, ni = ny * N + nx;
                    if (nx >= 0 && nx < N && ny >= 0 && ny < N && !_seq.Contains(ni)) opts.Add(ni);
                }
                if (opts.Count == 0) { _seq.Clear(); cur = UnityEngine.Random.Range(0, N * N); _seq.Add(cur); continue; }
                cur = opts[UnityEngine.Random.Range(0, opts.Count)];
                _seq.Add(cur);
            }
            _inputAt = 0;
            _phase = "show";
            _status.text = $"СЛЕДИ ЗА СИГНАЛОМ… ({_seq.Count} шагов)";
            StartCoroutine(PlaySequence());
        }

        IEnumerator PlaySequence()
        {
            yield return new WaitForSeconds(0.5f);
            foreach (var idx in _seq)
            {
                if (_phase != "show") yield break;
                _cellImgs[idx].color = CellLit;
                yield return new WaitForSeconds(ShowStep * 0.7f);
                _cellImgs[idx].color = CellIdle;
                yield return new WaitForSeconds(ShowStep * 0.3f);
            }
            _phase = "input";
            _status.text = $"ПОВТОРИ МАРШРУТ: 0/{_seq.Count}";
            _status.color = new Color(0.21f, 0.85f, 1f);
        }

        void OnCell(int idx)
        {
            if (_phase != "input") return;
            if (idx == _seq[_inputAt])
            {
                _inputAt++;
                StartCoroutine(FlashCell(idx));
                _status.text = $"ПОВТОРИ МАРШРУТ: {_inputAt}/{_seq.Count}";
                if (_inputAt >= _seq.Count)
                {
                    _phase = "done";
                    _status.text = "// ДОСТУП РАЗРЕШЁН //";
                    _status.color = new Color(0.16f, 0.95f, 0.75f);
                    Sfx.Play("win", 0.35f);
                    StartCoroutine(CloseSoon());
                }
            }
            else
            {
                _status.text = "СБОЙ ТРАССИРОВКИ — новый маршрут";
                _status.color = new Color(1f, 0.3f, 0.4f);
                _phase = "show";
                StartCoroutine(RestartSoon());
            }
        }

        IEnumerator FlashCell(int idx)
        {
            _cellImgs[idx].color = CellLit;
            yield return new WaitForSeconds(0.18f);
            if (_phase == "input" || _phase == "done") _cellImgs[idx].color = CellIdle;
        }

        IEnumerator RestartSoon() { yield return new WaitForSeconds(0.7f); if (_phase == "show") NewSequence(); }
        IEnumerator CloseSoon() { yield return new WaitForSeconds(0.55f); Close(true); }

        void Update()
        {
            if (Input.GetKeyDown(KeyCode.Escape)) Close(false);
        }

        void Close(bool success)
        {
            IsOpen = false;
            if (_player != null) _player.controlEnabled = true;
            Cursor.lockState = CursorLockMode.Locked;
            Cursor.visible = false;
            if (success) _onSolved?.Invoke();
            Destroy(_root);
            Destroy(gameObject);
        }
    }
}
