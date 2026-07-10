using System.Collections.Generic;
using UnityEngine;
using Virus.Core;
using Virus.Util;

namespace Virus.Player
{
    // Процедурные скины вирусов (полный редизайн). Рецепт «второго поколения»:
    // тёмный глянцевый корпус (PBR) + цветной эмиссив только в акцентах
    // (ядро, швы, глаза) — силуэт читается светом, а не сплошным неоном.
    // stage (0..3) наращивает броню/детали, на УР.3 — венец апекса,
    // доп. ветка примешивает орбитальную эмблему. Вся анимация — VirusModelAnim.
    public static class VirusModel
    {
        // корпусные материалы: тёмный панцирь и матовая «кость»
        static Material Shell(Color tint) =>
            Mats.Metal(new Color(tint.r * 0.16f + 0.05f, tint.g * 0.16f + 0.05f, tint.b * 0.16f + 0.07f), 0.35f);

        static Material ShellMatte(Color tint) =>
            Mats.Plastic(new Color(tint.r * 0.12f + 0.04f, tint.g * 0.12f + 0.04f, tint.b * 0.12f + 0.06f));

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

            // свет штамма — мягкий, чтобы модель не «горела»
            var l = new GameObject("glow").AddComponent<Light>();
            l.transform.SetParent(root.transform, false);
            l.transform.localPosition = new Vector3(0, 1.2f, 0);
            l.type = LightType.Point;
            l.color = color;
            l.intensity = 0.9f;
            l.range = 4.5f;
            return root;
        }

        // «баг»: глючный краб с мерцающим панцирем — форма игрока при 0 HP
        public static GameObject BuildBug(Transform parent, Color color)
        {
            var root = new GameObject("BugModel");
            root.transform.SetParent(parent, false);
            var anim = root.AddComponent<VirusModelAnim>();
            var shellM = ShellMatte(color);
            var body = Prim(PrimitiveType.Cube, root.transform, new Vector3(0, 0.32f, 0),
                new Vector3(0.52f, 0.28f, 0.44f), shellM);
            anim.breath = body.transform;
            // трещины панциря светятся и глитчуют
            var crack = Mats.Neon(new Color(1f, 0.35f, 0.4f), 2.2f);
            anim.flickers.Add(crack);
            Prim(PrimitiveType.Cube, root.transform, new Vector3(0.1f, 0.42f, 0), new Vector3(0.34f, 0.03f, 0.46f), crack);
            Prim(PrimitiveType.Cube, root.transform, new Vector3(-0.12f, 0.36f, 0.1f), new Vector3(0.03f, 0.14f, 0.3f), crack);
            for (int side = -1; side <= 1; side += 2)
            {
                Prim(PrimitiveType.Sphere, root.transform, new Vector3(side * 0.13f, 0.5f, -0.2f),
                    Vector3.one * 0.15f, Mats.Neon(new Color(1f, 0.5f, 0.5f), 3f));
                for (int i = 0; i < 3; i++)
                {
                    var leg = Prim(PrimitiveType.Cube, root.transform,
                        new Vector3(side * 0.34f, 0.16f, -0.14f + 0.15f * i),
                        new Vector3(0.26f, 0.045f, 0.045f), shellM);
                    leg.transform.localRotation = Quaternion.Euler(0, 0, -32f * side);
                    anim.wiggles.Add((leg.transform, i * 1.3f + side));
                }
            }
            return root;
        }

        // ящик-маскировка трояна: неотличим от лут-ящика рейда
        public static GameObject BuildCrate(Transform parent)
        {
            var root = new GameObject("MorphCrate");
            root.transform.SetParent(parent, false);
            var c = new Color(0.29f, 0.56f, 1f);
            Prim(PrimitiveType.Cube, root.transform, new Vector3(0, 0.45f, 0),
                new Vector3(1.05f, 0.85f, 0.9f), Mats.Neon(c, 0.9f));
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

        // сегментное кольцо из «пластин» — техно-обруч вместо бус
        static Transform PlateRing(Transform parent, Vector3 pos, float radius, int count, Vector3 plate, Material m, float tiltX = 0f)
        {
            var pivot = new GameObject("plateRing").transform;
            pivot.SetParent(parent, false);
            pivot.localPosition = pos;
            pivot.localRotation = Quaternion.Euler(tiltX, 0, 0);
            for (int i = 0; i < count; i++)
            {
                float a = Mathf.PI * 2f * i / count;
                var p = Prim(PrimitiveType.Cube, pivot, new Vector3(Mathf.Cos(a) * radius, 0, Mathf.Sin(a) * radius), plate, m);
                p.transform.localRotation = Quaternion.Euler(0, -a * Mathf.Rad2Deg, 0);
            }
            return pivot;
        }

        static void Spike(Transform parent, Vector3 center, Vector3 dir, float len, Material m, Material tipM)
        {
            var sp = Prim(PrimitiveType.Capsule, parent, center + dir * (0.42f + len * 0.4f),
                new Vector3(len * 0.3f, len * 0.5f, len * 0.3f), m);
            sp.transform.up = dir;
            Prim(PrimitiveType.Sphere, parent, center + dir * (0.42f + len * 0.95f),
                Vector3.one * len * 0.26f, tipM);
        }

        static void Eyes(Transform parent, Vector3 at, float r, Color c)
        {
            for (int side = -1; side <= 1; side += 2)
            {
                // тёмная глазница + яркий зрачок: взгляд читается издалека
                Prim(PrimitiveType.Sphere, parent, at + new Vector3(side * 0.15f, 0, 0.015f),
                    Vector3.one * r * 2.8f, ShellMatte(c));
                Prim(PrimitiveType.Sphere, parent, at + new Vector3(side * 0.15f, 0, -0.02f),
                    Vector3.one * r * 1.8f, Mats.Neon(Color.Lerp(Color.white, c, 0.2f), 3.5f));
            }
        }

        // ── БАЗОВЫЙ ПРОТО-ШТАММ: тёмная капсула-зонд с ярким ядром ──
        static void BuildBase(Transform t, VirusModelAnim anim, Color c)
        {
            var core = new GameObject("core").transform;
            core.SetParent(t, false);
            core.localPosition = new Vector3(0, 0.95f, 0);
            anim.breath = core;
            anim.bob = core;
            // корпус из двух получаш: тёмный панцирь со светящимся швом экватора
            Prim(PrimitiveType.Sphere, core, new Vector3(0, 0.12f, 0), new Vector3(0.78f, 0.56f, 0.78f), Shell(c));
            Prim(PrimitiveType.Sphere, core, new Vector3(0, -0.12f, 0), new Vector3(0.72f, 0.5f, 0.72f), Shell(c));
            // видимый шов: сегментное светящееся кольцо ПОВЕРХ панциря
            PlateRing(core, Vector3.zero, 0.37f, 14, new Vector3(0.1f, 0.05f, 0.03f), Mats.Neon(c, 2.6f));
            Eyes(core, new Vector3(0, 0.14f, -0.32f), 0.07f, c);
            // техно-обруч из тёмных пластин на орбите
            var halo = PlateRing(core, Vector3.zero, 0.54f, 9, new Vector3(0.14f, 0.07f, 0.04f), Shell(c));
            anim.spins.Add((halo, Vector3.up, 40f));
            // три светящиеся «линзы» на верхней чаше
            for (int i = 0; i < 3; i++)
            {
                float a = Mathf.PI * 2f * i / 3f + 0.5f;
                Prim(PrimitiveType.Sphere, core, new Vector3(Mathf.Cos(a) * 0.26f, 0.28f, Mathf.Sin(a) * 0.26f),
                    Vector3.one * 0.11f, Mats.Neon(c, 3f));
            }
        }

        // ── ЧЕРВЬ: бронированный бур-паразит, вздыбленный S-дугой ──
        static void BuildWorm(Transform t, VirusModelAnim anim, Color c, int stage)
        {
            var shell = Shell(c);
            var head = new GameObject("head").transform;
            head.SetParent(t, false);
            head.localPosition = new Vector3(0, 1.05f, -0.15f);
            anim.breath = head;
            // голова: тёмный купол + светящаяся пасть-воронка
            Prim(PrimitiveType.Sphere, head, Vector3.zero, new Vector3(0.62f, 0.58f, 0.62f), shell);
            PlateRing(head, new Vector3(0, 0.02f, 0), 0.33f, 8, new Vector3(0.16f, 0.1f, 0.05f), shell, 80f);
            Prim(PrimitiveType.Sphere, head, new Vector3(0, 0, -0.28f), Vector3.one * 0.3f, Mats.Neon(c, 2.4f));
            // вращающийся бур из трёх лопастей
            var drill = new GameObject("drill").transform;
            drill.SetParent(head, false);
            drill.localPosition = new Vector3(0, 0, -0.46f);
            for (int k = 0; k < 3; k++)
            {
                var blade = Prim(PrimitiveType.Cube, drill, Vector3.zero, new Vector3(0.07f, 0.34f, 0.2f),
                    Mats.Metal(new Color(0.55f, 0.58f, 0.62f), 0.25f));
                blade.transform.localRotation = Quaternion.Euler(28, 0, k * 120f);
                blade.transform.localPosition = blade.transform.localRotation * new Vector3(0, 0.12f, -0.1f);
            }
            Prim(PrimitiveType.Sphere, drill, new Vector3(0, 0, -0.2f), Vector3.one * 0.14f,
                Mats.Neon(Color.Lerp(c, Color.white, 0.4f), 3.5f));
            anim.spins.Add((drill, Vector3.forward, 340f));
            Eyes(head, new Vector3(0, 0.2f, -0.24f), 0.06f, c);
            // сегменты тела: бронированные кольца по S-дуге, к хвосту тоньше
            int count = 5 + stage;
            for (int i = 0; i < count; i++)
            {
                float k = (float)i / count;
                float r = 0.3f - 0.05f * k * 3f * 0.33f - 0.02f * i * 0.5f;
                r = Mathf.Max(0.3f - 0.028f * i, 0.12f);
                var pos = new Vector3(Mathf.Sin(i * 0.55f) * 0.14f,
                    1.0f - Mathf.Sin(k * 1.9f) * 0.55f, 0.28f + 0.27f * i);
                var seg = Prim(PrimitiveType.Sphere, t, pos, Vector3.one * r * 2f, shell);
                // светящийся межсегментный зазор
                if (i > 0)
                    Prim(PrimitiveType.Sphere, t, Vector3.Lerp(pos, new Vector3(Mathf.Sin((i - 1) * 0.55f) * 0.14f,
                        1.0f - Mathf.Sin((i - 1f) / count * 1.9f) * 0.55f, 0.28f + 0.27f * (i - 1)), 0.5f),
                        Vector3.one * r * 1.5f, Mats.Neon(c, 1.3f));
                anim.wiggles.Add((seg.transform, i * 0.65f));
            }
        }

        // ── ТРОЯН: подарочный ящик-мимик с приоткрытой крышкой ──
        static void BuildTrojan(Transform t, VirusModelAnim anim, Color c, int stage)
        {
            var body = new GameObject("body").transform;
            body.SetParent(t, false);
            body.localPosition = new Vector3(0, 0.88f, 0);
            anim.breath = body;
            var shell = ShellMatte(c);
            Prim(PrimitiveType.Cube, body, Vector3.zero, new Vector3(0.74f, 0.8f, 0.62f), shell);
            // «подарочная лента» крест-накрест — фирменный обман
            Prim(PrimitiveType.Cube, body, Vector3.zero, new Vector3(0.78f, 0.14f, 0.66f), Mats.Neon(c, 1.2f));
            Prim(PrimitiveType.Cube, body, Vector3.zero, new Vector3(0.16f, 0.84f, 0.66f), Mats.Neon(c, 1.2f));
            // приоткрытая крышка, из щели льётся свет
            var lid = Prim(PrimitiveType.Cube, body, new Vector3(0, 0.46f, 0.06f), new Vector3(0.8f, 0.1f, 0.68f), shell);
            lid.transform.localRotation = Quaternion.Euler(-9f, 0, 0);
            Prim(PrimitiveType.Cube, body, new Vector3(0, 0.42f, -0.02f), new Vector3(0.7f, 0.045f, 0.56f),
                Mats.Neon(Color.Lerp(c, Color.white, 0.35f), 3.2f));
            // глаза из щели-«рта»
            Prim(PrimitiveType.Cube, body, new Vector3(0, 0.12f, -0.325f), new Vector3(0.46f, 0.1f, 0.03f), Mats.Neon(c, 0.6f));
            Eyes(body, new Vector3(0, 0.13f, -0.33f), 0.055f, c);
            // лапки-защёлки по бокам
            for (int side = -1; side <= 1; side += 2)
                for (int i = 0; i < 2; i++)
                {
                    var claw = Prim(PrimitiveType.Cube, body, new Vector3(side * 0.42f, -0.18f + i * 0.28f, -0.05f),
                        new Vector3(0.07f, 0.2f, 0.12f), Shell(c));
                    claw.transform.localRotation = Quaternion.Euler(0, 0, side * 12f);
                }
            if (stage >= 2)   // сургучная печать и цепочка «сертификатов»
            {
                Prim(PrimitiveType.Sphere, body, new Vector3(0.22f, 0.02f, -0.34f), Vector3.one * 0.16f, Mats.Neon(new Color(1f, 0.4f, 0.35f), 2f));
                var tags = Ring(body, new Vector3(0, -0.46f, 0), 0.5f, 6, 0.045f, Mats.Neon(c, 1.4f));
                anim.spins.Add((tags, Vector3.up, 38f));
            }
        }

        // ── RANSOMWARE: кованый замок-танк на цепях ──
        static void BuildRansomware(Transform t, VirusModelAnim anim, Color c, int stage)
        {
            var body = new GameObject("body").transform;
            body.SetParent(t, false);
            body.localPosition = new Vector3(0, 0.82f, 0);
            anim.breath = body;
            var iron = Mats.Metal(new Color(0.14f, 0.1f, 0.14f), 0.45f);
            var steel = Mats.Metal(new Color(0.5f, 0.5f, 0.56f), 0.25f);
            // корпус с фасками (три слоя) — читается как кованый
            Prim(PrimitiveType.Cube, body, Vector3.zero, new Vector3(0.88f, 0.76f, 0.56f), iron);
            Prim(PrimitiveType.Cube, body, new Vector3(0, 0, -0.02f), new Vector3(0.78f, 0.66f, 0.58f), iron);
            Prim(PrimitiveType.Cube, body, new Vector3(0, 0.3f, 0), new Vector3(0.92f, 0.12f, 0.6f), steel);
            Prim(PrimitiveType.Cube, body, new Vector3(0, -0.32f, 0), new Vector3(0.92f, 0.12f, 0.6f), steel);
            // дужка из капсул — гладкая арка
            for (int i = 0; i <= 8; i++)
            {
                float a = Mathf.PI * i / 8f;
                var seg = Prim(PrimitiveType.Capsule, body,
                    new Vector3(Mathf.Cos(a) * 0.3f, 0.42f + Mathf.Sin(a) * 0.3f, 0),
                    new Vector3(0.1f, 0.09f, 0.1f), steel);
                seg.transform.localRotation = Quaternion.Euler(0, 0, a * Mathf.Rad2Deg + 90f);
            }
            // скважина: светится и «дышит» (медленный пульс)
            var hole = Mats.Neon(c, 3f);
            anim.pulses.Add((hole, c * 3f));
            Prim(PrimitiveType.Sphere, body, new Vector3(0, 0.06f, -0.3f), Vector3.one * 0.17f, hole);
            Prim(PrimitiveType.Cube, body, new Vector3(0, -0.1f, -0.3f), new Vector3(0.06f, 0.2f, 0.04f), hole);
            // заклёпки по периметру лицевой панели
            for (int sx = -1; sx <= 1; sx += 2)
                for (int sy = -1; sy <= 1; sy += 2)
                    Prim(PrimitiveType.Sphere, body, new Vector3(sx * 0.35f, sy * 0.27f, -0.3f),
                        Vector3.one * 0.07f, steel);
            Eyes(body, new Vector3(0, 0.28f, -0.31f), 0.05f, c);
            if (stage >= 2)   // провисающие цепи по бокам
                for (int side = -1; side <= 1; side += 2)
                    for (int i = 0; i < 4; i++)
                        Prim(PrimitiveType.Sphere, body,
                            new Vector3(side * (0.48f + Mathf.Sin(i * 1.1f) * 0.05f), 0.3f - i * 0.2f, 0.05f),
                            Vector3.one * 0.1f, steel);
        }

        // ── SPYWARE: дрон-глаз с диафрагмой и антеннами ──
        static void BuildSpyware(Transform t, VirusModelAnim anim, Color c, int stage)
        {
            var eye = new GameObject("eye").transform;
            eye.SetParent(t, false);
            eye.localPosition = new Vector3(0, 1.1f, 0);
            anim.breath = eye;
            anim.bob = eye;
            // тёмный кожух, белок, радужка, красный зрачок
            Prim(PrimitiveType.Sphere, eye, Vector3.zero, Vector3.one * 0.66f, Shell(c));
            Prim(PrimitiveType.Sphere, eye, new Vector3(0, 0, -0.2f), Vector3.one * 0.42f, Mats.Plastic(new Color(0.85f, 0.88f, 0.9f)));
            Prim(PrimitiveType.Sphere, eye, new Vector3(0, 0, -0.31f), Vector3.one * 0.22f, Mats.Neon(c, 1.8f));
            Prim(PrimitiveType.Sphere, eye, new Vector3(0, 0, -0.37f), Vector3.one * 0.1f, Mats.Neon(new Color(1f, 0.25f, 0.25f), 4.5f));
            // лепестки диафрагмы вокруг линзы
            var iris = new GameObject("iris").transform;
            iris.SetParent(eye, false);
            iris.localPosition = new Vector3(0, 0, -0.3f);
            for (int i = 0; i < 6; i++)
            {
                float a = Mathf.PI * 2f * i / 6f;
                var petal = Prim(PrimitiveType.Cube, iris,
                    new Vector3(Mathf.Cos(a) * 0.22f, Mathf.Sin(a) * 0.22f, 0),
                    new Vector3(0.12f, 0.04f, 0.03f), Shell(c));
                petal.transform.localRotation = Quaternion.Euler(0, 0, a * Mathf.Rad2Deg + 90f);
            }
            anim.spins.Add((iris, Vector3.forward, -30f));
            // антенны и стабилизаторы
            int stalks = 3 + stage;
            for (int i = 0; i < stalks; i++)
            {
                float a = Mathf.PI * 2f * i / stalks;
                var dir = new Vector3(Mathf.Cos(a), 1f, Mathf.Sin(a)).normalized;
                Spike(eye, Vector3.zero, dir, 0.3f, Shell(c), Mats.Neon(new Color(1f, 0.35f, 0.3f), 2.6f));
            }
            var gyro = PlateRing(eye, Vector3.zero, 0.52f, 10, new Vector3(0.14f, 0.04f, 0.04f), Shell(c), 18f);
            anim.spins.Add((gyro, Vector3.up, 85f));
        }

        // ── ADWARE: ядро-«приманка» в вихре неоновых баннеров ──
        static void BuildAdware(Transform t, VirusModelAnim anim, Color c, int stage)
        {
            var core = new GameObject("core").transform;
            core.SetParent(t, false);
            core.localPosition = new Vector3(0, 0.95f, 0);
            anim.breath = core;
            anim.bob = core;
            Prim(PrimitiveType.Sphere, core, Vector3.zero, Vector3.one * 0.52f, Shell(c));
            Prim(PrimitiveType.Cube, core, Vector3.zero, new Vector3(0.56f, 0.05f, 0.56f), Mats.Neon(c, 2.2f));
            Eyes(core, new Vector3(0, 0.08f, -0.24f), 0.06f, c);
            // два встречных вихря панелей: разные размеры, цвет чередуется
            var c2 = Color.Lerp(c, new Color(1f, 0.5f, 0.2f), 0.5f);
            var rng = new System.Random(11);
            for (int layer = 0; layer < 2; layer++)
            {
                var pivot = new GameObject("popups" + layer).transform;
                pivot.SetParent(core, false);
                pivot.localRotation = Quaternion.Euler(layer * 14f, 0, -layer * 10f);
                int n = 3 + stage + layer * 2;
                for (int i = 0; i < n; i++)
                {
                    float a = Mathf.PI * 2f * i / n;
                    float rr = 0.55f + layer * 0.24f;
                    var p = new Vector3(Mathf.Cos(a) * rr, (float)rng.NextDouble() * 0.6f - 0.22f, Mathf.Sin(a) * rr);
                    float w = 0.2f + (float)rng.NextDouble() * 0.14f;
                    var col = i % 2 == 0 ? c : c2;
                    var panel = Prim(PrimitiveType.Cube, pivot, p, new Vector3(w, w * 0.68f, 0.02f), Mats.Neon(col, 1.7f));
                    panel.transform.localRotation = Quaternion.Euler(0, -a * Mathf.Rad2Deg + 90f, 0);
                    // рамка и крестик закрытия
                    Prim(PrimitiveType.Cube, panel.transform, new Vector3(0, 0.56f, 0), new Vector3(1.04f, 0.14f, 0.5f), ShellMatte(col));
                    Prim(PrimitiveType.Cube, panel.transform, new Vector3(0.42f, 0.56f, -0.3f),
                        new Vector3(0.15f, 0.12f, 0.3f), Mats.Neon(new Color(1f, 0.3f, 0.3f), 2.6f));
                }
                anim.spins.Add((pivot, Vector3.up, layer == 0 ? 36f : -24f));
            }
        }

        // ── ROOTKIT: бесплотный призрак — слоёная мантия и руки-фантомы ──
        static void BuildRootkit(Transform t, VirusModelAnim anim, Color c, int stage)
        {
            var body = new GameObject("body").transform;
            body.SetParent(t, false);
            body.localPosition = new Vector3(0, 0.95f, 0);
            anim.breath = body;
            anim.bob = body;
            var cloth = ShellMatte(c);
            // мантия из трёх сужающихся ярусов — рваный низ
            Prim(PrimitiveType.Capsule, body, new Vector3(0, 0.1f, 0), new Vector3(0.56f, 0.52f, 0.56f), cloth);
            Prim(PrimitiveType.Capsule, body, new Vector3(0, -0.28f, 0), new Vector3(0.66f, 0.4f, 0.66f), cloth);
            for (int i = 0; i < 7; i++)
            {
                float a = Mathf.PI * 2f * i / 7f;
                Prim(PrimitiveType.Cube, body,
                    new Vector3(Mathf.Cos(a) * 0.28f, -0.6f - (i % 2) * 0.08f, Mathf.Sin(a) * 0.28f),
                    new Vector3(0.14f, 0.22f, 0.1f), cloth);
            }
            // капюшон с провалом лица
            Prim(PrimitiveType.Sphere, body, new Vector3(0, 0.52f, 0.04f), new Vector3(0.48f, 0.42f, 0.48f), cloth);
            Prim(PrimitiveType.Sphere, body, new Vector3(0, 0.5f, -0.1f), new Vector3(0.34f, 0.3f, 0.3f), Mats.Plastic(new Color(0.01f, 0.01f, 0.02f)));
            Eyes(body, new Vector3(0, 0.52f, -0.2f), 0.05f, c);
            // парящие кисти рук
            foreach (var side in new[] { -1, 1 })
            {
                var hand = Prim(PrimitiveType.Sphere, body, new Vector3(side * 0.44f, -0.05f, -0.18f),
                    new Vector3(0.14f, 0.18f, 0.14f), cloth);
                anim.wiggles.Add((hand.transform, side * 1.7f));
                for (int f = 0; f < 3; f++)
                    Prim(PrimitiveType.Capsule, hand.transform, new Vector3((f - 1) * 0.3f, -0.5f, 0),
                        new Vector3(0.16f, 0.4f, 0.2f), cloth);
            }
            // кольцо тумана у пола
            var mist = Ring(body, new Vector3(0, -0.72f, 0), 0.4f, 12, 0.05f, Mats.Neon(c, 0.8f));
            anim.spins.Add((mist, Vector3.up, -22f));
            if (stage >= 2)
            {
                var runes = PlateRing(body, new Vector3(0, 0.12f, 0), 0.56f, 5, new Vector3(0.08f, 0.14f, 0.02f), Mats.Neon(c, 1.8f), 8f);
                anim.spins.Add((runes, Vector3.up, -46f));
            }
        }

        // ── BOTNET: ядро-оператор и рой дронов-пирамидок на двух орбитах ──
        static void BuildBotnet(Transform t, VirusModelAnim anim, Color c, int stage)
        {
            var core = new GameObject("core").transform;
            core.SetParent(t, false);
            core.localPosition = new Vector3(0, 0.95f, 0);
            anim.breath = core;
            anim.bob = core;
            // ядро: тёмный октаэдр (куб на угол) со светящимися гранями
            var hub = Prim(PrimitiveType.Cube, core, Vector3.zero, Vector3.one * 0.44f, Shell(c));
            hub.transform.localRotation = Quaternion.Euler(45, 0, 45);
            Prim(PrimitiveType.Cube, core, Vector3.zero, Vector3.one * 0.3f, Mats.Neon(c, 2.8f)).transform.localRotation = Quaternion.Euler(45, 0, 45);
            Eyes(core, new Vector3(0, 0.05f, -0.3f), 0.055f, c);
            // две встречные орбиты дронов
            for (int layer = 0; layer < 2; layer++)
            {
                var swarm = new GameObject("swarm" + layer).transform;
                swarm.SetParent(core, false);
                swarm.localRotation = Quaternion.Euler(layer == 0 ? 12f : -18f, 0, layer * 9f);
                int n = 3 + stage + layer;
                for (int i = 0; i < n; i++)
                {
                    float a = Mathf.PI * 2f * i / n;
                    float rr = 0.62f + layer * 0.2f;
                    var p = new Vector3(Mathf.Cos(a) * rr, Mathf.Sin(a * 2f) * 0.14f, Mathf.Sin(a) * rr);
                    var drone = Prim(PrimitiveType.Cube, swarm, p, Vector3.one * 0.13f, Shell(c));
                    drone.transform.localRotation = Quaternion.Euler(45, -a * Mathf.Rad2Deg, 45);
                    Prim(PrimitiveType.Sphere, drone.transform, Vector3.zero, Vector3.one * 0.6f, Mats.Neon(c, 2.4f));
                }
                anim.spins.Add((swarm, Vector3.up, layer == 0 ? 68f : -44f));
            }
        }

        // ── УР.3: венец апекса поверх любого скина ──
        static void AddApexCrown(Transform t, VirusModelAnim anim, Color c)
        {
            var bright = Color.Lerp(c, Color.white, 0.35f);
            var crown = PlateRing(t, new Vector3(0, 2.25f, 0), 0.36f, 7, new Vector3(0.07f, 0.2f, 0.03f), Mats.Neon(bright, 3f), 6f);
            anim.spins.Add((crown, Vector3.up, 140f));
            for (int i = 0; i < 3; i++)
            {
                float ang = Mathf.PI * 2f * i / 3f;
                var shard = Prim(PrimitiveType.Capsule, t,
                    new Vector3(Mathf.Cos(ang) * 0.34f, 2.46f, Mathf.Sin(ang) * 0.34f),
                    new Vector3(0.06f, 0.13f, 0.06f), Mats.Neon(c, 2.6f));
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

    // Анимация скина: дыхание, парение, вращение колец, волна хвоста,
    // пульс эмиссива и глитч-мерцание (баг).
    public class VirusModelAnim : MonoBehaviour
    {
        public Transform breath;                 // масштабное «дыхание»
        public Transform bob;                    // вертикальное парение
        public readonly List<(Transform t, Vector3 axis, float speed)> spins = new();
        public readonly List<(Transform t, float phase)> wiggles = new();
        public readonly List<(Material m, Color baseEmission)> pulses = new();   // медленный пульс
        public readonly List<Material> flickers = new();                          // резкий глитч (баг)
        float _t;
        Vector3 _bobBase;
        bool _bobInit;

        void Update()
        {
            _t += Time.deltaTime;
            if (breath != null)
            {
                float k = 1f + Mathf.Sin(_t * 2.2f) * 0.03f;
                breath.localScale = new Vector3(k, 2f - k, k);
            }
            if (bob != null)
            {
                if (!_bobInit) { _bobBase = bob.localPosition; _bobInit = true; }
                bob.localPosition = _bobBase + Vector3.up * (Mathf.Sin(_t * 1.7f) * 0.05f);
            }
            foreach (var (tr, axis, speed) in spins)
                if (tr != null) tr.Rotate(axis, speed * Time.deltaTime, Space.Self);
            foreach (var (tr, phase) in wiggles)
                if (tr != null)
                {
                    var p = tr.localPosition;
                    p.x += (Mathf.Sin(_t * 3.4f + phase) * 0.08f - p.x) * 0.5f;
                    tr.localPosition = p;
                }
            if (pulses.Count > 0)
            {
                float pk = 0.75f + 0.25f * Mathf.Sin(_t * 3f);
                foreach (var (m, baseEm) in pulses)
                    if (m != null) m.SetColor("_EmissionColor", baseEm * pk);
            }
            if (flickers.Count > 0)
            {
                float fk = Mathf.PerlinNoise(_t * 14f, 0.3f) > 0.55f ? 1f : 0.25f;
                foreach (var m in flickers)
                    if (m != null) m.SetColor("_EmissionColor", new Color(1f, 0.35f, 0.4f) * (2.2f * fk));
            }
        }
    }
}
