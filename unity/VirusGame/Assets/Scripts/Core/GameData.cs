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

    // ── дерево эволюции: классы, умения, уровни (порт game_state.gd) ──
    public class ClassInfo
    {
        public string name, role, passive, active;
        public Color color;
        public int cost, str, dex, intel;
    }

    public class AbilityInfo
    {
        public string name, desc;
        public int cost;
    }

    public class AbilityTask
    {
        public string desc, key;
        public int need;
    }

    public class LevelInfo
    {
        public string title, perks;
        public Dictionary<string, int> cost;
    }

    public class TrapInfo
    {
        public string name;
        public int tier;
        public float speed, life;
        public Color color;
    }

    // архетип сервера: уникальное ПРАВИЛО узла (не числа!) — лечит «все рейды
    // одинаковые». Назначается детерминированно от сида узла: в коопе совпадает.
    public class ArchetypeInfo
    {
        public string name, twist;   // имя для Грида и твист-подсказка для рейда
        public Color color;
        public int minTier;          // с какого тира встречается
    }

    public static class GameData
    {
        // ── классы: "base" — общий старт, остальные — ветки дерева ──
        public static readonly Dictionary<string, ClassInfo> CLASSES = new()
        {
            ["base"] = new ClassInfo { name = "ПРОТО-ШТАММ", role = "Болванка без специализации",
                color = new Color(0.604f, 0.722f, 0.784f), cost = 0, str = 4, dex = 4, intel = 4,
                passive = "Все начинают одинаково. Ветку развития выбирают в дереве эволюции [Tab]",
                active = "—" },
            ["trojan"] = new ClassInfo { name = "ТРОЯН", role = "Мимик / диверсант",
                color = new Color(0.208f, 0.878f, 1f), cost = 20, str = 4, dex = 7, intel = 9,
                passive = "Мимикрия: активка превращает его в ящик — роботы его не видят, пока он не двинется",
                active = "Ложный файл — стать ящиком (до первого движения)" },
            ["worm"] = new ClassInfo { name = "ЧЕРВЬ", role = "Спринтер / курьер",
                color = new Color(0.220f, 0.941f, 0.659f), cost = 15, str = 3, dex = 10, intel = 5,
                passive = "Самый быстрый штамм; штраф от груза меньше",
                active = "Рывок — бросок вперёд (работает даже с грузом)" },
            ["ransomware"] = new ClassInfo { name = "RANSOMWARE", role = "Силач / танк",
                color = new Color(1f, 0.239f, 0.431f), cost = 35, str = 10, dex = 3, intel = 6,
                passive = "Тяжёлый лут тащит В ОДИНОЧКУ; +1 HP",
                active = "Шифрование — заморозка всех ловушек и робота на 3с" },
            ["spyware"] = new ClassInfo { name = "SPYWARE", role = "Разведчик / глаза",
                color = new Color(1f, 0.706f, 0.329f), cost = 20, str = 3, dex = 6, intel = 10,
                passive = "Видит радиусы обзора роботов-охранников и полную сводку системы",
                active = "Скан — лут и угрозы видны сквозь стены (6с) всем" },
            ["adware"] = new ClassInfo { name = "ADWARE", role = "Дезинформация",
                color = new Color(0.659f, 0.847f, 0.310f), cost = 25, str = 4, dex = 6, intel = 8,
                passive = "Ловушки иногда ведутся на его фантомный след и промахиваются",
                active = "Фантом — приманка уводит ловушки (5с)" },
            ["rootkit"] = new ClassInfo { name = "ROOTKIT", role = "Тихоня / сапёр",
                color = new Color(0.545f, 0.361f, 1f), cost = 30, str = 5, dex = 8, intel = 7,
                passive = "Бесшумный: его бег, прыжки и броски не поднимают тревогу",
                active = "Глушилка — тревога −12" },
            ["botnet"] = new ClassInfo { name = "BOTNET", role = "Оператор роя / медик",
                color = new Color(0.290f, 0.565f, 1f), cost = 40, str = 6, dex = 4, intel = 9,
                passive = "Bandwidth 150, двойная регенерация. Настраивает ВСПОМОГАТЕЛЬНЫЙ ВЗЛОМ: взломанные серверы зоны помогают вдвое сильнее",
                active = "Дефибрилляция — оживить «бага» рядом (или +1 HP себе)" },
        };

        // ── активные умения (общий пул) ──
        public static readonly Dictionary<string, AbilityInfo> ABILITIES = new()
        {
            ["dash"]   = new AbilityInfo { name = "РЫВОК", desc = "бросок вперёд (работает даже с грузом)", cost = 15 },
            ["morph"]  = new AbilityInfo { name = "ЛОЖНЫЙ ФАЙЛ", desc = "стать ящиком — роботы слепы, пока не двинешься", cost = 20 },
            ["freeze"] = new AbilityInfo { name = "ШИФРОВАНИЕ", desc = "заморозка системы, ловушек и роботов на 3с", cost = 35 },
            ["xray"]   = new AbilityInfo { name = "СКАН", desc = "лут и угрозы видны сквозь стены (6с) всем", cost = 20 },
            ["decoy"]  = new AbilityInfo { name = "ФАНТОМ", desc = "приманка уводит ловушки (5с)", cost = 25 },
            ["jam"]    = new AbilityInfo { name = "ГЛУШИЛКА", desc = "тревога −12", cost = 30 },
            ["heal"]   = new AbilityInfo { name = "ДЕФИБРИЛЛЯЦИЯ", desc = "оживить бага рядом (или +1 HP себе)", cost = 40 },
            ["haste"]  = new AbilityInfo { name = "СВЕРХТАКТ", desc = "разгон себя +45% скорости на 5с", cost = 20 },
            ["emp"]    = new AbilityInfo { name = "ЭМИ-РАЗРЯД", desc = "оглушить ближайшего робота на 4с", cost = 25 },
            ["cloak"]  = new AbilityInfo { name = "СТЕЛС-ПАКЕТ", desc = "невидим для роботов 4с (движение не выдаёт)", cost = 30 },
            ["purge"]  = new AbilityInfo { name = "ЧИСТКА", desc = "сжечь ВСЕ летящие ловушки системы", cost = 30 },
        };

        // ветка = 5 умений: сигнатурное на УР.1, дальше — по карьерным заданиям.
        // полный набор открывается примерно к началу зоны T3
        public static readonly Dictionary<string, string[]> BRANCH_ABILITIES = new()
        {
            ["trojan"]     = new[] { "morph", "cloak", "decoy", "xray", "purge" },
            ["worm"]       = new[] { "dash", "haste", "decoy", "jam", "purge" },
            ["ransomware"] = new[] { "freeze", "emp", "heal", "jam", "haste" },
            ["spyware"]    = new[] { "xray", "jam", "cloak", "decoy", "emp" },
            ["adware"]     = new[] { "decoy", "morph", "freeze", "haste", "purge" },
            ["rootkit"]    = new[] { "jam", "cloak", "morph", "xray", "emp" },
            ["botnet"]     = new[] { "heal", "purge", "freeze", "dash", "emp" },
        };

        // разблокировка умений по ГЛУБИНЕ в ветке (карьерные счётчики);
        // глубина 0 — сигнатурное, даётся с УР.1
        public static readonly Dictionary<int, AbilityTask> ABILITY_TASKS = new()
        {
            [1] = new AbilityTask { desc = "внеси 6 предметов в портал", key = "deposits", need = 6 },
            [2] = new AbilityTask { desc = "выполни 4 полевые задачи", key = "tasks", need = 4 },
            [3] = new AbilityTask { desc = "переживи 8 рейдов", key = "raids", need = 8 },
            [4] = new AbilityTask { desc = "вынеси добычи на ◈350 суммарно", key = "delivered", need = 350 },
        };

        // ── уровни развития штамма 0..3 ──
        public static readonly LevelInfo[] LEVELS =
        {
            new LevelInfo { title = "УР.0 · ПРОТО", cost = new Dictionary<string, int>(),
                perks = "базовые навыки: бег, прыжок, переноска" },
            new LevelInfo { title = "УР.1 · СПЕЦИАЛИЗАЦИЯ", cost = new Dictionary<string, int> { ["data_fragments"] = 60 },
                perks = "скин ветки · пассивка · 1-я активка · +навыки" },
            new LevelInfo { title = "УР.2 · МУТАЦИЯ", cost = new Dictionary<string, int> { ["data_fragments"] = 150, ["code_samples"] = 1 },
                perks = "+1 HP · до 2 активок (за задания) · продвинутый скин" },
            new LevelInfo { title = "УР.3 · АПЕКС", cost = new Dictionary<string, int> { ["data_fragments"] = 280, ["code_samples"] = 2, ["mutagen"] = 1 },
                perks = "3 активки · доп. ветка · финальный скин · расход BW ×1.5" },
        };

        public const float APEX_COST_MULT = 1.5f;   // УР.3: навыки мощнее — «мана» дороже

        // ── ловушки системы (вылетают из стен) ──
        public static readonly Dictionary<string, TrapInfo> TRAPS = new()
        {
            ["laser"]   = new TrapInfo { name = "ТОЧЕЧНЫЙ ЛАЗЕР", tier = 0, speed = 8.5f, life = 12f, color = new Color(1f, 0.25f, 0.3f) },
            ["cage"]    = new TrapInfo { name = "КЛЕТКА", tier = 1, speed = 6f, life = 10f, color = new Color(0.5f, 0.75f, 1f) },
            ["reset"]   = new TrapInfo { name = "СБРОС ДО НУЛЯ", tier = 1, speed = 6.5f, life = 10f, color = new Color(0.7f, 0.7f, 0.75f) },
            ["pull"]    = new TrapInfo { name = "ПРИТЯЖЕНИЕ", tier = 1, speed = 7f, life = 10f, color = new Color(0.9f, 0.5f, 1f) },
            ["mark"]    = new TrapInfo { name = "МЕТКА", tier = 2, speed = 7f, life = 10f, color = new Color(1f, 0.85f, 0.3f) },
            ["reflash"] = new TrapInfo { name = "ПАТРОН С ПЕРЕПРОШИВКОЙ", tier = 3, speed = 5.5f, life = 14f, color = new Color(0.3f, 1f, 0.6f) },
        };

        // ── архетипы серверов: у каждого узла своё правило игры ──
        public static readonly Dictionary<string, ArchetypeInfo> ARCHETYPES = new()
        {
            ["mail"] = new ArchetypeInfo { name = "ПОЧТОВЫЙ УЗЕЛ", minTier = 0,
                color = new Color(0.95f, 0.85f, 0.4f),
                twist = "СПАМ-ШТОРМ: среди лута фальшивки — цену не видно, присмотрись к глитч-мерцанию" },
            ["game"] = new ArchetypeInfo { name = "ИГРОВОЙ СЕРВЕР", minTier = 0,
                color = new Color(0.5f, 0.9f, 1f),
                twist = "ЧИТ-ГРАВИТАЦИЯ: прыжки выше, лучший лут на парящих платформах" },
            ["dark"] = new ArchetypeInfo { name = "УЗЕЛ УМНОГО ДОМА", minTier = 0,
                color = new Color(0.55f, 0.5f, 1f),
                twist = "СВЕТ ГАСНЕТ: периодические отключения — запоминай зал, пока светло" },
            ["proxy"] = new ArchetypeInfo { name = "ЗЕРКАЛЬНЫЙ ПРОКСИ", minTier = 1,
                color = new Color(0.4f, 1f, 0.8f),
                twist = "ПОРТ МИГРИРУЕТ: зона выноса периодически переезжает через зал" },
            ["scan"] = new ArchetypeInfo { name = "АРХИВНЫЙ МАССИВ", minTier = 1,
                color = new Color(1f, 0.6f, 0.3f),
                twist = "ПРОВЕРКА ЦЕЛОСТНОСТИ: во время скана ЗАМРИ или замаскируйся" },
            ["bank"] = new ArchetypeInfo { name = "ПЛАТЁЖНЫЙ ШЛЮЗ", minTier = 2,
                color = new Color(1f, 0.35f, 0.4f),
                twist = "ЛАЗЕРНАЯ ГРЕБЁНКА: лучи ходят по залу — перепрыгивай или страдай" },
            ["avlab"] = new ArchetypeInfo { name = "ЛАБОРАТОРИЯ АНТИВИРУСА", minTier = 2,
                color = new Color(0.8f, 0.4f, 1f),
                twist = "КАРАНТИН: датчики зорче, глушение недоступно — чистый стелс" },
        };

        // архетип узла из его сида: детерминированно (кооп/сейв дают то же),
        // зона 0 — обучение без сюрпризов, ~четверть узлов «чистые»
        public static string ArchForNode(int seed, int zone, int tier)
        {
            if (zone == 0) return "";
            var pool = new List<string>();
            foreach (var kv in ARCHETYPES)
                if (tier >= kv.Value.minTier) pool.Add(kv.Key);
            pool.Sort(System.StringComparer.Ordinal);   // порядок словаря не гарантирован
            uint h = (uint)seed;
            if (h % 4 == 0) return "";
            return pool[(int)(h / 4 % (uint)pool.Count)];
        }

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
