using UnityEngine;
using UnityEngine.SceneManagement;

namespace Virus.App
{
    // Порт get_tree().change_scene_to_file(...). Имена сцен = имена файлов .unity,
    // добавленных в Build Settings (создаются в редакторе Unity — см. PORTING.md).
    public static class SceneFlow
    {
        public const string Menu   = "MainMenu";
        public const string Grid   = "GridWorld";
        public const string Raid   = "Level";       // рейд (порт level.gd) — TODO
        public const string Victory = "VictoryTunnel";

        public static void GoMenu()  => SceneManager.LoadScene(Menu);
        public static void GoGrid()  => SceneManager.LoadScene(Grid);
        public static void EnterRaid() => SceneManager.LoadScene(Raid);
        public static void GoVictory() => SceneManager.LoadScene(Victory);

        /// Перезагрузка текущей сцены Грида (после «рейда» мир перестраивается
        /// с новым прогрессом — как в Godot при возврате из level.tscn).
        public static void ReloadGrid() =>
            SceneManager.LoadScene(SceneManager.GetActiveScene().buildIndex);
    }
}
