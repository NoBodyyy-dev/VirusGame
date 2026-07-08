using System;
using System.Collections.Generic;
using UnityEngine;

namespace Virus.Util
{
    // Godot делал взаимодействие через дистанцию до объектов и [E] в _process.
    // В Unity: компонент-маркер + менеджер, ищущий ближайший к игроку.
    public class Interactable : MonoBehaviour
    {
        public static readonly List<Interactable> All = new();
        public string prompt = "[E]";
        public float radius = 2.8f;
        public Action onInteract;

        void OnEnable() => All.Add(this);
        void OnDisable() => All.Remove(this);
    }

    public class InteractionManager : MonoBehaviour
    {
        public Transform player;
        public UI.Hud hud;

        void Update()
        {
            if (player == null) { var p = GameObject.Find("Player"); if (p) player = p.transform; }
            if (player == null) return;

            Interactable best = null;
            float bestD = float.MaxValue;
            foreach (var it in Interactable.All)
            {
                if (it == null) continue;
                float d = Vector3.Distance(player.position, it.transform.position);
                if (d < it.radius && d < bestD) { bestD = d; best = it; }
            }

            if (hud != null) hud.SetPrompt(best != null ? best.prompt : "");
            if (best != null && Input.GetKeyDown(KeyCode.E)) best.onInteract?.Invoke();
        }
    }
}
