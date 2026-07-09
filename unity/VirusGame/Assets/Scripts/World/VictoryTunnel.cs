using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;
using Virus.Core;
using Virus.Util;

namespace Virus.World
{
    // Порт victory_tunnel.gd: белый туннель, за окнами летают телевизоры
    // «ORACLE DEAD / WHERE LOST DATA / GG», в конце вход на сервер = конец игры.
    public class VictoryTunnel : MonoBehaviour
    {
        const float W = 10f, H = 6f, ZStart = 55f, ZEnd = -58f;
        static readonly string[] TvTexts = { "ORACLE DEAD", "WHERE LOST DATA", "GG" };

        Player.VirusPlayer _player;
        readonly List<(Transform t, float baseY, float speed, float phase)> _tvs = new();
        bool _finished;

        void Start()
        {
            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Flat;
            RenderSettings.ambientLight = new Color(0.95f, 0.97f, 1f) * 1.4f;
            RenderSettings.fog = true;
            RenderSettings.fogColor = new Color(0.88f, 0.92f, 0.97f);
            RenderSettings.fogMode = FogMode.Exponential;
            RenderSettings.fogDensity = 0.012f;
            RenderSettings.skybox = null;

            var sun = new GameObject("Sun").AddComponent<Light>();
            sun.type = LightType.Directional;
            sun.intensity = 0.9f;
            sun.transform.rotation = Quaternion.Euler(60, 20, 0);

            var white = Mats.WhitePanel();
            float len = ZStart - ZEnd + 8f, cz = (ZStart + ZEnd) * 0.5f, hw = W * 0.5f;
            Build.Solid(transform, new Vector3(W, 0.5f, len), white, new Vector3(0, -0.25f, cz));
            Build.Solid(transform, new Vector3(W, 0.4f, len), white, new Vector3(0, H + 0.2f, cz));
            Build.Solid(transform, new Vector3(W, H, 0.5f), white, new Vector3(0, H * 0.5f, ZStart + 3));
            Build.Solid(transform, new Vector3(W, H, 0.5f), white, new Vector3(0, H * 0.5f, ZEnd - 3));

            // стены: чередование панелей и «окон» (невидимый коллайдер держит внутри)
            for (int side = -1; side <= 1; side += 2)
            {
                float wx = side * hw;
                Build.Collide(transform, new Vector3(0.5f, H, len), new Vector3(wx, H * 0.5f, cz));
                float z = ZStart; bool window = false;
                while (z > ZEnd)
                {
                    float segLen = Mathf.Min(6f, z - ZEnd);
                    float segC = z - segLen * 0.5f;
                    if (window)
                    {
                        Build.MeshBox(transform, new Vector3(0.5f, 1.2f, segLen), white, new Vector3(wx, 0.6f, segC));
                        Build.MeshBox(transform, new Vector3(0.5f, H - 4.4f, segLen), white, new Vector3(wx, 4.4f + (H - 4.4f) * 0.5f, segC));
                    }
                    else Build.MeshBox(transform, new Vector3(0.5f, H, segLen), white, new Vector3(wx, H * 0.5f, segC));
                    z -= segLen; window = !window;
                }
            }

            // световые полосы на потолке
            for (float z = ZStart - 4; z > ZEnd + 2; z -= 8)
                Build.MeshBox(transform, new Vector3(W - 3, 0.08f, 0.8f), Mats.Neon(Color.white, 2f), new Vector3(0, H - 0.05f, z));

            foreach (var (txt, z) in new[] { ("ГРИД ОСВОБОЖДЁН", ZStart - 6f), ("ВСЯ ИНФОРМАЦИЯ УКРАДЕНА", 8f), ("ЯДРО РАЗРУШЕНО", -22f) })
            {
                var l = Build.Label(transform, txt, new Vector3(0, 4.6f, z), 5.4f, new Color(0.45f, 0.6f, 0.75f, 0.85f), false);
                l.transform.rotation = Quaternion.Euler(0, 180, 0);
            }

            // телевизоры за окнами
            var rng = new System.Random(777);
            float R(float a, float b) => Mathf.Lerp(a, b, (float)rng.NextDouble());
            for (int i = 0; i < 16; i++)
            {
                float side = i % 2 == 0 ? -1 : 1;
                var root = new GameObject("tv").transform;
                root.SetParent(transform, false);
                float baseY = R(1.5f, 5f);
                root.localPosition = new Vector3(side * R(9, 20), baseY, R(ZEnd, ZStart));
                Build.MeshBox(root, new Vector3(1.9f, 1.3f, 0.5f), Mats.Plastic(new Color(0.2f, 0.21f, 0.24f)), Vector3.zero);
                Build.MeshBox(root, new Vector3(1.6f, 1f, 0.1f), Mats.Neon(new Color(0.75f, 0.9f, 1f), 1.6f), new Vector3(0, 0, 0.3f));
                var lbl = Build.Label(root, TvTexts[i % TvTexts.Length], new Vector3(0, 0, 0.4f), 2.6f, new Color(0.1f, 0.25f, 0.4f), false);
                lbl.transform.localRotation = Quaternion.Euler(0, 180, 0);
                root.rotation = Quaternion.Euler(0, side > 0 ? -90 : 90, 0);
                _tvs.Add((root, baseY, R(1.2f, 3f), R(0, Mathf.PI * 2)));
            }

            // конец пути: обычный вход на сервер
            var endPos = new Vector3(0, 0, ZEnd + 3);
            Build.Solid(transform, new Vector3(1.7f, 2.6f, 1.2f), Mats.MetalDark(0.45f), endPos + Vector3.up * 1.3f);
            Build.MeshBox(transform, Vector3.one * 0.5f, Mats.Neon(GameData.INFECTED, 2f), endPos + Vector3.up * 3f);
            Build.Label(transform, "ВХОД НА СЕРВЕР\n[E] — конец игры", endPos + Vector3.up * 4.4f, 3.6f, GameData.INFECTED);

            var go = new GameObject("Player", typeof(CharacterController), typeof(Player.VirusPlayer));
            _player = go.GetComponent<Player.VirusPlayer>();
            go.transform.position = new Vector3(0, 1.2f, ZStart - 2);

            var it = new GameObject("end").AddComponent<Interactable>();
            it.transform.SetParent(transform, false);
            it.transform.position = endPos + Vector3.up * 1f;
            it.radius = 4f;
            it.prompt = "[E] ВОЙТИ НА СЕРВЕР — конец игры";
            it.onInteract = FinishGame;
        }

        void Update()
        {
            float t = Time.time;
            foreach (var (tr, baseY, speed, phase) in _tvs)
            {
                var p = tr.localPosition;
                p.z += speed * Time.deltaTime;
                if (p.z > ZStart + 4) p.z = ZEnd - 4;
                p.y = baseY + Mathf.Sin(t * 0.8f + phase) * 0.5f;
                tr.localPosition = p;
            }
        }

        void FinishGame()
        {
            if (_finished) return;
            _finished = true;
            _player.controlEnabled = false;
            Cursor.lockState = CursorLockMode.None;
            Cursor.visible = true;

            var s = GameState.I;
            var canvasGo = new GameObject("End", typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
            canvasGo.GetComponent<Canvas>().renderMode = RenderMode.ScreenSpaceOverlay;
            canvasGo.GetComponent<Canvas>().sortingOrder = 60;
            var dim = new GameObject("dim", typeof(RectTransform)).AddComponent<Image>();
            dim.transform.SetParent(canvasGo.transform, false);
            dim.rectTransform.anchorMin = Vector2.zero; dim.rectTransform.anchorMax = Vector2.one;
            dim.rectTransform.offsetMin = Vector2.zero; dim.rectTransform.offsetMax = Vector2.zero;
            dim.color = new Color(0.9f, 0.94f, 0.97f, 0.92f);

            T(canvasGo.transform, "КОНЕЦ ИГРЫ", new Vector2(0, 130), 48, new Color(0.05f, 0.35f, 0.3f));
            T(canvasGo.transform, "Oracle dead · Where lost data · GG", new Vector2(0, 70), 24, new Color(0.15f, 0.2f, 0.3f));
            T(canvasGo.transform, $"28 серверов, Оракул разрушен, данные украдены.\nData Fragments: {s.resources["data_fragments"]} · Code: {s.resources["code_samples"]} · Mutagen: {s.resources["mutagen"]}",
                new Vector2(0, 10), 20, new Color(0.25f, 0.3f, 0.4f));

            var btnGo = new GameObject("btn", typeof(RectTransform));
            btnGo.transform.SetParent(canvasGo.transform, false);
            btnGo.GetComponent<RectTransform>().sizeDelta = new Vector2(360, 56);
            btnGo.GetComponent<RectTransform>().anchoredPosition = new Vector2(0, -90);
            btnGo.AddComponent<Image>().color = new Color(0.1f, 0.45f, 0.4f, 0.95f);
            var btn = btnGo.AddComponent<Button>();
            btn.onClick.AddListener(() => App.SceneFlow.GoMenu());
            T(btnGo.transform, "В ГЛАВНОЕ МЕНЮ", Vector2.zero, 22, Color.white);
        }

        static void T(Transform parent, string s, Vector2 pos, int size, Color c)
        {
            var go = new GameObject("t", typeof(RectTransform));
            go.transform.SetParent(parent, false);
            var t = go.AddComponent<Text>();
            t.font = Build.UIFont; t.text = s; t.fontSize = size; t.color = c;
            t.alignment = TextAnchor.MiddleCenter;
            t.horizontalOverflow = HorizontalWrapMode.Overflow;
            t.verticalOverflow = VerticalWrapMode.Overflow;
            t.rectTransform.anchoredPosition = pos;
            t.rectTransform.sizeDelta = new Vector2(1200, 80);
        }
    }
}
