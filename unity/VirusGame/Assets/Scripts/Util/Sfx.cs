using System.Collections.Generic;
using UnityEngine;

namespace Virus.Util
{
    // Порт sfx.gd без аудио-ассетов: короткие сигналы синтезируются в PCM
    // прямо в коде (AudioClip.Create) и кэшируются. Один общий AudioSource.
    public static class Sfx
    {
        const int Rate = 22050;

        static AudioSource _src;
        static readonly Dictionary<string, AudioClip> _cache = new();

        static AudioSource Src
        {
            get
            {
                if (_src == null)
                {
                    var go = new GameObject("Sfx");
                    Object.DontDestroyOnLoad(go);
                    _src = go.AddComponent<AudioSource>();
                }
                return _src;
            }
        }

        public static void Play(string kind, float vol = 0.4f)
        {
            var clip = Clip(kind);
            if (clip != null) Src.PlayOneShot(clip, Mathf.Clamp01(vol));
        }

        // ── эмбиент: зацикленный гул без швов (целое число периодов в клипе).
        // Источник живёт в сцене и умирает с ней — каждая сцена задаёт свой.
        public static AudioSource Ambient(string kind, float vol)
        {
            var clip = AmbientClip(kind);
            if (clip == null) return null;
            var go = new GameObject("Ambience_" + kind);
            var src = go.AddComponent<AudioSource>();
            src.clip = clip;
            src.loop = true;
            src.volume = Mathf.Clamp01(vol);
            src.Play();
            return src;
        }

        static AudioClip AmbientClip(string kind)
        {
            string key = "amb_" + kind;
            if (_cache.TryGetValue(key, out var c)) return c;
            const float dur = 8f;
            int n = (int)(Rate * dur);
            var d = new float[n];
            // частоты кратны 1/8 Гц — на границе клипа фаза совпадает, шва нет
            (float f, float a)[] tones = kind switch
            {
                // серверная: низкий гул + лёгкая «электрика»
                "hum" => new[] { (55f, 0.5f), (110f, 0.22f), (220f, 0.06f) },
                // грид: ветер-подложка пониже и мягче
                _ => new[] { (40f, 0.5f), (80f, 0.18f), (161f, 0.05f) },
            };
            for (int i = 0; i < n; i++)
            {
                float t = (float)i / Rate, v = 0f;
                foreach (var (f, a) in tones) v += Mathf.Sin(2f * Mathf.PI * f * t) * a;
                // медленное «дыхание» (0.25 Гц — 2 полных цикла на клип)
                v *= 0.75f + 0.25f * Mathf.Sin(2f * Mathf.PI * 0.25f * t);
                d[i] = v * 0.5f;
            }
            var clip = AudioClip.Create(key, n, 1, Rate, false);
            clip.SetData(d, 0);
            _cache[key] = clip;
            return clip;
        }

        static AudioClip Clip(string kind)
        {
            if (_cache.TryGetValue(kind, out var c)) return c;
            float[] data = kind switch
            {
                "ui"      => Tone(880f, 0.06f),
                "ability" => Sweep(300f, 900f, 0.18f),
                "trap"    => NoiseBurst(0.22f),
                "deposit" => Chord(new[] { 660f, 990f }, 0.16f),
                "hook"    => Sweep(240f, 120f, 0.3f),
                "alarm"   => Chord(new[] { 440f, 466f }, 0.35f),
                "win"     => Arp(new[] { 523f, 659f, 784f, 1047f }, 0.09f),
                "fail"    => Arp(new[] { 392f, 330f, 262f }, 0.14f),
                _ => null,
            };
            if (data == null) return null;
            var clip = AudioClip.Create("sfx_" + kind, data.Length, 1, Rate, false);
            clip.SetData(data, 0);
            _cache[kind] = clip;
            return clip;
        }

        // ── синтез: простые формы с экспоненциальным затуханием ──
        static float[] Tone(float freq, float dur)
        {
            int n = (int)(Rate * dur);
            var d = new float[n];
            for (int i = 0; i < n; i++)
            {
                float t = (float)i / Rate;
                d[i] = Mathf.Sin(2f * Mathf.PI * freq * t) * Decay(i, n);
            }
            return d;
        }

        static float[] Sweep(float f0, float f1, float dur)
        {
            int n = (int)(Rate * dur);
            var d = new float[n];
            float phase = 0f;
            for (int i = 0; i < n; i++)
            {
                float k = (float)i / n;
                phase += 2f * Mathf.PI * Mathf.Lerp(f0, f1, k) / Rate;
                d[i] = Mathf.Sin(phase) * Decay(i, n);
            }
            return d;
        }

        static float[] Chord(float[] freqs, float dur)
        {
            int n = (int)(Rate * dur);
            var d = new float[n];
            for (int i = 0; i < n; i++)
            {
                float t = (float)i / Rate, v = 0f;
                foreach (var f in freqs) v += Mathf.Sin(2f * Mathf.PI * f * t);
                d[i] = v / freqs.Length * Decay(i, n);
            }
            return d;
        }

        static float[] Arp(float[] notes, float noteDur)
        {
            int per = (int)(Rate * noteDur), n = per * notes.Length;
            var d = new float[n];
            for (int i = 0; i < n; i++)
            {
                int ni = Mathf.Min(i / per, notes.Length - 1);
                float t = (float)(i % per) / Rate;
                d[i] = Mathf.Sin(2f * Mathf.PI * notes[ni] * t) * Decay(i % per, per);
            }
            return d;
        }

        static float[] NoiseBurst(float dur)
        {
            int n = (int)(Rate * dur);
            var d = new float[n];
            var rng = new System.Random(5);
            for (int i = 0; i < n; i++)
                d[i] = ((float)rng.NextDouble() * 2f - 1f) * Decay(i, n) * 0.8f;
            return d;
        }

        static float Decay(int i, int n) => Mathf.Pow(1f - (float)i / n, 2.2f);
    }
}
