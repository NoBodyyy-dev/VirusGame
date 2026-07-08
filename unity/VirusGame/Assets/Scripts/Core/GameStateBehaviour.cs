using UnityEngine;

namespace Virus.Core
{
    // Godot-автолоад GameState → персистентный синглтон Unity (DontDestroyOnLoad).
    // Держит ссылку на чистое ядро Virus.Core.GameState и гоняет его Tick.
    public class GameStateBehaviour : MonoBehaviour
    {
        public static GameStateBehaviour I { get; private set; }
        public GameState S => GameState.I;

        void Awake()
        {
            if (I != null) { Destroy(gameObject); return; }
            I = this;
            DontDestroyOnLoad(gameObject);
            if (S.gridNodes.Count == 0) S.NewCampaign();
        }

        void Update() => S.Tick(Time.deltaTime);
    }
}
