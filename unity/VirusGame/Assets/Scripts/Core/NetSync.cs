using System.Collections.Generic;
using System.Text;

namespace Virus.Core
{
    // Кооп-протокол (редизайн net.gd): хост владеет состоянием кампании.
    // Текстовые сообщения «TYPE|поле|поле…\n» поверх TCP — просто и отлаживаемо.
    // Здесь только чистая логика: сборка/разбор сообщений, фрейминг байтового
    // потока и применение к GameState. Транспорт — в Net/NetManager (Unity).
    public static class NetSync
    {
        public const int Port = 47777;

        static string Clean(string s) => (s ?? "").Replace("|", "/").Replace("\n", " ");

        // числа — только в инвариантной культуре: русская локаль пишет «1,5»
        static string F(float v) => v.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture);

        public static bool ParseF(string s, out float v) =>
            float.TryParse(s, System.Globalization.NumberStyles.Float,
                System.Globalization.CultureInfo.InvariantCulture, out v);

        // ── сборка сообщений ──
        public static string MsgHello(string name, string cls, int lvl, string sec) =>
            $"HI|{Clean(name)}|{Clean(cls)}|{lvl}|{Clean(sec)}";

        public static string MsgId(int id) => $"ID|{id}";

        // снапшот кампании: флаги, заражённые узлы, жар Грида
        public static string MsgSnapshot(GameState s)
        {
            var flags = new List<string>();
            foreach (var kv in s.gridFlags) if (kv.Value) flags.Add(kv.Key);
            var infected = new List<string>();
            foreach (var n in s.gridNodes) if (n.infected) infected.Add(n.id.ToString());
            return $"SNAP|{string.Join(",", flags)}|{string.Join(",", infected)}|{(int)s.gridHeat}";
        }

        public static string MsgFlag(string key) => $"FLAG|{Clean(key)}";
        public static string MsgNode(int id) => $"NODE|{id}";

        // позиция: сцена — "grid", "raid:<node>", "victory", "menu"
        public static string MsgPos(int id, string scene, float x, float y, float z, float ry) =>
            $"POS|{id}|{Clean(scene)}|{F(x)}|{F(y)}|{F(z)}|{F(ry)}";

        public static string MsgIdentity(int id, string name, string cls, int stage, string sec) =>
            $"IDY|{id}|{Clean(name)}|{Clean(cls)}|{stage}|{Clean(sec)}";

        public static string MsgToast(string text) => $"MSG|{Clean(text)}";
        public static string MsgBye(int id) => $"BYE|{id}";

        public static string[] Parse(string line) => (line ?? "").TrimEnd('\r').Split('|');

        // ── применение к состоянию (без эха обратно в сеть) ──
        public static void ApplySnapshot(GameState s, string[] p)
        {
            if (p.Length < 4) return;
            foreach (var f in p[1].Split(','))
                if (f.Length > 0) s.ApplyRemoteFlag(f);
            foreach (var idStr in p[2].Split(','))
                if (int.TryParse(idStr, out var id)) s.ApplyRemoteNode(id);
            if (ParseF(p[3], out var heat)) s.gridHeat = heat;
        }

        public static void ApplyFlag(GameState s, string[] p)
        {
            if (p.Length >= 2 && p[1].Length > 0) s.ApplyRemoteFlag(p[1]);
        }

        public static void ApplyNode(GameState s, string[] p)
        {
            if (p.Length >= 2 && int.TryParse(p[1], out var id)) s.ApplyRemoteNode(id);
        }
    }

    // Разрезает произвольные TCP-чанки на строки-сообщения ('\n').
    public class NetFramer
    {
        readonly StringBuilder _buf = new();

        public List<string> Feed(byte[] data, int count)
        {
            var lines = new List<string>();
            _buf.Append(Encoding.UTF8.GetString(data, 0, count));
            while (true)
            {
                string all = _buf.ToString();
                int nl = all.IndexOf('\n');
                if (nl < 0) break;
                if (nl > 0) lines.Add(all.Substring(0, nl));
                _buf.Clear();
                _buf.Append(all.Substring(nl + 1));
            }
            return lines;
        }

        public static byte[] Pack(string msg) => Encoding.UTF8.GetBytes(msg + "\n");
    }
}
