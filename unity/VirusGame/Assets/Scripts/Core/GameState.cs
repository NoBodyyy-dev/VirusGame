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
        public bool infected, failed;
    }

    // Порт game_state.gd: кампания, зоны Грида, флаги интерактива, экономика,
    // конфиг рейда. Чистая логика — без прямых вызовов движка (только Vector3/
    // Color/Mathf). Сетевые хуки вынесены в делегаты (см. Net-порт).
    public class GameState
    {
        public static GameState I { get; private set; } = new GameState();

        // Хуки для коопа (в одиночке null). SendFlag рассылает выставленный флаг.
        public Action<string> SendFlag;

        public event Action EvolutionChanged;

        // ── прогрессия ──
        public string branch = "";
        public string secondaryBranch = "";
        public int virusLevel = 0;
        public readonly List<string> activeAbilities = new();

        public readonly Dictionary<string, int> resources = new()
            { {"data_fragments",0}, {"code_samples",0}, {"mutagen",0}, {"ghost_tokens",0} };

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
            public string name, theme, av;
            public int tier, quota, files, crates, sensitivity, seed;
            public float trapInterval, camRange, creep;
        }

        public RaidConfig raid;
        public float access, alarm, maxBandwidth = 100f, bandwidth = 100f, bwRegen = 4f;
        public int myHp = 3, myMaxHp = 3;
        public bool myBug, evacOpen, wipeForced;
        public float evacLeft;
        public const float EVAC_TIME = 75f, WIPE_EVAC_TIME = 45f;

        // итоги последнего рейда (для результатов и статистики)
        public int lastDelivered, lastDeposits;

        // ── кампания ──
        public void NewCampaign()
        {
            branch = ""; secondaryBranch = ""; virusLevel = 0;
            activeAbilities.Clear();
            foreach (var k in new List<string>(resources.Keys)) resources[k] = 0;
            gridFlags.Clear(); blockPositions.Clear();
            gridHeat = 0f; campaignWon = false; oracleCoreDown = false;
            currentNode = null;
            GenerateGrid();
            EvolutionChanged?.Invoke();
        }

        void GenerateGrid()
        {
            gridNodes.Clear();
            zoneCounts.Clear();
            var counts = new[] { 0, 0, 0, 0 };
            var rng = new System.Random();
            int id = 0;
            foreach (var s in GameData.SERVERS)
            {
                counts[s.zone]++;
                gridNodes.Add(new ServerNode {
                    id = id, zone = s.zone, tier = s.tier, pos = s.pos, door = s.door, room = s.room,
                    name = $"{GameData.StagePrefix(s.zone)}-{id:D2}",
                    av = GameData.TIERS[s.tier].av, infected = false, failed = false, seed = rng.Next(),
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
            maxBandwidth = 100f; bandwidth = maxBandwidth; bwRegen = 4f;
            myMaxHp = 3; myHp = myMaxHp; myBug = false;
            evacOpen = false; wipeForced = false; evacLeft = 0f;
            lastDelivered = 0; lastDeposits = 0;
            var t = GameData.TIERS[n.tier];
            raid = new RaidConfig {
                name = n.name, tier = n.tier, theme = t.theme, av = n.av,
                quota = t.quota, files = t.files, crates = t.crates,
                sensitivity = t.sensitivity, trapInterval = t.trapInterval,
                camRange = t.camRange, creep = t.creep, seed = n.seed,
            };
        }

        // ── тревога (не падает сама!) и фазы: SLEEP/SCAN/PURGE/WIPE ──
        public int AlarmPhase() => alarm >= 90f ? 3 : alarm >= 55f ? 2 : alarm >= 25f ? 1 : 0;
        public string AlarmPhaseName() => new[] { "SLEEP", "SCAN", "PURGE", "WIPE" }[AlarmPhase()];
        public void ApplyAlarm(float amount) => alarm = Mathf.Clamp(alarm + amount, 0f, 100f);

        // лут внесён в портал
        public void DepositValue(float v)
        {
            access = Mathf.Min(access + v / Mathf.Max(raid?.quota ?? 100, 1) * 100f, 999f);
            lastDelivered += (int)v;
            lastDeposits++;
        }

        public void FinishHack(bool victory)
        {
            if (currentNode == null) return;
            if (victory)
            {
                currentNode.infected = true;
                currentNode.failed = false;
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
            EvolutionChanged?.Invoke();
        }

        public void Tick(float dt)
        {
            if (bandwidth < maxBandwidth) bandwidth = Mathf.Min(bandwidth + bwRegen * dt, maxBandwidth);
            if (gridHeat > 0f) gridHeat = Mathf.Max(gridHeat - dt * 1.5f, 0f);
        }
    }
}
