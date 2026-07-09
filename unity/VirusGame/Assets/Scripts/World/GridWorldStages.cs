using System.Collections.Generic;
using UnityEngine;
using Virus.Core;
using Virus.Util;

namespace Virus.World
{
    // Этапы Грида: туннели с энерго-барьерами, обучение (этап 0),
    // ночной мегаполис (1), затхлые офисы (2), бункер (3).
    public partial class GridWorld
    {
        readonly List<Light> _s3Lights = new();

        // ── туннели между этапами ──
        void BuildTunnels()
        {
            foreach (var t in GridData.TUNNELS)
            {
                float w = t.x1 - t.x0, cx = (t.x0 + t.x1) * 0.5f, cz = (t.zs + t.zn) * 0.5f, d = t.zs - t.zn;
                const float h = 5f;
                var mat = Mats.MetalDark(0.55f);
                Build.Solid(transform, new Vector3(w, 0.5f, d), Mats.DeckMetal(new Color(0.3f, 0.32f, 0.35f)), new Vector3(cx, -0.25f, cz));
                WallEW(t.zs, t.zn, t.x0 + WallT * 0.5f, h, mat, null);
                WallEW(t.zs, t.zn, t.x1 - WallT * 0.5f, h, mat, null);
                Build.Solid(transform, new Vector3(w, 0.35f, d), mat, new Vector3(cx, h + 0.175f, cz));
                for (int i = 1; i <= 3; i++)
                {
                    float rz = t.zs - d / 4f * i;
                    Build.Omni(transform, new Vector3(cx, h - 0.8f, rz), new Color(0.55f, 0.75f, 0.95f), 1.1f, 7f);
                }
                BuildStageGate(t);
                foreach (var dd in t.doors)
                    MakeDoor(new GridData.DoorDef(dd.key, "", "", 0, w - WallT * 2f, dd.diff, t.key == "t3o", dd.opz),
                        new Vector3(cx, 0, dd.z), "x", Mats.Rust());
                Build.Label(transform, $"ТУННЕЛЬ С ГОЛОВОЛОМКАМИ\n{t.to}", new Vector3(cx, 3.6f, t.zs - 2.6f), 2.8f, new Color(0.55f, 0.75f, 0.95f));
            }
        }

        void BuildStageGate(GridData.Tunnel t)
        {
            bool done = S.ZoneComplete(t.gateZone);
            float cx = (t.x0 + t.x1) * 0.5f, gw = t.x1 - t.x0 - WallT * 2f, gz = t.zs - 1.6f;
            var col = t.key == "t3o" ? GameData.ORACLE : new Color(0.2f, 0.55f, 1f);
            var pane = Build.MeshBox(transform, new Vector3(gw, DoorH, 0.3f), Mats.Neon(col, done ? 0.25f : 0.9f), new Vector3(cx, DoorH * 0.5f, gz));
            if (done) pane.transform.localScale = new Vector3(gw, 0.3f, 0.3f);  // открытый барьер — тонкая планка сверху
            Build.Omni(transform, new Vector3(cx, 3f, gz + 2f), col, 1.8f, 10f);
            if (!done) Build.Collide(transform, new Vector3(gw, DoorH, 0.4f), new Vector3(cx, DoorH * 0.5f, gz));
            string status = done ? "ПРОХОД ОТКРЫТ" :
                t.key == "t3o" ? $"ЗАБЛОКИРОВАНО: активируйте 28 серверов ({S.FacilityInfected()}/28)"
                               : $"ЗАБЛОКИРОВАНО: серверы этапа {S.ZoneInfected(t.gateZone)}/{S.ZoneTotal(t.gateZone)}";
            Build.Label(transform, status, new Vector3(cx, DoorH + 1.3f, gz + 0.6f), 3f, done ? GameData.INFECTED : col);
        }

        // ── этап 0: обучающий ангар ──
        void BuildStage0()
        {
            Build.Label(transform, "ТРЕНИРОВОЧНЫЙ ГРИД", new Vector3(0, 4.6f, 38.4f), 6f, new Color(0.7f, 0.9f, 1f), false);
            Build.Label(transform, "захвати 3 сервера — открой дверь на 1 уровень", new Vector3(0, 3.2f, 38.4f), 2.6f, GameData.INFECTED, false);
            Build.Label(transform, "WASD — движение · мышь — камера · ПРОБЕЛ — прыжок · Shift — бег", new Vector3(0, 2.3f, 38.4f), 2f, new Color(0.5f, 0.68f, 0.78f), false);

            Build.Label(transform, "УРОК 1 · подойди к серверу и жми [E]", new Vector3(0, 3.4f, 22f), 2.4f, GameData.INFECTED);

            // урок 2: отсек с дверью-головоломкой
            var part = Mats.Metal(new Color(0.4f, 0.42f, 0.46f), 0.5f);
            Build.Solid(transform, new Vector3(16, DoorH, WallT), part, new Vector3(-16, DoorH * 0.5f, 8));
            Build.Solid(transform, new Vector3(WallT, DoorH, 5.3f), part, new Vector3(-8, DoorH * 0.5f, 5.35f));
            Build.Solid(transform, new Vector3(WallT, DoorH, 5.3f), part, new Vector3(-8, DoorH * 0.5f, -3.35f));
            MakeDoor(new GridData.DoorDef("d_tut", "", "", 0, 3.4f, 1, false, ""), new Vector3(-8, 0, 1), "z", part);
            Build.Label(transform, "УРОК 2 · дверь заперта — реши головоломку [E]", new Vector3(-8, 3.6f, 4), 2.4f, new Color(1f, 0.7f, 0.35f));
            Build.Omni(transform, new Vector3(-16, 6, 0), new Color(0.85f, 0.92f, 1f), 2.2f, 16f);

            // урок 3: платформа + блок
            Build.Solid(transform, new Vector3(5, 2.6f, 5), Mats.DeckMetal(), new Vector3(14, 1.3f, 8));
            Build.MeshBox(transform, new Vector3(5.2f, 0.08f, 5.2f), Mats.Neon(GameData.TIER_COLORS[0], 0.8f), new Vector3(14, 2.65f, 8));
            Build.Label(transform, "УРОК 3 · поднеси блок [E], поставь и запрыгни", new Vector3(14, 4.4f, 8), 2.4f, new Color(0.8f, 0.9f, 1f));

            BuildBlocks();
            BuildTutorialExitGate();
        }

        void BuildTutorialExitGate()
        {
            bool done = S.ZoneComplete(0);
            const float gz = -6f, gw = 4f;
            var pane = Build.MeshBox(transform, new Vector3(gw, DoorH, 0.3f), Mats.Neon(new Color(0.25f, 0.6f, 1f), done ? 0.3f : 1.2f), new Vector3(0, DoorH * 0.5f, gz));
            if (done) pane.transform.localScale = new Vector3(gw, 0.3f, 0.3f);
            if (!done) Build.Collide(transform, new Vector3(gw, DoorH, 0.4f), new Vector3(0, DoorH * 0.5f, gz));
            Build.Omni(transform, new Vector3(0, 3, gz + 1.5f), new Color(0.25f, 0.6f, 1f), 1.8f, 10f);
            Build.Label(transform, done ? "ПРОХОД ОТКРЫТ · 1 УРОВЕНЬ" : $"ЗАБЛОКИРОВАНО: серверы {S.ZoneInfected(0)}/3",
                new Vector3(0, DoorH + 1.2f, gz + 0.6f), 3f, done ? GameData.INFECTED : new Color(0.5f, 0.8f, 1f));
        }

        // ── этап 1: ночной мегаполис ──
        void BuildStage1()
        {
            var rng = new System.Random(1001);
            float R(float a, float b) => Mathf.Lerp(a, b, (float)rng.NextDouble());

            // высотки с горящими окнами вокруг
            var spots = new Vector3[] {
                new(-32, 0, -12), new(-34, 0, -40), new(-20, 0, -64), new(6, 0, -72),
                new(28, 0, -74), new(62, 0, -68), new(72, 0, -42), new(68, 0, -14),
                new(48, 0, 6), new(22, 0, 12), new(-20, 0, 6),
            };
            for (int i = 0; i < spots.Length; i++)
            {
                float w = R(8, 14), h = R(24, 46);
                var win = Mats.Neon(new Color(0.85f, 0.75f, 0.5f), 0.35f);
                Build.MeshBox(transform, new Vector3(w, h, w), Mats.Plastic(new Color(0.06f, 0.07f, 0.1f)), spots[i] + Vector3.up * (h * 0.5f));
                // «окна» — светящиеся горизонтальные пояса
                for (float y = 3f; y < h - 2f; y += 4f)
                    Build.MeshBox(transform, new Vector3(w + 0.1f, 0.8f, w + 0.1f), win, spots[i] + Vector3.up * y);
            }

            // уличные фонари
            foreach (var lp in new Vector3[] { new(-6, 0, -16), new(6, 0, -36), new(16, 0, -32), new(30, 0, -50), new(48, 0, -30), new(24, 0, -38) })
            {
                Build.Solid(transform, new Vector3(0.22f, 5, 0.22f), Mats.MetalDark(0.6f), lp + new Vector3(0, 2.5f, 0));
                Build.MeshBox(transform, new Vector3(0.75f, 0.12f, 0.35f), Mats.Neon(new Color(1f, 0.85f, 0.55f), 3f), lp + new Vector3(0.55f, 4.9f, 0));
                Build.SpotDown(transform, lp + new Vector3(0.55f, 4.8f, 0), new Color(1f, 0.85f, 0.55f), 3.2f, 10f, 48f);
            }

            // неоновые вывески
            NeonSign("ГРИД-СИТИ", new Vector3(0, 6.5f, -43.2f), new Color(0.2f, 0.85f, 1f), 0f);
            NeonSign("24/7 DATA", new Vector3(8.4f, 5.4f, -30f), new Color(1f, 0.35f, 0.6f), -90f);
            NeonSign("НЕ-ХАКНИ", new Vector3(54.2f, 6.2f, -40f), new Color(1f, 0.7f, 0.2f), -90f);
            NeonSign("МЕГАПОЛИС", new Vector3(28f, 6.8f, -55.2f), new Color(0.55f, 0.4f, 1f), 0f);

            // платформа сервера этапа 1: строй лестницу из блоков
            Build.Solid(transform, new Vector3(6, 0.5f, 6), Mats.DeckMetal(), new Vector3(40, 4.25f, -46));
            for (int cx = -1; cx <= 1; cx += 2)
                for (int cz = -1; cz <= 1; cz += 2)
                    Build.Solid(transform, new Vector3(0.5f, 4, 0.5f), Mats.Metal(new Color(0.4f, 0.42f, 0.46f), 0.45f), new Vector3(40 + cx * 2.4f, 2, -46 + cz * 2.4f));
            Build.MeshBox(transform, new Vector3(6.2f, 0.08f, 6.2f), Mats.Neon(GameData.TIER_COLORS[0], 0.9f), new Vector3(40, 4.54f, -46));
            Build.Label(transform, "СЕРВЕР НА ВЫСОТЕ\nперенеси блоки [E] и выстрой лестницу", new Vector3(40, 7.2f, -46), 3f, GameData.TIER_COLORS[0]);

            Build.Label(transform, "СЕКРЕТНАЯ КОМНАТА", new Vector3(-15, 3.2f, -26), 2.6f, new Color(0.9f, 0.75f, 0.3f));
            Build.Label(transform, "СЕКРЕТНАЯ КОМНАТА", new Vector3(36, 3.2f, -20), 2.6f, new Color(0.9f, 0.75f, 0.3f));
        }

        void NeonSign(string text, Vector3 pos, Color color, float yawDeg)
        {
            var facing = Quaternion.Euler(0, yawDeg, 0) * Vector3.forward;
            var l = Build.Label(transform, text, pos + facing * 0.2f, 5f, color, false);
            l.transform.rotation = Quaternion.Euler(0, yawDeg + 180f, 0);   // TextMesh смотрит по -Z
            Build.Omni(transform, pos + facing * 1.2f, color, 1.3f, 7f);
        }

        // ── этап 2: затхлые офисы ──
        void BuildStage2()
        {
            var rng = new System.Random(2002);
            float R(float a, float b) => Mathf.Lerp(a, b, (float)rng.NextDouble());

            foreach (var roomKey in new[] { "c2", "d2" })
            {
                var r = GameData.ROOMS[roomKey];
                // кубиклы: перегородки, столы, мёртвые мониторы
                int rows = roomKey == "c2" ? 2 : 3;
                for (int row = 0; row < rows; row++)
                    for (int col = 0; col < 3; col++)
                    {
                        if (rng.NextDouble() < 0.2) continue;
                        var basePos = new Vector3(
                            Mathf.Lerp(r.x0 + 8, r.x1 - 8, (col + 0.5f) / 3f) + R(-2, 2), 0,
                            Mathf.Lerp(r.zs - 8, r.zn + 8, (row + 0.5f) / rows) + R(-2, 2));
                        var part = Mats.Plastic(new Color(0.3f, 0.32f, 0.3f));
                        Build.Solid(transform, new Vector3(5, 1.9f, 0.4f), part, basePos + new Vector3(0, 0.95f, -2.2f));
                        Build.Solid(transform, new Vector3(0.4f, 1.9f, 4.2f), part, basePos + new Vector3(-2.6f, 0.95f, 0));
                        Build.Solid(transform, new Vector3(3, 0.9f, 1.5f), Mats.PlasterOld(new Color(0.32f, 0.24f, 0.17f)), basePos + new Vector3(0.2f, 0.45f, -1.2f));
                        Build.MeshBox(transform, new Vector3(1.3f, 0.9f, 0.12f), Mats.Plastic(new Color(0.12f, 0.13f, 0.15f)), basePos + new Vector3(0.2f, 1.45f, -1.5f));
                    }
                // мох и лианы
                for (int i = 0; i < 7; i++)
                {
                    var mp = new Vector3(R(r.x0 + 2, r.x1 - 2), 0.03f, R(r.zn + 2, r.zs - 2));
                    Build.MeshBox(transform, new Vector3(R(1.2f, 3f), 0.06f, R(1.2f, 3f)), Mats.Moss(), mp);
                }
                for (int i = 0; i < 8; i++)
                {
                    float vl = R(1.5f, 4f);
                    Build.MeshBox(transform, new Vector3(0.1f, vl, 0.1f), Mats.Moss(new Color(0.16f, 0.28f, 0.1f)),
                        new Vector3(R(r.x0 + 3, r.x1 - 3), r.h - vl * 0.5f, R(r.zn + 3, r.zs - 3)));
                }
            }

            BuildCeils();

            // ярус d2 (Г-образные мостки, подъём лифтом)
            Build.Solid(transform, new Vector3(8, 0.5f, 44), Mats.DeckMetal(), new Vector3(74, 5.75f, -130));
            Build.Solid(transform, new Vector3(48, 0.5f, 8), Mats.DeckMetal(), new Vector3(102, 5.75f, -148));
            foreach (var cp in new Vector3[] { new(74, 0, -114), new(74, 0, -130), new(74, 0, -146), new(90, 0, -148), new(106, 0, -148), new(122, 0, -148) })
                Build.Solid(transform, new Vector3(0.6f, 5.5f, 0.6f), Mats.Metal(new Color(0.5f, 0.45f, 0.35f), 0.55f), cp + new Vector3(0, 2.75f, 0));
            Build.Solid(transform, new Vector3(0.15f, 1f, 12f), Mats.Metal(new Color(0.5f, 0.45f, 0.35f), 0.55f), new Vector3(78, 6.5f, -114));
            Build.Solid(transform, new Vector3(0.15f, 1f, 16f), Mats.Metal(new Color(0.5f, 0.45f, 0.35f), 0.55f), new Vector3(78, 6.5f, -134));
            Build.Solid(transform, new Vector3(48f, 1f, 0.15f), Mats.Metal(new Color(0.5f, 0.45f, 0.35f), 0.55f), new Vector3(102, 6.5f, -144));
            Build.Label(transform, "ЯРУС · подъём лифтом", new Vector3(80, 8.2f, -124), 2.8f, GameData.TIER_COLORS[1]);

            // питание лифта: 2 рычага + провод + роутер
            MakeLever("s2a", new Vector3(28, 0, -112), "РЫЧАГ ПИТАНИЯ А (лифт яруса)");
            MakeLever("s2b", new Vector3(122, 0, -148), "РЫЧАГ ПИТАНИЯ Б (лифт яруса)");
            MakeWire("s2", new Vector3[] { new(100, 0, -112), new(92, 0, -116), new(86, 0, -120), new(80, 0, -122) },
                new Color(0.95f, 0.6f, 0.2f), "КАБЕЛЬ К ЛИФТУ");
            MakeRouter("s2", new Vector3(124.4f, 0, -140));
            MakeLift(80, -124, 6.05f, "s2", "ЛИФТ ЯРУСА");

            Build.Label(transform, "СЕКРЕТНАЯ КОМНАТА", new Vector3(18, 3.2f, -94), 2.6f, new Color(0.9f, 0.75f, 0.3f));
            Build.Label(transform, "СЕКРЕТНАЯ КОМНАТА", new Vector3(132, 3.2f, -129), 2.6f, new Color(0.9f, 0.75f, 0.3f));
        }

        // ── этап 3: бункер ──
        void BuildStage3()
        {
            // аварийные красные лампы всегда; основной свет — от генераторов
            foreach (var roomKey in new[] { "e1", "e2", "e3", "e4" })
            {
                var r = GameData.ROOMS[roomKey];
                for (int i = 0; i < 2; i++)
                {
                    var ep = new Vector3(Mathf.Lerp(r.x0 + 4, r.x1 - 4, 0.25f + 0.5f * i), r.h - 1.2f, Mathf.Lerp(r.zs - 3, r.zn + 3, 0.3f + 0.4f * i));
                    Build.MeshBox(transform, new Vector3(0.4f, 0.2f, 0.4f), Mats.Neon(new Color(0.9f, 0.15f, 0.1f), 1.6f), ep);
                    Build.Omni(transform, ep + Vector3.down * 0.4f, new Color(0.9f, 0.18f, 0.12f), 0.6f, 9f);
                }
                for (int i = 0; i < 3; i++)
                {
                    var lp = new Vector3(Mathf.Lerp(r.x0 + 5, r.x1 - 5, (i + 0.5f) / 3f), r.h - 0.8f, (r.zs + r.zn) * 0.5f);
                    var sl = Build.SpotDown(transform, lp, new Color(0.8f, 0.9f, 1f), 3.2f, r.h + 3f);
                    sl.enabled = S.Stage3Powered();
                    _s3Lights.Add(sl);
                }
            }

            // щит питания + рубильник + 3 генератора с кабелями
            Build.MeshBox(transform, new Vector3(3.2f, 2.2f, 0.4f), Mats.Metal(new Color(0.5f, 0.45f, 0.3f), 0.5f), new Vector3(98, 1.6f, -177.8f));
            Build.Label(transform, "ЩИТ ПИТАНИЯ ЭТАПА 3\nпровода → генераторы → рубильник", new Vector3(98, 3.4f, -179), 2.6f, new Color(0.95f, 0.8f, 0.35f));
            MakeLever("s3master", new Vector3(102, 0, -179.5f), "ГЛАВНЫЙ РУБИЛЬНИК");
            MakeGenerator("g1", new Vector3(84, 0, -192));
            MakeGenerator("g2", new Vector3(104, 0, -200));
            MakeGenerator("g3", new Vector3(112, 0, -186));
            MakeWire("g1", new Vector3[] { new(96, 0, -182), new(90, 0, -186), new(86.5f, 0, -189) }, new Color(0.95f, 0.75f, 0.2f), "КАБЕЛЬ ГЕНЕРАТОРА 1");
            MakeWire("g2", new Vector3[] { new(100, 0, -184), new(102, 0, -190), new(103.5f, 0, -195.5f) }, new Color(0.95f, 0.75f, 0.2f), "КАБЕЛЬ ГЕНЕРАТОРА 2");
            MakeWire("g3", new Vector3[] { new(102, 0, -182), new(107, 0, -183.5f), new(110, 0, -184.5f) }, new Color(0.95f, 0.75f, 0.2f), "КАБЕЛЬ ГЕНЕРАТОРА 3");

            // верхний уступ e3 (2 сервера) + лифт
            Build.Solid(transform, new Vector3(32, 0.5f, 8), Mats.DeckMetal(), new Vector3(128, 5.75f, -260));
            foreach (var cp in new Vector3[] { new(114, 0, -258), new(128, 0, -258), new(142, 0, -258) })
                Build.Solid(transform, new Vector3(0.6f, 5.5f, 0.6f), Mats.Rust(), cp + new Vector3(0, 2.75f, 0));
            Build.Solid(transform, new Vector3(30, 1f, 0.15f), Mats.Metal(new Color(0.5f, 0.45f, 0.35f), 0.55f), new Vector3(129, 6.5f, -256));
            MakeLift(110, -260, 6.05f, "s3", "ЛИФТ УСТУПА");

            BuildBeams();

            // блок-отключатель ловушек + паркур + кнопка + зип
            bool off = S.Flag("traps_off");
            Build.Solid(transform, new Vector3(6, 6.5f, 6), Mats.BunkerWall(new Color(0.26f, 0.27f, 0.26f)), new Vector3(134, 3.25f, -252));
            Build.MeshBox(transform, new Vector3(6.2f, 0.3f, 6.2f), Mats.Hazard(), new Vector3(134, 6.55f, -252));
            Build.MeshBox(transform, new Vector3(0.6f, 0.5f, 0.6f), Mats.Neon(off ? GameData.INFECTED : new Color(1f, 0.2f, 0.15f), 2.2f), new Vector3(134, 7.2f, -252));
            Build.Label(transform, off ? "ЛОВУШКИ ОТКЛЮЧЕНЫ" : "БЛОК-ОТКЛЮЧАТЕЛЬ ЛОВУШЕК\n[E держать] на вершине",
                new Vector3(134, 9f, -252), 3f, off ? GameData.INFECTED : new Color(1f, 0.55f, 0.2f));
            var ov = MakeInteract(transform, new Vector3(134, 7f, -252), 3f);
            ov.holdSeconds = 1.5f;
            ov.prompt = "отключение ловушек…";
            ov.enabledFn = () => !S.Flag("traps_off");
            ov.onInteract = () => { S.SetFlag("traps_off"); _hud?.Toast("ВСЕ ЛОВУШКИ ЭТАПА 3 ОТКЛЮЧЕНЫ"); };

            // паркур к кнопке
            Build.Solid(transform, new Vector3(1.8f, 1.2f, 1.8f), Mats.Metal(new Color(0.34f, 0.36f, 0.32f), 0.6f), new Vector3(142.5f, 0.6f, -238));
            Build.Solid(transform, new Vector3(1.8f, 2.4f, 1.8f), Mats.Metal(new Color(0.34f, 0.36f, 0.32f), 0.6f), new Vector3(144.3f, 1.2f, -241));
            Build.Solid(transform, new Vector3(2.2f, 0.4f, 2.2f), Mats.DeckMetal(), new Vector3(144.3f, 3.2f, -244.5f));
            bool pressed = S.Flag("zip:e3");
            Build.MeshBox(transform, new Vector3(0.3f, 0.3f, 0.12f), Mats.Neon(pressed ? GameData.INFECTED : new Color(1f, 0.6f, 0.15f), 2f), new Vector3(144.3f, 4.1f, -245.3f));
            Build.Label(transform, pressed ? "ПРОВОД АКТИВЕН" : "КНОПКА ПЕРЕХОДА\n[E] активировать провод", new Vector3(144.3f, 5.3f, -244.5f), 2.4f,
                pressed ? GameData.INFECTED : new Color(1f, 0.7f, 0.35f));
            var btn = MakeInteract(transform, new Vector3(144.3f, 4.1f, -244.5f), 2.6f);
            btn.prompt = "[E] КНОПКА ПЕРЕХОДА: подать питание на провод";
            btn.enabledFn = () => !S.Flag("zip:e3");
            btn.onInteract = () =>
            {
                S.SetFlag("zip:e3");
                DrawZipByFlag("zip:e3");
                _hud?.Toast("ПРОВОД АКТИВЕН — лети к блоку-отключателю!");
            };
            MakeZip(new Vector3(144.3f, 5f, -244.5f), new Vector3(134, 7.4f, -252), "zip:e3");

            // красная тревога 28/28: маячки + надпись
            if (S.RedAlert())
            {
                foreach (var bp in new Vector3[] { new(96, 8.6f, -194), new(136, 7.6f, -211), new(122, 9.6f, -245), new(78, 7.6f, -247), new(122, 4.4f, -277) })
                {
                    Build.MeshBox(transform, new Vector3(0.5f, 0.3f, 0.5f), Mats.Neon(new Color(1f, 0.1f, 0.08f), 2.5f), bp);
                    _alertLights.Add(Build.Omni(transform, bp + Vector3.down * 0.6f, new Color(1f, 0.12f, 0.1f), 1.8f, 16f));
                }
                Build.Label(transform, "!! 28/28 СЕРВЕРОВ !!\nПРОТОКОЛ ВТОРЖЕНИЯ · ПУТЬ К ОРАКУЛУ ОТКРЫТ",
                    new Vector3(122, 6.5f, -268), 3.2f, new Color(1f, 0.25f, 0.2f));
            }
        }

        void ApplyStage3Power()
        {
            bool on = S.Stage3Powered();
            foreach (var sl in _s3Lights) if (sl != null) sl.enabled = on;
        }

        void TickAlert()
        {
            if (_alertLights.Count == 0) return;
            float pulse = 0.5f + 0.5f * Mathf.Sin(Time.time * 6f);
            foreach (var l in _alertLights) if (l != null) l.intensity = 0.4f + 2.2f * pulse;
        }
    }
}
