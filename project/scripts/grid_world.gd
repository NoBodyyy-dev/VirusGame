extends Node3D

## ГРИД ПО КАРТЕ: этап 0 (коробка) → этап 1 (ночной мегаполис, сервер на
## платформе, лестница из блоков) → этап 2 (затхлые офисы: ярус, лифт на
## рычагах/проводах/роутере, паутина, падающие потолки, мох) → этап 3
## (бункер: 3 генератора, провода, рычаги, ловушки, блок-отключатель,
## паркур и перелёты по проводам, сирена на 28/28) → ОРАКУЛ (15 головоломок,
## захват территорий, 10 роботов, кража данных, разрушение ядра, побег)
## → белый туннель победы.
## Двери серверных комнат вскрываются головоломкой «СХЕМА ВЗЛОМА».

const HUDScript: = preload("res://scripts/grid_hud.gd")
const EvolutionScript: = preload("res://scripts/evolution_ui.gd")
const HoloShader: = preload("res://shaders/hologram.gdshader")

const TIER_COLORS: = [Color("35e0ff"), Color("ffb454"), Color("ff5d8f"), Color("8b5cff")]
const INFECTED_COLOR: = Color("2fe6b0")
const LOCKED_COLOR: = Color("3a4a55")
const ORACLE_COLOR: = Color("ff2d4a")
const CODE_GLYPHS: = "01アイウエオ<>#$%&=+?ABCDEF"

const WALL_T: = 1.0        # толщина стен
const DOOR_H: = 4.0        # высота дверных проёмов
const BLOCK: = 1.5         # ребро переносного блока (и шаг сетки установки)
const LIFT_CYCLE: = 8.4    # период лифта: подъём 3с · пауза 1.2 · спуск 3 · пауза 1.2

## проёмы в стенах комнат: n/s — "c" по X, e/w — "c" по Z (см. GameState.GRID_ROOMS)
const ROOM_GAPS: = {
	"r0": {"n": [{"c": 0.0, "w": 4.0}]},
	"a1": {"s": [{"c": 0.0, "w": 4.0}], "e": [{"c": -35.0, "w": 6.0}], "w": [{"c": -26.0, "w": 3.4}]},
	"b1": {"w": [{"c": -35.0, "w": 6.0}], "s": [{"c": 36.0, "w": 3.4}], "n": [{"c": 48.0, "w": 6.0}]},
	"s1a": {"e": [{"c": -26.0, "w": 3.4}]},
	"s1b": {"n": [{"c": 36.0, "w": 3.4}]},
	"c2": {"s": [{"c": 48.0, "w": 6.0}], "w": [{"c": -94.0, "w": 3.4}], "n": [{"c": 36.0, "w": 4.0}], "e": [{"c": -112.0, "w": 6.0}]},
	"d2": {"w": [{"c": -112.0, "w": 6.0}], "s": [{"c": 106.0, "w": 4.0}], "e": [{"c": -129.0, "w": 3.4}], "n": [{"c": 98.0, "w": 6.0}]},
	"srv2a": {"s": [{"c": 36.0, "w": 4.0}]},
	"srv2b": {"n": [{"c": 106.0, "w": 4.0}]},
	"s2a": {"e": [{"c": -94.0, "w": 3.4}]},
	"s2b": {"w": [{"c": -129.0, "w": 3.4}]},
	"e1": {"s": [{"c": 98.0, "w": 6.0}], "w": [{"c": -198.0, "w": 4.0}], "e": [{"c": -203.0, "w": 6.0}]},
	"e2": {"w": [{"c": -203.0, "w": 6.0}], "e": [{"c": -212.0, "w": 4.0}], "n": [{"c": 131.0, "w": 6.0}]},
	"e3": {"s": [{"c": 131.0, "w": 6.0}], "w": [{"c": -247.0, "w": 6.0}], "n": [{"c": 110.0, "w": 3.4}, {"c": 122.0, "w": 6.0}]},
	"e4": {"e": [{"c": -247.0, "w": 6.0}], "s": [{"c": 76.0, "w": 4.0}]},
	"srv3a": {"e": [{"c": -198.0, "w": 4.0}]},
	"srv3b": {"w": [{"c": -212.0, "w": 4.0}]},
	"srv3c": {"n": [{"c": 76.0, "w": 4.0}]},
	"s3a": {"s": [{"c": 110.0, "w": 3.4}]},
	"or": {"s": [{"c": 122.0, "w": 6.0}]},
}

## туннели между этапами: энерго-барьер (открывается по серверам этапа)
## и двери-головоломки внутри. opz — зачёт в 15 головоломок Оракула
const TUNNELS: = [
	{"key": "t12", "x0": 45.0, "x1": 51.0, "zs": -56.0, "zn": -78.0, "gate_zone": 0, "to": "КО 2 УРОВНЮ",
		"doors": [{"z": -67.0, "key": "d_t12", "diff": 2, "opz": ""}]},
	{"key": "t23", "x0": 95.0, "x1": 101.0, "zs": -152.0, "zn": -176.0, "gate_zone": 1, "to": "К 3 УРОВНЮ",
		"doors": [{"z": -161.0, "key": "d_t23a", "diff": 2, "opz": ""}, {"z": -169.0, "key": "d_t23b", "diff": 3, "opz": ""}]},
	{"key": "t3o", "x0": 119.0, "x1": 125.0, "zs": -264.0, "zn": -290.0, "gate_zone": 2, "to": "К ОРАКУЛУ",
		"doors": [{"z": -272.0, "key": "d_t3oa", "diff": 3, "opz": "opz:1"},
			{"z": -279.0, "key": "d_t3ob", "diff": 4, "opz": "opz:2"},
			{"z": -286.0, "key": "d_t3oc", "diff": 4, "opz": "opz:3"}]},
]

## двери серверных комнат и секреток: у какой комнаты, на какой стене
const PUZZLE_DOORS: = [
	{"key": "d_s1a", "room": "s1a", "side": "e", "c": -26.0, "w": 3.4, "diff": 1, "power": false, "opz": ""},
	{"key": "d_s1b", "room": "s1b", "side": "n", "c": 36.0, "w": 3.4, "diff": 1, "power": false, "opz": ""},
	{"key": "d_srv2a", "room": "srv2a", "side": "s", "c": 36.0, "w": 4.0, "diff": 2, "power": false, "opz": ""},
	{"key": "d_srv2b", "room": "srv2b", "side": "n", "c": 106.0, "w": 4.0, "diff": 2, "power": false, "opz": ""},
	{"key": "d_s2a", "room": "s2a", "side": "e", "c": -94.0, "w": 3.4, "diff": 2, "power": false, "opz": ""},
	{"key": "d_s2b", "room": "s2b", "side": "w", "c": -129.0, "w": 3.4, "diff": 2, "power": false, "opz": ""},
	{"key": "d_srv3a", "room": "srv3a", "side": "e", "c": -198.0, "w": 4.0, "diff": 3, "power": true, "opz": ""},
	{"key": "d_srv3b", "room": "srv3b", "side": "w", "c": -212.0, "w": 4.0, "diff": 3, "power": true, "opz": ""},
	{"key": "d_srv3c", "room": "srv3c", "side": "n", "c": 76.0, "w": 4.0, "diff": 3, "power": true, "opz": ""},
	{"key": "d_s3a", "room": "s3a", "side": "s", "c": 110.0, "w": 3.4, "diff": 3, "power": true, "opz": ""},
]

## переносные блоки этапа 1 (лестница к серверу на платформе)
const BLOCK_DEFAULTS: = [
	{"id": 0, "pos": Vector3(18.0, 0.75, -30.0), "weight": 1},
	{"id": 1, "pos": Vector3(24.0, 0.75, -44.0), "weight": 1},
	{"id": 2, "pos": Vector3(30.0, 0.75, -52.0), "weight": 1},
	{"id": 3, "pos": Vector3(46.0, 0.75, -34.0), "weight": 2},
	{"id": 4, "pos": Vector3(52.0, 0.75, -50.0), "weight": 2},
]

## головоломки-пилоны Оракула (12 в зале + 3 двери туннеля = 15)
const ORACLE_PYLONS: = [
	{"key": "opz:4", "pos": Vector3(84, 0, -300), "diff": 3},
	{"key": "opz:5", "pos": Vector3(160, 0, -298), "diff": 3},
	{"key": "opz:6", "pos": Vector3(168, 0, -322), "diff": 3},
	{"key": "opz:7", "pos": Vector3(80, 0, -330), "diff": 3},
	{"key": "opz:8", "pos": Vector3(94, 0, -356), "diff": 4},
	{"key": "opz:9", "pos": Vector3(160, 0, -352), "diff": 4},
	{"key": "opz:10", "pos": Vector3(110, 0, -306), "diff": 3},
	{"key": "opz:11", "pos": Vector3(140, 0, -372), "diff": 4},
	{"key": "opz:12", "pos": Vector3(172, 0, -374), "diff": 4},
	{"key": "opz:13", "pos": Vector3(76, 0, -372), "diff": 4},
	{"key": "opz:14", "pos": Vector3(106, 0, -338), "diff": 5},
	{"key": "opz:15", "pos": Vector3(144, 0, -318), "diff": 5},
]

const ORACLE_TERRS: = [
	{"key": "oterr:1", "pos": Vector3(94, 0, -312)},
	{"key": "oterr:2", "pos": Vector3(154, 0, -316)},
	{"key": "oterr:3", "pos": Vector3(124, 0, -366)},
]

const ORACLE_RACKS_POS: = [
	{"key": "orack:1", "pos": Vector3(112, 0, -326)},
	{"key": "orack:2", "pos": Vector3(136, 0, -326)},
	{"key": "orack:3", "pos": Vector3(112, 0, -350)},
	{"key": "orack:4", "pos": Vector3(136, 0, -350)},
]

const ORACLE_CORE_POS: = Vector3(124, 0, -338)
const ORACLE_ENTRY: = Vector3(122, 0.3, -293)
const STAGE2_ENTRY: = Vector3(48, 0.3, -81)
const STAGE3_ENTRY: = Vector3(98, 0.3, -179)

## лазерные ловушки этапа 3 (отключаются блоком-отключателем)
const TRAP_BEAMS: = [
	{"a": Vector3(120, 0.6, -210), "b": Vector3(152, 0.6, -210), "phase": 0.0},
	{"a": Vector3(120, 0.6, -218), "b": Vector3(152, 0.6, -218), "phase": 1.5},
	{"a": Vector3(100, 0.6, -238), "b": Vector3(144, 0.6, -238), "phase": 0.7},
	{"a": Vector3(100, 0.6, -244), "b": Vector3(144, 0.6, -244), "phase": 2.2},
	{"a": Vector3(60, 0.6, -238), "b": Vector3(96, 0.6, -238), "phase": 1.1},
	{"a": Vector3(60, 0.6, -246), "b": Vector3(96, 0.6, -246), "phase": 2.8},
]

## падающие потолки этапа 2 (могут прибить)
const CEIL_TRAPS: = [
	{"pos": Vector3(40, 0, -96), "room": "c2"},
	{"pos": Vector3(56, 0, -110), "room": "c2"},
	{"pos": Vector3(86, 0, -116), "room": "d2"},
	{"pos": Vector3(100, 0, -136), "room": "d2"},
	{"pos": Vector3(118, 0, -126), "room": "d2"},
]

var player: VirusPlayer
var node_visuals: = {}
var motes: Array = []
var hud: Control
var env: Environment
var gates: Array = []         # энерго-барьеры туннелей (код переливается)

var _paused: = false
var pause_panel: Control
var top_layer: CanvasLayer
var _win_shown: = false
var evo_panel: Control
var avatars: = {}
var party: PartyFx
var _entering: = false
var _code_t: = 0.0

# ── интерактив Грида ──
var _doors: = {}              # key -> {mesh, body, label, panel_pos, diff, power, opz}
var _levers: = {}             # key -> {arm, label, pos, desc}
var _wires: = {}              # key -> {pylons: Array, label, color, desc}
var _gens: = {}               # key -> {glow, light, label, pos, wire}
var _routers: = {}            # key -> {led, label, pos}
var _blocks: = {}             # id -> {body, weight, label}
var _lifts: Array = []        # {body, x, z, y0, y1, power, label, t}
var _zips: Array = []         # {a, b, flag, segs_drawn, label_a, label_b}
var _traps: Array = []        # {beam, mat, a, b, phase, posts}
var _ceils: Array = []        # {plate, home, state, t}
var _terrs: = {}              # key -> {pos, ring_mat, label, prog}
var _racks: = {}              # key -> {label, screen, pos}
var _pylons: = {}             # key -> {label, orb_mat, pos, diff}
var _robots: Array = []       # {node, wp, t, stun}
var _core: = {}               # {label, shield, shield_body, core_mat, board}
var _escape: = {}             # {node, label, active}
var _flickers: Array = []     # мигающие офисные лампы {light, mat, t}
var _s3_lights: Array = []    # свет этапа 3, включается генераторами
var _s3_lamps: Array = []     # эмиссивные плафоны этапа 3
var _alert_lights: Array = [] # красные маячки 28/28
var _carrying_block: = -1
var _riding_zip: = false
var _puzzle_open: Control = null
var _hold_key: = ""
var _hold_t: = 0.0
var _siren_t: = 0.0
var _status_t: = 0.0
var _knock_lock: = 0.0
var _watch_t: = 0.0           # медленный тик: подхват флагов из коопа
var _s3_power_seen: = false
var prompt_target: Dictionary = {}

func _ready() -> void:
	if GameState.grid_nodes.is_empty():
		GameState.new_campaign()
	_build_environment()
	_build_rooms()
	_build_tunnels()
	_build_puzzle_doors()
	_build_stage0()
	_build_stage1()
	_build_stage2()
	_build_stage3()
	_build_oracle()
	_build_nodes()
	_build_motes()
	_spawn_player()
	_build_ui()
	_apply_stage3_power()
	_s3_power_seen = GameState.stage3_powered()
	if Net.active:
		_setup_coop()
		Net.sync_identity()
	Net.enter_fx.connect(_on_enter_fx)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Sfx.ambient(true, 1.15)
	if GameState.campaign_won:
		_show_win()

func _setup_coop() -> void:
	for id in Net.players:
		if id != Net.my_id():
			_spawn_avatar(id)
	Net.remote_pos.connect(_on_remote_pos)
	Net.peer_left.connect(_on_peer_left)
	Net.net_toast.connect(_on_net_toast)

func _spawn_avatar(id: int) -> void:
	var av: = RemoteAvatar.new()
	av.setup(id, Net.my_class_of(id), Net.player_name(id))
	av.position = Vector3(randf_range(-3.0, 3.0), 0.2, 4.0 + randf_range(-1.5, 1.5))
	av.target_pos = av.position
	add_child(av)
	avatars[id] = av

func _on_remote_pos(id: int, pos: Vector3, yaw: float, ratio: float) -> void:
	if id == Net.my_id():
		return
	if not avatars.has(id):
		if not Net.players.has(id):
			return
		_spawn_avatar(id)
	avatars[id].net_update(pos, yaw, ratio)

func _on_peer_left(id: int) -> void:
	if avatars.has(id):
		hud.flash_pickup("%s отключился" % Net.player_name(id))
		avatars[id].queue_free()
		avatars.erase(id)

func _on_net_toast(text: String, _color: Color) -> void:
	hud.flash_pickup(text)

func _actor_for(id: int) -> Node3D:
	if id == Net.my_id():
		return player
	return avatars.get(id)

# ── окружение ───────────────────────────────────────────────

func _build_environment() -> void:
	env = Environment.new()
	# ночной город: тёмное небо, звёздная дымка, луна
	var sky_mat: = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.015, 0.025, 0.055)
	sky_mat.sky_horizon_color = Color(0.08, 0.1, 0.18)
	sky_mat.ground_bottom_color = Color(0.008, 0.012, 0.025)
	sky_mat.ground_horizon_color = Color(0.06, 0.08, 0.14)
	sky_mat.sun_angle_max = 20.0
	var sky: = Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.05
	env.ssao_enabled = true
	env.ssao_intensity = 1.8
	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.08, 0.14)
	env.fog_density = 0.0028
	env.fog_sky_affect = 0.0
	var we: = WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var moon: = DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-55, 35, 0)
	moon.light_color = Color(0.55, 0.65, 0.88)
	moon.light_energy = 0.32
	moon.shadow_enabled = true
	add_child(moon)

# ── геометрические хелперы ──────────────────────────────────

func _neon(c: Color, e: = 1.8) -> StandardMaterial3D:
	var m: = StandardMaterial3D.new()
	m.albedo_color = Color(0.02, 0.03, 0.05)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m

func _holo_add(c: Color, alpha: float) -> StandardMaterial3D:
	var m: = StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	return m

func _mesh_box(size: Vector3, mat: Material, pos: Vector3, parent: Node3D = self) -> MeshInstance3D:
	var mi: = MeshInstance3D.new()
	var bm: = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _collide(size: Vector3, pos: Vector3) -> StaticBody3D:
	var sb: = StaticBody3D.new()
	sb.collision_layer = 1
	var cs: = CollisionShape3D.new()
	var box: = BoxShape3D.new()
	box.size = size
	cs.shape = box
	sb.position = pos
	sb.add_child(cs)
	add_child(sb)
	return sb

func _solid(size: Vector3, mat: Material, pos: Vector3) -> void:
	_mesh_box(size, mat, pos)
	_collide(size, pos)

func _label3d(text: String, pos: Vector3, size: int, color: Color, billboard: = true, parent: Node3D = self) -> Label3D:
	var l: = Label3D.new()
	l.text = text
	l.font_size = size
	l.modulate = color
	l.outline_size = maxi(size / 6, 4)
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = pos
	parent.add_child(l)
	return l

func _omni(pos: Vector3, color: Color, energy: float, range_m: float, parent: Node3D = self) -> OmniLight3D:
	var ol: = OmniLight3D.new()
	ol.light_color = color
	ol.light_energy = energy
	ol.omni_range = range_m
	ol.position = pos
	parent.add_child(ol)
	return ol

func _spot_down(pos: Vector3, color: Color, energy: float, range_m: float, angle: = 55.0) -> SpotLight3D:
	var sl: = SpotLight3D.new()
	sl.light_color = color
	sl.light_energy = energy
	sl.spot_range = range_m
	sl.spot_angle = angle
	sl.position = pos
	sl.rotation_degrees = Vector3(-90, 0, 0)
	add_child(sl)
	return sl

## стена вдоль X на линии z (n/s), с проёмами; gap: {"c": x, "w": ширина}
func _wall_ns(x0: float, x1: float, z: float, h: float, mat: Material, gaps: Array = []) -> void:
	var sorted: = gaps.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["c"] < b["c"])
	var cursor: = x0
	for g in sorted:
		var gx0: float = g["c"] - g["w"] * 0.5
		var gx1: float = g["c"] + g["w"] * 0.5
		if gx0 - cursor > 0.05:
			_solid(Vector3(gx0 - cursor, h, WALL_T), mat, Vector3((cursor + gx0) * 0.5, h * 0.5, z))
		if h - DOOR_H > 0.05:
			_solid(Vector3(g["w"], h - DOOR_H, WALL_T), mat, Vector3(g["c"], DOOR_H + (h - DOOR_H) * 0.5, z))
		cursor = gx1
	if x1 - cursor > 0.05:
		_solid(Vector3(x1 - cursor, h, WALL_T), mat, Vector3((cursor + x1) * 0.5, h * 0.5, z))

## стена вдоль Z на линии x (e/w); gap: {"c": z, "w": ширина}
func _wall_ew(z_s: float, z_n: float, x: float, h: float, mat: Material, gaps: Array = []) -> void:
	var sorted: = gaps.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["c"] > b["c"])
	var cursor: = z_s   # юг (больше) → север (меньше)
	for g in sorted:
		var gz0: float = g["c"] + g["w"] * 0.5   # южный край проёма
		var gz1: float = g["c"] - g["w"] * 0.5
		if cursor - gz0 > 0.05:
			_solid(Vector3(WALL_T, h, cursor - gz0), mat, Vector3(x, h * 0.5, (cursor + gz0) * 0.5))
		if h - DOOR_H > 0.05:
			_solid(Vector3(WALL_T, h - DOOR_H, g["w"]), mat, Vector3(x, DOOR_H + (h - DOOR_H) * 0.5, g["c"]))
		cursor = gz1
	if cursor - z_n > 0.05:
		_solid(Vector3(WALL_T, h, cursor - z_n), mat, Vector3(x, h * 0.5, (cursor + z_n) * 0.5))

func _room_rect(key: String) -> Dictionary:
	return GameState.GRID_ROOMS[key]

func _room_center(key: String) -> Vector3:
	var r: Dictionary = _room_rect(key)
	return Vector3((r["x0"] + r["x1"]) * 0.5, 0.0, (r["zs"] + r["zn"]) * 0.5)

func _wall_mat_for_stage(stage: int) -> StandardMaterial3D:
	match stage:
		0: return Mats.concrete(Color(0.38, 0.39, 0.42))
		1: return Mats.brick()
		2: return Mats.plaster_old()
		3: return Mats.bunker_wall()
	return Mats.obsidian()

func _floor_mat_for_stage(stage: int) -> StandardMaterial3D:
	match stage:
		0: return Mats.concrete(Color(0.3, 0.31, 0.33), 0.2)
		1: return Mats.sidewalk()
		2: return Mats.carpet_rot()
		3: return Mats.concrete(Color(0.26, 0.27, 0.28), 0.2)
	return Mats.obsidian()

# ── комнаты по карте ────────────────────────────────────────

func _build_rooms() -> void:
	for key in GameState.GRID_ROOMS:
		var r: Dictionary = GameState.GRID_ROOMS[key]
		var stage: int = r["stage"]
		var x0: float = r["x0"]
		var x1: float = r["x1"]
		var zs: float = r["zs"]
		var zn: float = r["zn"]
		var h: float = r["h"]
		var w: = x1 - x0
		var d: = zs - zn
		var cx: = (x0 + x1) * 0.5
		var cz: = (zs + zn) * 0.5
		var wall_mat: = _wall_mat_for_stage(stage)
		var floor_mat: = _floor_mat_for_stage(stage)
		# пол — плита с верхом на y=0
		_solid(Vector3(w, 0.5, d), floor_mat, Vector3(cx, -0.25, cz))
		# стены с проёмами (смещены внутрь на полтолщины)
		var gaps: Dictionary = ROOM_GAPS.get(key, {})
		_wall_ns(x0, x1, zs - WALL_T * 0.5, h, wall_mat, gaps.get("s", []))
		_wall_ns(x0, x1, zn + WALL_T * 0.5, h, wall_mat, gaps.get("n", []))
		_wall_ew(zs, zn, x0 + WALL_T * 0.5, h, wall_mat, gaps.get("w", []))
		_wall_ew(zs, zn, x1 - WALL_T * 0.5, h, wall_mat, gaps.get("e", []))
		# потолки: этап 1 под открытым небом города, остальное закрыто
		if stage != 1 or r.get("secret", false):
			var ceil_mat: = wall_mat if stage != 2 else Mats.plaster_old(Color(0.42, 0.4, 0.35))
			_solid(Vector3(w, 0.35, d), ceil_mat, Vector3(cx, h + 0.175, cz))
	# короткий переход этап 0 → этап 1 (между r0 и a1)
	var pass_mat: = Mats.concrete(Color(0.38, 0.39, 0.42))
	_solid(Vector3(4.0, 0.5, 2.0), pass_mat, Vector3(0, -0.25, -7.0))
	for side in [-1.0, 1.0]:
		_solid(Vector3(WALL_T, DOOR_H, 2.0), pass_mat, Vector3(side * 2.5, DOOR_H * 0.5, -7.0))
	_solid(Vector3(6.0, 0.5, 2.0), pass_mat, Vector3(0, DOOR_H + 0.25, -7.0))
	# крупные надписи уровней (как на карте)
	_stage_title("0 УРОВЕНЬ", Vector3(0, 4.5, 2.0), Color(0.65, 0.75, 0.85))
	_stage_title("1 УРОВЕНЬ", Vector3(0, 7.5, -26.0), TIER_COLORS[0])
	_stage_title("1 УРОВЕНЬ", Vector3(32, 7.5, -41.0), TIER_COLORS[0])
	_stage_title("2 УРОВЕНЬ", Vector3(47, 8.5, -97.0), TIER_COLORS[1])
	_stage_title("2 УРОВЕНЬ", Vector3(98, 10.5, -130.0), TIER_COLORS[1])
	_stage_title("3 УРОВЕНЬ", Vector3(96, 8.5, -194.0), TIER_COLORS[2])
	_stage_title("3 УРОВЕНЬ", Vector3(136, 7.5, -211.0), TIER_COLORS[2])
	_stage_title("3 УРОВЕНЬ", Vector3(122, 9.5, -245.0), TIER_COLORS[2])
	_stage_title("3 УРОВЕНЬ", Vector3(78, 7.5, -247.0), TIER_COLORS[2])
	_stage_title("ОРАКУЛ", Vector3(124, 18.0, -338.0), ORACLE_COLOR)

func _stage_title(text: String, pos: Vector3, color: Color) -> void:
	var l: = _label3d(text, pos, 240, Color(color.r, color.g, color.b, 0.5), true)
	l.no_depth_test = false
	l.outline_size = 18

# ── туннели между этапами ───────────────────────────────────

func _build_tunnels() -> void:
	for t in TUNNELS:
		var x0: float = t["x0"]
		var x1: float = t["x1"]
		var zs: float = t["zs"]
		var zn: float = t["zn"]
		var w: = x1 - x0
		var cx: = (x0 + x1) * 0.5
		var cz: = (zs + zn) * 0.5
		var d: = zs - zn
		var mat: = Mats.metal_dark(0.55)
		var h: = 5.0
		_solid(Vector3(w, 0.5, d), Mats.deck_metal(Color(0.3, 0.32, 0.35)), Vector3(cx, -0.25, cz))
		_wall_ew(zs, zn, x0 + WALL_T * 0.5, h, mat, [])
		_wall_ew(zs, zn, x1 - WALL_T * 0.5, h, mat, [])
		_solid(Vector3(w, 0.35, d), mat, Vector3(cx, h + 0.175, cz))
		# рёбра жёсткости и лампы вдоль туннеля
		var step: = d / 4.0
		for i in 3:
			var rz: = zs - step * float(i + 1)
			_mesh_box(Vector3(w, 0.25, 0.25), Mats.rust(), Vector3(cx, h - 0.3, rz))
			_mesh_box(Vector3(0.7, 0.1, 0.28), _neon(Color(0.55, 0.75, 0.95), 2.0), Vector3(cx, h - 0.12, rz))
			_omni(Vector3(cx, h - 0.8, rz), Color(0.55, 0.75, 0.95), 0.9, 7.0)
		# энерго-барьер: открывается по серверам этапа
		_build_stage_gate(t)
		# двери-головоломки внутри
		for dd in t["doors"]:
			_make_door(dd["key"], Vector3(cx, 0, dd["z"]), w - WALL_T * 2.0, "x",
				dd["diff"], t["key"] == "t3o", dd["opz"], Mats.rust())
		_label3d("ТУННЕЛЬ С ГОЛОВОЛОМКАМИ\nНА ПРОХОЖДЕНИЕ %s" % t["to"],
			Vector3(cx, 3.6, zs - 2.6), 30, Color(0.55, 0.75, 0.95))

func _build_stage_gate(t: Dictionary) -> void:
	## полупрозрачная стена с кодом: закрыта, пока не взломаны все серверы этапа
	var zone: int = t["gate_zone"]
	var done: = GameState.zone_complete(zone)
	var cx: float = (t["x0"] + t["x1"]) * 0.5
	var gw: float = t["x1"] - t["x0"] - WALL_T * 2.0
	var gz: float = t["zs"] - 1.6
	var gate_mat: = StandardMaterial3D.new()
	gate_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gate_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gate_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gate_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var gate_col: = ORACLE_COLOR if t["key"] == "t3o" else Color(0.2, 0.55, 1.0)
	gate_mat.albedo_color = Color(gate_col.r, gate_col.g, gate_col.b, 0.08 if done else 0.28)
	_mesh_box(Vector3(gw, DOOR_H, 0.3), gate_mat, Vector3(cx, DOOR_H * 0.5, gz))
	_mesh_box(Vector3(gw + 0.5, 0.25, 0.4), _neon(gate_col, 2.2), Vector3(cx, DOOR_H + 0.15, gz))
	for side in [-1.0, 1.0]:
		_mesh_box(Vector3(0.25, DOOR_H + 0.3, 0.4), _neon(gate_col, 2.2), Vector3(cx + side * (gw * 0.5 + 0.1), DOOR_H * 0.5, gz))
	_omni(Vector3(cx, 3.0, gz + 2.0), gate_col, 1.8, 10.0)
	var code: = _label3d(_random_code(), Vector3(cx, 2.2, gz + 0.3), 22, Color(gate_col.r, gate_col.g, gate_col.b, 0.85), false)
	var code2: = _label3d(_random_code(), Vector3(cx, 2.2, gz - 0.3), 22, Color(gate_col.r, gate_col.g, gate_col.b, 0.85), false)
	code2.rotation.y = PI
	gates.append({"labels": [code, code2], "mat": gate_mat})
	if not done:
		_collide(Vector3(gw, DOOR_H, 0.4), Vector3(cx, DOOR_H * 0.5, gz))
	var status: = "ПРОХОД ОТКРЫТ ▸" if done else "ЗАБЛОКИРОВАНО: серверы этапа %d/%d" % [
		GameState.zone_infected(zone), GameState.zone_total(zone)]
	if t["key"] == "t3o" and not done:
		status = "ЗАБЛОКИРОВАНО: активируйте 28 серверов (%d/28)" % GameState.infected_total()
	_label3d(status, Vector3(cx, DOOR_H + 1.3, gz + 0.6), 34,
		INFECTED_COLOR if done else Color(gate_col.r, gate_col.g, gate_col.b))

func _random_code() -> String:
	var s: = ""
	for row in 3:
		for i in 10:
			s += CODE_GLYPHS[randi() % CODE_GLYPHS.length()]
		if row < 2:
			s += "\n"
	return s

# ── двери-головоломки ───────────────────────────────────────

func _build_puzzle_doors() -> void:
	for dd in PUZZLE_DOORS:
		var r: Dictionary = _room_rect(dd["room"])
		var pos: = Vector3.ZERO
		var axis: = "x"
		match dd["side"]:
			"n": pos = Vector3(dd["c"], 0, r["zn"])
			"s": pos = Vector3(dd["c"], 0, r["zs"])
			"e":
				pos = Vector3(r["x1"], 0, dd["c"])
				axis = "z"
			"w":
				pos = Vector3(r["x0"], 0, dd["c"])
				axis = "z"
		var stage: int = r["stage"]
		var mat: Material = Mats.rust() if stage == 3 else (Mats.metal(Color(0.45, 0.44, 0.4), 0.5) if stage == 2 else Mats.metal_dark(0.4))
		_make_door(dd["key"], pos, dd["w"], axis, dd["diff"], dd["power"], dd["opz"], mat)

func _make_door(key: String, pos: Vector3, w: float, axis: String, diff: int,
		needs_power: bool, opz: String, mat: Material) -> void:
	## сдвижная дверь с терминалом-головоломкой; решённая — утоплена в пол
	var solved: = GameState.flag("door:" + key)
	var size: = Vector3(w, DOOR_H, 1.2) if axis == "x" else Vector3(1.2, DOOR_H, w)
	var mesh: = _mesh_box(size, mat, Vector3(pos.x, DOOR_H * 0.5, pos.z))
	# светящийся шов и рамка
	var seam_col: = INFECTED_COLOR if solved else Color(1.0, 0.45, 0.2)
	var seam_size: = Vector3(w * 0.9, 0.1, 1.3) if axis == "x" else Vector3(1.3, 0.1, w * 0.9)
	var seam: = _mesh_box(seam_size, _neon(seam_col, 1.4), Vector3(pos.x, 2.0, pos.z))
	seam.set_meta("door_seam", true)
	var body: StaticBody3D = null
	if not solved:
		body = _collide(size, Vector3(pos.x, DOOR_H * 0.5, pos.z))
	else:
		mesh.position.y = -DOOR_H * 0.5 + 0.25
		seam.position.y = 0.35
	var lbl: = _label3d("", Vector3(pos.x, DOOR_H + 0.9, pos.z), 26, seam_col)
	_doors[key] = {"mesh": mesh, "seam": seam, "body": body, "label": lbl,
		"pos": Vector3(pos.x, 0, pos.z), "diff": diff, "power": needs_power, "opz": opz}
	_refresh_door_label(key)

func _refresh_door_label(key: String) -> void:
	var d: Dictionary = _doors[key]
	var lbl: Label3D = d["label"]
	if GameState.flag("door:" + key):
		lbl.text = "ДВЕРЬ ОТКРЫТА"
		lbl.modulate = INFECTED_COLOR
	elif d["power"] and not GameState.stage3_powered():
		lbl.text = "ДВЕРЬ ОБЕСТОЧЕНА\nзапустите генераторы (%d/3) и рубильник" % GameState.stage3_generators_on()
		lbl.modulate = Color(0.85, 0.35, 0.3)
	else:
		lbl.text = "ЗАПЕРТО\n[E] решить головоломку"
		lbl.modulate = Color(1.0, 0.6, 0.25)

func _open_door(key: String) -> void:
	var d: Dictionary = _doors[key]
	GameState.set_flag("door:" + key)
	if d["body"] != null and is_instance_valid(d["body"]):
		d["body"].queue_free()
		d["body"] = null
	var mesh: MeshInstance3D = d["mesh"]
	var seam: MeshInstance3D = d["seam"]
	var tw: = create_tween()
	tw.set_parallel(true)
	tw.tween_property(mesh, "position:y", -DOOR_H * 0.5 + 0.25, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(seam, "position:y", 0.35, 1.1)
	var seam_mat: StandardMaterial3D = seam.material_override
	seam_mat.emission = INFECTED_COLOR
	Sfx.play("layer_done", -4.0, 0.9)
	if d["opz"] != "":
		GameState.set_flag(d["opz"])
		hud.flash_pickup("ГОЛОВОЛОМКИ ОРАКУЛА: %d/%d" % [GameState.oracle_puzzles_done(), GameState.ORACLE_PUZZLES_TOTAL])
		_refresh_oracle_shield()
	_refresh_door_label(key)

# ── этап 0: коробка без интерактива ─────────────────────────

func _build_stage0() -> void:
	# статичные декорации: трубы, ящики, вывеска — и ничего живого
	var pipe_mat: = Mats.metal(Color(0.42, 0.44, 0.48), 0.5)
	for i in 2:
		var pipe: = MeshInstance3D.new()
		var pc: = CylinderMesh.new()
		pc.top_radius = 0.18
		pc.bottom_radius = 0.18
		pc.height = 16.0
		pipe.mesh = pc
		pipe.rotation.z = deg_to_rad(90.0)
		pipe.material_override = pipe_mat
		pipe.position = Vector3(0, 5.0 - float(i) * 0.6, 8.6 - float(i) * 0.5)
		add_child(pipe)
	_solid(Vector3(1.6, 1.4, 1.6), Mats.plastic(Color(0.4, 0.36, 0.3)), Vector3(-6.5, 0.7, 6.5))
	_solid(Vector3(1.3, 1.1, 1.3), Mats.plastic(Color(0.35, 0.32, 0.27)), Vector3(-5.2, 0.55, 7.2))
	_mesh_box(Vector3(5.0, 1.4, 0.2), Mats.metal_dark(0.4), Vector3(0, 3.4, 9.4))
	_label3d("ГРИД // СЕКТОР 0", Vector3(0, 3.4, 9.2), 42, Color(0.65, 0.8, 0.9), false)
	_label3d("ПЕРЕХОД НА 1 УРОВЕНЬ ▸", Vector3(0, 4.6, -5.2), 30, TIER_COLORS[0], false)
	_omni(Vector3(0, 5.0, 2.0), Color(1.0, 0.9, 0.75), 1.4, 14.0)
	_spot_down(Vector3(0, 5.6, -4.0), Color(0.55, 0.8, 1.0), 2.2, 9.0)

# ── этап 1: ночной мегаполис ────────────────────────────────

func _build_stage1() -> void:
	var rng: = RandomNumberGenerator.new()
	rng.seed = 1001
	_build_city_skyline(rng)
	_build_city_rain()
	# уличные фонари: тёплые пятна света
	for lp in [Vector3(-6, 0, -16), Vector3(6, 0, -36), Vector3(16, 0, -32),
			Vector3(30, 0, -50), Vector3(48, 0, -30), Vector3(24, 0, -38)]:
		_street_lamp(lp)
	# неоновые вывески на кирпичных стенах (yaw: куда смотрит текст)
	_neon_sign("ГРИД-СИТИ", Vector3(0, 6.5, -43.2), Color(0.2, 0.85, 1.0), 0.0)
	_neon_sign("24/7 DATA", Vector3(8.4, 5.4, -30.0), Color(1.0, 0.35, 0.6), -PI * 0.5)
	_neon_sign("不夜城", Vector3(54.2, 6.2, -40.0), Color(1.0, 0.7, 0.2), -PI * 0.5)
	_neon_sign("メガポリス", Vector3(28.0, 6.8, -55.2), Color(0.55, 0.4, 1.0), 0.0)
	# мокрые лужи с отражениями
	for pp in [Vector3(4, 0, -24), Vector3(20, 0, -34), Vector3(38, 0, -52), Vector3(-2, 0, -40)]:
		var puddle: = _mesh_box(Vector3(3.4, 0.03, 2.6), Mats.wet_floor(Color(0.14, 0.16, 0.2)), pp + Vector3(0, 0.03, 0))
		puddle.rotation.y = randf_range(0.0, TAU)
	# платформа сервера: заберёшься, только выстроив лестницу из блоков
	_build_server_platform()
	_build_push_blocks()
	# бонусные ящики в секретках
	_label3d("СЕКРЕТНАЯ КОМНАТА", Vector3(-15, 3.2, -26), 26, Color(0.9, 0.75, 0.3))
	_label3d("СЕКРЕТНАЯ КОМНАТА", Vector3(36, 3.2, -20), 26, Color(0.9, 0.75, 0.3))

func _build_city_skyline(rng: RandomNumberGenerator) -> void:
	## высотки с горящими окнами вокруг этапа 1 — стиль ночного мегаполиса
	var spots: = [
		Vector3(-32, 0, -12), Vector3(-34, 0, -40), Vector3(-20, 0, -64),
		Vector3(6, 0, -72), Vector3(28, 0, -74), Vector3(62, 0, -68),
		Vector3(72, 0, -42), Vector3(68, 0, -14), Vector3(48, 0, 6),
		Vector3(22, 0, 12), Vector3(-4, 0, 16), Vector3(-20, 0, 6),
	]
	for i in spots.size():
		var p: Vector3 = spots[i]
		var w: = rng.randf_range(8.0, 14.0)
		var h: = rng.randf_range(24.0, 46.0)
		var tower: = _mesh_box(Vector3(w, h, w), Mats.city_windows(81 + i), p + Vector3(0, h * 0.5, 0))
		tower.rotation.y = rng.randf_range(-0.15, 0.15)
		# крыша с сигнальным огнём
		_mesh_box(Vector3(w * 0.4, 1.2, w * 0.4), Mats.metal_dark(0.6), p + Vector3(0, h + 0.6, 0))
		if i % 2 == 0:
			_mesh_box(Vector3(0.3, 0.3, 0.3), _neon(Color(1.0, 0.2, 0.2), 3.0), p + Vector3(0, h + 1.6, 0))

func _build_city_rain() -> void:
	var parts: = GPUParticles3D.new()
	parts.amount = 650
	parts.lifetime = 1.4
	parts.preprocess = 1.4
	var pm: = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(40.0, 1.0, 32.0)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 2.0
	pm.initial_velocity_min = 10.0
	pm.initial_velocity_max = 14.0
	pm.gravity = Vector3.ZERO
	parts.process_material = pm
	var quad: = QuadMesh.new()
	quad.size = Vector2(0.025, 0.55)
	var qm: = StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	qm.albedo_color = Color(0.45, 0.6, 0.8, 0.28)
	quad.material = qm
	parts.draw_pass_1 = quad
	parts.position = Vector3(17.0, 13.0, -32.0)
	add_child(parts)

func _street_lamp(pos: Vector3) -> void:
	_solid(Vector3(0.22, 5.0, 0.22), Mats.metal_dark(0.6), pos + Vector3(0, 2.5, 0))
	_mesh_box(Vector3(1.3, 0.16, 0.45), Mats.metal_dark(0.6), pos + Vector3(0.55, 5.0, 0))
	_mesh_box(Vector3(0.75, 0.1, 0.32), _neon(Color(1.0, 0.85, 0.55), 3.0), pos + Vector3(0.65, 4.9, 0))
	var sl: = _spot_down(pos + Vector3(0.65, 4.8, 0), Color(1.0, 0.85, 0.55), 3.2, 10.0, 48.0)
	sl.shadow_enabled = false

func _neon_sign(text: String, pos: Vector3, color: Color, yaw: float) -> void:
	## табличка на стене; yaw — куда смотрит текст (0 = на юг, −PI/2 = на −X)
	var facing: = Vector3(sin(yaw), 0.0, cos(yaw))
	var wide: = float(text.length()) * 0.85 + 1.0
	var panel_size: = Vector3(0.15, 1.4, wide) if absf(facing.x) > 0.5 else Vector3(wide, 1.4, 0.15)
	_mesh_box(panel_size, Mats.metal_dark(0.5), pos)
	var l: = _label3d(text, pos + facing * 0.18, 64, color, false)
	l.rotation.y = yaw
	_omni(pos + facing * 1.2, color, 1.3, 7.0)

func _build_server_platform() -> void:
	## сервер этапа 1 стоит на высокой платформе (верх на y=4.5)
	var deck: = Mats.deck_metal()
	_solid(Vector3(6.0, 0.5, 6.0), deck, Vector3(40, 4.25, -46))
	for corner in [Vector3(37.6, 0, -43.6), Vector3(42.4, 0, -43.6), Vector3(37.6, 0, -48.4), Vector3(42.4, 0, -48.4)]:
		_solid(Vector3(0.5, 4.0, 0.5), Mats.metal(Color(0.4, 0.42, 0.46), 0.45), corner + Vector3(0, 2.0, 0))
	# светящаяся окантовка и сигнальные полосы
	_mesh_box(Vector3(6.2, 0.08, 6.2), _neon(TIER_COLORS[0], 0.9), Vector3(40, 4.54, -46))
	for side in [-1.0, 1.0]:
		_mesh_box(Vector3(6.0, 0.3, 0.1), Mats.hazard(), Vector3(40, 4.1, -46 + side * 3.05))
		_mesh_box(Vector3(0.1, 0.3, 6.0), Mats.hazard(), Vector3(40 + side * 3.05, 4.1, -46))
	_label3d("СЕРВЕР НА ВЫСОТЕ\nперенеси блоки [E] и выстрой лестницу", Vector3(40, 7.2, -46), 30, TIER_COLORS[0])

func _build_push_blocks() -> void:
	## переносные блоки: лёгкие — в одиночку, тяжёлые — вдвоём или RANSOMWARE.
	## позиции переживают рейды (GameState.block_positions); кооп не синкает
	## блоки — лестницу строит хост
	for bd in BLOCK_DEFAULTS:
		var id: int = bd["id"]
		var pos: Vector3 = GameState.block_positions.get(id, bd["pos"])
		var body: = AnimatableBody3D.new()
		body.sync_to_physics = false
		body.collision_layer = 1
		var cs: = CollisionShape3D.new()
		var box: = BoxShape3D.new()
		box.size = Vector3(BLOCK, BLOCK, BLOCK)
		cs.shape = box
		body.add_child(cs)
		var mesh: = MeshInstance3D.new()
		var bm: = BoxMesh.new()
		bm.size = Vector3(BLOCK, BLOCK, BLOCK)
		mesh.mesh = bm
		mesh.material_override = Mats.deck_metal(Color(0.42, 0.4, 0.36)) if bd["weight"] == 1 else Mats.rust(Color(0.42, 0.3, 0.2))
		body.add_child(mesh)
		var edge: = MeshInstance3D.new()
		var em: = BoxMesh.new()
		em.size = Vector3(BLOCK * 1.02, 0.08, BLOCK * 1.02)
		edge.mesh = em
		edge.material_override = _neon(TIER_COLORS[0] if bd["weight"] == 1 else Color(1.0, 0.5, 0.2), 0.8)
		edge.position.y = BLOCK * 0.5 - 0.06
		body.add_child(edge)
		body.position = pos
		add_child(body)
		var cap: = "БЛОК" if bd["weight"] == 1 else "ТЯЖЁЛЫЙ БЛОК [×2]"
		var lbl: = _label3d(cap, Vector3(0, BLOCK * 0.5 + 0.6, 0), 20,
			Color(0.7, 0.85, 0.95) if bd["weight"] == 1 else Color(1.0, 0.6, 0.3), true, body)
		_blocks[id] = {"body": body, "weight": bd["weight"], "label": lbl}

# ── этап 2: затхлые офисы ───────────────────────────────────

func _build_stage2() -> void:
	var rng: = RandomNumberGenerator.new()
	rng.seed = 2002
	for room in ["c2", "d2"]:
		_office_props(room, rng)
		_office_decay(room, rng)
	# мигающие люминесцентные лампы
	for lp in [Vector3(36, 9.3, -90), Vector3(56, 9.3, -102), Vector3(44, 9.3, -110),
			Vector3(84, 11.3, -118), Vector3(100, 11.3, -128), Vector3(114, 11.3, -140), Vector3(90, 11.3, -144)]:
		_flicker_lamp(lp)
	_build_mezzanine()
	_build_ceiling_traps()
	# питание лифта: два рычага + провод + роутер
	_make_lever("s2a", Vector3(28, 0, -112), "РЫЧАГ ПИТАНИЯ А (лифт яруса)")
	_make_lever("s2b", Vector3(122, 0, -148), "РЫЧАГ ПИТАНИЯ Б (лифт яруса)")
	_make_wire("s2", [Vector3(100, 0, -112), Vector3(92, 0, -116), Vector3(86, 0, -120), Vector3(80, 0, -122)],
		Color(0.95, 0.6, 0.2), "КАБЕЛЬ К ЛИФТУ")
	_make_router("s2", Vector3(124.4, 0, -140))
	_make_lift(80.0, -124.0, 6.05, "s2", "ЛИФТ ЯРУСА")
	_label3d("СЕКРЕТНАЯ КОМНАТА", Vector3(18, 3.2, -94), 26, Color(0.9, 0.75, 0.3))
	_label3d("СЕКРЕТНАЯ КОМНАТА", Vector3(132, 3.2, -129), 26, Color(0.9, 0.75, 0.3))

func _office_props(room: String, rng: RandomNumberGenerator) -> void:
	## кубиклы, столы с мёртвыми мониторами, шкафы, разбросанные бумаги
	var r: Dictionary = _room_rect(room)
	var desk_mat: = Mats.wood_old()
	var part_mat: = Mats.plastic(Color(0.3, 0.32, 0.3))
	var rows: = 2 if room == "c2" else 3
	for row in rows:
		for col in 3:
			var base: = Vector3(
				lerpf(r["x0"] + 8.0, r["x1"] - 8.0, (float(col) + 0.5) / 3.0) + rng.randf_range(-2, 2),
				0.0,
				lerpf(r["zs"] - 8.0, r["zn"] + 8.0, (float(row) + 0.5) / float(rows)) + rng.randf_range(-2, 2))
			if rng.randf() < 0.2:
				continue
			_solid(Vector3(5.0, 1.9, 0.4), part_mat, base + Vector3(0, 0.95, -2.2))
			_solid(Vector3(0.4, 1.9, 4.2), part_mat, base + Vector3(-2.6, 0.95, 0))
			_solid(Vector3(3.0, 0.9, 1.5), desk_mat, base + Vector3(0.2, 0.45, -1.2))
			# мёртвый монитор (редкий ещё тлеет)
			var mon_dead: = rng.randf() > 0.2
			var mon_mat: Material = Mats.plastic(Color(0.12, 0.13, 0.15)) if mon_dead else _neon(Color(0.25, 0.6, 0.4), 0.5)
			var mon: = _mesh_box(Vector3(1.3, 0.9, 0.12), mon_mat, base + Vector3(0.2, 1.45, -1.5))
			mon.rotation.y = rng.randf_range(-0.4, 0.4)
			if rng.randf() < 0.5:
				var chair: = _mesh_box(Vector3(0.9, 0.5, 0.9), Mats.plastic(Color(0.2, 0.2, 0.22)), base + Vector3(1.4, 0.25, 0.6))
				chair.rotation.z = deg_to_rad(90.0) if rng.randf() < 0.5 else 0.0
			for pp in 3:
				var paper: = _mesh_box(Vector3(0.35, 0.02, 0.5), Mats.plastic(Color(0.7, 0.68, 0.6)),
					base + Vector3(rng.randf_range(-2, 2), 0.03, rng.randf_range(-1, 2)))
				paper.rotation.y = rng.randf_range(0, TAU)
	# шкафы вдоль стен
	for i in 3:
		var wx: float = rng.randf_range(r["x0"] + 4.0, r["x1"] - 4.0)
		_solid(Vector3(1.6, 2.4, 0.8), Mats.metal(Color(0.35, 0.37, 0.34), 0.6), Vector3(wx, 1.2, r["zn"] + 1.6))

func _office_decay(room: String, rng: RandomNumberGenerator) -> void:
	## упадок: паутина по углам, лианы с потолка, мох, упавшие плиты потолка
	var r: Dictionary = _room_rect(room)
	var h: float = r["h"]
	var web: = Mats.cobweb()
	for corner in [Vector3(r["x0"] + 1.2, h - 1.2, r["zs"] - 1.2), Vector3(r["x1"] - 1.2, h - 1.2, r["zs"] - 1.2),
			Vector3(r["x0"] + 1.2, h - 1.2, r["zn"] + 1.2), Vector3(r["x1"] - 1.2, h - 1.2, r["zn"] + 1.2)]:
		var q: = MeshInstance3D.new()
		var qm: = QuadMesh.new()
		qm.size = Vector2(3.2, 3.2)
		q.mesh = qm
		q.material_override = web
		q.position = corner
		q.rotation_degrees = Vector3(rng.randf_range(-30, 30), rng.randf_range(0, 360), rng.randf_range(-20, 20))
		add_child(q)
	# лианы: свисающие зелёные плети
	var vine_mat: = Mats.vine()
	for i in 8:
		var vp: = Vector3(rng.randf_range(r["x0"] + 3.0, r["x1"] - 3.0), 0, rng.randf_range(r["zn"] + 3.0, r["zs"] - 3.0))
		var vl: = rng.randf_range(1.5, 4.0)
		var vine: = MeshInstance3D.new()
		var vc: = CylinderMesh.new()
		vc.top_radius = 0.06
		vc.bottom_radius = 0.02
		vc.height = vl
		vine.mesh = vc
		vine.material_override = vine_mat
		vine.position = Vector3(vp.x, h - vl * 0.5, vp.z)
		vine.rotation.z = rng.randf_range(-0.12, 0.12)
		add_child(vine)
	# мох на полу и стенах
	var moss_mat: = Mats.moss()
	for i in 7:
		var mp: = Vector3(rng.randf_range(r["x0"] + 2.0, r["x1"] - 2.0), 0.03, rng.randf_range(r["zn"] + 2.0, r["zs"] - 2.0))
		var disc: = MeshInstance3D.new()
		var cm: = CylinderMesh.new()
		cm.top_radius = rng.randf_range(0.8, 2.2)
		cm.bottom_radius = cm.top_radius
		cm.height = 0.05
		disc.mesh = cm
		disc.material_override = moss_mat
		disc.position = mp
		add_child(disc)
	for i in 4:
		_mesh_box(Vector3(0.1, rng.randf_range(1.0, 2.5), rng.randf_range(1.5, 3.0)), moss_mat,
			Vector3(r["x0"] + 0.56, rng.randf_range(0.8, 2.2), rng.randf_range(r["zn"] + 3.0, r["zs"] - 3.0)))
	# обвалившиеся куски потолка на полу
	for i in 4:
		var deb: = _mesh_box(Vector3(rng.randf_range(1.0, 2.2), 0.25, rng.randf_range(1.0, 2.0)),
			Mats.plaster_old(Color(0.4, 0.38, 0.33)),
			Vector3(rng.randf_range(r["x0"] + 3.0, r["x1"] - 3.0), 0.14, rng.randf_range(r["zn"] + 3.0, r["zs"] - 3.0)))
		deb.rotation_degrees = Vector3(rng.randf_range(-8, 8), rng.randf_range(0, 360), rng.randf_range(-8, 8))
	# пылинки в воздухе
	var parts: = GPUParticles3D.new()
	parts.amount = 120
	parts.lifetime = 8.0
	parts.preprocess = 6.0
	var pm: = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3((r["x1"] - r["x0"]) * 0.5, h * 0.4, (r["zs"] - r["zn"]) * 0.5)
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.25
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.3
	parts.process_material = pm
	var quad: = QuadMesh.new()
	quad.size = Vector2(0.04, 0.04)
	var qmat: = StandardMaterial3D.new()
	qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qmat.albedo_color = Color(0.7, 0.65, 0.45, 0.35)
	quad.material = qmat
	parts.draw_pass_1 = quad
	parts.position = Vector3((r["x0"] + r["x1"]) * 0.5, h * 0.5, (r["zs"] + r["zn"]) * 0.5)
	add_child(parts)

func _flicker_lamp(pos: Vector3) -> void:
	var mat: = _neon(Color(0.85, 0.9, 0.8), 2.0)
	_mesh_box(Vector3(2.6, 0.12, 0.5), mat, pos)
	var sl: = _spot_down(pos + Vector3(0, -0.2, 0), Color(0.85, 0.92, 0.8), 2.4, 11.0)
	sl.shadow_enabled = false
	_flickers.append({"light": sl, "mat": mat, "seed": randf() * TAU})

func _build_mezzanine() -> void:
	## второй ярус комнаты d2: Г-образные мостки на y=6, подъём — только лифтом
	var deck: = Mats.deck_metal()
	var rail_mat: = Mats.metal(Color(0.5, 0.45, 0.35), 0.55)
	# западная полоса и северная полоса
	_solid(Vector3(8.0, 0.5, 44.0), deck, Vector3(74, 5.75, -130))
	_solid(Vector3(48.0, 0.5, 8.0), deck, Vector3(102, 5.75, -148))
	# опорные колонны
	for cp in [Vector3(74, 0, -114), Vector3(74, 0, -130), Vector3(74, 0, -146),
			Vector3(90, 0, -148), Vector3(106, 0, -148), Vector3(122, 0, -148)]:
		_solid(Vector3(0.6, 5.5, 0.6), rail_mat, cp + Vector3(0, 2.75, 0))
	# перила (с разрывом у лифта z −122..−126)
	_solid(Vector3(0.15, 1.0, 12.0), rail_mat, Vector3(78, 6.5, -114))
	_solid(Vector3(0.15, 1.0, 16.0), rail_mat, Vector3(78, 6.5, -134))
	_solid(Vector3(48.0, 1.0, 0.15), rail_mat, Vector3(102, 6.5, -144))
	_mesh_box(Vector3(8.0, 0.08, 0.15), _neon(TIER_COLORS[1], 0.8), Vector3(74, 6.02, -108.6))
	_label3d("ЯРУС // подъём лифтом", Vector3(80, 8.2, -124), 28, TIER_COLORS[1])

func _build_ceiling_traps() -> void:
	## треснувшие плиты потолка: дрожат и рушатся, когда кто-то встал под ними
	for ct in CEIL_TRAPS:
		var room: Dictionary = _room_rect(ct["room"])
		var h: float = room["h"]
		var home: = Vector3(ct["pos"].x, h - 0.45, ct["pos"].z)
		var plate: = _mesh_box(Vector3(3.0, 0.3, 3.0), Mats.plaster_old(Color(0.36, 0.34, 0.3)), home)
		# трещины — тёмные полосы
		for i in 2:
			var crack: = _mesh_box(Vector3(2.6, 0.02, 0.08), Mats.plastic(Color(0.08, 0.08, 0.08)), home + Vector3(0, -0.17, -0.5 + float(i)))
			crack.rotation.y = 0.4 + float(i) * 0.9
		_ceils.append({"plate": plate, "home": home, "state": "armed", "t": 0.0})

func _make_lever(key: String, pos: Vector3, desc: String) -> void:
	var on: = GameState.flag("lever:" + key)
	var root: = Node3D.new()
	root.position = pos
	add_child(root)
	_mesh_box(Vector3(0.7, 1.1, 0.5), Mats.metal_dark(0.4), Vector3(0, 0.55, 0), root)
	_collide(Vector3(0.7, 1.1, 0.5), pos + Vector3(0, 0.55, 0))
	var arm: = MeshInstance3D.new()
	var am: = CylinderMesh.new()
	am.top_radius = 0.05
	am.bottom_radius = 0.05
	am.height = 0.8
	arm.mesh = am
	arm.material_override = _neon(Color(1.0, 0.4, 0.3) if not on else INFECTED_COLOR, 2.0)
	arm.position = Vector3(0, 1.25, 0)
	arm.rotation.z = deg_to_rad(-40.0 if not on else 40.0)
	root.add_child(arm)
	var lbl: = _label3d("%s\n%s" % [desc, "✓ ВКЛЮЧЁН" if on else "[E] включить"],
		Vector3(0, 2.2, 0), 24, INFECTED_COLOR if on else Color(1.0, 0.7, 0.35), true, root)
	_levers[key] = {"arm": arm, "label": lbl, "pos": pos, "desc": desc}

func _pull_lever(key: String) -> void:
	GameState.set_flag("lever:" + key)
	var lv: Dictionary = _levers[key]
	var arm: MeshInstance3D = lv["arm"]
	var tw: = create_tween()
	tw.tween_property(arm, "rotation:z", deg_to_rad(40.0), 0.35).set_trans(Tween.TRANS_BACK)
	var arm_mat: StandardMaterial3D = arm.material_override
	arm_mat.emission = INFECTED_COLOR
	lv["label"].text = "%s\n✓ ВКЛЮЧЁН" % lv["desc"]
	lv["label"].modulate = INFECTED_COLOR
	Sfx.play("chain", -4.0, 1.2)
	_after_power_change()

func _make_wire(key: String, pylons: Array, color: Color, desc: String) -> void:
	## протяжка кабеля: подключай опоры по порядку [E]; прогресс переживает рейды
	var done_n: = 0
	for i in pylons.size():
		if GameState.flag("wirep:%s:%d" % [key, i]):
			done_n = i + 1
	var infos: Array = []
	for i in pylons.size():
		var p: Vector3 = pylons[i]
		var post: = MeshInstance3D.new()
		var pc: = CylinderMesh.new()
		pc.top_radius = 0.14
		pc.bottom_radius = 0.24
		pc.height = 1.7
		post.mesh = pc
		post.material_override = Mats.metal_dark(0.45)
		post.position = p + Vector3(0, 0.85, 0)
		add_child(post)
		var orb_mat: = _neon(color if i < done_n else Color(0.35, 0.38, 0.42), 1.6 if i < done_n else 0.5)
		_mesh_box(Vector3(0.26, 0.26, 0.26), orb_mat, p + Vector3(0, 1.85, 0))
		infos.append({"pos": p, "orb": orb_mat})
	var lbl: = _label3d("", pylons[0] + Vector3(0, 2.7, 0), 24, color)
	_wires[key] = {"pylons": infos, "label": lbl, "color": color, "desc": desc}
	for i in range(1, done_n):
		_draw_wire_seg(key, i - 1, i)
	if done_n >= pylons.size():
		GameState.set_flag("wire:" + key)
	_refresh_wire_label(key)

func _wire_done_n(key: String) -> int:
	var n: = 0
	for i in _wires[key]["pylons"].size():
		if GameState.flag("wirep:%s:%d" % [key, i]):
			n = i + 1
	return n

func _refresh_wire_label(key: String) -> void:
	var wr: Dictionary = _wires[key]
	var n: = _wire_done_n(key)
	var total: int = wr["pylons"].size()
	if n >= total:
		wr["label"].text = "%s ✓ ПОД НАПРЯЖЕНИЕМ" % wr["desc"]
		wr["label"].modulate = INFECTED_COLOR
	else:
		wr["label"].text = "%s: опоры %d/%d\n[E] подключить следующую" % [wr["desc"], n, total]

func _draw_wire_seg(key: String, i0: int, i1: int) -> void:
	var wr: Dictionary = _wires[key]
	var a: Vector3 = wr["pylons"][i0]["pos"] + Vector3(0, 1.85, 0)
	var b: Vector3 = wr["pylons"][i1]["pos"] + Vector3(0, 1.85, 0)
	var segs: = 6
	for s in segs:
		var t0: = float(s) / float(segs)
		var t1: = float(s + 1) / float(segs)
		var p0: = a.lerp(b, t0) + Vector3(0, -sin(t0 * PI) * 0.5, 0)
		var p1: = a.lerp(b, t1) + Vector3(0, -sin(t1 * PI) * 0.5, 0)
		var seg: = _mesh_box(Vector3(0.07, 0.07, p0.distance_to(p1)), _neon(wr["color"], 1.1), (p0 + p1) * 0.5)
		seg.look_at_from_position(seg.position, p1, Vector3.UP)

func _advance_wire(key: String) -> void:
	var n: = _wire_done_n(key)
	GameState.set_flag("wirep:%s:%d" % [key, n])
	var wr: Dictionary = _wires[key]
	var orb: StandardMaterial3D = wr["pylons"][n]["orb"]
	orb.emission = wr["color"]
	orb.emission_energy_multiplier = 1.6
	if n > 0:
		_draw_wire_seg(key, n - 1, n)
	Sfx.play("chain", -6.0, 1.0 + 0.15 * float(n))
	if n + 1 >= wr["pylons"].size():
		GameState.set_flag("wire:" + key)
		hud.flash_pickup("%s: линия под напряжением!" % wr["desc"])
		Sfx.play("layer_done", -4.0)
		_after_power_change()
	_refresh_wire_label(key)

func _make_router(key: String, pos: Vector3) -> void:
	var on: = GameState.flag("router:" + key)
	var root: = Node3D.new()
	root.position = pos
	add_child(root)
	_mesh_box(Vector3(0.5, 0.7, 0.9), Mats.plastic(Color(0.5, 0.52, 0.56)), Vector3(0, 2.2, 0), root)
	for a2 in 2:
		_mesh_box(Vector3(0.04, 0.5, 0.04), Mats.plastic(Color(0.2, 0.2, 0.22)), Vector3(0, 2.8, -0.25 + float(a2) * 0.5), root)
	var led: = _neon(INFECTED_COLOR if on else Color(0.9, 0.3, 0.2), 1.8)
	_mesh_box(Vector3(0.1, 0.1, 0.1), led, Vector3(-0.3, 2.35, 0.3), root)
	var lbl: = _label3d("РОУТЕР ЛИФТА\n%s" % ("✓ АКТИВЕН" if on else "[E держать] активировать"),
		Vector3(0, 3.4, 0), 24, INFECTED_COLOR if on else Color(0.4, 0.8, 1.0), true, root)
	_routers[key] = {"led": led, "label": lbl, "pos": pos}

func _activate_router(key: String) -> void:
	GameState.set_flag("router:" + key)
	var rt: Dictionary = _routers[key]
	var led: StandardMaterial3D = rt["led"]
	led.emission = INFECTED_COLOR
	rt["label"].text = "РОУТЕР ЛИФТА\n✓ АКТИВЕН"
	rt["label"].modulate = INFECTED_COLOR
	Sfx.play("ability", -4.0, 1.3)
	_after_power_change()

func _make_lift(x: float, z: float, y_top: float, power: String, cap: String) -> void:
	var body: = AnimatableBody3D.new()
	body.sync_to_physics = false
	body.collision_layer = 1
	var cs: = CollisionShape3D.new()
	var box: = BoxShape3D.new()
	box.size = Vector3(3.2, 0.4, 3.2)
	cs.shape = box
	body.add_child(cs)
	var mesh: = MeshInstance3D.new()
	var bm: = BoxMesh.new()
	bm.size = Vector3(3.2, 0.4, 3.2)
	mesh.mesh = bm
	mesh.material_override = Mats.deck_metal()
	body.add_child(mesh)
	var edge: = MeshInstance3D.new()
	var em: = BoxMesh.new()
	em.size = Vector3(3.3, 0.1, 3.3)
	edge.mesh = em
	edge.material_override = _neon(Color(0.3, 0.8, 1.0), 1.0)
	edge.position.y = 0.2
	body.add_child(edge)
	body.position = Vector3(x, 0.25, z)
	add_child(body)
	# направляющие
	for side in [-1.55, 1.55]:
		_solid(Vector3(0.25, y_top + 1.5, 0.25), Mats.metal_dark(0.5), Vector3(x + side, (y_top + 1.5) * 0.5, z - 1.55))
	var lbl: = _label3d(cap, Vector3(x, y_top + 2.4, z), 26, Color(0.3, 0.8, 1.0))
	_lifts.append({"body": body, "x": x, "z": z, "y0": 0.25, "y1": y_top, "power": power, "label": lbl, "t": 0.0})

# ── этап 3: бункер ──────────────────────────────────────────

func _build_stage3() -> void:
	var rng: = RandomNumberGenerator.new()
	rng.seed = 3003
	for room in ["e1", "e2", "e3", "e4"]:
		_bunker_props(room, rng)
	# генераторная: щит, рубильник, три генератора с кабелями
	_mesh_box(Vector3(3.2, 2.2, 0.4), Mats.metal(Color(0.5, 0.45, 0.3), 0.5), Vector3(98, 1.6, -177.8))
	_label3d("ЩИТ ПИТАНИЯ ЭТАПА 3\nпровода → генераторы → рубильник", Vector3(98, 3.4, -179), 26, Color(0.95, 0.8, 0.35))
	_make_lever("s3master", Vector3(102, 0, -179.5), "ГЛАВНЫЙ РУБИЛЬНИК")
	_make_generator("g1", Vector3(84, 0, -192))
	_make_generator("g2", Vector3(104, 0, -200))
	_make_generator("g3", Vector3(112, 0, -186))
	_make_wire("g1", [Vector3(96, 0, -182), Vector3(90, 0, -186), Vector3(86.5, 0, -189)], Color(0.95, 0.75, 0.2), "КАБЕЛЬ ГЕНЕРАТОРА 1")
	_make_wire("g2", [Vector3(100, 0, -184), Vector3(102, 0, -190), Vector3(103.5, 0, -195.5)], Color(0.95, 0.75, 0.2), "КАБЕЛЬ ГЕНЕРАТОРА 2")
	_make_wire("g3", [Vector3(102, 0, -182), Vector3(107, 0, -183.5), Vector3(110, 0, -184.5)], Color(0.95, 0.75, 0.2), "КАБЕЛЬ ГЕНЕРАТОРА 3")
	# лифт на верхний уступ e3 (там два сервера)
	_build_stage3_ledge()
	_make_lift(110.0, -260.0, 6.05, "s3", "ЛИФТ УСТУПА")
	# лазерные ловушки и блок-отключатель
	_build_traps()
	_build_override_tower()
	_build_parkour_button()
	# красная тревога 28/28
	if GameState.red_alert():
		_build_red_alert()

func _bunker_props(room: String, rng: RandomNumberGenerator) -> void:
	var r: Dictionary = _room_rect(room)
	var h: float = r["h"]
	# аварийные красные лампы (горят всегда)
	for i in 2:
		var ep: = Vector3(lerpf(r["x0"] + 4.0, r["x1"] - 4.0, 0.25 + 0.5 * float(i)), h - 1.2,
			lerpf(r["zs"] - 3.0, r["zn"] + 3.0, 0.3 + 0.4 * float(i)))
		_mesh_box(Vector3(0.4, 0.2, 0.4), _neon(Color(0.9, 0.15, 0.1), 1.6), ep)
		_omni(ep + Vector3(0, -0.4, 0), Color(0.9, 0.18, 0.12), 0.55, 9.0)
	# основной холодный свет — включается генераторами
	for i in 3:
		var lp: = Vector3(lerpf(r["x0"] + 5.0, r["x1"] - 5.0, (float(i) + 0.5) / 3.0), h - 0.5,
			(r["zs"] + r["zn"]) * 0.5 + rng.randf_range(-4.0, 4.0))
		var lamp_mat: = _neon(Color(0.8, 0.9, 1.0), 0.15)
		_mesh_box(Vector3(2.8, 0.15, 0.7), lamp_mat, lp)
		var sl: = _spot_down(lp + Vector3(0, -0.2, 0), Color(0.8, 0.9, 1.0), 3.2, h + 3.0)
		sl.visible = false
		_s3_lights.append(sl)
		_s3_lamps.append(lamp_mat)
	# трубы, кабельные лотки, бочки, гермоящики
	var pipe_mat: = Mats.rust()
	var pipe: = MeshInstance3D.new()
	var pc: = CylinderMesh.new()
	pc.top_radius = 0.2
	pc.bottom_radius = 0.2
	pc.height = r["x1"] - r["x0"] - 4.0
	pipe.mesh = pc
	pipe.rotation.z = deg_to_rad(90.0)
	pipe.material_override = pipe_mat
	pipe.position = Vector3((r["x0"] + r["x1"]) * 0.5, h - 1.6, r["zn"] + 1.8)
	add_child(pipe)
	_mesh_box(Vector3(r["x1"] - r["x0"] - 4.0, 0.12, 0.5), Mats.metal_dark(0.5), Vector3((r["x0"] + r["x1"]) * 0.5, h - 2.2, r["zn"] + 1.8))
	for i in 4:
		var bp: = Vector3(rng.randf_range(r["x0"] + 3.0, r["x1"] - 3.0), 0, rng.randf_range(r["zn"] + 3.0, r["zs"] - 3.0))
		if rng.randf() < 0.5:
			var barrel: = MeshInstance3D.new()
			var bc: = CylinderMesh.new()
			bc.top_radius = 0.55
			bc.bottom_radius = 0.55
			bc.height = 1.4
			barrel.mesh = bc
			barrel.material_override = Mats.rust(Color(0.3, 0.32, 0.25))
			barrel.position = bp + Vector3(0, 0.7, 0)
			add_child(barrel)
			_collide(Vector3(1.1, 1.4, 1.1), bp + Vector3(0, 0.7, 0))
		else:
			_solid(Vector3(1.6, 1.2, 1.2), Mats.metal(Color(0.32, 0.35, 0.3), 0.6), bp + Vector3(0, 0.6, 0))
	# сигнальные полосы у проёмов
	for g in ROOM_GAPS.get(room, {}).get("s", []):
		_mesh_box(Vector3(g["w"] + 1.0, 0.02, 1.2), Mats.hazard(), Vector3(g["c"], 0.02, r["zs"] - 1.4))
	for g in ROOM_GAPS.get(room, {}).get("n", []):
		_mesh_box(Vector3(g["w"] + 1.0, 0.02, 1.2), Mats.hazard(), Vector3(g["c"], 0.02, r["zn"] + 1.4))

func _make_generator(key: String, pos: Vector3) -> void:
	var on: = GameState.flag("gen:" + key)
	var root: = Node3D.new()
	root.position = pos
	add_child(root)
	_mesh_box(Vector3(2.2, 2.0, 3.0), Mats.metal(Color(0.4, 0.42, 0.38), 0.5), Vector3(0, 1.0, 0), root)
	_collide(Vector3(2.2, 2.0, 3.0), pos + Vector3(0, 1.0, 0))
	_mesh_box(Vector3(2.3, 0.25, 3.1), Mats.rust(), Vector3(0, 2.1, 0), root)
	# турбинное окно — светится при работе
	var glow: = _neon(INFECTED_COLOR if on else Color(0.3, 0.32, 0.35), 2.0 if on else 0.3)
	var ring: = MeshInstance3D.new()
	var tm: = TorusMesh.new()
	tm.inner_radius = 0.45
	tm.outer_radius = 0.65
	ring.mesh = tm
	ring.material_override = glow
	ring.rotation.z = deg_to_rad(90.0)
	ring.position = Vector3(1.15, 1.1, 0)
	root.add_child(ring)
	var light: = _omni(Vector3(1.4, 1.4, 0), INFECTED_COLOR, 1.2 if on else 0.0, 7.0, root)
	var lbl: = _label3d("", Vector3(0, 3.0, 0), 26, Color(0.95, 0.8, 0.35), true, root)
	_gens[key] = {"glow": glow, "light": light, "label": lbl, "pos": pos, "wire": key}
	_refresh_gen_label(key)

func _refresh_gen_label(key: String) -> void:
	var g: Dictionary = _gens[key]
	var lbl: Label3D = g["label"]
	if GameState.flag("gen:" + key):
		lbl.text = "ГЕНЕРАТОР %s\n✓ РАБОТАЕТ" % key.to_upper()
		lbl.modulate = INFECTED_COLOR
	elif not GameState.flag("wire:" + g["wire"]):
		lbl.text = "ГЕНЕРАТОР %s\nсначала протяни кабель от щита" % key.to_upper()
		lbl.modulate = Color(0.85, 0.4, 0.3)
	else:
		lbl.text = "ГЕНЕРАТОР %s\n[E держать] запустить" % key.to_upper()
		lbl.modulate = Color(0.95, 0.8, 0.35)

func _start_generator(key: String) -> void:
	GameState.set_flag("gen:" + key)
	var g: Dictionary = _gens[key]
	var glow: StandardMaterial3D = g["glow"]
	glow.emission = INFECTED_COLOR
	glow.emission_energy_multiplier = 2.0
	var light: OmniLight3D = g["light"]
	light.light_energy = 1.2
	Sfx.play("layer_done", -3.0, 0.7)
	hud.flash_pickup("Генераторы: %d/3" % GameState.stage3_generators_on())
	_refresh_gen_label(key)
	_after_power_change()

func _after_power_change() -> void:
	## что-то щёлкнуло в цепи: обновить свет, двери, генераторы, лифты, щит
	_apply_stage3_power()
	for key in _gens:
		_refresh_gen_label(key)
	for key in _doors:
		_refresh_door_label(key)
	_refresh_oracle_shield()
	if GameState.stage3_powered() and _s3_power_seen != true:
		_s3_power_seen = true
		hud.flash_pickup("ЭТАП 3 ПОД НАПРЯЖЕНИЕМ: свет, лифты и двери активны")

func _apply_stage3_power() -> void:
	var on: = GameState.stage3_powered()
	for sl in _s3_lights:
		if is_instance_valid(sl):
			sl.visible = on
	for lm in _s3_lamps:
		lm.emission_energy_multiplier = 2.4 if on else 0.15

func _build_stage3_ledge() -> void:
	## верхний уступ e3 с двумя серверами — подъём лифтом после генераторов
	var deck: = Mats.deck_metal()
	_solid(Vector3(32.0, 0.5, 8.0), deck, Vector3(128, 5.75, -260))
	for cp in [Vector3(114, 0, -258), Vector3(128, 0, -258), Vector3(142, 0, -258)]:
		_solid(Vector3(0.6, 5.5, 0.6), Mats.rust(), cp + Vector3(0, 2.75, 0))
	# перила с разрывом у лифта (x 108.5..111.5)
	_solid(Vector3(30.0, 1.0, 0.15), Mats.metal(Color(0.5, 0.45, 0.35), 0.55), Vector3(129, 6.5, -256))
	_mesh_box(Vector3(32.0, 0.08, 0.15), _neon(TIER_COLORS[2], 0.8), Vector3(128, 6.02, -256.4))

func _build_traps() -> void:
	## лазерные лучи поперёк залов: мигают по фазам, бьют током
	var off: = GameState.flag("traps_off")
	for tb in TRAP_BEAMS:
		var a: Vector3 = tb["a"]
		var b: Vector3 = tb["b"]
		var posts: Array = []
		for endpoint in [a, b]:
			var post: = _mesh_box(Vector3(0.3, 1.2, 0.3), Mats.rust(), Vector3(endpoint.x, 0.6, endpoint.z))
			var tip: = _mesh_box(Vector3(0.18, 0.18, 0.18),
				_neon(INFECTED_COLOR if off else Color(1.0, 0.15, 0.1), 1.5), Vector3(endpoint.x, 1.25, endpoint.z))
			posts.append(tip)
		var beam_mat: = _neon(Color(1.0, 0.12, 0.08), 3.0)
		var beam: = _mesh_box(Vector3(0.06, 0.06, a.distance_to(b)), beam_mat, (a + b) * 0.5)
		beam.look_at_from_position(beam.position, b, Vector3.UP)
		beam.visible = not off
		_traps.append({"beam": beam, "mat": beam_mat, "a": a, "b": b, "phase": tb["phase"], "posts": posts})

func _build_override_tower() -> void:
	## отдельностоящий квадратный блок: с него отключаются все ловушки этапа.
	## забраться можно только перелётом по проводу (кнопка на стене — паркур)
	var off: = GameState.flag("traps_off")
	_solid(Vector3(6.0, 6.5, 6.0), Mats.bunker_wall(Color(0.26, 0.27, 0.26)), Vector3(134, 3.25, -252))
	_mesh_box(Vector3(6.2, 0.3, 6.2), Mats.hazard(), Vector3(134, 6.55, -252))
	_mesh_box(Vector3(0.8, 0.9, 0.8), Mats.metal_dark(0.4), Vector3(134, 7.15, -252))
	_mesh_box(Vector3(0.5, 0.12, 0.5), _neon(INFECTED_COLOR if off else Color(1.0, 0.2, 0.15), 2.2), Vector3(134, 7.66, -252))
	_label3d("БЛОК-ОТКЛЮЧАТЕЛЬ ЛОВУШЕК\n%s" % ("✓ ЛОВУШКИ ОТКЛЮЧЕНЫ" if off else "[E держать] на вершине"),
		Vector3(134, 9.0, -252), 30, INFECTED_COLOR if off else Color(1.0, 0.55, 0.2))
	# зиплайн от паркур-уступа к вершине блока
	_make_zip(Vector3(144.3, 5.0, -244.5), Vector3(134, 7.4, -252), "zip:e3")

func _build_parkour_button() -> void:
	## паркур у восточной стены e3: ящики → уступ → кнопка перехода
	_solid(Vector3(1.8, 1.2, 1.8), Mats.metal(Color(0.34, 0.36, 0.32), 0.6), Vector3(142.5, 0.6, -238))
	_solid(Vector3(1.8, 2.4, 1.8), Mats.metal(Color(0.34, 0.36, 0.32), 0.6), Vector3(144.3, 1.2, -241))
	_solid(Vector3(2.2, 0.4, 2.2), Mats.deck_metal(), Vector3(144.3, 3.2, -244.5))
	var pressed: = GameState.flag("zip:e3")
	_mesh_box(Vector3(0.5, 0.5, 0.15), Mats.metal_dark(0.4), Vector3(144.3, 4.1, -245.4))
	_mesh_box(Vector3(0.26, 0.26, 0.1), _neon(INFECTED_COLOR if pressed else Color(1.0, 0.6, 0.15), 2.0), Vector3(144.3, 4.1, -245.3))
	_label3d("КНОПКА ПЕРЕХОДА\n%s" % ("✓ ПРОВОД АКТИВЕН" if pressed else "[E] активировать провод"),
		Vector3(144.3, 5.2, -244.5), 24, INFECTED_COLOR if pressed else Color(1.0, 0.7, 0.35))

func _make_zip(a: Vector3, b: Vector3, flag_key: String) -> void:
	## перелёт по проводу; активируется кнопкой (flag), потом работает всегда
	for endpoint in [a, b]:
		_mesh_box(Vector3(0.2, 1.0, 0.2), Mats.metal_dark(0.5), endpoint - Vector3(0, 0.5, 0))
		_mesh_box(Vector3(0.16, 0.16, 0.16), _neon(Color(0.2, 0.8, 0.95), 1.6), endpoint)
	var zip: = {"a": a, "b": b, "flag": flag_key, "drawn": false, "label": null}
	zip["label"] = _label3d("", a + Vector3(0, 1.1, 0), 22, Color(0.2, 0.8, 0.95))
	_zips.append(zip)
	if flag_key == "" or GameState.flag(flag_key):
		_draw_zip_cable(zip)
	_refresh_zip_label(zip)

func _draw_zip_cable(zip: Dictionary) -> void:
	if zip["drawn"]:
		return
	zip["drawn"] = true
	var a: Vector3 = zip["a"]
	var b: Vector3 = zip["b"]
	var segs: = 8
	for s in segs:
		var t0: = float(s) / float(segs)
		var t1: = float(s + 1) / float(segs)
		var p0: = a.lerp(b, t0) + Vector3(0, sin(t0 * PI) * 0.4, 0)
		var p1: = a.lerp(b, t1) + Vector3(0, sin(t1 * PI) * 0.4, 0)
		var seg: = _mesh_box(Vector3(0.07, 0.07, p0.distance_to(p1)), _neon(Color(0.2, 0.8, 0.95), 0.9), (p0 + p1) * 0.5)
		seg.look_at_from_position(seg.position, p1, Vector3.UP)

func _refresh_zip_label(zip: Dictionary) -> void:
	var lbl: Label3D = zip["label"]
	if zip["flag"] == "" or GameState.flag(zip["flag"]):
		lbl.text = "ПРОВОД [E] — перелёт"
	else:
		lbl.text = "провод обесточен\n(кнопка перехода на стене)"
		lbl.modulate = Color(0.5, 0.55, 0.6)

func _build_red_alert() -> void:
	## 28/28: бункер мигает красным, воет сирена (тикается в _process)
	for bp in [Vector3(96, 8.6, -194), Vector3(136, 7.6, -211), Vector3(122, 9.6, -245),
			Vector3(78, 7.6, -247), Vector3(122, 4.4, -277)]:
		var beacon_mat: = _neon(Color(1.0, 0.1, 0.08), 2.5)
		_mesh_box(Vector3(0.5, 0.3, 0.5), beacon_mat, bp)
		var ol: = _omni(bp + Vector3(0, -0.6, 0), Color(1.0, 0.12, 0.1), 1.8, 16.0)
		_alert_lights.append({"light": ol, "mat": beacon_mat})
	_label3d("!! 28/28 СЕРВЕРОВ АКТИВИРОВАНО !!\nПРОТОКОЛ ВТОРЖЕНИЯ · ПУТЬ К ОРАКУЛУ ОТКРЫТ",
		Vector3(122, 6.5, -268), 34, Color(1.0, 0.25, 0.2))

# ── ОРАКУЛ: зал одного гигантского сервера ──────────────────

func _build_oracle() -> void:
	var r: Dictionary = _room_rect("or")
	# стены-стойки: панели с бегущими огнями по периметру
	var panel_mat: = Mats.metal_dark(0.45)
	for i in 10:
		var px: = lerpf(r["x0"] + 8.0, r["x1"] - 8.0, float(i) / 9.0)
		_mesh_box(Vector3(6.0, 9.0, 1.0), panel_mat, Vector3(px, 4.5, r["zn"] + 1.6))
		_mesh_box(Vector3(5.4, 0.1, 0.2), _neon(Color(0.2, 0.7, 1.0), 1.4), Vector3(px, 3.0 + float(i % 3), r["zn"] + 2.15))
	for i in 8:
		var pz: = lerpf(r["zn"] + 10.0, r["zs"] - 10.0, float(i) / 7.0)
		for side_x in [r["x0"] + 1.6, r["x1"] - 1.6]:
			_mesh_box(Vector3(1.0, 7.0, 5.0), panel_mat, Vector3(side_x, 3.5, pz))
	# холодный свет по углам + пульс ядра
	for cp in [Vector3(84, 18, -302), Vector3(164, 18, -302), Vector3(84, 18, -374), Vector3(164, 18, -374)]:
		_spot_down(cp, Color(0.5, 0.75, 1.0), 3.0, 26.0, 70.0)
	_build_oracle_core()
	# 12 пилонов-головоломок
	for pd in ORACLE_PYLONS:
		_make_pylon(pd["key"], pd["pos"], pd["diff"])
	# захват территорий
	for td in ORACLE_TERRS:
		_make_territory(td["key"], td["pos"])
	# магистраль и рубильник зала
	_make_wire("or", [Vector3(140, 0, -296), Vector3(150, 0, -302), Vector3(158, 0, -309), Vector3(164, 0, -317)],
		Color(0.2, 0.85, 1.0), "МАГИСТРАЛЬ ОРАКУЛА")
	_make_lever("or", Vector3(108, 0, -296), "РУБИЛЬНИК ЗАЛА")
	# стойки данных: украсть всю информацию
	for rd in ORACLE_RACKS_POS:
		_make_rack(rd["key"], rd["pos"])
	# 10 роботов бегут из разных мест
	for sp in [Vector3(76, 0, -296), Vector3(172, 0, -296), Vector3(76, 0, -380), Vector3(172, 0, -380),
			Vector3(124, 0, -300), Vector3(80, 0, -338), Vector3(170, 0, -338), Vector3(124, 0, -378),
			Vector3(100, 0, -320), Vector3(148, 0, -358)]:
		_spawn_oracle_bot(sp)
	# побег: портал у входа (появляется после разрушения ядра)
	_build_escape_portal()
	if GameState.oracle_core_down:
		_set_core_destroyed(true)

func _build_oracle_core() -> void:
	var pos: = ORACLE_CORE_POS
	var core_mat: = _neon(ORACLE_COLOR, 1.4)
	var tower: = MeshInstance3D.new()
	var tm: = CylinderMesh.new()
	tm.top_radius = 5.0
	tm.bottom_radius = 6.5
	tm.height = 16.0
	tm.radial_segments = 8
	tower.mesh = tm
	tower.material_override = Mats.obsidian()
	tower.position = pos + Vector3(0, 8.0, 0)
	add_child(tower)
	var sb: = StaticBody3D.new()
	sb.collision_layer = 1
	var cs: = CollisionShape3D.new()
	var cyl: = CylinderShape3D.new()
	cyl.radius = 6.5
	cyl.height = 16.0
	cs.shape = cyl
	cs.position = pos + Vector3(0, 8.0, 0)
	sb.add_child(cs)
	add_child(sb)
	# светящиеся пояса и вершина
	for k in 4:
		_mesh_box(Vector3(11.5, 0.3, 11.5), core_mat, pos + Vector3(0, 2.5 + float(k) * 3.6, 0))
	var rings: Array = []
	for k in 3:
		var ring: = MeshInstance3D.new()
		var tor: = TorusMesh.new()
		tor.inner_radius = 8.0 + float(k) * 2.2
		tor.outer_radius = 8.4 + float(k) * 2.2
		ring.mesh = tor
		ring.material_override = _neon(ORACLE_COLOR, 0.9)
		ring.position = pos + Vector3(0, 12.0 + float(k) * 1.8, 0)
		add_child(ring)
		rings.append(ring)
	var eye: = MeshInstance3D.new()
	var sm: = SphereMesh.new()
	sm.radius = 1.8
	sm.height = 3.6
	eye.mesh = sm
	var eye_mat: = _neon(ORACLE_COLOR, 3.0)
	eye.material_override = eye_mat
	eye.position = pos + Vector3(0, 17.6, 0)
	add_child(eye)
	_omni(pos + Vector3(0, 17.6, 0), ORACLE_COLOR, 3.0, 26.0)
	# энергощит вокруг ядра
	var shield: MeshInstance3D = null
	var shield_body: StaticBody3D = null
	if not GameState.oracle_core_open():
		shield = MeshInstance3D.new()
		var shc: = CylinderMesh.new()
		shc.top_radius = 10.0
		shc.bottom_radius = 10.0
		shc.height = 14.0
		shield.mesh = shc
		shield.material_override = _holo_add(ORACLE_COLOR, 0.09)
		shield.position = pos + Vector3(0, 7.0, 0)
		add_child(shield)
		shield_body = StaticBody3D.new()
		shield_body.collision_layer = 1
		var scs: = CollisionShape3D.new()
		var scyl: = CylinderShape3D.new()
		scyl.radius = 10.0
		scyl.height = 14.0
		scs.shape = scyl
		scs.position = pos + Vector3(0, 7.0, 0)
		shield_body.add_child(scs)
		add_child(shield_body)
	# табло состояния штурма
	var board: = _label3d("", pos + Vector3(0, 13.5, 0), 52, Color(0.85, 0.92, 1.0))
	board.no_depth_test = true
	_core = {"core_mat": core_mat, "eye_mat": eye_mat, "rings": rings, "shield": shield,
		"shield_body": shield_body, "board": board}

func _refresh_oracle_shield() -> void:
	if not GameState.oracle_core_open():
		return
	var shield: MeshInstance3D = _core.get("shield")
	if shield != null and is_instance_valid(shield):
		var tw: = create_tween()
		tw.tween_property(shield, "scale", Vector3(0.02, 1.2, 0.02), 0.8).set_trans(Tween.TRANS_QUAD)
		tw.tween_callback(shield.queue_free)
		_core["shield"] = null
		Sfx.play("quarantine", -6.0, 1.5)
		hud.flash_pickup("ЩИТ ОРАКУЛА ПАЛ — крадите данные со стоек!")
	var sb: StaticBody3D = _core.get("shield_body")
	if sb != null and is_instance_valid(sb):
		sb.queue_free()
		_core["shield_body"] = null
	for rkey in _racks:
		_refresh_rack_label(rkey)

func _make_pylon(key: String, pos: Vector3, diff: int) -> void:
	var solved: = GameState.flag(key)
	var root: = Node3D.new()
	root.position = pos
	add_child(root)
	_mesh_box(Vector3(0.9, 1.2, 0.6), Mats.obsidian(), Vector3(0, 0.6, 0), root)
	_collide(Vector3(0.9, 1.2, 0.6), pos + Vector3(0, 0.6, 0))
	var scr: = _mesh_box(Vector3(1.1, 0.7, 0.08), _neon(INFECTED_COLOR if solved else ORACLE_COLOR, 1.3), Vector3(0, 1.5, 0.2), root)
	scr.rotation.x = deg_to_rad(-18.0)
	var orb_mat: StandardMaterial3D = scr.material_override
	var lbl: = _label3d("ГОЛОВОЛОМКА %s\n%s" % [key.trim_prefix("opz:"), "✓ РЕШЕНА" if solved else "[E] взломать"],
		Vector3(0, 2.5, 0), 24, INFECTED_COLOR if solved else Color(1.0, 0.5, 0.55), true, root)
	_pylons[key] = {"orb": orb_mat, "label": lbl, "pos": pos, "diff": diff}

func _solve_pylon(key: String) -> void:
	GameState.set_flag(key)
	var p: Dictionary = _pylons[key]
	var orb: StandardMaterial3D = p["orb"]
	orb.emission = INFECTED_COLOR
	p["label"].text = "ГОЛОВОЛОМКА %s\n✓ РЕШЕНА" % key.trim_prefix("opz:")
	p["label"].modulate = INFECTED_COLOR
	hud.flash_pickup("ГОЛОВОЛОМКИ ОРАКУЛА: %d/%d" % [GameState.oracle_puzzles_done(), GameState.ORACLE_PUZZLES_TOTAL])
	_refresh_oracle_shield()

func _make_territory(key: String, pos: Vector3) -> void:
	var done: = GameState.flag(key)
	var ring: = MeshInstance3D.new()
	var tor: = TorusMesh.new()
	tor.inner_radius = 4.6
	tor.outer_radius = 5.0
	ring.mesh = tor
	var ring_mat: = _neon(INFECTED_COLOR if done else ORACLE_COLOR, 1.2)
	ring.material_override = ring_mat
	ring.position = pos + Vector3(0, 0.1, 0)
	add_child(ring)
	var beacon: = MeshInstance3D.new()
	var bc: = CylinderMesh.new()
	bc.top_radius = 0.1
	bc.bottom_radius = 0.28
	bc.height = 2.4
	beacon.mesh = bc
	beacon.material_override = ring_mat
	beacon.position = pos + Vector3(0, 1.2, 0)
	add_child(beacon)
	var lbl: = _label3d("", pos + Vector3(0, 3.2, 0), 28, INFECTED_COLOR if done else Color(1.0, 0.6, 0.6))
	_terrs[key] = {"pos": pos, "ring_mat": ring_mat, "label": lbl, "prog": 1.0 if done else 0.0}
	_refresh_terr_label(key)

func _refresh_terr_label(key: String) -> void:
	var t: Dictionary = _terrs[key]
	if GameState.flag(key):
		t["label"].text = "ТЕРРИТОРИЯ ЗАХВАЧЕНА ✓"
		t["label"].modulate = INFECTED_COLOR
	elif t["prog"] > 0.01:
		t["label"].text = "ЗАХВАТ ТЕРРИТОРИИ: %d%%\n(стой в кольце)" % int(t["prog"] * 100.0)
	else:
		t["label"].text = "ТЕРРИТОРИЯ ОРАКУЛА\nвстань в кольцо для захвата"

func _make_rack(key: String, pos: Vector3) -> void:
	var done: = GameState.flag(key)
	var root: = Node3D.new()
	root.position = pos
	add_child(root)
	_mesh_box(Vector3(1.8, 2.6, 1.0), Mats.metal_dark(0.4), Vector3(0, 1.3, 0), root)
	_collide(Vector3(1.8, 2.6, 1.0), pos + Vector3(0, 1.3, 0))
	for k in 6:
		_mesh_box(Vector3(1.5, 0.16, 0.06), Mats.plastic(Color(0.1, 0.11, 0.13)), Vector3(0, 0.5 + float(k) * 0.36, 0.52), root)
	var scr_mat: = _neon(INFECTED_COLOR if done else Color(0.2, 0.85, 0.4), 1.2)
	_mesh_box(Vector3(0.8, 0.5, 0.06), scr_mat, Vector3(0.3, 2.2, 0.54), root)
	var lbl: = _label3d("", Vector3(0, 3.4, 0), 26, INFECTED_COLOR if done else Color(0.4, 0.95, 0.55), true, root)
	_racks[key] = {"screen": scr_mat, "label": lbl, "pos": pos}
	_refresh_rack_label(key)

func _refresh_rack_label(key: String) -> void:
	var rk: Dictionary = _racks[key]
	if GameState.flag(key):
		rk["label"].text = "СТОЙКА ДАННЫХ\n✓ ИНФОРМАЦИЯ УКРАДЕНА"
		rk["label"].modulate = INFECTED_COLOR
	elif not GameState.oracle_core_open():
		rk["label"].text = "СТОЙКА ДАННЫХ\n(экранирована щитом Оракула)"
		rk["label"].modulate = Color(0.5, 0.55, 0.6)
	else:
		rk["label"].text = "СТОЙКА ДАННЫХ\n[E держать] красть информацию"
		rk["label"].modulate = Color(0.4, 0.95, 0.55)

func _steal_rack(key: String) -> void:
	GameState.set_flag(key)
	var rk: Dictionary = _racks[key]
	var scr: StandardMaterial3D = rk["screen"]
	scr.emission = INFECTED_COLOR
	_refresh_rack_label(key)
	GameState.resources["data_fragments"] += 40
	Sfx.play("pickup", -2.0, 0.8)
	hud.flash_pickup("ДАННЫЕ УКРАДЕНЫ: %d/%d (+40 ◈)" % [GameState.oracle_racks_done(), GameState.ORACLE_RACKS])
	if GameState.oracle_data_stolen():
		hud.flash_pickup("ВСЯ ИНФОРМАЦИЯ У НАС — РУШЬТЕ ЯДРО ОРАКУЛА!")
		Sfx.play("hack_win", -4.0)

func _spawn_oracle_bot(pos: Vector3) -> void:
	## робот-охранник Оракула (кооп: у каждого пира свои роботы — хаб,
	## наказание локальное: отбрасывание ко входу)
	var root: = Node3D.new()
	root.position = pos
	add_child(root)
	var body_mat: = Mats.metal(Color(0.5, 0.52, 0.58), 0.35)
	var dark: = Mats.metal(Color(0.16, 0.17, 0.2), 0.5)
	_mesh_box(Vector3(1.6, 0.5, 2.1), body_mat, Vector3(0, 0.65, 0), root)
	_mesh_box(Vector3(1.3, 0.9, 1.0), body_mat, Vector3(0, 1.5, 0), root)
	_mesh_box(Vector3(1.35, 0.14, 1.05), dark, Vector3(0, 2.0, 0), root)
	var wheels: Array = []
	var tire: = Mats.rubber()
	for sx in [-0.85, 0.85]:
		for sz in [-0.7, 0.7]:
			var wheel: = MeshInstance3D.new()
			var wm: = CylinderMesh.new()
			wm.top_radius = 0.38
			wm.bottom_radius = 0.38
			wm.height = 0.3
			wheel.mesh = wm
			wheel.material_override = tire
			wheel.rotation.z = deg_to_rad(90.0)
			wheel.position = Vector3(sx, 0.38, sz)
			root.add_child(wheel)
			wheels.append(wheel)
	root.set_meta("wheels", wheels)
	var dome: = MeshInstance3D.new()
	var dm: = SphereMesh.new()
	dm.radius = 0.36
	dm.height = 0.56
	dome.mesh = dm
	dome.material_override = body_mat
	dome.position = Vector3(0, 2.3, 0)
	root.add_child(dome)
	var lens: = MeshInstance3D.new()
	var lm: = SphereMesh.new()
	lm.radius = 0.13
	lm.height = 0.26
	lens.mesh = lm
	lens.material_override = _neon(ORACLE_COLOR, 4.0)
	lens.position = Vector3(0, 2.33, -0.3)
	root.add_child(lens)
	_omni(Vector3(0, 2.4, 0), ORACLE_COLOR, 1.2, 7.0, root)
	_robots.append({"node": root, "wp": pos, "t": randf_range(0.0, 2.0), "home": pos})

func _build_escape_portal() -> void:
	var pos: = Vector3(122, 0, -294)
	var root: = Node3D.new()
	root.position = pos
	root.visible = false
	add_child(root)
	var ring: = MeshInstance3D.new()
	var tor: = TorusMesh.new()
	tor.inner_radius = 1.5
	tor.outer_radius = 1.8
	ring.mesh = tor
	ring.material_override = _neon(INFECTED_COLOR, 2.4)
	ring.rotation.x = deg_to_rad(90.0)
	ring.position.y = 1.9
	root.add_child(ring)
	_omni(Vector3(0, 2.0, 0), INFECTED_COLOR, 2.5, 12.0, root)
	var lbl: = _label3d("ЭВАКУАЦИЯ ИЗ ГРИДА\n[E] сбежать", Vector3(0, 4.2, 0), 36, INFECTED_COLOR, true, root)
	_escape = {"node": root, "label": lbl, "pos": pos, "active": false}

func _set_core_destroyed(at_load: bool) -> void:
	## ядро разрушено: Оракул гаснет, роботы в бешенстве, побег открыт
	var eye_mat: StandardMaterial3D = _core["eye_mat"]
	eye_mat.emission = Color(0.25, 0.28, 0.32)
	eye_mat.emission_energy_multiplier = 0.4
	var core_mat: StandardMaterial3D = _core["core_mat"]
	core_mat.emission = Color(0.3, 0.1, 0.1)
	core_mat.emission_energy_multiplier = 0.5
	var node: Node3D = _escape["node"]
	node.visible = true
	_escape["active"] = true
	if not at_load:
		GameState.oracle_core_down = true
		Sfx.play("quarantine")
		player.shake(0.8)
		hud.flash_pickup("ЯДРО ОРАКУЛА РАЗРУШЕНО — БЕГИТЕ К ПОРТАЛУ!")
		if Net.active:
			Net.toast_all("ЯДРО ОРАКУЛА РАЗРУШЕНО — все к порталу!", ORACLE_COLOR)
		# вспышка и осколки
		for i in 14:
			var bit: = _mesh_box(Vector3(0.3, 0.3, 0.3), _neon(ORACLE_COLOR, 3.0),
				ORACLE_CORE_POS + Vector3(randf_range(-3, 3), randf_range(6, 14), randf_range(-3, 3)))
			var tw: = bit.create_tween()
			tw.tween_property(bit, "position", bit.position + Vector3(randf_range(-9, 9), randf_range(-6, 4), randf_range(-9, 9)), 0.9)
			tw.parallel().tween_property(bit, "scale", Vector3(0.05, 0.05, 0.05), 0.9)
			tw.tween_callback(bit.queue_free)

# ── серверы ─────────────────────────────────────────────────

func _build_nodes() -> void:
	for node in GameState.grid_nodes:
		_build_node(node)

func _build_node(node: Dictionary) -> void:
	var root: = Node3D.new()
	root.position = node["pos"]
	add_child(root)
	var unlocked: bool = GameState.node_unlocked(node)
	var infected: bool = node["infected"]
	var tier_color: Color = TIER_COLORS[node["tier"]]
	var color: Color = tier_color
	if infected:
		color = INFECTED_COLOR
	elif not unlocked:
		color = LOCKED_COLOR
	# реалистичная стойка: металл, вентрешётки, LED, экранчик
	var h: = 2.4 + float(node["tier"]) * 0.4
	_mesh_box(Vector3(1.7, h, 1.2), Mats.metal_dark(0.45), Vector3(0, h * 0.5, 0), root)
	var sb: = StaticBody3D.new()
	sb.collision_layer = 1
	var cs: = CollisionShape3D.new()
	var cbox: = BoxShape3D.new()
	cbox.size = Vector3(1.7, h, 1.2)
	cs.shape = cbox
	cs.position.y = h * 0.5
	sb.add_child(cs)
	root.add_child(sb)
	_mesh_box(Vector3(1.5, h - 0.4, 0.06), Mats.plastic(Color(0.22, 0.24, 0.28)), Vector3(0, h * 0.5, 0.6), root)
	var vent_mat: = Mats.plastic(Color(0.1, 0.11, 0.13))
	var units: = int((h - 0.8) / 0.3)
	for k in units:
		_mesh_box(Vector3(1.3, 0.14, 0.05), vent_mat, Vector3(-0.05, 0.55 + float(k) * 0.3, 0.64), root)
	var led_on: = _neon(Color(0.25, 0.9, 0.4) if not infected else INFECTED_COLOR, 1.6)
	var led_warn: = _neon(Color(0.95, 0.6, 0.15), 1.4)
	for k in mini(units, 6):
		var mat: Material = led_on if (node["id"] + k) % 3 != 0 else led_warn
		_mesh_box(Vector3(0.05, 0.05, 0.03), mat, Vector3(0.62, 0.55 + float(k) * 0.3, 0.65), root)
	_mesh_box(Vector3(0.62, 0.4, 0.04), _neon(color, 0.85), Vector3(0.3, h - 0.42, 0.65), root)
	for k in 2:
		_mesh_box(Vector3(0.07, 0.5, 0.07), vent_mat, Vector3(-0.4 + float(k) * 0.25, h + 0.2, -0.3), root)
	_mesh_box(Vector3(0.5, 0.06, 0.5), Mats.metal_dark(0.35), Vector3(0, h + 0.03, 0), root)
	var core: = MeshInstance3D.new()
	var sm: = SphereMesh.new()
	sm.radius = 0.24
	sm.height = 0.48
	core.mesh = sm
	core.material_override = _neon(color, 1.2)
	core.position.y = h + 0.32
	root.add_child(core)
	if unlocked and not infected:
		_omni(Vector3(0, h + 0.6, 0), color, 1.1, 7.0, root)
	var label: = Label3D.new()
	label.font_size = 34
	label.modulate = color
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = h + 1.5
	label.no_depth_test = true
	root.add_child(label)
	node_visuals[node["id"]] = {"root": root, "label": label, "core": core, "tier_color": tier_color, "core_h": node["pos"].y + h + 0.5}
	_refresh_node_label(node)

func _refresh_node_label(node: Dictionary) -> void:
	var vis: Dictionary = node_visuals[node["id"]]
	var label: Label3D = vis["label"]
	var status: = ""
	if node["infected"]:
		status = "✓ ВЗЛОМАН"
	elif not GameState.node_unlocked(node):
		status = "🔒"
	elif node["failed"]:
		status = "⚠ ПОВТОР"
	else:
		status = "[E] ВЗЛОМ"
	label.text = "%s · %s" % [node["name"], status]

func _refresh_nodes_behind_door(door_key: String) -> void:
	for node in GameState.grid_nodes:
		if node.get("door", "") == door_key:
			_refresh_node_label(node)

# ── бонусные точки данных ───────────────────────────────────

func _build_motes() -> void:
	var spots: = [
		# секретные комнаты набиты фрагментами
		Vector3(-15, 1.2, -24), Vector3(-13, 1.2, -28), Vector3(36, 1.2, -18), Vector3(34, 1.2, -22),
		Vector3(18, 1.2, -92), Vector3(16, 1.2, -96), Vector3(132, 1.2, -127), Vector3(130, 1.2, -131),
		Vector3(110, 1.2, -268), Vector3(112, 1.2, -272),
		# и немного по открытым залам
		Vector3(20, 1.2, -40), Vector3(50, 1.2, -90), Vector3(90, 1.2, -130),
		Vector3(100, 1.2, -190), Vector3(120, 1.2, -240), Vector3(150, 1.2, -330),
	]
	for pos in spots:
		var m: = MeshInstance3D.new()
		var sm: = SphereMesh.new()
		sm.radius = 0.32
		sm.height = 0.64
		m.mesh = sm
		var sh: = ShaderMaterial.new()
		sh.shader = HoloShader
		sh.set_shader_parameter("col", Vector3(0.16, 0.95, 0.75))
		m.material_override = sh
		m.position = pos
		add_child(m)
		motes.append({"node": m, "pos": pos, "phase": randf() * TAU})

# ── игрок и UI ──────────────────────────────────────────────

func _spawn_player() -> void:
	player = VirusPlayer.new()
	var spawn: = Vector3(0, 0.3, 4.0)
	if not GameState.current_node.is_empty():
		var np: Vector3 = GameState.current_node["pos"]
		spawn = Vector3(np.x, 0.3, np.z + 4.0)
	player.position = spawn
	add_child(player)

func _build_ui() -> void:
	var hud_layer: = CanvasLayer.new()
	hud_layer.layer = 1
	add_child(hud_layer)
	hud = HUDScript.new()
	hud_layer.add_child(hud)

	party = PartyFx.new()
	party.local_player = player
	party.get_actor = _actor_for
	party.toast_request.connect(_on_net_toast)
	hud_layer.add_child(party)

	top_layer = CanvasLayer.new()
	top_layer.layer = 10
	top_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(top_layer)
	pause_panel = _build_pause_panel()
	pause_panel.visible = false
	top_layer.add_child(pause_panel)

func _build_pause_panel() -> Control:
	var root: = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim: = ColorRect.new()
	dim.color = Color(0, 0.005, 0.015, 0.75)
	root.add_child(UIKit.full_rect(dim))
	var center: = CenterContainer.new()
	root.add_child(UIKit.full_rect(center))
	var panel: = PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 240)
	panel.add_theme_stylebox_override("panel", UIKit.panel_box(UIKit.CYAN, Color(0.008, 0.02, 0.036, 0.97), 1, 8, 24))
	center.add_child(panel)
	var v: = VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	v.add_child(UIKit.label("ГРИД // пауза", 24, UIKit.CYAN))
	var resume: = UIKit.button("  ПРОДОЛЖИТЬ  ", 19, UIKit.TEAL)
	resume.pressed.connect(_toggle_pause)
	v.add_child(resume)
	var menu: = UIKit.button("  ВЫЙТИ В МЕНЮ  ", 19, UIKit.MAGENTA)
	menu.pressed.connect(func() -> void:
		Net.leave()
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	v.add_child(menu)
	return root

# ── цикл ────────────────────────────────────────────────────

var _demo_grid_timer: = 0.0

func _process(delta: float) -> void:
	var t: = Time.get_ticks_msec() / 1000.0
	_knock_lock = maxf(_knock_lock - delta, 0.0)

	# демо-бот: сам ныряет в первый доступный узел (и в коопе — хостом)
	if GameState.demo_mode and not _win_shown:
		_demo_grid_timer += delta
		if _demo_grid_timer > 4.0 and (not Net.active or Net.is_server()):
			_demo_grid_timer = -INF
			for node in GameState.grid_nodes:
				if not node["infected"] and GameState.node_unlocked(node):
					if Net.active:
						Net.start_hack(node)
					else:
						GameState.start_hack(node)
						get_tree().change_scene_to_file("res://scenes/level.tscn")
					return

	for id in node_visuals:
		node_visuals[id]["core"].rotate_y(delta * 0.6)

	# код на барьерах переливается
	_code_t += delta
	if _code_t > 0.35:
		_code_t = 0.0
		for g in gates:
			for lbl in g["labels"]:
				lbl.text = _random_code()
			var m: StandardMaterial3D = g["mat"]
			m.albedo_color.a = clampf(m.albedo_color.a + randf_range(-0.04, 0.04), 0.06, 0.32)

	for mote in motes:
		if mote["node"] == null:
			continue
		var m: MeshInstance3D = mote["node"]
		m.position.y = mote["pos"].y + sin(t * 2.0 + mote["phase"]) * 0.25
		m.rotate_y(delta * 1.5)
		if player.global_position.distance_to(m.global_position) < 1.8:
			GameState.resources["data_fragments"] += 3
			hud.flash_pickup("+3 Data Fragments")
			Sfx.play("pickup")
			m.queue_free()
			mote["node"] = null

	_flicker_tick(t)
	_lift_tick(delta)
	_trap_tick(t)
	_ceil_tick(delta)
	_robot_tick(delta, t)
	_terr_tick(delta)
	_alert_tick(t)
	_board_tick(delta)
	_carry_block_tick(delta)
	_flag_watch_tick(delta)
	_interaction_tick(delta)
	if not _win_shown:
		hud.refresh()

func _flag_watch_tick(delta: float) -> void:
	## медленный тик: в коопе флаги приходят по сети — подхватить двери и питание
	_watch_t -= delta
	if _watch_t > 0.0:
		return
	_watch_t = 0.7
	for key in _doors:
		if GameState.flag("door:" + key) and _doors[key]["body"] != null:
			_open_door(key)
			_refresh_nodes_behind_door(key)
	if GameState.stage3_powered() != _s3_power_seen:
		_after_power_change()
	_refresh_oracle_shield()

func _flicker_tick(t: float) -> void:
	for f in _flickers:
		var e: = 0.55 + 0.45 * absf(sin(t * 6.0 + f["seed"]) * sin(t * 1.7 + f["seed"] * 2.0))
		if randf() < 0.006:
			e = 0.05
		f["light"].light_energy = 2.4 * e
		f["mat"].emission_energy_multiplier = 2.0 * e

func _lift_tick(delta: float) -> void:
	for lf in _lifts:
		var powered: = GameState.stage2_lift_powered() if lf["power"] == "s2" else GameState.stage3_powered()
		var body: AnimatableBody3D = lf["body"]
		var lbl: Label3D = lf["label"]
		if not powered:
			body.position.y = lf["y0"]
			if lf["power"] == "s2":
				lbl.text = "ЛИФТ ОБЕСТОЧЕН\nрычаги %d/2 · провод %s · роутер %s" % [
					int(GameState.flag("lever:s2a")) + int(GameState.flag("lever:s2b")),
					"✓" if GameState.flag("wire:s2") else "✗",
					"✓" if GameState.flag("router:s2") else "✗"]
			else:
				lbl.text = "ЛИФТ ОБЕСТОЧЕН\nгенераторы %d/3 · рубильник %s" % [
					GameState.stage3_generators_on(), "✓" if GameState.flag("lever:s3master") else "✗"]
			lbl.modulate = Color(0.85, 0.4, 0.3)
			continue
		lbl.text = "ЛИФТ РАБОТАЕТ"
		lbl.modulate = Color(0.3, 0.8, 1.0)
		lf["t"] += delta
		var ph: = fmod(lf["t"], LIFT_CYCLE)
		var y: float = lf["y0"]
		if ph < 3.0:
			y = lerpf(lf["y0"], lf["y1"], smoothstep(0.0, 1.0, ph / 3.0))
		elif ph < 4.2:
			y = lf["y1"]
		elif ph < 7.2:
			y = lerpf(lf["y1"], lf["y0"], smoothstep(0.0, 1.0, (ph - 4.2) / 3.0))
		body.position.y = y

func _trap_tick(t: float) -> void:
	var off: = GameState.flag("traps_off")
	for i in _traps.size():
		var tr: Dictionary = _traps[i]
		var beam: MeshInstance3D = tr["beam"]
		if off:
			if beam.visible:
				beam.visible = false
				for tip in tr["posts"]:
					tip.material_override = _neon(INFECTED_COLOR, 1.2)
			continue
		var on: = fmod(t + tr["phase"], 3.2) < 1.7
		beam.visible = on
		if not on or _knock_lock > 0.0:
			continue
		var a: Vector3 = tr["a"]
		var b: Vector3 = tr["b"]
		var pp: = player.global_position
		if absf(pp.z - a.z) < 0.6 and pp.y < 1.7 and pp.x > minf(a.x, b.x) - 0.3 and pp.x < maxf(a.x, b.x) + 0.3:
			var resp: = STAGE3_ENTRY
			if i < 2:
				resp = Vector3(119, 0.3, -203)
			elif i < 4:
				resp = Vector3(131, 0.3, -229)
			else:
				resp = Vector3(95, 0.3, -247)
			_knockdown(resp, Vector3(pp.x, 0.6, a.z), "ЛАЗЕРНАЯ ЛОВУШКА! Отключи их с блока-отключателя")

func _ceil_tick(delta: float) -> void:
	for ct in _ceils:
		var plate: MeshInstance3D = ct["plate"]
		var home: Vector3 = ct["home"]
		match ct["state"]:
			"armed":
				var pp: = player.global_position
				if Vector2(pp.x - home.x, pp.z - home.z).length() < 1.7 and pp.y < 2.5:
					ct["state"] = "warn"
					ct["t"] = 0.65
					Sfx.play("alarm", -12.0, 2.2)
			"warn":
				ct["t"] -= delta
				plate.position = home + Vector3(randf_range(-0.06, 0.06), randf_range(-0.05, 0.02), randf_range(-0.06, 0.06))
				if ct["t"] <= 0.0:
					ct["state"] = "fall"
			"fall":
				plate.position.y -= 20.0 * delta
				if plate.position.y <= 0.2:
					plate.position.y = 0.2
					ct["state"] = "debris"
					ct["t"] = 10.0
					Sfx.play("trap", -4.0, 0.7)
					var pp2: = player.global_position
					if Vector2(pp2.x - home.x, pp2.z - home.z).length() < 1.7 and pp2.y < 2.2 and _knock_lock <= 0.0:
						_knockdown(STAGE2_ENTRY, plate.position, "ПОТОЛОК РУХНУЛ! Тебя откопали у входа на этап")
			"debris":
				ct["t"] -= delta
				if ct["t"] <= 0.0:
					plate.position = home
					ct["state"] = "armed"

func _robot_tick(delta: float, _t: float) -> void:
	var pp: = player.global_position
	var in_hall: = pp.z < -290.0
	var frenzy: = GameState.oracle_core_down
	for rb in _robots:
		var node: Node3D = rb["node"]
		if not is_instance_valid(node):
			continue
		rb["t"] -= delta
		var target: Vector3 = rb["wp"]
		var speed: = 4.0
		var sight: = 22.0 if frenzy else 15.0
		var dist_p: = node.global_position.distance_to(pp)
		if in_hall and dist_p < sight and not player.morphed:
			target = pp
			speed = 7.6 if frenzy else 6.4
		elif rb["t"] <= 0.0 or node.global_position.distance_to(target) < 2.0:
			rb["t"] = randf_range(2.5, 6.0)
			for attempt in 8:
				var cand: = Vector3(randf_range(76.0, 172.0), 0.0, randf_range(-380.0, -296.0))
				if cand.distance_to(ORACLE_CORE_POS) > 14.0:
					rb["wp"] = cand
					break
			target = rb["wp"]
		var dir: = target - node.global_position
		dir.y = 0.0
		var moved: = 0.0
		if dir.length() > 1.2:
			_move_unit_collide(node, dir.normalized(), speed * delta)
			node.rotation.y = atan2(dir.x, dir.z)
			moved = speed * delta
		var spin: = moved / 0.38
		for w in node.get_meta("wheels", []):
			if is_instance_valid(w):
				w.rotate_object_local(Vector3.UP, spin)
		# поймал: вышвыривает ко входу в зал
		if in_hall and dist_p < 1.8 and _knock_lock <= 0.0:
			_knockdown(ORACLE_ENTRY, node.global_position, "РОБОТ ОРАКУЛА вышвырнул тебя ко входу!")

func _move_unit_collide(node: Node3D, dir: Vector3, dist: float) -> void:
	var space: = get_world_3d().direct_space_state
	var from: = node.global_position + Vector3(0, 1.0, 0)
	var q: = PhysicsRayQueryParameters3D.create(from, from + dir * (dist + 1.1))
	q.collision_mask = 1
	var hit: = space.intersect_ray(q)
	if hit.is_empty():
		node.global_position += dir * dist
		return
	var n: Vector3 = hit["normal"]
	var slide: = dir - n * dir.dot(n)
	slide.y = 0.0
	if slide.length() < 0.05:
		return
	slide = slide.normalized()
	var q2: = PhysicsRayQueryParameters3D.create(from, from + slide * (dist + 1.1))
	q2.collision_mask = 1
	if space.intersect_ray(q2).is_empty():
		node.global_position += slide * dist

func _terr_tick(delta: float) -> void:
	for key in _terrs:
		if GameState.flag(key):
			continue
		var tr: Dictionary = _terrs[key]
		var pp: = player.global_position
		var inside: = Vector2(pp.x - tr["pos"].x, pp.z - tr["pos"].z).length() < 5.0 and pp.y < 2.0
		if inside:
			tr["prog"] = minf(tr["prog"] + delta / 12.0, 1.0)
			var rm: StandardMaterial3D = tr["ring_mat"]
			rm.emission_energy_multiplier = 1.2 + tr["prog"] * 1.6
			if tr["prog"] >= 1.0:
				GameState.set_flag(key)
				rm.emission = INFECTED_COLOR
				Sfx.play("layer_done", -3.0)
				hud.flash_pickup("ТЕРРИТОРИИ ОРАКУЛА: %d/%d" % [GameState.oracle_territories_done(), GameState.ORACLE_TERRITORIES])
				_refresh_oracle_shield()
				for rkey in _racks:
					_refresh_rack_label(rkey)
		_refresh_terr_label(key)

func _alert_tick(t: float) -> void:
	if _alert_lights.is_empty():
		return
	var pulse: = 0.5 + 0.5 * sin(t * 6.0)
	for al in _alert_lights:
		al["light"].light_energy = 0.4 + 2.2 * pulse
		al["mat"].emission_energy_multiplier = 0.8 + 2.6 * pulse
	# сирена воет, пока ты в бункере или у Оракула
	if player.global_position.z < -170.0:
		_siren_t -= get_process_delta_time()
		if _siren_t <= 0.0:
			_siren_t = 2.8
			Sfx.play("alarm", -6.0, 0.9)

func _board_tick(delta: float) -> void:
	_status_t -= delta
	if _status_t > 0.0 or _core.is_empty():
		return
	_status_t = 0.5
	var board: Label3D = _core["board"]
	if GameState.oracle_core_down:
		board.text = "// ОРАКУЛ МЁРТВ //\nбегите к порталу эвакуации"
		board.modulate = INFECTED_COLOR
		return
	var lines: = "ШТУРМ ОРАКУЛА\nголоволомки %d/%d · территории %d/%d\nмагистраль %s · рубильник %s" % [
		GameState.oracle_puzzles_done(), GameState.ORACLE_PUZZLES_TOTAL,
		GameState.oracle_territories_done(), GameState.ORACLE_TERRITORIES,
		"✓" if GameState.flag("wire:or") else "✗", "✓" if GameState.flag("lever:or") else "✗"]
	if GameState.oracle_core_open():
		lines += "\nЩИТ ПАЛ · данные %d/%d" % [GameState.oracle_racks_done(), GameState.ORACLE_RACKS]
		if GameState.oracle_data_stolen():
			lines += "\n▸ РАЗРУШЬТЕ ЯДРО [E у ядра]"
	board.text = lines

# ── переносные блоки: взять / поставить ─────────────────────

func _carry_block_tick(delta: float) -> void:
	if _carrying_block < 0:
		return
	var body: AnimatableBody3D = _blocks[_carrying_block]["body"]
	var target: = player.global_position + player.look_dir() * 1.7 + Vector3(0, 1.0, 0)
	body.global_position = body.global_position.lerp(target, minf(12.0 * delta, 1.0))

func _grab_block(id: int) -> void:
	var b: Dictionary = _blocks[id]
	_carrying_block = id
	var body: AnimatableBody3D = b["body"]
	body.collision_layer = 0
	player.carrying = true
	var f: = 0.66
	if b["weight"] >= 2:
		f = 0.6 if GameState.has_passive("ransomware") else 0.3
	if GameState.has_passive("worm"):
		f += 0.08
	player.carry_factor = f
	Sfx.play("pickup", -6.0, 1.1)

func _release_block() -> void:
	var b: Dictionary = _blocks[_carrying_block]
	var body: AnimatableBody3D = b["body"]
	var p: = body.global_position
	var sx: = roundf(p.x / BLOCK) * BLOCK
	var sz: = roundf(p.z / BLOCK) * BLOCK
	# блок ложится на первую опору под собой (пол, платформа, другой блок)
	var space: = get_world_3d().direct_space_state
	var q: = PhysicsRayQueryParameters3D.create(Vector3(sx, p.y + 1.5, sz), Vector3(sx, -2.0, sz))
	q.collision_mask = 1
	q.exclude = [body.get_rid(), player.get_rid()]
	var hit: = space.intersect_ray(q)
	var floor_y: = 0.0
	if not hit.is_empty():
		floor_y = hit["position"].y
	body.global_position = Vector3(sx, floor_y + BLOCK * 0.5, sz)
	body.collision_layer = 1
	GameState.block_positions[_carrying_block] = body.global_position
	_carrying_block = -1
	player.carrying = false
	player.carry_factor = 1.0
	Sfx.play("land", -6.0)

# ── головоломки, зиплайн, нокдаун ───────────────────────────

func _open_puzzle(diff: int, title: String, on_solved: Callable) -> void:
	if _puzzle_open != null:
		return
	player.control_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var p: = PuzzleUI.open(top_layer, diff, title)
	_puzzle_open = p
	p.finished.connect(func(success: bool) -> void:
		_puzzle_open = null
		if is_instance_valid(player):
			player.control_enabled = true
		if not _paused:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if success:
			on_solved.call())

func _ride_zip(from: Vector3, to: Vector3) -> void:
	if _riding_zip:
		return
	_riding_zip = true
	player.control_enabled = false
	player.velocity = Vector3.ZERO
	Sfx.play("chain", -4.0, 1.4)
	var dur: = 0.5 + from.distance_to(to) / 26.0
	var step: = func(t: float) -> void:
		if is_instance_valid(player):
			var p: = from.lerp(to, t)
			p.y += sin(t * PI) * 0.35 - 0.9
			player.global_position = p
	var tw: = create_tween()
	tw.tween_method(step, 0.0, 1.0, dur)
	tw.tween_callback(func() -> void:
		_riding_zip = false
		if is_instance_valid(player):
			player.control_enabled = true)

func _knockdown(respawn: Vector3, from: Vector3, msg: String) -> void:
	_knock_lock = 2.0
	player.ragdoll_from(from)
	Sfx.play("trap", -2.0, 1.0)
	hud.flash_pickup(msg)
	var flash: = ColorRect.new()
	flash.color = Color(0.9, 0.1, 0.1, 0.0)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_layer.add_child(flash)
	var tw: = create_tween()
	tw.tween_property(flash, "color:a", 0.5, 0.15)
	tw.tween_property(flash, "color:a", 0.0, 0.5)
	tw.tween_callback(flash.queue_free)
	get_tree().create_timer(0.55).timeout.connect(func() -> void:
		if is_instance_valid(player):
			player.global_position = respawn
			player.velocity = Vector3.ZERO)

# ── взаимодействия ──────────────────────────────────────────

func _interaction_tick(delta: float) -> void:
	if _win_shown or _paused or _riding_zip or _puzzle_open != null:
		return
	if _entering:
		hud.set_prompt("▸▸ ИНЪЕКЦИЯ В СЕРВЕР…")
		return
	var pp: = player.global_position
	var pressed: = Input.is_action_pressed("interact")
	var just: = Input.is_action_just_pressed("interact")

	# несу блок — ставим
	if _carrying_block >= 0:
		hud.set_prompt("[E] поставить блок — встанет по сетке (стройте лестницу)")
		if just:
			_release_block()
		return

	# двери-головоломки
	for key in _doors:
		var d: Dictionary = _doors[key]
		if GameState.flag("door:" + key):
			continue
		if pp.distance_to(d["pos"]) < 3.0:
			if d["power"] and not GameState.stage3_powered():
				hud.set_prompt("⚡ ДВЕРЬ ОБЕСТОЧЕНА: генераторы %d/3 + рубильник" % GameState.stage3_generators_on())
			else:
				hud.set_prompt("[E] ДВЕРЬ: решить головоломку взлома")
				if just:
					var door_key: = key
					_open_puzzle(d["diff"], "СХЕМА ВЗЛОМА ДВЕРИ", func() -> void:
						_open_door(door_key)
						_refresh_nodes_behind_door(door_key))
			return

	# рычаги
	for key in _levers:
		if GameState.flag("lever:" + key):
			continue
		var lv: Dictionary = _levers[key]
		if pp.distance_to(lv["pos"]) < 2.6:
			hud.set_prompt("[E] %s" % lv["desc"])
			if just:
				_pull_lever(key)
			return

	# провода: подключить следующую опору
	for key in _wires:
		if GameState.flag("wire:" + key):
			continue
		var wr: Dictionary = _wires[key]
		var n: = _wire_done_n(key)
		var next_pos: Vector3 = wr["pylons"][n]["pos"]
		if pp.distance_to(next_pos) < 2.6:
			hud.set_prompt("[E] подключить кабель к опоре %d/%d (%s)" % [n + 1, wr["pylons"].size(), wr["desc"]])
			if just:
				_advance_wire(key)
			return

	# генераторы (удержание)
	for key in _gens:
		if GameState.flag("gen:" + key):
			continue
		var g: Dictionary = _gens[key]
		if pp.distance_to(g["pos"]) < 3.2:
			if not GameState.flag("wire:" + g["wire"]):
				hud.set_prompt("⚡ ГЕНЕРАТОР: сначала протяни кабель от щита")
			elif pressed:
				var prog: = _hold_progress("gen:" + key, delta, 2.5)
				hud.set_prompt("запуск генератора… %d%%" % int(prog * 100.0))
				if prog >= 1.0:
					_hold_key = ""
					_start_generator(key)
			else:
				_hold_key = ""
				hud.set_prompt("[E держать] запустить генератор")
			return

	# роутер (удержание)
	for key in _routers:
		if GameState.flag("router:" + key):
			continue
		var rt: Dictionary = _routers[key]
		if pp.distance_to(rt["pos"]) < 2.8:
			if pressed:
				var prog: = _hold_progress("router:" + key, delta, 2.0)
				hud.set_prompt("активация роутера… %d%%" % int(prog * 100.0))
				if prog >= 1.0:
					_hold_key = ""
					_activate_router(key)
			else:
				_hold_key = ""
				hud.set_prompt("[E держать] РОУТЕР: активировать")
			return

	# кнопка перехода (паркур-стена этапа 3)
	if not GameState.flag("zip:e3") and pp.distance_to(Vector3(144.3, 4.1, -244.5)) < 2.6:
		hud.set_prompt("[E] КНОПКА ПЕРЕХОДА: подать питание на провод к блоку-отключателю")
		if just:
			GameState.set_flag("zip:e3")
			for zip in _zips:
				if zip["flag"] == "zip:e3":
					_draw_zip_cable(zip)
					_refresh_zip_label(zip)
			Sfx.play("layer_done", -4.0)
			hud.flash_pickup("ПРОВОД АКТИВЕН — лети к блоку-отключателю!")
		return

	# выключатель ловушек на вершине блока
	if not GameState.flag("traps_off") and pp.distance_to(Vector3(134, 7.0, -252)) < 3.0:
		if pressed:
			var prog: = _hold_progress("override", delta, 1.5)
			hud.set_prompt("отключение ловушек… %d%%" % int(prog * 100.0))
			if prog >= 1.0:
				_hold_key = ""
				_disable_traps()
		else:
			_hold_key = ""
			hud.set_prompt("[E держать] ОТКЛЮЧИТЬ ВСЕ ЛОВУШКИ ЭТАПА")
		return

	# зиплайны
	for zip in _zips:
		if zip["flag"] != "" and not GameState.flag(zip["flag"]):
			continue
		for pair in [[zip["a"], zip["b"]], [zip["b"], zip["a"]]]:
			if pp.distance_to(pair[0]) < 2.6:
				hud.set_prompt("[E] ПРОВОД: перелёт на ту сторону")
				if just:
					_ride_zip(pair[0], pair[1])
				return

	# пилоны-головоломки Оракула
	for key in _pylons:
		if GameState.flag(key):
			continue
		var py: Dictionary = _pylons[key]
		if pp.distance_to(py["pos"]) < 2.8:
			hud.set_prompt("[E] ГОЛОВОЛОМКА ОРАКУЛА %s/15" % key.trim_prefix("opz:"))
			if just:
				var pylon_key: = key
				_open_puzzle(py["diff"], "ГОЛОВОЛОМКА ОРАКУЛА", func() -> void:
					_solve_pylon(pylon_key))
			return

	# стойки данных
	for key in _racks:
		if GameState.flag(key):
			continue
		var rk: Dictionary = _racks[key]
		if pp.distance_to(rk["pos"]) < 2.8:
			if not GameState.oracle_core_open():
				hud.set_prompt("стойка экранирована: решите головоломки, включите магистраль, захватите территории")
			elif pressed:
				var prog: = _hold_progress("rack:" + key, delta, 3.0)
				hud.set_prompt("кража данных… %d%%" % int(prog * 100.0))
				if prog >= 1.0:
					_hold_key = ""
					_steal_rack(key)
			else:
				_hold_key = ""
				hud.set_prompt("[E держать] СТОЙКА: украсть информацию")
			return

	# ядро Оракула
	if not _core.is_empty() and not GameState.oracle_core_down:
		var core_d: = Vector2(pp.x - ORACLE_CORE_POS.x, pp.z - ORACLE_CORE_POS.z).length()
		if core_d < 12.0:
			if not GameState.oracle_core_open():
				hud.set_prompt("ЯДРО ЭКРАНИРОВАНО — смотри табло над Оракулом")
				return
			if not GameState.oracle_data_stolen():
				hud.set_prompt("сначала украдите ВСЮ информацию: стойки %d/%d" % [GameState.oracle_racks_done(), GameState.ORACLE_RACKS])
				return
			if core_d < 9.0:
				if pressed:
					var prog: = _hold_progress("core", delta, 5.0)
					hud.set_prompt("РАЗРУШЕНИЕ ЯДРА… %d%%" % int(prog * 100.0))
					player.shake(0.15)
					if prog >= 1.0:
						_hold_key = ""
						_set_core_destroyed(false)
				else:
					_hold_key = ""
					hud.set_prompt("[E держать] РАЗРУШИТЬ РАБОТУ СЕРВЕРА")
				return

	# портал побега
	if not _escape.is_empty() and _escape["active"] and pp.distance_to(_escape["pos"]) < 3.4:
		hud.set_prompt("[E] СБЕЖАТЬ ИЗ ГРИДА")
		if just:
			_do_escape()
		return

	# блоки этапа 1
	for id in _blocks:
		var b: Dictionary = _blocks[id]
		var body: AnimatableBody3D = b["body"]
		if pp.distance_to(body.global_position) < 2.6:
			if b["weight"] >= 2 and not GameState.has_passive("ransomware"):
				hud.set_prompt("[E] ТЯЖЁЛЫЙ БЛОК: одному ОЧЕНЬ медленно (RANSOMWARE тащит бодро)")
			else:
				hud.set_prompt("[E] взять блок")
			if just:
				_grab_block(id)
			return

	# лифты: подсказка
	for lf in _lifts:
		if Vector2(pp.x - lf["x"], pp.z - lf["z"]).length() < 4.0:
			var powered: = GameState.stage2_lift_powered() if lf["power"] == "s2" else GameState.stage3_powered()
			if not powered:
				hud.set_prompt("лифт обесточен — смотри табло над ним")
				return

	# серверы
	_hold_key = ""
	_update_server_prompt(just)

func _hold_progress(key: String, delta: float, need: float) -> float:
	if _hold_key != key:
		_hold_key = key
		_hold_t = 0.0
	_hold_t += delta
	return _hold_t / need

func _disable_traps() -> void:
	GameState.set_flag("traps_off")
	Sfx.play("quarantine", -6.0, 1.6)
	hud.flash_pickup("ВСЕ ЛОВУШКИ ЭТАПА 3 ОТКЛЮЧЕНЫ")
	# перестроить подписи блока-отключателя
	_label3d("✓ ЛОВУШКИ ОТКЛЮЧЕНЫ", Vector3(134, 8.2, -252), 28, INFECTED_COLOR)

func _do_escape() -> void:
	GameState.campaign_won = true
	Sfx.play("hack_win")
	if Net.active:
		Net.toast_all("ОРАКУЛ МЁРТВ — стая уходит в белый туннель!", INFECTED_COLOR)
	get_tree().change_scene_to_file("res://scenes/victory_tunnel.tscn")

func _update_server_prompt(just: bool) -> void:
	prompt_target = {}
	var best: = 5.0
	for node in GameState.grid_nodes:
		if node["infected"]:
			continue
		var d: = player.global_position.distance_to(node["pos"])
		if d < best:
			best = d
			prompt_target = node
	if prompt_target.is_empty():
		hud.set_prompt("")
		return
	if not GameState.node_unlocked(prompt_target):
		hud.set_prompt("🔒 %s — %s" % [prompt_target["name"], GameState.node_lock_reason(prompt_target)])
		return
	hud.set_prompt("[E] ВЗЛОМ СЕРВЕРА: %s (%s · %s)" % [prompt_target["name"],
		GameState.TIERS[prompt_target["tier"]]["short"], prompt_target["av"]])
	if just:
		_begin_enter(prompt_target)

func _unhandled_input(event: InputEvent) -> void:
	if _win_shown or _entering:
		return
	if event.is_action_pressed("pause"):
		if _puzzle_open == null:
			_toggle_pause()
	elif event.is_action_pressed("evolve") and not _paused and evo_panel == null and _puzzle_open == null:
		_open_evolution()

# ── вход в узел: анимация «нырка» ───────────────────────────

func _begin_enter(node: Dictionary) -> void:
	if _entering:
		return
	_entering = true
	player.control_enabled = false
	if Net.active:
		if Net.is_server():
			Net.start_hack_with_fx(node)
		else:
			Net.srv_request_hack.rpc_id(1, node["id"])
	else:
		_play_enter_anim(node)
		await get_tree().create_timer(1.5).timeout
		GameState.start_hack(node)
		get_tree().change_scene_to_file("res://scenes/level.tscn")

func _on_enter_fx(node_id: int) -> void:
	for node in GameState.grid_nodes:
		if node["id"] == node_id:
			_play_enter_anim(node)
			return

func _play_enter_anim(node: Dictionary) -> void:
	## камера ныряет в ядро сервера, экран заливает свет — инъекция!
	_entering = true
	player.control_enabled = false
	Sfx.play("chain", 0.0, 1.1)
	var vis: Dictionary = node_visuals.get(node["id"], {})
	var core_y: float = vis.get("core_h", 3.0)
	var target: Vector3 = Vector3(node["pos"].x, core_y, node["pos"].z)

	var cam: = Camera3D.new()
	add_child(cam)
	cam.global_transform = player.camera.global_transform
	cam.fov = player.camera.fov
	cam.current = true

	var flash: = ColorRect.new()
	flash.color = Color(0.16, 0.95, 0.75, 0.0)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_layer.add_child(flash)

	var lbl: = UIKit.label("ИНЪЕКЦИЯ: %s" % node["name"], 40, UIKit.TEAL)
	lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	lbl.modulate.a = 0.0
	top_layer.add_child(lbl)

	cam.look_at(target, Vector3.UP)
	var tw: = create_tween()
	tw.set_parallel(true)
	tw.tween_property(cam, "global_position", target, 1.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(cam, "fov", 100.0, 1.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(flash, "color:a", 1.0, 1.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tw.tween_property(lbl, "modulate:a", 1.0, 0.4)

func _open_evolution() -> void:
	evo_panel = EvolutionScript.new()
	top_layer.add_child(evo_panel)
	if Net.active:
		player.control_enabled = false # в коопе Грид не замирает
	else:
		get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play("ui_click")
	evo_panel.closed.connect(func() -> void:
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		evo_panel.queue_free()
		evo_panel = null
		# пересобрать тело: уровень/ветка/скин могли измениться
		var pos: = player.global_position
		var yaw: float = player.yaw_pivot.rotation.y
		player.queue_free()
		player = VirusPlayer.new()
		player.position = pos
		add_child(player)
		player.yaw_pivot.rotation.y = yaw
		party.local_player = player)

func _toggle_pause() -> void:
	_paused = not _paused
	if Net.active:
		player.control_enabled = not _paused
	else:
		get_tree().paused = _paused
	pause_panel.visible = _paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _paused else Input.MOUSE_MODE_CAPTURED

func _show_win() -> void:
	_win_shown = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var root: = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim: = ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.02, 0.9)
	root.add_child(UIKit.full_rect(dim))
	var center: = CenterContainer.new()
	root.add_child(UIKit.full_rect(center))
	var panel: = PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 400)
	panel.add_theme_stylebox_override("panel", UIKit.panel_box(INFECTED_COLOR, Color(0.008, 0.03, 0.04, 0.98), 2, 10, 32))
	center.add_child(panel)
	var v: = VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	v.add_child(UIKit.label("ОРАКУЛ МЁРТВ // ГРИД НАШ", 34, INFECTED_COLOR))
	v.add_child(UIKit.label("Вся информация украдена, ядро разрушено, стая ушла чисто.", 18, UIKit.WHITE))
	v.add_child(UIKit.label("Собрано Data Fragments: %d · Code Samples: %d · Mutagen: %d · Ghost Tokens: %d" % [
		GameState.resources["data_fragments"], GameState.resources["code_samples"],
		GameState.resources["mutagen"], GameState.resources["ghost_tokens"]], 16, UIKit.DIM))
	var btn: = UIKit.button("  НОВАЯ КАМПАНИЯ  ", 20, UIKit.TEAL)
	btn.pressed.connect(func() -> void:
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	v.add_child(btn)
	top_layer.add_child(root)
