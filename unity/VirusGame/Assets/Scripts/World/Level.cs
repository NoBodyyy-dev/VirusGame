using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;
using Virus.Core;
using Virus.Util;

namespace Virus.World
{
    // Порт ядра level.gd: рейд-ограбление внутри сервера.
    // Арена по теме тира, физический лут (тащи к порталу), СИСТЕМА с тревогой
    // (SLEEP→SCAN→PURGE→WIPE), типизированные ловушки из стен (лазер/клетка/
    // сброс/притяжение/метка/перепрошивка), роботы по углам: с 50% тревоги
    // пускают крюк-притягиватель, на 100% выходят на охоту. Активки [Q]/[X]/[C]
    // за Bandwidth, полевые задачи, HP/баг, эвакуация по квоте, результаты.
    public class Level : MonoBehaviour
    {
        static readonly Vector3 PadPos = new(-27, 0, 0);
        const float PadRadius = 3.6f;
        const float HookSpeed = 11.5f, HookReturn = 14f, HookRange = 32f;

        GameState S => GameState.I;
        Player.VirusPlayer _player;
        UI.Hud _hud;
        System.Random _rng;
        float _hallW, _hallD;

        class Loot { public Transform body; public Rigidbody rb; public float value; public int weight; public bool carried, deposited; public TextMesh label; public GameObject beacon; }
        readonly List<Loot> _loot = new();
        Loot _carried;

        class Trap { public Transform t; public string kind; public float life, speed; public Vector3 aim; }
        readonly List<Trap> _traps = new();

        class Guard
        {
            public Transform t, radar;
            public readonly List<Transform> wheels = new();
            public Vector3 home, lastPos;
            public float meleeCd, hookCd, stunUntil;
            public bool hookOut;
        }
        readonly List<Guard> _guards = new();

        class Hook { public Transform t; public Guard owner; public Vector3 dir; public bool ret; public bool caught; }
        readonly List<Hook> _hooks = new();

        // статусы системы/активок (метки Time.time)
        float _frozenUntil, _decoyUntil, _cloakUntil, _markedUntil, _hookedUntil, _abilityCd;
        Vector3 _decoyPos;
        Guard _hookedBy;

        float _trapTimer, _hitLock, _reviveT;
        int _phaseSeen;
        bool _done;
        Color _accent;
        TextMesh _sysScreen;
        Image _fade, _flash;
        float _flashA;
        Color _flashCol = new(1f, 0.15f, 0.2f);
        Transform _padArrow;

        // тема арены по тиру узла: материалы, свет, туман
        class ThemeCfg
        {
            public Material wall, floor, ceil;
            public Color lightCol, fogCol, ambSky, ambEq, ambGnd;
        }

        ThemeCfg _theme;   // кеш: Theme() создаёт материалы, звать один раз

        ThemeCfg Theme() => S.raid.theme switch
        {
            // домашний ПК: тёплые обои, ковёр, ламповый свет
            "home" => new ThemeCfg
            {
                wall = Mats.PlasterOld(new Color(0.52f, 0.47f, 0.38f)),
                floor = Mats.CarpetRot(),
                ceil = Mats.PlasterOld(new Color(0.45f, 0.43f, 0.4f)),
                lightCol = new Color(1f, 0.88f, 0.7f),
                fogCol = new Color(0.09f, 0.08f, 0.07f),
                ambSky = new Color(0.42f, 0.38f, 0.32f),
                ambEq = new Color(0.32f, 0.29f, 0.25f),
                ambGnd = new Color(0.15f, 0.13f, 0.11f),
            },
            // офис/лавка: серо-зелёная штукатурка, плитка, холодные лампы
            "office" => new ThemeCfg
            {
                wall = Mats.PlasterOld(new Color(0.45f, 0.48f, 0.42f)),
                floor = Mats.Sidewalk(),
                ceil = Mats.WhitePanel(),
                lightCol = new Color(0.92f, 0.96f, 1f),
                fogCol = new Color(0.06f, 0.08f, 0.08f),
                ambSky = new Color(0.36f, 0.4f, 0.38f),
                ambEq = new Color(0.28f, 0.31f, 0.29f),
                ambGnd = new Color(0.12f, 0.14f, 0.13f),
            },
            // дата-центр: металл, рифлёный пол, ледяной свет
            "dc" => new ThemeCfg
            {
                wall = Mats.Metal(new Color(0.4f, 0.44f, 0.5f), 0.55f),
                floor = Mats.DeckMetal(),
                ceil = Mats.MetalDark(0.6f),
                lightCol = new Color(0.75f, 0.88f, 1f),
                fogCol = new Color(0.04f, 0.07f, 0.12f),
                ambSky = new Color(0.3f, 0.38f, 0.5f),
                ambEq = new Color(0.24f, 0.29f, 0.38f),
                ambGnd = new Color(0.1f, 0.12f, 0.17f),
            },
            // военная сеть: бункерный бетон, ржавчина, тревожный свет
            _ => new ThemeCfg
            {
                wall = Mats.BunkerWall(),
                floor = Mats.Concrete(new Color(0.24f, 0.24f, 0.25f)),
                ceil = Mats.Rust(),
                lightCol = new Color(1f, 0.72f, 0.55f),
                fogCol = new Color(0.1f, 0.05f, 0.05f),
                ambSky = new Color(0.4f, 0.32f, 0.3f),
                ambEq = new Color(0.3f, 0.24f, 0.22f),
                ambGnd = new Color(0.13f, 0.1f, 0.1f),
            },
        };

        void Start()
        {
            if (S.raid == null)   // прямой запуск сцены — тестовый рейд
            {
                if (S.gridNodes.Count == 0) S.NewCampaign();
                S.StartHack(S.gridNodes[0]);
            }
            _rng = new System.Random(S.raid.seed);
            _hallW = 70f + (float)_rng.NextDouble() * 18f;
            _hallD = 46f + (float)_rng.NextDouble() * 14f;
            _accent = GameData.TIER_COLORS[S.raid.tier];
            _trapTimer = S.raid.trapInterval;
            _theme = Theme();

            BuildEnvironment();
            BuildArena();
            BuildPortal();
            SpawnLoot();
            SpawnGuards();
            SpawnFieldTasks();
            SpawnPlayer();

            _hud = FindFirstObjectByType<UI.Hud>();
            if (_hud != null)
            {
                _hud.raidMode = true;
                _hud.Toast($"{S.raid.name} · {GameData.TIERS[S.raid.tier].name} · выносим лут и тихо!");
                if (S.raid.assist > 0)
                    _hud.Toast($"ВСПОМОГАТЕЛЬНЫЙ ВЗЛОМ: {S.raid.assist} серверов зоны помогают (−{(int)(S.raid.assistK * 100)}% защиты)");
                _hud.SetObjective("Тащи лут в круг у портала — набери 100% квоты");
            }
            BuildFlashOverlay();
            BuildPadArrow();
            BuildMinimap();
            StartCoroutine(EnterAnimation());
        }

        // ── мини-карта: игрок/портал/лут/роботы точками (правый верх) ──
        RectTransform _mapRoot;
        Image _mapPlayer, _mapPad;
        readonly List<Image> _mapLoot = new();
        readonly List<Image> _mapGuards = new();
        const float MapW = 190f, MapH = 140f;

        Image MapDot(Color c, float size)
        {
            var go = new GameObject("dot", typeof(RectTransform));
            go.transform.SetParent(_mapRoot, false);
            var img = go.AddComponent<Image>();
            img.color = c;
            img.raycastTarget = false;
            img.rectTransform.sizeDelta = new Vector2(size, size);
            return img;
        }

        void BuildMinimap()
        {
            var canvasGo = new GameObject("Minimap", typeof(Canvas), typeof(CanvasScaler));
            var canvas = canvasGo.GetComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = 30;
            var scaler = canvasGo.GetComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1600, 900);

            var panel = new GameObject("panel", typeof(RectTransform));
            panel.transform.SetParent(canvasGo.transform, false);
            var bg = panel.AddComponent<Image>();
            bg.color = new Color(0.02f, 0.04f, 0.07f, 0.55f);
            bg.raycastTarget = false;
            _mapRoot = bg.rectTransform;
            _mapRoot.anchorMin = new Vector2(1, 1);
            _mapRoot.anchorMax = new Vector2(1, 1);
            _mapRoot.pivot = new Vector2(1, 1);
            _mapRoot.anchoredPosition = new Vector2(-24, -64);
            _mapRoot.sizeDelta = new Vector2(MapW, MapH);

            _mapPad = MapDot(GameData.INFECTED, 12f);
            foreach (var l in _loot) _mapLoot.Add(MapDot(new Color(0.4f, 0.9f, 1f), 6f));
            foreach (var g in _guards) _mapGuards.Add(MapDot(new Color(1f, 0.3f, 0.3f), 8f));
            _mapPlayer = MapDot(Color.white, 9f);
        }

        Vector2 MapPos(Vector3 world) => new(
            Mathf.Clamp(world.x / _hallW, -0.5f, 0.5f) * (MapW - 14f) - MapW * 0.5f,
            Mathf.Clamp(world.z / _hallD, -0.5f, 0.5f) * (MapH - 14f) - MapH * 0.5f);

        void TickMinimap()
        {
            if (_mapRoot == null) return;
            _mapPlayer.rectTransform.anchoredPosition = MapPos(_player.transform.position);
            _mapPad.rectTransform.anchoredPosition = MapPos(PadPos);
            for (int i = 0; i < _loot.Count && i < _mapLoot.Count; i++)
            {
                bool show = !_loot[i].deposited && _loot[i].body != null;
                _mapLoot[i].enabled = show;
                if (show) _mapLoot[i].rectTransform.anchoredPosition = MapPos(_loot[i].body.position);
            }
            // роботы видны на карте по метке spyware или при охоте
            bool robotsVisible = S.HasPassive("spyware") || S.AlarmPhase() >= 3;
            for (int i = 0; i < _guards.Count && i < _mapGuards.Count; i++)
            {
                _mapGuards[i].enabled = robotsVisible;
                if (robotsVisible) _mapGuards[i].rectTransform.anchoredPosition = MapPos(_guards[i].t.position);
            }
        }

        // ── красная вспышка при уроне + бирюзовый пульс на эвакуации ──
        void BuildFlashOverlay()
        {
            var canvasGo = new GameObject("FlashFx", typeof(Canvas), typeof(CanvasScaler));
            var canvas = canvasGo.GetComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = 40;
            var go = new GameObject("flash", typeof(RectTransform));
            go.transform.SetParent(canvasGo.transform, false);
            _flash = go.AddComponent<Image>();
            _flash.raycastTarget = false;
            var rt = _flash.rectTransform;
            rt.anchorMin = Vector2.zero; rt.anchorMax = Vector2.one;
            rt.offsetMin = Vector2.zero; rt.offsetMax = Vector2.zero;
            _flash.color = new Color(0, 0, 0, 0);
        }

        // стрелка над головой: пока несёшь груз — указывает на зону выноса
        void BuildPadArrow()
        {
            _padArrow = new GameObject("padArrow").transform;
            Build.MeshBox(_padArrow, new Vector3(0.12f, 0.12f, 0.9f), Mats.Neon(GameData.INFECTED, 2.2f), new Vector3(0, 0, 0.1f));
            Build.MeshBox(_padArrow, new Vector3(0.3f, 0.05f, 0.3f), Mats.Neon(GameData.INFECTED, 2.6f), new Vector3(0, 0, 0.62f));
            _padArrow.gameObject.SetActive(false);
        }

        void TickFlash(float dt)
        {
            if (_flash == null) return;
            _flashA = Mathf.Max(_flashA - dt * 1.6f, 0f);
            float evacPulse = S.evacOpen && !_done
                ? 0.06f + 0.05f * Mathf.Sin(Time.time * 5f) : 0f;
            if (_flashA > 0.001f)
                _flash.color = new Color(_flashCol.r, _flashCol.g, _flashCol.b, _flashA);
            else
                _flash.color = new Color(0.1f, 0.9f, 0.8f, evacPulse);
        }

        void TickPadArrow()
        {
            if (_padArrow == null || _player == null) return;
            bool show = _carried != null && !_done;
            if (_padArrow.gameObject.activeSelf != show) _padArrow.gameObject.SetActive(show);
            if (!show) return;
            _padArrow.position = _player.transform.position + Vector3.up * 2.9f;
            var dir = PadPos - _player.transform.position;
            dir.y = 0f;
            if (dir.sqrMagnitude > 0.1f)
                _padArrow.rotation = Quaternion.LookRotation(dir);
        }

        // ── анимация захода в сервер: тьма → вспышка кода → игра ──
        IEnumerator EnterAnimation()
        {
            var canvasGo = new GameObject("Fade", typeof(Canvas), typeof(CanvasScaler));
            var canvas = canvasGo.GetComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = 90;
            var go = new GameObject("dim", typeof(RectTransform));
            go.transform.SetParent(canvasGo.transform, false);
            _fade = go.AddComponent<Image>();
            var rt = _fade.rectTransform;
            rt.anchorMin = Vector2.zero; rt.anchorMax = Vector2.one;
            rt.offsetMin = Vector2.zero; rt.offsetMax = Vector2.zero;
            _fade.color = new Color(0.0f, 0.01f, 0.02f, 1f);

            var txtGo = new GameObject("txt", typeof(RectTransform));
            txtGo.transform.SetParent(canvasGo.transform, false);
            var txt = txtGo.AddComponent<Text>();
            txt.font = Build.UIFont;
            txt.fontSize = 30;
            txt.alignment = TextAnchor.MiddleCenter;
            txt.color = GameData.INFECTED;
            txt.horizontalOverflow = HorizontalWrapMode.Overflow;
            txt.rectTransform.sizeDelta = new Vector2(1200, 60);
            txt.text = $">> инъекция в {S.raid.name} · обход {S.raid.av}…";

            float t = 0f;
            while (t < 1.4f)
            {
                t += Time.deltaTime;
                float k = Mathf.Clamp01(t / 1.4f);
                _fade.color = new Color(0, 0.01f, 0.02f, 1f - k);
                txt.color = new Color(GameData.INFECTED.r, GameData.INFECTED.g, GameData.INFECTED.b, 1f - k * k);
                yield return null;
            }
            Destroy(canvasGo);
            _fade = null;
        }

        float R(float a, float b) => Mathf.Lerp(a, b, (float)_rng.NextDouble());

        void BuildEnvironment()
        {
            var th = _theme;
            QualitySettings.pixelLightCount = 10;
            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Trilight;
            // ACES-тонмаппинг съедает яркость — амбиент даём с запасом
            RenderSettings.ambientSkyColor = th.ambSky * 1.5f;
            RenderSettings.ambientEquatorColor = th.ambEq * 1.5f;
            RenderSettings.ambientGroundColor = th.ambGnd * 1.4f;
            RenderSettings.fog = true;
            RenderSettings.fogColor = th.fogCol;
            RenderSettings.fogMode = FogMode.Exponential;
            RenderSettings.fogDensity = 0.004f;
            RenderSettings.skybox = null;

            var moon = new GameObject("Fill").AddComponent<Light>();
            moon.type = LightType.Directional;
            moon.color = th.lightCol;
            moon.intensity = 0.8f;
            moon.transform.rotation = Quaternion.Euler(58, -28, 0);
            moon.shadows = LightShadows.Soft;
        }

        void BuildArena()
        {
            var th = _theme;
            float hx = _hallW * 0.5f, hz = _hallD * 0.5f;
            Build.Solid(transform, new Vector3(_hallW, 0.5f, _hallD), th.floor, new Vector3(0, -0.25f, 0));
            Build.Solid(transform, new Vector3(_hallW, 7, 0.6f), th.wall, new Vector3(0, 3.5f, -hz));
            Build.Solid(transform, new Vector3(_hallW, 7, 0.6f), th.wall, new Vector3(0, 3.5f, hz));
            Build.Solid(transform, new Vector3(0.6f, 7, _hallD), th.wall, new Vector3(-hx, 3.5f, 0));
            Build.Solid(transform, new Vector3(0.6f, 7, _hallD), th.wall, new Vector3(hx, 3.5f, 0));
            Build.Solid(transform, new Vector3(_hallW, 0.35f, _hallD), th.ceil, new Vector3(0, 7.3f, 0));

            // акцент тира по периметру + плинтус-подсветка
            Build.MeshBox(transform, new Vector3(_hallW - 2, 0.06f, 0.2f), Mats.Neon(_accent, 1.2f), new Vector3(0, 0.05f, -hz + 1.2f));
            Build.MeshBox(transform, new Vector3(_hallW - 2, 0.06f, 0.2f), Mats.Neon(_accent, 1.2f), new Vector3(0, 0.05f, hz - 1.2f));

            // кабель-каналы и трубы под потолком (вдоль зала)
            var pipeMat = Mats.MetalDark(0.55f);
            for (int i = 0; i < 4; i++)
            {
                float z = Mathf.Lerp(-hz + 4f, hz - 4f, (i + 0.5f) / 4f) + (float)_rng.NextDouble() * 1.6f - 0.8f;
                Build.MeshBox(transform, new Vector3(_hallW - 3f, 0.16f, 0.16f), pipeMat, new Vector3(0, 6.9f - i * 0.12f, z));
            }
            for (int i = 0; i < 2; i++)
            {
                float x = Mathf.Lerp(-hx + 6f, hx - 6f, i);
                Build.MeshBox(transform, new Vector3(0.22f, 0.22f, _hallD - 3f), pipeMat, new Vector3(x, 6.7f, 0));
            }

            // потолочные светильники: тёплые/холодные по теме
            for (int gx = 0; gx < 3; gx++)
                for (int gz = 0; gz < 2; gz++)
                {
                    var lp = new Vector3((gx - 1) * _hallW * 0.3f, 6.9f, (gz - 0.5f) * _hallD * 0.42f);
                    Build.MeshBox(transform, new Vector3(4.6f, 0.14f, 1.7f), Mats.Neon(th.lightCol, 2.4f), lp);
                    var sl = Build.SpotDown(transform, lp + Vector3.down * 0.3f, th.lightCol, 4.2f, 16f);
                    sl.shadows = LightShadows.Soft;
                }

            BuildThemeProps(hx, hz);

            // экран СИСТЕМЫ на стене
            Build.MeshBox(transform, new Vector3(11, 4.6f, 0.5f), Mats.Plastic(new Color(0.2f, 0.22f, 0.26f)), new Vector3(6, 3.4f, -hz + 0.6f));
            _sysScreen = Build.Label(transform, "", new Vector3(6, 3.4f, -hz + 1.0f), 3.4f, new Color(0.75f, 0.95f, 1f), false);
        }

        // ── реквизит по теме: у каждого тира свой характер зала ──
        void BuildThemeProps(float hx, float hz)
        {
            switch (S.raid.theme)
            {
                case "home":   // столы с домашними ПК, диваны
                    for (int i = 0; i < 7; i++)
                    {
                        var pos = FreeSpot(hx, hz);
                        Build.Solid(transform, new Vector3(2.2f, 0.8f, 1.1f), Mats.PlasterOld(new Color(0.42f, 0.33f, 0.24f)), pos + Vector3.up * 0.4f);
                        Build.MeshBox(transform, new Vector3(0.9f, 0.6f, 0.08f), Mats.Neon(new Color(0.5f, 0.75f, 1f), 1.4f), pos + new Vector3(0, 1.15f, -0.3f));
                        Build.MeshBox(transform, new Vector3(0.5f, 0.35f, 0.4f), Mats.Plastic(new Color(0.2f, 0.2f, 0.22f)), pos + new Vector3(0.7f, 0.98f, 0.1f));
                    }
                    for (int i = 0; i < 3; i++)
                    {
                        var pos = FreeSpot(hx, hz);
                        Build.Solid(transform, new Vector3(2.6f, 0.7f, 1.2f), Mats.CarpetRot(), pos + Vector3.up * 0.35f);
                        Build.Solid(transform, new Vector3(2.6f, 0.7f, 0.35f), Mats.CarpetRot(), pos + new Vector3(0, 0.9f, -0.45f));
                    }
                    break;
                case "office":   // ряды столов с перегородками
                    for (int row = 0; row < 3; row++)
                        for (int k = 0; k < 4; k++)
                        {
                            var pos = new Vector3(-hx + 10f + row * (hx * 0.55f), 0, -hz + 6f + k * ((hz * 2f - 12f) / 4f));
                            if (Vector3.Distance(pos, PadPos) < 9f) continue;
                            Build.Solid(transform, new Vector3(2f, 0.78f, 1f), Mats.Plastic(new Color(0.5f, 0.47f, 0.42f)), pos + Vector3.up * 0.39f);
                            Build.Solid(transform, new Vector3(2f, 1.5f, 0.1f), Mats.PlasterOld(new Color(0.38f, 0.4f, 0.36f)), pos + new Vector3(0, 0.75f, 0.55f));
                            Build.MeshBox(transform, new Vector3(0.75f, 0.5f, 0.07f), Mats.Neon(new Color(0.6f, 0.8f, 0.9f), 1.1f), pos + new Vector3(-0.3f, 1.05f, 0.2f));
                        }
                    break;
                case "dc":   // ровные ряды серверных стоек с мигающими LED
                    for (int row = 0; row < 3; row++)
                    {
                        float x = -hx + 12f + row * (hx * 0.6f);
                        for (int k = 0; k < 5; k++)
                        {
                            var pos = new Vector3(x, 0, -hz + 5f + k * ((hz * 2f - 10f) / 5f));
                            if (Vector3.Distance(pos, PadPos) < 9f) continue;
                            Build.Solid(transform, new Vector3(1.4f, 2.6f, 1f), Mats.MetalDark(0.4f), pos + Vector3.up * 1.3f);
                            for (int led = 0; led < 4; led++)
                                Build.MeshBox(transform, new Vector3(1.15f, 0.08f, 0.04f),
                                    Mats.Neon(led % 2 == 0 ? _accent : new Color(0.3f, 1f, 0.5f), 1.6f),
                                    pos + new Vector3(0, 0.5f + led * 0.55f, -0.53f));
                        }
                    }
                    break;
                default:   // бункер: бетонные блоки, ящики с hazard-полосами
                    for (int i = 0; i < 9; i++)
                    {
                        var pos = FreeSpot(hx, hz);
                        float h = R(1.1f, 2.4f);
                        Build.Solid(transform, new Vector3(R(1.6f, 3f), h, R(1.4f, 2.4f)), Mats.Concrete(new Color(0.3f, 0.3f, 0.31f)), pos + Vector3.up * (h * 0.5f));
                        if (_rng.NextDouble() < 0.6)
                            Build.MeshBox(transform, new Vector3(1.4f, 0.18f, 0.06f), Mats.Hazard(), pos + new Vector3(0, h * 0.5f, -R(0.7f, 1.2f)));
                    }
                    break;
            }
        }

        Vector3 FreeSpot(float hx, float hz)
        {
            for (int tries = 0; tries < 8; tries++)
            {
                var pos = new Vector3(R(-hx + 6, hx - 6), 0, R(-hz + 5, hz - 5));
                if (Vector3.Distance(pos, PadPos) >= 9f) return pos;
            }
            return new Vector3(hx - 8f, 0, 0);
        }

        void BuildPortal()
        {
            Build.MeshBox(transform, new Vector3(PadRadius * 2, 0.1f, PadRadius * 2), Mats.Neon(GameData.INFECTED, 0.5f), PadPos + Vector3.up * 0.05f);
            // hazard-рамка по периметру зоны выноса
            float b = PadRadius + 0.55f;
            Build.MeshBox(transform, new Vector3(b * 2, 0.06f, 0.35f), Mats.Hazard(), PadPos + new Vector3(0, 0.04f, -b));
            Build.MeshBox(transform, new Vector3(b * 2, 0.06f, 0.35f), Mats.Hazard(), PadPos + new Vector3(0, 0.04f, b));
            Build.MeshBox(transform, new Vector3(0.35f, 0.06f, b * 2), Mats.Hazard(), PadPos + new Vector3(-b, 0.04f, 0));
            Build.MeshBox(transform, new Vector3(0.35f, 0.06f, b * 2), Mats.Hazard(), PadPos + new Vector3(b, 0.04f, 0));
            Build.Omni(transform, PadPos + Vector3.up * 2f, new Color(0.1f, 0.8f, 0.9f), 1.6f, 8f);
            Build.Label(transform, "ЗОНА ВЫНОСА — неси лут сюда", PadPos + Vector3.up * 2.6f, 3f, GameData.INFECTED);
        }

        void SpawnLoot()
        {
            float hx = _hallW * 0.5f, hz = _hallD * 0.5f;
            int files = S.raid.files, crates = S.raid.crates;
            for (int i = 0; i < files + crates; i++)
            {
                bool crate = i >= files;
                var pos = new Vector3(R(-hx + 8, hx - 5), 1f, R(-hz + 4, hz - 4));
                if (pos.x < -14) pos.x = -pos.x;   // не спавним в зоне выноса
                var go = new GameObject(crate ? "crate" : "file");
                go.transform.SetParent(transform, false);
                go.transform.position = pos;
                var col = go.AddComponent<BoxCollider>();
                col.size = crate ? new Vector3(1.05f, 0.85f, 0.9f) : new Vector3(0.55f, 0.5f, 0.42f);
                var rb = go.AddComponent<Rigidbody>();
                rb.mass = crate ? 8 : 4;
                var c = crate ? new Color(0.29f, 0.56f, 1f) : new Color(0.22f, 0.94f, 0.66f);
                Build.MeshBox(go.transform, col.size, Mats.Neon(c, 0.9f), Vector3.zero);
                float value = crate ? R(16, 24) : R(7, 11);
                var loot = new Loot { body = go.transform, rb = rb, value = value, weight = crate ? 2 : 1 };
                loot.label = Build.Label(go.transform, $"◈ {(int)value}{(crate ? "  [тяжёлый]" : "")}", new Vector3(0, 0.9f, 0), 2.2f, c);
                _loot.Add(loot);

                var it = go.AddComponent<Interactable>();
                it.radius = 2.7f;
                it.dynamicPrompt = () => _carried == null
                    ? $"[E] схватить лут (◈ {(int)value})"
                    : "[E] положить · [F] швырнуть";
                it.enabledFn = () => !loot.deposited && (_carried == null || _carried == loot);
                it.onInteract = () => ToggleCarry(loot);
            }
        }

        void ToggleCarry(Loot loot)
        {
            if (S.myBug) return;
            if (_carried == loot) { DropLoot(); return; }
            if (_carried != null) return;
            _carried = loot;
            loot.carried = true;
            loot.rb.isKinematic = true;
            _player.carrying = true;
            // ransomware тащит тяжёлое как лёгкое; червь страдает от груза меньше
            float heavy = S.HasPassive("ransomware") ? 0.72f : 0.38f;
            float light = 0.78f;
            float k = loot.weight >= 2 ? heavy : light;
            if (S.HasPassive("worm")) k = Mathf.Min(k + 0.12f, 0.95f);
            _player.carryFactor = k;
            _player.SetMorph(false);
        }

        void DropLoot()
        {
            if (_carried == null) return;
            _carried.carried = false;
            _carried.rb.isKinematic = false;
            _carried = null;
            if (_player != null)
            {
                _player.carrying = false;
                _player.carryFactor = 1f;
            }
        }

        void SpawnGuards()
        {
            float hx = _hallW * 0.5f - 4f, hz = _hallD * 0.5f - 4f;
            var corners = new[] { new Vector3(hx, 0, hz), new Vector3(-hx, 0, -hz), new Vector3(hx, 0, -hz), new Vector3(-hx, 0, hz) };
            int n = Mathf.Clamp(S.raid.sensitivity, 1, 4);
            for (int i = 0; i < n; i++)
            {
                var root = new GameObject("guard").transform;
                root.SetParent(transform, false);
                root.localPosition = corners[i];
                var body = Mats.Metal(new Color(0.58f, 0.62f, 0.68f), 0.35f);
                Build.MeshBox(root, new Vector3(1.9f, 0.55f, 2.5f), body, new Vector3(0, 0.72f, 0));
                Build.MeshBox(root, new Vector3(1.35f, 1f, 1.1f), body, new Vector3(0, 1.75f, 0));
                Build.MeshBox(root, Vector3.one * 0.6f, body, new Vector3(0, 2.5f, 0));
                Build.MeshBox(root, Vector3.one * 0.26f, Mats.Neon(new Color(1f, 0.2f, 0.2f), 4f), new Vector3(0, 2.55f, 0.34f));
                // дуло крюка
                Build.MeshBox(root, new Vector3(0.2f, 0.2f, 0.6f), Mats.Metal(new Color(0.35f, 0.38f, 0.42f), 0.6f), new Vector3(0, 1.9f, 0.75f));
                Build.Omni(root, new Vector3(0, 2.6f, 0), new Color(1f, 0.25f, 0.2f), 1.4f, 9f);
                var guard = new Guard { t = root, home = corners[i], lastPos = corners[i], hookCd = (float)_rng.NextDouble() * 4f + 4f };
                // колёса и вращающийся радар — робот выглядит живым
                var wheelMat = Mats.Plastic(new Color(0.08f, 0.09f, 0.1f));
                foreach (var (wx, wz) in new[] { (-0.95f, 0.9f), (0.95f, 0.9f), (-0.95f, -0.9f), (0.95f, -0.9f) })
                {
                    var w = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
                    Destroy(w.GetComponent<Collider>());
                    w.transform.SetParent(root, false);
                    w.transform.localPosition = new Vector3(wx, 0.36f, wz);
                    w.transform.localScale = new Vector3(0.72f, 0.14f, 0.72f);
                    w.transform.localRotation = Quaternion.Euler(0, 0, 90);
                    w.GetComponent<MeshRenderer>().sharedMaterial = wheelMat;
                    guard.wheels.Add(w.transform);
                }
                guard.radar = Build.MeshBox(root, new Vector3(0.55f, 0.08f, 0.18f),
                    Mats.Metal(new Color(0.7f, 0.72f, 0.76f), 0.4f), new Vector3(0, 2.92f, 0)).transform;
                // пассивка spyware: радиус обзора робота виден кольцом на полу
                if (S.HasPassive("spyware"))
                {
                    float rr = S.raid.camRange * 1.4f;
                    for (int k = 0; k < 24; k++)
                    {
                        float a = Mathf.PI * 2f * k / 24f;
                        Build.MeshBox(root, new Vector3(0.3f, 0.04f, 0.3f), Mats.Neon(new Color(1f, 0.6f, 0.25f), 1.1f),
                            new Vector3(Mathf.Cos(a) * rr, 0.06f, Mathf.Sin(a) * rr));
                    }
                }
                _guards.Add(guard);
            }
        }

        // ── полевые кооп-задачи (вдвоём легко, одному — мучение) ──
        // тир 0: консоль; тир 1+: двойной рубильник; тир 2+: протяжка кабеля
        void SpawnFieldTasks()
        {
            int n = GameData.TIERS[S.raid.tier].tasks;
            if (n >= 1) SpawnConsoleTask();
            if (n >= 2) SpawnDualLeverTask();
            if (n >= 3) SpawnCableTask();
        }

        Vector3 TaskSpot(float margin)
        {
            float hx = _hallW * 0.5f, hz = _hallD * 0.5f;
            var pos = new Vector3(R(-hx + margin, hx - margin), 0, R(-hz + margin, hz - margin));
            if (Vector3.Distance(pos, PadPos) < 9f) pos.x = Mathf.Abs(pos.x);
            return pos;
        }

        void TaskDone(string msg)
        {
            S.ApplyAlarm(-8f);
            S.CareerEvent("tasks");
            Sfx.Play("win", 0.3f);
            _hud?.Toast(msg + " · тревога −8, карьера +1 задача");
        }

        void SpawnConsoleTask()
        {
            var root = new GameObject("task_console").transform;
            root.SetParent(transform, false);
            root.localPosition = TaskSpot(7f);
            Build.Solid(root, new Vector3(1.1f, 1.3f, 0.7f), Mats.Plastic(new Color(0.14f, 0.2f, 0.26f)), new Vector3(0, 0.65f, 0));
            var led = Build.MeshBox(root, new Vector3(0.8f, 0.5f, 0.06f), Mats.Neon(new Color(1f, 0.7f, 0.35f), 1.6f), new Vector3(0, 0.9f, -0.39f));
            var label = Build.Label(root, "СЕРВИСНАЯ КОНСОЛЬ\nполевая задача", new Vector3(0, 2f, 0), 2.4f, new Color(1f, 0.7f, 0.35f));
            bool used = false;
            var it = root.gameObject.AddComponent<Interactable>();
            it.radius = 3f;
            it.holdSeconds = 3f;
            it.prompt = "[E·держать] откалибровать консоль";
            it.enabledFn = () => !used && !S.myBug;
            it.onInteract = () =>
            {
                used = true;
                led.GetComponent<MeshRenderer>().sharedMaterial = Mats.Neon(new Color(0.4f, 0.42f, 0.45f), 0.4f);
                label.text = "СЕРВИСНАЯ КОНСОЛЬ\n// ИСПОЛЬЗОВАНА //";
                label.color = new Color(0.45f, 0.5f, 0.55f);
                TaskDone("Консоль откалибрована");
            };
        }

        // двойной рубильник: второй надо дёрнуть за 6 секунд после первого
        void SpawnDualLeverTask()
        {
            var posA = TaskSpot(8f);
            var posB = posA + new Vector3(posA.x > 0 ? -18f : 18f, 0, posA.z > 0 ? -10f : 10f);
            posB.x = Mathf.Clamp(posB.x, -_hallW * 0.5f + 6f, _hallW * 0.5f - 6f);
            posB.z = Mathf.Clamp(posB.z, -_hallD * 0.5f + 5f, _hallD * 0.5f - 5f);
            float window = 0f;   // Time.time, до которого активен второй рычаг
            bool done = false;
            var col = new Color(0.4f, 0.85f, 1f);

            Transform Lever(Vector3 pos, string name)
            {
                var root = new GameObject(name).transform;
                root.SetParent(transform, false);
                root.localPosition = pos;
                Build.Solid(root, new Vector3(0.5f, 1.1f, 0.5f), Mats.MetalDark(0.5f), new Vector3(0, 0.55f, 0));
                var arm = Build.MeshBox(root, new Vector3(0.12f, 0.7f, 0.12f), Mats.Neon(col, 1.6f), new Vector3(0, 1.35f, 0));
                arm.transform.localRotation = Quaternion.Euler(0, 0, 35);
                Build.Label(root, "ДВОЙНОЙ РУБИЛЬНИК\n(нужны оба за 6с)", new Vector3(0, 2.2f, 0), 2.2f, col);
                return root;
            }

            var a = Lever(posA, "task_leverA");
            var b = Lever(posB, "task_leverB");

            void Wire(Transform lever)
            {
                var it = lever.gameObject.AddComponent<Interactable>();
                it.radius = 2.8f;
                it.dynamicPrompt = () => window > Time.time
                    ? $"[E] ВТОРОЙ РЫЧАГ — успей! ({Mathf.Max(window - Time.time, 0f):0.0}с)"
                    : "[E] дёрнуть рубильник (второй — за 6с)";
                it.enabledFn = () => !done && !S.myBug;
                it.onInteract = () =>
                {
                    if (window > Time.time)
                    {
                        done = true;
                        TaskDone("Рубильники синхронизированы");
                    }
                    else
                    {
                        window = Time.time + 6f;
                        Sfx.Play("ui");
                        _hud?.Toast("Первый есть! Второй рычаг — за 6 секунд!");
                    }
                };
            }
            Wire(a);
            Wire(b);
        }

        // протяжка кабеля: пилоны по порядку, на каждый шаг — 8 секунд
        void SpawnCableTask()
        {
            var col = new Color(1f, 0.85f, 0.3f);
            var start = TaskSpot(9f);
            var pts = new Vector3[3];
            for (int i = 0; i < 3; i++)
            {
                pts[i] = start + new Vector3((i + 1) * (start.x > 0 ? -9f : 9f), 0, Mathf.Sin(i * 2.1f) * 7f);
                pts[i].x = Mathf.Clamp(pts[i].x, -_hallW * 0.5f + 5f, _hallW * 0.5f - 5f);
                pts[i].z = Mathf.Clamp(pts[i].z, -_hallD * 0.5f + 4f, _hallD * 0.5f - 4f);
            }
            int next = 0;
            float deadline = 0f;
            bool done = false;
            var orbGos = new GameObject[3];
            var dim = Mats.Neon(col, 0.5f);
            var lit = Mats.Neon(col, 2.4f);

            for (int i = 0; i < 3; i++)
            {
                int idx = i;
                var root = new GameObject($"task_pylon{i}").transform;
                root.SetParent(transform, false);
                root.localPosition = pts[i];
                Build.Solid(root, new Vector3(0.35f, 2.2f, 0.35f), Mats.MetalDark(0.5f), new Vector3(0, 1.1f, 0));
                orbGos[i] = Build.MeshBox(root, Vector3.one * 0.4f, dim, new Vector3(0, 2.4f, 0));
                Build.Label(root, $"ОПОРА {i + 1}/3\nпротяжка кабеля", new Vector3(0, 3.1f, 0), 2f, col);
                var it = root.gameObject.AddComponent<Interactable>();
                it.radius = 2.8f;
                it.dynamicPrompt = () => idx == next && next > 0 && deadline > Time.time
                    ? $"[E] тяни кабель! ({Mathf.Max(deadline - Time.time, 0f):0.0}с)"
                    : $"[E] опора {idx + 1} (по порядку)";
                it.enabledFn = () => !done && !S.myBug && idx == next;
                it.onInteract = () =>
                {
                    if (next > 0 && Time.time > deadline)
                    {
                        next = 0;   // кабель остыл — сначала
                        foreach (var o in orbGos) o.GetComponent<MeshRenderer>().sharedMaterial = dim;
                        Sfx.Play("fail", 0.25f);
                        _hud?.Toast("Кабель остыл — тяни заново с опоры 1");
                        return;
                    }
                    orbGos[idx].GetComponent<MeshRenderer>().sharedMaterial = lit;
                    next++;
                    deadline = Time.time + 8f;
                    Sfx.Play("ui");
                    if (next >= 3)
                    {
                        done = true;
                        TaskDone("Кабель протянут");
                    }
                    else _hud?.Toast($"Опора {next}/3! Следующая — за 8 секунд");
                };
            }
        }

        void SpawnPlayer()
        {
            var go = new GameObject("Player", typeof(CharacterController), typeof(Player.VirusPlayer));
            _player = go.GetComponent<Player.VirusPlayer>();
            go.transform.position = new Vector3(-27, 1.2f, 3);
            _player.morphBroken = () => _hud?.Toast("Морф слетел — ты двинулся!");
        }

        bool Frozen => Time.time < _frozenUntil;
        bool PlayerHidden => _player.Morphed || (Time.time < _cloakUntil && Time.time >= _markedUntil);

        Vector3 TrapTargetPos()
        {
            if (Time.time < _decoyUntil) return _decoyPos;
            return _player.transform.position + Vector3.up * 1.1f;
        }

        void Update()
        {
            if (_done || _player == null) return;
            float dt = Time.deltaTime;
            _hitLock = Mathf.Max(_hitLock - dt, 0f);
            _abilityCd = Mathf.Max(_abilityCd - dt, 0f);

            // тревога ползёт сама; на эвакуации — быстрее
            S.ApplyAlarm(S.raid.creep * (S.evacOpen ? 1.6f : 1f) * dt);
            TickPhaseFx();
            if (!Frozen)
            {
                TickTraps(dt);
                TickGuards(dt);
                TickHooks(dt);
            }
            TickHooked(dt);
            TickAbilities();
            TickThrow();
            TickCarryAndDeposit();
            TickBugAndRevive(dt);
            TickEvac(dt);
            TickSystemScreen();
            TickFlash(dt);
            TickPadArrow();
            TickLootPulse();
            TickMinimap();
        }

        // [F] — швырнуть груз вперёд (перекинуть напарнику или докинуть к порталу)
        void TickThrow()
        {
            if (_carried == null || !Input.GetKeyDown(KeyCode.F)) return;
            if (UI.PuzzleUI.IsOpen || UI.EvolutionUI.IsOpen) return;
            var l = _carried;
            DropLoot();
            l.rb.linearVelocity = _player.LookDir() * 10f + Vector3.up * 4.5f;
            Sfx.Play("ui", 0.3f);
        }

        // лут рядом «дышит» подсветкой — легче заметить в темноте
        void TickLootPulse()
        {
            var pp = _player.transform.position;
            foreach (var l in _loot)
            {
                if (l.deposited || l.body == null || l.label == null) continue;
                bool near = Vector3.Distance(pp, l.body.position) < 5f;
                float k = near ? 1f + 0.25f * Mathf.Sin(Time.time * 6f) : 1f;
                l.label.characterSize = 2.2f * 0.08f * k;
            }
        }

        void TickPhaseFx()
        {
            int ph = S.AlarmPhase();
            if (ph != _phaseSeen && ph > _phaseSeen)
            {
                string[] msg = { "", "СИСТЕМА: СКАНИРОВАНИЕ — ловушки активированы!", "СИСТЕМА: ЗАЧИСТКА — роботы заряжают крюки!", "СИСТЕМА: ВТОРЖЕНИЕ — роботы вышли на охоту!" };
                _hud?.Toast(msg[ph]);
                Sfx.Play("alarm", 0.35f);
            }
            _phaseSeen = ph;
            RenderSettings.fogColor = ph switch
            {
                3 => new Color(0.25f, 0.03f, 0.05f),
                2 => new Color(0.2f, 0.08f, 0.08f),
                1 => new Color(0.14f, 0.11f, 0.06f),
                _ => _theme.fogCol,
            };
        }

        // ── ловушки: типизированные снаряды из ближайшей стены ──
        void TickTraps(float dt)
        {
            if (S.AlarmPhase() >= 1 && !S.myBug && !PlayerHidden)
            {
                float speedup = 1f + S.alarm / 100f + S.raid.tier * 0.25f;
                if (Time.time < _markedUntil) speedup *= 1.6f;   // метка: система ведёт тебя
                _trapTimer -= dt * speedup;
                if (_trapTimer <= 0f)
                {
                    _trapTimer = S.raid.trapInterval;
                    SpawnTrap();
                }
            }
            for (int i = _traps.Count - 1; i >= 0; i--)
            {
                var o = _traps[i];
                o.life -= dt;
                if (o.t == null || o.life <= 0f) { if (o.t != null) Destroy(o.t.gameObject); _traps.RemoveAt(i); continue; }
                var target = TrapTargetPos() + o.aim;   // adware: часть ловушек мажет
                o.t.position = Vector3.MoveTowards(o.t.position, target, o.speed * dt);
                if (Vector3.Distance(o.t.position, _player.transform.position + Vector3.up * 1.1f) < 1f)
                {
                    var from = o.t.position;
                    Destroy(o.t.gameObject);
                    _traps.RemoveAt(i);
                    ApplyTrapHit(o.kind, from);
                }
            }
        }

        void SpawnTrap()
        {
            // доступные типы по тиру узла (из GameData.TIERS)
            var kinds = S.raid != null ? GameData.TIERS[S.raid.tier].traps : new[] { "laser" };
            string kind = kinds[_rng.Next(kinds.Length)];
            var info = GameData.TRAPS[kind];

            float hx = _hallW * 0.5f, hz = _hallD * 0.5f;
            var pp = _player.transform.position;
            var candidates = new[] { new Vector3(-hx + 1, 2.2f, pp.z), new Vector3(hx - 1, 2.2f, pp.z), new Vector3(pp.x, 2.2f, -hz + 1), new Vector3(pp.x, 2.2f, hz - 1) };
            var origin = candidates[0];
            foreach (var c in candidates) if (Vector3.Distance(c, pp) < Vector3.Distance(origin, pp)) origin = c;

            GameObject body;
            if (kind == "reflash")   // летящая флешка
            {
                body = Build.MeshBox(transform, new Vector3(0.28f, 0.28f, 0.72f), Mats.Neon(info.color, 3f), origin);
                Build.MeshBox(body.transform, new Vector3(0.55f, 0.12f, 0.4f), Mats.Metal(new Color(0.7f, 0.72f, 0.76f), 0.4f), new Vector3(0, 0, -1f));
            }
            else if (kind == "cage")
            {
                body = Build.MeshBox(transform, Vector3.one * 0.55f, Mats.Neon(info.color, 2.2f), origin);
                Build.MeshBox(body.transform, Vector3.one * 1.25f, Mats.Neon(info.color, 0.7f), Vector3.zero);
            }
            else
                body = Build.MeshBox(transform, Vector3.one * 0.45f, Mats.Neon(info.color, 3.5f), origin);
            Build.Omni(body.transform, Vector3.zero, info.color, 1.2f, 4f);
            Build.Label(body.transform, info.name, new Vector3(0, 0.7f, 0), 1.8f, info.color);
            // пассивка adware: ловушки иногда ведутся на фантомный след и промахиваются
            var aim = Vector3.zero;
            if (S.HasPassive("adware") && _rng.NextDouble() < 0.35)
            {
                float ma = (float)_rng.NextDouble() * Mathf.PI * 2f;
                aim = new Vector3(Mathf.Cos(ma), 0, Mathf.Sin(ma)) * R(2.8f, 4.5f);
            }
            _traps.Add(new Trap { t = body.transform, kind = kind, life = info.life, speed = info.speed, aim = aim });
        }

        void ApplyTrapHit(string kind, Vector3 from)
        {
            float now = Time.time;
            switch (kind)
            {
                case "laser":
                    HurtPlayer(from, 1);
                    break;
                case "cage":
                    _player.lockedUntil = now + 8f;
                    SpawnDome(8f, GameData.TRAPS["cage"].color);
                    _hud?.Toast("КЛЕТКА: 8 секунд без движения!");
                    break;
                case "mark":
                    _markedUntil = now + 10f;
                    HurtPlayer(from, 1);
                    _hud?.Toast("МЕТКА: система ведёт тебя 10 секунд");
                    break;
                case "reset":
                    S.resetUntil = S.now + 10f;
                    _hud?.Toast("СБРОС ДО НУЛЯ: скин и ветка отключены на 10 секунд");
                    break;
                case "pull":
                    HurtPlayer(from, 1);
                    var dir = NearestWallDir(_player.transform.position);
                    _player.Impulse(dir * 20f + Vector3.up * 4f);
                    _hud?.Toast("ПРИТЯЖЕНИЕ: тебя утянуло к стене!");
                    break;
                case "reflash":
                    _player.lockedUntil = now + 2.5f;
                    _player.slowUntil = now + 15f;
                    var lost = S.StealAbility();
                    HurtPlayer(from, 3);
                    SpawnDome(2.5f, GameData.TRAPS["reflash"].color);
                    _hud?.Toast("ПЕРЕПРОШИВКА: −3 HP, замедление 15с" +
                        (lost != "" ? $" · украдено умение «{GameData.ABILITIES[lost].name}»" : ""));
                    break;
            }
        }

        Vector3 NearestWallDir(Vector3 p)
        {
            float hx = _hallW * 0.5f, hz = _hallD * 0.5f;
            var best = Vector3.right; float bestD = hx - p.x;
            if (hx + p.x < bestD) { best = Vector3.left; bestD = hx + p.x; }
            if (hz - p.z < bestD) { best = Vector3.forward; bestD = hz - p.z; }
            if (hz + p.z < bestD) best = Vector3.back;
            return best;
        }

        // купол с кодом вокруг жертвы (клетка/перепрошивка)
        void SpawnDome(float dur, Color color)
        {
            var dome = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            Destroy(dome.GetComponent<Collider>());
            dome.transform.SetParent(_player.transform, false);
            dome.transform.localPosition = new Vector3(0, 1f, 0);
            dome.transform.localScale = Vector3.one * 3f;
            dome.GetComponent<MeshRenderer>().sharedMaterial = Mats.Neon(color, 0.55f);
            Destroy(dome, dur);
        }

        // ── роботы: угол → крюки (50%) → погоня (100%) ──
        void TickGuards(float dt)
        {
            bool hunt = S.AlarmPhase() >= 3;
            bool seen = !S.myBug && !PlayerHidden;
            foreach (var g in _guards)
            {
                g.meleeCd = Mathf.Max(g.meleeCd - dt, 0f);
                g.hookCd = Mathf.Max(g.hookCd - dt, 0f);
                // колёса крутятся от пройденного пути, радар — всегда (кроме стана)
                float moved = (g.t.position - g.lastPos).magnitude;
                g.lastPos = g.t.position;
                foreach (var w in g.wheels) w.Rotate(0f, moved / 0.36f * Mathf.Rad2Deg, 0f, Space.Self);
                if (Time.time >= g.stunUntil && g.radar != null) g.radar.Rotate(0f, 140f * dt, 0f, Space.Self);
                if (Time.time < g.stunUntil || g.hookOut) continue;   // ЭМИ или крюк в полёте — робот замер

                var pp = _player.transform.position;
                float dist = Vector3.Distance(g.t.position, pp);

                if (hunt && seen)
                {
                    var dir = pp - g.t.position; dir.y = 0;
                    if (dir.magnitude > 1.6f)
                    {
                        g.t.position += dir.normalized * (6f * dt);
                        g.t.rotation = Quaternion.Slerp(g.t.rotation, Quaternion.LookRotation(dir), 8f * dt);
                    }
                    else if (g.meleeCd <= 0f) { g.meleeCd = 1.4f; HurtPlayer(g.t.position, 1); }
                }
                else
                {
                    var back = g.home - g.t.position; back.y = 0;
                    if (back.magnitude > 1f) g.t.position += back.normalized * (3.5f * dt);
                    else if (seen && dist < S.raid.camRange * 1.4f)
                    {
                        var face = pp - g.t.position; face.y = 0;
                        if (face.sqrMagnitude > 0.1f)
                            g.t.rotation = Quaternion.Slerp(g.t.rotation, Quaternion.LookRotation(face), 4f * dt);
                    }
                    else
                        g.t.Rotate(0f, 22f * dt, 0f);   // дежурное сканирование зала
                }

                // крюк: с 50% тревоги по цели в радиусе обзора (на 100% — дальнобойный)
                float sight = hunt ? HookRange : S.raid.camRange * 1.4f;
                if (S.alarm >= 50f && seen && g.hookCd <= 0f && dist > 3f && dist < sight)
                {
                    g.hookCd = (float)_rng.NextDouble() * 4f + 5f;
                    g.hookOut = true;
                    var origin = g.t.position + Vector3.up * 1.9f;
                    var hdir = (pp + Vector3.up * 1f - origin).normalized;
                    var body = Build.MeshBox(transform, new Vector3(0.3f, 0.3f, 0.6f), Mats.Neon(new Color(1f, 0.5f, 0.2f), 3f), origin);
                    Build.Omni(body.transform, Vector3.zero, new Color(1f, 0.5f, 0.2f), 1f, 4f);
                    body.transform.rotation = Quaternion.LookRotation(hdir);
                    _hooks.Add(new Hook { t = body.transform, owner = g, dir = hdir });
                    Sfx.Play("hook", 0.45f);
                    _hud?.Toast("⚠ РОБОТ ВЫПУСТИЛ КРЮК — уворачивайся!");
                }
            }
        }

        void TickHooks(float dt)
        {
            for (int i = _hooks.Count - 1; i >= 0; i--)
            {
                var h = _hooks[i];
                if (h.t == null) { h.owner.hookOut = false; _hooks.RemoveAt(i); continue; }
                var robotPos = h.owner.t.position + Vector3.up * 1.9f;
                float hx = _hallW * 0.5f, hz = _hallD * 0.5f;

                if (!h.ret)
                {
                    h.t.position += h.dir * (HookSpeed * dt);
                    var p = h.t.position;
                    // граница зала или дальность — крюк возвращается
                    if (Mathf.Abs(p.x) > hx - 1f || Mathf.Abs(p.z) > hz - 1f ||
                        Vector3.Distance(p, robotPos) > HookRange)
                        h.ret = true;
                }
                else
                {
                    var back = robotPos - h.t.position;
                    if (back.magnitude < 1.2f)
                    {
                        h.owner.hookOut = false;
                        Destroy(h.t.gameObject);
                        _hooks.RemoveAt(i);
                        continue;
                    }
                    h.t.position += back.normalized * (HookReturn * dt);
                }

                // зацепил? жертва роняет груз и волочётся к роботу (не убивает!)
                if (!h.caught && !S.myBug && !PlayerHidden &&
                    Vector3.Distance(h.t.position, _player.transform.position + Vector3.up * 1f) < 1.2f)
                {
                    h.caught = true;
                    h.ret = true;
                    DropLoot();
                    _hookedUntil = Time.time + 1.6f;
                    _hookedBy = h.owner;
                    _player.Shake(0.6f);
                    _hud?.Toast("🪝 КРЮК ЗАЦЕПИЛ — тебя тянет к роботу!");
                }
            }
        }

        // тянет жертву к роботу, у клешней добьёт melee-удар
        void TickHooked(float dt)
        {
            if (Time.time >= _hookedUntil || S.myBug || _hookedBy == null) return;
            var rp = _hookedBy.t.position;
            var pull = rp - _player.transform.position;
            pull.y = 0f;
            if (pull.magnitude < 2f) { _hookedUntil = 0f; return; }
            _player.Teleport(_player.transform.position + pull.normalized * (13f * dt));
        }

        // ── активки [Q]/[X]/[C] за Bandwidth ──
        void TickAbilities()
        {
            if (UI.PuzzleUI.IsOpen || UI.EvolutionUI.IsOpen) return;
            if (Input.GetKeyDown(KeyCode.Q)) UseAbility(0);
            if (Input.GetKeyDown(KeyCode.X)) UseAbility(1);
            if (Input.GetKeyDown(KeyCode.C)) UseAbility(2);
        }

        void UseAbility(int slot)
        {
            if (S.myBug) { _hud?.Toast("ты баг. у багов нет активок. у багов есть только писк"); return; }
            if (_player.Locked) { _hud?.Toast("умения заблокированы ловушкой!"); return; }
            if (slot >= S.activeAbilities.Count)
            {
                if (S.activeAbilities.Count == 0)
                    _hud?.Toast("нет активок: выбери ветку и УР.1 в дереве эволюции [Tab] (в Гриде)");
                return;
            }
            if (_abilityCd > 0f) { _hud?.Toast("активка перезаряжается"); return; }
            string id = S.activeAbilities[slot];
            float cost = S.AbilityCost(id);
            if (!S.TrySpendBandwidth(cost)) { _hud?.Toast("недостаточно Bandwidth"); return; }
            Sfx.Play("ability");

            float now = Time.time;
            switch (id)
            {
                case "morph":
                    _player.SetMorph(true);
                    _hud?.Toast("ЛОЖНЫЙ ФАЙЛ: замри — роботы тебя не видят. Движение снимает морф");
                    break;
                case "dash":
                    _player.Dash();
                    _hud?.Toast("РЫВОК!");
                    break;
                case "freeze":
                    _frozenUntil = now + 3f;
                    _hud?.Toast("ШИФРОВАНИЕ: система и ловушки заморожены (3с)");
                    break;
                case "xray":
                    StartCoroutine(XRay(6f));
                    _hud?.Toast("СКАН: лут и угрозы подсвечены (6с)");
                    break;
                case "decoy":
                    _decoyUntil = now + 5f;
                    _decoyPos = _player.transform.position + _player.LookDir() * 4f + Vector3.up * 1.2f;
                    SpawnDecoyGhost(_decoyPos);
                    _hud?.Toast("ФАНТОМ: ловушки ведутся (5с)");
                    break;
                case "jam":
                    S.ApplyAlarm(-12f);
                    _hud?.Toast("ГЛУШИЛКА: тревога −12");
                    break;
                case "haste":
                    _player.hasteUntil = now + 5f;
                    _hud?.Toast("СВЕРХТАКТ: +45% скорости (5с)");
                    break;
                case "emp":
                    Guard nearest = null; float bd = 999f;
                    foreach (var g in _guards)
                    {
                        float d = Vector3.Distance(g.t.position, _player.transform.position);
                        if (d < bd) { bd = d; nearest = g; }
                    }
                    if (nearest != null) nearest.stunUntil = now + 4f;
                    _hud?.Toast("ЭМИ-РАЗРЯД: ближайший робот оглушён (4с)");
                    break;
                case "cloak":
                    _cloakUntil = now + 4f;
                    _hud?.Toast("СТЕЛС-ПАКЕТ: роботы тебя не видят (4с)");
                    break;
                case "purge":
                    foreach (var o in _traps) if (o.t != null) Destroy(o.t.gameObject);
                    _traps.Clear();
                    foreach (var h in _hooks) { if (h.t != null) Destroy(h.t.gameObject); h.owner.hookOut = false; }
                    _hooks.Clear();
                    _hud?.Toast("ЧИСТКА: все летящие ловушки сожжены");
                    break;
                case "heal":
                    if (S.myHp < S.myMaxHp)
                    {
                        S.myHp++;
                        _hud?.Toast($"РОЙ: подлатал себя (+1 HP → {S.myHp}/{S.myMaxHp})");
                    }
                    else _hud?.Toast("HP уже полные — рой скучает");
                    break;
            }
            _abilityCd = 8f - S.EvoBonus("cooldown");
        }

        public float AbilityCooldown => _abilityCd;

        IEnumerator XRay(float dur)
        {
            var beacons = new List<GameObject>();
            foreach (var l in _loot)
            {
                if (l.deposited || l.body == null) continue;
                var b = Build.MeshBox(l.body, new Vector3(0.12f, 26f, 0.12f), Mats.Neon(new Color(1f, 0.85f, 0.4f), 2.2f), new Vector3(0, 13f, 0));
                beacons.Add(b);
            }
            foreach (var g in _guards)
            {
                var b = Build.MeshBox(g.t, new Vector3(0.16f, 26f, 0.16f), Mats.Neon(new Color(1f, 0.3f, 0.3f), 2.2f), new Vector3(0, 13f, 0));
                beacons.Add(b);
            }
            yield return new WaitForSeconds(dur);
            foreach (var b in beacons) if (b != null) Destroy(b);
        }

        void SpawnDecoyGhost(Vector3 pos)
        {
            var ghost = GameObject.CreatePrimitive(PrimitiveType.Capsule);
            Destroy(ghost.GetComponent<Collider>());
            ghost.transform.position = pos;
            ghost.transform.localScale = new Vector3(0.84f, 0.78f, 0.84f);
            ghost.GetComponent<MeshRenderer>().sharedMaterial = Mats.Neon(new Color(1f, 0.7f, 0.3f), 1.4f);
            Destroy(ghost, 5f);
        }

        void HurtPlayer(Vector3 from, int dmg)
        {
            if (_hitLock > 0f || S.myBug || _done) return;
            _hitLock = 1.2f;
            S.myHp = Mathf.Max(S.myHp - dmg, 0);
            // rootkit бесшумный: система слышит удар вдвое тише
            S.ApplyAlarm(S.HasPassive("rootkit") ? 1f : 2f);
            _flashA = Mathf.Min(0.4f + dmg * 0.12f, 0.65f);
            _player.Shake(0.5f + dmg * 0.15f);
            Sfx.Play("trap");
            DropLoot();
            _player.SetMorph(false);
            var push = _player.transform.position - from; push.y = 0;
            _player.Impulse(push.normalized * 11f + Vector3.up * 7f);
            if (S.myHp <= 0)
            {
                S.myBug = true;
                _player.SetBug(true);
                _hud?.Toast("КРИТИЧЕСКИЙ СБОЙ: ты — БАГ. Ползи к порталу!");
            }
            else _hud?.Toast($"ЛОВУШКА СИСТЕМЫ! HP −{dmg} ({S.myHp}/{S.myMaxHp})");
        }

        void TickCarryAndDeposit()
        {
            if (_carried != null)
            {
                var target = _player.transform.position + Vector3.up * 2.2f;
                _carried.body.position = Vector3.Lerp(_carried.body.position, target, Mathf.Min(14f * Time.deltaTime, 1f));
                if (Vector3.Distance(_carried.body.position, PadPos) < PadRadius + 0.6f)
                {
                    var l = _carried;
                    DropLoot();
                    l.deposited = true;
                    float got = S.DepositValue(l.value);
                    Destroy(l.body.gameObject);
                    string combo = S.ComboCount > 1 ? $"  КОМБО ×{S.ComboMult:0.0} ({S.ComboCount} подряд)" : "";
                    Sfx.Play("deposit");
                    _hud?.Toast($"◈ +{(int)got} — внесено! Добыча {(int)S.access}%{combo}");
                    if (!S.evacOpen && S.access >= 100f) OpenEvac(false);
                }
            }
        }

        void TickBugAndRevive(float dt)
        {
            if (!S.myBug) return;
            if (Vector3.Distance(_player.transform.position, PadPos) < PadRadius)
            {
                _reviveT += dt;
                _hud?.SetPrompt($"реанимация у портала… {(int)(_reviveT / 3f * 100)}%");
                if (_reviveT >= 3f)
                {
                    _reviveT = 0f;
                    S.myBug = false; S.myHp = 1;
                    S.ApplyAlarm(5f);
                    _player.SetBug(false);
                    _hud?.Toast("ПЕРЕЗАПУСК: 1 HP. Аккуратнее!");
                }
            }
            else _reviveT = 0f;
        }

        void OpenEvac(bool forced)
        {
            S.evacOpen = true;
            S.wipeForced = forced;
            S.evacLeft = forced ? GameState.WIPE_EVAC_TIME : GameState.EVAC_TIME;
            if (!forced) S.alarm = Mathf.Max(S.alarm, 58f);
            _hud?.Toast(forced ? $"СТИРАНИЕ УЗЛА: {(int)S.evacLeft}с — В КРУГ!" : $"КВОТА ВЗЯТА! Эвакуация {(int)S.evacLeft}с — в круг у портала!");
            _hud?.SetObjective("ЭВАКУАЦИЯ: встань в круг у портала!");
        }

        void TickEvac(float dt)
        {
            if (!S.evacOpen)
            {
                if (S.alarm >= 99.9f) OpenEvac(true);
                return;
            }
            S.evacLeft -= dt;
            bool inPad = Vector3.Distance(_player.transform.position, PadPos) <= PadRadius && !S.myBug;
            if (S.evacLeft <= 0f) { Finish(S.access >= 100f, $"Портал закрылся. Вынесено {(int)S.access}% квоты"); return; }
            if (inPad && S.access >= 100f && S.evacLeft < GameState.EVAC_TIME - 3f)
                Finish(true, "Чистый уход — система в ярости");
        }

        void TickSystemScreen()
        {
            if (_sysScreen == null) return;
            string extra = Frozen ? "\n// ЗАМОРОЖЕНА //" : Time.time < _markedUntil ? "\nЦЕЛЬ ПОМЕЧЕНА" : "";
            _sysScreen.text = $"СИСТЕМА {S.raid.av}\nчувствительность {S.raid.sensitivity} · роботов {_guards.Count}\nтревога {(int)S.alarm}% · {S.AlarmPhaseName()}{extra}";
        }

        void Finish(bool victory, string reason)
        {
            if (_done) return;
            _done = true;
            Sfx.Play(victory ? "win" : "fail", 0.5f);
            S.FinishHack(victory);
            _player.controlEnabled = false;
            Cursor.lockState = CursorLockMode.None;
            Cursor.visible = true;
            BuildResults(victory, reason);
        }

        void BuildResults(bool victory, string reason)
        {
            var canvasGo = new GameObject("Results", typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
            var canvas = canvasGo.GetComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = 60;
            var dim = new GameObject("dim", typeof(RectTransform)).AddComponent<Image>();
            dim.transform.SetParent(canvasGo.transform, false);
            dim.rectTransform.anchorMin = Vector2.zero; dim.rectTransform.anchorMax = Vector2.one;
            dim.rectTransform.offsetMin = Vector2.zero; dim.rectTransform.offsetMax = Vector2.zero;
            dim.color = new Color(0, 0.01f, 0.02f, 0.88f);

            MakeUiText(canvasGo.transform, victory ? "СЕРВЕР ВЗЛОМАН" : "РЕЙД ПРОВАЛЕН", new Vector2(0, 140), 44,
                victory ? GameData.INFECTED : new Color(1f, 0.3f, 0.4f));
            MakeUiText(canvasGo.transform, reason, new Vector2(0, 80), 22, new Color(0.88f, 0.95f, 1f));
            MakeUiText(canvasGo.transform, $"Вынесено ◈{S.lastDelivered} за {S.lastDeposits} ходок", new Vector2(0, 40), 20, new Color(0.6f, 0.75f, 0.85f));
            MakeUiText(canvasGo.transform,
                $"Карьера: {S.career["deposits"]} вносов · {S.career["tasks"]} задач · {S.career["raids"]} рейдов · ◈{S.career["delivered"]} всего",
                new Vector2(0, 4), 17, new Color(0.55f, 0.65f, 0.75f));

            var btnGo = new GameObject("btn", typeof(RectTransform));
            btnGo.transform.SetParent(canvasGo.transform, false);
            var rt = btnGo.GetComponent<RectTransform>();
            rt.sizeDelta = new Vector2(360, 56);
            rt.anchoredPosition = new Vector2(0, -80);
            btnGo.AddComponent<Image>().color = new Color(0.05f, 0.2f, 0.18f, 0.95f);
            var btn = btnGo.AddComponent<Button>();
            btn.onClick.AddListener(() => App.SceneFlow.GoGrid());
            MakeUiText(btnGo.transform, "ВЕРНУТЬСЯ В ГРИД", Vector2.zero, 22, GameData.INFECTED);
        }

        static void MakeUiText(Transform parent, string s, Vector2 pos, int size, Color c)
        {
            var go = new GameObject("t", typeof(RectTransform));
            go.transform.SetParent(parent, false);
            var t = go.AddComponent<Text>();
            t.font = Build.UIFont; t.text = s; t.fontSize = size; t.color = c;
            t.alignment = TextAnchor.MiddleCenter;
            t.horizontalOverflow = HorizontalWrapMode.Overflow;
            t.verticalOverflow = VerticalWrapMode.Overflow;
            t.rectTransform.anchoredPosition = pos;
            t.rectTransform.sizeDelta = new Vector2(1000, 60);
        }
    }
}
