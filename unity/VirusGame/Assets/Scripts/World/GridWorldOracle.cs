using UnityEngine;
using Virus.Core;
using Virus.Util;

namespace Virus.World
{
    // ОРАКУЛ: зал одного гигантского сервера. 15 головоломок + магистраль +
    // рычаг + 3 территории → щит падает → украсть данные с 4 стоек →
    // разрушить ядро → побег. По залу гоняют 10 роботов.
    public partial class GridWorld
    {
        void BuildOracle()
        {
            var r = GameData.ROOMS["or"];
            // панели-стойки по периметру
            for (int i = 0; i < 10; i++)
            {
                float px = Mathf.Lerp(r.x0 + 8, r.x1 - 8, i / 9f);
                Build.MeshBox(transform, new Vector3(6, 9, 1), Mats.MetalDark(0.45f), new Vector3(px, 4.5f, r.zn + 1.6f));
                Build.MeshBox(transform, new Vector3(5.4f, 0.12f, 0.2f), Mats.Neon(new Color(0.2f, 0.7f, 1f), 1.4f), new Vector3(px, 3f + i % 3, r.zn + 2.15f));
            }
            for (var cp = 0; cp < 4; cp++)
                Build.SpotDown(transform, new Vector3(cp % 2 == 0 ? 84 : 164, 18, cp < 2 ? -302 : -374), new Color(0.5f, 0.75f, 1f), 3f, 26f, 70f);

            BuildOracleCore();

            foreach (var pd in GridData.ORACLE_PYLONS) MakePylon(pd);
            foreach (var (key, pos) in GridData.ORACLE_TERRS) MakeTerritory(key, pos);
            MakeWire("or", new Vector3[] { new(140, 0, -296), new(150, 0, -302), new(158, 0, -309), new(164, 0, -317) },
                new Color(0.2f, 0.85f, 1f), "МАГИСТРАЛЬ ОРАКУЛА");
            MakeLever("or", new Vector3(108, 0, -296), "РУБИЛЬНИК ЗАЛА");
            foreach (var (key, pos) in GridData.ORACLE_RACKS) MakeRack(key, pos);
            foreach (var sp in GridData.BOT_SPAWNS) SpawnBot(sp);

            BuildEscapePortal();
            if (S.oracleCoreDown) SetCoreDestroyed(true);
        }

        void BuildOracleCore()
        {
            var pos = GridData.ORACLE_CORE;
            // башня ядра
            _coreMat = Mats.Neon(GameData.ORACLE, 1.4f);
            Build.Solid(transform, new Vector3(11, 16, 11), Mats.Obsidian(), pos + Vector3.up * 8f);
            for (int k = 0; k < 4; k++)
                Build.MeshBox(transform, new Vector3(11.5f, 0.3f, 11.5f), _coreMat, pos + Vector3.up * (2.5f + k * 3.6f));
            _eyeMat = Mats.Neon(GameData.ORACLE, 3f);
            Build.MeshBox(transform, Vector3.one * 3.4f, _eyeMat, pos + Vector3.up * 17.6f);
            Build.Omni(transform, pos + Vector3.up * 17.6f, GameData.ORACLE, 3f, 26f);

            // энергощит
            if (!S.OracleCoreOpen() && !S.oracleCoreDown)
            {
                _shield = new GameObject("shield");
                _shield.transform.SetParent(transform, false);
                _shield.transform.position = pos + Vector3.up * 7f;
                var mesh = Build.MeshBox(_shield.transform, new Vector3(20, 14, 20), Mats.Neon(GameData.ORACLE, 0.25f), Vector3.zero);
                mesh.GetComponent<MeshRenderer>().sharedMaterial.SetColor("_BaseColor", new Color(0.3f, 0.02f, 0.05f, 1f));
                var col = _shield.AddComponent<BoxCollider>();
                col.size = new Vector3(20, 14, 20);
            }

            _board = Build.Label(transform, "", pos + Vector3.up * 13.5f, 4.6f, new Color(0.85f, 0.92f, 1f));
        }

        void RefreshOracleShield()
        {
            if (_shield == null || !S.OracleCoreOpen()) return;
            Destroy(_shield);
            _shield = null;
            _hud?.Toast("ЩИТ ОРАКУЛА ПАЛ — крадите данные со стоек!");
        }

        void MakePylon(GridData.Pylon pd)
        {
            bool solved = S.Flag(pd.key);
            var root = new GameObject("pylon").transform;
            root.SetParent(transform, false);
            root.localPosition = pd.pos;
            Build.Solid(root, new Vector3(0.9f, 1.2f, 0.6f), Mats.Obsidian(), new Vector3(0, 0.6f, 0));
            Build.MeshBox(root, new Vector3(1.1f, 0.7f, 0.1f), Mats.Neon(solved ? GameData.INFECTED : GameData.ORACLE, 1.3f), new Vector3(0, 1.5f, 0.2f));
            var num = pd.key.Substring(4);
            var lbl = Build.Label(root, $"ГОЛОВОЛОМКА {num}\n{(solved ? "РЕШЕНА" : "[E] взломать")}", new Vector3(0, 2.5f, 0), 2.4f,
                solved ? GameData.INFECTED : new Color(1f, 0.5f, 0.55f));
            if (!solved)
            {
                var it = MakeInteract(root, new Vector3(0, 1, 0), 2.8f);
                it.prompt = $"[E] ГОЛОВОЛОМКА ОРАКУЛА {num}/15";
                it.enabledFn = () => !S.Flag(pd.key);
                it.onInteract = () => UI.PuzzleUI.Open(pd.diff, "ГОЛОВОЛОМКА ОРАКУЛА", () =>
                {
                    S.SetFlag(pd.key);
                    lbl.text = $"ГОЛОВОЛОМКА {num}\nРЕШЕНА";
                    lbl.color = GameData.INFECTED;
                    _hud?.Toast($"ГОЛОВОЛОМКИ ОРАКУЛА: {S.OraclePuzzlesDone()}/{GameData.ORACLE_PUZZLES_TOTAL}");
                    RefreshOracleShield();
                });
            }
        }

        void MakeTerritory(string key, Vector3 pos)
        {
            bool done = S.Flag(key);
            var mat = Mats.Neon(done ? GameData.INFECTED : GameData.ORACLE, 1.2f);
            // кольцо из 12 сегментов
            for (int i = 0; i < 12; i++)
            {
                float a = i * Mathf.PI * 2f / 12f;
                Build.MeshBox(transform, new Vector3(1.4f, 0.1f, 0.3f), mat,
                    pos + new Vector3(Mathf.Cos(a) * 4.8f, 0.1f, Mathf.Sin(a) * 4.8f));
            }
            Build.MeshBox(transform, new Vector3(0.4f, 2.4f, 0.4f), mat, pos + Vector3.up * 1.2f);
            var st = new TerrState { pos = pos, prog = done ? 1f : 0f, mat = mat };
            st.label = Build.Label(transform, done ? "ТЕРРИТОРИЯ ЗАХВАЧЕНА" : "ТЕРРИТОРИЯ ОРАКУЛА\nвстань в кольцо для захвата",
                pos + Vector3.up * 3.2f, 2.8f, done ? GameData.INFECTED : new Color(1f, 0.6f, 0.6f));
            _terrs[key] = st;
        }

        void TickTerrs()
        {
            if (_player == null) return;
            foreach (var kv in _terrs)
            {
                if (S.Flag(kv.Key)) continue;
                var st = kv.Value;
                var pp = _player.transform.position;
                bool inside = new Vector2(pp.x - st.pos.x, pp.z - st.pos.z).magnitude < 5f && pp.y < 2f;
                if (inside)
                {
                    st.prog = Mathf.Min(st.prog + Time.deltaTime / 12f, 1f);
                    st.label.text = $"ЗАХВАТ ТЕРРИТОРИИ: {(int)(st.prog * 100)}%\n(стой в кольце)";
                    if (st.prog >= 1f)
                    {
                        S.SetFlag(kv.Key);
                        st.mat.SetColor("_EmissionColor", (Color)GameData.INFECTED * 1.4f);
                        st.label.text = "ТЕРРИТОРИЯ ЗАХВАЧЕНА";
                        st.label.color = GameData.INFECTED;
                        _hud?.Toast($"ТЕРРИТОРИИ ОРАКУЛА: {S.OracleTerritoriesDone()}/{GameData.ORACLE_TERRITORIES}");
                        RefreshOracleShield();
                    }
                }
            }
        }

        void MakeRack(string key, Vector3 pos)
        {
            bool done = S.Flag(key);
            var root = new GameObject("rack").transform;
            root.SetParent(transform, false);
            root.localPosition = pos;
            Build.Solid(root, new Vector3(1.8f, 2.6f, 1f), Mats.MetalDark(0.4f), new Vector3(0, 1.3f, 0));
            var scr = Mats.Neon(done ? GameData.INFECTED : new Color(0.2f, 0.85f, 0.4f), 1.2f);
            Build.MeshBox(root, new Vector3(0.8f, 0.5f, 0.08f), scr, new Vector3(0.3f, 2.2f, 0.54f));
            var lbl = Build.Label(root, "", new Vector3(0, 3.4f, 0), 2.6f, done ? GameData.INFECTED : new Color(0.4f, 0.95f, 0.55f));
            lbl.text = done ? "СТОЙКА ДАННЫХ\nИНФОРМАЦИЯ УКРАДЕНА" : "СТОЙКА ДАННЫХ";
            if (!done)
            {
                var it = MakeInteract(root, new Vector3(0, 1.3f, 0), 2.8f);
                it.holdSeconds = 3f;
                it.dynamicPrompt = () => S.OracleCoreOpen()
                    ? "кража данных…"
                    : "стойка экранирована: головоломки + магистраль + рубильник + территории";
                it.enabledFn = () => !S.Flag(key);
                it.onInteract = () =>
                {
                    if (!S.OracleCoreOpen()) return;
                    S.SetFlag(key);
                    scr.SetColor("_EmissionColor", (Color)GameData.INFECTED * 1.2f);
                    lbl.text = "СТОЙКА ДАННЫХ\nИНФОРМАЦИЯ УКРАДЕНА";
                    lbl.color = GameData.INFECTED;
                    S.resources["data_fragments"] += 40;
                    _hud?.Toast($"ДАННЫЕ УКРАДЕНЫ: {S.OracleRacksDone()}/{GameData.ORACLE_RACKS} (+40 Data)");
                    if (S.OracleDataStolen()) _hud?.Toast("ВСЯ ИНФОРМАЦИЯ У НАС — РУШЬТЕ ЯДРО ОРАКУЛА!");
                };
            }

            // ядро: интеракт на разрушение (один, вешаем от первой стойки)
            if (key == "orack:1")
            {
                var core = MakeInteract(transform, GridData.ORACLE_CORE + Vector3.up * 1.5f, 9f);
                core.holdSeconds = 5f;
                core.dynamicPrompt = () =>
                    S.oracleCoreDown ? "" :
                    !S.OracleCoreOpen() ? "ЯДРО ЭКРАНИРОВАНО — смотри табло над Оракулом" :
                    !S.OracleDataStolen() ? $"сначала украдите ВСЮ информацию: стойки {S.OracleRacksDone()}/{GameData.ORACLE_RACKS}" :
                    "РАЗРУШЕНИЕ ЯДРА…";
                core.enabledFn = () => !S.oracleCoreDown;
                core.onInteract = () =>
                {
                    if (!S.OracleCoreOpen() || !S.OracleDataStolen()) return;
                    SetCoreDestroyed(false);
                };
            }
        }

        void SetCoreDestroyed(bool atLoad)
        {
            S.oracleCoreDown = true;
            _eyeMat?.SetColor("_EmissionColor", new Color(0.25f, 0.28f, 0.32f) * 0.4f);
            _coreMat?.SetColor("_EmissionColor", new Color(0.3f, 0.1f, 0.1f) * 0.5f);
            if (_escapeGo != null) _escapeGo.SetActive(true);
            if (!atLoad)
            {
                _hud?.Toast("ЯДРО ОРАКУЛА РАЗРУШЕНО — БЕГИ К ПОРТАЛУ!");
                UpdateObjective();
            }
        }

        void BuildEscapePortal()
        {
            var pos = new Vector3(122, 0, -294);
            _escapeGo = new GameObject("escape");
            _escapeGo.transform.SetParent(transform, false);
            _escapeGo.transform.localPosition = pos;
            Build.MeshBox(_escapeGo.transform, new Vector3(3.4f, 0.3f, 3.4f), Mats.Neon(GameData.INFECTED, 2.4f), new Vector3(0, 0.15f, 0));
            Build.Omni(_escapeGo.transform, new Vector3(0, 2, 0), GameData.INFECTED, 2.5f, 12f);
            Build.Label(_escapeGo.transform, "ЭВАКУАЦИЯ ИЗ ГРИДА\n[E] сбежать", new Vector3(0, 4.2f, 0), 3.4f, GameData.INFECTED);
            var it = MakeInteract(_escapeGo.transform, new Vector3(0, 1, 0), 3.4f);
            it.prompt = "[E] СБЕЖАТЬ ИЗ ГРИДА";
            it.onInteract = () =>
            {
                S.campaignWon = true;
                App.SceneFlow.GoVictory();
            };
            _escapeGo.SetActive(false);
        }

        // ── роботы Оракула ──
        void SpawnBot(Vector3 pos)
        {
            var root = new GameObject("bot").transform;
            root.SetParent(transform, false);
            root.localPosition = pos;
            var body = Mats.Metal(new Color(0.5f, 0.52f, 0.58f), 0.35f);
            Build.MeshBox(root, new Vector3(1.6f, 0.5f, 2.1f), body, new Vector3(0, 0.65f, 0));
            Build.MeshBox(root, new Vector3(1.3f, 0.9f, 1f), body, new Vector3(0, 1.5f, 0));
            Build.MeshBox(root, Vector3.one * 0.55f, body, new Vector3(0, 2.25f, 0));
            Build.MeshBox(root, Vector3.one * 0.24f, Mats.Neon(GameData.ORACLE, 4f), new Vector3(0, 2.3f, 0.32f));
            Build.Omni(root, new Vector3(0, 2.4f, 0), GameData.ORACLE, 1.2f, 7f);
            _robots.Add(new BotState { node = root, wp = pos, t = Random.Range(0f, 2f) });
        }

        void TickRobots()
        {
            if (_player == null || _robots.Count == 0) return;
            var pp = _player.transform.position;
            bool inHall = pp.z < -290f;
            bool frenzy = S.oracleCoreDown;
            foreach (var rb in _robots)
            {
                if (rb.node == null) continue;
                rb.t -= Time.deltaTime;
                var target = rb.wp;
                float speed = 4f, sight = frenzy ? 22f : 15f;
                float distP = Vector3.Distance(rb.node.position, pp);
                if (inHall && distP < sight) { target = pp; speed = frenzy ? 7.6f : 6.4f; }
                else if (rb.t <= 0f || Vector3.Distance(rb.node.position, target) < 2f)
                {
                    rb.t = Random.Range(2.5f, 6f);
                    for (int a = 0; a < 8; a++)
                    {
                        var cand = new Vector3(Random.Range(76f, 172f), 0, Random.Range(-380f, -296f));
                        if (Vector3.Distance(cand, GridData.ORACLE_CORE) > 14f) { rb.wp = cand; break; }
                    }
                    target = rb.wp;
                }
                var dir = target - rb.node.position;
                dir.y = 0;
                if (dir.magnitude > 1.2f)
                {
                    rb.node.position += dir.normalized * (speed * Time.deltaTime);
                    rb.node.rotation = Quaternion.Slerp(rb.node.rotation, Quaternion.LookRotation(dir), 8f * Time.deltaTime);
                }
                if (inHall && distP < 1.8f && _knockLock <= 0f)
                    Knockdown(GridData.ORACLE_ENTRY, rb.node.position, "РОБОТ ОРАКУЛА вышвырнул тебя ко входу!");
            }
        }

        void TickBoard()
        {
            _boardT -= Time.deltaTime;
            if (_boardT > 0f || _board == null) return;
            _boardT = 0.5f;
            if (S.oracleCoreDown)
            {
                _board.text = "// ОРАКУЛ МЁРТВ //\nбеги к порталу эвакуации";
                _board.color = GameData.INFECTED;
                return;
            }
            string lines = $"ШТУРМ ОРАКУЛА\nголоволомки {S.OraclePuzzlesDone()}/{GameData.ORACLE_PUZZLES_TOTAL} · территории {S.OracleTerritoriesDone()}/{GameData.ORACLE_TERRITORIES}\n" +
                           $"магистраль {(S.Flag("wire:or") ? "+" : "-")} · рубильник {(S.Flag("lever:or") ? "+" : "-")}";
            if (S.OracleCoreOpen())
            {
                lines += $"\nЩИТ ПАЛ · данные {S.OracleRacksDone()}/{GameData.ORACLE_RACKS}";
                if (S.OracleDataStolen()) lines += "\n[E у ядра] РАЗРУШИТЬ СЕРВЕР";
            }
            _board.text = lines;
        }
    }
}
