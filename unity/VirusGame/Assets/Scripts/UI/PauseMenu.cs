using UnityEngine;
using UnityEngine.UI;
using Virus.Core;
using Virus.Util;

namespace Virus.UI
{
    // Меню паузы по ESC: продолжить / покинуть рейд (провал) / меню / выход.
    // В одиночке останавливает время; в коопе мир живёт дальше.
    public class PauseMenu : MonoBehaviour
    {
        public static bool IsOpen { get; private set; }

        GameObject _root;
        Player.VirusPlayer _player;
        bool _pausedTime;
        float _openT;

        public static void Toggle()
        {
            if (IsOpen)
            {
                var m = FindFirstObjectByType<PauseMenu>();
                if (m != null) m.Close();
                return;
            }
            if (PuzzleUI.IsOpen || EvolutionUI.IsOpen) return;
            new GameObject("PauseMenu", typeof(PauseMenu));
        }

        void Awake()
        {
            IsOpen = true;
            _openT = Time.unscaledTime;
            _player = FindFirstObjectByType<Player.VirusPlayer>();
            if (_player != null) _player.controlEnabled = false;
            Cursor.lockState = CursorLockMode.None;
            Cursor.visible = true;

            bool coop = Net.NetManager.Active;
            if (!coop) { Time.timeScale = 0f; _pausedTime = true; }

            bool inRaid = FindFirstObjectByType<World.Level>() != null;
            string scene = UnityEngine.SceneManagement.SceneManager.GetActiveScene().name;

            _root = new GameObject("PauseCanvas", typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
            var canvas = _root.GetComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = 95;
            var scaler = _root.GetComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1600, 900);

            // затемнение + карточка
            var dim = new GameObject("dim", typeof(RectTransform)).AddComponent<Image>();
            dim.transform.SetParent(_root.transform, false);
            dim.rectTransform.anchorMin = Vector2.zero;
            dim.rectTransform.anchorMax = Vector2.one;
            dim.rectTransform.offsetMin = Vector2.zero;
            dim.rectTransform.offsetMax = Vector2.zero;
            dim.color = new Color(0, 0.01f, 0.02f, 0.7f);

            var card = UIKit.Panel(_root.transform, new Vector2(0.5f, 0.5f), Vector2.zero,
                new Vector2(440, inRaid ? 330 : 290), UIKit.PanelBg2);
            UIKit.Label(card.transform, "ПАУЗА", new Vector2(0.5f, 1), new Vector2(0, -30), 30,
                UIKit.Accent, TextAnchor.MiddleCenter, true);
            if (coop)
                UIKit.Label(card.transform, "кооп: мир продолжает жить", new Vector2(0.5f, 1),
                    new Vector2(0, -60), 14, UIKit.TextDim, TextAnchor.MiddleCenter);

            float y = -105f;
            UIKit.MakeButton(card.transform, "ПРОДОЛЖИТЬ", new Vector2(0, card.rectTransform.sizeDelta.y * 0.5f + y),
                new Vector2(360, 50), Close, UIKit.Good);
            y -= 62f;
            if (inRaid)
            {
                UIKit.MakeButton(card.transform, "ПОКИНУТЬ РЕЙД (провал)", new Vector2(0, card.rectTransform.sizeDelta.y * 0.5f + y),
                    new Vector2(360, 50), AbortRaid, UIKit.Warn);
                y -= 62f;
            }
            else if (scene != "MainMenu")
            {
                UIKit.MakeButton(card.transform, "ГЛАВНОЕ МЕНЮ", new Vector2(0, card.rectTransform.sizeDelta.y * 0.5f + y),
                    new Vector2(360, 50), () => { Close(); App.SceneFlow.GoMenu(); }, UIKit.Accent);
                y -= 62f;
            }
            UIKit.MakeButton(card.transform, "ВЫЙТИ ИЗ ИГРЫ", new Vector2(0, card.rectTransform.sizeDelta.y * 0.5f + y),
                new Vector2(360, 50), Application.Quit, UIKit.Bad);
        }

        void AbortRaid()
        {
            Close();
            var level = FindFirstObjectByType<World.Level>();
            if (level != null) level.Abort();
        }

        void Update()
        {
            // защита от закрытия тем же нажатием ESC, что открыло меню
            if (Time.unscaledTime - _openT > 0.15f && Input.GetKeyDown(KeyCode.Escape)) Close();
        }

        void Close()
        {
            if (!IsOpen) return;
            IsOpen = false;
            if (_pausedTime) Time.timeScale = 1f;
            if (_player != null) _player.controlEnabled = true;
            Cursor.lockState = CursorLockMode.Locked;
            Cursor.visible = false;
            Destroy(_root);
            Destroy(gameObject);
        }

        void OnDestroy()
        {
            if (IsOpen) { IsOpen = false; if (_pausedTime) Time.timeScale = 1f; }
        }
    }
}
