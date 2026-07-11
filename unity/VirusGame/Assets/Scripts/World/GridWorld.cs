using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using Virus.Core;
using Virus.Util;

namespace Virus.World
{
    // Порт grid_world.gd (полный): комнаты по карте, туннели с барьерами,
    // обучение, город/офисы/бункер со всем интерактивом, Оракул, побег.
    // Ядро: поля, Start/Update-тики, стены, свет, серверы, нокдаун, зип.
    public partial class GridWorld : MonoBehaviour
    {
        const float WallT = 1f, DoorH = 4f, BlockEdge = 1.5f, LiftCycle = 8.4f;

        struct Gap { public float c, w; public Gap(float c, float w) { this.c = c; this.w = w; } }
        static Dictionary<string, Dictionary<string, Gap[]>> _gaps;

        GameState S => GameState.I;
        Player.VirusPlayer _player;
        UI.Hud _hud;

        // ── состояния интерактива ──
        class DoorState { public GridData.DoorDef def; public GameObject mesh, body; public Vector3 pos; }
        readonly Dictionary<string, DoorState> _doors = new();
        class WireState { public string key; public Vector3[] pylons; public Material[] orbs; public Color color; public string desc; }
        readonly Dictionary<string, WireState> _wires = new();
        class LiftState { public Transform body; public float x, z, y0, y1, t; public string power; }
        readonly List<LiftState> _lifts = new();
        class BeamState { public GameObject beam; public Vector3 a, b; public float phase; }
        readonly List<BeamState> _beams = new();
        class CeilState { public Transform plate; public Vector3 home; public int st; public float t; }
        readonly List<CeilState> _ceils = new();
        class BotState { public Transform node; public Vector3 wp; public float t; }
        readonly List<BotState> _robots = new();
        class TerrState { public Vector3 pos; public Transform pillar; public float prog; public Material mat; }
        readonly Dictionary<string, TerrState> _terrs = new();
        class BlockState { public Transform body; public BoxCollider col; public int weight; }
        readonly Dictionary<int, BlockState> _blocks = new();
        int _carryBlock = -1;
        class ZipState { public Vector3 a, b; public string flag; public bool drawn; }
        readonly List<ZipState> _zips = new();

        GameObject _shield, _escapeGo;
        TextMesh _board;
        Material _coreMat, _eyeMat;
        readonly List<Light> _alertLights = new();
        readonly List<(Transform t, Vector3 basePos, int id)> _motes = new();
        float _knockLock, _boardT;
        bool _ridingZip;

        void Start()
        {
            BuildRoomGaps();
            BuildEnvironment();
            BuildRooms();
            LightRooms();
            BuildTunnels();
            BuildPuzzleDoors();
            BuildStage0();
            BuildStage1();
            BuildStage2();
            BuildStage3();
            BuildOracle();
            BuildNodes();
            BuildMotes();
            Sfx.Ambient("wind", 0.14f);   // подложка Грида
            // атмосфера: мотыльки данных над обучающим ангаром и залом Оракула
            Fx.DataMotes(transform, new Vector3(0, 5f, 17f), new Vector3(44f, 7f, 42f),
                GameData.TIER_COLORS[0], 26f);
            Fx.DataMotes(transform, new Vector3(124f, 9f, -338f), new Vector3(100f, 16f, 90f),
                GameData.ORACLE, 40f);
            SpawnPlayer();
            BuildCarryInteract();
            _hud = FindFirstObjectByType<UI.Hud>();
            UpdateObjective();
        }

        float _saveTimer = 20f;

        void OnDestroy() => App.SaveSystem.Save();

        void Update()
        {
            // автосейв: интерактив Грида (двери/рычаги/блоки) не теряется
            _saveTimer -= Time.deltaTime;
            if (_saveTimer <= 0f)
            {
                _saveTimer = 20f;
                App.SaveSystem.Save();
            }

            // дерево эволюции: Tab открывает/закрывает (закрытие — внутри UI)
            if (Input.GetKeyDown(KeyCode.Tab) && !UI.PuzzleUI.IsOpen && !UI.EvolutionUI.IsOpen && !UI.PauseMenu.IsOpen)
                UI.EvolutionUI.Toggle();

            _knockLock = Mathf.Max(_knockLock - Time.deltaTime, 0f);
            TickLifts();
            TickBeams();
            TickCeils();
            TickRobots();
            TickTerrs();
            TickAlert();
            TickBoard();
            TickMotes();
            TickCarry();
            TickHints();
        }

        void UpdateObjective()
        {
            if (_hud == null) return;
            if (S.oracleCoreDown) _hud.SetObjective("ЯДРО РАЗРУШЕНО — беги к порталу эвакуации!");
            else if (S.RedAlert()) _hud.SetObjective("28/28! Путь к ОРАКУЛУ открыт — реши 15 головоломок и захвати зал");
            else if (!S.ZoneComplete(0)) _hud.SetObjective("ОБУЧЕНИЕ: захвати 3 сервера и открой дверь на 1 уровень · [Tab] — дерево эволюции");
            else _hud.SetObjective($"Захвати все серверы этапа — туннель дальше откроется ({S.FacilityInfected()}/28) · [Tab] — эволюция");
        }

        // ── окружение (ночной город) ──
        void BuildEnvironment()
        {
            QualitySettings.pixelLightCount = 10;
            QualitySettings.shadowDistance = 70f;
            QualitySettings.antiAliasing = 4;

            var sun = new GameObject("Moon").AddComponent<Light>();
            sun.type = LightType.Directional;
            sun.color = new Color(0.6f, 0.7f, 0.92f);
            sun.intensity = 1.0f;
            sun.transform.rotation = Quaternion.Euler(55, -35, 0);
            sun.shadows = LightShadows.Soft;
            sun.shadowStrength = 0.75f;

            // ACES-тонмаппинг съедает яркость — амбиент с запасом
            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Trilight;
            RenderSettings.ambientSkyColor = new Color(0.55f, 0.63f, 0.82f);
            RenderSettings.ambientEquatorColor = new Color(0.45f, 0.49f, 0.58f);
            RenderSettings.ambientGroundColor = new Color(0.2f, 0.21f, 0.25f);

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

        // ── стены с проёмами ──
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
            0 => Mats.Concrete(new Color(0.38f, 0.39f, 0.42f)),
            1 => Mats.Brick(),
            2 => Mats.PlasterOld(),
            3 => Mats.BunkerWall(),
            _ => Mats.Obsidian(),
        };
        Material FloorMat(int stage) => stage switch
        {
            0 => Mats.Concrete(new Color(0.30f, 0.31f, 0.33f)),
            1 => Mats.Sidewalk(),
            2 => Mats.CarpetRot(),
            3 => Mats.Concrete(new Color(0.26f, 0.27f, 0.28f)),
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
            var pass = Mats.Concrete(new Color(0.38f, 0.39f, 0.42f));
            Build.Solid(transform, new Vector3(4, 0.5f, 2), pass, new Vector3(0, -0.25f, -7));
            for (int s = -1; s <= 1; s += 2) Build.Solid(transform, new Vector3(WallT, DoorH, 2), pass, new Vector3(s * 2.5f, DoorH * 0.5f, -7));
            // этапы различаются материалами/светом; гигантские надписи убраны —
            // название этапа приходит подсказкой при входе (MakeHint в Stages)
        }

        void LightRooms()
        {
            foreach (var kv in GameData.ROOMS)
            {
                var r = kv.Value;
                if (r.stage == 1 && !r.secret) continue;
                Color col = r.stage switch
                {
                    0 => new Color(0.85f, 0.92f, 1f),
                    2 => new Color(0.95f, 0.85f, 0.65f),
                    3 => new Color(0.7f, 0.82f, 1f),
                    4 => new Color(0.55f, 0.7f, 1f),
                    _ => new Color(0.8f, 0.86f, 0.95f),
                };
                float energy = r.stage == 0 ? 3.0f : 2.3f;
                int nx = Mathf.Clamp((int)(r.W / 18f), 1, 4), nz = Mathf.Clamp((int)(r.D / 18f), 1, 4);
                for (int ix = 0; ix < nx; ix++)
                    for (int iz = 0; iz < nz; iz++)
                    {
                        float lx = Mathf.Lerp(r.x0 + 4, r.x1 - 4, (ix + 0.5f) / nx);
                        float lz = Mathf.Lerp(r.zs - 4, r.zn + 4, (iz + 0.5f) / nz);
                        Build.MeshBox(transform, new Vector3(2.4f, 0.14f, 0.7f), Mats.Neon(col, 1.3f), new Vector3(lx, r.h - 0.35f, lz));
                        Build.Omni(transform, new Vector3(lx, r.h - 0.8f, lz), col, energy, Mathf.Max(r.h, 9f) + 8f);
                    }
            }
        }

        // ── серверы ──
        void BuildNodes()
        {
            foreach (var n in S.gridNodes)
            {
                bool unlocked = S.NodeUnlocked(n), infected = n.infected;
                Color col = infected ? GameData.INFECTED : (unlocked ? GameData.TIER_COLORS[n.tier] : new Color(0.23f, 0.29f, 0.33f));
                float h = 2.4f + n.tier * 0.4f;
                var root = new GameObject($"srv_{n.id}").transform;
                root.SetParent(transform, false);
                root.localPosition = n.pos;
                Build.Solid(root, new Vector3(1.7f, h, 1.2f), Mats.MetalDark(0.45f), new Vector3(0, h * 0.5f, 0));
                Build.MeshBox(root, new Vector3(1.5f, h - 0.4f, 0.06f), Mats.Plastic(new Color(0.22f, 0.24f, 0.28f)), new Vector3(0, h * 0.5f, 0.6f));
                for (int k = 0; k < 5; k++)
                    Build.MeshBox(root, new Vector3(1.3f, 0.12f, 0.05f), Mats.Plastic(new Color(0.1f, 0.11f, 0.13f)), new Vector3(-0.05f, 0.55f + k * 0.35f, 0.64f));
                Build.MeshBox(root, new Vector3(0.5f, 0.5f, 0.5f), Mats.Neon(col, 1.2f), new Vector3(0, h + 0.35f, 0));
                if (unlocked && !infected) Build.Omni(root, new Vector3(0, h + 0.6f, 0), col, 1.1f, 7f);

                if (!infected)
                {
                    var it = MakeInteract(root, new Vector3(0, 1, 0), 4.2f);
                    var node = n;
                    it.dynamicPrompt = () => S.NodeUnlocked(node)
                        ? $"[E] ВЗЛОМ СЕРВЕРА: {node.name} ({GameData.TIERS[node.tier].shortName}" +
                          (node.arch != "" ? $" · {GameData.ARCHETYPES[node.arch].name}" : "") +
                          $" · {node.av})"
                        : $"ЗАПЕРТО: {S.NodeLockReason(node)}";
                    it.onInteract = () =>
                    {
                        if (!S.NodeUnlocked(node)) return;
                        S.StartHack(node);
                        App.SceneFlow.EnterRaid();
                    };
                }
            }
        }

        // моты одноразовые на кампанию: подобранный помечается флагом mote:<i>
        // (флаг уходит в сейв и рассылается стае — у напарников мот тоже гаснет)
        void BuildMotes()
        {
            for (int i = 0; i < GridData.MOTES.Length; i++)
            {
                if (S.Flag($"mote:{i}")) continue;
                var pos = GridData.MOTES[i];
                var m = Build.MeshBox(transform, Vector3.one * 0.5f, Mats.Neon(GameData.INFECTED, 1.8f), pos);
                m.transform.rotation = Quaternion.Euler(45, 0, 45);
                _motes.Add((m.transform, pos, i));
            }
        }

        void TickMotes()
        {
            if (_player == null) return;
            float t = Time.time;
            for (int i = _motes.Count - 1; i >= 0; i--)
            {
                var (tr, basePos, id) = _motes[i];
                if (tr == null) { _motes.RemoveAt(i); continue; }
                if (S.Flag($"mote:{id}"))   // напарник успел первым
                {
                    Destroy(tr.gameObject);
                    _motes.RemoveAt(i);
                    continue;
                }
                tr.position = basePos + Vector3.up * (Mathf.Sin(t * 2f + i) * 0.25f);
                tr.Rotate(0, 60f * Time.deltaTime, 0, Space.World);
                if (Vector3.Distance(_player.transform.position, tr.position) < 1.8f)
                {
                    S.SetFlag($"mote:{id}");
                    S.resources["data_fragments"] += 3;
                    _hud?.Toast("+3 Data Fragments");
                    Destroy(tr.gameObject);
                    _motes.RemoveAt(i);
                }
            }
        }

        void SpawnPlayer()
        {
            var go = new GameObject("Player", typeof(CharacterController), typeof(Player.VirusPlayer));
            _player = go.GetComponent<Player.VirusPlayer>();
            var spawn = new Vector3(0, 1.2f, 32f);
            if (S.currentNode != null)
                spawn = new Vector3(S.currentNode.pos.x, S.currentNode.pos.y + 1.2f, S.currentNode.pos.z + 4f);
            go.transform.position = spawn;
        }

        // ── общий хелпер: Interactable на дочернем объекте ──
        Interactable MakeInteract(Transform parent, Vector3 localPos, float radius)
        {
            var go = new GameObject("interact");
            go.transform.SetParent(parent, false);
            go.transform.localPosition = localPos;
            var it = go.AddComponent<Interactable>();
            it.radius = radius;
            return it;
        }

        // ── подсказки по приближению: замена летающих текстов уроков/зон ──
        // Тост показывается один раз за сессию при входе в радиус.
        class Hint { public Vector3 pos; public float r; public System.Func<string> text; public bool shown; }
        readonly List<Hint> _hints = new();

        void MakeHint(Vector3 pos, float radius, System.Func<string> text) =>
            _hints.Add(new Hint { pos = pos, r = radius, text = text });

        void TickHints()
        {
            if (_player == null) return;
            var pp = _player.transform.position;
            foreach (var h in _hints)
            {
                if (h.shown) continue;
                if (Vector3.Distance(pp, h.pos) > h.r) continue;
                h.shown = true;
                var msg = h.text();
                if (!string.IsNullOrEmpty(msg)) _hud?.Toast(msg);
            }
        }

        // ── нокдаун: вспышка, тост, телепорт к точке ──
        public void Knockdown(Vector3 respawn, Vector3 hitFrom, string msg)
        {
            if (_knockLock > 0f) return;
            _knockLock = 2f;
            _hud?.Toast(msg);
            var push = _player.transform.position - hitFrom;
            push.y = 0;
            _player.Impulse(push.normalized * 9f + Vector3.up * 6f);
            StartCoroutine(KnockTeleport(respawn));
        }

        IEnumerator KnockTeleport(Vector3 respawn)
        {
            yield return new WaitForSeconds(0.55f);
            if (_player != null) _player.Teleport(respawn);
        }

        // ── зип-лайн: перелёт по проводу ──
        void RideZip(Vector3 from, Vector3 to)
        {
            if (_ridingZip) return;
            StartCoroutine(ZipRide(from, to));
        }

        IEnumerator ZipRide(Vector3 from, Vector3 to)
        {
            _ridingZip = true;
            _player.controlEnabled = false;
            float dur = 0.5f + Vector3.Distance(from, to) / 26f, t = 0f;
            while (t < dur)
            {
                t += Time.deltaTime;
                float k = Mathf.Clamp01(t / dur);
                var p = Vector3.Lerp(from, to, k);
                p.y += Mathf.Sin(k * Mathf.PI) * 0.35f - 0.9f;
                _player.Teleport(p);
                yield return null;
            }
            _player.controlEnabled = true;
            _ridingZip = false;
        }

        // ── проёмы комнат ──
        void BuildRoomGaps()
        {
            _gaps = new Dictionary<string, Dictionary<string, Gap[]>>
            {
                ["r0"] = new() { ["n"] = new[] { new Gap(0, 4) } },
                ["a1"] = new() { ["s"] = new[] { new Gap(0, 4) }, ["e"] = new[] { new Gap(-35, 6) }, ["w"] = new[] { new Gap(-26, 3.4f) } },
                ["b1"] = new() { ["w"] = new[] { new Gap(-35, 6) }, ["s"] = new[] { new Gap(36, 3.4f) }, ["n"] = new[] { new Gap(48, 6) } },
                ["s1a"] = new() { ["e"] = new[] { new Gap(-26, 3.4f) } },
                ["s1b"] = new() { ["n"] = new[] { new Gap(36, 3.4f) } },
                ["c2"] = new() { ["s"] = new[] { new Gap(48, 6) }, ["w"] = new[] { new Gap(-94, 3.4f) }, ["n"] = new[] { new Gap(36, 4) }, ["e"] = new[] { new Gap(-112, 6) } },
                ["d2"] = new() { ["w"] = new[] { new Gap(-112, 6) }, ["s"] = new[] { new Gap(106, 4) }, ["e"] = new[] { new Gap(-129, 3.4f) }, ["n"] = new[] { new Gap(98, 6) } },
                ["srv2a"] = new() { ["s"] = new[] { new Gap(36, 4) } },
                ["srv2b"] = new() { ["n"] = new[] { new Gap(106, 4) } },
                ["s2a"] = new() { ["e"] = new[] { new Gap(-94, 3.4f) } },
                ["s2b"] = new() { ["w"] = new[] { new Gap(-129, 3.4f) } },
                ["e1"] = new() { ["s"] = new[] { new Gap(98, 6) }, ["w"] = new[] { new Gap(-198, 4) }, ["e"] = new[] { new Gap(-203, 6) } },
                ["e2"] = new() { ["w"] = new[] { new Gap(-203, 6) }, ["e"] = new[] { new Gap(-212, 4) }, ["n"] = new[] { new Gap(131, 6) } },
                ["e3"] = new() { ["s"] = new[] { new Gap(131, 6) }, ["w"] = new[] { new Gap(-247, 6) }, ["n"] = new[] { new Gap(110, 3.4f), new Gap(122, 6) } },
                ["e4"] = new() { ["e"] = new[] { new Gap(-247, 6) }, ["s"] = new[] { new Gap(76, 4) } },
                ["srv3a"] = new() { ["e"] = new[] { new Gap(-198, 4) } },
                ["srv3b"] = new() { ["w"] = new[] { new Gap(-212, 4) } },
                ["srv3c"] = new() { ["n"] = new[] { new Gap(76, 4) } },
                ["s3a"] = new() { ["s"] = new[] { new Gap(110, 3.4f) } },
                ["or"] = new() { ["s"] = new[] { new Gap(122, 6) } },
            };
        }
    }
}
