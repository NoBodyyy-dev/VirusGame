using UnityEngine;

namespace Virus.Util
{
    // Порт mats.gd: процедурные материалы (URP Lit). Godot StandardMaterial3D +
    // NoiseTexture2D → Unity Material + сгенерированная в коде шумовая Texture2D.
    // Триплана в URP Lit из коробки нет — используем обычный UV-тайлинг; для
    // «настоящего» триплана нужен Shader Graph (см. PORTING.md).
    public static class Mats
    {
        static Shader _lit;
        static Shader Lit => _lit ??= Shader.Find("Universal Render Pipeline/Lit");

        static readonly System.Collections.Generic.Dictionary<string, Texture2D> _texCache = new();

        static Texture2D Noise(string key, int seed, float freq)
        {
            if (_texCache.TryGetValue(key, out var t)) return t;
            const int N = 128;
            var tex = new Texture2D(N, N, TextureFormat.RGB24, true) { wrapMode = TextureWrapMode.Repeat };
            var rng = new System.Random(seed);
            // простой октавный value-noise; для продакшена заменить на FastNoiseLite-порт
            var px = new Color[N * N];
            for (int y = 0; y < N; y++)
                for (int x = 0; x < N; x++)
                {
                    float v = 0f, amp = 0.5f, f = freq;
                    for (int o = 0; o < 4; o++)
                    {
                        v += amp * Mathf.PerlinNoise((x * f + seed) , (y * f + seed));
                        amp *= 0.5f; f *= 2f;
                    }
                    px[y * N + x] = new Color(v, v, v);
                }
            tex.SetPixels(px);
            tex.Apply();
            _texCache[key] = tex;
            return tex;
        }

        static Material Base(Color albedo, float metallic, float smoothness, string noiseKey, int seed, float freq, float tile)
        {
            var m = new Material(Lit);
            m.SetColor("_BaseColor", albedo);
            m.SetFloat("_Metallic", metallic);
            m.SetFloat("_Smoothness", smoothness);
            if (noiseKey != null)
            {
                m.SetTexture("_BaseMap", Noise(noiseKey, seed, freq));
                m.SetTextureScale("_BaseMap", new Vector2(tile, tile));
            }
            return m;
        }

        public static Material Neon(Color c, float energy = 1.8f)
        {
            var m = new Material(Lit);
            m.SetColor("_BaseColor", new Color(0.02f, 0.03f, 0.05f));
            m.EnableKeyword("_EMISSION");
            m.globalIlluminationFlags = MaterialGlobalIlluminationFlags.RealtimeEmissive;
            m.SetColor("_EmissionColor", new Color(c.r, c.g, c.b) * energy);
            return m;
        }

        public static Material Concrete(Color? tint = null) =>
            Base(tint ?? new Color(0.44f,0.45f,0.48f), 0f, 0.08f, "conc", 11, 0.05f, 0.3f);
        public static Material Metal(Color? tint = null, float rough = 0.4f) =>
            Base(tint ?? new Color(0.62f,0.65f,0.70f), 0.85f, 1f - rough, "met", 21, 0.03f, 0.6f);
        public static Material MetalDark(float rough = 0.5f) => Metal(new Color(0.34f,0.36f,0.40f), rough);
        public static Material Plastic(Color? tint = null) =>
            Base(tint ?? new Color(0.36f,0.39f,0.44f), 0.15f, 0.38f, "pl", 31, 0.12f, 0.5f);
        public static Material Brick()      => Base(new Color(0.32f,0.26f,0.24f), 0f, 0.1f, "brk", 71, 0.25f, 0.55f);
        public static Material Sidewalk()   => Base(new Color(0.26f,0.27f,0.30f), 0f, 0.45f, "side", 91, 0.5f, 0.4f);
        public static Material PlasterOld(Color? t = null) => Base(t ?? new Color(0.5f,0.48f,0.42f), 0f, 0.05f, "pls", 101, 0.08f, 0.35f);
        public static Material CarpetRot()  => Base(new Color(0.24f,0.26f,0.20f), 0f, 0f, "cpt", 121, 0.35f, 0.3f);
        public static Material Moss()       => Base(new Color(0.20f,0.34f,0.14f), 0f, 0f, "mos", 131, 0.28f, 0.5f);
        public static Material BunkerWall(Color? t = null) => Base(t ?? new Color(0.30f,0.31f,0.30f), 0f, 0.03f, "bnk", 161, 0.04f, 0.25f);
        public static Material Rust(Color? t = null) => Base(t ?? new Color(0.38f,0.24f,0.16f), 0.6f, 0.2f, "rst", 171, 0.16f, 0.45f);
        public static Material DeckMetal(Color? t = null) => Base(t ?? new Color(0.36f,0.38f,0.42f), 0.8f, 0.5f, "dck", 181, 0.9f, 0.8f);
        public static Material Hazard()     => Base(new Color(0.75f,0.60f,0.12f), 0f, 0.3f, "hzd", 191, 0.4f, 1.5f);
        public static Material Obsidian()   => Base(new Color(0.07f,0.08f,0.10f), 0.4f, 0.82f, "obs", 201, 0.05f, 0.3f);
        public static Material WhitePanel() => Base(new Color(0.92f,0.94f,0.97f), 0.1f, 0.65f, "wht", 211, 0.25f, 0.4f);
    }
}
