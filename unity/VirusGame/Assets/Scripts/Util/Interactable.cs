using System;
using System.Collections.Generic;
using UnityEngine;

namespace Virus.Util
{
    // Взаимодействия как в Godot: дистанция до объекта + [E].
    // holdSeconds > 0 — действие с удержанием (генераторы, стойки, ядро…).
    public class Interactable : MonoBehaviour
    {
        public static readonly List<Interactable> All = new();
        public string prompt = "[E]";
        public Func<string> dynamicPrompt;     // если задан — перекрывает prompt
        public Func<bool> enabledFn;           // false = кандидат не участвует
        public float radius = 2.8f;
        public float holdSeconds = 0f;
        public Action onInteract;

        void OnEnable() => All.Add(this);
        void OnDisable() => All.Remove(this);
    }

    public class InteractionManager : MonoBehaviour
    {
        public Transform player;
        public Action<string> setPrompt;       // куда писать подсказку (HUD)

        Interactable _held;
        float _holdT;

        void Update()
        {
            if (UI.PuzzleUI.IsOpen || UI.EvolutionUI.IsOpen || UI.PauseMenu.IsOpen) { setPrompt?.Invoke(""); return; }
            if (player == null)
            {
                var p = FindFirstObjectByType<Player.VirusPlayer>();
                if (p != null) player = p.transform;
                if (player == null) return;
            }

            Interactable best = null;
            float bestD = float.MaxValue;
            foreach (var it in Interactable.All)
            {
                if (it == null) continue;
                if (it.enabledFn != null && !it.enabledFn()) continue;
                float d = Vector3.Distance(player.position, it.transform.position);
                if (d < it.radius && d < bestD) { bestD = d; best = it; }
            }

            if (best == null)
            {
                setPrompt?.Invoke("");
                _held = null; _holdT = 0f;
                return;
            }

            string text = best.dynamicPrompt != null ? best.dynamicPrompt() : best.prompt;

            if (best.holdSeconds > 0f)
            {
                if (Input.GetKey(KeyCode.E))
                {
                    if (_held != best) { _held = best; _holdT = 0f; }
                    _holdT += Time.deltaTime;
                    setPrompt?.Invoke($"{text}  {Mathf.Min((int)(_holdT / best.holdSeconds * 100f), 100)}%");
                    if (_holdT >= best.holdSeconds)
                    {
                        _held = null; _holdT = 0f;
                        best.onInteract?.Invoke();
                    }
                }
                else
                {
                    _held = null; _holdT = 0f;
                    setPrompt?.Invoke(text);
                }
            }
            else
            {
                setPrompt?.Invoke(text);
                if (Input.GetKeyDown(KeyCode.E)) best.onInteract?.Invoke();
            }
        }
    }
}
