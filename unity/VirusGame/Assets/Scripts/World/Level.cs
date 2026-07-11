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
        // зона выноса: у архетипа «зеркальный прокси» переезжает по залу
        Vector3 _padPos = new(-27, 0, 0);
        Vector3 PadPos => _padPos;
        const float PadRadius = 3.6f;
        const float HookSpeed = 11.5f, HookReturn = 14f, HookRange = 32f;

        GameState S => GameState.I;
        Player.VirusPlayer _player;
        UI.Hud _hud;
        System.Random _rng;
        float _hallW, _hallD;

        class Loot
        {
            public Transform body; public Rigidbody rb; public float value; public int weight;
            public bool carried, deposited; public GameObject beacon;
            public bool fake;            // почтовый узел: спам-пустышка (внос = тревога)
            public bool fragile;         // хрупкий: жёсткие удары режут цену, потом бьётся
            public float value0;         // цена на спавне (порог «разбился»)
            public float lastHitT;
            public bool hot;             // горячий пакет: греется в руках — эстафета [F]
            public float heat;
            public bool hotWarned;
            public bool mimic;           // приманка: при подборе прыгает на игрока
            public Material mat;         // эмиссия горячего: жёлтый → алый
            public int carrier;          // кооп: id носильщика (0 — свободен)
            public Vector3 netPos;       // кооп: позиция от чужого носильщика
            public bool hasNet;
        }
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
            public Vector3 netPos;       // кооп-реплика: цель от директора
            public float netRy;
            public bool hasNet;
        }
        readonly List<Guard> _guards = new();

        class Hook { public Transform t; public Guard owner; public Vector3 dir; public bool ret; public bool caught; public Vector3 netPos; }
        readonly List<Hook> _hooks = new();

        // ── кооп: директор рейда (наименьший id в узле) владеет системой ──
        // Директор симулирует тревогу/роботов/крюки и рассылает их; остальные
        // видят реплики и засчитывают урон по себе сами. Ловушки — личные.
        public static Level Current { get; private set; }
        string _netScene = "";
        bool _coop;
        bool _director = true;
        readonly List<Net.NetManager.PeerInfo> _peers = new();
        readonly Dictionary<int, Hook> _hookReplicas = new();   // индекс робота → реплика крюка
        float _coopTimer, _netPosTimer, _netStateTimer, _lootPosTimer;
        bool _helperActive;

        // статусы системы/активок (метки Time.time)
        float _frozenUntil, _decoyUntil, _cloakUntil, _markedUntil, _hookedUntil, _abilityCd;
        Vector3 _decoyPos;
        Guard _hookedBy;

        AudioSource _ambience;

        // ── мутатор рейда: случайный твист каждого захода ──
        string _mutator = "";
        string _mutatorDesc = "";
        int _goldIndex = -1;
        float _hookAlarmGate = 50f, _hookCdScale = 1f, _chaseSpeed = 6f;

        // ── архетип сервера: постоянное ПРАВИЛО узла (сеется от сида кампании) ──
        string _arch = "";
        readonly List<Transform> _beams = new();     // bank: лазерная гребёнка
        readonly List<float> _beamDir = new();
        float _beamHitLock;
        Transform _portalRoot;                       // proxy: портал-мигрант
        int _padIdx;
        float _padSwitchT;
        bool _padWarned;
        float _darkT;                                // dark: цикл затемнения
        int _darkPhase;                              // 0 свет · 1 мерцание · 2 тьма
        Color _ambSky0, _ambEq0, _ambGnd0;
        float _fogDensity0;
        float _scanT;                                // scan: проверка целостности
        int _scanPhase;                              // 0 тихо · 1 отсчёт · 2 скан
        bool _scanBusted;
        Material _scanMat;

        // ── мимик и сводка неприятностей рейда (для экрана результатов) ──
        GameObject _mimic;                           // краб, вцепившийся в игрока
        float _mimicSince, _jamNoted, _morphAt;
        int _statFragileBroken, _statOverheats, _statMimics;

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

        // ── мутатор: случайный твист рейда (обучение Т0 — без сюрпризов) ──
        void RollMutator()
        {
            if (S.raid.tier == 0 || _rng.NextDouble() < 0.35) return;   // часть рейдов «чистые»
            int roll = _rng.Next(5);
            // конфликт с архетипом: игровой сервер сам про гравитацию,
            // почтовый сам про «лишний» лут — мутатор уступает правилу узла
            if ((_arch == "game" && roll == 1) || (_arch == "mail" && roll == 3)) return;
            switch (roll)
            {
                case 0:
                    _mutator = "gold";
                    _mutatorDesc = "ЖИРНЫЙ КУШ — где-то лежит золотой файл ×3";
                    _goldIndex = _rng.Next(S.raid.files);
                    break;
                case 1:
                    _mutator = "lowgrav";
                    _mutatorDesc = "НЕВЕСОМОСТЬ — прыжки выше, падения мягче";
                    break;
                case 2:
                    _mutator = "slippery";
                    _mutatorDesc = "СКОЛЬЗКИЙ ПОЛ — разгон и торможение как на льду";
                    break;
                case 3:
                    _mutator = "double";
                    _mutatorDesc = "ДВОЙНОЙ ЛУТ, ДВОЙНАЯ ТРЕВОГА";
                    S.raid.files = (int)(S.raid.files * 1.6f);
                    S.raid.creep *= 1.7f;
                    break;
                case 4:
                    _mutator = "hooks";
                    _mutatorDesc = "БЕШЕНЫЕ КРЮКИ — летят с любой тревоги, но роботы ленивые";
                    _hookAlarmGate = 5f;
                    _hookCdScale = 0.5f;
                    _chaseSpeed = 4.4f;
                    break;
            }
        }

        void ApplyPlayerMutator()
        {
            if (_mutator == "lowgrav") _player.gravityScale = 0.5f;
            if (_mutator == "slippery") _player.accelScale = 0.32f;
            if (_arch == "game") _player.gravityScale = 0.62f;   // чит-гравитация сервера
        }

        void Start()
        {
            if (S.raid == null)   // прямой запуск сцены — тестовый рейд
            {
                if (S.gridNodes.Count == 0) S.NewCampaign();
                S.StartHack(S.gridNodes[0]);
            }
            // тестовые крюки смоук-рана (боевой запуск их не передаёт):
            // -arch <имя> навязывает архетип, -hot подкладывает горячие пакеты
            var bootArgs = System.Environment.GetCommandLineArgs();
            int archAt = System.Array.IndexOf(bootArgs, "-arch");
            if (archAt >= 0 && archAt + 1 < bootArgs.Length && GameData.ARCHETYPES.ContainsKey(bootArgs[archAt + 1]))
                S.raid.arch = bootArgs[archAt + 1];
            if (System.Array.IndexOf(bootArgs, "-hot") >= 0 && S.raid.hot == 0) S.raid.hot = 2;
            Current = this;
            _netScene = "raid:" + (S.currentNode?.id ?? -1);
            _rng = new System.Random(S.raid.seed);
            _arch = S.raid.arch ?? "";
            _hallW = 70f + (float)_rng.NextDouble() * 18f;
            _hallD = 46f + (float)_rng.NextDouble() * 14f;
            _accent = GameData.TIER_COLORS[S.raid.tier];
            _theme = Theme();
            RollMutator();
            _trapTimer = S.raid.trapInterval;

            BuildEnvironment();
            BuildArena();
            BuildPortal();
            SpawnLoot();
            SpawnGuards();
            SpawnFieldTasks();
            BuildJamConsole();
            BuildArchetype();
            SpawnPlayer();
            ApplyPlayerMutator();

            _hud = FindFirstObjectByType<UI.Hud>();
            if (_hud != null)
            {
                _hud.raidMode = true;
                _hud.Toast($"{S.raid.name} · {GameData.TIERS[S.raid.tier].name} · выносим лут и тихо!");
                if (S.raid.assist > 0)
                    _hud.Toast($"ВСПОМОГАТЕЛЬНЫЙ ВЗЛОМ: {S.raid.assist} серверов зоны помогают (−{(int)(S.raid.assistK * 100)}% защиты)");
                string archLine = _arch != "" ? $"{GameData.ARCHETYPES[_arch].twist} · " : "";
                if (_mutator != "")
                    _hud.SetObjective($"{archLine}МУТАТОР: {_mutatorDesc} · лут в зону выноса");
                else
                    _hud.SetObjective($"{archLine}Тащи лут в круг у портала — 100% квоты");
                if (_arch != "")
                    _hud.Toast($"{GameData.ARCHETYPES[_arch].name} — {GameData.ARCHETYPES[_arch].twist}");
                if (S.raid.hot > 0)
                    _hud.Toast("ГОРЯЧИЕ ПАКЕТЫ в хранилище: греются в руках — сбрасывай или перекидывай [F] по цепочке!");
                if (S.avCounter != "")
                    _hud.Toast($"⚠ {S.raid.av} ИЗУЧИЛ ВАС — {GameState.AV_COUNTER_DESC[S.avCounter]}");
            }
            // атмосфера: мотыльки данных по залу, вихрь над зоной выноса,
            // отражения неона на полу (probe вместо тяжёлого SSR)
            Fx.DataMotes(transform, new Vector3(0, 3f, 0), new Vector3(_hallW - 6f, 5.5f, _hallD - 6f),
                _accent, 45f);
            Fx.ReflectionProbe(transform, new Vector3(0, 3.4f, 0), new Vector3(_hallW, 8f, _hallD));

            _ambience = Sfx.Ambient("hum", 0.22f);   // гул серверной, густеет с тревогой

            BuildFlashOverlay();
            BuildPadArrow();
            BuildMinimap();
            StartCoroutine(EnterAnimation());

            // автотест полного цикла: победа → возврат в Грид (ловля глюков перехода)
            if (System.Array.IndexOf(System.Environment.GetCommandLineArgs(), "-autowin") >= 0)
                StartCoroutine(AutoWin());
            // автофиниш БЕЗ перехода: экран результатов остаётся — для теста кнопки
            if (System.Array.IndexOf(System.Environment.GetCommandLineArgs(), "-autofinish") >= 0)
                StartCoroutine(AutoFinish());
        }

        System.Collections.IEnumerator AutoFinish()
        {
            yield return new WaitForSeconds(6f);
            S.access = 100f;
            Finish(true, "автотест кнопки результатов");
        }

        System.Collections.IEnumerator AutoWin()
        {
            yield return new WaitForSeconds(8f);
            S.access = 100f;
            Finish(true, "автотест перехода");
            yield return new WaitForSeconds(2f);
            App.SceneFlow.GoGrid();
        }

        // покинуть рейд из паузы: считается провалом, дальше экран результатов
        public void Abort()
        {
            if (_done) return;
            Finish(false, "Рейд прерван — стая отступила");
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

            // рамка + скруглённая подложка в стиле UIKit
            UI.UIKit.Panel(canvasGo.transform, new Vector2(1, 1), new Vector2(-22, -58),
                new Vector2(MapW + 4, MapH + 4), new Color(UI.UIKit.Accent.r, UI.UIKit.Accent.g, UI.UIKit.Accent.b, 0.28f));
            var bg = UI.UIKit.Panel(canvasGo.transform, new Vector2(1, 1), new Vector2(-24, -60),
                new Vector2(MapW, MapH), UI.UIKit.PanelBg);
            _mapRoot = bg.rectTransform;

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

        // ── брифинг-карточка входа: узел, архетип, контрмера АВ, контракты.
        // Все новые системы собраны в один читаемый момент — каждый рейд
        // начинается как событие, а не как загрузка.
        Text MakeBriefText(Transform parent, string s, Vector2 pos, int size, Color c)
        {
            var go = new GameObject("brief", typeof(RectTransform));
            go.transform.SetParent(parent, false);
            var t = go.AddComponent<Text>();
            t.font = Build.UIFont;
            t.fontSize = size;
            t.alignment = TextAnchor.MiddleCenter;
            t.color = c;
            t.horizontalOverflow = HorizontalWrapMode.Overflow;
            t.rectTransform.anchoredPosition = pos;
            t.rectTransform.sizeDelta = new Vector2(1400, 60);
            t.text = s;
            return t;
        }

        IEnumerator EnterAnimation()
        {
            var canvasGo = new GameObject("Fade", typeof(Canvas), typeof(CanvasScaler));
            var canvas = canvasGo.GetComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = 90;
            var scaler = canvasGo.GetComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1600, 900);
            var go = new GameObject("dim", typeof(RectTransform));
            go.transform.SetParent(canvasGo.transform, false);
            _fade = go.AddComponent<Image>();
            var rt = _fade.rectTransform;
            rt.anchorMin = Vector2.zero; rt.anchorMax = Vector2.one;
            rt.offsetMin = Vector2.zero; rt.offsetMax = Vector2.zero;
            _fade.color = new Color(0.0f, 0.01f, 0.02f, 1f);

            var texts = new List<Text>
            {
                MakeBriefText(canvasGo.transform, $">> инъекция в {S.raid.name} · {GameData.TIERS[S.raid.tier].shortName} · обход {S.raid.av}",
                    new Vector2(0, 120), 26, GameData.INFECTED),
            };
            if (_arch != "")
            {
                var a = GameData.ARCHETYPES[_arch];
                texts.Add(MakeBriefText(canvasGo.transform, a.name, new Vector2(0, 58), 46, a.color));
                texts.Add(MakeBriefText(canvasGo.transform, a.twist, new Vector2(0, 14), 18,
                    new Color(0.8f, 0.9f, 1f)));
            }
            if (S.avCounter != "")
                texts.Add(MakeBriefText(canvasGo.transform, "⚠ АВ ИЗУЧИЛ ВАС: " + GameState.AV_COUNTER_DESC[S.avCounter],
                    new Vector2(0, -34), 18, new Color(1f, 0.6f, 0.3f)));
            var open = new List<string>();
            foreach (var cid in S.contracts)
                if (!S.contractsDone.Contains(cid))
                    open.Add($"{GameData.CONTRACTS[cid].name} ({GameData.RewardLabel(GameData.CONTRACTS[cid].reward)})");
            if (open.Count > 0)
                texts.Add(MakeBriefText(canvasGo.transform, "Контракты стаи: " + string.Join(" · ", open),
                    new Vector2(0, -76), 15, new Color(0.6f, 0.7f, 0.8f)));

            const float dur = 2.4f;
            float t = 0f;
            while (t < dur)
            {
                t += Time.deltaTime;
                float dim = 1f - Mathf.Clamp01(t / 1.5f) * 0.999f;      // фон уходит раньше
                float txtA = 1f - Mathf.Clamp01((t - 1.5f) / (dur - 1.5f)); // текст держится дольше
                _fade.color = new Color(0, 0.01f, 0.02f, dim * 0.92f);
                foreach (var tx in texts)
                    tx.color = new Color(tx.color.r, tx.color.g, tx.color.b, txtA);
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
            // лёгкая дымка вместо молока: контраст важнее «атмосферы»
            RenderSettings.fog = true;
            RenderSettings.fogColor = th.fogCol;
            RenderSettings.fogMode = FogMode.Exponential;
            RenderSettings.fogDensity = 0.0015f;
            RenderSettings.skybox = null;
            // база для архетипа «свет гаснет»: к чему возвращаться после тьмы
            _ambSky0 = RenderSettings.ambientSkyColor;
            _ambEq0 = RenderSettings.ambientEquatorColor;
            _ambGnd0 = RenderSettings.ambientGroundColor;
            _fogDensity0 = RenderSettings.fogDensity;

            var moon = new GameObject("Fill").AddComponent<Light>();
            moon.type = LightType.Directional;
            moon.color = th.lightCol;
            moon.intensity = 0.55f;   // ниже филл — спот-светильники дают контраст
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

            // ── архитектурная деталировка: стены перестают быть плоскими ──
            var trim = Mats.MetalDark(0.45f);
            var panelMat = Mats.Plastic(new Color(0.16f, 0.17f, 0.2f));
            // плинтус и карниз по периметру
            foreach (float z in new[] { -hz + 0.35f, hz - 0.35f })
            {
                Build.MeshBox(transform, new Vector3(_hallW - 0.6f, 0.35f, 0.14f), trim, new Vector3(0, 0.18f, z));
                Build.MeshBox(transform, new Vector3(_hallW - 0.6f, 0.22f, 0.12f), trim, new Vector3(0, 6.75f, z));
            }
            foreach (float x in new[] { -hx + 0.35f, hx - 0.35f })
            {
                Build.MeshBox(transform, new Vector3(0.14f, 0.35f, _hallD - 0.6f), trim, new Vector3(x, 0.18f, 0));
                Build.MeshBox(transform, new Vector3(0.12f, 0.22f, _hallD - 0.6f), trim, new Vector3(x, 6.75f, 0));
            }
            // пилястры каждые ~8 м с эмиссивной прорезью — ритм стены
            int nPil = Mathf.Max(3, (int)(_hallW / 8f));
            for (int i = 0; i <= nPil; i++)
            {
                float x = Mathf.Lerp(-hx + 2.5f, hx - 2.5f, (float)i / nPil);
                foreach (float z in new[] { -hz + 0.5f, hz - 0.5f })
                {
                    Build.Solid(transform, new Vector3(0.55f, 7f, 0.35f), th.wall, new Vector3(x, 3.5f, z));
                    Build.MeshBox(transform, new Vector3(0.08f, 5.6f, 0.38f), Mats.Neon(_accent, 0.8f), new Vector3(x, 3.2f, z));
                }
            }
            int nPilZ = Mathf.Max(2, (int)(_hallD / 8f));
            for (int i = 0; i <= nPilZ; i++)
            {
                float z = Mathf.Lerp(-hz + 3f, hz - 3f, (float)i / nPilZ);
                foreach (float x in new[] { -hx + 0.5f, hx - 0.5f })
                    Build.Solid(transform, new Vector3(0.35f, 7f, 0.55f), th.wall, new Vector3(x, 3.5f, z));
            }
            // стеновые панели с нишами и вентрешётки между пилястрами
            for (int i = 0; i < nPil; i++)
            {
                float x = Mathf.Lerp(-hx + 2.5f, hx - 2.5f, (i + 0.5f) / nPil);
                Build.MeshBox(transform, new Vector3(2.6f, 1.9f, 0.12f), panelMat, new Vector3(x, 1.6f, hz - 0.42f));
                if (i % 2 == 0)
                    for (int v = 0; v < 4; v++)
                        Build.MeshBox(transform, new Vector3(1.1f, 0.07f, 0.1f), trim, new Vector3(x, 5.2f + v * 0.16f, hz - 0.44f));
            }

            // акцент тира по периметру + плинтус-подсветка
            Build.MeshBox(transform, new Vector3(_hallW - 2, 0.06f, 0.2f), Mats.Neon(_accent, 1.2f), new Vector3(0, 0.05f, -hz + 1.2f));
            Build.MeshBox(transform, new Vector3(_hallW - 2, 0.06f, 0.2f), Mats.Neon(_accent, 1.2f), new Vector3(0, 0.05f, hz - 1.2f));

            // кабель-лотки на подвесах и КРУГЛЫЕ трубы под потолком (вдоль зала)
            var pipeMat = Mats.MetalDark(0.55f);
            for (int i = 0; i < 4; i++)
            {
                float z = Mathf.Lerp(-hz + 4f, hz - 4f, (i + 0.5f) / 4f) + (float)_rng.NextDouble() * 1.6f - 0.8f;
                float y = 6.9f - i * 0.12f;
                var pipe = Build.Prim(PrimitiveType.Cylinder, transform,
                    new Vector3(0.16f, (_hallW - 3f) * 0.5f, 0.16f), pipeMat, new Vector3(0, y, z));
                pipe.transform.localRotation = Quaternion.Euler(0, 0, 90);
                // подвесы к потолку каждые ~7 м
                for (float sx = -hx + 4f; sx < hx - 3f; sx += 7f)
                    Build.MeshBox(transform, new Vector3(0.05f, 7.25f - y, 0.05f), pipeMat, new Vector3(sx, (y + 7.25f) * 0.5f, z));
            }
            for (int i = 0; i < 2; i++)
            {
                float x = Mathf.Lerp(-hx + 6f, hx - 6f, i);
                var pipe = Build.Prim(PrimitiveType.Cylinder, transform,
                    new Vector3(0.22f, (_hallD - 3f) * 0.5f, 0.22f), pipeMat, new Vector3(x, 6.7f, 0));
                pipe.transform.localRotation = Quaternion.Euler(90, 0, 0);
            }

            // потолочные светильники в утопленных нишах с рамкой
            for (int gx = 0; gx < 3; gx++)
                for (int gz = 0; gz < 2; gz++)
                {
                    var lp = new Vector3((gx - 1) * _hallW * 0.3f, 6.95f, (gz - 0.5f) * _hallD * 0.42f);
                    Build.MeshBox(transform, new Vector3(5.1f, 0.22f, 2.2f), trim, lp + Vector3.up * 0.1f);
                    Build.MeshBox(transform, new Vector3(4.6f, 0.14f, 1.7f), Mats.Neon(th.lightCol, 2.4f), lp);
                    var sl = Build.SpotDown(transform, lp + Vector3.down * 0.3f, th.lightCol, 4.6f, 17f);
                    sl.shadows = LightShadows.Soft;
                }

            BuildThemeProps(hx, hz);

            // экран СИСТЕМЫ на стене: корпус, рамка, кронштейны
            Build.MeshBox(transform, new Vector3(11.4f, 5f, 0.3f), trim, new Vector3(6, 3.4f, -hz + 0.5f));
            Build.MeshBox(transform, new Vector3(11, 4.6f, 0.5f), Mats.Plastic(new Color(0.08f, 0.09f, 0.12f)), new Vector3(6, 3.4f, -hz + 0.6f));
            for (int s = -1; s <= 1; s += 2)
                Build.MeshBox(transform, new Vector3(0.3f, 1.4f, 0.5f), trim, new Vector3(6 + s * 5.2f, 6.4f, -hz + 0.55f));
            _sysScreen = Build.Label(transform, "", new Vector3(6, 3.4f, -hz + 1.0f), 3.4f, new Color(0.75f, 0.95f, 1f), false);
            // TextMesh читаем только с одной стороны — разворачиваем к залу
            _sysScreen.transform.localRotation = Quaternion.Euler(0, 180f, 0);
        }

        // ── детальные пропы: стол на ножках + монитор на подставке + клавиатура ──
        void Desk(Vector3 pos, float yaw, Material top, Color screenCol, bool screenOn = true)
        {
            var root = new GameObject("desk").transform;
            root.SetParent(transform, false);
            root.localPosition = pos;
            root.localRotation = Quaternion.Euler(0, yaw, 0);
            var legMat = Mats.MetalDark(0.5f);
            Build.MeshBox(root, new Vector3(2.1f, 0.07f, 1.05f), top, new Vector3(0, 0.76f, 0));
            foreach (var (lx, lz) in new[] { (-0.95f, 0.42f), (0.95f, 0.42f), (-0.95f, -0.42f), (0.95f, -0.42f) })
                Build.MeshBox(root, new Vector3(0.07f, 0.76f, 0.07f), legMat, new Vector3(lx, 0.38f, lz));
            Build.Collide(root, new Vector3(2.1f, 0.86f, 1.05f), new Vector3(0, 0.43f, 0));
            // монитор: подставка, шея, корпус, экран
            Build.MeshBox(root, new Vector3(0.34f, 0.03f, 0.24f), legMat, new Vector3(-0.2f, 0.81f, 0.22f));
            Build.MeshBox(root, new Vector3(0.05f, 0.22f, 0.05f), legMat, new Vector3(-0.2f, 0.92f, 0.26f));
            Build.MeshBox(root, new Vector3(0.92f, 0.58f, 0.06f), Mats.Plastic(new Color(0.07f, 0.08f, 0.09f)), new Vector3(-0.2f, 1.3f, 0.28f));
            Build.MeshBox(root, new Vector3(0.84f, 0.5f, 0.02f), screenOn ? Mats.Neon(screenCol, 1.3f) : Mats.Plastic(new Color(0.03f, 0.03f, 0.04f)),
                new Vector3(-0.2f, 1.3f, 0.24f));
            // клавиатура и системник
            Build.MeshBox(root, new Vector3(0.52f, 0.03f, 0.2f), Mats.Plastic(new Color(0.13f, 0.14f, 0.16f)), new Vector3(-0.2f, 0.81f, -0.12f));
            Build.MeshBox(root, new Vector3(0.24f, 0.5f, 0.5f), Mats.Plastic(new Color(0.1f, 0.11f, 0.13f)), new Vector3(0.75f, 0.25f, 0.1f));
            Build.MeshBox(root, new Vector3(0.02f, 0.05f, 0.05f), Mats.Neon(new Color(0.3f, 1f, 0.5f), 2f), new Vector3(0.63f, 0.42f, -0.1f));
        }

        // серверная стойка: корпус, дверца с ручкой, ножки, LED-ряды, кабели сверху
        void Rack(Vector3 pos, float yaw)
        {
            var root = new GameObject("rack").transform;
            root.SetParent(transform, false);
            root.localPosition = pos;
            root.localRotation = Quaternion.Euler(0, yaw, 0);
            Build.MeshBox(root, new Vector3(1.4f, 2.6f, 1f), Mats.MetalDark(0.4f), new Vector3(0, 1.42f, 0));
            Build.Collide(root, new Vector3(1.4f, 2.75f, 1f), new Vector3(0, 1.38f, 0));
            Build.MeshBox(root, new Vector3(1.5f, 0.12f, 1.1f), Mats.MetalDark(0.55f), new Vector3(0, 0.2f, 0));
            // перфорированная дверца (слои) + ручка
            Build.MeshBox(root, new Vector3(1.24f, 2.3f, 0.05f), Mats.Metal(new Color(0.24f, 0.26f, 0.3f), 0.55f), new Vector3(0, 1.42f, -0.51f));
            Build.MeshBox(root, new Vector3(0.06f, 0.3f, 0.05f), Mats.Metal(new Color(0.6f, 0.62f, 0.66f), 0.25f), new Vector3(-0.5f, 1.5f, -0.55f));
            for (int led = 0; led < 5; led++)
                Build.MeshBox(root, new Vector3(1.1f, 0.07f, 0.03f),
                    Mats.Neon(led % 2 == 0 ? _accent : new Color(0.3f, 1f, 0.5f), 1.6f),
                    new Vector3(0, 0.6f + led * 0.44f, -0.54f));
            // жгут кабелей вверх
            for (int cbl = 0; cbl < 3; cbl++)
                Build.MeshBox(root, new Vector3(0.06f, 7.3f - 2.7f, 0.06f), Mats.MetalDark(0.6f),
                    new Vector3(-0.3f + cbl * 0.3f, 2.7f + (7.3f - 2.7f) * 0.5f - 1.35f + 1.35f, 0.3f));
        }

        // ── реквизит по теме: у каждого тира свой характер зала ──
        void BuildThemeProps(float hx, float hz)
        {
            switch (S.raid.theme)
            {
                case "home":   // жилая комната: столы с ПК, диваны, ковёр, торшер
                    for (int i = 0; i < 6; i++)
                        Desk(FreeSpot(hx, hz), R(0, 360), Mats.PlasterOld(new Color(0.42f, 0.33f, 0.24f)), new Color(0.5f, 0.75f, 1f), _rng.NextDouble() < 0.7);
                    for (int i = 0; i < 3; i++)
                    {
                        var pos = FreeSpot(hx, hz);
                        var sofa = Mats.CarpetRot();
                        var root = new GameObject("sofa").transform;
                        root.SetParent(transform, false);
                        root.localPosition = pos;
                        root.localRotation = Quaternion.Euler(0, R(0, 360), 0);
                        Build.MeshBox(root, new Vector3(2.4f, 0.45f, 1.1f), sofa, new Vector3(0, 0.35f, 0));
                        Build.MeshBox(root, new Vector3(2.4f, 0.8f, 0.3f), sofa, new Vector3(0, 0.75f, -0.45f));
                        foreach (int s in new[] { -1, 1 })
                            Build.MeshBox(root, new Vector3(0.28f, 0.65f, 1.1f), sofa, new Vector3(s * 1.2f, 0.5f, 0));
                        Build.Collide(root, new Vector3(2.6f, 1f, 1.2f), new Vector3(0, 0.5f, 0));
                    }
                    // торшеры: круглая ножка, сферический плафон, тёплый свет
                    for (int i = 0; i < 2; i++)
                    {
                        var pos = FreeSpot(hx, hz);
                        Build.Prim(PrimitiveType.Cylinder, transform, new Vector3(0.09f, 0.85f, 0.09f),
                            Mats.MetalDark(0.5f), pos + Vector3.up * 0.85f, collide: true);
                        Build.Prim(PrimitiveType.Cylinder, transform, new Vector3(0.36f, 0.03f, 0.36f),
                            Mats.MetalDark(0.5f), pos + Vector3.up * 0.03f);
                        Build.Prim(PrimitiveType.Sphere, transform, Vector3.one * 0.46f,
                            Mats.Neon(new Color(1f, 0.8f, 0.55f), 1.8f), pos + Vector3.up * 1.85f);
                        Build.Omni(transform, pos + Vector3.up * 1.7f, new Color(1f, 0.82f, 0.6f), 1.6f, 7f);
                    }
                    // круглый журнальный столик
                    for (int i = 0; i < 2; i++)
                    {
                        var pos = FreeSpot(hx, hz);
                        Build.Prim(PrimitiveType.Cylinder, transform, new Vector3(1.1f, 0.04f, 1.1f),
                            Mats.PlasterOld(new Color(0.36f, 0.28f, 0.2f)), pos + Vector3.up * 0.52f, collide: true);
                        Build.Prim(PrimitiveType.Cylinder, transform, new Vector3(0.12f, 0.26f, 0.12f),
                            Mats.MetalDark(0.5f), pos + Vector3.up * 0.26f);
                    }
                    break;
                case "office":   // кубиклы: столы, перегородки с рамами, кулер
                    for (int row = 0; row < 3; row++)
                        for (int k = 0; k < 4; k++)
                        {
                            var pos = new Vector3(-hx + 10f + row * (hx * 0.55f), 0, -hz + 6f + k * ((hz * 2f - 12f) / 4f));
                            if (Vector3.Distance(pos, PadPos) < 9f) continue;
                            Desk(pos, (k % 2) * 180f, Mats.Plastic(new Color(0.5f, 0.47f, 0.42f)), new Color(0.6f, 0.8f, 0.9f), _rng.NextDouble() < 0.5);
                            // перегородка с алюминиевой рамой
                            var part = new GameObject("part").transform;
                            part.SetParent(transform, false);
                            part.localPosition = pos + new Vector3(0, 0, 0.62f);
                            Build.MeshBox(part, new Vector3(2.1f, 1.5f, 0.07f), Mats.PlasterOld(new Color(0.38f, 0.4f, 0.36f)), new Vector3(0, 0.75f, 0));
                            Build.MeshBox(part, new Vector3(2.2f, 0.06f, 0.1f), Mats.MetalDark(0.4f), new Vector3(0, 1.52f, 0));
                            foreach (int s in new[] { -1, 1 })
                                Build.MeshBox(part, new Vector3(0.06f, 1.55f, 0.1f), Mats.MetalDark(0.4f), new Vector3(s * 1.06f, 0.77f, 0));
                            Build.Collide(part, new Vector3(2.2f, 1.6f, 0.12f), new Vector3(0, 0.8f, 0));
                        }
                    // кулер для воды — обязательный офисный житель (круглая бутыль)
                    var wc = FreeSpot(hx, hz);
                    Build.Solid(transform, new Vector3(0.4f, 1f, 0.4f), Mats.Plastic(new Color(0.75f, 0.78f, 0.8f)), wc + Vector3.up * 0.5f);
                    Build.Prim(PrimitiveType.Cylinder, transform, new Vector3(0.3f, 0.18f, 0.3f),
                        Mats.Neon(new Color(0.45f, 0.7f, 0.95f), 0.7f), wc + Vector3.up * 1.18f);
                    Build.Prim(PrimitiveType.Sphere, transform, Vector3.one * 0.3f,
                        Mats.Neon(new Color(0.45f, 0.7f, 0.95f), 0.7f), wc + Vector3.up * 1.4f);
                    // фикусы в круглых кадках — живой офис
                    for (int i = 0; i < 3; i++)
                    {
                        var pp = FreeSpot(hx, hz);
                        Build.Prim(PrimitiveType.Cylinder, transform, new Vector3(0.3f, 0.22f, 0.3f),
                            Mats.PlasterOld(new Color(0.35f, 0.24f, 0.18f)), pp + Vector3.up * 0.22f, collide: true);
                        Build.Prim(PrimitiveType.Cylinder, transform, new Vector3(0.05f, 0.35f, 0.05f),
                            Mats.PlasterOld(new Color(0.3f, 0.22f, 0.14f)), pp + Vector3.up * 0.7f);
                        var leaf = Mats.Moss(new Color(0.16f, 0.34f, 0.14f));
                        Build.Prim(PrimitiveType.Sphere, transform, new Vector3(0.7f, 0.55f, 0.7f), leaf, pp + Vector3.up * 1.25f);
                        Build.Prim(PrimitiveType.Sphere, transform, new Vector3(0.45f, 0.4f, 0.45f), leaf, pp + new Vector3(0.25f, 1.55f, 0.1f));
                    }
                    break;
                case "dc":   // машинный зал: ряды стоек + фальшпол-плиты
                    for (int row = 0; row < 3; row++)
                    {
                        float x = -hx + 12f + row * (hx * 0.6f);
                        for (int k = 0; k < 5; k++)
                        {
                            var pos = new Vector3(x, 0, -hz + 5f + k * ((hz * 2f - 10f) / 5f));
                            if (Vector3.Distance(pos, PadPos) < 9f) continue;
                            Rack(pos, row % 2 == 0 ? 0f : 180f);
                        }
                        // холодный коридор: световая полоса на полу вдоль ряда
                        Build.MeshBox(transform, new Vector3(0.14f, 0.04f, hz * 2f - 10f), Mats.Neon(new Color(0.4f, 0.75f, 1f), 0.9f), new Vector3(x + 1.4f, 0.03f, 0));
                        // цилиндрический бак охлаждения в торце ряда
                        var tank = new Vector3(x, 0, hz - 6.5f);
                        Build.Prim(PrimitiveType.Cylinder, transform, new Vector3(1.3f, 1.5f, 1.3f),
                            Mats.Metal(new Color(0.5f, 0.56f, 0.62f), 0.45f), tank + Vector3.up * 1.5f, collide: true);
                        Build.Prim(PrimitiveType.Sphere, transform, new Vector3(1.3f, 0.7f, 1.3f),
                            Mats.Metal(new Color(0.5f, 0.56f, 0.62f), 0.45f), tank + Vector3.up * 3.05f);
                        Build.Prim(PrimitiveType.Cylinder, transform, new Vector3(0.12f, 1.85f, 0.12f),
                            Mats.MetalDark(0.55f), tank + new Vector3(0.7f, 5.2f, 0));
                    }
                    break;
                default:   // бункер: бетонные блоки, армейские ящики с крышками
                    for (int i = 0; i < 6; i++)
                    {
                        var pos = FreeSpot(hx, hz);
                        float h = R(1.1f, 2.4f);
                        Build.Solid(transform, new Vector3(R(1.6f, 3f), h, R(1.4f, 2.4f)), Mats.Concrete(new Color(0.3f, 0.3f, 0.31f)), pos + Vector3.up * (h * 0.5f));
                        if (_rng.NextDouble() < 0.6)
                            Build.MeshBox(transform, new Vector3(1.4f, 0.18f, 0.06f), Mats.Hazard(), pos + new Vector3(0, h * 0.5f, -R(0.7f, 1.2f)));
                    }
                    for (int i = 0; i < 5; i++)
                    {
                        var pos = FreeSpot(hx, hz);
                        var root = new GameObject("crate").transform;
                        root.SetParent(transform, false);
                        root.localPosition = pos;
                        root.localRotation = Quaternion.Euler(0, R(0, 360), 0);
                        var box = Mats.Metal(new Color(0.3f, 0.32f, 0.26f), 0.6f);
                        Build.MeshBox(root, new Vector3(1.5f, 0.7f, 0.9f), box, new Vector3(0, 0.35f, 0));
                        Build.MeshBox(root, new Vector3(1.56f, 0.12f, 0.96f), Mats.Metal(new Color(0.36f, 0.38f, 0.3f), 0.55f), new Vector3(0, 0.76f, 0));
                        foreach (int s in new[] { -1, 1 })   // защёлки
                            Build.MeshBox(root, new Vector3(0.1f, 0.2f, 0.04f), Mats.Metal(new Color(0.6f, 0.6f, 0.55f), 0.3f), new Vector3(s * 0.5f, 0.6f, -0.46f));
                        Build.Collide(root, new Vector3(1.56f, 0.85f, 0.96f), new Vector3(0, 0.42f, 0));
                    }
                    // кластеры бочек — круглый армейский быт
                    for (int i = 0; i < 3; i++)
                    {
                        var bp = FreeSpot(hx, hz);
                        var barrel = Mats.Rust(new Color(0.34f, 0.3f, 0.22f));
                        int n2 = 2 + _rng.Next(2);
                        for (int b2 = 0; b2 < n2; b2++)
                        {
                            var off = new Vector3(Mathf.Cos(b2 * 2.4f) * 0.55f, 0, Mathf.Sin(b2 * 2.4f) * 0.55f);
                            Build.Prim(PrimitiveType.Cylinder, transform, new Vector3(0.5f, 0.55f, 0.5f),
                                barrel, bp + off + Vector3.up * 0.55f, collide: true);
                            Build.Prim(PrimitiveType.Cylinder, transform, new Vector3(0.52f, 0.02f, 0.52f),
                                Mats.MetalDark(0.5f), bp + off + Vector3.up * 0.85f);
                        }
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
            // весь портал живёт под _portalRoot: архетип «прокси» двигает его
            // целиком одним сдвигом корня (корень в нуле — локальные == мировые)
            _portalRoot = new GameObject("portal").transform;
            _portalRoot.SetParent(transform, false);
            var pr = _portalRoot;
            // приглушённая площадка: тёмная плита, неоновая РАМКА по краю и малый центр
            Build.MeshBox(pr, new Vector3(PadRadius * 2, 0.1f, PadRadius * 2), Mats.Plastic(new Color(0.05f, 0.1f, 0.09f)), PadPos + Vector3.up * 0.05f);
            float inR = PadRadius * 2 - 0.5f;
            foreach (int s in new[] { -1, 1 })
            {
                Build.MeshBox(pr, new Vector3(inR, 0.04f, 0.18f), Mats.Neon(GameData.INFECTED, 1.1f), PadPos + new Vector3(0, 0.11f, s * (inR * 0.5f - 0.09f)));
                Build.MeshBox(pr, new Vector3(0.18f, 0.04f, inR), Mats.Neon(GameData.INFECTED, 1.1f), PadPos + new Vector3(s * (inR * 0.5f - 0.09f), 0.11f, 0));
            }
            Build.MeshBox(pr, new Vector3(1.4f, 0.05f, 1.4f), Mats.Neon(GameData.INFECTED, 1.4f), PadPos + Vector3.up * 0.12f);
            // hazard-рамка по периметру зоны выноса
            float b = PadRadius + 0.55f;
            Build.MeshBox(pr, new Vector3(b * 2, 0.06f, 0.35f), Mats.Hazard(), PadPos + new Vector3(0, 0.04f, -b));
            Build.MeshBox(pr, new Vector3(b * 2, 0.06f, 0.35f), Mats.Hazard(), PadPos + new Vector3(0, 0.04f, b));
            Build.MeshBox(pr, new Vector3(0.35f, 0.06f, b * 2), Mats.Hazard(), PadPos + new Vector3(-b, 0.04f, 0));
            Build.MeshBox(pr, new Vector3(0.35f, 0.06f, b * 2), Mats.Hazard(), PadPos + new Vector3(b, 0.04f, 0));
            Build.Omni(pr, PadPos + Vector3.up * 2f, new Color(0.1f, 0.8f, 0.9f), 1.6f, 8f);
            // вместо летающего текста — круглые колонны-маяки по углам
            for (int sx = -1; sx <= 1; sx += 2)
                for (int sz = -1; sz <= 1; sz += 2)
                {
                    var cp = PadPos + new Vector3(sx * b, 0, sz * b);
                    Build.Prim(PrimitiveType.Cylinder, pr, new Vector3(0.24f, 1.3f, 0.24f),
                        Mats.MetalDark(0.5f), cp + Vector3.up * 1.3f, collide: true);
                    Build.Prim(PrimitiveType.Sphere, pr, Vector3.one * 0.32f,
                        Mats.Neon(GameData.INFECTED, 2.4f), cp + Vector3.up * 2.75f);
                }
            for (int i = 0; i < 3; i++)
            {
                var ch = PadPos + new Vector3(PadRadius + 1.6f + i * 1.1f, 0.03f, 0);
                var a1 = Build.MeshBox(pr, new Vector3(1.1f, 0.05f, 0.22f), Mats.Neon(GameData.INFECTED, 1.4f - i * 0.3f), ch + new Vector3(0, 0, 0.38f));
                a1.transform.localRotation = Quaternion.Euler(0, 45, 0);
                var a2 = Build.MeshBox(pr, new Vector3(1.1f, 0.05f, 0.22f), Mats.Neon(GameData.INFECTED, 1.4f - i * 0.3f), ch + new Vector3(0, 0, -0.38f));
                a2.transform.localRotation = Quaternion.Euler(0, -45, 0);
            }
            Fx.PortalSwirl(pr, PadPos + Vector3.up * 0.2f, GameData.INFECTED);
        }

        void SpawnLoot()
        {
            float hx = _hallW * 0.5f, hz = _hallD * 0.5f;
            int files = S.raid.files, crates = S.raid.crates, safes = S.raid.safes, hotN = S.raid.hot;
            for (int i = 0; i < files + crates + safes + hotN; i++)
            {
                bool hot = i >= files + crates + safes;   // греется в руках — эстафета
                bool safe = !hot && i >= files + crates;  // сейф (вес 3): T2+, только вдвоём
                bool crate = !hot && !safe && i >= files;
                var pos = new Vector3(R(-hx + 8, hx - 5), 1f, R(-hz + 4, hz - 4));
                if (pos.x < -14) pos.x = -pos.x;   // не спавним в зоне выноса
                var go = new GameObject(hot ? "hot" : safe ? "safe" : crate ? "crate" : "file");
                go.transform.SetParent(transform, false);
                go.transform.position = pos;
                var col = go.AddComponent<BoxCollider>();
                col.size = hot ? new Vector3(0.62f, 0.58f, 0.5f)
                    : safe ? new Vector3(1.35f, 1.15f, 1.1f)
                    : crate ? new Vector3(1.05f, 0.85f, 0.9f) : new Vector3(0.55f, 0.5f, 0.42f);
                var rb = go.AddComponent<Rigidbody>();
                rb.mass = hot ? 4 : safe ? 20 : crate ? 8 : 4;
                var c = hot ? new Color(1f, 0.5f, 0.15f)
                    : safe ? new Color(1f, 0.72f, 0.2f)
                    : crate ? new Color(0.29f, 0.56f, 1f) : new Color(0.22f, 0.94f, 0.66f);
                float value = hot ? R(30, 42) : safe ? R(34, 46) : crate ? R(16, 24) : R(7, 11);
                // хрупкий лут (T1+): дороже, но бьётся от ударов — не швырять!
                bool fragile = !hot && !safe && S.raid.tier >= 1 && _rng.NextDouble() < 0.26;
                if (fragile) value *= 1.4f;
                // мимик-приманка (T1+): выглядит как файл, при подборе кусает.
                // В почтовом узле спам-фауна злее. Spyware видит красную метку.
                bool mimic = !hot && !safe && !crate && !fragile && S.raid.tier >= 1
                    && _rng.NextDouble() < (_arch == "mail" ? 0.2 : 0.1);
                // мутатор ЖИРНЫЙ КУШ: один золотой файл ×3, светится издалека
                bool golden = _mutator == "gold" && i == _goldIndex && !crate && !safe && !hot;
                if (golden) mimic = false;   // золотой куш всегда настоящий
                if (golden)
                {
                    value *= 3f;
                    c = new Color(1f, 0.82f, 0.25f);
                    go.transform.localScale = Vector3.one * 1.3f;
                    Build.Omni(go.transform, Vector3.up * 0.6f, c, 1.8f, 7f);
                }
                Material hotMat = null;
                if (safe)
                {
                    // бронированный корпус + светящаяся скважина и полосы
                    Build.MeshBox(go.transform, col.size, Mats.Metal(new Color(0.2f, 0.18f, 0.14f), 0.45f), Vector3.zero);
                    Build.MeshBox(go.transform, new Vector3(col.size.x + 0.04f, 0.16f, col.size.z + 0.04f), Mats.Hazard(), new Vector3(0, 0.32f, 0));
                    Build.MeshBox(go.transform, new Vector3(col.size.x + 0.04f, 0.16f, col.size.z + 0.04f), Mats.Hazard(), new Vector3(0, -0.32f, 0));
                    Build.MeshBox(go.transform, Vector3.one * 0.18f, Mats.Neon(c, 2.6f), new Vector3(0, 0.05f, -col.size.z * 0.5f - 0.02f));
                }
                else if (hot)
                {
                    // тёмный кожух с раскалённым ядром: цвет ядра = шкала нагрева
                    Build.MeshBox(go.transform, col.size, Mats.MetalDark(0.5f), Vector3.zero);
                    hotMat = Mats.Neon(c, 1.6f);
                    Build.MeshBox(go.transform, col.size * 0.62f, hotMat, Vector3.zero);
                    Build.Omni(go.transform, Vector3.up * 0.4f, c, 1.1f, 4f);
                }
                else
                {
                    Build.MeshBox(go.transform, col.size, Mats.Neon(c, golden ? 2.2f : 0.9f), Vector3.zero);
                    if (fragile)   // стеклянный ореол: хрупкость видно издалека
                        Build.MeshBox(go.transform, col.size * 1.18f, Mats.Holo(new Color(0.8f, 0.95f, 1f), 0.5f), Vector3.zero);
                }
                var loot = new Loot
                {
                    body = go.transform, rb = rb, value = value, value0 = value,
                    weight = safe ? 3 : crate ? 2 : 1,
                    fragile = fragile, hot = hot, mat = hotMat, mimic = mimic,
                };
                _loot.Add(loot);
                if (fragile)
                    go.AddComponent<FragileWatch>().onImpact = v => OnFragileImpact(loot, v);
                if (mimic && S.HasPassive("spyware"))
                    Build.Omni(go.transform, Vector3.up * 0.5f, new Color(1f, 0.25f, 0.2f), 1.2f, 3.5f);

                var it = go.AddComponent<Interactable>();
                it.radius = 2.7f;
                bool maskVal = _arch == "mail" && !safe && !crate && !hot;   // почта прячет ценники
                it.dynamicPrompt = () =>
                {
                    if (_carried != null) return "[E] положить · [F] швырнуть";
                    if (loot.carrier != 0) return "лут у напарника";
                    string val = maskVal ? "◈ ??" : $"◈ {(int)loot.value}";
                    if (hot) return $"[E] ГОРЯЧИЙ ПАКЕТ ({val} · греется в руках!)";
                    if (safe) return $"[E] СЕЙФ ({val} · поднимать вдвоём)";
                    return $"[E] схватить лут ({val}{(crate ? " · тяжёлый" : "")}{(loot.fragile ? " · ХРУПКИЙ" : "")})";
                };
                it.enabledFn = () => !loot.deposited &&
                    (_carried == loot || (_carried == null && loot.carrier == 0));
                it.onInteract = () => ToggleCarry(loot);
            }
            if (_arch == "mail") SpawnSpam();
        }

        // хрупкий лут ударился (свободный полёт после броска/падения):
        // цена тает, на трети от исходной — вдребезги и тревога
        void OnFragileImpact(Loot l, float speed)
        {
            if (_done || l.deposited || l.carried || l.carrier != 0) return;
            if (speed < 7.5f || Time.time - l.lastHitT < 0.4f) return;
            l.lastHitT = Time.time;
            l.value *= 0.72f;
            Sfx.Play("trap", 0.25f);
            if (l.value <= l.value0 * 0.35f)
            {
                l.deposited = true;   // осколки не подобрать
                _statFragileBroken++;
                AlarmEvent(8f);
                _flashCol = new Color(1f, 0.5f, 0.6f);
                _flashA = 0.3f;
                _hud?.Toast("ХРУПКИЙ ФАЙЛ РАЗБИТ! Осколки подняли тревогу (+8)");
                int idx = _loot.IndexOf(l);
                if (l.body != null) Destroy(l.body.gameObject);
                if (_coop && idx >= 0)
                    Net.NetManager.Send(NetSync.MsgLootGone(_netScene, idx));
            }
            else _hud?.Toast($"Хрупкий файл повреждён: цена упала до ◈{(int)l.value}");
        }

        // спам-шторм: пустышки выглядят как файлы, но внос — тревога +6.
        // Выдаёт их глитч-мерцание (TickLootPulse); spyware метит их красным.
        void SpawnSpam()
        {
            float hx = _hallW * 0.5f, hz = _hallD * 0.5f;
            int fakes = Mathf.Max(2, S.raid.files / 2);
            var fileCol = new Color(0.22f, 0.94f, 0.66f);
            for (int i = 0; i < fakes; i++)
            {
                var pos = new Vector3(R(-hx + 8, hx - 5), 1f, R(-hz + 4, hz - 4));
                if (pos.x < -14) pos.x = -pos.x;
                var go = new GameObject("file");   // имя как у настоящего — не подсматривать
                go.transform.SetParent(transform, false);
                go.transform.position = pos;
                var col = go.AddComponent<BoxCollider>();
                col.size = new Vector3(0.55f, 0.5f, 0.42f);
                var rb = go.AddComponent<Rigidbody>();
                rb.mass = 4;
                Build.MeshBox(go.transform, col.size, Mats.Neon(fileCol, 0.9f), Vector3.zero);
                if (S.HasPassive("spyware"))
                    Build.Omni(go.transform, Vector3.up * 0.5f, new Color(1f, 0.25f, 0.2f), 1.2f, 3.5f);
                var loot = new Loot { body = go.transform, rb = rb, value = 0f, weight = 1, fake = true };
                _loot.Add(loot);
                var it = go.AddComponent<Interactable>();
                it.radius = 2.7f;
                it.dynamicPrompt = () => _carried == null
                    ? (loot.carrier != 0 ? "лут у напарника" : "[E] схватить лут (◈ ??)")
                    : "[E] положить · [F] швырнуть";
                it.enabledFn = () => !loot.deposited &&
                    (_carried == loot || (_carried == null && loot.carrier == 0));
                it.onInteract = () => ToggleCarry(loot);
            }
        }

        // ransomware тащит тяжёлое как лёгкое; червь страдает от груза меньше;
        // второй носильщик рядом (кооп) заметно ускоряет тяжёлый груз
        float CarryFactorFor(Loot loot, bool helper)
        {
            // сейф (вес 3): в одиночку — черепаший шаг, вдвоём — терпимо
            if (loot.weight >= 3)
            {
                float k3 = S.HasPassive("ransomware") ? 0.3f : 0.18f;
                if (helper) k3 = 0.52f;
                return k3;
            }
            float heavy = S.HasPassive("ransomware") ? 0.72f : 0.38f;
            float light = 0.78f;
            float k = loot.weight >= 2 ? heavy : light;
            if (S.HasPassive("worm")) k = Mathf.Min(k + 0.12f, 0.95f);
            if (helper && loot.weight >= 2) k = Mathf.Min(k * 1.6f, 0.92f);
            return k;
        }

        bool HelperNear()
        {
            if (!_coop) return false;
            foreach (var pr in _peers)
                if (Vector3.Distance(pr.pos, _player.transform.position) < 4f) return true;
            return false;
        }

        // ── ТЕРМИНАЛ ОПЕРАТОРА: асимметричная роль для стаи ──
        // Сев за консоль, игрок получает тактический вид сверху: видит роботов
        // и лут, ставит пинг-метки [ЛКМ], жмёт стоп-кадр системы [R] и глушит
        // фоновый рост тревоги. Сам не носит и уязвим — вся сила в голосе.
        Transform _jamConsole;
        Material _jamScreenMat;
        readonly Color _jamCol = new(0.25f, 0.9f, 1f);
        float _jamFlushT, _jamAccum;
        bool _jamming;
        bool _opMode;
        Camera _opCam;
        Camera _playerCam;
        float _opFreezeCd;
        readonly List<GameObject> _opMarks = new();
        GameObject _opCanvas;
        UnityEngine.UI.Text _opHint;

        void BuildJamConsole()
        {
            if (_arch == "avlab") return;   // КАРАНТИН: терминал изолирован — чистый стелс
            float hz = _hallD * 0.5f;
            var root = new GameObject("op_console").transform;
            root.SetParent(transform, false);
            root.localPosition = new Vector3(-2.5f, 0, -hz + 1.6f);
            Build.Solid(root, new Vector3(1.6f, 1.15f, 0.8f), Mats.MetalDark(0.45f), new Vector3(0, 0.58f, 0));
            _jamScreenMat = Mats.Neon(_jamCol, 0.7f);
            var scr = Build.MeshBox(root, new Vector3(1.2f, 0.55f, 0.07f), _jamScreenMat, new Vector3(0, 1.3f, 0.12f));
            scr.transform.localRotation = Quaternion.Euler(-26, 0, 0);
            Build.MeshBox(root, new Vector3(1.3f, 0.06f, 0.5f), Mats.Plastic(new Color(0.1f, 0.11f, 0.13f)), new Vector3(0, 1.17f, -0.14f));
            _jamConsole = root;
            var it = root.gameObject.AddComponent<Interactable>();
            it.radius = 2.6f;
            it.dynamicPrompt = () =>
                "[E] ТЕРМИНАЛ ОПЕРАТОРА: вид сверху · пинг · стоп-кадр · глушение фона";
            it.enabledFn = () => !S.myBug && !_opMode && _carried == null;
            it.onInteract = EnterOperator;
        }

        float _opEnterT;   // защита от выхода тем же нажатием E, что вошло

        void EnterOperator()
        {
            if (_opMode || S.myBug || _done) return;
            _opMode = true;
            _opEnterT = Time.time;
            _player.controlEnabled = false;
            Cursor.lockState = CursorLockMode.None;
            Cursor.visible = true;
            _playerCam = _player.GetComponentInChildren<Camera>();
            if (_playerCam != null) _playerCam.enabled = false;
            var camGo = new GameObject("OpCam", typeof(Camera));
            _opCam = camGo.GetComponent<Camera>();
            _opCam.fieldOfView = 60f;
            _opCam.nearClipPlane = 0.3f;
            _opCam.farClipPlane = 300f;
            camGo.transform.position = new Vector3(0, 52f, -8f);
            camGo.transform.rotation = Quaternion.Euler(80f, 0, 0);
            PostFx.AttachCamera(_opCam);
            // маркеры над роботами: с высоты их видно даже за стойками
            foreach (var g in _guards)
            {
                var mark = Build.MeshBox(g.t, new Vector3(0.9f, 0.25f, 0.9f),
                    Mats.Neon(new Color(1f, 0.25f, 0.2f), 3f), new Vector3(0, 7.5f, 0));
                _opMarks.Add(mark);
            }
            // подсказка управления
            _opCanvas = new GameObject("OpCanvas", typeof(Canvas), typeof(CanvasScaler));
            var cv = _opCanvas.GetComponent<Canvas>();
            cv.renderMode = RenderMode.ScreenSpaceOverlay;
            cv.sortingOrder = 35;
            _opCanvas.GetComponent<CanvasScaler>().uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            _opCanvas.GetComponent<CanvasScaler>().referenceResolution = new Vector2(1600, 900);
            var txtGo = new GameObject("hint", typeof(RectTransform));
            txtGo.transform.SetParent(_opCanvas.transform, false);
            _opHint = txtGo.AddComponent<Text>();
            _opHint.font = Build.UIFont;
            _opHint.fontSize = 20;
            _opHint.alignment = TextAnchor.MiddleCenter;
            _opHint.color = new Color(0.75f, 0.92f, 1f);
            _opHint.horizontalOverflow = HorizontalWrapMode.Overflow;
            var hintRt = _opHint.rectTransform;
            hintRt.anchorMin = new Vector2(0.5f, 0); hintRt.anchorMax = new Vector2(0.5f, 0);
            hintRt.anchoredPosition = new Vector2(0, 40);
            hintRt.sizeDelta = new Vector2(1400, 40);
            Sfx.Play("ui", 0.3f);
            _hud?.Toast("РЕЖИМ ОПЕРАТОРА: ты — глаза стаи. Говори, куда идти!");
            if (_jamScreenMat != null) _jamScreenMat.SetColor("_EmissionColor", _jamCol * 2.8f);
        }

        void ExitOperator()
        {
            if (!_opMode) return;
            _opMode = false;
            if (_opCam != null) Destroy(_opCam.gameObject);
            foreach (var m in _opMarks) if (m != null) Destroy(m);
            _opMarks.Clear();
            if (_opCanvas != null) Destroy(_opCanvas);
            if (_playerCam != null) _playerCam.enabled = true;
            if (!_done)
            {
                _player.controlEnabled = true;
                Cursor.lockState = CursorLockMode.Locked;
                Cursor.visible = false;
            }
            if (_jamScreenMat != null) _jamScreenMat.SetColor("_EmissionColor", _jamCol * 0.7f);
        }

        void TickOperator(float dt)
        {
            _opFreezeCd = Mathf.Max(_opFreezeCd - dt, 0f);
            if (!_opMode) return;
            if (S.myBug || (Input.GetKeyDown(KeyCode.E) && Time.time > _opEnterT + 0.25f))
            {
                ExitOperator();
                return;
            }
            if (_opHint != null)
                _opHint.text = "[ЛКМ] пинг-метка стае   ·   [R] СТОП-КАДР системы " +
                    (_opFreezeCd > 0f ? $"(перезарядка {(int)_opFreezeCd}с)" : "(готов)") +
                    "   ·   [E] встать";
            // пинг: клик по полу — световой столб, виден всей стае
            if (Input.GetMouseButtonDown(0) && _opCam != null)
            {
                var ray = _opCam.ScreenPointToRay(Input.mousePosition);
                if (ray.direction.y < -0.05f)
                {
                    float t = -ray.origin.y / ray.direction.y;
                    var pos = ray.origin + ray.direction * t;
                    SpawnPing(pos, true);
                }
            }
            // стоп-кадр: замораживает систему всем на 4с
            if (Input.GetKeyDown(KeyCode.R) && _opFreezeCd <= 0f)
            {
                _opFreezeCd = 25f;
                ApplyOpFreeze(true);
            }
        }

        void SpawnPing(Vector3 pos, bool mine)
        {
            pos.y = 0;
            var ping = new GameObject("ping");
            ping.transform.SetParent(transform, false);
            ping.transform.position = pos;
            var col = new Color(0.3f, 0.95f, 1f);
            Build.Prim(PrimitiveType.Cylinder, ping.transform, new Vector3(0.5f, 7f, 0.5f),
                Mats.Holo(col, 0.65f), Vector3.up * 7f);
            Build.Prim(PrimitiveType.Sphere, ping.transform, Vector3.one * 1.1f,
                Mats.Neon(col, 2.6f), Vector3.up * 0.6f);
            Build.Omni(ping.transform, Vector3.up * 1.5f, col, 1.6f, 9f);
            Destroy(ping, 6f);
            Sfx.Play("ui", 0.25f);
            if (mine && _coop)
                Net.NetManager.Send(NetSync.MsgOpPing(_netScene, pos.x, pos.z));
            if (!mine) _hud?.Toast("ОПЕРАТОР: метка на поле — туда!");
        }

        void ApplyOpFreeze(bool mine)
        {
            _frozenUntil = Mathf.Max(_frozenUntil, Time.time + 4f);
            _flashCol = new Color(0.3f, 0.9f, 1f);
            _flashA = 0.25f;
            Sfx.Play("ability", 0.4f);
            _hud?.Toast(mine ? "СТОП-КАДР: система заморожена на 4с!"
                             : "ОПЕРАТОР дал СТОП-КАДР: система замерла (4с)!");
            if (mine && _coop)
                Net.NetManager.Send(NetSync.MsgOpFreeze(_netScene));
        }

        // глушение фона: работает, пока оператор сидит за терминалом
        void TickJam(float dt)
        {
            bool was = _jamming;
            _jamming = _opMode && !S.myBug && !Frozen;
            if (_jamming)
            {
                // компенсируем фоновый creep с запасом; АВ с анти-глушением
                // давит вдвое слабее. Злоупотребление копит обучение системы.
                float k = S.avCounter == "jam" ? 0.55f : 1.1f;
                _jamAccum -= S.raid.creep * (S.evacOpen ? 1.6f : 1f) * dt * k;
                _jamNoted += dt;
                if (_jamNoted >= 10f) { _jamNoted = 0f; S.AvNote("jam"); }
            }
            if (_jamming != was && _jamScreenMat != null)
                _jamScreenMat.SetColor("_EmissionColor", _jamCol * (_jamming ? 2.8f : 0.7f));
            _jamFlushT -= dt;
            if (_jamFlushT <= 0f)
            {
                _jamFlushT = 0.5f;
                if (_jamAccum < -0.001f) { AlarmEvent(_jamAccum); _jamAccum = 0f; }
            }
        }


        // ── АРХЕТИПЫ СЕРВЕРОВ: у каждого узла своё правило игры ──────────────
        void BuildArchetype()
        {
            switch (_arch)
            {
                case "bank":
                {
                    // две лазерные гребёнки ходят по залу поперёк — перепрыгиваемые
                    var beamCol = new Color(1f, 0.25f, 0.3f);
                    for (int i = 0; i < 2; i++)
                    {
                        var beam = Build.MeshBox(transform, new Vector3(0.16f, 1.05f, _hallD - 2f),
                            Mats.Neon(beamCol, 2.6f),
                            new Vector3(i == 0 ? -_hallW * 0.25f : _hallW * 0.25f, 0.55f, 0));
                        Build.Omni(beam.transform, Vector3.zero, beamCol, 1.2f, 6f);
                        _beams.Add(beam.transform);
                        _beamDir.Add(i == 0 ? 1f : -1f);
                    }
                    break;
                }
                case "game":
                {
                    // чит-гравитация + парящие платформы: лучшие файлы наверху
                    var files = new List<Loot>();
                    foreach (var l in _loot) if (l.weight == 1 && !l.fake) files.Add(l);
                    float hx = _hallW * 0.5f, hz = _hallD * 0.5f;
                    for (int i = 0; i < 4; i++)
                    {
                        var pos = new Vector3(R(-hx + 12, hx - 8), R(2.2f, 2.9f), R(-hz + 7, hz - 7));
                        if (pos.x < -12) pos.x = -pos.x;
                        Build.Solid(transform, new Vector3(5.2f, 0.5f, 4.2f),
                            Mats.Metal(new Color(0.35f, 0.5f, 0.6f), 0.5f), pos);
                        Build.MeshBox(transform, new Vector3(5.4f, 0.08f, 4.4f),
                            Mats.Neon(new Color(0.5f, 0.9f, 1f), 1.4f), pos + Vector3.up * 0.3f);
                        Loot best = null;
                        foreach (var l in files)
                            if (best == null || l.value > best.value) best = l;
                        if (best != null)
                        {
                            best.body.position = pos + Vector3.up * 1.2f;
                            files.Remove(best);
                        }
                    }
                    break;
                }
                case "scan":
                    // потолочная балка сканера через весь зал: греется перед проверкой
                    _scanMat = Mats.Neon(new Color(1f, 0.6f, 0.3f), 0.8f);
                    Build.MeshBox(transform, new Vector3(_hallW - 4f, 0.35f, 0.8f), _scanMat,
                        new Vector3(0, 6.4f, 0));
                    _scanT = 14f;
                    break;
                case "dark":
                    _darkT = 15f;
                    break;
                case "proxy":
                    _padSwitchT = 38f;
                    break;
            }
        }

        void TickArchetype(float dt)
        {
            switch (_arch)
            {
                case "bank": TickBeams(dt); break;
                case "dark": TickDark(dt); break;
                case "scan": TickScan(dt); break;
                case "proxy": TickProxy(dt); break;
            }
        }

        // платёжный шлюз: лучи ходят по залу, бьют стоящих на полу — прыгай
        void TickBeams(float dt)
        {
            _beamHitLock = Mathf.Max(_beamHitLock - dt, 0f);
            if (Frozen) return;   // «шифрование» замораживает и гребёнку
            float hx = _hallW * 0.5f - 2f;
            float speed = 4.6f + S.raid.tier * 0.5f;
            for (int i = 0; i < _beams.Count; i++)
            {
                var b = _beams[i];
                float x = b.position.x + _beamDir[i] * speed * dt;
                if (x > hx) { x = hx; _beamDir[i] = -1f; }
                else if (x < -hx) { x = -hx; _beamDir[i] = 1f; }
                b.position = new Vector3(x, b.position.y, 0);
                var pp = _player.transform.position;
                if (_beamHitLock <= 0f && !S.myBug && pp.y < 1.15f && Mathf.Abs(pp.x - x) < 0.5f)
                {
                    _beamHitLock = 1.2f;
                    HurtPlayer(new Vector3(x, 1f, pp.z), 1);
                    _hud?.Toast("ЛАЗЕРНАЯ ГРЕБЁНКА: перепрыгивай лучи!");
                }
            }
        }

        // умный дом: свет гаснет циклами — запоминай зал, пока светло
        void TickDark(float dt)
        {
            _darkT -= dt;
            switch (_darkPhase)
            {
                case 0:
                    if (_darkT <= 0f)
                    {
                        _darkPhase = 1; _darkT = 3f;
                        _hud?.Toast("УМНЫЙ ДОМ: свет гаснет через 3с — запомни, где лут!");
                        Sfx.Play("alarm", 0.25f);
                    }
                    break;
                case 1:
                    float fl = 0.35f + Mathf.PerlinNoise(Time.time * 9f, 0.5f) * 0.65f;
                    RenderSettings.ambientSkyColor = _ambSky0 * fl;
                    RenderSettings.ambientEquatorColor = _ambEq0 * fl;
                    RenderSettings.ambientGroundColor = _ambGnd0 * fl;
                    if (_darkT <= 0f)
                    {
                        _darkPhase = 2; _darkT = 8f;
                        RenderSettings.ambientSkyColor = _ambSky0 * 0.05f;
                        RenderSettings.ambientEquatorColor = _ambEq0 * 0.05f;
                        RenderSettings.ambientGroundColor = _ambGnd0 * 0.04f;
                        RenderSettings.fogDensity = 0.02f;
                    }
                    break;
                case 2:
                    if (_darkT <= 0f)
                    {
                        _darkPhase = 0; _darkT = 17f + (float)_rng.NextDouble() * 6f;
                        RenderSettings.ambientSkyColor = _ambSky0;
                        RenderSettings.ambientEquatorColor = _ambEq0;
                        RenderSettings.ambientGroundColor = _ambGnd0;
                        RenderSettings.fogDensity = _fogDensity0;
                        _hud?.Toast("Питание восстановлено");
                    }
                    break;
            }
        }

        // архивный массив: периодический скан целостности — замри или маскируйся
        void TickScan(float dt)
        {
            if (Frozen) return;   // заморозка системы останавливает и сканер
            _scanT -= dt;
            switch (_scanPhase)
            {
                case 0:
                    if (_scanT <= 0f)
                    {
                        _scanPhase = 1; _scanT = 3f; _scanBusted = false;
                        _hud?.Toast("ПРОВЕРКА ЦЕЛОСТНОСТИ через 3с: ЗАМРИ или маскируйся!");
                        Sfx.Play("alarm", 0.3f);
                        _scanMat?.SetColor("_EmissionColor", new Color(1f, 0.6f, 0.3f) * 3f);
                    }
                    break;
                case 1:
                    if (_scanT <= 0f)
                    {
                        _scanPhase = 2; _scanT = 2.6f;
                        _scanMat?.SetColor("_EmissionColor", new Color(1f, 0.2f, 0.15f) * 4f);
                    }
                    break;
                case 2:
                    if (!_scanBusted && !S.myBug && !PlayerHidden && _player.PlanarSpeed > 0.8f)
                    {
                        _scanBusted = true;
                        AlarmEvent(12f);
                        SpawnTrap();
                        _flashCol = new Color(1f, 0.3f, 0.2f);
                        _flashA = 0.35f;
                        Sfx.Play("trap", 0.4f);
                        _hud?.Toast("СКАН ЗАСЁК ДВИЖЕНИЕ: тревога +12!");
                    }
                    if (_scanT <= 0f)
                    {
                        _scanPhase = 0; _scanT = 16f + (float)_rng.NextDouble() * 8f;
                        _scanMat?.SetColor("_EmissionColor", new Color(1f, 0.6f, 0.3f) * 0.8f);
                        if (!_scanBusted) _hud?.Toast("Проверка пройдена — чисто");
                    }
                    break;
            }
        }

        // зеркальный прокси: зона выноса мигрирует запад↔восток.
        // В коопе миграцию решает директор, остальные получают её через RAS.
        void TickProxy(float dt)
        {
            if (_coop && !_director) return;
            _padSwitchT -= dt;
            if (_padSwitchT <= 5f && !_padWarned)
            {
                _padWarned = true;
                _hud?.Toast("ПРОКСИ: порт мигрирует через 5 секунд!");
                Sfx.Play("alarm", 0.25f);
            }
            if (_padSwitchT <= 0f)
            {
                _padSwitchT = 38f;
                _padWarned = false;
                SetPadIndex(_padIdx ^ 1);
            }
        }

        void SetPadIndex(int idx)
        {
            if (idx == _padIdx || _portalRoot == null) return;
            _padIdx = idx;
            var target = idx == 0 ? new Vector3(-27, 0, 0) : new Vector3(27, 0, 0);
            _portalRoot.position += target - _padPos;
            _padPos = target;
            Sfx.Play("hook", 0.4f);
            _hud?.Toast("ПОРТ ПЕРЕЕХАЛ: новая зона выноса " + (idx == 0 ? "на западе" : "на востоке"));
        }

        static void SetLayerDeep(Transform t, int layer)
        {
            t.gameObject.layer = layer;
            foreach (Transform c in t) SetLayerDeep(c, layer);
        }

        void ToggleCarry(Loot loot)
        {
            if (S.myBug) return;
            if (_mimic != null) { _hud?.Toast("Сначала стряхни мимика [F]!"); return; }
            if (_carried == loot) { DropLoot(); return; }
            if (_carried != null) return;
            if (loot.carrier != 0 && loot.carrier != Net.NetManager.MyId) return;   // несёт напарник
            if (loot.mimic) { TriggerMimic(loot); return; }   // приманка кусается
            // сейф в коопе поднимается только вдвоём (в соло — просто очень медленно)
            if (loot.weight >= 3 && Net.NetManager.Active && !HelperNear())
            {
                _hud?.Toast("СЕЙФ: поднимать только вдвоём — напарник должен стоять рядом");
                return;
            }
            _carried = loot;
            loot.carried = true;
            loot.carrier = Net.NetManager.MyId;
            loot.hasNet = false;
            loot.rb.isKinematic = true;
            // груз парит на пути спринг-арма камеры: IgnoreRaycast, иначе камера
            // «прилипает» к грузу при повороте
            SetLayerDeep(loot.body, 2);
            _player.carrying = true;
            _player.carryFactor = CarryFactorFor(loot, HelperNear());
            _player.SetMorph(false);
            if (_coop)
                Net.NetManager.Send(NetSync.MsgLootCarry(_netScene, _loot.IndexOf(loot), Net.NetManager.MyId));
        }

        void DropLoot()
        {
            if (_carried == null) return;
            var l = _carried;
            l.carried = false;
            l.carrier = 0;
            l.rb.isKinematic = false;
            SetLayerDeep(l.body, 0);   // снова видим для камеры/рейкастов
            _carried = null;
            _helperActive = false;
            if (_player != null)
            {
                _player.carrying = false;
                _player.carryFactor = 1f;
            }
            if (_coop)
                Net.NetManager.Send(NetSync.MsgLootCarry(_netScene, _loot.IndexOf(l), 0));
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
                // круглая голова-сенсор вместо куба + скруглённый бампер
                Build.Prim(PrimitiveType.Sphere, root, Vector3.one * 0.66f, body, new Vector3(0, 2.5f, 0));
                Build.Prim(PrimitiveType.Sphere, root, Vector3.one * 0.28f,
                    Mats.Neon(new Color(1f, 0.2f, 0.2f), 4f), new Vector3(0, 2.52f, 0.28f));
                var bumper = Build.Prim(PrimitiveType.Capsule, root, new Vector3(0.3f, 0.95f, 0.3f),
                    Mats.MetalDark(0.5f), new Vector3(0, 0.55f, 1.28f));
                bumper.transform.localRotation = Quaternion.Euler(0, 0, 90);
                // дуло крюка — круглый ствол
                var muzzle = Build.Prim(PrimitiveType.Cylinder, root, new Vector3(0.18f, 0.32f, 0.18f),
                    Mats.Metal(new Color(0.35f, 0.38f, 0.42f), 0.6f), new Vector3(0, 1.9f, 0.75f));
                muzzle.transform.localRotation = Quaternion.Euler(90, 0, 0);
                Build.Omni(root, new Vector3(0, 2.6f, 0), new Color(1f, 0.25f, 0.2f), 1.4f, 9f);
                // корпус робота осязаем: игрока не пропускает
                Build.Collide(root, new Vector3(1.95f, 2.6f, 2.55f), new Vector3(0, 1.35f, 0));
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
            // в карантине лаборатории системе доверия меньше: скидка вдвое слабее
            float bonus = _arch == "avlab" ? -4f : -8f;
            AlarmEvent(bonus);
            S.CareerEvent("tasks");
            Sfx.Play("win", 0.3f);
            _hud?.Toast($"{msg} · тревога {(int)bonus}, карьера +1 задача");
        }

        void SpawnConsoleTask()
        {
            var root = new GameObject("task_console").transform;
            root.SetParent(transform, false);
            root.localPosition = TaskSpot(7f);
            Build.Solid(root, new Vector3(1.1f, 1.3f, 0.7f), Mats.Plastic(new Color(0.14f, 0.2f, 0.26f)), new Vector3(0, 0.65f, 0));
            var led = Build.MeshBox(root, new Vector3(0.8f, 0.5f, 0.06f), Mats.Neon(new Color(1f, 0.7f, 0.35f), 1.6f), new Vector3(0, 0.9f, -0.39f));
            bool used = false;
            var it = root.gameObject.AddComponent<Interactable>();
            it.radius = 3f;
            it.enabledFn = () => !used && !S.myBug;
            // T1+ половина консолей требует мини-взлом из пула головоломок —
            // рискованно (ловушки летят, пока ковыряешься), зато интереснее
            bool puzzled = S.raid.tier >= 1 && _rng.NextDouble() < 0.5;
            void Done()
            {
                used = true;
                led.GetComponent<MeshRenderer>().sharedMaterial = Mats.Neon(new Color(0.4f, 0.42f, 0.45f), 0.4f);
                TaskDone("Консоль откалибрована");
            }
            if (puzzled)
            {
                it.prompt = "[E] СЕРВИСНАЯ КОНСОЛЬ: мини-взлом (тревога −8, система не ждёт!)";
                it.onInteract = () =>
                {
                    if (used) return;
                    UI.PuzzleUI.Open(Mathf.Min(S.raid.tier + 1, 4), "ВЗЛОМ СЕРВИСНОЙ КОНСОЛИ", Done);
                };
            }
            else
            {
                it.holdSeconds = 3f;
                it.prompt = "[E·держать] СЕРВИСНАЯ КОНСОЛЬ: откалибровать (тревога −8)";
                it.onInteract = Done;
            }
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
                    : "[E] ДВОЙНОЙ РУБИЛЬНИК: дёрнуть (второй — за 6с)";
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
                var it = root.gameObject.AddComponent<Interactable>();
                it.radius = 2.8f;
                it.dynamicPrompt = () => idx == next && next > 0 && deadline > Time.time
                    ? $"[E] тяни кабель! ({Mathf.Max(deadline - Time.time, 0f):0.0}с)"
                    : $"[E] ПРОТЯЖКА КАБЕЛЯ: опора {idx + 1}/3 (по порядку)";
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

        void OnDestroy()
        {
            if (Current == this) Current = null;
        }

        void Update()
        {
            // с экрана результатов можно выйти и клавишей — не только мышью
            if (_done && (Input.GetKeyDown(KeyCode.Return) || Input.GetKeyDown(KeyCode.Space) || Input.GetKeyDown(KeyCode.E)))
            {
                Debug.Log("[UI] results->grid key");
                App.SceneFlow.GoGrid();
                return;
            }
            if (_done || _player == null) return;
            float dt = Time.deltaTime;
            _hitLock = Mathf.Max(_hitLock - dt, 0f);
            _abilityCd = Mathf.Max(_abilityCd - dt, 0f);

            TickCoop(dt);
            // тревога ползёт сама (у не-директора её ведёт директор через RAS)
            if (_director) S.ApplyAlarm(S.raid.creep * (S.evacOpen ? 1.6f : 1f) * dt);
            // пик тревоги для контракта «ПРИЗРАК» (ловит и синк от директора)
            if (S.alarm > S.lastMaxAlarm) S.lastMaxAlarm = S.alarm;
            TickPhaseFx();
            if (!Frozen)
            {
                TickTraps(dt);
                if (_director)
                {
                    TickGuards(dt);
                    TickHooks(dt);
                }
            }
            if (!_director)
            {
                TickGuardReplicas(dt);
                TickHookReplicas(dt);
            }
            TickHooked(dt);
            TickAbilities();
            TickThrow();
            TickJam(dt);
            TickOperator(dt);
            TickArchetype(dt);
            TickHeat(dt);
            TickAdaptive(dt);
            TickCarryAndDeposit();
            TickPadIntake();
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
            if (UI.PuzzleUI.IsOpen || UI.EvolutionUI.IsOpen || UI.PauseMenu.IsOpen) return;
            var l = _carried;
            DropLoot();
            if (l.hot) l.heat = Mathf.Max(l.heat - 25f, 0f);   // эстафета студит пакет
            var v = _player.LookDir() * 10f + Vector3.up * 4.5f;
            l.rb.linearVelocity = v;
            if (_coop)
            {
                var p = l.body.position;
                Net.NetManager.Send(NetSync.MsgLootThrow(_netScene, _loot.IndexOf(l),
                    p.x, p.y, p.z, v.x, v.y, v.z));
            }
            Sfx.Play("ui", 0.3f);
        }

        // лут рядом слегка «дышит» размером — легче заметить в темноте.
        // Спам-пустышки выдаёт рваное глитч-дрожание — внимательный заметит.
        void TickLootPulse()
        {
            var pp = _player.transform.position;
            for (int i = 0; i < _loot.Count; i++)
            {
                var l = _loot[i];
                if (l.deposited || l.body == null || l.carried) continue;
                bool near = Vector3.Distance(pp, l.body.position) < 5f;
                float k = near ? 1f + 0.05f * Mathf.Sin(Time.time * 6f) : 1f;
                if (l.fake && Mathf.PerlinNoise(Time.time * 2.6f, i * 7.13f) > 0.72f)
                    k *= 1.14f;   // глитч спама: редкие рывки размера
                l.body.localScale = Vector3.one * k;
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
            if (_ambience != null) _ambience.volume = 0.22f + ph * 0.07f;   // тревога густит гул
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
            // в темноте умного дома система «слепнет» — новые ловушки не летят
            if (S.AlarmPhase() >= 1 && !S.myBug && !PlayerHidden && _darkPhase != 2)
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
            {
                // энергетическая сфера с гало — не куб
                body = Build.Prim(PrimitiveType.Sphere, transform, Vector3.one * 0.4f, Mats.Neon(info.color, 3.5f), Vector3.zero);
                body.transform.position = origin;
                Build.Prim(PrimitiveType.Sphere, body.transform, Vector3.one * 1.55f, Mats.Neon(info.color, 0.5f), Vector3.zero);
            }
            Build.Omni(body.transform, Vector3.zero, info.color, 1.2f, 4f);
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

        // цель робота среди всей стаи: на охоте — сильнейший штамм, иначе ближайший
        bool GuardTarget(Guard g, bool hunt, out Vector3 pos, out bool isSelf)
        {
            pos = default; isSelf = false;
            bool found = false;
            float best = float.MinValue;
            if (!S.myBug && !PlayerHidden)
            {
                var pp = _player.transform.position;
                best = (hunt ? S.EvolveStage() * 1000f : 0f) - Vector3.Distance(g.t.position, pp);
                pos = pp; isSelf = true; found = true;
            }
            foreach (var pr in _peers)
            {
                float key = (hunt ? pr.stage * 1000f : 0f) - Vector3.Distance(g.t.position, pr.pos);
                if (!found || key > best) { best = key; pos = pr.pos; isSelf = false; found = true; }
            }
            return found;
        }

        // ── роботы: угол → крюки (50%) → погоня (100%) ──
        void TickGuards(float dt)
        {
            bool hunt = S.AlarmPhase() >= 3;
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

                bool seen = GuardTarget(g, hunt, out var tp, out bool isSelf);
                float dist = seen ? Vector3.Distance(g.t.position, tp) : 999f;

                if (hunt && seen)
                {
                    var dir = tp - g.t.position; dir.y = 0;
                    if (dir.magnitude > 1.6f)
                    {
                        g.t.position += dir.normalized * (_chaseSpeed * dt);
                        g.t.rotation = Quaternion.Slerp(g.t.rotation, Quaternion.LookRotation(dir), 8f * dt);
                    }
                    // melee по себе; урон напарникам засчитывают их клиенты
                    else if (isSelf && g.meleeCd <= 0f) { g.meleeCd = 1.4f; HurtPlayer(g.t.position, 1); }
                }
                else
                {
                    var back = g.home - g.t.position; back.y = 0;
                    if (back.magnitude > 1f) g.t.position += back.normalized * (3.5f * dt);
                    else if (seen && dist < S.raid.camRange * 1.4f)
                    {
                        var face = tp - g.t.position; face.y = 0;
                        if (face.sqrMagnitude > 0.1f)
                            g.t.rotation = Quaternion.Slerp(g.t.rotation, Quaternion.LookRotation(face), 4f * dt);
                    }
                    else
                        g.t.Rotate(0f, 22f * dt, 0f);   // дежурное сканирование зала
                }

                // крюк: с 50% тревоги по цели в радиусе обзора (на 100% — дальнобойный)
                float sight = hunt ? HookRange : S.raid.camRange * 1.4f;
                if (S.alarm >= _hookAlarmGate && seen && g.hookCd <= 0f && dist > 3f && dist < sight)
                {
                    g.hookCd = ((float)_rng.NextDouble() * 4f + 5f) * _hookCdScale;
                    g.hookOut = true;
                    var origin = g.t.position + Vector3.up * 1.9f;
                    var hdir = (tp + Vector3.up * 1f - origin).normalized;
                    var body = Build.MeshBox(transform, new Vector3(0.3f, 0.3f, 0.6f), Mats.Neon(new Color(1f, 0.5f, 0.2f), 3f), origin);
                    Build.Omni(body.transform, Vector3.zero, new Color(1f, 0.5f, 0.2f), 1f, 4f);
                    body.transform.rotation = Quaternion.LookRotation(hdir);
                    _hooks.Add(new Hook { t = body.transform, owner = g, dir = hdir });
                    Sfx.Play("hook", 0.45f);
                    _hud?.Toast("⚠ РОБОТ ВЫПУСТИЛ КРЮК — уворачивайся!");
                }
            }
        }

        // директор сообщает репликам, что крюк смотан
        void NetHookEnd(Guard owner)
        {
            if (!_coop || !_director) return;
            int gi = _guards.IndexOf(owner);
            if (gi >= 0) Net.NetManager.Send(NetSync.MsgHookEnd(_netScene, gi));
        }

        void TickHooks(float dt)
        {
            for (int i = _hooks.Count - 1; i >= 0; i--)
            {
                var h = _hooks[i];
                if (h.t == null) { h.owner.hookOut = false; NetHookEnd(h.owner); _hooks.RemoveAt(i); continue; }
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
                        NetHookEnd(h.owner);
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
                    if (_opMode) ExitOperator();   // крюк выдёргивает оператора
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

        // ── кооп: выборы директора, рассылка состояния, реплики ──
        void TickCoop(float dt)
        {
            if (Net.NetManager.Active) Net.NetManager.PeersIn(_netScene, _peers);
            else _peers.Clear();

            _coopTimer -= dt;
            if (_coopTimer <= 0f)
            {
                _coopTimer = 0.5f;
                _coop = Net.NetManager.Active && _peers.Count > 0;
                bool was = _director;
                _director = true;
                foreach (var pr in _peers)
                    if (pr.id < Net.NetManager.MyId) { _director = false; break; }
                if (_director && !was) OnBecameDirector();

                // носильщик пропал (дисконнект/ушёл из узла) — освобождаем груз
                foreach (var l in _loot)
                {
                    if (l.carrier == 0 || l.carrier == Net.NetManager.MyId || l.deposited) continue;
                    bool present = false;
                    foreach (var pr in _peers) if (pr.id == l.carrier) { present = true; break; }
                    if (!present)
                    {
                        l.carrier = 0; l.carried = false; l.hasNet = false;
                        if (l.rb != null) l.rb.isKinematic = false;
                    }
                }
            }
            if (!_coop) return;

            if (_director)
            {
                _netPosTimer -= dt;
                if (_netPosTimer <= 0f)
                {
                    _netPosTimer = 0.12f;
                    for (int i = 0; i < _guards.Count; i++)
                    {
                        var g = _guards[i];
                        Net.NetManager.Send(NetSync.MsgGuardPos(_netScene, i,
                            g.t.position.x, g.t.position.z, g.t.eulerAngles.y));
                    }
                    foreach (var h in _hooks)
                    {
                        if (h.t == null) continue;
                        int gi = _guards.IndexOf(h.owner);
                        if (gi >= 0)
                            Net.NetManager.Send(NetSync.MsgHookPos(_netScene, gi,
                                h.t.position.x, h.t.position.y, h.t.position.z));
                    }
                }
                _netStateTimer -= dt;
                if (_netStateTimer <= 0f)
                {
                    _netStateTimer = 0.5f;
                    Net.NetManager.Send(NetSync.MsgRaidState(_netScene, S.alarm, S.evacOpen,
                        S.evacLeft, S.wipeForced, DepositedMask(), S.access, _padIdx));
                }
            }

            // моя ноша: позиция груза для остальных (8 Гц)
            if (_carried != null)
            {
                _lootPosTimer -= dt;
                if (_lootPosTimer <= 0f)
                {
                    _lootPosTimer = 0.12f;
                    int idx = _loot.IndexOf(_carried);
                    var p = _carried.body.position;
                    Net.NetManager.Send(NetSync.MsgLootPos(_netScene, idx, p.x, p.y, p.z));
                }
            }

            // лут в руках напарников следует их позициям
            foreach (var l in _loot)
                if (l.carrier != 0 && l.carrier != Net.NetManager.MyId && l.hasNet
                    && l.body != null && !l.deposited)
                    l.body.position = Vector3.Lerp(l.body.position, l.netPos, Mathf.Min(12f * dt, 1f));
        }

        // директор ушёл — реплики становятся моей симуляцией
        void OnBecameDirector()
        {
            foreach (var kv in _hookReplicas)
                if (kv.Value.t != null) Destroy(kv.Value.t.gameObject);
            _hookReplicas.Clear();
            foreach (var g in _guards) { g.hasNet = false; g.hookOut = false; }
        }

        int DepositedMask()
        {
            int m = 0;
            for (int i = 0; i < _loot.Count && i < 31; i++)
                if (_loot[i].deposited) m |= 1 << i;
            return m;
        }

        // событийная тревога: не-директор дублирует поправку директору
        void AlarmEvent(float delta)
        {
            S.ApplyAlarm(delta);
            if (_coop && !_director)
                Net.NetManager.Send(NetSync.MsgAlarmDelta(_netScene, delta));
        }

        /// Входящие рейд-сообщения (маршрутизирует NetManager по токену сцены).
        public void HandleNet(string[] p)
        {
            if (_done || _player == null || p.Length < 3) return;
            switch (p[0])
            {
                case "RAS":
                    ApplyRaidState(p);
                    break;
                case "RALD":
                    if (_director && NetSync.ParseF(p[2], out var d)) S.ApplyAlarm(d);
                    break;
                case "RGP":
                    if (!_director && p.Length >= 6 && int.TryParse(p[2], out var gi)
                        && gi >= 0 && gi < _guards.Count
                        && NetSync.ParseF(p[3], out var gx) && NetSync.ParseF(p[4], out var gz)
                        && NetSync.ParseF(p[5], out var gry))
                    {
                        var g = _guards[gi];
                        g.netPos = new Vector3(gx, 0f, gz);
                        g.netRy = gry;
                        g.hasNet = true;
                    }
                    break;
                case "RSTN":
                    if (_director && int.TryParse(p[2], out var si) && si >= 0 && si < _guards.Count)
                        _guards[si].stunUntil = Time.time + 4f;
                    break;
                case "RHP":
                    if (!_director && p.Length >= 6 && int.TryParse(p[2], out var hi)
                        && hi >= 0 && hi < _guards.Count
                        && NetSync.ParseF(p[3], out var hx2) && NetSync.ParseF(p[4], out var hy2)
                        && NetSync.ParseF(p[5], out var hz2))
                    {
                        var pos = new Vector3(hx2, hy2, hz2);
                        if (!_hookReplicas.TryGetValue(hi, out var hr))
                        {
                            var hookCol = new Color(1f, 0.5f, 0.2f);
                            var body = Build.MeshBox(transform, new Vector3(0.3f, 0.3f, 0.6f), Mats.Neon(hookCol, 3f), pos);
                            Build.Omni(body.transform, Vector3.zero, hookCol, 1f, 4f);
                            hr = new Hook { t = body.transform, owner = _guards[hi] };
                            _hookReplicas[hi] = hr;
                            Sfx.Play("hook", 0.4f);
                        }
                        hr.netPos = pos;
                    }
                    break;
                case "RHE":
                    if (int.TryParse(p[2], out var he) && _hookReplicas.TryGetValue(he, out var her))
                    {
                        if (her.t != null) Destroy(her.t.gameObject);
                        _hookReplicas.Remove(he);
                    }
                    break;
                case "RHC":   // напарника зацепило моим крюком — сматываем
                    if (_director && int.TryParse(p[2], out var hc) && hc >= 0 && hc < _guards.Count)
                        foreach (var h in _hooks)
                            if (h.owner == _guards[hc]) { h.caught = true; h.ret = true; }
                    break;
                case "RLC":
                    if (p.Length >= 4 && int.TryParse(p[2], out var ci) && ci >= 0 && ci < _loot.Count
                        && int.TryParse(p[3], out var pid))
                        ApplyLootCarry(_loot[ci], pid);
                    break;
                case "RLP":
                    if (p.Length >= 6 && int.TryParse(p[2], out var li) && li >= 0 && li < _loot.Count
                        && NetSync.ParseF(p[3], out var lx) && NetSync.ParseF(p[4], out var ly)
                        && NetSync.ParseF(p[5], out var lz))
                    {
                        var l = _loot[li];
                        if (_carried != l && !l.deposited)
                        {
                            l.netPos = new Vector3(lx, ly, lz);
                            l.hasNet = true;
                            if (l.carrier == 0) { l.carried = true; if (l.rb != null) l.rb.isKinematic = true; }
                        }
                    }
                    break;
                case "RLT":
                    if (p.Length >= 9 && int.TryParse(p[2], out var ti) && ti >= 0 && ti < _loot.Count
                        && NetSync.ParseF(p[3], out var tx) && NetSync.ParseF(p[4], out var ty)
                        && NetSync.ParseF(p[5], out var tz) && NetSync.ParseF(p[6], out var tvx)
                        && NetSync.ParseF(p[7], out var tvy) && NetSync.ParseF(p[8], out var tvz))
                    {
                        var l = _loot[ti];
                        l.carrier = 0; l.carried = false; l.hasNet = false;
                        if (l.body != null && l.rb != null && !l.deposited)
                        {
                            l.rb.isKinematic = false;
                            l.body.position = new Vector3(tx, ty, tz);
                            l.rb.linearVelocity = new Vector3(tvx, tvy, tvz);
                        }
                    }
                    break;
                case "RLD":
                    if (p.Length >= 4 && int.TryParse(p[2], out var di) && di >= 0 && di < _loot.Count)
                    {
                        MarkDepositedRemote(_loot[di]);
                        if (NetSync.ParseF(p[3], out var acc)) S.access = Mathf.Max(S.access, acc);
                        Sfx.Play("deposit", 0.3f);
                        _hud?.Toast($"Напарник внёс лут! Добыча {(int)S.access}%");
                        if (!S.evacOpen && S.access >= 100f) OpenEvac(false);
                    }
                    break;
                case "RLG":   // лут пропал: спам сгорел в фильтре / хрупкий разбился
                    if (int.TryParse(p[2], out var gi2) && gi2 >= 0 && gi2 < _loot.Count)
                    {
                        MarkDepositedRemote(_loot[gi2]);
                        Sfx.Play("trap", 0.2f);
                    }
                    break;
                case "ROP":   // пинг оператора: столб света для всей стаи
                    if (p.Length >= 4 && NetSync.ParseF(p[2], out var px)
                        && NetSync.ParseF(p[3], out var pz))
                        SpawnPing(new Vector3(px, 0, pz), false);
                    break;
                case "ROF":   // стоп-кадр оператора: система замерла у всех
                    ApplyOpFreeze(false);
                    break;
            }
        }

        void ApplyRaidState(string[] p)
        {
            if (_director || p.Length < 8) return;
            if (NetSync.ParseF(p[2], out var alarm)) S.alarm = alarm;
            bool evac = p[3] == "1";
            NetSync.ParseF(p[4], out var evacLeft);
            bool wipe = p[5] == "1";
            if (evac && !S.evacOpen)
            {
                S.evacOpen = true;
                S.wipeForced = wipe;
                S.evacLeft = evacLeft;
                _hud?.Toast(wipe ? $"СТИРАНИЕ УЗЛА: {(int)evacLeft}с — В КРУГ!"
                                 : $"КВОТА ВЗЯТА! Эвакуация {(int)evacLeft}с — в круг у портала!");
                _hud?.SetObjective("ЭВАКУАЦИЯ: встань в круг у портала!");
            }
            else if (evac) S.evacLeft = evacLeft;
            if (int.TryParse(p[6], out var mask))
                for (int i = 0; i < _loot.Count && i < 31; i++)
                    if ((mask & (1 << i)) != 0) MarkDepositedRemote(_loot[i]);
            if (NetSync.ParseF(p[7], out var acc)) S.access = Mathf.Max(S.access, acc);
            // прокси: не-директор двигает зону выноса вслед за директором
            if (p.Length >= 9 && int.TryParse(p[8], out var padIdx)) SetPadIndex(padIdx);
        }

        void ApplyLootCarry(Loot l, int pid)
        {
            if (l.deposited) return;
            if (pid == 0)
            {
                if (_carried == l) return;   // мой захват новее — не отпускаем
                l.carrier = 0; l.carried = false; l.hasNet = false;
                if (l.rb != null) l.rb.isKinematic = false;
                return;
            }
            if (pid == Net.NetManager.MyId) return;
            // гонка захвата: уступает тот, у кого id больше
            if (_carried == l)
            {
                if (pid > Net.NetManager.MyId) return;
                DropLoot();
                _hud?.Toast("Напарник перехватил груз");
            }
            l.carrier = pid;
            l.carried = true;
            if (l.rb != null) l.rb.isKinematic = true;
        }

        void MarkDepositedRemote(Loot l)
        {
            if (l.deposited) return;
            if (_carried == l) DropLoot();
            l.deposited = true;
            l.carrier = 0;
            if (l.body != null) Destroy(l.body.gameObject);
        }

        // реплики роботов: позиции ведёт директор, урон по себе считаем сами
        void TickGuardReplicas(float dt)
        {
            bool hunt = S.AlarmPhase() >= 3;
            bool seen = !S.myBug && !PlayerHidden;
            foreach (var g in _guards)
            {
                g.meleeCd = Mathf.Max(g.meleeCd - dt, 0f);
                float moved = (g.t.position - g.lastPos).magnitude;
                g.lastPos = g.t.position;
                foreach (var w in g.wheels) w.Rotate(0f, moved / 0.36f * Mathf.Rad2Deg, 0f, Space.Self);
                if (g.radar != null) g.radar.Rotate(0f, 140f * dt, 0f, Space.Self);
                if (g.hasNet)
                {
                    g.t.position = Vector3.Lerp(g.t.position, g.netPos, Mathf.Min(10f * dt, 1f));
                    g.t.rotation = Quaternion.Slerp(g.t.rotation, Quaternion.Euler(0, g.netRy, 0), 10f * dt);
                }
                if (hunt && seen && g.meleeCd <= 0f
                    && Vector3.Distance(g.t.position, _player.transform.position) < 1.9f)
                {
                    g.meleeCd = 1.4f;
                    HurtPlayer(g.t.position, 1);
                }
            }
        }

        // реплики крюков: летят к последней известной точке, зацеп считаем сами
        void TickHookReplicas(float dt)
        {
            foreach (var kv in _hookReplicas)
            {
                var h = kv.Value;
                if (h.t == null) continue;
                h.t.position = Vector3.MoveTowards(h.t.position, h.netPos, HookSpeed * 1.6f * dt);
                if (!h.caught && !S.myBug && !PlayerHidden &&
                    Vector3.Distance(h.t.position, _player.transform.position + Vector3.up * 1f) < 1.4f)
                {
                    h.caught = true;
                    Net.NetManager.Send(NetSync.MsgHookCaught(_netScene, kv.Key));
                    DropLoot();
                    if (_opMode) ExitOperator();   // крюк выдёргивает оператора
                    _hookedUntil = Time.time + 1.6f;
                    _hookedBy = h.owner;
                    _player.Shake(0.6f);
                    _hud?.Toast("🪝 КРЮК ЗАЦЕПИЛ — тебя тянет к роботу!");
                }
            }
        }

        // ── активки [Q]/[X]/[C] за Bandwidth ──
        void TickAbilities()
        {
            if (UI.PuzzleUI.IsOpen || UI.EvolutionUI.IsOpen || UI.PauseMenu.IsOpen) return;
            if (_opMode) return;   // за терминалом клавиши — операторские
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
                    _morphAt = now;
                    S.AvNote("morph");
                    _hud?.Toast(S.avCounter == "morph"
                        ? "ЛОЖНЫЙ ФАЙЛ: эвристика АВ вскроет тебя через 4с!"
                        : "ЛОЖНЫЙ ФАЙЛ: замри — роботы тебя не видят. Движение снимает морф");
                    break;
                case "dash":
                    _player.Dash();
                    _hud?.Toast("РЫВОК!");
                    break;
                case "freeze":
                    S.AvNote("freeze");
                    _frozenUntil = now + (S.avCounter == "freeze" ? 1.8f : 3f);
                    _hud?.Toast(S.avCounter == "freeze"
                        ? "ШИФРОВАНИЕ: горячий резерв АВ — заморозка лишь 1.8с"
                        : "ШИФРОВАНИЕ: система и ловушки заморожены (3с)");
                    break;
                case "xray":
                    StartCoroutine(XRay(6f));
                    _hud?.Toast("СКАН: лут и угрозы подсвечены (6с)");
                    break;
                case "decoy":
                    S.AvNote("decoy");
                    _decoyUntil = now + (S.avCounter == "decoy" ? 2f : 5f);
                    _decoyPos = _player.transform.position + _player.LookDir() * 4f + Vector3.up * 1.2f;
                    SpawnDecoyGhost(_decoyPos);
                    _hud?.Toast(S.avCounter == "decoy"
                        ? "ФАНТОМ: АВ трассирует приманку — лишь 2с"
                        : "ФАНТОМ: ловушки ведутся (5с)");
                    break;
                case "jam":
                    AlarmEvent(-12f);
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
                    if (nearest != null)
                    {
                        nearest.stunUntil = now + 4f;
                        // симуляцию ведёт директор — сообщаем ему про стан
                        if (_coop && !_director)
                            Net.NetManager.Send(NetSync.MsgGuardStun(_netScene, _guards.IndexOf(nearest)));
                    }
                    _hud?.Toast("ЭМИ-РАЗРЯД: ближайший робот оглушён (4с)");
                    break;
                case "cloak":
                    _cloakUntil = now + 4f;
                    _hud?.Toast("СТЕЛС-ПАКЕТ: роботы тебя не видят (4с)");
                    break;
                case "purge":
                    foreach (var o in _traps) if (o.t != null) Destroy(o.t.gameObject);
                    _traps.Clear();
                    foreach (var h in _hooks) { if (h.t != null) Destroy(h.t.gameObject); h.owner.hookOut = false; NetHookEnd(h.owner); }
                    _hooks.Clear();
                    // не-директор: просим директора смотать крюки, реплики гасим
                    foreach (var kv in _hookReplicas)
                    {
                        if (kv.Value.t != null) Destroy(kv.Value.t.gameObject);
                        if (_coop && !_director) Net.NetManager.Send(NetSync.MsgHookCaught(_netScene, kv.Key));
                    }
                    _hookReplicas.Clear();
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
            if (_opMode) ExitOperator();   // оператора выбило из терминала
            _hitLock = 1.2f;
            S.lastHits++;                  // контракт «ЧИСТЫЕ РУКИ» сорван
            S.myHp = Mathf.Max(S.myHp - dmg, 0);
            // rootkit бесшумный: система слышит удар вдвое тише
            AlarmEvent(S.HasPassive("rootkit") ? 1f : 2f);
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

        // спам-пустышка попала в портал: система заметила мусор
        void SpamBusted(Loot l, int idx)
        {
            AlarmEvent(6f);
            Sfx.Play("trap", 0.35f);
            _flashCol = new Color(1f, 0.75f, 0.2f);
            _flashA = 0.3f;
            _hud?.Toast("СПАМ-ПУСТЫШКА! Фильтр заметил мусор: тревога +6");
            if (l.body != null) Destroy(l.body.gameObject);
            if (_coop && idx >= 0)
                Net.NetManager.Send(NetSync.MsgLootGone(_netScene, idx));
        }

        // ── горячие пакеты: греются в руках, стынут на полу; бросок [F]
        // сбрасывает четверть шкалы — конвейер из рук в руки быстрее ходок ──
        float _hotBeepT;

        void TickHeat(float dt)
        {
            foreach (var l in _loot)
            {
                if (!l.hot || l.deposited || l.body == null) continue;
                if (_carried == l)
                {
                    l.heat += dt * 13f;
                    if (l.heat >= 60f && !l.hotWarned)
                    {
                        l.hotWarned = true;
                        _hud?.Toast("ПАКЕТ РАСКАЛЯЕТСЯ: перекинь [F] напарнику или положи остыть!");
                    }
                    if (l.heat < 40f) l.hotWarned = false;
                    // писк учащается с нагревом
                    _hotBeepT -= dt;
                    if (_hotBeepT <= 0f)
                    {
                        _hotBeepT = Mathf.Lerp(1.1f, 0.22f, Mathf.Clamp01(l.heat / 100f));
                        Sfx.Play("ui", 0.16f);
                    }
                    if (l.heat >= 100f) Overheat(l);
                }
                else if (l.carrier == 0)
                    l.heat = Mathf.Max(l.heat - dt * 22f, 0f);
                if (l.mat != null)
                {
                    float k = Mathf.Clamp01(l.heat / 100f);
                    var c = new Color(1f, 0.5f - 0.42f * k, 0.15f - 0.1f * k);
                    l.mat.SetColor("_EmissionColor", c * (1.4f + k * 2.4f));
                }
            }
        }

        // ── мимик: файл оказался живым — вцепился, сосёт BW, тормозит ──
        void TriggerMimic(Loot l)
        {
            l.deposited = true;   // «файл» выбыл из лута навсегда
            int idx = _loot.IndexOf(l);
            if (l.body != null) Destroy(l.body.gameObject);
            if (_coop && idx >= 0)
                Net.NetManager.Send(NetSync.MsgLootGone(_netScene, idx));
            AlarmEvent(4f);
            Sfx.Play("trap", 0.4f);
            _player.Shake(0.55f);
            _player.SetMorph(false);
            _flashCol = new Color(1f, 0.45f, 0.2f);
            _flashA = 0.35f;
            _mimicSince = Time.time;
            _mimic = Player.VirusModel.BuildBug(_player.transform, new Color(1f, 0.4f, 0.2f));
            _mimic.transform.localPosition = new Vector3(0, 2.05f, 0);
            _mimic.transform.localScale = Vector3.one * 0.7f;
            _hud?.Toast("ЭТО МИМИК! Вцепился и сосёт BW — стряхни его [F]!");
        }

        // адаптивный АВ (вскрытие морфа) и жизнь мимика на загривке
        void TickAdaptive(float dt)
        {
            if (S.avCounter == "morph" && _player.Morphed && Time.time - _morphAt > 4f)
            {
                _player.SetMorph(false);
                AlarmEvent(3f);
                _hud?.Toast("ЭВРИСТИКА АВ вскрыла ложный файл: тревога +3");
            }
            if (_mimic != null)
            {
                S.bandwidth = Mathf.Max(S.bandwidth - 3f * dt, 0f);
                _player.slowUntil = Time.time + 0.3f;
                if (Input.GetKeyDown(KeyCode.F) && _carried == null && Time.time - _mimicSince > 1.2f
                    && !UI.PuzzleUI.IsOpen && !UI.EvolutionUI.IsOpen && !UI.PauseMenu.IsOpen)
                {
                    Destroy(_mimic);
                    _mimic = null;
                    _statMimics++;
                    AlarmEvent(2f);
                    Sfx.Play("ability", 0.3f);
                    _hud?.Toast("Мимик стряхнут и раздавлен. Фу.");
                }
            }
        }

        void Overheat(Loot l)
        {
            l.heat = 55f;          // остаётся горячим — не поднять и бежать дальше
            l.hotWarned = false;
            _statOverheats++;
            l.value *= 0.85f;
            AlarmEvent(7f);
            DropLoot();
            _flashCol = new Color(1f, 0.4f, 0.1f);
            _flashA = 0.35f;
            Sfx.Play("trap", 0.4f);
            _hud?.Toast("ПАКЕТ ПЕРЕГРЕЛСЯ: выпал (−15% цены, тревога +7). Работайте цепочкой [F]!");
        }

        // данк: свободный лут, оказавшийся в зоне выноса (брошенный/уроненный),
        // засчитывается сам; влетевший на скорости — «трёхочковый» +15%
        void TickPadIntake()
        {
            for (int i = 0; i < _loot.Count; i++)
            {
                var l = _loot[i];
                if (l.deposited || l.carried || l.carrier != 0 || l.body == null) continue;
                if (Vector3.Distance(l.body.position, PadPos) > PadRadius + 0.4f) continue;
                bool dunk = l.rb != null && !l.rb.isKinematic && l.rb.linearVelocity.magnitude > 4f;
                l.deposited = true;
                if (l.fake) { SpamBusted(l, i); continue; }
                // адаптивный АВ выучил данки: бонуса нет, бросок злит систему
                bool countered = dunk && S.avCounter == "dunk";
                if (dunk) { S.lastDunks++; S.AvNote("dunk"); }
                float got = S.DepositValue(l.value * (dunk && !countered ? 1.15f : 1f));
                if (countered) AlarmEvent(4f);
                Destroy(l.body.gameObject);
                if (_coop)
                    Net.NetManager.Send(NetSync.MsgLootDeposit(_netScene, i, S.access));
                string combo = S.ComboCount > 1 ? $"  КОМБО ×{S.ComboMult:0.0}" : "";
                Sfx.Play(dunk ? "win" : "deposit", dunk ? 0.4f : 0.4f);
                _hud?.Toast(countered
                    ? $"ФИЛЬТР БРОСКОВ: ◈ +{(int)got} без бонуса, тревога +4{combo}"
                    : dunk
                    ? $"ТРЁХОЧКОВЫЙ! ◈ +{(int)got} (+15% за бросок){combo}"
                    : $"◈ +{(int)got} — в зоне выноса!{combo}");
                if (!S.evacOpen && S.access >= 100f) OpenEvac(false);
            }
        }

        void TickCarryAndDeposit()
        {
            if (_carried != null)
            {
                // второй носильщик рядом ускоряет тяжёлый груз
                bool helper = _carried.weight >= 2 && HelperNear();
                if (helper != _helperActive)
                {
                    _helperActive = helper;
                    if (helper) _hud?.Toast("ВТОРОЙ НОСИЛЬЩИК: тащите вдвоём — быстрее!");
                }
                _player.carryFactor = CarryFactorFor(_carried, helper);

                var target = _player.transform.position + Vector3.up * 2.2f;
                _carried.body.position = Vector3.Lerp(_carried.body.position, target, Mathf.Min(14f * Time.deltaTime, 1f));
                if (Vector3.Distance(_carried.body.position, PadPos) < PadRadius + 0.6f)
                {
                    var l = _carried;
                    DropLoot();
                    l.deposited = true;
                    if (l.fake) { SpamBusted(l, _loot.IndexOf(l)); return; }
                    float got = S.DepositValue(l.value);
                    Destroy(l.body.gameObject);
                    if (_coop)
                        Net.NetManager.Send(NetSync.MsgLootDeposit(_netScene, _loot.IndexOf(l), S.access));
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
                    AlarmEvent(5f);
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
            ExitOperator();   // вернуть камеру игроку до экрана результатов
            Sfx.Play(victory ? "win" : "fail", 0.5f);
            S.FinishHack(victory);
            App.SaveSystem.Save();   // прогресс кампании переживает закрытие игры
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

            // карточка результата на UIKit
            var card = UI.UIKit.Panel(canvasGo.transform, new Vector2(0.5f, 0.5f), Vector2.zero,
                new Vector2(640, 440), UI.UIKit.PanelBg2);
            var accent = victory ? GameData.INFECTED : new Color(1f, 0.3f, 0.4f);
            UI.UIKit.Panel(card.transform, new Vector2(0.5f, 1), new Vector2(0, -4), new Vector2(632, 5),
                new Color(accent.r, accent.g, accent.b, 0.9f));
            MakeUiText(card.transform, victory ? "СЕРВЕР ВЗЛОМАН" : "РЕЙД ПРОВАЛЕН", new Vector2(0, 120), 42, accent);
            string archName = _arch != "" ? $"{GameData.ARCHETYPES[_arch].name} · " : "";
            MakeUiText(card.transform, $"{archName}{reason}", new Vector2(0, 62), 21, new Color(0.88f, 0.95f, 1f));
            string dunks = S.lastDunks > 0 ? $" · данков: {S.lastDunks}" : "";
            string combo = S.lastBestCombo > 1 ? $" · комбо ×{S.lastBestCombo}" : "";
            MakeUiText(card.transform, $"Вынесено ◈{S.lastDelivered} за {S.lastDeposits} ходок{dunks}{combo}",
                new Vector2(0, 22), 19, new Color(0.6f, 0.75f, 0.85f));
            // новые рекорды кампании — золотая строка
            if (S.lastRecordLoot || S.lastRecordCombo)
            {
                string rec = "НОВЫЙ РЕКОРД: " +
                    (S.lastRecordLoot ? $"добыча ◈{S.records["bestLoot"]}" : "") +
                    (S.lastRecordLoot && S.lastRecordCombo ? " и " : "") +
                    (S.lastRecordCombo ? $"комбо ×{S.records["bestCombo"]}" : "") + "!";
                MakeUiText(card.transform, rec, new Vector2(0, -8), 18, new Color(1f, 0.82f, 0.3f));
            }
            MakeUiText(card.transform,
                $"Карьера: {S.career["deposits"]} вносов · {S.career["tasks"]} задач · {S.career["raids"]} рейдов · ◈{S.career["delivered"]} всего",
                new Vector2(0, -38), 16, new Color(0.55f, 0.65f, 0.75f));
            // сводка неприятностей — есть чем оправдаться перед стаей
            if (_statFragileBroken + _statOverheats + _statMimics > 0)
            {
                var bits = new List<string>();
                if (_statFragileBroken > 0) bits.Add($"разбито хрупких: {_statFragileBroken}");
                if (_statOverheats > 0) bits.Add($"перегревов: {_statOverheats}");
                if (_statMimics > 0) bits.Add($"мимиков стряхнуто: {_statMimics}");
                MakeUiText(card.transform, string.Join(" · ", bits), new Vector2(0, -64), 15,
                    new Color(1f, 0.6f, 0.4f));
            }
            // выполненные контракты доски — золотая строка с наградой
            if (S.lastContractsDone.Count > 0)
            {
                var cbits = new List<string>();
                foreach (var id in S.lastContractsDone)
                    cbits.Add($"{GameData.CONTRACTS[id].name} ({GameData.RewardLabel(GameData.CONTRACTS[id].reward)})");
                MakeUiText(card.transform, "КОНТРАКТ ВЫПОЛНЕН: " + string.Join(" · ", cbits),
                    new Vector2(0, -86), 16, new Color(1f, 0.82f, 0.3f));
            }
            UI.UIKit.MakeButton(card.transform, "ВЕРНУТЬСЯ В ГРИД", new Vector2(0, -142), new Vector2(380, 56),
                () => { Debug.Log("[UI] results->grid click"); App.SceneFlow.GoGrid(); }, GameData.INFECTED);
            MakeUiText(card.transform, "клик · Enter · Пробел", new Vector2(0, -190), 14, new Color(0.45f, 0.55f, 0.65f));
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

    // сторож хрупкого лута: физика сообщает о жёстких ударах корпуса
    public class FragileWatch : MonoBehaviour
    {
        public System.Action<float> onImpact;
        void OnCollisionEnter(Collision c) => onImpact?.Invoke(c.relativeVelocity.magnitude);
    }
}
