using UnityEngine;

namespace Virus.Util
{
    // Порт mats.gd: процедурные материалы (URP Lit). Godot StandardMaterial3D +
    // NoiseTexture2D → Unity Material + сгенерированная в коде шумовая Texture2D.
    // Триплана в URP Lit из коробки нет — используем обычный UV-тайлинг; для
    // «настоящего» триплана нужен Shader Graph (см. PORTING.md).
    public static class Mats
    {
        // Работает и в URP, и во встроенном конвейере. Под URP базовые материалы
        // берём из Resources (их кладёт editor-скрипт SetupURP — так шейдер
        // URP/Lit попадает в билд с нужными вариантами); иначе — Standard.
        static Shader _lit;
        static Shader Lit
        {
            get
            {
                if (_lit == null)
                {
                    _lit = Shader.Find("Universal Render Pipeline/Lit");
                    if (_lit == null) _lit = Shader.Find("Standard");
                }
                return _lit;
            }
        }

        static Material _baseLit, _baseEmis;
        static bool _basesInit;

        static void InitBases()
        {
            if (_basesInit) return;
            _basesInit = true;
            _baseLit = Resources.Load<Material>("mat_urp_lit");
            _baseEmis = Resources.Load<Material>("mat_urp_lit_emissive");
        }

        static Material NewLit()
        {
            InitBases();
            return _baseLit != null ? new Material(_baseLit) : new Material(Lit);
        }

        static Material NewEmissive()
        {
            InitBases();
            var m = _baseEmis != null ? new Material(_baseEmis) : new Material(Lit);
            m.EnableKeyword("_EMISSION");
            m.globalIlluminationFlags = MaterialGlobalIlluminationFlags.RealtimeEmissive;
            return m;
        }

        static readonly System.Collections.Generic.Dictionary<string, Texture2D> _texCache = new();

        static Texture2D Noise(string key, int seed, float freq)
        {
            if (_texCache.TryGetValue(key, out var t)) return t;
            const int N = 256;   // 128 мылило вблизи
            var tex = new Texture2D(N, N, TextureFormat.RGB24, true) { wrapMode = TextureWrapMode.Repeat, anisoLevel = 4 };
            var rng = new System.Random(seed);
            // простой октавный value-noise; для продакшена заменить на FastNoiseLite-порт
            var px = new Color[N * N];
            for (int y = 0; y < N; y++)
                for (int x = 0; x < N; x++)
                {
                    float v = 0f, amp = 0.5f, f = freq;
                    for (int o = 0; o < 5; o++)
                    {
                        v += amp * Mathf.PerlinNoise((x * f + seed), (y * f + seed));
                        amp *= 0.5f; f *= 2f;
                    }
                    // текстура МНОЖИТ цвет материала: держим среднее светлым, но
                    // с более широким размахом — фактура читается, а не мылится
                    float c = Mathf.Clamp01(0.58f + v * 0.5f);
                    // лёгкий цветовой перекос: убирает «пластилиновую» серость
                    px[y * N + x] = new Color(c, c * 0.985f, c * 0.965f);
                }
            tex.SetPixels(px);
            tex.Apply();
            _texCache[key] = tex;
            return tex;
        }

        // ставим оба набора имён свойств: лишнее шейдер молча игнорирует
        static void SetAlbedo(Material m, Color c)
        {
            m.SetColor("_BaseColor", c);
            m.SetColor("_Color", c);
        }
        static void SetTex(Material m, Texture t, float tile)
        {
            var scale = new Vector2(tile, tile);
            m.SetTexture("_BaseMap", t);
            m.SetTextureScale("_BaseMap", scale);
            m.SetTexture("_MainTex", t);
            m.SetTextureScale("_MainTex", scale);
        }
        static void SetSmooth(Material m, float metallic, float smoothness)
        {
            m.SetFloat("_Metallic", metallic);
            m.SetFloat("_Smoothness", smoothness);
            m.SetFloat("_Glossiness", smoothness);
        }

        static Material Base(Color albedo, float metallic, float smoothness, string noiseKey, int seed, float freq, float tile)
        {
            var m = NewLit();
            SetAlbedo(m, albedo);
            SetSmooth(m, metallic, smoothness);
            // у Godot был триплан в мировых координатах; тут UV 0..1 на грань
            // скейленного куба — умножаем тайлинг, чтобы фактура не размазывалась
            if (noiseKey != null) SetTex(m, Noise(noiseKey, seed, freq), tile * 12f);
            return m;
        }

        public static Material Neon(Color c, float energy = 1.8f)
        {
            var m = NewEmissive();
            // альбедо слегка тонируем цветом: при слабом эмиссиве тело не сереет
            SetAlbedo(m, new Color(c.r * 0.35f, c.g * 0.35f, c.b * 0.35f));
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
        public static Material Moss(Color? t = null) => Base(t ?? new Color(0.20f,0.34f,0.14f), 0f, 0f, "mos", 131, 0.28f, 0.5f);
        public static Material BunkerWall(Color? t = null) => Base(t ?? new Color(0.30f,0.31f,0.30f), 0f, 0.03f, "bnk", 161, 0.04f, 0.25f);
        public static Material Rust(Color? t = null) => Base(t ?? new Color(0.38f,0.24f,0.16f), 0.6f, 0.2f, "rst", 171, 0.16f, 0.45f);
        public static Material DeckMetal(Color? t = null) => Base(t ?? new Color(0.36f,0.38f,0.42f), 0.8f, 0.5f, "dck", 181, 0.9f, 0.8f);
        public static Material Hazard()     => Base(new Color(0.75f,0.60f,0.12f), 0f, 0.3f, "hzd", 191, 0.4f, 1.5f);
        public static Material Obsidian()   => Base(new Color(0.07f,0.08f,0.10f), 0.4f, 0.82f, "obs", 201, 0.05f, 0.3f);
        public static Material WhitePanel() => Base(new Color(0.92f,0.94f,0.97f), 0.1f, 0.65f, "wht", 211, 0.25f, 0.4f);
    }
}
