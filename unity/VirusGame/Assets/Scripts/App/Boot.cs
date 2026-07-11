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
            _t -= Time.deltaTime;
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
            if (System.Array.IndexOf(args, "-autogrid") >= 0)
            { GameState.I.NewCampaign(); SceneFlow.GoGrid(); return; }
            if (System.Array.IndexOf(args, "-autoraid") >= 0)
            { GameState.I.NewCampaign(); GameState.I.StartHack(GameState.I.gridNodes[0]); SceneFlow.EnterRaid(); return; }
            if (System.Array.IndexOf(args, "-autovictory") >= 0)
            { GameState.I.NewCampaign(); SceneFlow.GoVictory(); return; }

            Cursor.lockState = CursorLockMode.None;
            Cursor.visible = true;

            var cam = new GameObject("Camera", typeof(Camera));
            cam.tag = "MainCamera";
            cam.GetComponent<Camera>().clearFlags = CameraClearFlags.SolidColor;
            cam.GetComponent<Camera>().backgroundColor = new Color(0.012f, 0.02f, 0.045f);
            PostFx.AttachCamera(cam.GetComponent<Camera>());
            PostFx.EnsureVolume();

            var canvasGo = new GameObject("Menu", typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
            canvasGo.GetComponent<Canvas>().renderMode = RenderMode.ScreenSpaceOverlay;
            var scaler = canvasGo.GetComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1600, 900);

            // курсорные события UI требуют EventSystem — добавляем
            if (FindFirstObjectByType<UnityEngine.EventSystems.EventSystem>() == null)
                new GameObject("EventSystem", typeof(UnityEngine.EventSystems.EventSystem),
                    typeof(UnityEngine.EventSystems.StandaloneInputModule));

            UI.UIKit.Panel(canvasGo.transform, new Vector2(0.5f, 0.5f), new Vector2(0, 170),
                new Vector2(1180, 240), UI.UIKit.PanelBg);
            T(canvasGo.transform, "VIRUS // PANIC PROTOCOL", new Vector2(0, 220), 56, new Color(0.21f, 0.85f, 1f));
            T(canvasGo.transform,
                "Ты — полиморфный вирус, проснувшийся в тренировочном Гриде.\n" +
                "Впереди: ночной мегаполис, затхлые офисы и военный бункер — 28 серверов,\n" +
                "которые нужно заразить, чтобы открыть путь к ОРАКУЛУ — ядру всей сети.\n" +
                "Укради его данные, разрушь сервер и сбеги в белый туннель.",
                new Vector2(0, 110), 21, new Color(0.6f, 0.75f, 0.85f));

            Btn(canvasGo.transform, "НОВАЯ КАМПАНИЯ", new Vector2(0, -30), () =>
            {
                GameState.I.NewCampaign();
                SceneFlow.GoGrid();
            });
            Btn(canvasGo.transform, "КООП: СОЗДАТЬ СТАЮ (LAN)", new Vector2(-210, -95), () =>
            {
                GameState.I.NewCampaign();
                Net.NetManager.StartHost();
                SceneFlow.GoGrid();
            });
            Btn(canvasGo.transform, "КООП: ВОЙТИ (LAN / -join <ip>)", new Vector2(-210, -160), () =>
            {
                GameState.I.NewCampaign();
                Net.NetManager.StartClient("127.0.0.1");
                SceneFlow.GoGrid();
            });
            // Steam-кнопки живут только при работающем Steam-клиенте
            if (Net.NetManager.SteamReady)
            {
                Btn(canvasGo.transform, "КООП: STEAM — СОЗДАТЬ ЛОББИ", new Vector2(210, -95), () =>
                {
                    GameState.I.NewCampaign();
                    Net.NetManager.StartSteamHost();
                    SceneFlow.GoGrid();
                });
                Btn(canvasGo.transform, "КООП: STEAM — НАЙТИ ЛОББИ", new Vector2(210, -160), () =>
                {
                    GameState.I.NewCampaign();
                    Net.NetManager.JoinSteamLobby();
                    SceneFlow.GoGrid();
                });
            }
            else
                T(canvasGo.transform, "Steam не запущен — кооп через Steam недоступен",
                    new Vector2(210, -128), 15, new Color(0.4f, 0.5f, 0.6f));
            if (GameState.I.gridNodes.Count > 0 && GameState.I.InfectedTotal() > 0 && !GameState.I.campaignWon)
                Btn(canvasGo.transform, "ПРОДОЛЖИТЬ", new Vector2(0, -225), SceneFlow.GoGrid);
            Btn(canvasGo.transform, "ВЫХОД", new Vector2(0, -290), Application.Quit);
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
