using UnityEngine;
using UnityEngine.UI;
using Virus.Core;
using Virus.Util;

namespace Virus.UI
{
    // HUD на UIKit: панели со скруглениями, настоящие полосы ДОБЫЧА/ТРЕВОГА/BW,
    // пипсы HP, слоты активок с кулдаун-заливкой, чипы цели/тоста/подсказки.
    public class Hud : MonoBehaviour
    {
        public bool raidMode = false;

        Canvas _canvas;
        Image _statusPanel;
        Text _title, _res;
        UIKit.Bar _accessBar, _alarmBar, _bwBar, _gridBar;
        UIKit.Pips _hp;
        UIKit.Chip _objective, _toast, _prompt, _strain;

        class Slot
        {
            public Image bg, keyBg, cdOverlay;
            public Text key, name, info;
        }
        readonly Slot[] _slots = new Slot[3];
        static readonly string[] SlotKeys = { "Q", "X", "C" };

        World.Level _level;
        float _toastT;
        bool _builtRaid;

        void Awake()
        {
            var canvasGo = new GameObject("HudCanvas", typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
            _canvas = canvasGo.GetComponent<Canvas>();
            _canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            var scaler = canvasGo.GetComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1600, 900);

            BuildCommon();
        }

        void BuildCommon()
        {
            var root = _canvas.transform;
            // чипы: цель (верх-центр), тост (под целью), подсказка [E] (низ-центр)
            _objective = UIKit.MakeChip(root, new Vector2(0.5f, 1), new Vector2(0, -18), 38, 18, UIKit.TextMain);
            _toast = UIKit.MakeChip(root, new Vector2(0.5f, 1), new Vector2(0, -64), 40, 19, UIKit.Good, UIKit.PanelBg2);
            _prompt = UIKit.MakeChip(root, new Vector2(0.5f, 0), new Vector2(0, 96), 44, 21, UIKit.TextMain, UIKit.PanelBg2);
            // штамм (верх-право)
            _strain = UIKit.MakeChip(root, new Vector2(1, 1), new Vector2(-24, -18), 34, 17, UIKit.Accent);
        }

        // ── верх-лево: статус рейда или Грида ──
        void BuildStatus(bool raid)
        {
            if (_statusPanel != null) Destroy(_statusPanel.gameObject);
            var root = _canvas.transform;
            _statusPanel = UIKit.Panel(root, new Vector2(0, 1), new Vector2(24, -18),
                new Vector2(354, raid ? 128 : 100), UIKit.PanelBg);
            var p = _statusPanel.transform;
            _title = UIKit.Label(p, "", new Vector2(0, 1), new Vector2(14, -10), 15, UIKit.TextDim);
            if (raid)
            {
                _accessBar = UIKit.MakeBar(p, new Vector2(14, -32), 326, 24, "ДОБЫЧА", UIKit.Good);
                _alarmBar = UIKit.MakeBar(p, new Vector2(14, -62), 326, 24, "ТРЕВОГА", UIKit.Warn);
                _hp = UIKit.MakePips(p, new Vector2(20, -100));
                _res = UIKit.Label(p, "", new Vector2(1, 1), new Vector2(-14, -100), 15, UIKit.TextDim, TextAnchor.UpperRight);
            }
            else
            {
                _gridBar = UIKit.MakeBar(p, new Vector2(14, -32), 326, 26, "ЗАРАЖЕНИЕ", UIKit.Accent);
                _res = UIKit.Label(p, "", new Vector2(0, 1), new Vector2(14, -72), 16, UIKit.TextDim);
            }

            // низ-лево: BW и слоты активок — только в рейде
            if (raid)
            {
                var bwPanel = UIKit.Panel(root, new Vector2(0, 0), new Vector2(24, 20), new Vector2(354, 46), UIKit.PanelBg);
                _bwBar = UIKit.MakeBar(bwPanel.transform, new Vector2(12, -9), 330, 28, "BW", UIKit.Accent);
                for (int i = 0; i < 3; i++)
                {
                    var s = new Slot();
                    s.bg = UIKit.Panel(root, new Vector2(0, 0), new Vector2(24 + i * 122, 74), new Vector2(116, 52), UIKit.PanelBg);
                    s.keyBg = UIKit.Panel(s.bg.transform, new Vector2(0, 0.5f), new Vector2(8, 0), new Vector2(30, 30), UIKit.BarBack);
                    s.key = UIKit.Label(s.keyBg.transform, SlotKeys[i], new Vector2(0.5f, 0.5f), Vector2.zero, 16, UIKit.Accent, TextAnchor.MiddleCenter, true);
                    s.name = UIKit.Label(s.bg.transform, "—", new Vector2(0, 1), new Vector2(46, -9), 13, UIKit.TextMain);
                    s.info = UIKit.Label(s.bg.transform, "", new Vector2(0, 0), new Vector2(46, 9), 12, UIKit.TextDim);
                    s.cdOverlay = UIKit.Panel(s.bg.transform, new Vector2(0, 0.5f), new Vector2(2, 0), new Vector2(112, 48), new Color(0, 0, 0, 0.55f));
                    s.cdOverlay.gameObject.SetActive(false);
                    _slots[i] = s;
                }
            }
            _builtRaid = raid;
        }

        void Update()
        {
            var s = GameState.I;
            if (s == null) return;
            if (_statusPanel == null || _builtRaid != raidMode) BuildStatus(raidMode);

            var info = s.MyClassInfo();
            var r = s.resources;
            string resLine = $"◈ {r["data_fragments"]}   ◇ {r["code_samples"]}   ✦ {r["mutagen"]}";

            if (raidMode && s.raid != null)
            {
                string evac = s.evacOpen ? $"   ·   ЭВАКУАЦИЯ {Mathf.Max((int)s.evacLeft, 0)}с" : "";
                _title.text = $"{s.raid.name} · {GameData.TIERS[s.raid.tier].shortName} · {s.raid.av}{evac}";
                _title.color = s.evacOpen ? UIKit.Warn : UIKit.TextDim;

                _accessBar.Set(s.access / 100f);
                _accessBar.value.text = $"{Mathf.Min((int)s.access, 999)}%";

                int ph = s.AlarmPhase();
                var alarmCol = ph switch
                {
                    3 => UIKit.Bad,
                    2 => new Color(1f, 0.45f, 0.25f),
                    1 => UIKit.Warn,
                    _ => new Color(0.45f, 0.6f, 0.72f),
                };
                _alarmBar.Set(s.alarm / 100f, alarmCol);
                _alarmBar.value.text = $"{(int)s.alarm}% · {s.AlarmPhaseName()}";

                _hp.Set(s.myHp, s.myMaxHp);
                _res.text = resLine;

                _bwBar.Set(s.bandwidth / Mathf.Max(s.maxBandwidth, 1f));
                _bwBar.value.text = $"{(int)s.bandwidth}/{(int)s.maxBandwidth}";
                UpdateSlots(s);
                _strain.Set($"{info.name} · УР.{s.virusLevel}");
            }
            else
            {
                _title.text = "СЕТЬ ГРИДА · зачисти зону — откроется следующая";
                _gridBar.Set(s.TotalNodes() > 0 ? (float)s.InfectedTotal() / s.TotalNodes() : 0f);
                _gridBar.value.text = $"{s.InfectedTotal()} / {s.TotalNodes()}";
                _res.text = resLine;
                _strain.Set($"{info.name} · УР.{s.virusLevel} · [Tab] эволюция");
            }
            if (_strain.text != null) _strain.text.color = info.color;

            if (_toastT > 0f)
            {
                _toastT -= Time.deltaTime;
                if (_toastT <= 0f) _toast.Set("");
            }
        }

        void UpdateSlots(GameState s)
        {
            if (_level == null) _level = FindFirstObjectByType<World.Level>();
            float cd = _level != null ? _level.AbilityCooldown : 0f;
            float cdMax = Mathf.Max(8f - s.EvoBonus("cooldown"), 1f);
            for (int i = 0; i < 3; i++)
            {
                var slot = _slots[i];
                if (slot == null) continue;
                if (i < s.activeAbilities.Count)
                {
                    var ab = GameData.ABILITIES[s.activeAbilities[i]];
                    slot.name.text = ab.name;
                    slot.name.color = UIKit.TextMain;
                    slot.info.text = cd > 0f ? $"кд {cd:0.0}с" : $"{(int)s.AbilityCost(s.activeAbilities[i])} BW";
                    bool cool = cd > 0f;
                    if (slot.cdOverlay.gameObject.activeSelf != cool) slot.cdOverlay.gameObject.SetActive(cool);
                    if (cool) slot.cdOverlay.rectTransform.sizeDelta =
                        new Vector2(112f * Mathf.Clamp01(cd / cdMax), 48f);
                }
                else
                {
                    bool unlockable = i < s.MaxAbilitySlots();
                    slot.name.text = unlockable ? "пусто" : $"УР.{i + 1}";
                    slot.name.color = UIKit.TextDim;
                    slot.info.text = unlockable ? "[Tab] в Гриде" : "заперто";
                    slot.cdOverlay.gameObject.SetActive(false);
                }
            }
        }

        public void SetPrompt(string text) => _prompt?.Set(text);
        public void SetObjective(string text) => _objective?.Set(text);

        public void Toast(string text)
        {
            if (_toast == null) return;
            _toast.Set(text);
            _toastT = 3.2f;
        }
    }
}
