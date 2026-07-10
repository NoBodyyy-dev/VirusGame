using System.Collections;
using UnityEngine;
using UnityEngine.UI;
using Virus.Core;
using Virus.Util;

namespace Virus.UI
{
    // Порт grid_hud.gd + hud.gd (рейд): ресурсы, прогресс, подсказка [E],
    // тосты, цель; в рейде — полосы ДОБЫЧА/ТРЕВОГА и HP.
    public class Hud : MonoBehaviour
    {
        public bool raidMode = false;

        Text _prompt, _res, _progress, _toast, _objective, _bars, _abilities, _strain;
        World.Level _level;
        float _toastT;

        void Awake()
        {
            var canvasGo = new GameObject("HudCanvas", typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
            var canvas = canvasGo.GetComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            var scaler = canvasGo.GetComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1600, 900);

            _res       = MakeText(canvasGo.transform, new Vector2(0, 0), TextAnchor.LowerLeft, 20, new Vector2(28, 28));
            _progress  = MakeText(canvasGo.transform, new Vector2(0, 1), TextAnchor.UpperLeft, 20, new Vector2(28, -28));
            _bars      = MakeText(canvasGo.transform, new Vector2(0, 1), TextAnchor.UpperLeft, 22, new Vector2(28, -58));
            _objective = MakeText(canvasGo.transform, new Vector2(0.5f, 1), TextAnchor.UpperCenter, 20, new Vector2(0, -24));
            _prompt    = MakeText(canvasGo.transform, new Vector2(0.5f, 0), TextAnchor.LowerCenter, 26, new Vector2(0, 96));
            _toast     = MakeText(canvasGo.transform, new Vector2(0.5f, 1), TextAnchor.UpperCenter, 24, new Vector2(0, -110));
            _toast.color = new Color(0.16f, 0.95f, 0.75f);
            _abilities = MakeText(canvasGo.transform, new Vector2(0, 0), TextAnchor.LowerLeft, 18, new Vector2(28, 58));
            _strain    = MakeText(canvasGo.transform, new Vector2(1, 1), TextAnchor.UpperRight, 20, new Vector2(-28, -28));
        }

        static Text MakeText(Transform parent, Vector2 anchor, TextAnchor align, int size, Vector2 offset)
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
            rt.anchorMin = anchor; rt.anchorMax = anchor;
            rt.pivot = anchor;
            rt.anchoredPosition = offset;
            rt.sizeDelta = new Vector2(1400, 44);
            return t;
        }

        void Update()
        {
            var s = GameState.I;
            if (s == null) return;
            var r = s.resources;
            _res.text = $"Data {r["data_fragments"]}   Code {r["code_samples"]}   Mutagen {r["mutagen"]}";

            var info = s.MyClassInfo();
            if (raidMode && s.raid != null)
            {
                _progress.text = $"{s.raid.name} · {GameData.TIERS[s.raid.tier].shortName} · {s.raid.av}";
                string evac = s.evacOpen ? $"   ЭВАКУАЦИЯ: {Mathf.Max((int)s.evacLeft, 0)}с" : "";
                _bars.text = $"ДОБЫЧА {Mathf.Min((int)s.access, 999)}%   ТРЕВОГА {(int)s.alarm}% [{s.AlarmPhaseName()}]   HP {s.myHp}/{s.myMaxHp}{evac}";
                _bars.color = s.AlarmPhase() >= 2 ? new Color(1f, 0.4f, 0.4f) : new Color(0.88f, 0.95f, 1f);
                _strain.text = $"{info.name} · УР.{s.virusLevel}";
                _strain.color = info.color;
                _abilities.text = AbilityLine(s);
            }
            else
            {
                _progress.text = $"ЗАРАЖЕНИЕ ГРИДА: {s.InfectedTotal()} / {s.TotalNodes()} серверов";
                _bars.text = "";
                _strain.text = $"{info.name} · УР.{s.virusLevel}   [Tab] дерево эволюции";
                _strain.color = info.color;
                _abilities.text = "";
            }

            if (_toastT > 0f)
            {
                _toastT -= Time.deltaTime;
                if (_toastT <= 0f) _toast.text = "";
            }
        }

        // BANDWIDTH-полоса + слоты активок [Q]/[X]/[C] с кд
        string AbilityLine(GameState s)
        {
            int bwPips = Mathf.Clamp(Mathf.RoundToInt(s.bandwidth / s.maxBandwidth * 10f), 0, 10);
            string bar = new string('█', bwPips) + new string('░', 10 - bwPips);
            string line = $"BW {bar} {(int)s.bandwidth}/{(int)s.maxBandwidth}";
            if (_level == null) _level = FindFirstObjectByType<World.Level>();
            float cd = _level != null ? _level.AbilityCooldown : 0f;
            var keys = new[] { "Q", "X", "C" };
            for (int i = 0; i < 3; i++)
            {
                if (i < s.activeAbilities.Count)
                {
                    var ab = GameData.ABILITIES[s.activeAbilities[i]];
                    string state = cd > 0f ? $"кд {cd:0.0}с" : $"{(int)s.AbilityCost(s.activeAbilities[i])} BW";
                    line += $"   [{keys[i]}] {ab.name} ({state})";
                }
                else if (i < s.MaxAbilitySlots())
                    line += $"   [{keys[i]}] — пусто (дерево [Tab] в Гриде)";
            }
            return line;
        }

        public void SetPrompt(string text) { if (_prompt != null) _prompt.text = text; }
        public void SetObjective(string text) { if (_objective != null) _objective.text = text; }
        public void Toast(string text) { if (_toast != null) { _toast.text = text; _toastT = 3.2f; } }
    }
}
