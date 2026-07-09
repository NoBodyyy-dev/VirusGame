using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;
using Virus.Core;
using Virus.Util;

namespace Virus.World
{
    // Порт ядра level.gd: рейд-ограбление внутри сервера.
    // Арена по теме тира, физический лут (тащи к порталу), СИСТЕМА с тревогой
    // (SLEEP→SCAN→PURGE→WIPE), ловушки из стен, роботы-охранники по углам
    // (охота на 100%), HP/баг, эвакуация по квоте, экран результатов.
    public class Level : MonoBehaviour
    {
        static readonly Vector3 PadPos = new(-27, 0, 0);
        const float PadRadius = 3.6f;

        GameState S => GameState.I;
        Player.VirusPlayer _player;
        UI.Hud _hud;
        System.Random _rng;
        float _hallW, _hallD;

        class Loot { public Transform body; public Rigidbody rb; public float value; public int weight; public bool carried, deposited; public TextMesh label; }
        readonly List<Loot> _loot = new();
        Loot _carried;

        class Orb { public Transform t; public float life; }
        readonly List<Orb> _orbs = new();
        class Guard { public Transform t; public Vector3 home; public float meleeCd; }
        readonly List<Guard> _guards = new();

        float _trapTimer, _hitLock, _reviveT;
        int _phaseSeen;
        bool _done;
        Light _moon;
        Color _accent;

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

            BuildEnvironment();
            BuildArena();
            BuildPortal();
            SpawnLoot();
            SpawnGuards();
            SpawnPlayer();

            _hud = FindFirstObjectByType<UI.Hud>();
            if (_hud != null)
            {
                _hud.raidMode = true;
                _hud.Toast($"{S.raid.name} · {GameData.TIERS[S.raid.tier].name} · выносим лут и тихо!");
                _hud.SetObjective("Тащи лут в круг у портала — набери 100% квоты");
            }
        }

        float R(float a, float b) => Mathf.Lerp(a, b, (float)_rng.NextDouble());

        void BuildEnvironment()
        {
            QualitySettings.pixelLightCount = 10;
            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Trilight;
            RenderSettings.ambientSkyColor = new Color(0.34f, 0.4f, 0.52f);
            RenderSettings.ambientEquatorColor = new Color(0.28f, 0.3f, 0.36f);
            RenderSettings.ambientGroundColor = new Color(0.12f, 0.13f, 0.16f);
            RenderSettings.fog = true;
            RenderSettings.fogColor = new Color(0.05f, 0.07f, 0.11f);
            RenderSettings.fogMode = FogMode.Exponential;
            RenderSettings.fogDensity = 0.004f;
            RenderSettings.skybox = null;

            _moon = new GameObject("Fill").AddComponent<Light>();
            _moon.type = LightType.Directional;
            _moon.color = new Color(0.55f, 0.65f, 0.85f);
            _moon.intensity = 0.5f;
            _moon.transform.rotation = Quaternion.Euler(58, -28, 0);
            _moon.shadows = LightShadows.Soft;
        }

        void BuildArena()
        {
            float hx = _hallW * 0.5f, hz = _hallD * 0.5f;
            Build.Solid(transform, new Vector3(_hallW, 0.5f, _hallD), Mats.Concrete(new Color(0.2f, 0.22f, 0.26f)), new Vector3(0, -0.25f, 0));
            var wall = Mats.Concrete(new Color(0.42f, 0.44f, 0.48f));
            Build.Solid(transform, new Vector3(_hallW, 7, 0.6f), wall, new Vector3(0, 3.5f, -hz));
            Build.Solid(transform, new Vector3(_hallW, 7, 0.6f), wall, new Vector3(0, 3.5f, hz));
            Build.Solid(transform, new Vector3(0.6f, 7, _hallD), wall, new Vector3(-hx, 3.5f, 0));
            Build.Solid(transform, new Vector3(0.6f, 7, _hallD), wall, new Vector3(hx, 3.5f, 0));
            Build.Solid(transform, new Vector3(_hallW, 0.35f, _hallD), Mats.Concrete(new Color(0.3f, 0.31f, 0.34f)), new Vector3(0, 7.3f, 0));

            // акцент тира по периметру + прожекторы
            Build.MeshBox(transform, new Vector3(_hallW - 2, 0.06f, 0.2f), Mats.Neon(_accent, 1.2f), new Vector3(0, 0.05f, -hz + 1.2f));
            Build.MeshBox(transform, new Vector3(_hallW - 2, 0.06f, 0.2f), Mats.Neon(_accent, 1.2f), new Vector3(0, 0.05f, hz - 1.2f));
            for (int gx = 0; gx < 3; gx++)
                for (int gz = 0; gz < 2; gz++)
                {
                    var lp = new Vector3((gx - 1) * _hallW * 0.3f, 6.9f, (gz - 0.5f) * _hallD * 0.42f);
                    Build.MeshBox(transform, new Vector3(4.6f, 0.14f, 1.7f), Mats.Neon(new Color(1f, 0.93f, 0.78f), 2.4f), lp);
                    var sl = Build.SpotDown(transform, lp + Vector3.down * 0.3f, new Color(1f, 0.93f, 0.8f), 4.2f, 16f);
                    sl.shadows = LightShadows.Soft;
                }

            // тематический реквизит по тиру
            var propMat = Mats.Plastic(new Color(0.3f, 0.33f, 0.38f));
            int props = 8 + S.raid.tier * 3;
            for (int i = 0; i < props; i++)
            {
                var pos = new Vector3(R(-hx + 6, hx - 6), 0, R(-hz + 5, hz - 5));
                if (Vector3.Distance(pos, PadPos) < 8f) continue;
                float h = R(1.2f, 3.6f);
                Build.Solid(transform, new Vector3(R(1.4f, 3.4f), h, R(1.2f, 2.6f)), propMat, pos + Vector3.up * (h * 0.5f));
                if (_rng.NextDouble() < 0.5)
                    Build.MeshBox(transform, new Vector3(1.2f, 0.08f, 0.08f), Mats.Neon(_accent, 1.2f), pos + Vector3.up * (h + 0.06f));
            }

            // экран СИСТЕМЫ на стене
            Build.MeshBox(transform, new Vector3(11, 4.6f, 0.5f), Mats.Plastic(new Color(0.2f, 0.22f, 0.26f)), new Vector3(6, 3.4f, -hz + 0.6f));
            _sysScreen = Build.Label(transform, "", new Vector3(6, 3.4f, -hz + 1.0f), 3.4f, new Color(0.75f, 0.95f, 1f), false);
        }

        TextMesh _sysScreen;

        void BuildPortal()
        {
            Build.MeshBox(transform, new Vector3(PadRadius * 2, 0.1f, PadRadius * 2), Mats.Neon(GameData.INFECTED, 0.5f), PadPos + Vector3.up * 0.05f);
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
                    : "[E] бросить лут";
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
            _player.carryFactor = loot.weight >= 2 ? 0.38f : 0.78f;
        }

        void DropLoot()
        {
            if (_carried == null) return;
            _carried.carried = false;
            _carried.rb.isKinematic = false;
            _carried = null;
            _player.carrying = false;
            _player.carryFactor = 1f;
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
                Build.Omni(root, new Vector3(0, 2.6f, 0), new Color(1f, 0.25f, 0.2f), 1.4f, 9f);
                _guards.Add(new Guard { t = root, home = corners[i] });
            }
        }

        void SpawnPlayer()
        {
            var go = new GameObject("Player", typeof(CharacterController), typeof(Player.VirusPlayer));
            _player = go.GetComponent<Player.VirusPlayer>();
            go.transform.position = new Vector3(-27, 1.2f, 3);
        }

        void Update()
        {
            if (_done || _player == null) return;
            float dt = Time.deltaTime;
            _hitLock = Mathf.Max(_hitLock - dt, 0f);

            // тревога ползёт сама; на эвакуации — быстрее
            S.ApplyAlarm(S.raid.creep * (S.evacOpen ? 1.6f : 1f) * dt);
            TickPhaseFx();
            TickTraps(dt);
            TickGuards(dt);
            TickCarryAndDeposit();
            TickBugAndRevive(dt);
            TickEvac(dt);
            TickSystemScreen();
        }

        void TickPhaseFx()
        {
            int ph = S.AlarmPhase();
            if (ph != _phaseSeen && ph > _phaseSeen)
            {
                string[] msg = { "", "СИСТЕМА: СКАНИРОВАНИЕ — ловушки активированы!", "СИСТЕМА: ЗАЧИСТКА — ловушки летят чаще!", "СИСТЕМА: ВТОРЖЕНИЕ — роботы вышли на охоту!" };
                _hud?.Toast(msg[ph]);
            }
            _phaseSeen = ph;
            RenderSettings.fogColor = ph switch
            {
                3 => new Color(0.25f, 0.03f, 0.05f),
                2 => new Color(0.2f, 0.08f, 0.08f),
                1 => new Color(0.14f, 0.11f, 0.06f),
                _ => new Color(0.05f, 0.07f, 0.11f),
            };
        }

        void TickTraps(float dt)
        {
            // сфера-ловушка летит в игрока из ближайшей стены (фаза SCAN+)
            if (S.AlarmPhase() >= 1 && !S.myBug)
            {
                float speedup = 1f + S.alarm / 100f + S.raid.tier * 0.25f;
                _trapTimer -= dt * speedup;
                if (_trapTimer <= 0f)
                {
                    _trapTimer = S.raid.trapInterval;
                    float hx = _hallW * 0.5f, hz = _hallD * 0.5f;
                    var pp = _player.transform.position;
                    var candidates = new[] { new Vector3(-hx + 1, 2.2f, pp.z), new Vector3(hx - 1, 2.2f, pp.z), new Vector3(pp.x, 2.2f, -hz + 1), new Vector3(pp.x, 2.2f, hz - 1) };
                    var origin = candidates[0];
                    foreach (var c in candidates) if (Vector3.Distance(c, pp) < Vector3.Distance(origin, pp)) origin = c;
                    var orb = Build.MeshBox(transform, Vector3.one * 0.45f, Mats.Neon(new Color(1f, 0.25f, 0.3f), 3.5f), origin);
                    Build.Omni(orb.transform, Vector3.zero, new Color(1f, 0.25f, 0.3f), 1.2f, 4f);
                    _orbs.Add(new Orb { t = orb.transform, life = 12f });
                }
            }
            for (int i = _orbs.Count - 1; i >= 0; i--)
            {
                var o = _orbs[i];
                o.life -= dt;
                if (o.t == null || o.life <= 0f) { if (o.t != null) Destroy(o.t.gameObject); _orbs.RemoveAt(i); continue; }
                var target = _player.transform.position + Vector3.up * 1.1f;
                o.t.position = Vector3.MoveTowards(o.t.position, target, 8.5f * dt);
                if (Vector3.Distance(o.t.position, target) < 1f)
                {
                    Destroy(o.t.gameObject);
                    _orbs.RemoveAt(i);
                    HurtPlayer(o.t.position);
                }
            }
        }

        void TickGuards(float dt)
        {
            bool hunt = S.AlarmPhase() >= 3;
            foreach (var g in _guards)
            {
                g.meleeCd = Mathf.Max(g.meleeCd - dt, 0f);
                var pp = _player.transform.position;
                if (hunt && !S.myBug)
                {
                    var dir = pp - g.t.position; dir.y = 0;
                    if (dir.magnitude > 1.6f)
                    {
                        g.t.position += dir.normalized * (6f * dt);
                        g.t.rotation = Quaternion.Slerp(g.t.rotation, Quaternion.LookRotation(dir), 8f * dt);
                    }
                    else if (g.meleeCd <= 0f) { g.meleeCd = 1.4f; HurtPlayer(g.t.position); }
                }
                else
                {
                    var back = g.home - g.t.position; back.y = 0;
                    if (back.magnitude > 1f) g.t.position += back.normalized * (3.5f * dt);
                }
            }
        }

        void HurtPlayer(Vector3 from)
        {
            if (_hitLock > 0f || S.myBug || _done) return;
            _hitLock = 1.2f;
            S.myHp = Mathf.Max(S.myHp - 1, 0);
            S.ApplyAlarm(2f);
            DropLoot();
            var push = _player.transform.position - from; push.y = 0;
            _player.Impulse(push.normalized * 11f + Vector3.up * 7f);
            if (S.myHp <= 0)
            {
                S.myBug = true;
                _player.baseSpeed = 3.4f;
                _player.sprintSpeed = 3.4f;
                _hud?.Toast("КРИТИЧЕСКИЙ СБОЙ: ты — БАГ. Ползи к порталу!");
            }
            else _hud?.Toast($"ЛОВУШКА СИСТЕМЫ! HP −1 ({S.myHp}/{S.myMaxHp})");
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
                    S.DepositValue(l.value);
                    Destroy(l.body.gameObject);
                    _hud?.Toast($"◈ +{(int)l.value} — внесено! Добыча {(int)S.access}%");
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
                    _player.baseSpeed = 6f;
                    _player.sprintSpeed = 9.2f;
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
            _sysScreen.text = $"СИСТЕМА {S.raid.av}\nчувствительность {S.raid.sensitivity} · роботов {_guards.Count}\nтревога {(int)S.alarm}% · {S.AlarmPhaseName()}";
        }

        void Finish(bool victory, string reason)
        {
            if (_done) return;
            _done = true;
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

            MakeUiText(canvasGo.transform, victory ? "СЕРВЕР ВЗЛОМАН" : "РЕЙД ПРОВАЛЕН", new Vector2(0, 120), 44,
                victory ? GameData.INFECTED : new Color(1f, 0.3f, 0.4f));
            MakeUiText(canvasGo.transform, reason, new Vector2(0, 60), 22, new Color(0.88f, 0.95f, 1f));
            MakeUiText(canvasGo.transform, $"Вынесено ◈{S.lastDelivered} за {S.lastDeposits} ходок", new Vector2(0, 20), 20, new Color(0.6f, 0.75f, 0.85f));

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
