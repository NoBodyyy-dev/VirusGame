using UnityEngine;
using UnityEngine.UI;
using Virus.Core;
using Virus.Util;

namespace Virus.App
{
    // Бутстрапы сцен (порт _ready корневых нод Godot): каждый строит свою
    // сцену процедурно. GameState — персистентный синглтон.
    // -shot <префикс>: игра сама сохраняет свои кадры (для автопроверки
    // рендера без захвата чужого экрана; окно может быть перекрыто).
    public class AutoShot : MonoBehaviour
    {
        public string prefix = "shot";
        float _t = 6f;   // первый кадр — через 6с (мир успел построиться)
        int _n;

        void Update()
        {
            _t -= Time.unscaledDeltaTime;   // работает и на паузе (timeScale 0)
            if (_t <= 0f && _n < 5)
            {
                _t = 6f;
                ScreenCapture.CaptureScreenshot($"{prefix}_{_n++}.png");
            }
        }
    }

    static class BootCommon
    {
        public static void EnsureState()
        {
            Application.runInBackground = true;   // кооп/автотесты: не замирать без фокуса
            if (GameStateBehaviour.I == null)
                new GameObject("GameState", typeof(GameStateBehaviour));
            var args = System.Environment.GetCommandLineArgs();
            int shotAt = System.Array.IndexOf(args, "-shot");
            if (shotAt >= 0 && Object.FindFirstObjectByType<AutoShot>() == null)
            {
                var shot = new GameObject("AutoShot", typeof(AutoShot)).GetComponent<AutoShot>();
                shot.prefix = shotAt + 1 < args.Length ? args[shotAt + 1] : "shot";
                Object.DontDestroyOnLoad(shot.gameObject);
            }
            // кнопки uGUI (головоломка, результаты, меню) требуют EventSystem
            if (Object.FindFirstObjectByType<UnityEngine.EventSystems.EventSystem>() == null)
                new GameObject("EventSystem", typeof(UnityEngine.EventSystems.EventSystem),
                    typeof(UnityEngine.EventSystems.StandaloneInputModule));
        }

        public static UI.Hud Hud(bool raid = false)
        {
            var hud = new GameObject("HUD", typeof(UI.Hud)).GetComponent<UI.Hud>();
            hud.raidMode = raid;
            var im = new GameObject("Interactions", typeof(InteractionManager)).GetComponent<InteractionManager>();
            im.setPrompt = hud.SetPrompt;
            return hud;
        }
    }

    // Сцена GridWorld
    public class Boot : MonoBehaviour
    {
        void Awake()
        {
            BootCommon.EnsureState();
            BootCommon.Hud();
            new GameObject("GridWorld", typeof(World.GridWorld));
        }
    }

    // Сцена Level (рейд)
    public class LevelBoot : MonoBehaviour
    {
        void Awake()
        {
            BootCommon.EnsureState();
            BootCommon.Hud(raid: true);
            new GameObject("Level", typeof(World.Level));
        }
    }

    // Сцена VictoryTunnel
    public class VictoryBoot : MonoBehaviour
    {
        void Awake()
        {
            BootCommon.EnsureState();
            BootCommon.Hud();
            new GameObject("VictoryTunnel", typeof(World.VictoryTunnel));
        }
    }

    // Сцена MainMenu: сюжет и старт кампании
    public class MenuBoot : MonoBehaviour
    {
        void Awake()
        {
            BootCommon.EnsureState();

            // отладочный автозапуск сцен (аналог autostart-аргументов Godot)
            var args = System.Environment.GetCommandLineArgs();
            if (System.Array.IndexOf(args, "-host") >= 0)
            { GameState.I.NewCampaign(); Net.NetManager.StartHost(); SceneFlow.GoGrid(); return; }
            if (System.Array.IndexOf(args, "-steamhost") >= 0)
            { GameState.I.NewCampaign(); Net.NetManager.StartSteamHost(); SceneFlow.GoGrid(); return; }
            if (System.Array.IndexOf(args, "-steamjoin") >= 0)
            { GameState.I.NewCampaign(); Net.NetManager.JoinSteamLobby(); SceneFlow.GoGrid(); return; }
            int joinAt = System.Array.IndexOf(args, "-join");
            if (joinAt >= 0)
            {
                GameState.I.NewCampaign();
                Net.NetManager.StartClient(joinAt + 1 < args.Length ? args[joinAt + 1] : "127.0.0.1");
                SceneFlow.GoGrid();
                return;
            }
            if (System.Array.IndexOf(args, "-continue") >= 0)
            { SaveSystem.Load(); SceneFlow.GoGrid(); return; }
            if (System.Array.IndexOf(args, "-autogrid") >= 0)
            { GameState.I.NewCampaign(); SceneFlow.GoGrid(); return; }
            if (System.Array.IndexOf(args, "-autoraid") >= 0)
            { GameState.I.NewCampaign(); GameState.I.StartHack(GameState.I.gridNodes[0]); SceneFlow.EnterRaid(); return; }
            if (System.Array.IndexOf(args, "-autovictory") >= 0)
            { GameState.I.NewCampaign(); SceneFlow.GoVictory(); return; }

            Cursor.lockState = CursorLockMode.None;
            Cursor.visible = true;

            BuildBackdrop();
            BuildMenuUI();
            StartCoroutine(FadeIn());
        }

        // ── живой 3D-фон: вирион-апекс на пьедестале, неон, мотыльки данных ──
        void BuildBackdrop()
        {
            var camGo = new GameObject("Camera", typeof(Camera), typeof(AudioListener));
            camGo.tag = "MainCamera";
            var cam = camGo.GetComponent<Camera>();
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = new Color(0.008f, 0.014f, 0.03f);
            cam.fieldOfView = 46f;
            camGo.transform.position = new Vector3(0.4f, 1.7f, -4.2f);
            camGo.transform.rotation = Quaternion.LookRotation(
                new Vector3(1.1f, 1.15f, 0f) - camGo.transform.position);
            PostFx.AttachCamera(cam);
            PostFx.EnsureVolume();

            RenderSettings.fog = true;
            RenderSettings.fogColor = new Color(0.02f, 0.03f, 0.06f);
            RenderSettings.fogMode = FogMode.Exponential;
            RenderSettings.fogDensity = 0.06f;
            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Trilight;
            RenderSettings.ambientSkyColor = new Color(0.16f, 0.22f, 0.32f);
            RenderSettings.ambientEquatorColor = new Color(0.1f, 0.13f, 0.2f);
            RenderSettings.ambientGroundColor = new Color(0.04f, 0.05f, 0.08f);

            var root = new GameObject("Backdrop").transform;
            // пьедестал и глянцевый пол
            Build.Prim(PrimitiveType.Cylinder, root, new Vector3(1.7f, 0.07f, 1.7f),
                Mats.Metal(new Color(0.2f, 0.24f, 0.3f), 0.15f), new Vector3(1.1f, 0.07f, 0f));
            Build.Prim(PrimitiveType.Cylinder, root, new Vector3(12f, 0.02f, 12f),
                Mats.Metal(new Color(0.07f, 0.09f, 0.13f), 0.12f), new Vector3(0.5f, 0f, 1f));
            // герой сцены: вирион-апекс, медленно вращается
            BuildHeroVirion(root);
            // неоновая подсветка: холодный ключевой + тёплый контровой
            Build.Omni(root, new Vector3(2.6f, 2.6f, -1.8f), new Color(0.25f, 0.85f, 1f), 2.4f, 9f);
            Build.Omni(root, new Vector3(-0.6f, 1.9f, 2.2f), new Color(1f, 0.45f, 0.75f), 1.5f, 8f);
            Build.Omni(root, new Vector3(1.1f, 3.4f, 0f), new Color(0.9f, 0.95f, 1f), 0.8f, 6f);
            Fx.DataMotes(root, new Vector3(0.8f, 1.6f, 0.5f), new Vector3(7f, 3.6f, 5f),
                new Color(0.25f, 0.85f, 1f), 16f);
            Sfx.Ambient("wind", 0.1f);
        }

        // ── UI: левая колонка (титул, кнопки, сюжет), карточка кампании ──
        void BuildMenuUI()
        {
            var canvasGo = new GameObject("Menu", typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
            canvasGo.GetComponent<Canvas>().renderMode = RenderMode.ScreenSpaceOverlay;
            var scaler = canvasGo.GetComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1600, 900);

            if (FindFirstObjectByType<UnityEngine.EventSystems.EventSystem>() == null)
                new GameObject("EventSystem", typeof(UnityEngine.EventSystems.EventSystem),
                    typeof(UnityEngine.EventSystems.StandaloneInputModule));

            // колонка на всю высоту + светящаяся кромка
            var col = new GameObject("col", typeof(RectTransform));
            col.transform.SetParent(canvasGo.transform, false);
            var colImg = col.AddComponent<Image>();
            colImg.color = new Color(0.016f, 0.035f, 0.06f, 0.88f);
            colImg.raycastTarget = false;
            var crt = colImg.rectTransform;
            crt.anchorMin = new Vector2(0, 0); crt.anchorMax = new Vector2(0, 1);
            crt.pivot = new Vector2(0, 0.5f);
            crt.anchoredPosition = Vector2.zero;
            crt.sizeDelta = new Vector2(560, 0);
            var edge = new GameObject("edge", typeof(RectTransform));
            edge.transform.SetParent(canvasGo.transform, false);
            var eimg = edge.AddComponent<Image>();
            eimg.color = new Color(UI.UIKit.Accent.r, UI.UIKit.Accent.g, UI.UIKit.Accent.b, 0.35f);
            eimg.raycastTarget = false;
            var ert = eimg.rectTransform;
            ert.anchorMin = new Vector2(0, 0); ert.anchorMax = new Vector2(0, 1);
            ert.pivot = new Vector2(0, 0.5f);
            ert.anchoredPosition = new Vector2(560, 0);
            ert.sizeDelta = new Vector2(2, 0);

            // титул
            UI.UIKit.Label(col.transform, "VIRUS", new Vector2(0.5f, 0.5f), new Vector2(-215, 330), 88, UI.UIKit.Accent, TextAnchor.MiddleLeft, true);
            UI.UIKit.Label(col.transform, "PANIC PROTOCOL", new Vector2(0.5f, 0.5f), new Vector2(-212, 262), 26, UI.UIKit.TextDim, TextAnchor.MiddleLeft);
            UI.UIKit.Panel(col.transform, new Vector2(0.5f, 0.5f), new Vector2(-90, 236), new Vector2(250, 4), UI.UIKit.Accent);

            // кнопки: кампания → кооп → выход
            float y = 150f;
            bool memProgress = GameState.I.gridNodes.Count > 0 && GameState.I.InfectedTotal() > 0 && !GameState.I.campaignWon;
            if (memProgress || SaveSystem.HasSave)
            {
                MenuBtn(col.transform, "ПРОДОЛЖИТЬ КАМПАНИЮ", new Vector2(0, y), () =>
                {
                    if (!memProgress) SaveSystem.Load();
                    SceneFlow.GoGrid();
                }, UI.UIKit.Good);
                y -= 62f;
            }
            MenuBtn(col.transform, "НОВАЯ КАМПАНИЯ", new Vector2(0, y), () =>
            {
                SaveSystem.Delete();   // старый сейв стирается осознанно
                GameState.I.NewCampaign();
                SceneFlow.GoGrid();
            });
            y -= 78f;
            UI.UIKit.Label(col.transform, "КООПЕРАТИВ · стая до 8 штаммов", new Vector2(0.5f, 0.5f), new Vector2(-215, y + 6f), 14, UI.UIKit.TextDim, TextAnchor.MiddleLeft);
            y -= 34f;
            MenuBtn(col.transform, "СОЗДАТЬ СТАЮ", new Vector2(0, y), () =>
            {
                GameState.I.NewCampaign();
                Net.NetManager.StartHost();
                SceneFlow.GoGrid();
            }, null, "LAN");
            y -= 62f;
            MenuBtn(col.transform, "ВОЙТИ В СТАЮ", new Vector2(0, y), () =>
            {
                GameState.I.NewCampaign();
                Net.NetManager.StartClient("127.0.0.1");
                SceneFlow.GoGrid();
            }, null, "LAN · -join <ip>");
            y -= 62f;
            if (Net.NetManager.SteamReady)
            {
                MenuBtn(col.transform, "СОЗДАТЬ ЛОББИ", new Vector2(0, y), () =>
                {
                    GameState.I.NewCampaign();
                    Net.NetManager.StartSteamHost();
                    SceneFlow.GoGrid();
                }, null, "STEAM");
                y -= 62f;
                MenuBtn(col.transform, "НАЙТИ ЛОББИ", new Vector2(0, y), () =>
                {
                    GameState.I.NewCampaign();
                    Net.NetManager.JoinSteamLobby();
                    SceneFlow.GoGrid();
                }, null, "STEAM");
                y -= 62f;
            }
            else
            {
                UI.UIKit.Label(col.transform, "Steam не запущен — Steam-кооп недоступен", new Vector2(0.5f, 0.5f), new Vector2(-215, y + 10f), 13, new Color(0.4f, 0.5f, 0.6f), TextAnchor.MiddleLeft);
                y -= 40f;
            }
            y -= 16f;
            MenuBtn(col.transform, "ВЫХОД", new Vector2(0, y), Application.Quit, UI.UIKit.Bad);

            // сюжет — коротко, внизу колонки
            UI.UIKit.Label(col.transform,
                "Ты — полиморфный вирус в тренировочном Гриде.\n" +
                "Впереди 28 серверов: мегаполис, офисы, бункер —\n" +
                "и ОРАКУЛ, ядро сети. Укради данные и сбеги.",
                new Vector2(0.5f, 0.5f), new Vector2(-215, y - 78f), 14,
                new Color(0.5f, 0.62f, 0.72f), TextAnchor.MiddleLeft);

            // версия
            UI.UIKit.Label(col.transform, "alpha · Unity 6 · PanicWorks", new Vector2(0, 0), new Vector2(24, 18), 12, new Color(0.35f, 0.45f, 0.55f));

            // карточка текущей кампании (справа снизу)
            var pv = memProgress
                ? new SaveSystem.Preview { ok = true, infected = GameState.I.InfectedTotal(),
                    level = GameState.I.virusLevel, branch = GameState.I.branch,
                    bestLoot = GameState.I.records["bestLoot"] }
                : SaveSystem.Peek();
            if (pv.ok)
            {
                var card = UI.UIKit.Panel(canvasGo.transform, new Vector2(1, 0), new Vector2(-36, 36), new Vector2(380, 128), UI.UIKit.PanelBg);
                UI.UIKit.Label(card.transform, "ТЕКУЩАЯ КАМПАНИЯ", new Vector2(0, 1), new Vector2(18, -14), 14, UI.UIKit.TextDim);
                string branchName = pv.branch != "" && GameData.CLASSES.ContainsKey(pv.branch)
                    ? GameData.CLASSES[pv.branch].name : "ПРОТО-ШТАММ";
                UI.UIKit.Label(card.transform, $"{branchName} · УР.{pv.level}", new Vector2(0, 1), new Vector2(18, -42), 20, UI.UIKit.Accent, TextAnchor.UpperLeft, true);
                UI.UIKit.Label(card.transform, $"заражено серверов: {pv.infected} / 31", new Vector2(0, 1), new Vector2(18, -72), 16, UI.UIKit.TextMain);
                UI.UIKit.Label(card.transform, pv.bestLoot > 0 ? $"рекорд добычи: ◈{pv.bestLoot}" : "рекордов пока нет — всё впереди",
                    new Vector2(0, 1), new Vector2(18, -98), 14, UI.UIKit.TextDim);
            }
        }

        System.Collections.IEnumerator FadeIn()
        {
            var canvasGo = new GameObject("Fade", typeof(Canvas));
            var canvas = canvasGo.GetComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = 99;
            var img = new GameObject("dim", typeof(RectTransform)).AddComponent<Image>();
            img.transform.SetParent(canvasGo.transform, false);
            img.rectTransform.anchorMin = Vector2.zero; img.rectTransform.anchorMax = Vector2.one;
            img.rectTransform.offsetMin = Vector2.zero; img.rectTransform.offsetMax = Vector2.zero;
            img.raycastTarget = false;
            float t = 0f;
            while (t < 0.9f)
            {
                t += Time.deltaTime;
                img.color = new Color(0, 0.005f, 0.015f, 1f - Mathf.Clamp01(t / 0.9f));
                yield return null;
            }
            Destroy(canvasGo);
        }

        // пункт меню: слева акцентная полоска и текст, справа приписка (LAN/STEAM)
        static Button MenuBtn(Transform parent, string label, Vector2 pos,
                              UnityEngine.Events.UnityAction action, Color? textCol = null, string hint = null)
        {
            var go = new GameObject("mbtn", typeof(RectTransform));
            go.transform.SetParent(parent, false);
            var img = go.AddComponent<Image>();
            img.sprite = UI.UIKit.Rounded;
            img.type = Image.Type.Sliced;
            img.color = new Color(0.06f, 0.1f, 0.15f, 0.92f);
            var rt = img.rectTransform;
            rt.anchorMin = new Vector2(0.5f, 0.5f); rt.anchorMax = new Vector2(0.5f, 0.5f);
            rt.pivot = new Vector2(0.5f, 0.5f);
            rt.anchoredPosition = pos;
            rt.sizeDelta = new Vector2(450, 54);
            var btn = go.AddComponent<Button>();
            btn.targetGraphic = img;
            var cb = btn.colors;
            cb.normalColor = Color.white;
            cb.highlightedColor = new Color(1.5f, 1.65f, 1.8f, 1f);
            cb.pressedColor = new Color(0.72f, 0.82f, 0.92f, 1f);
            btn.colors = cb;
            btn.onClick.AddListener(action);
            var accent = textCol ?? UI.UIKit.Accent;
            UI.UIKit.Panel(go.transform, new Vector2(0, 0.5f), new Vector2(7, 0), new Vector2(4, 34),
                new Color(accent.r, accent.g, accent.b, 0.9f));
            UI.UIKit.Label(go.transform, label, new Vector2(0, 0.5f), new Vector2(26, 0), 19,
                textCol ?? UI.UIKit.TextMain, TextAnchor.MiddleLeft, true);
            if (hint != null)
                UI.UIKit.Label(go.transform, hint, new Vector2(1, 0.5f), new Vector2(-18, 0), 12,
                    UI.UIKit.TextDim, TextAnchor.MiddleRight);
            return btn;
        }

        // герой меню: классический вирион — глянцевый панцирь, шипы-рецепторы
        // с неоновыми узлами, светящееся ядро сквозь «поры»
        static void BuildHeroVirion(Transform root)
        {
            var hero = new GameObject("Hero");
            hero.transform.SetParent(root, false);
            hero.transform.position = new Vector3(1.1f, 1.35f, 0f);
            hero.AddComponent<SlowSpin>();

            var teal = new Color(0.25f, 0.85f, 1f);
            var shell = Mats.Metal(new Color(0.09f, 0.12f, 0.18f), 0.25f);
            var tip = Mats.Neon(teal, 2.0f);
            var stem = Mats.Neon(teal, 0.8f);

            Build.Prim(PrimitiveType.Sphere, hero.transform, Vector3.one * 1.5f, shell, Vector3.zero);
            // поры-пустулы: маленькие светящиеся точки по панцирю
            var rng = new System.Random(9);
            for (int i = 0; i < 14; i++)
            {
                var d = new Vector3((float)rng.NextDouble() * 2f - 1f, (float)rng.NextDouble() * 2f - 1f,
                    (float)rng.NextDouble() * 2f - 1f).normalized;
                Build.Prim(PrimitiveType.Sphere, hero.transform, Vector3.one * 0.09f, tip, d * 0.74f);
            }
            // шипы-рецепторы по «экватору» и диагоналям
            for (int i = 0; i < 12; i++)
            {
                float a = Mathf.PI * 2f * i / 12f;
                float tiltY = (i % 3 - 1) * 0.55f;
                var dir = new Vector3(Mathf.Cos(a), tiltY, Mathf.Sin(a)).normalized;
                var spike = Build.Prim(PrimitiveType.Capsule, hero.transform,
                    new Vector3(0.09f, 0.24f, 0.09f), stem, dir * 0.92f);
                spike.transform.up = dir;
                Build.Prim(PrimitiveType.Sphere, hero.transform, Vector3.one * 0.15f, tip, dir * 1.16f);
            }
            Build.Omni(hero.transform, Vector3.zero, teal, 1.6f, 4.5f);
        }

        // медленное вращение героя фона
        public class SlowSpin : MonoBehaviour
        {
            void Update() => transform.Rotate(0f, 9f * Time.deltaTime, 0f);
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
            t.rectTransform.sizeDelta = new Vector2(1400, 140);
        }

        static void Btn(Transform parent, string label, Vector2 pos, UnityEngine.Events.UnityAction action) =>
            UI.UIKit.MakeButton(parent, label, pos, new Vector2(420, 54), action);
    }
}
