using System.IO;
using UnityEngine;
using Virus.Core;

namespace Virus.App
{
    // Сохранение кампании: сериализация ядра (GameState.Serialize) в
    // persistentDataPath. Автосейв — после рейда, периодически в Гриде,
    // при выходе из сцены. НОВАЯ КАМПАНИЯ стирает сейв.
    public static class SaveSystem
    {
        static string PathFile => Application.persistentDataPath + "/campaign.sav";

        public static bool HasSave
        {
            get { try { return File.Exists(PathFile); } catch { return false; } }
        }

        public static void Save()
        {
            try { File.WriteAllText(PathFile, GameState.I.Serialize()); }
            catch { /* диск занят/нет прав — прогресс живёт в памяти */ }
        }

        public static bool Load()
        {
            try
            {
                if (!HasSave) return false;
                return GameState.I.Deserialize(File.ReadAllText(PathFile));
            }
            catch { return false; }
        }

        public static void Delete()
        {
            try { if (HasSave) File.Delete(PathFile); } catch { }
        }

        // сводка сейва для карточки в меню — без применения к GameState
        public class Preview
        {
            public bool ok;
            public int infected, level, bestLoot;
            public string branch = "";
        }

        public static Preview Peek()
        {
            var p = new Preview();
            try
            {
                if (!HasSave) return p;
                foreach (var raw in File.ReadAllText(PathFile).Split('\n'))
                {
                    var line = raw.TrimEnd('\r');
                    int eq = line.IndexOf('=');
                    if (eq <= 0) continue;
                    string key = line.Substring(0, eq), val = line.Substring(eq + 1);
                    switch (key)
                    {
                        case "branch": p.branch = val; break;
                        case "level": int.TryParse(val, out p.level); break;
                        case "rec.bestLoot": int.TryParse(val, out p.bestLoot); break;
                        case "infected":
                            foreach (var id in val.Split(',')) if (id.Length > 0) p.infected++;
                            break;
                    }
                }
                p.ok = true;
            }
            catch { }
            return p;
        }
    }
}
