using UnityEngine;
using Virus.Core;
using Virus.Util;
using Virus.World;

namespace Virus.App
{
    // Единая точка входа сцены GridWorld: поднимает синглтон GameState (если его
    // ещё нет), строит мир, HUD и менеджер взаимодействий. В финальном проекте
    // часть этого выносится в сцены-ассеты, но процедурный подход Godot сохранён.
    public class Boot : MonoBehaviour
    {
        void Awake()
        {
            if (GameStateBehaviour.I == null)
                new GameObject("GameState", typeof(GameStateBehaviour));

            var hud = new GameObject("HUD", typeof(UI.Hud)).GetComponent<UI.Hud>();
            var world = new GameObject("GridWorld", typeof(GridWorld));
            var im = new GameObject("Interactions", typeof(InteractionManager)).GetComponent<InteractionManager>();
            im.hud = hud;
        }
    }
}
