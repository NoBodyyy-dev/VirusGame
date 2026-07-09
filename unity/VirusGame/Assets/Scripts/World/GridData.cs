using UnityEngine;

namespace Virus.World
{
    // Порт констант интерактива grid_world.gd: туннели, двери-головоломки,
    // блоки, пилоны/территории/стойки Оракула, лазеры, падающие потолки.
    public static class GridData
    {
        public struct TunnelDoor { public float z; public string key; public int diff; public string opz;
            public TunnelDoor(float z, string key, int diff, string opz) { this.z = z; this.key = key; this.diff = diff; this.opz = opz; } }

        public struct Tunnel { public string key; public float x0, x1, zs, zn; public int gateZone; public string to; public TunnelDoor[] doors;
            public Tunnel(string key, float x0, float x1, float zs, float zn, int gateZone, string to, TunnelDoor[] doors)
            { this.key = key; this.x0 = x0; this.x1 = x1; this.zs = zs; this.zn = zn; this.gateZone = gateZone; this.to = to; this.doors = doors; } }

        public static readonly Tunnel[] TUNNELS =
        {
            new("t12", 45, 51, -56, -78, 1, "КО 2 УРОВНЮ", new[] { new TunnelDoor(-67, "d_t12", 2, "") }),
            new("t23", 95, 101, -152, -176, 2, "К 3 УРОВНЮ", new[] {
                new TunnelDoor(-161, "d_t23a", 2, ""), new TunnelDoor(-169, "d_t23b", 3, "") }),
            new("t3o", 119, 125, -264, -290, 3, "К ОРАКУЛУ", new[] {
                new TunnelDoor(-272, "d_t3oa", 3, "opz:1"),
                new TunnelDoor(-279, "d_t3ob", 4, "opz:2"),
                new TunnelDoor(-286, "d_t3oc", 4, "opz:3") }),
        };

        public struct DoorDef { public string key, room, side; public float c, w; public int diff; public bool power; public string opz;
            public DoorDef(string key, string room, string side, float c, float w, int diff, bool power, string opz)
            { this.key = key; this.room = room; this.side = side; this.c = c; this.w = w; this.diff = diff; this.power = power; this.opz = opz; } }

        public static readonly DoorDef[] PUZZLE_DOORS =
        {
            new("d_s1a", "s1a", "e", -26, 3.4f, 1, false, ""),
            new("d_s1b", "s1b", "n", 36, 3.4f, 1, false, ""),
            new("d_srv2a", "srv2a", "s", 36, 4, 2, false, ""),
            new("d_srv2b", "srv2b", "n", 106, 4, 2, false, ""),
            new("d_s2a", "s2a", "e", -94, 3.4f, 2, false, ""),
            new("d_s2b", "s2b", "w", -129, 3.4f, 2, false, ""),
            new("d_srv3a", "srv3a", "e", -198, 4, 3, true, ""),
            new("d_srv3b", "srv3b", "w", -212, 4, 3, true, ""),
            new("d_srv3c", "srv3c", "n", 76, 4, 3, true, ""),
            new("d_s3a", "s3a", "s", 110, 3.4f, 3, true, ""),
        };

        public struct BlockDef { public int id, weight; public Vector3 pos;
            public BlockDef(int id, Vector3 pos, int weight) { this.id = id; this.pos = pos; this.weight = weight; } }

        public static readonly BlockDef[] BLOCKS =
        {
            new(5, new Vector3(10, 0.75f, 13), 1),      // обучение, урок 3
            new(0, new Vector3(18, 0.75f, -30), 1),
            new(1, new Vector3(24, 0.75f, -44), 1),
            new(2, new Vector3(30, 0.75f, -52), 1),
            new(3, new Vector3(46, 0.75f, -34), 2),
            new(4, new Vector3(52, 0.75f, -50), 2),
        };

        public struct Pylon { public string key; public Vector3 pos; public int diff;
            public Pylon(string key, Vector3 pos, int diff) { this.key = key; this.pos = pos; this.diff = diff; } }

        public static readonly Pylon[] ORACLE_PYLONS =
        {
            new("opz:4", new Vector3(84, 0, -300), 3),  new("opz:5", new Vector3(160, 0, -298), 3),
            new("opz:6", new Vector3(168, 0, -322), 3), new("opz:7", new Vector3(80, 0, -330), 3),
            new("opz:8", new Vector3(94, 0, -356), 4),  new("opz:9", new Vector3(160, 0, -352), 4),
            new("opz:10", new Vector3(110, 0, -306), 3),new("opz:11", new Vector3(140, 0, -372), 4),
            new("opz:12", new Vector3(172, 0, -374), 4),new("opz:13", new Vector3(76, 0, -372), 4),
            new("opz:14", new Vector3(106, 0, -338), 5),new("opz:15", new Vector3(144, 0, -318), 5),
        };

        public static readonly (string key, Vector3 pos)[] ORACLE_TERRS =
        {
            ("oterr:1", new Vector3(94, 0, -312)),
            ("oterr:2", new Vector3(154, 0, -316)),
            ("oterr:3", new Vector3(124, 0, -366)),
        };

        public static readonly (string key, Vector3 pos)[] ORACLE_RACKS =
        {
            ("orack:1", new Vector3(112, 0, -326)), ("orack:2", new Vector3(136, 0, -326)),
            ("orack:3", new Vector3(112, 0, -350)), ("orack:4", new Vector3(136, 0, -350)),
        };

        public static readonly Vector3 ORACLE_CORE = new(124, 0, -338);
        public static readonly Vector3 ORACLE_ENTRY = new(122, 1.2f, -293);
        public static readonly Vector3 STAGE2_ENTRY = new(48, 1.2f, -81);
        public static readonly Vector3 STAGE3_ENTRY = new(98, 1.2f, -179);

        public static readonly Vector3[] BOT_SPAWNS =
        {
            new(76, 0, -296), new(172, 0, -296), new(76, 0, -380), new(172, 0, -380),
            new(124, 0, -300), new(80, 0, -338), new(170, 0, -338), new(124, 0, -378),
            new(100, 0, -320), new(148, 0, -358),
        };

        public struct Beam { public Vector3 a, b; public float phase;
            public Beam(Vector3 a, Vector3 b, float phase) { this.a = a; this.b = b; this.phase = phase; } }

        public static readonly Beam[] TRAP_BEAMS =
        {
            new(new Vector3(120, 0.6f, -210), new Vector3(152, 0.6f, -210), 0.0f),
            new(new Vector3(120, 0.6f, -218), new Vector3(152, 0.6f, -218), 1.5f),
            new(new Vector3(100, 0.6f, -238), new Vector3(144, 0.6f, -238), 0.7f),
            new(new Vector3(100, 0.6f, -244), new Vector3(144, 0.6f, -244), 2.2f),
            new(new Vector3(60, 0.6f, -238), new Vector3(96, 0.6f, -238), 1.1f),
            new(new Vector3(60, 0.6f, -246), new Vector3(96, 0.6f, -246), 2.8f),
        };

        public static readonly (Vector3 pos, string room)[] CEIL_TRAPS =
        {
            (new Vector3(40, 0, -96), "c2"), (new Vector3(56, 0, -110), "c2"),
            (new Vector3(86, 0, -116), "d2"), (new Vector3(100, 0, -136), "d2"),
            (new Vector3(118, 0, -126), "d2"),
        };

        public static readonly Vector3[] MOTES =
        {
            new(-15, 1.2f, -24), new(-13, 1.2f, -28), new(36, 1.2f, -18), new(34, 1.2f, -22),
            new(18, 1.2f, -92), new(16, 1.2f, -96), new(132, 1.2f, -127), new(130, 1.2f, -131),
            new(110, 1.2f, -268), new(112, 1.2f, -272),
            new(20, 1.2f, -40), new(50, 1.2f, -90), new(90, 1.2f, -130),
            new(100, 1.2f, -190), new(120, 1.2f, -240), new(150, 1.2f, -330),
        };
    }
}
