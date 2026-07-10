using System.Collections.Generic;
using UnityEngine;
using Virus.Core;
using Virus.Util;

namespace Virus.Player
{
    // Порт virus_models.gd: уникальное процедурное тело для каждого класса вируса.
    // Полиморфный визуал: stage (0..3) добавляет детали по мере прокачки,
    // на УР.3 — венец апекса; доп. ветка примешивает свою эмблему к скину.
    public static class VirusModel
    {
        public static GameObject Build(Transform parent, string cls, int stage, string secondary)
        {
            var color = GameData.CLASSES.TryGetValue(cls, out var ci) ? ci.color : new Color(0.6f, 0.72f, 0.78f);
            var root = new GameObject("VirusModel");
            root.transform.SetParent(parent, false);
            var anim = root.AddComponent<VirusModelAnim>();

            switch (cls)
            {
                case "worm": BuildWorm(root.transform, anim, color, stage); break;
                case "trojan": BuildTrojan(root.transform, anim, color, stage); break;
                case "ransomware": BuildRansomware(root.transform, anim, color, stage); break;
                case "spyware": BuildSpyware(root.transform, anim, color, stage); break;
                case "adware": BuildAdware(root.transform, anim, color, stage); break;
                case "rootkit": BuildRootkit(root.transform, anim, color, stage); break;
                case "botnet": BuildBotnet(root.transform, anim, color, stage); break;
                default: BuildBase(root.transform, anim, color); break;
            }
            if (stage >= 3) AddApexCrown(root.transform, anim, color);
            if (!string.IsNullOrEmpty(secondary)) AddSecondaryEmblem(root.transform, anim, secondary);

            // свет штамма
            var l = new GameObject("glow").AddComponent<Light>();
            l.transform.SetParent(root.transform, false);
            l.transform.localPosition = new Vector3(0, 1.2f, 0);
            l.type = LightType.Point;
            l.color = color;
            l.intensity = 1.3f;
            l.range = 5f;
            return root;
        }

        // «баг»: глючный пищащий краб — форма игрока при 0 HP
        public static GameObject BuildBug(Transform parent, Color color)
        {
            var root = new GameObject("BugModel");
            root.transform.SetParent(parent, false);
            var body = Prim(PrimitiveType.Cube, root.transform, new Vector3(0, 0.35f, 0),
                new Vector3(0.5f, 0.32f, 0.42f), Mats.Neon(color * 0.7f, 1.4f));
            for (int side = -1; side <= 1; side += 2)
            {
                Prim(PrimitiveType.Sphere, root.transform, new Vector3(side * 0.13f, 0.52f, -0.18f),
                    Vector3.one * 0.18f, Mats.Neon(Color.white, 3f));
                Prim(PrimitiveType.Sphere, root.transform, new Vector3(side * 0.13f, 0.52f, -0.26f),
                    Vector3.one * 0.08f, Mats.Plastic(new Color(0.02f, 0.02f, 0.03f)));
                for (int i = 0; i < 3; i++)
                {
                    var leg = Prim(PrimitiveType.Cube, root.transform,
                        new Vector3(side * 0.32f, 0.2f, -0.12f + 0.14f * i),
                        new Vector3(0.22f, 0.04f, 0.04f), Mats.Neon(color, 1.6f));
                    leg.transform.localRotation = Quaternion.Euler(0, 0, -30f * side);
                }
            }
            Util.Build.Label(root.transform, "SEGFAULT", new Vector3(0, 0.95f, 0), 2.4f, new Color(1f, 0.35f, 0.4f));
            return root;
        }

        // ящик-маскировка трояна: неотличим от обычного лута
        public static GameObject BuildCrate(Transform parent)
        {
            var root = new GameObject("MorphCrate");
            root.transform.SetParent(parent, false);
            Prim(PrimitiveType.Cube, root.transform, new Vector3(0, 0.45f, 0),
                new Vector3(1f, 0.85f, 0.9f), Mats.Neon(new Color(0.29f, 0.56f, 1f), 0.9f));
            Util.Build.Label(root.transform, "точно_не_вирус.box\n◈ 18", new Vector3(0, 1.35f, 0), 2.2f, new Color(0.29f, 0.56f, 1f));
            return root;
        }

        // ── общие детали ──
        static GameObject Prim(PrimitiveType t, Transform parent, Vector3 pos, Vector3 scale, Material m)
        {
            var go = GameObject.CreatePrimitive(t);
            Object.Destroy(go.GetComponent<Collider>());   // скин не должен толкаться
            go.layer = 2;
            go.transform.SetParent(parent, false);
            go.transform.localPosition = pos;
            go.transform.localScale = scale;
            go.GetComponent<MeshRenderer>().sharedMaterial = m;
            return go;
        }

        // кольцо из орбов — замена тора Godot
        static Transform Ring(Transform parent, Vector3 pos, float radius, int count, float orbR, Material m, float tiltX = 0f)
        {
            var pivot = new GameObject("ring").transform;
            pivot.SetParent(parent, false);
            pivot.localPosition = pos;
            pivot.localRotation = Quaternion.Euler(tiltX, 0, 0);
            for (int i = 0; i < count; i++)
            {
                float a = Mathf.PI * 2f * i / count;
                Prim(PrimitiveType.Sphere, pivot, new Vector3(Mathf.Cos(a) * radius, 0, Mathf.Sin(a) * radius),
                    Vector3.one * orbR * 2f, m);
            }
            return pivot;
        }

        static void Spike(Transform parent, Vector3 center, Vector3 dir, float len, Material m, Material tipM)
        {
            var sp = Prim(PrimitiveType.Capsule, parent, center + dir * (0.42f + len * 0.4f),
                new Vector3(len * 0.35f, len * 0.5f, len * 0.35f), m);
            sp.transform.up = dir;
            Prim(PrimitiveType.Sphere, parent, center + dir * (0.42f + len * 0.95f),
                Vector3.one * len * 0.32f, tipM);
        }

        static void Eyes(Transform parent, Vector3 at, float r, Color c)
        {
            for (int side = -1; side <= 1; side += 2)
                Prim(PrimitiveType.Sphere, parent, at + new Vector3(side * 0.16f, 0, 0),
                    Vector3.one * r * 2f, Mats.Neon(Color.Lerp(Color.white, c, 0.25f), 3.5f));
        }

        // ── БАЗОВЫЙ ПРОТО-ШТАММ: у всех одинаковый на старте ──
        static void BuildBase(Transform t, VirusModelAnim anim, Color c)
        {
            var core = new GameObject("core").transform;
            core.SetParent(t, false);
            core.localPosition = new Vector3(0, 0.95f, 0);
            anim.breath = core;
            Prim(PrimitiveType.Sphere, core, Vector3.zero, Vector3.one * 0.84f, Mats.Neon(c, 1.1f));
            Prim(PrimitiveType.Sphere, core, Vector3.zero, Vector3.one * 0.36f, Mats.Neon(c, 3f));
            var rng = new System.Random(3);
            for (int i = 0; i < 10; i++)
            {
                var dir = new Vector3((float)rng.NextDouble() * 2 - 1, (float)rng.NextDouble() * 1.6f - 0.6f,
                    (float)rng.NextDouble() * 2 - 1).normalized;
                Spike(core, Vector3.zero, dir, 0.24f, Mats.Neon(c, 1.8f), Mats.Neon(Color.Lerp(c, Color.white, 0.3f), 2.6f));
            }
            Eyes(core, new Vector3(0, 0.1f, -0.36f), 0.08f, c);
            var ring = Ring(core, Vector3.zero, 0.54f, 10, 0.05f, Mats.Neon(c, 1.2f), 70f);
            anim.spins.Add((ring, Vector3.up, 54f));
        }

        // ── ЧЕРВЬ: членистый бур-паразит ──
        static void BuildWorm(Transform t, VirusModelAnim anim, Color c, int stage)
        {
            var head = new GameObject("head").transform;
            head.SetParent(t, false);
            head.localPosition = new Vector3(0, 0.95f, 0);
            anim.breath = head;
            Prim(PrimitiveType.Sphere, head, Vector3.zero, Vector3.one * 0.68f, Mats.Neon(c, 1f));
            Ring(head, new Vector3(0, 0.05f, 0.05f), 0.32f, 8, 0.05f, Mats.Neon(c, 1.4f), 78f);
            // вращающийся бур
            var drill = new GameObject("drill").transform;
            drill.SetParent(head, false);
            drill.localPosition = new Vector3(0, 0, -0.42f);
            var dm = Prim(PrimitiveType.Capsule, drill, Vector3.zero, new Vector3(0.3f, 0.3f, 0.3f), Mats.Neon(c, 2.2f));
            dm.transform.localRotation = Quaternion.Euler(-90, 0, 0);
            for (int k = 0; k < 3; k++)
                Ring(drill, new Vector3(0, 0, -0.05f - 0.12f * k), 0.08f + 0.05f * k, 6, 0.03f,
                    Mats.Neon(Color.Lerp(c, Color.white, 0.25f), 2.8f), 90f);
            anim.spins.Add((drill, Vector3.forward, 320f));
            Eyes(head, new Vector3(0, 0.12f, -0.28f), 0.07f, c);
            // сегменты хвоста
            int count = 4 + stage;
            for (int i = 0; i < count; i++)
            {
                float r = 0.27f - 0.03f * i;
                var seg = Prim(PrimitiveType.Sphere, t,
                    new Vector3(0, 0.95f - 0.05f * i, 0.42f + 0.32f * i), Vector3.one * r * 2f,
                    Mats.Neon(c, Mathf.Max(1.15f - 0.12f * i, 0.3f)));
                anim.wiggles.Add((seg.transform, i * 0.7f));
            }
        }

        // ── ТРОЯН: коробчатый мимик с маской ──
        static void BuildTrojan(Transform t, VirusModelAnim anim, Color c, int stage)
        {
            var body = new GameObject("body").transform;
            body.SetParent(t, false);
            body.localPosition = new Vector3(0, 0.9f, 0);
            anim.breath = body;
            Prim(PrimitiveType.Cube, body, Vector3.zero, new Vector3(0.72f, 0.86f, 0.6f), Mats.Plastic(new Color(0.07f, 0.09f, 0.12f)));
            // швы-подсветка
            Prim(PrimitiveType.Cube, body, new Vector3(0, 0.1f, 0), new Vector3(0.74f, 0.04f, 0.62f), Mats.Neon(c, 2f));
            Prim(PrimitiveType.Cube, body, new Vector3(0, -0.22f, 0), new Vector3(0.74f, 0.03f, 0.62f), Mats.Neon(c, 1.4f));
            // маска-лицо
            Prim(PrimitiveType.Cube, body, new Vector3(0, 0.22f, -0.33f), new Vector3(0.4f, 0.3f, 0.05f), Mats.Neon(Color.Lerp(c, Color.white, 0.15f), 1.2f));
            Eyes(body, new Vector3(0, 0.24f, -0.38f), 0.06f, c);
            if (stage >= 2)   // фальш-крышка и «лапки-защёлки»
            {
                Prim(PrimitiveType.Cube, body, new Vector3(0, 0.48f, 0), new Vector3(0.8f, 0.08f, 0.66f), Mats.Plastic(new Color(0.1f, 0.12f, 0.16f)));
                for (int side = -1; side <= 1; side += 2)
                    Prim(PrimitiveType.Cube, body, new Vector3(side * 0.4f, -0.1f, 0), new Vector3(0.06f, 0.5f, 0.2f), Mats.Neon(c, 0.9f));
            }
            var ring = Ring(body, new Vector3(0, -0.42f, 0), 0.5f, 8, 0.04f, Mats.Neon(c, 1.1f));
            anim.spins.Add((ring, Vector3.up, 40f));
        }

        // ── RANSOMWARE: тяжёлый замок-танк ──
        static void BuildRansomware(Transform t, VirusModelAnim anim, Color c, int stage)
        {
            var body = new GameObject("body").transform;
            body.SetParent(t, false);
            body.localPosition = new Vector3(0, 0.85f, 0);
            anim.breath = body;
            Prim(PrimitiveType.Cube, body, Vector3.zero, new Vector3(0.9f, 0.8f, 0.62f), Mats.Metal(new Color(0.16f, 0.1f, 0.14f), 0.5f));
            // дужка замка
            var shackle = new GameObject("shackle").transform;
            shackle.SetParent(body, false);
            shackle.localPosition = new Vector3(0, 0.55f, 0);
            for (int i = 0; i <= 6; i++)
            {
                float a = Mathf.PI * i / 6f;
                Prim(PrimitiveType.Sphere, shackle, new Vector3(Mathf.Cos(a) * 0.32f, Mathf.Sin(a) * 0.32f, 0),
                    Vector3.one * 0.14f, Mats.Metal(new Color(0.5f, 0.5f, 0.55f), 0.7f));
            }
            // скважина и заклёпки
            Prim(PrimitiveType.Sphere, body, new Vector3(0, 0.08f, -0.33f), Vector3.one * 0.18f, Mats.Neon(c, 2.6f));
            Prim(PrimitiveType.Cube, body, new Vector3(0, -0.1f, -0.33f), new Vector3(0.07f, 0.22f, 0.04f), Mats.Neon(c, 2.6f));
            for (int sx = -1; sx <= 1; sx += 2)
                for (int sy = -1; sy <= 1; sy += 2)
                    Prim(PrimitiveType.Sphere, body, new Vector3(sx * 0.36f, sy * 0.28f, -0.32f),
                        Vector3.one * 0.08f, Mats.Metal(new Color(0.45f, 0.45f, 0.5f), 0.8f));
            Eyes(body, new Vector3(0, 0.3f, -0.34f), 0.055f, c);
            if (stage >= 2)   // цепи по бокам
                for (int side = -1; side <= 1; side += 2)
                    for (int i = 0; i < 3; i++)
                        Prim(PrimitiveType.Sphere, body, new Vector3(side * 0.5f, 0.25f - i * 0.22f, 0),
                            Vector3.one * 0.11f, Mats.Metal(new Color(0.4f, 0.4f, 0.45f), 0.7f));
        }

        // ── SPYWARE: летающий глаз-разведчик ──
        static void BuildSpyware(Transform t, VirusModelAnim anim, Color c, int stage)
        {
            var eye = new GameObject("eye").transform;
            eye.SetParent(t, false);
            eye.localPosition = new Vector3(0, 1.05f, 0);
            anim.breath = eye;
            Prim(PrimitiveType.Sphere, eye, Vector3.zero, Vector3.one * 0.7f, Mats.Neon(c, 0.9f));
            Prim(PrimitiveType.Sphere, eye, new Vector3(0, 0, -0.26f), Vector3.one * 0.34f, Mats.Neon(Color.white, 1.8f));
            Prim(PrimitiveType.Sphere, eye, new Vector3(0, 0, -0.37f), Vector3.one * 0.16f, Mats.Neon(new Color(1f, 0.3f, 0.3f), 4f));
            // антенны-стебельки
            int stalks = 3 + stage;
            for (int i = 0; i < stalks; i++)
            {
                float a = Mathf.PI * 2f * i / stalks;
                var dir = new Vector3(Mathf.Cos(a), 0.9f, Mathf.Sin(a)).normalized;
                Spike(eye, Vector3.zero, dir, 0.3f, Mats.Neon(c, 1.6f), Mats.Neon(Color.Lerp(c, Color.white, 0.4f), 3f));
            }
            var ring = Ring(eye, Vector3.zero, 0.52f, 12, 0.035f, Mats.Neon(c, 1.5f), 20f);
            anim.spins.Add((ring, Vector3.up, 80f));
        }

        // ── ADWARE: рой всплывающих окон ──
        static void BuildAdware(Transform t, VirusModelAnim anim, Color c, int stage)
        {
            var core = new GameObject("core").transform;
            core.SetParent(t, false);
            core.localPosition = new Vector3(0, 0.95f, 0);
            anim.breath = core;
            Prim(PrimitiveType.Sphere, core, Vector3.zero, Vector3.one * 0.6f, Mats.Neon(c, 1.2f));
            Eyes(core, new Vector3(0, 0.08f, -0.26f), 0.07f, c);
            var pivot = new GameObject("popups").transform;
            pivot.SetParent(core, false);
            int n = 4 + stage * 2;
            var rng = new System.Random(11);
            for (int i = 0; i < n; i++)
            {
                float a = Mathf.PI * 2f * i / n;
                var p = new Vector3(Mathf.Cos(a) * 0.62f, (float)rng.NextDouble() * 0.7f - 0.25f, Mathf.Sin(a) * 0.62f);
                var panel = Prim(PrimitiveType.Cube, pivot, p, new Vector3(0.26f, 0.18f, 0.02f), Mats.Neon(c, 1.5f));
                panel.transform.localRotation = Quaternion.Euler(0, -a * Mathf.Rad2Deg + 90f, 0);
                // крестик закрытия
                Prim(PrimitiveType.Cube, panel.transform, new Vector3(0.4f, 0.36f, -0.6f),
                    new Vector3(0.14f, 0.14f, 0.2f), Mats.Neon(new Color(1f, 0.3f, 0.3f), 2.4f));
            }
            anim.spins.Add((pivot, Vector3.up, 34f));
        }

        // ── ROOTKIT: тихий призрак в капюшоне ──
        static void BuildRootkit(Transform t, VirusModelAnim anim, Color c, int stage)
        {
            var body = new GameObject("body").transform;
            body.SetParent(t, false);
            body.localPosition = new Vector3(0, 0.9f, 0);
            anim.breath = body;
            // мантия (тёмная капля) и светящаяся кромка
            var robe = Prim(PrimitiveType.Capsule, body, Vector3.zero, new Vector3(0.6f, 0.6f, 0.6f), Mats.Plastic(new Color(0.05f, 0.04f, 0.09f)));
            robe.transform.localScale = new Vector3(0.62f, 0.78f, 0.62f);
            Ring(body, new Vector3(0, -0.55f, 0), 0.35f, 10, 0.035f, Mats.Neon(c, 1.6f));
            // капюшон
            Prim(PrimitiveType.Sphere, body, new Vector3(0, 0.5f, 0.05f), new Vector3(0.5f, 0.42f, 0.5f), Mats.Plastic(new Color(0.07f, 0.05f, 0.12f)));
            // глаза из тени
            Eyes(body, new Vector3(0, 0.5f, -0.2f), 0.06f, c);
            if (stage >= 2)
            {
                var ring = Ring(body, new Vector3(0, 0.15f, 0), 0.55f, 6, 0.04f, Mats.Neon(c, 1.2f), 12f);
                anim.spins.Add((ring, Vector3.up, -46f));
            }
        }

        // ── BOTNET: ядро-оператор и рой дронов ──
        static void BuildBotnet(Transform t, VirusModelAnim anim, Color c, int stage)
        {
            var core = new GameObject("core").transform;
            core.SetParent(t, false);
            core.localPosition = new Vector3(0, 0.95f, 0);
            anim.breath = core;
            Prim(PrimitiveType.Sphere, core, Vector3.zero, Vector3.one * 0.56f, Mats.Neon(c, 1.4f));
            Eyes(core, new Vector3(0, 0.06f, -0.24f), 0.06f, c);
            var swarm = new GameObject("swarm").transform;
            swarm.SetParent(core, false);
            int n = 3 + stage * 2;
            for (int i = 0; i < n; i++)
            {
                float a = Mathf.PI * 2f * i / n;
                var p = new Vector3(Mathf.Cos(a) * 0.7f, Mathf.Sin(a * 2f) * 0.22f, Mathf.Sin(a) * 0.7f);
                Prim(PrimitiveType.Sphere, swarm, p, Vector3.one * 0.14f, Mats.Neon(c, 2.2f));
            }
            anim.spins.Add((swarm, Vector3.up, 62f));
        }

        // ── УР.3: венец апекса поверх любого скина ──
        static void AddApexCrown(Transform t, VirusModelAnim anim, Color c)
        {
            var bright = Color.Lerp(c, Color.white, 0.35f);
            var crown = Ring(t, new Vector3(0, 2.25f, 0), 0.37f, 9, 0.05f, Mats.Neon(bright, 3.2f), 12f);
            anim.spins.Add((crown, Vector3.up, 150f));
            for (int i = 0; i < 3; i++)
            {
                float ang = Mathf.PI * 2f * i / 3f;
                var shard = Prim(PrimitiveType.Capsule, t,
                    new Vector3(Mathf.Cos(ang) * 0.37f, 2.42f, Mathf.Sin(ang) * 0.37f),
                    new Vector3(0.07f, 0.12f, 0.07f), Mats.Neon(c, 2.6f));
                shard.transform.localRotation = Quaternion.Euler(Mathf.Sin(ang) * 17f, 0, -Mathf.Cos(ang) * 17f);
            }
        }

        // ── доп. ветка: компактная эмблема её силуэта на орбите ──
        static void AddSecondaryEmblem(Transform t, VirusModelAnim anim, string sec)
        {
            var c2 = GameData.CLASSES.TryGetValue(sec, out var ci) ? ci.color : Color.white;
            var pivot = new GameObject("secondary").transform;
            pivot.SetParent(t, false);
            pivot.localPosition = new Vector3(0, 1.55f, 0);
            anim.spins.Add((pivot, Vector3.up, 92f));
            var at = new Vector3(0.62f, 0, 0);
            switch (sec)
            {
                case "worm":
                    var drill = Prim(PrimitiveType.Capsule, pivot, at, new Vector3(0.12f, 0.16f, 0.12f), Mats.Neon(c2, 2.4f));
                    drill.transform.localRotation = Quaternion.Euler(0, 0, 90);
                    break;
                case "trojan":
                    Prim(PrimitiveType.Cube, pivot, at, new Vector3(0.2f, 0.24f, 0.04f), Mats.Neon(c2, 1.6f));
                    Prim(PrimitiveType.Cube, pivot, at + new Vector3(0, 0.04f, -0.03f), new Vector3(0.1f, 0.03f, 0.02f), Mats.Neon(c2, 3.5f));
                    break;
                case "ransomware":
                    Ring(pivot, at, 0.1f, 6, 0.03f, Mats.Neon(c2, 2.2f), 90f);
                    Prim(PrimitiveType.Cube, pivot, at + new Vector3(0, -0.12f, 0), new Vector3(0.12f, 0.14f, 0.08f), Mats.Metal(new Color(0.1f, 0.1f, 0.13f), 0.85f));
                    break;
                case "spyware":
                    Prim(PrimitiveType.Sphere, pivot, at, Vector3.one * 0.24f, Mats.Neon(c2, 1.4f));
                    Prim(PrimitiveType.Sphere, pivot, at + new Vector3(0, 0, -0.1f), Vector3.one * 0.1f, Mats.Neon(new Color(1f, 0.3f, 0.3f), 4f));
                    break;
                case "adware":
                    Prim(PrimitiveType.Cube, pivot, at, new Vector3(0.26f, 0.18f, 0.02f), Mats.Neon(c2, 1.8f));
                    break;
                case "rootkit":
                    Prim(PrimitiveType.Capsule, pivot, at, new Vector3(0.14f, 0.12f, 0.14f), Mats.Plastic(new Color(0.06f, 0.05f, 0.1f)));
                    Prim(PrimitiveType.Sphere, pivot, at + new Vector3(0, 0.05f, -0.06f), Vector3.one * 0.06f, Mats.Neon(c2, 3f));
                    break;
                case "botnet":
                    Prim(PrimitiveType.Sphere, pivot, at, Vector3.one * 0.18f, Mats.Neon(c2, 2.6f));
                    Prim(PrimitiveType.Sphere, pivot, at + new Vector3(0.16f, 0.08f, 0), Vector3.one * 0.1f, Mats.Neon(c2, 2.6f));
                    break;
                default:
                    Prim(PrimitiveType.Sphere, pivot, at, Vector3.one * 0.16f, Mats.Neon(c2, 2.4f));
                    break;
            }
        }
    }

    // дыхание, вращение колец и волна хвоста — вся анимация скина
    public class VirusModelAnim : MonoBehaviour
    {
        public Transform breath;
        public readonly List<(Transform t, Vector3 axis, float speed)> spins = new();
        public readonly List<(Transform t, float phase)> wiggles = new();
        float _t;

        void Update()
        {
            _t += Time.deltaTime;
            if (breath != null)
            {
                float k = 1f + Mathf.Sin(_t * 2.2f) * 0.03f;
                breath.localScale = new Vector3(k, 2f - k, k);
            }
            foreach (var (tr, axis, speed) in spins)
                if (tr != null) tr.Rotate(axis, speed * Time.deltaTime, Space.Self);
            foreach (var (tr, phase) in wiggles)
                if (tr != null)
                {
                    var p = tr.localPosition;
                    p.x = Mathf.Sin(_t * 3.4f + phase) * 0.08f;
                    tr.localPosition = p;
                }
        }
    }
}
