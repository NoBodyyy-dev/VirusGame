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
    }
}
