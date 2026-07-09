using System.Collections.Generic;
using UnityEngine;
using Virus.Core;
using Virus.Util;

namespace Virus.World
{
    // Порт grid_world.gd (каркас). Готово: окружение, комнаты со стенами и
    // проёмами, обучающий этап 0 (3 сервера + дверь на выход), серверы, вход в
    // сервер, заливающий свет. TODO-заглушки: провода/генераторы/лифты/ловушки/
    // блоки-физика/Оракул/зип-лайны — см. PORTING.md.
    public class GridWorld : MonoBehaviour
    {
        const float WallT = 1f, DoorH = 4f;

        struct Gap { public float c, w; public Gap(float c, float w) { this.c = c; this.w = w; } }
        static Dictionary<string, Dictionary<string, Gap[]>> _gaps;

        GameState S => GameState.I;
        Player.VirusPlayer _player;
        readonly Dictionary<int, Transform> _nodeVis = new();

        void Start()
        {
            BuildRoomGaps();
            BuildEnvironment();
            BuildRooms();
            LightRooms();
            BuildStage0();
            BuildNodes();
            SpawnPlayer();
        }

        // ── окружение: ночной город (луна, градиентный амбиент, скайбокс) ──
        void BuildEnvironment()
        {
            // качество: без этого большинство точечных ламп падают в vertex-lit
            QualitySettings.pixelLightCount = 10;
            QualitySettings.shadowDistance = 70f;
            QualitySettings.antiAliasing = 4;

            var sun = new GameObject("Moon").AddComponent<Light>();
            sun.type = LightType.Directional;
            sun.color = new Color(0.55f, 0.65f, 0.88f);
            sun.intensity = 0.65f;
            sun.transform.rotation = Quaternion.Euler(55, -35, 0);
            sun.shadows = LightShadows.Soft;
            sun.shadowStrength = 0.75f;

            // градиентный амбиент: небо/горизонт/земля — объёмнее плоского
            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Trilight;
            RenderSettings.ambientSkyColor = new Color(0.38f, 0.45f, 0.60f);
            RenderSettings.ambientEquatorColor = new Color(0.32f, 0.35f, 0.42f);
            RenderSettings.ambientGroundColor = new Color(0.14f, 0.15f, 0.18f);

            // ночное небо (если шейдер не попал в билд — останется solid color)
            var skyShader = Shader.Find("Skybox/Procedural");
            if (skyShader != null)
            {
                var sky = new Material(skyShader);
                sky.SetFloat("_SunSize", 0.025f);
                sky.SetFloat("_AtmosphereThickness", 0.5f);
                sky.SetFloat("_Exposure", 0.4f);
                sky.SetColor("_SkyTint", new Color(0.12f, 0.16f, 0.3f));
                sky.SetColor("_GroundColor", new Color(0.02f, 0.03f, 0.05f));
                RenderSettings.skybox = sky;
            }

            RenderSettings.fog = true;
            RenderSettings.fogColor = new Color(0.08f, 0.11f, 0.17f);
            RenderSettings.fogMode = FogMode.Exponential;
            RenderSettings.fogDensity = 0.0016f;
        }

        // ── стены с проёмами (порт _wall_ns / _wall_ew) ──
        void WallNS(float x0, float x1, float z, float h, Material mat, Gap[] gaps)
        {
            var list = new List<Gap>(gaps ?? new Gap[0]);
            list.Sort((a, b) => a.c.CompareTo(b.c));
            float cur = x0;
            foreach (var g in list)
            {
                float gx0 = g.c - g.w * 0.5f, gx1 = g.c + g.w * 0.5f;
                if (gx0 - cur > 0.05f) Build.Solid(transform, new Vector3(gx0 - cur, h, WallT), mat, new Vector3((cur + gx0) * 0.5f, h * 0.5f, z));
                if (h - DoorH > 0.05f) Build.Solid(transform, new Vector3(g.w, h - DoorH, WallT), mat, new Vector3(g.c, DoorH + (h - DoorH) * 0.5f, z));
                cur = gx1;
            }
            if (x1 - cur > 0.05f) Build.Solid(transform, new Vector3(x1 - cur, h, WallT), mat, new Vector3((cur + x1) * 0.5f, h * 0.5f, z));
        }

        void WallEW(float zs, float zn, float x, float h, Material mat, Gap[] gaps)
        {
            var list = new List<Gap>(gaps ?? new Gap[0]);
            list.Sort((a, b) => b.c.CompareTo(a.c));
            float cur = zs;
            foreach (var g in list)
            {
                float gz0 = g.c + g.w * 0.5f, gz1 = g.c - g.w * 0.5f;
                if (cur - gz0 > 0.05f) Build.Solid(transform, new Vector3(WallT, h, cur - gz0), mat, new Vector3(x, h * 0.5f, (cur + gz0) * 0.5f));
                if (h - DoorH > 0.05f) Build.Solid(transform, new Vector3(WallT, h - DoorH, g.w), mat, new Vector3(x, DoorH + (h - DoorH) * 0.5f, g.c));
                cur = gz1;
            }
            if (cur - zn > 0.05f) Build.Solid(transform, new Vector3(WallT, h, cur - zn), mat, new Vector3(x, h * 0.5f, (cur + zn) * 0.5f));
        }

        Material WallMat(int stage) => stage switch
        {
            0 => Mats.Concrete(new Color(0.38f,0.39f,0.42f)),
            1 => Mats.Brick(),
            2 => Mats.PlasterOld(),
            3 => Mats.BunkerWall(),
            _ => Mats.Obsidian(),
        };
        Material FloorMat(int stage) => stage switch
        {
            0 => Mats.Concrete(new Color(0.30f,0.31f,0.33f)),
            1 => Mats.Sidewalk(),
            2 => Mats.CarpetRot(),
            3 => Mats.Concrete(new Color(0.26f,0.27f,0.28f)),
            _ => Mats.Obsidian(),
        };

        void BuildRooms()
        {
            foreach (var kv in GameData.ROOMS)
            {
                var r = kv.Value;
                var wall = WallMat(r.stage);
                Build.Solid(transform, new Vector3(r.W, 0.5f, r.D), FloorMat(r.stage), new Vector3(r.Cx, -0.25f, r.Cz));
                var g = _gaps.TryGetValue(kv.Key, out var gg) ? gg : new Dictionary<string, Gap[]>();
                WallNS(r.x0, r.x1, r.zs - WallT * 0.5f, r.h, wall, g.GetValueOrDefault("s"));
                WallNS(r.x0, r.x1, r.zn + WallT * 0.5f, r.h, wall, g.GetValueOrDefault("n"));
                WallEW(r.zs, r.zn, r.x0 + WallT * 0.5f, r.h, wall, g.GetValueOrDefault("w"));
                WallEW(r.zs, r.zn, r.x1 - WallT * 0.5f, r.h, wall, g.GetValueOrDefault("e"));
                if (r.stage != 1 || r.secret)
                    Build.Solid(transform, new Vector3(r.W, 0.35f, r.D), wall, new Vector3(r.Cx, r.h + 0.175f, r.Cz));
            }
            // переход этап0→этап1
            var pass = Mats.Concrete(new Color(0.38f,0.39f,0.42f));
            Build.Solid(transform, new Vector3(4, 0.5f, 2), pass, new Vector3(0, -0.25f, -7));
            for (int s = -1; s <= 1; s += 2) Build.Solid(transform, new Vector3(WallT, DoorH, 2), pass, new Vector3(s * 2.5f, DoorH * 0.5f, -7));
        }

        // ── заливающий свет по закрытым комнатам ──
        void LightRooms()
        {
            foreach (var kv in GameData.ROOMS)
            {
                var r = kv.Value;
                if (r.stage == 1 && !r.secret) continue;
                Color col = r.stage switch { 0 => new Color(0.85f,0.92f,1f), 2 => new Color(0.95f,0.85f,0.65f),
                    3 => new Color(0.7f,0.82f,1f), 4 => new Color(0.55f,0.7f,1f), _ => new Color(0.8f,0.86f,0.95f) };
                float energy = r.stage == 0 ? 2.4f : 1.7f;
                int nx = Mathf.Clamp((int)(r.W / 18f), 1, 4), nz = Mathf.Clamp((int)(r.D / 18f), 1, 4);
                for (int ix = 0; ix < nx; ix++)
                    for (int iz = 0; iz < nz; iz++)
                    {
                        float lx = Mathf.Lerp(r.x0 + 4, r.x1 - 4, (ix + 0.5f) / nx);
                        float lz = Mathf.Lerp(r.zs - 4, r.zn + 4, (iz + 0.5f) / nz);
                        Build.Omni(transform, new Vector3(lx, r.h - 0.7f, lz), col, energy, Mathf.Max(r.h, 9f) + 8f);
                    }
            }
        }

        // ── обучающий этап 0 ──
        void BuildStage0()
        {
            Build.Label(transform, "ТРЕНИРОВОЧНЫЙ ГРИД", new Vector3(0, 4.4f, 38.4f), 6, new Color(0.7f,0.9f,1f), false);
            Build.Label(transform, "захвати 3 сервера — открой дверь на 1 уровень", new Vector3(0, 3f, 38.4f), 2.6f, GameData.INFECTED, false);

            // урок 2: отсек с дверью-головоломкой
            var part = Mats.Metal(new Color(0.4f,0.42f,0.46f), 0.5f);
            Build.Solid(transform, new Vector3(16, DoorH, WallT), part, new Vector3(-16, DoorH * 0.5f, 8));
            Build.Solid(transform, new Vector3(WallT, DoorH, 5.3f), part, new Vector3(-8, DoorH * 0.5f, 5.35f));
            Build.Solid(transform, new Vector3(WallT, DoorH, 5.3f), part, new Vector3(-8, DoorH * 0.5f, -3.35f));
            MakeDoor("d_tut", new Vector3(-8, 0, 1), 3.4f, "z", part);
            Build.Omni(transform, new Vector3(-16, 6, 0), new Color(0.85f,0.92f,1f), 2.2f, 16f);

            // урок 3: платформа под сервер (блок-механику см. PORTING.md)
            Build.Solid(transform, new Vector3(5, 2.6f, 5), Mats.DeckMetal(), new Vector3(14, 1.3f, 8));

            BuildExitGate();
        }

        // ── дверь-головоломка ──
        readonly Dictionary<string, GameObject> _doors = new();
        void MakeDoor(string key, Vector3 pos, float w, string axis, Material mat)
        {
            bool solved = S.Flag("door:" + key);
            var size = axis == "x" ? new Vector3(w, DoorH, 1.2f) : new Vector3(1.2f, DoorH, w);
            var mesh = Build.MeshBox(transform, size, mat, new Vector3(pos.x, DoorH * 0.5f, pos.z));
            if (!solved)
            {
                Build.Collide(transform, size, new Vector3(pos.x, DoorH * 0.5f, pos.z));
                var trig = new GameObject("door_trigger");
                trig.transform.SetParent(transform, false);
                trig.transform.position = new Vector3(pos.x, 1.5f, pos.z);
                var it = trig.AddComponent<Interactable>();
                it.prompt = "[E] ДВЕРЬ: решить головоломку взлома";
                it.onInteract = () => { S.SetFlag("door:" + key); Destroy(mesh); /* TODO: PuzzleUI */ };
                _doors[key] = trig;
            }
            else mesh.transform.localPosition += new Vector3(0, -DoorH, 0);
        }

        void BuildExitGate()
        {
            bool done = S.ZoneComplete(0);
            var gate = Mats.Neon(new Color(0.25f, 0.6f, 1f), done ? 0.4f : 1.2f);
            var m = Build.MeshBox(transform, new Vector3(4, DoorH, 0.3f), gate, new Vector3(0, DoorH * 0.5f, -6));
            if (!done) Build.Collide(transform, new Vector3(4, DoorH, 0.4f), new Vector3(0, DoorH * 0.5f, -6));
            Build.Label(transform, done ? "ПРОХОД ОТКРЫТ ▸ 1 УРОВЕНЬ" : $"ЗАБЛОКИРОВАНО: серверы {S.ZoneInfected(0)}/3",
                new Vector3(0, DoorH + 1.2f, -5.4f), 3.2f, done ? GameData.INFECTED : new Color(0.5f,0.8f,1f));
        }

        // ── серверы ──
        void BuildNodes()
        {
            foreach (var n in S.gridNodes)
            {
                bool unlocked = S.NodeUnlocked(n), infected = n.infected;
                Color col = infected ? GameData.INFECTED : (unlocked ? GameData.TIER_COLORS[n.tier] : new Color(0.23f,0.29f,0.33f));
                float h = 2.4f + n.tier * 0.4f;
                var root = new GameObject($"srv_{n.id}").transform;
                root.SetParent(transform, false);
                root.localPosition = n.pos;
                Build.Solid(root, new Vector3(1.7f, h, 1.2f), Mats.MetalDark(0.45f), new Vector3(0, h * 0.5f, 0));
                Build.MeshBox(root, new Vector3(0.5f, 0.06f, 0.5f), Mats.Neon(col, 1.2f), new Vector3(0, h + 0.32f, 0));
                Build.Label(root, $"{n.name} · {(infected ? "✓ ВЗЛОМАН" : unlocked ? "[E] ВЗЛОМ" : "🔒")}",
                    new Vector3(0, h + 1.5f, 0), 3.4f, col);
                _nodeVis[n.id] = root;

                if (unlocked && !infected)
                {
                    var trig = new GameObject($"srv_trigger_{n.id}");
                    trig.transform.SetParent(root, false);
                    trig.transform.localPosition = new Vector3(0, 1, 0);
                    var it = trig.AddComponent<Interactable>();
                    var node = n;
                    it.prompt = $"[E] ВЗЛОМ СЕРВЕРА: {n.name}";
                    // ВРЕМЕННО (пока не портирован рейд level.gd): мгновенный
                    // успешный взлом + перезагрузка Грида (двери/барьеры обновятся)
                    it.onInteract = () =>
                    {
                        S.StartHack(node);
                        S.FinishHack(true);
                        App.SceneFlow.ReloadGrid();
                    };
                }
            }
        }

        void SpawnPlayer()
        {
            var go = new GameObject("Player", typeof(CharacterController), typeof(Player.VirusPlayer));
            _player = go.GetComponent<Player.VirusPlayer>();
            go.transform.position = new Vector3(0, 1.2f, 32f);
        }

        // ── проёмы комнат (порт ROOM_GAPS) ──
        void BuildRoomGaps()
        {
            _gaps = new Dictionary<string, Dictionary<string, Gap[]>>
            {
                ["r0"]  = new() { ["n"] = new[] { new Gap(0, 4) } },
                ["a1"]  = new() { ["s"] = new[] { new Gap(0, 4) }, ["e"] = new[] { new Gap(-35, 6) }, ["w"] = new[] { new Gap(-26, 3.4f) } },
                ["b1"]  = new() { ["w"] = new[] { new Gap(-35, 6) }, ["s"] = new[] { new Gap(36, 3.4f) }, ["n"] = new[] { new Gap(48, 6) } },
                ["s1a"] = new() { ["e"] = new[] { new Gap(-26, 3.4f) } },
                ["s1b"] = new() { ["n"] = new[] { new Gap(36, 3.4f) } },
                ["c2"]  = new() { ["s"] = new[] { new Gap(48, 6) }, ["w"] = new[] { new Gap(-94, 3.4f) }, ["n"] = new[] { new Gap(36, 4) }, ["e"] = new[] { new Gap(-112, 6) } },
                ["d2"]  = new() { ["w"] = new[] { new Gap(-112, 6) }, ["s"] = new[] { new Gap(106, 4) }, ["e"] = new[] { new Gap(-129, 3.4f) }, ["n"] = new[] { new Gap(98, 6) } },
                ["srv2a"] = new() { ["s"] = new[] { new Gap(36, 4) } },
                ["srv2b"] = new() { ["n"] = new[] { new Gap(106, 4) } },
                ["s2a"] = new() { ["e"] = new[] { new Gap(-94, 3.4f) } },
                ["s2b"] = new() { ["w"] = new[] { new Gap(-129, 3.4f) } },
                ["e1"]  = new() { ["s"] = new[] { new Gap(98, 6) }, ["w"] = new[] { new Gap(-198, 4) }, ["e"] = new[] { new Gap(-203, 6) } },
                ["e2"]  = new() { ["w"] = new[] { new Gap(-203, 6) }, ["e"] = new[] { new Gap(-212, 4) }, ["n"] = new[] { new Gap(131, 6) } },
                ["e3"]  = new() { ["s"] = new[] { new Gap(131, 6) }, ["w"] = new[] { new Gap(-247, 6) }, ["n"] = new[] { new Gap(110, 3.4f), new Gap(122, 6) } },
                ["e4"]  = new() { ["e"] = new[] { new Gap(-247, 6) }, ["s"] = new[] { new Gap(76, 4) } },
                ["srv3a"] = new() { ["e"] = new[] { new Gap(-198, 4) } },
                ["srv3b"] = new() { ["w"] = new[] { new Gap(-212, 4) } },
                ["srv3c"] = new() { ["n"] = new[] { new Gap(76, 4) } },
                ["s3a"] = new() { ["s"] = new[] { new Gap(110, 3.4f) } },
                ["or"]  = new() { ["s"] = new[] { new Gap(122, 6) } },
            };
        }
    }
}
