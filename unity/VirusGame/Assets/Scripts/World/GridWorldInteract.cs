using UnityEngine;
using Virus.Core;
using Virus.Util;

namespace Virus.World
{
    // Интерактив Грида: двери-головоломки, рычаги, провода (опоры по порядку),
    // роутер, генераторы, лифты, переносные блоки, зип-лайны, лазеры, потолки.
    public partial class GridWorld
    {
        // ── двери-головоломки ──
        void BuildPuzzleDoors()
        {
            foreach (var dd in GridData.PUZZLE_DOORS)
            {
                var r = GameData.ROOMS[dd.room];
                Vector3 pos; string axis;
                switch (dd.side)
                {
                    case "n": pos = new Vector3(dd.c, 0, r.zn); axis = "x"; break;
                    case "s": pos = new Vector3(dd.c, 0, r.zs); axis = "x"; break;
                    case "e": pos = new Vector3(r.x1, 0, dd.c); axis = "z"; break;
                    default:  pos = new Vector3(r.x0, 0, dd.c); axis = "z"; break;
                }
                var mat = r.stage == 3 ? Mats.Rust() : Mats.Metal(new Color(0.45f, 0.44f, 0.4f), 0.5f);
                MakeDoor(dd, pos, axis, mat);
            }
        }

        void MakeDoor(GridData.DoorDef def, Vector3 pos, string axis, Material mat)
        {
            bool solved = S.Flag("door:" + def.key);
            var size = axis == "x" ? new Vector3(def.w, DoorH, 1.2f) : new Vector3(1.2f, DoorH, def.w);
            var mesh = Build.MeshBox(transform, size, mat, new Vector3(pos.x, DoorH * 0.5f, pos.z));
            var seamSize = axis == "x" ? new Vector3(def.w * 0.9f, 0.1f, 1.3f) : new Vector3(1.3f, 0.1f, def.w * 0.9f);
            Build.MeshBox(transform, seamSize, Mats.Neon(solved ? GameData.INFECTED : new Color(1f, 0.45f, 0.2f), 1.4f),
                new Vector3(pos.x, solved ? 0.35f : 2f, pos.z));
            var st = new DoorState { def = def, mesh = mesh, pos = new Vector3(pos.x, 0, pos.z) };
            if (!solved)
                st.body = Build.Collide(transform, size, new Vector3(pos.x, DoorH * 0.5f, pos.z));
            else
                mesh.transform.localPosition += new Vector3(0, -DoorH + 0.4f, 0);
            st.label = Build.Label(transform, "", new Vector3(pos.x, DoorH + 0.9f, pos.z), 2.6f, new Color(1f, 0.6f, 0.25f));
            _doors[def.key] = st;
            RefreshDoorLabel(def.key);

            if (!solved)
            {
                var it = MakeInteract(transform, new Vector3(pos.x, 1.4f, pos.z), 3.0f);
                var key = def.key;
                it.dynamicPrompt = () =>
                    S.Flag("door:" + key) ? "" :
                    def.power && !S.Stage3Powered()
                        ? $"ДВЕРЬ ОБЕСТОЧЕНА: генераторы {S.Stage3GeneratorsOn()}/3 + рубильник"
                        : "[E] ДВЕРЬ: решить головоломку взлома";
                it.enabledFn = () => !S.Flag("door:" + key);
                it.onInteract = () =>
                {
                    if (def.power && !S.Stage3Powered()) return;
                    UI.PuzzleUI.Open(def.diff, "СХЕМА ВЗЛОМА ДВЕРИ", () => OpenDoor(key));
                };
            }
        }

        void RefreshDoorLabel(string key)
        {
            var d = _doors[key];
            if (d.label == null) return;
            if (S.Flag("door:" + key)) { d.label.text = "ДВЕРЬ ОТКРЫТА"; d.label.color = GameData.INFECTED; }
            else if (d.def.power && !S.Stage3Powered()) { d.label.text = "ОБЕСТОЧЕНА"; d.label.color = new Color(0.85f, 0.35f, 0.3f); }
            else { d.label.text = "ЗАПЕРТО · [E] головоломка"; d.label.color = new Color(1f, 0.6f, 0.25f); }
        }

        void OpenDoor(string key)
        {
            var d = _doors[key];
            S.SetFlag("door:" + key);
            if (d.body != null) Destroy(d.body);
            if (d.mesh != null) d.mesh.transform.localPosition += new Vector3(0, -DoorH + 0.4f, 0);
            if (!string.IsNullOrEmpty(d.def.opz))
            {
                S.SetFlag(d.def.opz);
                _hud?.Toast($"ГОЛОВОЛОМКИ ОРАКУЛА: {S.OraclePuzzlesDone()}/{GameData.ORACLE_PUZZLES_TOTAL}");
                RefreshOracleShield();
            }
            RefreshDoorLabel(key);
            RefreshPowerLabels();
        }

        // ── рычаг ──
        void MakeLever(string key, Vector3 pos, string desc)
        {
            bool on = S.Flag("lever:" + key);
            var root = new GameObject("lever_" + key).transform;
            root.SetParent(transform, false);
            root.localPosition = pos;
            Build.Solid(root, new Vector3(0.7f, 1.1f, 0.5f), Mats.MetalDark(0.4f), new Vector3(0, 0.55f, 0));
            var arm = Build.MeshBox(root, new Vector3(0.1f, 0.8f, 0.1f), Mats.Neon(on ? GameData.INFECTED : new Color(1f, 0.4f, 0.3f), 2f), new Vector3(0, 1.25f, 0));
            arm.transform.localRotation = Quaternion.Euler(0, 0, on ? 40 : -40);
            var lbl = Build.Label(root, $"{desc}\n{(on ? "ВКЛЮЧЁН" : "[E] включить")}", new Vector3(0, 2.2f, 0), 2.4f,
                on ? GameData.INFECTED : new Color(1f, 0.7f, 0.35f));
            if (!on)
            {
                var it = MakeInteract(root, new Vector3(0, 1, 0), 2.6f);
                it.prompt = $"[E] {desc}";
                it.enabledFn = () => !S.Flag("lever:" + key);
                it.onInteract = () =>
                {
                    S.SetFlag("lever:" + key);
                    arm.transform.localRotation = Quaternion.Euler(0, 0, 40);
                    arm.GetComponent<MeshRenderer>().sharedMaterial = Mats.Neon(GameData.INFECTED, 2f);
                    lbl.text = $"{desc}\nВКЛЮЧЁН";
                    lbl.color = GameData.INFECTED;
                    _hud?.Toast($"{desc}: включён");
                    RefreshPowerLabels();
                };
            }
        }

        // ── провода: подключай опоры по порядку ──
        void MakeWire(string key, Vector3[] pylons, Color color, string desc)
        {
            var ws = new WireState { key = key, pylons = pylons, color = color, desc = desc, orbs = new Material[pylons.Length] };
            int doneN = WireDoneN(key, pylons.Length);
            for (int i = 0; i < pylons.Length; i++)
            {
                var p = pylons[i];
                Build.MeshBox(transform, new Vector3(0.3f, 1.7f, 0.3f), Mats.MetalDark(0.45f), p + new Vector3(0, 0.85f, 0));
                bool lit = i < doneN;
                var orb = Mats.Neon(lit ? color : new Color(0.35f, 0.38f, 0.42f), lit ? 1.6f : 0.5f);
                ws.orbs[i] = orb;
                Build.MeshBox(transform, Vector3.one * 0.3f, orb, p + new Vector3(0, 1.85f, 0));

                int idx = i;
                var it = MakeInteract(transform, p + new Vector3(0, 1.2f, 0), 2.6f);
                it.dynamicPrompt = () => $"[E] подключить опору {idx + 1}/{pylons.Length} ({desc})";
                it.enabledFn = () => !S.Flag("wire:" + key) && WireDoneN(key, pylons.Length) == idx;
                it.onInteract = () => AdvanceWire(ws, idx);
            }
            ws.label = Build.Label(transform, "", pylons[0] + new Vector3(0, 2.8f, 0), 2.4f, color);
            _wires[key] = ws;
            for (int i = 1; i < doneN; i++) DrawWireSeg(ws, i - 1, i);
            RefreshWireLabel(ws);
        }

        int WireDoneN(string key, int total)
        {
            int n = 0;
            for (int i = 0; i < total; i++) if (S.Flag($"wirep:{key}:{i}")) n = i + 1;
            return n;
        }

        void AdvanceWire(WireState ws, int idx)
        {
            S.SetFlag($"wirep:{ws.key}:{idx}");
            ws.orbs[idx].SetColor("_EmissionColor", ws.color * 1.6f);
            if (idx > 0) DrawWireSeg(ws, idx - 1, idx);
            if (idx + 1 >= ws.pylons.Length)
            {
                S.SetFlag("wire:" + ws.key);
                _hud?.Toast($"{ws.desc}: линия под напряжением!");
                RefreshPowerLabels();
            }
            RefreshWireLabel(ws);
        }

        void DrawWireSeg(WireState ws, int i0, int i1)
        {
            var a = ws.pylons[i0] + new Vector3(0, 1.85f, 0);
            var b = ws.pylons[i1] + new Vector3(0, 1.85f, 0);
            const int segs = 6;
            for (int s = 0; s < segs; s++)
            {
                float t0 = (float)s / segs, t1 = (float)(s + 1) / segs;
                var p0 = Vector3.Lerp(a, b, t0) + Vector3.down * (Mathf.Sin(t0 * Mathf.PI) * 0.5f);
                var p1 = Vector3.Lerp(a, b, t1) + Vector3.down * (Mathf.Sin(t1 * Mathf.PI) * 0.5f);
                var seg = Build.MeshBox(transform, new Vector3(0.07f, 0.07f, Vector3.Distance(p0, p1)), Mats.Neon(ws.color, 1.1f), (p0 + p1) * 0.5f);
                seg.transform.rotation = Quaternion.LookRotation(p1 - p0);
            }
        }

        void RefreshWireLabel(WireState ws)
        {
            if (ws.label == null) return;
            int n = WireDoneN(ws.key, ws.pylons.Length);
            if (n >= ws.pylons.Length) { ws.label.text = $"{ws.desc}: ПОД НАПРЯЖЕНИЕМ"; ws.label.color = GameData.INFECTED; }
            else ws.label.text = $"{ws.desc}: опоры {n}/{ws.pylons.Length}";
        }

        // ── роутер (удержание) ──
        void MakeRouter(string key, Vector3 pos)
        {
            bool on = S.Flag("router:" + key);
            var root = new GameObject("router").transform;
            root.SetParent(transform, false);
            root.localPosition = pos;
            Build.MeshBox(root, new Vector3(0.5f, 0.7f, 0.9f), Mats.Plastic(new Color(0.5f, 0.52f, 0.56f)), new Vector3(0, 2.2f, 0));
            var led = Mats.Neon(on ? GameData.INFECTED : new Color(0.9f, 0.3f, 0.2f), 1.8f);
            Build.MeshBox(root, Vector3.one * 0.12f, led, new Vector3(-0.3f, 2.35f, 0.3f));
            var lbl = Build.Label(root, $"РОУТЕР ЛИФТА\n{(on ? "АКТИВЕН" : "[E держать] активировать")}", new Vector3(0, 3.4f, 0), 2.4f,
                on ? GameData.INFECTED : new Color(0.4f, 0.8f, 1f));
            if (!on)
            {
                var it = MakeInteract(root, new Vector3(0, 2, 0), 2.8f);
                it.prompt = "РОУТЕР: активация…";
                it.holdSeconds = 2f;
                it.enabledFn = () => !S.Flag("router:" + key);
                it.onInteract = () =>
                {
                    S.SetFlag("router:" + key);
                    led.SetColor("_EmissionColor", (Color)GameData.INFECTED * 1.8f);
                    lbl.text = "РОУТЕР ЛИФТА\nАКТИВЕН";
                    lbl.color = GameData.INFECTED;
                    _hud?.Toast("Роутер активен");
                    RefreshPowerLabels();
                };
            }
        }

        // ── генератор (провод → удержание) ──
        void MakeGenerator(string key, Vector3 pos)
        {
            bool on = S.Flag("gen:" + key);
            var root = new GameObject("gen_" + key).transform;
            root.SetParent(transform, false);
            root.localPosition = pos;
            Build.Solid(root, new Vector3(2.2f, 2f, 3f), Mats.Metal(new Color(0.4f, 0.42f, 0.38f), 0.5f), new Vector3(0, 1f, 0));
            var glow = Mats.Neon(on ? GameData.INFECTED : new Color(0.3f, 0.32f, 0.35f), on ? 2f : 0.3f);
            Build.MeshBox(root, new Vector3(0.2f, 1.1f, 1.1f), glow, new Vector3(1.15f, 1.1f, 0));
            var lbl = Build.Label(root, "", new Vector3(0, 3f, 0), 2.6f, new Color(0.95f, 0.8f, 0.35f));
            void refresh()
            {
                if (S.Flag("gen:" + key)) { lbl.text = $"ГЕНЕРАТОР {key.ToUpper()}\nРАБОТАЕТ"; lbl.color = GameData.INFECTED; }
                else if (!S.Flag("wire:" + key)) { lbl.text = $"ГЕНЕРАТОР {key.ToUpper()}\nсначала протяни кабель"; lbl.color = new Color(0.85f, 0.4f, 0.3f); }
                else { lbl.text = $"ГЕНЕРАТОР {key.ToUpper()}\n[E держать] запустить"; lbl.color = new Color(0.95f, 0.8f, 0.35f); }
            }
            refresh();
            _genRefresh.Add(refresh);
            if (!on)
            {
                var it = MakeInteract(root, new Vector3(0, 1, 0), 3.2f);
                it.holdSeconds = 2.5f;
                it.dynamicPrompt = () => S.Flag("wire:" + key) ? "запуск генератора…" : "ГЕНЕРАТОР: сначала протяни кабель от щита";
                it.enabledFn = () => !S.Flag("gen:" + key);
                it.onInteract = () =>
                {
                    if (!S.Flag("wire:" + key)) return;
                    S.SetFlag("gen:" + key);
                    glow.SetColor("_EmissionColor", (Color)GameData.INFECTED * 2f);
                    _hud?.Toast($"Генераторы: {S.Stage3GeneratorsOn()}/3");
                    RefreshPowerLabels();
                };
            }
        }

        readonly System.Collections.Generic.List<System.Action> _genRefresh = new();

        void RefreshPowerLabels()
        {
            foreach (var a in _genRefresh) a();
            foreach (var k in _doors.Keys) RefreshDoorLabel(k);
            if (S.Stage3Powered()) _hud?.Toast("ЭТАП 3 ПОД НАПРЯЖЕНИЕМ: свет, лифты и двери активны");
            ApplyStage3Power();
            RefreshOracleShield();
            UpdateObjective();
        }

        // ── лифт ──
        void MakeLift(float x, float z, float yTop, string power, string cap)
        {
            var body = new GameObject("lift").transform;
            body.SetParent(transform, false);
            body.localPosition = new Vector3(x, 0.25f, z);
            var col = body.gameObject.AddComponent<BoxCollider>();
            col.size = new Vector3(3.2f, 0.4f, 3.2f);
            var mesh = Build.MeshBox(body, new Vector3(3.2f, 0.4f, 3.2f), Mats.DeckMetal(), Vector3.zero);
            Build.MeshBox(body, new Vector3(3.3f, 0.1f, 3.3f), Mats.Neon(new Color(0.3f, 0.8f, 1f), 1f), new Vector3(0, 0.2f, 0));
            for (int s = -1; s <= 1; s += 2)
                Build.Solid(transform, new Vector3(0.25f, yTop + 1.5f, 0.25f), Mats.MetalDark(0.5f), new Vector3(x + s * 1.55f, (yTop + 1.5f) * 0.5f, z - 1.55f));
            var lbl = Build.Label(transform, cap, new Vector3(x, yTop + 2.4f, z), 2.6f, new Color(0.3f, 0.8f, 1f));
            _lifts.Add(new LiftState { body = body, x = x, z = z, y0 = 0.25f, y1 = yTop, power = power, label = lbl });
        }

        void TickLifts()
        {
            foreach (var lf in _lifts)
            {
                bool powered = lf.power == "s2" ? S.Stage2LiftPowered() : S.Stage3Powered();
                if (!powered)
                {
                    lf.body.localPosition = new Vector3(lf.x, lf.y0, lf.z);
                    lf.label.text = lf.power == "s2"
                        ? $"ЛИФТ ОБЕСТОЧЕН\nрычаги {(S.Flag("lever:s2a") ? 1 : 0) + (S.Flag("lever:s2b") ? 1 : 0)}/2 · провод {(S.Flag("wire:s2") ? "+" : "-")} · роутер {(S.Flag("router:s2") ? "+" : "-")}"
                        : $"ЛИФТ ОБЕСТОЧЕН\nгенераторы {S.Stage3GeneratorsOn()}/3 · рубильник {(S.Flag("lever:s3master") ? "+" : "-")}";
                    lf.label.color = new Color(0.85f, 0.4f, 0.3f);
                    continue;
                }
                lf.label.text = "ЛИФТ РАБОТАЕТ";
                lf.label.color = new Color(0.3f, 0.8f, 1f);
                lf.t += Time.deltaTime;
                float ph = lf.t % LiftCycle, y;
                if (ph < 3f) y = Mathf.Lerp(lf.y0, lf.y1, Mathf.SmoothStep(0, 1, ph / 3f));
                else if (ph < 4.2f) y = lf.y1;
                else if (ph < 7.2f) y = Mathf.Lerp(lf.y1, lf.y0, Mathf.SmoothStep(0, 1, (ph - 4.2f) / 3f));
                else y = lf.y0;
                lf.body.localPosition = new Vector3(lf.x, y, lf.z);
            }
        }

        // ── переносные блоки ──
        void BuildBlocks()
        {
            foreach (var bd in GridData.BLOCKS)
            {
                var pos = S.blockPositions.TryGetValue(bd.id, out var saved) ? saved : bd.pos;
                var body = new GameObject($"block_{bd.id}").transform;
                body.SetParent(transform, false);
                body.localPosition = pos;
                var col = body.gameObject.AddComponent<BoxCollider>();
                col.size = Vector3.one * BlockEdge;
                bool heavy = bd.weight >= 2;
                Build.MeshBox(body, Vector3.one * BlockEdge, heavy ? Mats.Rust(new Color(0.42f, 0.3f, 0.2f)) : Mats.DeckMetal(new Color(0.42f, 0.4f, 0.36f)), Vector3.zero);
                Build.MeshBox(body, new Vector3(BlockEdge * 1.02f, 0.08f, BlockEdge * 1.02f),
                    Mats.Neon(heavy ? new Color(1f, 0.5f, 0.2f) : GameData.TIER_COLORS[0], 0.8f), new Vector3(0, BlockEdge * 0.5f - 0.05f, 0));
                Build.Label(body, heavy ? "ТЯЖЁЛЫЙ БЛОК" : "БЛОК", new Vector3(0, 1.4f, 0), 2f,
                    heavy ? new Color(1f, 0.6f, 0.3f) : new Color(0.7f, 0.85f, 0.95f));
                _blocks[bd.id] = new BlockState { body = body, col = col, weight = bd.weight };

                int id = bd.id;
                var it = MakeInteract(body, Vector3.zero, 2.6f);
                it.dynamicPrompt = () => heavy && _carryBlock < 0 ? "[E] ТЯЖЁЛЫЙ БЛОК: тащится очень медленно" : "[E] взять блок";
                it.enabledFn = () => _carryBlock < 0;
                it.onInteract = () => GrabBlock(id);
            }
        }

        void BuildCarryInteract()
        {
            var it = MakeInteract(_player.transform, Vector3.zero, 99f);
            it.prompt = "[E] поставить блок — встанет по сетке";
            it.enabledFn = () => _carryBlock >= 0;
            it.onInteract = PlaceBlock;
        }

        void GrabBlock(int id)
        {
            _carryBlock = id;
            var b = _blocks[id];
            b.col.enabled = false;
            _player.carrying = true;
            _player.carryFactor = b.weight >= 2 ? 0.3f : 0.66f;
        }

        void PlaceBlock()
        {
            if (_carryBlock < 0) return;
            var b = _blocks[_carryBlock];
            var p = b.body.position;
            float sx = Mathf.Round(p.x / BlockEdge) * BlockEdge;
            float sz = Mathf.Round(p.z / BlockEdge) * BlockEdge;
            float floorY = 0f;
            if (Physics.Raycast(new Vector3(sx, p.y + 1.5f, sz), Vector3.down, out var hit, 40f,
                    Physics.DefaultRaycastLayers, QueryTriggerInteraction.Ignore))
                floorY = hit.point.y;
            b.body.position = new Vector3(sx, floorY + BlockEdge * 0.5f, sz);
            b.col.enabled = true;
            S.blockPositions[_carryBlock] = b.body.position;
            _carryBlock = -1;
            _player.carrying = false;
            _player.carryFactor = 1f;
        }

        void TickCarry()
        {
            if (_carryBlock < 0 || _player == null) return;
            var b = _blocks[_carryBlock];
            var target = _player.transform.position + _player.LookDir() * 1.7f + Vector3.up * 1.0f;
            b.body.position = Vector3.Lerp(b.body.position, target, Mathf.Min(12f * Time.deltaTime, 1f));
        }

        // ── зип-лайны ──
        void MakeZip(Vector3 a, Vector3 b, string flagKey)
        {
            foreach (var e in new[] { a, b })
            {
                Build.MeshBox(transform, new Vector3(0.2f, 1f, 0.2f), Mats.MetalDark(0.5f), e - new Vector3(0, 0.5f, 0));
                Build.MeshBox(transform, Vector3.one * 0.18f, Mats.Neon(new Color(0.2f, 0.8f, 0.95f), 1.6f), e);
            }
            var zs = new ZipState { a = a, b = b, flag = flagKey };
            zs.label = Build.Label(transform, "", a + new Vector3(0, 1.1f, 0), 2.2f, new Color(0.2f, 0.8f, 0.95f));
            _zips.Add(zs);
            if (string.IsNullOrEmpty(flagKey) || S.Flag(flagKey)) DrawZip(zs);
            RefreshZipLabel(zs);

            foreach (var (from, to) in new[] { (a, b), (b, a) })
            {
                var it = MakeInteract(transform, from, 2.6f);
                it.prompt = "[E] ПРОВОД: перелёт на ту сторону";
                it.enabledFn = () => string.IsNullOrEmpty(zs.flag) || S.Flag(zs.flag);
                var f = from; var t2 = to;
                it.onInteract = () => RideZip(f, t2);
            }
        }

        public void DrawZipByFlag(string flagKey)
        {
            foreach (var z in _zips)
                if (z.flag == flagKey) { DrawZip(z); RefreshZipLabel(z); }
        }

        void DrawZip(ZipState z)
        {
            if (z.drawn) return;
            z.drawn = true;
            const int segs = 8;
            for (int s = 0; s < segs; s++)
            {
                float t0 = (float)s / segs, t1 = (float)(s + 1) / segs;
                var p0 = Vector3.Lerp(z.a, z.b, t0) + Vector3.up * (Mathf.Sin(t0 * Mathf.PI) * 0.4f);
                var p1 = Vector3.Lerp(z.a, z.b, t1) + Vector3.up * (Mathf.Sin(t1 * Mathf.PI) * 0.4f);
                var seg = Build.MeshBox(transform, new Vector3(0.07f, 0.07f, Vector3.Distance(p0, p1)), Mats.Neon(new Color(0.2f, 0.8f, 0.95f), 0.9f), (p0 + p1) * 0.5f);
                seg.transform.rotation = Quaternion.LookRotation(p1 - p0);
            }
        }

        void RefreshZipLabel(ZipState z)
        {
            if (z.label == null) return;
            z.label.text = string.IsNullOrEmpty(z.flag) || S.Flag(z.flag)
                ? "ПРОВОД [E] — перелёт" : "провод обесточен\n(кнопка перехода на стене)";
        }

        // ── лазеры этапа 3 ──
        void BuildBeams()
        {
            bool off = S.Flag("traps_off");
            foreach (var tb in GridData.TRAP_BEAMS)
            {
                foreach (var e in new[] { tb.a, tb.b })
                {
                    Build.MeshBox(transform, new Vector3(0.3f, 1.2f, 0.3f), Mats.Rust(), new Vector3(e.x, 0.6f, e.z));
                    Build.MeshBox(transform, Vector3.one * 0.2f, Mats.Neon(off ? GameData.INFECTED : new Color(1f, 0.15f, 0.1f), 1.5f), new Vector3(e.x, 1.25f, e.z));
                }
                var beam = Build.MeshBox(transform, new Vector3(0.07f, 0.07f, Vector3.Distance(tb.a, tb.b)), Mats.Neon(new Color(1f, 0.12f, 0.08f), 3f), (tb.a + tb.b) * 0.5f);
                beam.transform.rotation = Quaternion.LookRotation(tb.b - tb.a);
                beam.SetActive(!off);
                _beams.Add(new BeamState { beam = beam, a = tb.a, b = tb.b, phase = tb.phase });
            }
        }

        void TickBeams()
        {
            if (_player == null || _beams.Count == 0) return;
            bool off = S.Flag("traps_off");
            float t = Time.time;
            for (int i = 0; i < _beams.Count; i++)
            {
                var tr = _beams[i];
                if (off) { if (tr.beam.activeSelf) tr.beam.SetActive(false); continue; }
                bool on = (t + tr.phase) % 3.2f < 1.7f;
                tr.beam.SetActive(on);
                if (!on || _knockLock > 0f) continue;
                var pp = _player.transform.position;
                if (Mathf.Abs(pp.z - tr.a.z) < 0.6f && pp.y < 1.7f &&
                    pp.x > Mathf.Min(tr.a.x, tr.b.x) - 0.3f && pp.x < Mathf.Max(tr.a.x, tr.b.x) + 0.3f)
                {
                    var resp = i < 2 ? new Vector3(119, 1.2f, -203) : i < 4 ? new Vector3(131, 1.2f, -229) : new Vector3(95, 1.2f, -247);
                    Knockdown(resp, new Vector3(pp.x, 0.6f, tr.a.z), "ЛАЗЕРНАЯ ЛОВУШКА! Отключи их с блока-отключателя");
                }
            }
        }

        // ── падающие потолки этапа 2 ──
        void BuildCeils()
        {
            foreach (var (pos, room) in GridData.CEIL_TRAPS)
            {
                var r = GameData.ROOMS[room];
                var home = new Vector3(pos.x, r.h - 0.45f, pos.z);
                var plate = Build.MeshBox(transform, new Vector3(3f, 0.3f, 3f), Mats.PlasterOld(new Color(0.36f, 0.34f, 0.3f)), home);
                _ceils.Add(new CeilState { plate = plate.transform, home = home, st = 0 });
            }
        }

        void TickCeils()
        {
            if (_player == null) return;
            foreach (var ct in _ceils)
            {
                var pp = _player.transform.position;
                float d2 = new Vector2(pp.x - ct.home.x, pp.z - ct.home.z).magnitude;
                switch (ct.st)
                {
                    case 0: // armed
                        if (d2 < 1.7f && pp.y < 2.5f) { ct.st = 1; ct.t = 0.65f; }
                        break;
                    case 1: // warn — плита дрожит
                        ct.t -= Time.deltaTime;
                        ct.plate.position = ct.home + new Vector3(Random.Range(-0.06f, 0.06f), Random.Range(-0.05f, 0.02f), Random.Range(-0.06f, 0.06f));
                        if (ct.t <= 0f) ct.st = 2;
                        break;
                    case 2: // fall
                        ct.plate.position += Vector3.down * (20f * Time.deltaTime);
                        if (ct.plate.position.y <= 0.2f)
                        {
                            ct.plate.position = new Vector3(ct.home.x, 0.2f, ct.home.z);
                            ct.st = 3; ct.t = 10f;
                            if (d2 < 1.7f && pp.y < 2.2f && _knockLock <= 0f)
                                Knockdown(GridData.STAGE2_ENTRY, ct.plate.position, "ПОТОЛОК РУХНУЛ! Тебя откопали у входа на этап");
                        }
                        break;
                    case 3: // debris
                        ct.t -= Time.deltaTime;
                        if (ct.t <= 0f) { ct.plate.position = ct.home; ct.st = 0; }
                        break;
                }
            }
        }
    }
}
