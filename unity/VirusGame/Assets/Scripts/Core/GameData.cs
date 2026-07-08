using System.Collections.Generic;
using UnityEngine;

namespace Virus.Core
{
    // Порт констант/таблиц из game_state.gd (Godot).
    // Движко-независимые данные правил — только Vector3/Color из UnityEngine.
    public struct Room
    {
        public int stage;
        public float x0, x1, zs, zn, h;
        public bool secret;
        public Room(int stage, float x0, float x1, float zs, float zn, float h, bool secret = false)
        { this.stage = stage; this.x0 = x0; this.x1 = x1; this.zs = zs; this.zn = zn; this.h = h; this.secret = secret; }
        public float Cx => (x0 + x1) * 0.5f;
        public float Cz => (zs + zn) * 0.5f;
        public float W  => x1 - x0;
        public float D  => zs - zn;
    }

    public struct ServerDef
    {
        public int zone, tier;
        public Vector3 pos;
        public string door, room;
        public ServerDef(int zone, int tier, Vector3 pos, string door, string room)
        { this.zone = zone; this.tier = tier; this.pos = pos; this.door = door; this.room = room; }
    }

    public class Tier
    {
        public string name, shortName, av, theme;
        public int quota, files, crates, tasks, sensitivity;
        public float creep, trapInterval, camRange;
        public string[] traps;
    }

    public static class GameData
    {
        // ── тиры узлов (T0 обучающий → T3 военные) ──
        public static readonly Tier[] TIERS =
        {
            new Tier { name="Незащищённые ПК", shortName="T0", av="WATCHDOG-LITE", theme="home",
                quota=40, creep=0.06f, files=6, crates=1, tasks=1, sensitivity=1,
                trapInterval=18f, camRange=10f, traps=new[]{"laser"} },
            new Tier { name="Защищённые ПК и лавки", shortName="T1", av="BEHAVIORAL", theme="office",
                quota=70, creep=0.22f, files=8, crates=2, tasks=2, sensitivity=2,
                trapInterval=12f, camRange=13f, traps=new[]{"laser","cage","reset","pull"} },
            new Tier { name="Дата-центры", shortName="T2", av="SANDBOX", theme="dc",
                quota=95, creep=0.30f, files=9, crates=3, tasks=2, sensitivity=3,
                trapInterval=9f, camRange=15f, traps=new[]{"laser","cage","reset","pull","mark"} },
            new Tier { name="Военные сети", shortName="T3", av="AIR-GAPPED", theme="bank",
                quota=115, creep=0.38f, files=10, crates=4, tasks=3, sensitivity=4,
                trapInterval=7f, camRange=17f, traps=new[]{"laser","cage","reset","pull","mark","reflash"} },
        };

        public static readonly string[] BRANCHES =
            { "trojan", "worm", "ransomware", "spyware", "adware", "rootkit", "botnet" };

        // ── карта Грида: комнаты (север = -Z) ──
        public static readonly Dictionary<string, Room> ROOMS = new()
        {
            { "r0",    new Room(0, -24, 24, 40, -6, 9) },            // обучающий ангар
            { "a1",    new Room(1, -9, 9, -8, -44, 9) },
            { "b1",    new Room(1, 9, 55, -26, -56, 9) },
            { "s1a",   new Room(1, -21, -9, -20, -32, 5, true) },
            { "s1b",   new Room(1, 30, 42, -14, -26, 5, true) },
            { "c2",    new Room(2, 24, 70, -78, -116, 10) },
            { "d2",    new Room(2, 70, 126, -108, -152, 12) },
            { "s2a",   new Room(2, 12, 24, -88, -100, 5, true) },
            { "s2b",   new Room(2, 126, 138, -124, -136, 5, true) },
            { "srv2a", new Room(2, 30, 42, -116, -128, 6) },
            { "srv2b", new Room(2, 100, 112, -96, -108, 6) },
            { "e1",    new Room(3, 74, 118, -176, -212, 10) },
            { "e2",    new Room(3, 118, 154, -196, -226, 9) },
            { "e3",    new Room(3, 98, 146, -226, -264, 11) },
            { "e4",    new Room(3, 58, 98, -234, -260, 9) },
            { "srv3a", new Room(3, 62, 74, -192, -204, 6) },
            { "srv3b", new Room(3, 154, 166, -206, -218, 6) },
            { "srv3c", new Room(3, 70, 82, -222, -234, 6) },
            { "s3a",   new Room(3, 104, 116, -264, -276, 6, true) },
            { "or",    new Room(4, 70, 178, -290, -386, 22) },
        };

        // ── серверы: зона 0=обучение,1=город,2=офисы,3=бункер ──
        public static readonly ServerDef[] SERVERS =
        {
            new(0, 0, new Vector3(0, 0, 16),   "",        "r0"),
            new(0, 0, new Vector3(-16, 0, 0),  "d_tut",   "r0"),
            new(0, 0, new Vector3(14, 2.6f, 8),"",        "r0"),
            new(1, 0, new Vector3(40, 4.5f, -46), "",     "b1"),
            new(2, 1, new Vector3(34, 0, -90),  "",        "c2"),
            new(2, 1, new Vector3(58, 0, -104), "",        "c2"),
            new(2, 1, new Vector3(36, 0, -122), "d_srv2a", "srv2a"),
            new(2, 1, new Vector3(84, 0, -124), "",        "d2"),
            new(2, 1, new Vector3(112, 0, -144),"",        "d2"),
            new(2, 1, new Vector3(106, 0, -102),"d_srv2b", "srv2b"),
            new(2, 2, new Vector3(74, 6f, -136), "",       "d2"),
            new(2, 2, new Vector3(108, 6f, -148),"",       "d2"),
            new(3, 2, new Vector3(80, 0, -184), "",        "e1"),
            new(3, 2, new Vector3(92, 0, -206), "",        "e1"),
            new(3, 2, new Vector3(110, 0, -182),"",        "e1"),
            new(3, 3, new Vector3(68, 0, -198), "d_srv3a", "srv3a"),
            new(3, 2, new Vector3(126, 0, -202),"",        "e2"),
            new(3, 2, new Vector3(146, 0, -220),"",        "e2"),
            new(3, 2, new Vector3(124, 0, -220),"",        "e2"),
            new(3, 3, new Vector3(160, 0, -212),"d_srv3b", "srv3b"),
            new(3, 2, new Vector3(104, 0, -232),"",        "e3"),
            new(3, 2, new Vector3(140, 0, -232),"",        "e3"),
            new(3, 2, new Vector3(102, 0, -258),"",        "e3"),
            new(3, 3, new Vector3(124, 0, -246),"",        "e3"),
            new(3, 2, new Vector3(130, 0, -256),"",        "e3"),
            new(3, 3, new Vector3(118, 6f, -261),"",       "e3"),
            new(3, 3, new Vector3(136, 6f, -261),"",       "e3"),
            new(3, 2, new Vector3(66, 0, -240), "",        "e4"),
            new(3, 2, new Vector3(88, 0, -254), "",        "e4"),
            new(3, 3, new Vector3(64, 0, -256), "",        "e4"),
            new(3, 3, new Vector3(76, 0, -228), "d_srv3c", "srv3c"),
        };

        public const int ORACLE_PUZZLES_TOTAL = 15;
        public const int ORACLE_TERRITORIES  = 3;
        public const int ORACLE_RACKS        = 4;

        public static readonly Color[] TIER_COLORS =
        {
            new Color(0.208f,0.878f,1f), new Color(1f,0.706f,0.329f),
            new Color(1f,0.365f,0.561f), new Color(0.545f,0.361f,1f),
        };
        public static readonly Color INFECTED = new(0.184f,0.902f,0.690f);
        public static readonly Color ORACLE   = new(1f,0.176f,0.290f);

        public static string StagePrefix(int zone) =>
            new[] { "TUT", "CITY", "OFC", "BNK" }[Mathf.Clamp(zone, 0, 3)];
    }
}
