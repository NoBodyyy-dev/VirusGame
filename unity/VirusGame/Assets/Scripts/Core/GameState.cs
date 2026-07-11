using System;
using System.Collections.Generic;
using UnityEngine;

namespace Virus.Core
{
    public class ServerNode
    {
        public int id, zone, tier, seed;
        public Vector3 pos;
        public string door, room, name, av;
        public string arch = "";     // архетип: правило-твист узла (из сида)
        public bool infected, failed;
    }

    // Порт game_state.gd: кампания, зоны Грида, флаги интерактива, экономика,
    // конфиг рейда. Чистая логика — без прямых вызовов движка (только Vector3/
    // Color/Mathf). Сетевые хуки вынесены в делегаты (см. Net-порт).
    public class GameState
    {
        public static GameState I { get; private set; } = new GameState();

        // Хуки для коопа (в одиночке null): рассылка флага и захвата узла.
        public Action<string> SendFlag;
        public Action<int> SendNodeInfected;

        public event Action EvolutionChanged;

        // ── применение сетевых событий (без эха обратно в сеть) ──
        public void ApplyRemoteFlag(string key)
        {
            gridFlags[key] = true;
        }

        public void ApplyRemoteNode(int id)
        {
            if (id < 0 || id >= gridNodes.Count) return;
            if (gridNodes[id].infected) return;
            gridNodes[id].infected = true;
            gridNodes[id].failed = false;
            EvolutionChanged?.Invoke();
        }

        // ── прогрессия ──
        public string branch = "";
        public string secondaryBranch = "";
        public int virusLevel = 0;
        public readonly List<string> activeAbilities = new();
        public readonly List<string> stolenAbilities = new();
        public float resetUntil = 0f;    // «сброс до нуля»: до этого времени скин голый
        public float now = 0f;           // игровые часы ядра (двигает Tick)

        // карьерные счётчики — открывают умения по глубине ветки
        public readonly Dictionary<string, int> career = new()
            { {"deposits",0}, {"delivered",0}, {"tasks",0}, {"raids",0} };

        // ── адаптивный антивирус: система «учится» на злоупотреблениях ──
        // Счётчики копятся между рейдами; на пороге АВ выкатывает контрмеру
        // в следующем рейде (T1+) и счётчик сбрасывается — меняй стиль!
        public readonly Dictionary<string, int> avSeen = new()
            { {"dunk",0}, {"jam",0}, {"morph",0}, {"decoy",0}, {"freeze",0} };
        public const int AV_LEARN_AT = 6;
        public string avCounter = "";   // контрмера ТЕКУЩЕГО рейда ("" — нет)

        public void AvNote(string tactic, int amount = 1)
        {
            if (avSeen.ContainsKey(tactic)) avSeen[tactic] += amount;
        }

        // выбрать самый заезженный приём (порог достигнут) — его и контрят
        string AvPickCounter()
        {
            string best = "";
            int bestN = AV_LEARN_AT - 1;
            foreach (var kv in avSeen)
                if (kv.Value > bestN) { best = kv.Key; bestN = kv.Value; }
            return best;
        }

        public static readonly Dictionary<string, string> AV_COUNTER_DESC = new()
        {
            ["dunk"] = "ФИЛЬТР БРОСКОВ: данки без бонуса, влетевший лут злит систему (+4 тревоги)",
            ["jam"] = "АНТИ-ГЛУШЕНИЕ: терминал оператора давит фон вдвое слабее",
            ["morph"] = "ЭВРИСТИКА МАСКИРОВКИ: ложный файл вскрывается через 4с",
            ["decoy"] = "ТРАССИРОВКА ФАНТОМА: приманка живёт 2с вместо 5",
            ["freeze"] = "ГОРЯЧИЙ РЕЗЕРВ: шифрование морозит систему лишь 1.8с",
        };

        // ── контракты стаи: 3 испытания на кампанию (доска в Гриде) ──
        // Набор детерминирован сидом кампании — у стаи одна и та же доска.
        public readonly List<string> contracts = new();
        public readonly HashSet<string> contractsDone = new();
        public readonly List<string> lastContractsDone = new();   // взятые в ПОСЛЕДНЕМ рейде

        // пер-рейдовая статистика для условий контрактов
        public int lastHits, lastTasksRaid;
        public float lastMaxAlarm;

        void PickContracts()
        {
            contracts.Clear();
            var keys = new List<string>(GameData.CONTRACTS.Keys);
            keys.Sort(System.StringComparer.Ordinal);
            var rng = new System.Random(campaignSeed ^ 0x5EED);
            for (int i = keys.Count - 1; i > 0; i--)
            {
                int j = rng.Next(i + 1);
                (keys[i], keys[j]) = (keys[j], keys[i]);
            }
            for (int i = 0; i < 3 && i < keys.Count; i++) contracts.Add(keys[i]);
        }

        void CheckContracts(bool victory)
        {
            lastContractsDone.Clear();
            foreach (var id in contracts)
            {
                if (contractsDone.Contains(id)) continue;
                bool ok = id switch
                {
                    "untouched" => victory && lastHits == 0,
                    "ghost" => victory && lastMaxAlarm < 55f,
                    "showman" => lastDunks >= 3,
                    "courier" => lastDelivered >= 120,
                    "handyman" => lastTasksRaid >= 2,
                    _ => false,
                };
                if (!ok) continue;
                contractsDone.Add(id);
                lastContractsDone.Add(id);
                var rw = GameData.CONTRACTS[id].reward.Split(':');
                if (rw.Length == 2 && int.TryParse(rw[1], out var amt))
                    resources[rw[0]] = resources.GetValueOrDefault(rw[0], 0) + amt;
            }
        }

        public readonly Dictionary<string, int> resources = new()
            { {"data_fragments",0}, {"code_samples",0}, {"mutagen",0}, {"ghost_tokens",0} };

        readonly System.Random _rng = new();

        // ── Грид ──
        public readonly List<ServerNode> gridNodes = new();
        public readonly List<int> zoneCounts = new();               // серверов на зону
        public readonly Dictionary<string, bool> gridFlags = new(); // двери/рычаги/провода…
        public readonly Dictionary<int, Vector3> blockPositions = new();
        public bool oracleCoreDown = false;
        public float gridHeat = 0f;
        public ServerNode currentNode;
        public bool campaignWon = false;

        // ── состояние взлома (рейда) ──
        public class RaidConfig
        {
            public string name, theme, av, arch;
            public int tier, quota, files, crates, sensitivity, seed;
            public int safes;           // сейфы (вес 3): T2+ — поднимать вдвоём
            public int hot;             // горячие пакеты: греются в руках — эстафета
            public float trapInterval, camRange, creep;
            public int assist;          // вспомогательный взлом: заражённые серверы зоны
            public float assistK;       // их суммарная помощь (0..~0.35)
        }

        // размер стаи (обновляет NetManager): рейды масштабируются под кооп —
        // больше квота/лута/роботов, чаще ловушки, быстрее тревога
        public int packSize = 1;

        public RaidConfig raid;
        public float access, alarm, maxBandwidth = 100f, bandwidth = 100f, bwRegen = 4f;
        public int myHp = 3, myMaxHp = 3;
        public bool myBug, evacOpen, wipeForced;
        public float evacLeft;
        public const float EVAC_TIME = 75f, WIPE_EVAC_TIME = 45f;

        // итоги последнего рейда (для результатов и статистики)
        public int lastDelivered, lastDeposits, lastDunks, lastBestCombo;
        public bool lastRecordLoot, lastRecordCombo;

        // персистентные рекорды кампании (в сейве)
        public readonly Dictionary<string, int> records = new()
            { {"bestLoot",0}, {"bestCombo",0}, {"dunks",0} };

        // ── идентичность штамма ──
        // скин ветки появляется только с УР.1; «сброс до нуля» временно оголяет
        public string DisplayClass() =>
            now < resetUntil ? "base" : (branch != "" && virusLevel >= 1 ? branch : "base");

        public string DisplaySecondary() => virusLevel >= 3 ? secondaryBranch : "";

        public ClassInfo MyClassInfo() => GameData.CLASSES[DisplayClass()];

        public bool HasPassive(string cls)
        {
            if (virusLevel < 1) return false;
            return branch == cls || (virusLevel >= 3 && secondaryBranch == cls);
        }

        // ── дерево эволюции: ветка и уровни ──
        public bool ChooseBranch(string cls)
        {
            if (branch != "" || !GameData.CLASSES.ContainsKey(cls) || cls == "base") return false;
            branch = cls;
            EvolutionChanged?.Invoke();
            return true;
        }

        public bool ChooseSecondary(string cls)
        {
            if (virusLevel < 3 || secondaryBranch != "" || cls == branch ||
                !GameData.CLASSES.ContainsKey(cls) || cls == "base") return false;
            secondaryBranch = cls;
            EvolutionChanged?.Invoke();
            return true;
        }

        public Dictionary<string, int> LevelCost(int lvl) =>
            GameData.LEVELS[Mathf.Clamp(lvl, 0, 3)].cost;

        public bool CanLevelUp()
        {
            if (virusLevel >= 3 || branch == "") return false;   // сперва выбери направленность
            foreach (var kv in LevelCost(virusLevel + 1))
                if (resources.GetValueOrDefault(kv.Key, 0) < kv.Value) return false;
            return true;
        }

        public bool LevelUp()
        {
            if (!CanLevelUp()) return false;
            foreach (var kv in LevelCost(virusLevel + 1)) resources[kv.Key] -= kv.Value;
            virusLevel++;
            if (virusLevel == 1)
            {
                // сигнатурная активка ветки выдаётся бесплатно
                var sig = GameData.BRANCH_ABILITIES[branch][0];
                if (!activeAbilities.Contains(sig)) activeAbilities.Add(sig);
            }
            EvolutionChanged?.Invoke();
            return true;
        }

        // ── активки: слоты, пул, задания ──
        public int MaxAbilitySlots() => new[] { 0, 1, 2, 3 }[Mathf.Clamp(virusLevel, 0, 3)];

        public List<string> AbilityPool()
        {
            // УР.3 с доп. веткой расширяет выбор её умениями
            var pool = new List<string>();
            if (branch == "") return pool;
            pool.AddRange(GameData.BRANCH_ABILITIES[branch]);
            if (DisplaySecondary() != "")
                foreach (var id in GameData.BRANCH_ABILITIES[secondaryBranch])
                    if (!pool.Contains(id)) pool.Add(id);
            return pool;
        }

        public int AbilityDepth(string id)
        {
            // глубина умения в ветке (0 = сигнатурное); для доп. ветки — её глубина
            int d = 99;
            foreach (var cls in new[] { branch, secondaryBranch })
            {
                if (cls == "" || !GameData.BRANCH_ABILITIES.TryGetValue(cls, out var arr)) continue;
                int idx = System.Array.IndexOf(arr, id);
                if (idx >= 0) d = Mathf.Min(d, idx);
            }
            return d;
        }

        public bool AbilityTaskDone(int depth)
        {
            if (depth <= 0) return true;
            if (!GameData.ABILITY_TASKS.TryGetValue(depth, out var t)) return false;
            return career.GetValueOrDefault(t.key, 0) >= t.need;
        }

        public string AbilityTaskProgress(int depth)
        {
            if (depth <= 0 || !GameData.ABILITY_TASKS.TryGetValue(depth, out var t)) return "";
            return $"{t.desc} ({Mathf.Min(career.GetValueOrDefault(t.key, 0), t.need)}/{t.need})";
        }

        public bool CanPickAbility(string id)
        {
            if (activeAbilities.Contains(id) || !AbilityPool().Contains(id)) return false;
            if (activeAbilities.Count >= MaxAbilitySlots()) return false;
            return AbilityTaskDone(AbilityDepth(id));
        }

        public bool PickAbility(string id)
        {
            if (!CanPickAbility(id)) return false;
            activeAbilities.Add(id);
            EvolutionChanged?.Invoke();
            return true;
        }

        // откат: снять умение со слота (вернуть можно в любой момент бесплатно)
        public bool UnequipAbility(string id)
        {
            if (!activeAbilities.Remove(id)) return false;
            EvolutionChanged?.Invoke();
            return true;
        }

        public float AbilityCost(string id) =>
            GameData.ABILITIES[id].cost * (virusLevel >= 3 ? GameData.APEX_COST_MULT : 1f);

        public bool TrySpendBandwidth(float cost)
        {
            if (bandwidth < cost) return false;
            bandwidth -= cost;
            return true;
        }

        // перепрошивка: крадёт умение (глубина 1 — 80%, 2 — 18%, 3 — 2%)
        public string StealAbility()
        {
            if (activeAbilities.Count == 0) return "";
            double r = _rng.NextDouble();
            int idx = r >= 0.98 ? 2 : r >= 0.80 ? 1 : 0;
            idx = Mathf.Min(idx, activeAbilities.Count - 1);
            var id = activeAbilities[idx];
            activeAbilities.RemoveAt(idx);
            stolenAbilities.Add(id);
            EvolutionChanged?.Invoke();
            return id;
        }

        // ── базовые навыки растут с уровнем ──
        public float EvoBonus(string id)
        {
            float lvl = virusLevel;
            return id switch
            {
                "bw"       => lvl * 15f,
                "stealth"  => lvl * 0.08f,
                "vitality" => virusLevel >= 2 ? 1f : 0f,
                "speed"    => lvl * 0.35f,
                "cooldown" => lvl * 0.8f,
                _ => 0f,
            };
        }

        public int EvolveStage() => virusLevel;   // стадия скина = уровень штамма

        public void CareerEvent(string key, int amount = 1)
        {
            career[key] = career.GetValueOrDefault(key, 0) + amount;
            if (key == "tasks") lastTasksRaid += amount;   // контракт «МОНТАЖНИК»
            EvolutionChanged?.Invoke();
        }

        // ── кампания ──
        public void NewCampaign()
        {
            branch = ""; secondaryBranch = ""; virusLevel = 0;
            activeAbilities.Clear();
            stolenAbilities.Clear();
            resetUntil = 0f;
            foreach (var k in new List<string>(career.Keys)) career[k] = 0;
            foreach (var k in new List<string>(records.Keys)) records[k] = 0;
            foreach (var k in new List<string>(resources.Keys)) resources[k] = 0;
            gridFlags.Clear(); blockPositions.Clear();
            gridHeat = 0f; campaignWon = false; oracleCoreDown = false;
            currentNode = null;
            contractsDone.Clear();
            lastContractsDone.Clear();
            foreach (var k in new List<string>(avSeen.Keys)) avSeen[k] = 0;
            avCounter = "";
            GenerateGrid();
            PickContracts();
            EvolutionChanged?.Invoke();
        }

        // сид кампании определяет сиды узлов (арены рейдов); в коопе клиент
        // получает сид хоста в снапшоте — иначе арены одного узла разойдутся
        public int campaignSeed;

        /// Перезасев узлов по чужому сиду БЕЗ пересоздания списка: ссылки на
        /// ServerNode, которые уже держит сцена Грида, остаются живыми.
        public void ReseedCampaign(int seed)
        {
            if (seed == campaignSeed) return;
            campaignSeed = seed;
            var rng = new System.Random(seed);
            foreach (var n in gridNodes)
            {
                n.seed = rng.Next();
                n.arch = GameData.ArchForNode(n.seed, n.zone, n.tier);
            }
            PickContracts();   // доска контрактов тоже от сида — совпадает с хостом
        }

        void GenerateGrid()
        {
            gridNodes.Clear();
            zoneCounts.Clear();
            var counts = new[] { 0, 0, 0, 0 };
            campaignSeed = System.Environment.TickCount;
            var rng = new System.Random(campaignSeed);
            int id = 0;
            foreach (var s in GameData.SERVERS)
            {
                counts[s.zone]++;
                int nodeSeed = rng.Next();
                gridNodes.Add(new ServerNode {
                    id = id, zone = s.zone, tier = s.tier, pos = s.pos, door = s.door, room = s.room,
                    name = $"{GameData.StagePrefix(s.zone)}-{id:D2}",
                    av = GameData.TIERS[s.tier].av, infected = false, failed = false, seed = nodeSeed,
                    arch = GameData.ArchForNode(nodeSeed, s.zone, s.tier),
                });
                id++;
            }
            foreach (var c in counts) zoneCounts.Add(c);
        }

        // ── флаги интерактива ──
        public bool Flag(string key) => gridFlags.TryGetValue(key, out var v) && v;

        public void SetFlag(string key, bool on = true)
        {
            if (Flag(key) == on) return;
            gridFlags[key] = on;
            if (on) SendFlag?.Invoke(key);   // кооп: общий флаг на стаю
        }

        public int CountFlags(string prefix)
        {
            int c = 0;
            foreach (var kv in gridFlags) if (kv.Value && kv.Key.StartsWith(prefix)) c++;
            return c;
        }

        // ── питание этапов ──
        public bool Stage2LiftPowered() =>
            Flag("lever:s2a") && Flag("lever:s2b") && Flag("wire:s2") && Flag("router:s2");

        public bool Stage3Powered() =>
            Flag("gen:g1") && Flag("gen:g2") && Flag("gen:g3") && Flag("lever:s3master");

        public int Stage3GeneratorsOn()
        {
            int c = 0;
            foreach (var g in new[] { "g1", "g2", "g3" }) if (Flag("gen:" + g)) c++;
            return c;
        }

        public bool RedAlert() => ZoneComplete(3);

        // ── Оракул ──
        public int OraclePuzzlesDone()     => CountFlags("opz:");
        public int OracleTerritoriesDone() => CountFlags("oterr:");
        public int OracleRacksDone()       => CountFlags("orack:");

        public bool OracleCoreOpen() =>
            OraclePuzzlesDone() >= GameData.ORACLE_PUZZLES_TOTAL &&
            Flag("wire:or") && Flag("lever:or") &&
            OracleTerritoriesDone() >= GameData.ORACLE_TERRITORIES;

        public bool OracleDataStolen() => OracleRacksDone() >= GameData.ORACLE_RACKS;

        // ── зоны ──
        public int TotalNodes() => gridNodes.Count;

        public int InfectedTotal()
        {
            int c = 0;
            foreach (var n in gridNodes) if (n.infected) c++;
            return c;
        }

        public int ZoneTotal(int z) => (z < 0 || z >= zoneCounts.Count) ? 0 : zoneCounts[z];

        public int ZoneInfected(int z)
        {
            int c = 0;
            foreach (var n in gridNodes) if (n.zone == z && n.infected) c++;
            return c;
        }

        public bool ZoneComplete(int z) => ZoneInfected(z) >= ZoneTotal(z);
        public bool ZoneOpen(int z) => z == 0 || ZoneComplete(z - 1);

        // «боевые» серверы (без обучающей зоны 0) — их 28
        public int FacilityTotal()    => TotalNodes() - ZoneTotal(0);
        public int FacilityInfected() => InfectedTotal() - ZoneInfected(0);

        public bool NodeUnlocked(ServerNode n)
        {
            if (!ZoneOpen(n.zone)) return false;
            return string.IsNullOrEmpty(n.door) || Flag("door:" + n.door);
        }

        public string NodeLockReason(ServerNode n)
        {
            if (!ZoneOpen(n.zone))
                return $"сначала зачистите предыдущий этап ({ZoneInfected(n.zone - 1)}/{ZoneTotal(n.zone - 1)})";
            if (!string.IsNullOrEmpty(n.door) && !Flag("door:" + n.door))
                return "комната заперта — решите головоломку на двери";
            return "";
        }

        // ── взлом узла ──
        public void StartHack(ServerNode n)
        {
            currentNode = n;
            access = 0f;
            alarm = gridHeat * 0.3f;
            // пассивки и эволюция: botnet — BW 150 и двойная регенерация;
            // ransomware — +1 HP; УР.2+ — +1 HP; уровень растит BW
            maxBandwidth = (HasPassive("botnet") ? 150f : 100f) + EvoBonus("bw");
            bandwidth = maxBandwidth;
            bwRegen = HasPassive("botnet") ? 8f : 4f;
            myMaxHp = 3 + (int)EvoBonus("vitality") + (HasPassive("ransomware") ? 1 : 0);
            myHp = myMaxHp; myBug = false;
            evacOpen = false; wipeForced = false; evacLeft = 0f;
            lastDelivered = 0; lastDeposits = 0;
            lastDunks = 0; lastBestCombo = 0;
            lastHits = 0; lastTasksRaid = 0; lastMaxAlarm = alarm;
            lastRecordLoot = false; lastRecordCombo = false;
            _comboCount = 0; _comboUntil = 0f;
            var t = GameData.TIERS[n.tier];
            // вспомогательный взлом: уже взломанные серверы этой зоны помогают —
            // ниже стартовая тревога, реже ловушки. Botnet-оператор удваивает эффект.
            int assist = 0;
            foreach (var g in gridNodes)
                if (g.zone == n.zone && g.infected) assist++;
            float assistK = Mathf.Min(assist * (HasPassive("botnet") ? 0.06f : 0.03f), 0.35f);
            alarm *= 1f - assistK;
            // кооп-скейлинг: на каждого штамма сверх первого — квота +40%,
            // больше лута и роботов, ловушки чаще, тревога живее
            int extra = Math.Max(packSize - 1, 0);
            raid = new RaidConfig {
                name = n.name, tier = n.tier, theme = t.theme, av = n.av,
                arch = n.arch ?? "",
                quota = (int)(t.quota * (1f + 0.4f * extra)),
                files = t.files + extra,
                crates = t.crates + extra / 2,
                safes = n.tier >= 2 ? 1 + extra / 3 : 0,
                hot = n.tier >= 2 ? n.tier - 1 + extra / 4 : 0,
                sensitivity = Math.Min(t.sensitivity + extra / 2, 4),
                trapInterval = t.trapInterval * (1f + assistK) / (1f + 0.15f * extra),
                camRange = t.camRange,
                creep = t.creep * (1f - assistK * 0.5f) * (1f + 0.12f * extra),
                seed = n.seed,
                assist = assist, assistK = assistK,
            };
            // КАРАНТИН лаборатории АВ: ловушек меньше, но датчики зорче и
            // фоновая тревога мягче — весь риск переезжает в стелс
            if (raid.arch == "avlab")
            {
                raid.trapInterval *= 1.7f;
                raid.camRange *= 1.35f;
                raid.creep *= 0.8f;
            }
            // адаптивный АВ: обучение по заезженному приёму (обучение T0 не учится)
            avCounter = "";
            if (n.tier >= 1)
            {
                avCounter = AvPickCounter();
                if (avCounter != "") avSeen[avCounter] = 0;   // выучил — копим заново
            }
        }

        // ── тревога (не падает сама!) и фазы: SLEEP/SCAN/PURGE/WIPE ──
        public int AlarmPhase() => alarm >= 90f ? 3 : alarm >= 55f ? 2 : alarm >= 25f ? 1 : 0;
        public string AlarmPhaseName() => new[] { "SLEEP", "SCAN", "PURGE", "WIPE" }[AlarmPhase()];
        public void ApplyAlarm(float amount) => alarm = Mathf.Clamp(alarm + amount, 0f, 100f);

        // комбо-серия: вносы подряд (окно 20с) множат ценность — стая, не тормози!
        int _comboCount;
        float _comboUntil;
        public int ComboCount => _comboCount;
        public float ComboMult => Mathf.Min(1f + 0.1f * Mathf.Max(_comboCount - 1, 0), 1.5f);

        // лут внесён в портал; возвращает фактически зачтённую ценность (с комбо)
        public float DepositValue(float v)
        {
            _comboCount = now < _comboUntil ? _comboCount + 1 : 1;
            _comboUntil = now + 20f;
            if (_comboCount > lastBestCombo) lastBestCombo = _comboCount;
            float boosted = v * ComboMult;
            access = Mathf.Min(access + boosted / Mathf.Max(raid?.quota ?? 100, 1) * 100f, 999f);
            lastDelivered += (int)boosted;
            lastDeposits++;
            career["deposits"]++;
            career["delivered"] += (int)boosted;
            return boosted;
        }

        public void FinishHack(bool victory)
        {
            if (currentNode == null) return;
            // украденное перепрошивкой возвращается после рейда
            foreach (var id in stolenAbilities)
                if (!activeAbilities.Contains(id) && activeAbilities.Count < 3)
                    activeAbilities.Add(id);
            stolenAbilities.Clear();
            resetUntil = 0f;
            career["raids"]++;   // карьерные счётчики — топливо заданий на активки
            // рекорды кампании: чем хвастаться на экране результатов
            records["dunks"] += lastDunks;
            lastRecordLoot = lastDelivered > records["bestLoot"];
            if (lastRecordLoot) records["bestLoot"] = lastDelivered;
            lastRecordCombo = lastBestCombo > records["bestCombo"];
            if (lastRecordCombo) records["bestCombo"] = lastBestCombo;
            if (victory)
            {
                currentNode.infected = true;
                currentNode.failed = false;
                SendNodeInfected?.Invoke(currentNode.id);   // кооп: стая видит захват
                gridHeat = Mathf.Max(gridHeat - 10f, 0f);
                resources["data_fragments"] += Mathf.Max((int)(lastDelivered * (1.1f + 0.35f * currentNode.tier)), 8);
                if (currentNode.tier >= 2) resources["mutagen"] += 1;
                resources["code_samples"] += currentNode.tier >= 1 ? 1 : 0;
            }
            else
            {
                currentNode.failed = true;
                gridHeat = Mathf.Min(gridHeat + 25f, 100f);
                resources["data_fragments"] += (int)(lastDelivered * 0.4f);
            }
            CheckContracts(victory);   // испытания доски: награда сверху
            EvolutionChanged?.Invoke();
        }

        // ── сохранение кампании: простой текстовый формат key=value ──
        static string F(float v) => v.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture);

        public string Serialize()
        {
            var sb = new System.Text.StringBuilder();
            sb.Append("v=1\n");
            // сид кампании: без него после перезапуска арены рейдов другие
            sb.Append($"seed={campaignSeed}\n");
            // точка возврата: спавн у последнего узла, а не с начала Грида
            sb.Append($"cur={currentNode?.id ?? -1}\n");
            sb.Append($"branch={branch}\n");
            sb.Append($"secondary={secondaryBranch}\n");
            sb.Append($"level={virusLevel}\n");
            sb.Append($"abilities={string.Join(",", activeAbilities)}\n");
            sb.Append($"heat={(int)gridHeat}\n");
            sb.Append($"won={(campaignWon ? 1 : 0)}\n");
            sb.Append($"oracle={(oracleCoreDown ? 1 : 0)}\n");
            foreach (var kv in resources) sb.Append($"res.{kv.Key}={kv.Value}\n");
            foreach (var kv in career) sb.Append($"car.{kv.Key}={kv.Value}\n");
            foreach (var kv in records) sb.Append($"rec.{kv.Key}={kv.Value}\n");
            foreach (var kv in avSeen) sb.Append($"av.{kv.Key}={kv.Value}\n");
            var inf = new List<string>();
            foreach (var n in gridNodes) if (n.infected) inf.Add(n.id.ToString());
            sb.Append($"infected={string.Join(",", inf)}\n");
            var failn = new List<string>();
            foreach (var n in gridNodes) if (n.failed && !n.infected) failn.Add(n.id.ToString());
            sb.Append($"failedn={string.Join(",", failn)}\n");
            var flags = new List<string>();
            foreach (var kv in gridFlags) if (kv.Value) flags.Add(kv.Key);
            sb.Append($"flags={string.Join(",", flags)}\n");
            sb.Append($"cdone={string.Join(",", contractsDone)}\n");
            foreach (var kv in blockPositions)
                sb.Append($"block.{kv.Key}={F(kv.Value.x)};{F(kv.Value.y)};{F(kv.Value.z)}\n");
            return sb.ToString();
        }

        public bool Deserialize(string data)
        {
            if (string.IsNullOrEmpty(data) || !data.StartsWith("v=1")) return false;
            NewCampaign();   // чистая база: узлы/словари, затем накатываем сейв
            foreach (var raw in data.Split('\n'))
            {
                var line = raw.TrimEnd('\r');
                int eq = line.IndexOf('=');
                if (eq <= 0) continue;
                string key = line.Substring(0, eq), val = line.Substring(eq + 1);
                switch (key)
                {
                    case "seed":
                        if (int.TryParse(val, out var seed)) ReseedCampaign(seed);
                        break;
                    case "cur":
                        if (int.TryParse(val, out var cur) && cur >= 0 && cur < gridNodes.Count)
                            currentNode = gridNodes[cur];
                        break;
                    case "branch": branch = val; break;
                    case "secondary": secondaryBranch = val; break;
                    case "level": int.TryParse(val, out virusLevel); break;
                    case "abilities":
                        activeAbilities.Clear();
                        foreach (var a in val.Split(',')) if (a.Length > 0) activeAbilities.Add(a);
                        break;
                    case "heat": if (NetSync.ParseF(val, out var h)) gridHeat = h; break;
                    case "won": campaignWon = val == "1"; break;
                    case "oracle": oracleCoreDown = val == "1"; break;
                    case "infected":
                        foreach (var ids in val.Split(','))
                            if (int.TryParse(ids, out var id) && id >= 0 && id < gridNodes.Count)
                            { gridNodes[id].infected = true; gridNodes[id].failed = false; }
                        break;
                    case "failedn":
                        foreach (var ids in val.Split(','))
                            if (int.TryParse(ids, out var id) && id >= 0 && id < gridNodes.Count && !gridNodes[id].infected)
                                gridNodes[id].failed = true;
                        break;
                    case "flags":
                        foreach (var fl in val.Split(',')) if (fl.Length > 0) gridFlags[fl] = true;
                        break;
                    case "cdone":
                        foreach (var cd in val.Split(',')) if (cd.Length > 0) contractsDone.Add(cd);
                        break;
                    default:
                        if (key.StartsWith("res.") && int.TryParse(val, out var rv))
                            resources[key.Substring(4)] = rv;
                        else if (key.StartsWith("car.") && int.TryParse(val, out var cv))
                            career[key.Substring(4)] = cv;
                        else if (key.StartsWith("rec.") && int.TryParse(val, out var rcv))
                            records[key.Substring(4)] = rcv;
                        else if (key.StartsWith("av.") && int.TryParse(val, out var avv))
                            avSeen[key.Substring(3)] = avv;
                        else if (key.StartsWith("block.") && int.TryParse(key.Substring(6), out var bid))
                        {
                            var p = val.Split(';');
                            if (p.Length == 3 && NetSync.ParseF(p[0], out var bx) &&
                                NetSync.ParseF(p[1], out var by) && NetSync.ParseF(p[2], out var bz))
                                blockPositions[bid] = new Vector3(bx, by, bz);
                        }
                        break;
                }
            }
            EvolutionChanged?.Invoke();
            return true;
        }

        public void Tick(float dt)
        {
            now += dt;
            if (bandwidth < maxBandwidth) bandwidth = Mathf.Min(bandwidth + bwRegen * dt, maxBandwidth);
            if (gridHeat > 0f) gridHeat = Mathf.Max(gridHeat - dt * 1.5f, 0f);
        }
    }
}
