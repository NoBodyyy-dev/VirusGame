extends Node3D

## PANIC PROTOCOL — узел как ограбление ОТ ПЕРВОГО ЛИЦА.
## Вместо летающих стражей — СИСТЕМА: экран на стене, камеры-сканеры,
## ловушки, вылетающие из стен, и робот-охотник на 100% тревоги.
## Рельеф: антресоли с пандусами, лифт, провода-туннели. Без брифа — сразу в бой.
## Хост владеет: лутом, системой, тревогой, HP, задачами, эвакуацией.

const HUDScript: = preload("res://scripts/hud.gd")
const ResultsScript: = preload("res://scripts/results_ui.gd")

const PAD_POS: = Vector3(-27.0, 0.0, 0.0)
const PAD_RADIUS: = 3.6
const REVIVE_TIME: = 3.0
const COOLER_TIME: = 2.6
const SYNC_CHARGE_TIME: = 2.8    # сек удержания на рычаг
const SYNC_DECAY: = 0.16         # заряд утекает без удержания
const ZONE_RADIUS: = 4.5
const ZONE_TIME: = 14.0          # сек монтажа в одиночку
const RELAY_WINDOW: = 12.0       # сек на цепь после первой опоры
const LEDGE_Y: = 2.4             # высота антресоли

var hall: = Vector2(70.0, 46.0)
var rng: = RandomNumberGenerator.new()
var theme: = "home"

var player: VirusPlayer
var loots: = {}              # lid -> LootItem
var tasks_rt: Array = []     # runtime полевых задач
var portal: Node3D
var portal_ring_mat: StandardMaterial3D
var portal_light: OmniLight3D
var pad_mat: StandardMaterial3D
var cooler: Node3D
var cooler_label: Label3D
var cooler_charges: = 3
var cooler_pos: = Vector3(-2.0, 0.0, 16.0)
var env: Environment
var is_boss: = false

var hud_layer: CanvasLayer
var top_layer: CanvasLayer
var hud: Control
var pause_panel: Control

var ability_cd: = 0.0
var phase: = "heist"          # heist / done (эвакуация = evac_open)
var _paused_by_menu: = false
var _fog_base: = Color(0.3, 0.6, 0.8)
var _next_lid: = 0
var _next_uid: = 0

# ── СИСТЕМА: камеры, ловушки, робот ──
var cams: Array = []          # [{node, cone, pos, base_yaw, sweep, phase}]
var sys_units: = {}           # uid -> {type, node, ...} (хост симулирует, клиент — куклы)
var sys_screen_label: Label3D
var sys_screen_mat: StandardMaterial3D
var _trap_timer: = 6.0
var _traps_sent: = 0
var _marked: = {}             # id -> until (хост)
var _robot_spawned: = false
var _decoy_until: = 0.0
var _decoy_pos: = Vector3.ZERO
var _frozen_until: = 0.0      # шифрование: система замирает

# ── кооп и пати ──
var avatars: = {}
var party: PartyFx
var _unit_sync: = 0.0
var _loot_sync: = 0.0
var _task_sync: = 0.0
var _host_hp: = {}            # id -> hp (владеет хост; для соло — {1: hp})
var _revive_t: = {}           # id -> прогресс реанимации на паде
var _cooler_hold: = 0.0
var _my_hold_idx: = -1        # какой рычаг я сейчас держу
var _my_hold_sub: = -1
var _demo_timer: = 0.0
var _demo_grab_cd: = 0.0
var _high_spots: Array = []   # точки лута на антресоли (достижимы по пандусам)
var _crate_spots: Array = []
var _wires: Array = []        # провода-туннели [{a, b}]
var _riding_wire: = false
var _my_phase_seen: = 0
var _screen_t: = 0.0

func _ready() -> void:
	if GameState.node_config.is_empty():
		if GameState.grid_nodes.is_empty():
			GameState.new_campaign()
		GameState.start_hack(GameState.grid_nodes[0])
	is_boss = GameState.node_config.get("boss", false)
	theme = GameState.node_config.get("theme", "home")
	# сид узла: у всех пиров одинаковая геометрия, у каждого узла — своя
	rng.seed = int(GameState.node_config.get("seed", 1))
	hall = Vector2(70.0 + rng.randf_range(0.0, 18.0), 46.0 + rng.randf_range(0.0, 14.0))
	cooler_pos = Vector3(rng.randf_range(-6.0, 10.0), 0.0, rng.randf_range(6.0, hall.y * 0.5 - 12.0))
	_build_environment()
	_build_arena()
	_build_theme_props()
	_build_terrain()
	_build_portal_and_pad()
	_build_cooler()
	_build_system_screen()
	_build_cameras()
	_spawn_player()
	_spawn_task_stations()
	_build_particles()
	_build_ui()
	if Net.active:
		_setup_coop()
	if Net.is_server():
		_host_init()
	# автотест системы охраны: старт с почти полной тревогой
	if "alarmtest" in OS.get_cmdline_user_args():
		GameState.alarm = 92.0
	# без модального брифа — сразу в дело
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.toast("%s · %s · выносим ◈ и тихо!" % [GameState.node_config["name"], GameState.node_config["tier_name"]], UIKit.TEAL)
	if GameState.node_config.get("assist", 0.0) > 0.0:
		hud.toast("ВСПОМОГАТЕЛЬНЫЙ ВЗЛОМ: рой зоны давит на систему (−%d%% квоты)" % int(GameState.node_config["assist"] * 60.0), Color("4a90ff"))
	Sfx.ambient(true, 0.85 if is_boss else 1.0)

func _dlog(msg: String) -> void:
	if GameState.demo_mode:
		print("[LVL] %s" % msg)

# ── хост: старт симуляции ───────────────────────────────────

func _host_init() -> void:
	_host_hp[1] = GameState.my_max_hp
	if Net.active:
		Net.set_hp(1, GameState.my_max_hp, false)
	_spawn_loot_table()
	_trap_timer = float(GameState.node_config.get("trap_interval", 12.0))

# ── окружение ───────────────────────────────────────────────

func _build_environment() -> void:
	## кинематографичный реализм в духе RE2: контрастный свет прожекторов,
	## мокрый отражающий пол (SSR), объёмный туман, мягкая цветокоррекция
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.016, 0.026)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.36, 0.48)
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.05
	env.ssao_enabled = true
	env.ssao_intensity = 2.0
	env.ssao_radius = 1.8
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.014
	_fog_base = Color(0.55, 0.25, 0.3) if is_boss else [
		Color(0.35, 0.65, 0.8), Color(0.7, 0.55, 0.3), Color(0.45, 0.3, 0.75), Color(0.7, 0.3, 0.45),
	][GameState.node_config.get("difficulty", 0)]
	env.volumetric_fog_albedo = _fog_base
	env.volumetric_fog_emission = Color(0.012, 0.028, 0.045)
	env.volumetric_fog_emission_energy = 0.3
	var we: = WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# холодный «лунный» заполняющий свет — основную работу делают прожекторы
	var moon: = DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-58, 28, 0)
	moon.light_color = Color(0.55, 0.65, 0.85)
	moon.light_energy = 0.25
	moon.shadow_enabled = true
	add_child(moon)

func _neon_mat(c: Color, energy: = 1.6) -> StandardMaterial3D:
	var m: = StandardMaterial3D.new()
	m.albedo_color = Color(0.02, 0.03, 0.05)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m

func _dark_mat() -> StandardMaterial3D:
	## тёмный пластик техники с шумовой текстурой (см. Mats)
	return Mats.plastic(Color(0.3, 0.33, 0.38))

func _metal_mat(c: Color, rough: = 0.35) -> StandardMaterial3D:
	return Mats.metal(c, rough)

func _box(size: Vector3, mat: Material, pos: Vector3, parent: Node = self) -> MeshInstance3D:
	var mi: = MeshInstance3D.new()
	var mesh: = BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _collider(size: Vector3, pos: Vector3, rot: = Vector3.ZERO) -> void:
	var sb: = StaticBody3D.new()
	sb.collision_layer = 1
	var cs: = CollisionShape3D.new()
	var box: = BoxShape3D.new()
	box.size = size
	cs.shape = box
	sb.position = pos
	sb.rotation = rot
	sb.add_child(cs)
	add_child(sb)

func _solid_box(size: Vector3, mat: Material, pos: Vector3) -> void:
	_box(size, mat, pos)
	_collider(size, pos)

func _ramp(size: Vector3, mat: Material, pos: Vector3, rot: Vector3) -> void:
	## наклонная плита-пандус с коллизией
	var mi: = _box(size, mat, pos)
	mi.rotation = rot
	_collider(size, pos, rot)

func _spot_free(pos: Vector3, clearance: = 3.5) -> bool:
	## не застраиваем зону выноса, кулер и дорожку к порталу
	if pos.distance_to(Vector3(PAD_POS.x, pos.y, PAD_POS.z)) < 8.0:
		return false
	if pos.x < -14.0 and absf(pos.z) < 4.0:
		return false
	if Vector2(pos.x - cooler_pos.x, pos.z - cooler_pos.z).length() < clearance:
		return false
	return true

func _build_arena() -> void:
	# мокрый бетон: тёмный глянец, в котором отражаются лампы (SSR)
	var floor_mesh: = MeshInstance3D.new()
	var plane: = PlaneMesh.new()
	plane.size = hall
	floor_mesh.mesh = plane
	floor_mesh.material_override = Mats.wet_floor()
	add_child(floor_mesh)
	_collider(Vector3(hall.x, 0.5, hall.y), Vector3(0, -0.25, 0))
	# цветовой акцент тира — светящаяся окантовка по периметру пола
	var tier: int = GameState.node_config.get("difficulty", 0)
	var tier_cols: = [Color(0.08, 0.75, 0.95), Color(0.85, 0.6, 0.2), Color(0.5, 0.3, 0.95), Color(0.9, 0.3, 0.5)]
	var edge_col: Color = Color(0.9, 0.15, 0.25) if is_boss else tier_cols[tier]
	var ex: = hall.x * 0.5 - 1.2
	var ez: = hall.y * 0.5 - 1.2
	_box(Vector3(hall.x - 2.4, 0.04, 0.18), _neon_mat(edge_col, 1.2), Vector3(0, 0.03, -ez))
	_box(Vector3(hall.x - 2.4, 0.04, 0.18), _neon_mat(edge_col, 1.2), Vector3(0, 0.03, ez))
	_box(Vector3(0.18, 0.04, hall.y - 2.4), _neon_mat(edge_col, 1.2), Vector3(-ex, 0.03, 0))
	_box(Vector3(0.18, 0.04, hall.y - 2.4), _neon_mat(edge_col, 1.2), Vector3(ex, 0.03, 0))

	# новый пол: панели-плиты и напольные кабель-каналы
	var panel_mat: = _dark_mat()
	panel_mat.albedo_color = Color(0.16, 0.185, 0.22)
	panel_mat.roughness = 0.6
	for i in 18:
		var p: = Vector3(rng.randf_range(-hall.x * 0.5 + 5.0, hall.x * 0.5 - 5.0), 0.03, rng.randf_range(-hall.y * 0.5 + 5.0, hall.y * 0.5 - 5.0))
		_box(Vector3(rng.randf_range(3.0, 5.0), 0.06, rng.randf_range(3.0, 5.0)), panel_mat, p)
	for i in 5:
		var z: = rng.randf_range(-hall.y * 0.5 + 6.0, hall.y * 0.5 - 6.0)
		_box(Vector3(hall.x - 14.0, 0.05, 0.3), _neon_mat(Color(0.1, 0.4, 0.55), 0.5), Vector3(2.0, 0.05, z))

	var wall_mat: = Mats.concrete(Color(0.42, 0.44, 0.48))
	var trim_color: = Color(0.7, 0.12, 0.2) if is_boss else Color(0.12, 0.55, 0.75)
	var trim_mat: = _neon_mat(trim_color, 0.7)
	var hx: = hall.x * 0.5
	var hz: = hall.y * 0.5
	for side in [
		{"size": Vector3(hall.x, 7, 0.6), "pos": Vector3(0, 3.5, -hz)},
		{"size": Vector3(hall.x, 7, 0.6), "pos": Vector3(0, 3.5, hz)},
		{"size": Vector3(0.6, 7, hall.y), "pos": Vector3(-hx, 3.5, 0)},
		{"size": Vector3(0.6, 7, hall.y), "pos": Vector3(hx, 3.5, 0)},
	]:
		_box(side["size"], wall_mat, side["pos"])
		_collider(side["size"], side["pos"])
		var trim_size: Vector3 = side["size"]
		trim_size.y = 0.08
		var trim_pos: Vector3 = side["pos"]
		trim_pos.y = 2.6
		_box(trim_size * Vector3(1.0, 1.0, 1.02), trim_mat, trim_pos)

	# потолок с коллайдером — камера больше не выходит за пределы коробки
	var ceil_mat: = Mats.concrete(Color(0.3, 0.31, 0.34), 0.2)
	_box(Vector3(hall.x, 0.35, hall.y), ceil_mat, Vector3(0, 7.3, 0))
	_collider(Vector3(hall.x, 0.35, hall.y), Vector3(0, 7.3, 0))
	# промышленные прожекторы: тёплый направленный свет с тенями (стиль RE2)
	var lamp_mat: = StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(0.95, 0.9, 0.8)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.93, 0.78)
	lamp_mat.emission_energy_multiplier = 3.2
	var cols_n: = 3
	var rows_n: = 2
	for gx in cols_n:
		for gz in rows_n:
			var lp: = Vector3(
				(float(gx) - float(cols_n - 1) * 0.5) * hall.x * 0.3,
				7.02,
				(float(gz) - float(rows_n - 1) * 0.5) * hall.y * 0.42)
			_box(Vector3(4.6, 0.14, 1.7), lamp_mat, lp)
			_box(Vector3(4.9, 0.1, 2.0), _metal_mat(Color(0.2, 0.21, 0.24), 0.4), lp + Vector3(0, 0.12, 0))
			var sl: = SpotLight3D.new()
			sl.light_color = Color(1.0, 0.93, 0.8)
			sl.light_energy = 4.5
			sl.spot_range = 16.0
			sl.spot_angle = 55.0
			sl.spot_angle_attenuation = 0.8
			sl.shadow_enabled = true
			sl.position = lp + Vector3(0, -0.3, 0)
			sl.rotation_degrees = Vector3(-90, 0, 0)
			add_child(sl)
	# настенные светильники — тёплые пятна света по периметру
	var sconce_mat: = _neon_mat(Color(1.0, 0.75, 0.45), 2.6)
	for i in 3:
		for side in [-1.0, 1.0]:
			var sx: = (float(i) - 1.0) * hall.x * 0.32
			var sp: = Vector3(sx, 3.6, side * (hz - 0.75))
			_box(Vector3(0.9, 0.25, 0.18), sconce_mat, sp)
			var wl: = OmniLight3D.new()
			wl.light_color = Color(1.0, 0.78, 0.5)
			wl.light_energy = 1.1
			wl.omni_range = 8.0
			wl.position = sp + Vector3(0, 0.3, -side * 0.8)
			add_child(wl)

	# декоративные «свечки» неона
	for i in 14:
		var p: = Vector3(rng.randf_range(-hx + 3, hx - 3), 2.6, rng.randf_range(-hz + 3, hz - 3))
		var c: = Color(0.1, rng.randf_range(0.5, 0.8), rng.randf_range(0.7, 1.0))
		_box(Vector3(0.05, rng.randf_range(2.5, 5.0), 0.05), _neon_mat(c, rng.randf_range(0.5, 1.1)), p)

# ── тематические локации ────────────────────────────────────

func _build_theme_props() -> void:
	if is_boss:
		_theme_boss()
		return
	match theme:
		"home": _theme_home()
		"office": _theme_office()
		"bank": _theme_bank()
		"dc": _theme_dc()

func _theme_home() -> void:
	## незащищённый ПК: гигантские клавиши, планки RAM, башня системника
	var key_mat: = _dark_mat()
	var kx: = rng.randf_range(-4.0, 10.0)
	var kz: = rng.randf_range(-14.0, -4.0)
	for row in 3:
		for col in 5:
			if rng.randf() < 0.25:
				continue
			var pos: = Vector3(kx + col * 3.1, 0.8, kz + row * 3.1)
			if not _spot_free(pos):
				continue
			_solid_box(Vector3(2.6, 1.6, 2.6), key_mat, pos)
			_box(Vector3(2.4, 0.06, 2.4), _neon_mat(Color(0.15, 0.7, 0.9), 0.9), pos + Vector3(0, 0.84, 0))
	for i in 3 + rng.randi() % 3:
		var pos: = Vector3(rng.randf_range(-16.0, 24.0), 1.4, rng.randf_range(4.0, hall.y * 0.5 - 7.0))
		if not _spot_free(pos):
			continue
		_solid_box(Vector3(7.5, 2.8, 0.9), key_mat, pos)
		for k in 4:
			_box(Vector3(0.9, 1.6, 0.1), _neon_mat(Color(0.2, 0.85, 0.5), 1.3), pos + Vector3(-2.6 + k * 1.7, 0.2, 0.51))
	var tower_pos: = Vector3(hall.x * 0.5 - 5.0, 3.0, rng.randf_range(-10.0, 10.0))
	_solid_box(Vector3(4.5, 6.0, 6.5), key_mat, tower_pos)
	_box(Vector3(0.4, 0.4, 0.4), _neon_mat(Color(0.2, 0.9, 0.6), 2.5), tower_pos + Vector3(-2.3, 1.8, 2.0))

func _theme_office() -> void:
	## лавки и офисы: кубиклы, столы с мониторами, ксерокс
	var desk_mat: = _dark_mat()
	var part_mat: = _dark_mat()
	part_mat.albedo_color = Color(0.09, 0.1, 0.13)
	for row in 2:
		for col in 3:
			var base: = Vector3(-10.0 + col * 14.0 + rng.randf_range(-2, 2), 0.0, -12.0 + row * 16.0 + rng.randf_range(-2, 2))
			if not _spot_free(base, 5.0):
				continue
			_solid_box(Vector3(6.0, 2.2, 0.5), part_mat, base + Vector3(0, 1.1, -2.5))
			_solid_box(Vector3(0.5, 2.2, 5.0), part_mat, base + Vector3(-3.0, 1.1, 0))
			_solid_box(Vector3(3.4, 1.0, 1.6), desk_mat, base + Vector3(0.4, 0.5, -1.4))
			var mon_col: = Color(0.2, 0.7, 0.95) if rng.randf() < 0.5 else Color(0.95, 0.7, 0.25)
			var mon: = _box(Vector3(1.5, 1.0, 0.12), _neon_mat(mon_col, 1.4), base + Vector3(0.4, 1.6, -1.7))
			mon.rotation.y = rng.randf_range(-0.3, 0.3)
	var xerox: = Vector3(rng.randf_range(14.0, 24.0), 1.0, rng.randf_range(-6.0, 6.0))
	if _spot_free(xerox):
		_solid_box(Vector3(2.2, 2.0, 2.2), desk_mat, xerox)
		_box(Vector3(1.8, 0.08, 1.8), _neon_mat(Color(0.9, 0.4, 0.2), 1.6), xerox + Vector3(0, 1.06, 0))

func _theme_bank() -> void:
	## военные сети: колонны, гермодверь, ящики с «золотом данных»
	var col_mat: = _dark_mat()
	col_mat.metallic = 0.8
	for i in 6:
		var pos: = Vector3(-14.0 + (i % 3) * 14.0, 3.0, -9.0 + float(i / 3) * 18.0)
		pos.x += rng.randf_range(-1.5, 1.5)
		if not _spot_free(pos, 4.0):
			continue
		_solid_box(Vector3(2.4, 6.0, 2.4), col_mat, pos)
		_box(Vector3(2.6, 0.3, 2.6), _neon_mat(Color(0.95, 0.75, 0.3), 1.3), pos + Vector3(0, 3.1, 0))
		_box(Vector3(2.6, 0.3, 2.6), _neon_mat(Color(0.95, 0.75, 0.3), 1.3), pos + Vector3(0, -2.9, 0))
	var vault: = MeshInstance3D.new()
	var cyl: = CylinderMesh.new()
	cyl.top_radius = 4.2
	cyl.bottom_radius = 4.2
	cyl.height = 1.0
	vault.mesh = cyl
	vault.material_override = _neon_mat(Color(0.95, 0.75, 0.3), 0.9)
	vault.rotation.x = deg_to_rad(90.0)
	vault.position = Vector3(rng.randf_range(-8.0, 16.0), 4.0, -hall.y * 0.5 + 0.8)
	add_child(vault)
	for i in 4 + rng.randi() % 4:
		var pos: = Vector3(rng.randf_range(-18.0, 26.0), 0.6, rng.randf_range(-hall.y * 0.5 + 6.0, hall.y * 0.5 - 6.0))
		if not _spot_free(pos):
			continue
		_solid_box(Vector3(1.8, 1.2, 1.2), _neon_mat(Color(0.95, 0.8, 0.35), 0.7), pos)

func _theme_dc() -> void:
	## дата-центр: ряды серверных стоек + кабельные лотки
	var rack_mat: = _dark_mat()
	var strip_colors: = [Color(0.15, 0.7, 0.9), Color(0.12, 0.8, 0.6), Color(0.45, 0.3, 0.9)]
	var row_gap: = rng.randf_range(7.0, 9.0)
	var rows: = int(hall.y / row_gap) - 1
	for r in rows:
		var rz: = -hall.y * 0.5 + row_gap * float(r + 1)
		var gap_at: = rng.randi() % 5
		for c in 6:
			if c == gap_at:
				continue
			var pos: = Vector3(-18.0 + c * 8.5, 1.5, rz)
			if not _spot_free(pos):
				continue
			_solid_box(Vector3(5.0, 3.0, 1.4), rack_mat, pos)
			var sc: Color = strip_colors[rng.randi() % strip_colors.size()]
			for k in 3:
				_box(Vector3(4.6, 0.06, 0.06), _neon_mat(sc, 1.5), pos + Vector3(0, -0.9 + k * 0.8, 0.74))
		_box(Vector3(44.0, 0.15, 0.8), _neon_mat(Color(0.2, 0.5, 0.7), 0.6), Vector3(0, 4.9, rz))

func _theme_boss() -> void:
	## ПЕНТАГОН: пятиугольное ядро и кольца вычислений
	var core_mat: = _neon_mat(Color(0.9, 0.2, 0.3), 1.6)
	var penta: = MeshInstance3D.new()
	var pmesh: = CylinderMesh.new()
	pmesh.top_radius = 7.0
	pmesh.bottom_radius = 7.5
	pmesh.height = 6.0
	pmesh.radial_segments = 5
	penta.mesh = pmesh
	penta.material_override = _dark_mat()
	penta.position = Vector3(8.0, 3.0, 0.0)
	add_child(penta)
	var pc: = CylinderShape3D.new()
	pc.radius = 7.5
	pc.height = 6.0
	var psb: = StaticBody3D.new()
	psb.collision_layer = 1
	var pcs: = CollisionShape3D.new()
	pcs.shape = pc
	psb.position = penta.position
	psb.add_child(pcs)
	add_child(psb)
	_box(Vector3(15.5, 0.3, 15.5), core_mat, penta.position + Vector3(0, 3.2, 0))
	for i in 5:
		var ang: = TAU * float(i) / 5.0
		var pos: = penta.position + Vector3(cos(ang) * 12.0, 3.5, sin(ang) * 12.0)
		if not _spot_free(pos, 4.0):
			continue
		_solid_box(Vector3(2.0, 7.0, 2.0), _dark_mat(), pos)
		_box(Vector3(2.2, 0.4, 2.2), core_mat, pos + Vector3(0, rng.randf_range(-2.0, 2.5), 0))
	for k in 3:
		var ring: = MeshInstance3D.new()
		var tor: = TorusMesh.new()
		tor.inner_radius = 9.0 + k * 3.0
		tor.outer_radius = 9.3 + k * 3.0
		ring.mesh = tor
		ring.material_override = _neon_mat(Color(0.8, 0.15, 0.25), 0.8)
		ring.position = penta.position + Vector3(0, 6.0 + k * 1.2, 0)
		add_child(ring)

# ── рельеф: антресоль, пандусы, лифт, провода ───────────────

func _build_terrain() -> void:
	var mat: = _dark_mat()
	var glow: = _neon_mat(Color(0.16, 0.95, 0.75) if not is_boss else Color(0.9, 0.25, 0.3), 1.2)
	var hz: = hall.y * 0.5
	# антресоль вдоль дальней стены (+Z): весь лут наверху достижим ногами
	var ledge_len: = hall.x * 0.55
	var ledge_x: = rng.randf_range(-4.0, 10.0)
	var ledge_pos: = Vector3(ledge_x, LEDGE_Y, hz - 3.2)
	_solid_box(Vector3(ledge_len, 0.4, 6.0), mat, ledge_pos)
	_box(Vector3(ledge_len, 0.06, 0.15), glow, ledge_pos + Vector3(0, 0.24, -3.0))
	# пандусы с двух концов
	var ramp_len: = 7.5
	for side in [-1.0, 1.0]:
		var rx: float = ledge_x + side * (ledge_len * 0.5 + ramp_len * 0.45)
		_ramp(Vector3(ramp_len, 0.35, 5.0), mat, Vector3(rx, LEDGE_Y * 0.5, hz - 3.2),
			Vector3(0, 0, -side * atan(LEDGE_Y / ramp_len)))
	# точки лута на антресоли
	for i in 4:
		_high_spots.append(ledge_pos + Vector3(rng.randf_range(-ledge_len * 0.4, ledge_len * 0.4), 0.9, rng.randf_range(-1.5, 1.5)))
	# лифт-платформа: пол ↔ антресоль
	var lift: = AnimatableBody3D.new()
	lift.sync_to_physics = false
	lift.collision_layer = 1
	var lcs: = CollisionShape3D.new()
	var lbox: = BoxShape3D.new()
	lbox.size = Vector3(3.2, 0.35, 3.2)
	lcs.shape = lbox
	lift.add_child(lcs)
	var lmesh: = MeshInstance3D.new()
	var lbm: = BoxMesh.new()
	lbm.size = Vector3(3.2, 0.35, 3.2)
	lmesh.mesh = lbm
	lmesh.material_override = _neon_mat(Color(0.3, 0.8, 1.0), 0.9)
	lift.add_child(lmesh)
	var lift_x: = ledge_x - ledge_len * 0.5 - 12.0
	lift.position = Vector3(lift_x, 0.25, hz - 3.2)
	add_child(lift)
	var ltw: = create_tween().set_loops()
	ltw.tween_property(lift, "position:y", LEDGE_Y + 0.05, 3.0).set_trans(Tween.TRANS_SINE)
	ltw.tween_interval(1.2)
	ltw.tween_property(lift, "position:y", 0.25, 3.0).set_trans(Tween.TRANS_SINE)
	ltw.tween_interval(1.2)
	var llbl: = Label3D.new()
	llbl.text = "ЛИФТ"
	llbl.font_size = 26
	llbl.modulate = Color(0.3, 0.8, 1.0)
	llbl.outline_size = 6
	llbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	llbl.position = Vector3(lift_x, 3.6, hz - 3.2)
	add_child(llbl)

	# точки тяжёлых ящиков — только на земле, всё достижимо ногами
	for i in 10:
		var cpos: = Vector3(rng.randf_range(-hall.x * 0.5 + 8.0, hall.x * 0.5 - 6.0), 0.7, rng.randf_range(-hall.y * 0.5 + 6.0, hall.y * 0.5 - 6.0))
		if _spot_free(cpos):
			_crate_spots.append(cpos)
	if _crate_spots.is_empty():
		_crate_spots.append(Vector3(12, 0.7, 8))

	# провода-туннели: вирус путешествует по кабелю [E]
	var wire_count: = 2 if hall.x > 76.0 else 1
	for w in wire_count:
		var a: = Vector3(rng.randf_range(-hall.x * 0.5 + 10.0, -2.0), 0.0, rng.randf_range(-hz + 8.0, hz - 10.0))
		var b: = Vector3(rng.randf_range(8.0, hall.x * 0.5 - 8.0), 0.0, rng.randf_range(-hz + 8.0, hz - 10.0))
		if not _spot_free(a, 2.5) or not _spot_free(b, 2.5):
			continue
		_wires.append({"a": a, "b": b})
		for endpoint in [a, b]:
			var post: = MeshInstance3D.new()
			var pcyl: = CylinderMesh.new()
			pcyl.top_radius = 0.22
			pcyl.bottom_radius = 0.34
			pcyl.height = 1.5
			post.mesh = pcyl
			post.material_override = _neon_mat(Color(0.95, 0.6, 0.2), 1.4)
			post.position = endpoint + Vector3(0, 0.75, 0)
			add_child(post)
			var plbl: = Label3D.new()
			plbl.text = "ПРОВОД [E] — переброс"
			plbl.font_size = 22
			plbl.modulate = Color(0.95, 0.6, 0.2)
			plbl.outline_size = 6
			plbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			plbl.position = endpoint + Vector3(0, 2.1, 0)
			add_child(plbl)
		# сам кабель — цепочка сегментов с провисом
		var segs: = 10
		for s in segs:
			var t0: = float(s) / float(segs)
			var t1: = float(s + 1) / float(segs)
			var p0: = a.lerp(b, t0) + Vector3(0, 1.4 + sin(t0 * PI) * 1.6, 0)
			var p1: = a.lerp(b, t1) + Vector3(0, 1.4 + sin(t1 * PI) * 1.6, 0)
			var seg: = _box(Vector3(0.08, 0.08, p0.distance_to(p1)), _neon_mat(Color(0.95, 0.6, 0.2), 0.8), (p0 + p1) * 0.5)
			seg.look_at_from_position(seg.position, p1, Vector3.UP)

# ── СИСТЕМА: экран на стене ─────────────────────────────────

func _build_system_screen() -> void:
	var hz: = hall.y * 0.5
	var root: = Node3D.new()
	root.position = Vector3(6.0, 0.0, -hz + 0.4)
	add_child(root)
	_box(Vector3(11.0, 4.6, 0.5), _dark_mat(), Vector3(0, 3.4, 0), root)
	var scr: = MeshInstance3D.new()
	var quad: = QuadMesh.new()
	quad.size = Vector2(10.2, 3.8)
	scr.mesh = quad
	sys_screen_mat = _neon_mat(Color(0.12, 0.5, 0.7), 1.0)
	sys_screen_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	scr.material_override = sys_screen_mat
	scr.position = Vector3(0, 3.4, 0.28)
	root.add_child(scr)
	sys_screen_label = Label3D.new()
	sys_screen_label.font_size = 40
	sys_screen_label.modulate = Color(0.75, 0.95, 1.0)
	sys_screen_label.outline_size = 6
	sys_screen_label.position = Vector3(0, 3.4, 0.36)
	root.add_child(sys_screen_label)
	_refresh_system_screen()

func _refresh_system_screen() -> void:
	var cfg: Dictionary = GameState.node_config
	var ph: = GameState.alarm_phase()
	var status: String = ["РЕЖИМ СНА", "СКАНИРОВАНИЕ", "ЗАЧИСТКА", "!! ВТОРЖЕНИЕ !!"][ph]
	sys_screen_label.text = "СИСТЕМА %s\nчувствительность %d · камер %d\nтревога %d%% · %s" % [
		cfg.get("antivirus", "?"), cfg.get("sensitivity", 1), cams.size(),
		roundi(GameState.alarm), status]
	var col: Color = [Color(0.12, 0.5, 0.7), Color(0.8, 0.6, 0.2), Color(0.85, 0.35, 0.2), Color(0.9, 0.12, 0.2)][ph]
	sys_screen_mat.emission = col
	if ph == 3:
		# 100%: система мигает красным
		sys_screen_mat.emission_energy_multiplier = 1.6 + sin(Time.get_ticks_msec() / 90.0) * 1.2

# ── СИСТЕМА: камеры на стенах ───────────────────────────────

func _build_cameras() -> void:
	var count: int = GameState.node_config.get("sensitivity", 1)
	var hx: = hall.x * 0.5
	var hz: = hall.y * 0.5
	for i in count:
		# камеры равномерно по периметру (кроме стены портала)
		var side: = i % 3
		var pos: Vector3
		var face: float
		match side:
			0:
				pos = Vector3(rng.randf_range(-hx * 0.5, hx - 6.0), 4.6, -hz + 0.8)
				face = 0.0
			1:
				pos = Vector3(rng.randf_range(-hx * 0.5, hx - 6.0), 4.6, hz - 0.8)
				face = PI
			2:
				pos = Vector3(hx - 0.8, 4.6, rng.randf_range(-hz + 6.0, hz - 6.0))
				face = PI * 0.5
		var cam_root: = Node3D.new()
		cam_root.position = pos
		add_child(cam_root)
		_box(Vector3(0.7, 0.5, 0.9), _dark_mat(), Vector3.ZERO, cam_root)
		var eye: = MeshInstance3D.new()
		var sm: = SphereMesh.new()
		sm.radius = 0.18
		sm.height = 0.36
		eye.mesh = sm
		eye.material_override = _neon_mat(Color(1.0, 0.3, 0.3), 2.5)
		eye.position = Vector3(0, 0, 0.5)
		cam_root.add_child(eye)
		# конус сканирования
		var cone: = MeshInstance3D.new()
		var cmesh: = CylinderMesh.new()
		cmesh.top_radius = 0.05
		var crange: float = GameState.node_config.get("cam_range", 12.0)
		cmesh.bottom_radius = crange * 0.36
		cmesh.height = crange
		var cmat: = StandardMaterial3D.new()
		cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cmat.albedo_color = Color(1.0, 0.25, 0.25, 0.05)
		cmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		cone.mesh = cmesh
		cone.material_override = cmat
		cone.rotation.x = deg_to_rad(-64.0)
		cone.position = Vector3(0, -crange * 0.42, crange * 0.34)
		cam_root.add_child(cone)
		cams.append({
			"node": cam_root, "cone_mat": cmat, "pos": pos,
			"base_yaw": face, "sweep": 0.85, "phase": rng.randf() * TAU,
			"range": crange,
		})

func _cam_dir(cam: Dictionary, t: float) -> Vector3:
	var yaw: float = cam["base_yaw"] + sin(t * 0.5 + cam["phase"]) * cam["sweep"]
	return Vector3(sin(yaw), 0.0, cos(yaw))

func _cams_tick(_delta: float) -> void:
	## каждый пир: поворот камер детерминирован временем
	var t: = Time.get_ticks_msec() / 1000.0
	var active: = GameState.alarm_phase() >= 1
	for cam in cams:
		var dir: = _cam_dir(cam, t)
		var node: Node3D = cam["node"]
		node.rotation.y = atan2(dir.x, dir.z)
		var cmat: StandardMaterial3D = cam["cone_mat"]
		cmat.albedo_color.a = 0.11 if active else 0.03
		# spyware видит сектора камер ярче
		if GameState.has_passive("spyware"):
			cmat.albedo_color.a += 0.05

# ── СИСТЕМА: хост-директор (ловушки и робот) ────────────────

func _detected_players() -> Array:
	## только хост: кто в конусе камеры / помечен / все при 100%
	var actors: = _all_actor_nodes()
	var now: = Time.get_ticks_msec() / 1000.0
	var out: Array = []
	var t: = now
	var everyone: = GameState.alarm_phase() >= 3
	for id in actors:
		var bugged: = Net.is_bug(id) if Net.active else GameState.my_bug
		if bugged:
			continue
		# троян-ящик невидим для камер
		var hidden: = false
		if id == Net.my_id():
			hidden = player.morphed
		elif avatars.has(id):
			hidden = avatars[id].morph_hidden
		if hidden:
			continue
		if everyone or _marked.get(id, 0.0) > now:
			out.append(id)
			continue
		if GameState.alarm_phase() < 1:
			continue
		var p: Vector3 = actors[id].global_position
		for cam in cams:
			var cpos: Vector3 = cam["pos"]
			var flat: = Vector3(p.x - cpos.x, 0.0, p.z - cpos.z)
			if flat.length() > cam["range"]:
				continue
			if flat.normalized().dot(_cam_dir(cam, t)) > 0.82:
				out.append(id)
				break
	return out

func _system_tick(delta: float) -> void:
	## только хост
	var now: = Time.get_ticks_msec() / 1000.0
	if now < _frozen_until:
		return # шифрование: система колом
	var detected: = _detected_players()
	# запуск ловушек: чем выше тревога и тир — тем чаще
	if not detected.is_empty():
		var speedup: = 1.0 + GameState.alarm / 100.0 + float(GameState.node_config.get("difficulty", 0)) * 0.25
		_trap_timer -= delta * speedup
		if _trap_timer <= 0.0:
			_trap_timer = float(GameState.node_config.get("trap_interval", 12.0))
			_launch_trap(detected.pick_random())
	# симуляция ловушек
	for uid in sys_units.keys():
		var u: Dictionary = sys_units[uid]
		match u["type"]:
			"ROBOT": _robot_tick(u, delta)
			"HOOK": _hook_tick(u, delta)
			_: _trap_tick(u, delta)
	# робот выезжает на 100%
	if GameState.alarm_phase() >= 3 and not _robot_spawned:
		_robot_spawned = true
		_spawn_unit("ROBOT", Vector3(hall.x * 0.5 - 4.0, 0.0, 0.0))
		var msg: = "⚠ СИСТЕМА ВЫСЛАЛА РОБОТА-ОХОТНИКА! Все видны!"
		if Net.active:
			Net.toast_all(msg, Color(1.0, 0.15, 0.25))
		else:
			hud.toast(msg, Color(1.0, 0.15, 0.25))
		Sfx.play("hunter")

func _launch_trap(target_id: int) -> void:
	var kinds: Array = GameState.node_config.get("trap_kinds", ["laser"])
	var kind: String = kinds.pick_random()
	var actors: = _all_actor_nodes()
	if not actors.has(target_id):
		return
	var tp: Vector3 = actors[target_id].global_position
	# ловушка вылетает из ближайшей стены
	var hx: = hall.x * 0.5
	var hz: = hall.y * 0.5
	var candidates: = [
		Vector3(-hx + 0.8, 2.2, tp.z), Vector3(hx - 0.8, 2.2, tp.z),
		Vector3(tp.x, 2.2, -hz + 0.8), Vector3(tp.x, 2.2, hz - 0.8),
	]
	var origin: Vector3 = candidates[0]
	for c in candidates:
		if c.distance_to(tp) < origin.distance_to(tp):
			origin = c
	var uid: = _spawn_unit(kind, origin)
	var u: Dictionary = sys_units[uid]
	u["target"] = target_id
	_traps_sent += 1
	Sfx.play("alarm", -10.0, 1.8)

func _spawn_unit(type: String, pos: Vector3) -> int:
	_next_uid += 1
	var uid: = _next_uid
	var node: = _build_unit_visual(type, pos)
	sys_units[uid] = {"type": type, "node": node, "target": 0, "life": 0.0,
		"hook_cd": rng.randf_range(4.0, 8.0), "hook_out": false, "ret": false, "origin": pos}
	if type in GameState.TRAPS:
		sys_units[uid]["life"] = float(GameState.TRAPS[type]["life"])
	if Net.active:
		Net.send_enemy_spawn(uid, type, pos)
	return uid

func _build_unit_visual(type: String, pos: Vector3) -> Node3D:
	var root: = Node3D.new()
	root.position = pos
	add_child(root)
	if type == "ROBOT":
		_build_robot_visual(root)
	elif type == "HOOK":
		# трёхпалая клешня-захват
		var claw_mat: = _metal_mat(Color(0.75, 0.5, 0.25), 0.3)
		var hub: = MeshInstance3D.new()
		var hsm: = SphereMesh.new()
		hsm.radius = 0.16
		hsm.height = 0.32
		hub.mesh = hsm
		hub.material_override = claw_mat
		root.add_child(hub)
		for i in 3:
			var ang: = TAU * float(i) / 3.0
			var prong: = _cone_mesh(0.07, 0.42, claw_mat, Vector3(cos(ang) * 0.16, sin(ang) * 0.16, -0.18), root)
			prong.rotation.x = deg_to_rad(115.0)
			prong.rotation.z = ang
		var hl: = OmniLight3D.new()
		hl.light_color = Color(1.0, 0.55, 0.2)
		hl.light_energy = 1.0
		hl.omni_range = 3.5
		root.add_child(hl)
	else:
		var info: Dictionary = GameState.TRAPS.get(type, {"color": Color(1, 0.3, 0.3)})
		var c: Color = info["color"]
		match type:
			"laser":
				var s: = MeshInstance3D.new()
				var sm2: = SphereMesh.new()
				sm2.radius = 0.22
				sm2.height = 0.44
				s.mesh = sm2
				s.material_override = _neon_mat(c, 3.5)
				root.add_child(s)
			"cage":
				_box(Vector3(0.6, 0.6, 0.6), _neon_mat(c, 1.6), Vector3.ZERO, root)
				var frame: = _box(Vector3(0.72, 0.72, 0.72), _holo_add(c, 0.25), Vector3.ZERO, root)
				frame.rotation_degrees = Vector3(15, 30, 0)
			"reflash":
				# летящая флешка
				_box(Vector3(0.5, 0.22, 0.9), _neon_mat(c, 1.8), Vector3.ZERO, root)
				_box(Vector3(0.3, 0.16, 0.3), _dark_mat(), Vector3(0, 0, -0.6), root)
			"mark":
				var tor: = MeshInstance3D.new()
				var tm: = TorusMesh.new()
				tm.inner_radius = 0.22
				tm.outer_radius = 0.34
				tor.mesh = tm
				tor.material_override = _neon_mat(c, 2.4)
				root.add_child(tor)
			"reset":
				var s2: = MeshInstance3D.new()
				var sm3: = SphereMesh.new()
				sm3.radius = 0.3
				sm3.height = 0.6
				s2.mesh = sm3
				s2.material_override = _neon_mat(c, 1.4)
				root.add_child(s2)
			"pull":
				var cone: = _cone_mesh(0.3, 0.8, _neon_mat(c, 2.0), Vector3.ZERO, root)
				cone.rotation.x = deg_to_rad(90.0)
		var tl: = OmniLight3D.new()
		tl.light_color = c
		tl.light_energy = 1.2
		tl.omni_range = 4.0
		root.add_child(tl)
	return root

func _build_robot_visual(root: Node3D) -> void:
	## робот-охотник НА КОЛЁСАХ: шасси, башня с пусковой трубой крюка,
	## купол-голова с линзой, антенна с мигающим маячком, полосы опасности
	var body_mat: = _metal_mat(Color(0.58, 0.62, 0.68), 0.35)
	var dark: = _metal_mat(Color(0.16, 0.17, 0.2), 0.5)
	var hazard_y: = _neon_mat(Color(0.95, 0.75, 0.15), 1.0)
	var hazard_b: = _metal_mat(Color(0.08, 0.08, 0.09), 0.6)

	# шасси с бампером
	_box(Vector3(1.9, 0.55, 2.5), body_mat, Vector3(0, 0.72, 0), root)
	_box(Vector3(1.6, 0.3, 2.2), dark, Vector3(0, 1.06, 0), root)
	# полосы опасности на переднем и заднем бампере
	for zz in [-1.28, 1.28]:
		for k in 4:
			var seg_mat: Material = hazard_y if k % 2 == 0 else hazard_b
			_box(Vector3(0.45, 0.32, 0.06), seg_mat, Vector3(-0.68 + float(k) * 0.45, 0.72, zz), root)
	# 4 колеса с дисками
	var wheels: Array = []
	var tire_mat: = Mats.rubber()
	for sx in [-1.0, 1.0]:
		for sz in [-0.85, 0.85]:
			var wheel: = MeshInstance3D.new()
			var wm: = CylinderMesh.new()
			wm.top_radius = 0.42
			wm.bottom_radius = 0.42
			wm.height = 0.32
			wheel.mesh = wm
			wheel.material_override = tire_mat
			wheel.rotation.z = deg_to_rad(90.0)
			wheel.position = Vector3(sx * 1.02, 0.42, sz)
			root.add_child(wheel)
			var hubcap: = MeshInstance3D.new()
			var hm: = CylinderMesh.new()
			hm.top_radius = 0.2
			hm.bottom_radius = 0.2
			hm.height = 0.34
			hubcap.mesh = hm
			hubcap.material_override = _neon_mat(Color(1.0, 0.3, 0.25), 1.2)
			wheel.add_child(hubcap)
			wheels.append(wheel)
	root.set_meta("wheels", wheels)
	# башня-торс
	_box(Vector3(1.35, 1.0, 1.1), body_mat, Vector3(0, 1.75, 0), root)
	_box(Vector3(1.42, 0.14, 1.16), dark, Vector3(0, 2.28, 0), root)
	# пусковая труба крюка на правом плече
	var tube: = MeshInstance3D.new()
	var tm: = CylinderMesh.new()
	tm.top_radius = 0.17
	tm.bottom_radius = 0.2
	tm.height = 1.0
	tube.mesh = tm
	tube.material_override = dark
	tube.rotation.x = deg_to_rad(90.0)
	tube.position = Vector3(0.62, 2.05, -0.35)
	root.add_child(tube)
	_box(Vector3(0.3, 0.3, 0.3), body_mat, Vector3(0.62, 2.05, 0.35), root)
	# кабели по левому борту
	for k in 3:
		_box(Vector3(0.06, 0.85, 0.06), _metal_mat(Color(0.12, 0.12, 0.14), 0.4), Vector3(-0.72, 1.75, -0.25 + float(k) * 0.25), root)
	# голова-купол с линзой
	var dome: = MeshInstance3D.new()
	var dm: = SphereMesh.new()
	dm.radius = 0.4
	dm.height = 0.62
	dome.mesh = dm
	dome.material_override = body_mat
	dome.position = Vector3(0, 2.55, 0)
	root.add_child(dome)
	var lens: = MeshInstance3D.new()
	var lm: = SphereMesh.new()
	lm.radius = 0.15
	lm.height = 0.3
	lens.mesh = lm
	lens.material_override = _neon_mat(Color(1.0, 0.2, 0.2), 4.0)
	lens.position = Vector3(0, 2.58, -0.34)
	root.add_child(lens)
	_box(Vector3(0.7, 0.1, 0.2), dark, Vector3(0, 2.75, -0.22), root)
	# антенна с маячком
	_box(Vector3(0.04, 0.55, 0.04), dark, Vector3(-0.35, 2.95, 0.2), root)
	var beacon: = MeshInstance3D.new()
	var bm2: = SphereMesh.new()
	bm2.radius = 0.1
	bm2.height = 0.2
	beacon.mesh = bm2
	var beacon_mat: = _neon_mat(Color(1.0, 0.45, 0.1), 2.0)
	beacon.material_override = beacon_mat
	beacon.position = Vector3(-0.35, 3.28, 0.2)
	root.add_child(beacon)
	root.set_meta("beacon_mat", beacon_mat)
	# красная подсветка угрозы
	var rl: = OmniLight3D.new()
	rl.light_color = Color(1.0, 0.25, 0.2)
	rl.light_energy = 1.6
	rl.omni_range = 9.0
	rl.position.y = 2.6
	root.add_child(rl)

func _units_visual_tick(delta: float) -> void:
	## каждый пир: колёса крутятся, маячок мигает, трос крюка тянется к роботу
	var t: = Time.get_ticks_msec() / 1000.0
	var robot_node: Node3D = null
	for uid in sys_units:
		var u: Dictionary = sys_units[uid]
		if u["type"] == "ROBOT" and is_instance_valid(u["node"]):
			robot_node = u["node"]
			break
	for uid in sys_units:
		var u: Dictionary = sys_units[uid]
		var node: Node3D = u["node"]
		if not is_instance_valid(node):
			continue
		match u["type"]:
			"ROBOT":
				var last: Vector3 = u.get("last_pos", node.global_position)
				var moved: = (node.global_position - last).length()
				u["last_pos"] = node.global_position
				var spin: = moved / 0.42
				for w in node.get_meta("wheels", []):
					if is_instance_valid(w):
						w.rotate_object_local(Vector3.UP, spin)
				var bmat: StandardMaterial3D = node.get_meta("beacon_mat", null)
				if bmat != null:
					bmat.emission_energy_multiplier = 1.2 + 3.0 * maxf(sin(t * 7.0), 0.0)
			"HOOK":
				node.rotate_z(delta * 4.0)
				var cable: MeshInstance3D = u.get("cable", null)
				if cable == null or not is_instance_valid(cable):
					cable = MeshInstance3D.new()
					var cbm: = BoxMesh.new()
					cbm.size = Vector3(0.05, 0.05, 1.0)
					cable.mesh = cbm
					cable.material_override = _metal_mat(Color(0.35, 0.28, 0.18), 0.5)
					add_child(cable)
					u["cable"] = cable
				var anchor: Vector3 = u["origin"]
				if robot_node != null:
					anchor = robot_node.global_position + Vector3(0.62, 2.05, 0)
				var from: = node.global_position
				var dist: = from.distance_to(anchor)
				if dist > 0.3:
					cable.global_position = (from + anchor) * 0.5
					cable.look_at_from_position(cable.global_position, anchor, Vector3.UP)
					cable.scale = Vector3(1, 1, dist)

func _cone_mesh(bottom: float, height: float, mat: Material, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var mi: = MeshInstance3D.new()
	var cm: = CylinderMesh.new()
	cm.top_radius = 0.01
	cm.bottom_radius = bottom
	cm.height = height
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _holo_add(c: Color, alpha: float) -> StandardMaterial3D:
	var m: = StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	return m

func _despawn_unit(uid: int) -> void:
	var u: Dictionary = sys_units.get(uid, {})
	if not u.is_empty():
		if is_instance_valid(u["node"]):
			u["node"].queue_free()
		var cable: MeshInstance3D = u.get("cable", null)
		if cable != null and is_instance_valid(cable):
			cable.queue_free()
	sys_units.erase(uid)
	if Net.active:
		Net.send_enemy_gone(uid)

func _trap_target_pos(u: Dictionary) -> Vector3:
	## куда летит ловушка (учитывает фантом Adware)
	var now: = Time.get_ticks_msec() / 1000.0
	if now < _decoy_until:
		return _decoy_pos
	var actors: = _all_actor_nodes()
	var tid: int = u["target"]
	if not actors.has(tid):
		return u["node"].global_position
	var p: Vector3 = actors[tid].global_position + Vector3(0, 1.1, 0)
	# пассивка Adware: ловушки иногда мажут по фантомному следу
	if Net.my_class_of(tid) == "adware" and rng.randf() < 0.2:
		p += Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4))
	return p

func _trap_tick(u: Dictionary, delta: float) -> void:
	var kind: String = u["type"]
	var info: Dictionary = GameState.TRAPS.get(kind, {})
	if info.is_empty():
		return
	u["life"] -= delta
	var node: Node3D = u["node"]
	var uid: = _uid_of(u)
	if u["life"] <= 0.0 or not is_instance_valid(node):
		_despawn_unit(uid)
		return
	var target: = _trap_target_pos(u)
	var dir: = (target - node.global_position)
	var dist: = dir.length()
	if dist > 0.05:
		node.global_position += dir.normalized() * minf(float(info["speed"]) * delta, dist)
		node.rotation.y = atan2(dir.x, dir.z)
	# попадание
	var actors: = _all_actor_nodes()
	var tid: int = u["target"]
	if actors.has(tid) and node.global_position.distance_to(actors[tid].global_position + Vector3(0, 1.1, 0)) < 1.0:
		_apply_trap_hit(kind, tid, node.global_position)
		_despawn_unit(uid)

func _uid_of(u: Dictionary) -> int:
	for uid in sys_units:
		if sys_units[uid] == u:
			return uid
	return -1

func _apply_trap_hit(kind: String, id: int, from: Vector3) -> void:
	## только хост: эффект ловушки
	var now: = Time.get_ticks_msec() / 1000.0
	match kind:
		"laser":
			_hurt_player(id, 1, from)
		"cage":
			Net.send_system_fx(id, "cage", 8.0) if Net.active else _on_system_fx(id, "cage", 8.0)
		"mark":
			_marked[id] = now + 10.0
			_hurt_player(id, 1, from)
			Net.send_system_fx(id, "mark", 10.0) if Net.active else _on_system_fx(id, "mark", 10.0)
		"reset":
			Net.send_system_fx(id, "reset", 10.0) if Net.active else _on_system_fx(id, "reset", 10.0)
		"pull":
			_hurt_player(id, 1, from)
			Net.send_system_fx(id, "pull", 0.0) if Net.active else _on_system_fx(id, "pull", 0.0)
		"reflash":
			_hurt_player(id, 3, from)
			Net.send_system_fx(id, "reflash", 15.0) if Net.active else _on_system_fx(id, "reflash", 15.0)
	Sfx.play("trap", -6.0, 1.2)

func _hurt_player(id: int, dmg: int, from: Vector3) -> void:
	## только хост: система ударила
	if phase == "done":
		return
	var cur: int = _host_hp.get(id, 3)
	cur = maxi(cur - dmg, 0)
	_host_hp[id] = cur
	var bug: = cur <= 0
	GameState.apply_alarm(2.0, "trap", "worm")
	for it in loots.values():
		if id in it.carriers:
			_release_item(it, id, false, Vector3.ZERO)
	if Net.active:
		Net.set_hp(id, cur, bug)
		Net.send_ragdoll(id, from)
		Net.score_event(id, "caught")
	else:
		GameState.my_hp = cur
		GameState.my_bug = bug
		GameState.hp_changed.emit(cur)
		GameState.stats["caught"] += 1
		player.ragdoll_from(from)
		hud.toast("ЛОВУШКА СИСТЕМЫ! HP −%d" % dmg, Color(1.0, 0.3, 0.3))
		if bug:
			player.set_bug(true)
			hud.toast("КРИТИЧЕСКИЙ СБОЙ: ты теперь БАГ. Ползи к порталу!", Color(1.0, 0.3, 0.3))

# ── робот-охотник (100% тревоги) ────────────────────────────

func _strongest_player() -> int:
	var actors: = _all_actor_nodes()
	var best: = -1
	var best_score: = -999.0
	for id in actors:
		var bugged: = Net.is_bug(id) if Net.active else GameState.my_bug
		if bugged:
			continue
		var s: = float(Net.my_level_of(id)) * 100.0
		if Net.scores.has(id):
			s += float(Net.scores[id]["score"])
		if s > best_score:
			best_score = s
			best = id
	return best

func _robot_tick(u: Dictionary, delta: float) -> void:
	var node: Node3D = u["node"]
	if not is_instance_valid(node):
		return
	var now: = Time.get_ticks_msec() / 1000.0
	if now < _frozen_until:
		return
	# крюк в полёте — робот стоит
	if u["hook_out"]:
		return
	var target: = _strongest_player()
	u["target"] = target
	var actors: = _all_actor_nodes()
	if target < 0 or not actors.has(target):
		return
	var tp: Vector3 = actors[target].global_position
	var dir: = tp - node.global_position
	dir.y = 0.0
	var dist: = dir.length()
	if dist > 1.6:
		# скорость робота = скорость игрока без спринта
		node.global_position += dir.normalized() * 6.0 * delta
		node.rotation.y = atan2(dir.x, dir.z)
	else:
		_hurt_player(target, 1, node.global_position)
	# случайный выстрел крюком
	u["hook_cd"] -= delta
	if u["hook_cd"] <= 0.0 and dist < 22.0 and dist > 3.0:
		u["hook_cd"] = rng.randf_range(6.0, 11.0)
		u["hook_out"] = true
		var hook_uid: = _spawn_unit("HOOK", node.global_position + Vector3(0, 1.6, 0))
		var h: Dictionary = sys_units[hook_uid]
		h["dir"] = dir.normalized()
		h["owner"] = _uid_of(u)
		h["ret"] = false
		var msg: = "⚠ РОБОТ ВЫПУСТИЛ КРЮК — уворачивайтесь!"
		if Net.active:
			Net.toast_all(msg, Color(1.0, 0.5, 0.2))
		else:
			hud.toast(msg, Color(1.0, 0.5, 0.2))

func _hook_tick(u: Dictionary, delta: float) -> void:
	var node: Node3D = u["node"]
	if not is_instance_valid(node):
		return
	var owner_uid: int = u.get("owner", -1)
	var robot: Dictionary = sys_units.get(owner_uid, {})
	var robot_pos: Vector3 = u["origin"]
	if not robot.is_empty() and is_instance_valid(robot["node"]):
		robot_pos = robot["node"].global_position + Vector3(0, 1.6, 0)
	if not u["ret"]:
		var d: Vector3 = u["dir"]
		node.global_position += d * 5.5 * delta # крюк летит медленно — можно среагировать
		node.rotation.y = atan2(d.x, d.z)
		# граница зала или дальность — крюк возвращается
		var p: = node.global_position
		if absf(p.x) > hall.x * 0.5 - 1.0 or absf(p.z) > hall.y * 0.5 - 1.0 \
			or p.distance_to(robot_pos) > 26.0:
			u["ret"] = true
	else:
		var back: = robot_pos - node.global_position
		if back.length() < 1.2:
			if not robot.is_empty():
				robot["hook_out"] = false
			_despawn_unit(_uid_of(u))
			return
		node.global_position += back.normalized() * 8.0 * delta
	# поймал? мгновенный баг
	var actors: = _all_actor_nodes()
	for id in actors:
		var bugged: = Net.is_bug(id) if Net.active else GameState.my_bug
		if bugged:
			continue
		if node.global_position.distance_to(actors[id].global_position + Vector3(0, 1.0, 0)) < 1.1:
			_hurt_player(id, 99, node.global_position)
			var msg: = "☠ КРЮК ПОЙМАЛ %s — мгновенный сбой!" % Net.player_name(id)
			if Net.active:
				Net.toast_all(msg, Color(1.0, 0.2, 0.25))
			else:
				hud.toast(msg, Color(1.0, 0.2, 0.25))
			u["ret"] = true
			return

# ── эффекты ловушек на пирах ────────────────────────────────

func _on_system_fx(target: int, kind: String, arg: float) -> void:
	var now: = Time.get_ticks_msec() / 1000.0
	var me: = target == Net.my_id()
	match kind:
		"cage":
			if me:
				player.locked_until = now + arg
				hud.toast("КЛЕТКА: %d секунд без движения!" % int(arg), Color(0.5, 0.75, 1.0))
			_spawn_cage_dome(target, arg, Color(0.5, 0.75, 1.0))
		"mark":
			if me:
				hud.toast("МЕТКА: система ведёт тебя %d секунд" % int(arg), Color(1.0, 0.85, 0.3))
		"reset":
			if me:
				GameState.reset_until = now + arg
				Net.sync_identity()
				hud.toast("СБРОС ДО НУЛЯ: скин и ветка отключены на %d секунд" % int(arg), Color(0.7, 0.7, 0.75))
				get_tree().create_timer(arg + 0.2).timeout.connect(func() -> void:
					if is_instance_valid(self):
						Net.sync_identity())
		"pull":
			if me:
				var dir: = _nearest_wall_dir(player.global_position)
				player.velocity = dir * 20.0 + Vector3.UP * 4.0
				player.shake(0.5)
				hud.toast("ПРИТЯЖЕНИЕ: тебя утянуло к стене!", Color(0.9, 0.5, 1.0))
		"reflash":
			if me:
				player.locked_until = now + 2.5
				player.slow_until = now + arg
				var lost: = GameState.steal_ability()
				var lost_name: = ""
				if lost != "":
					lost_name = " · украдено умение «%s»" % GameState.ABILITIES[lost]["name"]
				hud.toast("ПЕРЕПРОШИВКА: −3 HP, замедление %dс%s" % [int(arg), lost_name], Color(0.3, 1.0, 0.6))
			_spawn_cage_dome(target, 2.5, Color(0.3, 1.0, 0.6))

func _nearest_wall_dir(p: Vector3) -> Vector3:
	var hx: = hall.x * 0.5
	var hz: = hall.y * 0.5
	var dists: = {
		Vector3(-1, 0, 0): hx + p.x, Vector3(1, 0, 0): hx - p.x,
		Vector3(0, 0, -1): hz + p.z, Vector3(0, 0, 1): hz - p.z,
	}
	var best: Vector3 = Vector3(1, 0, 0)
	for d in dists:
		if dists[d] < dists[best]:
			best = d
	return best

func _spawn_cage_dome(target: int, dur: float, color: Color) -> void:
	## визуал купола с кодом вокруг жертвы
	var anchor: Node3D = player if target == Net.my_id() else avatars.get(target)
	if anchor == null or not is_instance_valid(anchor):
		return
	var dome: = MeshInstance3D.new()
	var sm: = SphereMesh.new()
	sm.radius = 1.5
	sm.height = 3.0
	dome.mesh = sm
	var sh: = ShaderMaterial.new()
	sh.shader = load("res://shaders/hologram.gdshader")
	sh.set_shader_parameter("col", Vector3(color.r, color.g, color.b))
	dome.material_override = sh
	dome.position.y = 1.0
	anchor.add_child(dome)
	get_tree().create_timer(dur).timeout.connect(func() -> void:
		if is_instance_valid(dome):
			dome.queue_free())

# ── куклы юнитов на клиентах ────────────────────────────────

func _on_enemy_spawned(id: int, type: String, pos: Vector3) -> void:
	if Net.is_server():
		return
	var node: = _build_unit_visual(type, pos)
	sys_units[id] = {"type": type, "node": node, "target": 0, "life": 0.0,
		"hook_cd": 0.0, "hook_out": false, "ret": false, "origin": pos}

func _on_enemies_tf(batch: Array) -> void:
	if Net.is_server():
		return
	for row in batch:
		var u: Dictionary = sys_units.get(int(row[0]), {})
		if not u.is_empty() and is_instance_valid(u["node"]):
			var node: Node3D = u["node"]
			node.global_position = node.global_position.lerp(Vector3(row[1], row[2], row[3]), 0.5)
			node.rotation.y = row[4]

func _on_enemy_gone(id: int) -> void:
	if Net.is_server():
		return
	var u: Dictionary = sys_units.get(id, {})
	if not u.is_empty():
		if is_instance_valid(u["node"]):
			u["node"].queue_free()
		var cable: MeshInstance3D = u.get("cable", null)
		if cable != null and is_instance_valid(cable):
			cable.queue_free()
	sys_units.erase(id)

func apply_enemy_effect(kind: String, arg: float, pos: Vector3) -> void:
	## активки против системы (только хост)
	var now: = Time.get_ticks_msec() / 1000.0
	match kind:
		"freeze":
			_frozen_until = now + arg
		"decoy":
			_decoy_until = now + arg
			_decoy_pos = pos

# ── портал, кулер, лут, задачи (как раньше) ─────────────────

func _build_portal_and_pad() -> void:
	portal = Node3D.new()
	portal.position = Vector3(-30.5, 0, 0)
	portal.rotation.y = deg_to_rad(90.0)
	add_child(portal)

	var ring: = MeshInstance3D.new()
	var tor: = TorusMesh.new()
	tor.inner_radius = 1.5
	tor.outer_radius = 1.75
	ring.mesh = tor
	portal_ring_mat = _neon_mat(Color(0.1, 0.5, 0.6), 1.0)
	ring.material_override = portal_ring_mat
	ring.rotation.x = deg_to_rad(90.0)
	ring.position.y = 1.9
	portal.add_child(ring)

	var lbl: = Label3D.new()
	lbl.text = "ЭКФИЛЬТРАЦИЯ"
	lbl.font_size = 44
	lbl.modulate = UIKit.TEAL
	lbl.outline_size = 8
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position.y = 4.1
	portal.add_child(lbl)

	portal_light = OmniLight3D.new()
	portal_light.light_color = Color(0.1, 0.8, 0.9)
	portal_light.light_energy = 1.4
	portal_light.omni_range = 8.0
	portal_light.position.y = 2.0
	portal.add_child(portal_light)

	var pad: = MeshInstance3D.new()
	var cyl: = CylinderMesh.new()
	cyl.top_radius = PAD_RADIUS
	cyl.bottom_radius = PAD_RADIUS
	cyl.height = 0.06
	pad.mesh = cyl
	pad_mat = StandardMaterial3D.new()
	pad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pad_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pad_mat.albedo_color = Color(0.1, 0.85, 0.75, 0.14)
	pad.material_override = pad_mat
	pad.position = PAD_POS + Vector3(0, 0.05, 0)
	add_child(pad)
	var pad_lbl: = Label3D.new()
	pad_lbl.text = "ЗОНА ВЫНОСА — неси лут сюда"
	pad_lbl.font_size = 30
	pad_lbl.modulate = UIKit.TEAL
	pad_lbl.outline_size = 8
	pad_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pad_lbl.position = PAD_POS + Vector3(0, 2.6, 0)
	add_child(pad_lbl)

func _build_cooler() -> void:
	cooler = Node3D.new()
	cooler.position = cooler_pos
	add_child(cooler)
	_box(Vector3(1.4, 1.8, 1.0), _dark_mat(), Vector3(0, 0.9, 0), cooler)
	_collider(Vector3(1.4, 1.8, 1.0), cooler_pos + Vector3(0, 0.9, 0))
	var fan: = MeshInstance3D.new()
	var tm: = TorusMesh.new()
	tm.inner_radius = 0.28
	tm.outer_radius = 0.42
	fan.mesh = tm
	fan.material_override = _neon_mat(Color(0.3, 0.8, 1.0), 2.0)
	fan.rotation.x = deg_to_rad(90.0)
	fan.position = Vector3(0, 1.2, -0.55)
	cooler.add_child(fan)
	cooler_label = Label3D.new()
	cooler_label.font_size = 30
	cooler_label.modulate = Color(0.3, 0.8, 1.0)
	cooler_label.outline_size = 8
	cooler_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	cooler_label.position.y = 2.5
	cooler.add_child(cooler_label)
	_update_cooler_label()

func _update_cooler_label() -> void:
	if cooler_charges > 0:
		cooler_label.text = "КУЛЕР: сброс тревоги −15\n[E держать] · зарядов: %d" % cooler_charges
	else:
		cooler_label.text = "КУЛЕР: ПЕРЕГРЕТ"
		cooler_label.modulate = Color(0.5, 0.4, 0.4)

func _spawn_player() -> void:
	player = VirusPlayer.new()
	player.position = Vector3(-27, 0.2, 3)
	add_child(player)

func _spawn_task_stations() -> void:
	var cfg_tasks: Array = GameState.node_config.get("tasks", [])
	var centers: Array = []
	for i in cfg_tasks.size():
		var center: = Vector3(12, 0, 0)
		for attempt in 24:
			center = Vector3(rng.randf_range(-4.0, hall.x * 0.5 - 9.0), 0.0, rng.randf_range(-hall.y * 0.5 + 8.0, hall.y * 0.5 - 10.0))
			var ok: = _spot_free(center, 5.0)
			for prev in centers:
				if Vector2(center.x - prev.x, center.z - prev.z).length() < 14.0:
					ok = false
			if ok:
				break
		centers.append(center)
		var cfg: Dictionary = cfg_tasks[i]
		var color: = Color("ffb454")
		var rt: = {"type": cfg["type"], "title": cfg["title"], "done": cfg.get("done", false),
			"center": center, "stations": [], "p1": 0.0, "p2": 0.0, "step": 0, "timer": 0.0,
			"holders": {}, "contributors": {}, "wired": 0}
		match cfg["type"]:
			"sync":
				var off: = Vector3(rng.randf_range(-1.0, 1.0), 0, rng.randf_range(-1.0, 1.0)).normalized() * 6.5
				for sub in 2:
					var st: = TaskStation.create("console", color, "%s\nрычаг %s" % [cfg["title"], ["А", "Б"][sub]])
					st.position = center + (off if sub == 0 else -off)
					st.rotation.y = rng.randf_range(0.0, TAU)
					add_child(st)
					rt["stations"].append(st)
			"zone":
				var st: = TaskStation.create("zone", color, cfg["title"])
				st.position = center
				add_child(st)
				rt["stations"].append(st)
			"relay":
				var dir: = Vector3(rng.randf_range(-1.0, 1.0), 0, rng.randf_range(-1.0, 1.0)).normalized()
				for sub in 3:
					var st: = TaskStation.create("relay", color, "%s\nопора %d" % [cfg["title"], sub + 1])
					st.position = center + dir * (float(sub) - 1.0) * 8.0 + Vector3(rng.randf_range(-2, 2), 0, rng.randf_range(-2, 2))
					add_child(st)
					rt["stations"].append(st)
		if rt["done"]:
			for st in rt["stations"]:
				st.set_done()
		tasks_rt.append(rt)

func _build_particles() -> void:
	var parts: = GPUParticles3D.new()
	parts.amount = 220
	parts.lifetime = 9.0
	parts.preprocess = 5.0
	var pm: = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(hall.x * 0.5, 3.5, hall.y * 0.5)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.15
	pm.initial_velocity_max = 0.55
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 3.0
	parts.process_material = pm
	var quad: = QuadMesh.new()
	quad.size = Vector2(0.055, 0.055)
	var qm: = StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.albedo_color = Color(0.9, 0.25, 0.3, 0.5) if is_boss else Color(0.25, 0.8, 0.95, 0.5)
	quad.material = qm
	parts.draw_pass_1 = quad
	parts.position.y = 3.0
	add_child(parts)

# ── UI ──────────────────────────────────────────────────────

func _build_ui() -> void:
	hud_layer = CanvasLayer.new()
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
	Net.xray_pulse.connect(_apply_xray)
	Net.cooler_used.connect(_on_cooler_used)
	Net.task_state.connect(_on_task_state)
	Net.task_done.connect(_on_task_done)
	Net.system_fx.connect(_on_system_fx)
	Net.enemy_gone.connect(_on_enemy_gone)
	_update_objective()

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
	v.add_child(UIKit.label("ПАУЗА // соединение удерживается", 22, UIKit.CYAN))
	var resume: = UIKit.button("  ПРОДОЛЖИТЬ  ", 19, UIKit.TEAL)
	resume.pressed.connect(_toggle_pause)
	v.add_child(resume)
	if Net.active:
		var quit: = UIKit.button("  ПОКИНУТЬ РЕЙД (в меню)  ", 19, UIKit.MAGENTA)
		quit.pressed.connect(func() -> void:
			Net.leave()
			get_tree().paused = false
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
		v.add_child(quit)
	else:
		var menu: = UIKit.button("  ОБОРВАТЬ СОЕДИНЕНИЕ (в Грид)  ", 19, UIKit.MAGENTA)
		menu.pressed.connect(func() -> void:
			GameState.grid_heat = minf(GameState.grid_heat + 12.0, 100.0)
			get_tree().paused = false
			get_tree().change_scene_to_file("res://scenes/grid_world.tscn"))
		v.add_child(menu)
	return root

func _tasks_done_count() -> int:
	var c: = 0
	for rt in tasks_rt:
		if rt["done"]:
			c += 1
	return c

func _update_objective() -> void:
	if GameState.evac_open:
		hud.set_objective("ЭВАКУАЦИЯ: все в круг у портала!")
	else:
		hud.set_objective("%s (%s) · вынести ◈ на 100%% · задачи %d/%d" % [
			GameState.node_config["name"], GameState.node_config["tier_short"],
			_tasks_done_count(), tasks_rt.size()])

# ── кооп ────────────────────────────────────────────────────

func _setup_coop() -> void:
	for id in Net.players:
		if id != Net.my_id():
			_spawn_avatar(id)
	Net.remote_pos.connect(_on_remote_pos)
	Net.peer_left.connect(_on_peer_left)
	Net.player_hp.connect(_on_player_hp)
	Net.player_ragdoll.connect(_on_player_ragdoll)
	Net.player_morph.connect(_on_player_morph)
	Net.loot_table.connect(_on_loot_table)
	Net.loot_added.connect(_on_loot_added)
	Net.loot_state.connect(_on_loot_state)
	Net.loot_tf.connect(_on_loot_tf)
	Net.loot_damage.connect(_on_loot_damage)
	Net.loot_deposited.connect(_on_loot_deposited)
	Net.enemy_spawned.connect(_on_enemy_spawned)
	Net.enemies_tf.connect(_on_enemies_tf)
	Net.hack_finished.connect(_on_net_finished)
	Net.net_toast.connect(_on_net_toast)
	Net.scores_changed.connect(_refresh_scores)
	if not Net.is_server():
		Net.srv_hello_hp.rpc_id(1, GameState.my_max_hp)
	_refresh_scores()

func _spawn_avatar(id: int) -> void:
	var av: = RemoteAvatar.new()
	av.setup(id, Net.my_class_of(id), Net.player_name(id))
	av.position = Vector3(-27, 0.2, randf_range(-4.0, 4.0))
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
		hud.toast("%s отключился от узла" % Net.player_name(id), UIKit.DIM)
		avatars[id].queue_free()
		avatars.erase(id)
	if Net.is_server():
		_host_hp.erase(id)
		_marked.erase(id)
		for it in loots.values():
			if id in it.carriers:
				_release_item(it, id, false, Vector3.ZERO)
		for rt in tasks_rt:
			for sub in rt["holders"].keys():
				rt["holders"][sub].erase(id)

func _on_net_toast(text: String, color: Color) -> void:
	hud.toast(text, color)

func _actor_for(id: int) -> Node3D:
	if id == Net.my_id():
		return player
	return avatars.get(id)

func _refresh_scores() -> void:
	var rows: Array = []
	for id in Net.scores:
		rows.append({"name": Net.player_name(id), "color": Net.player_color(id),
			"score": Net.scores[id]["score"]})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	hud.set_scores(rows)

func _all_actor_nodes() -> Dictionary:
	var out: = {Net.my_id(): player}
	for id in avatars:
		out[id] = avatars[id]
	return out

# ── хост: лут ───────────────────────────────────────────────

func _spawn_loot_table() -> void:
	var cfg: Dictionary = GameState.node_config
	var items: Array = []
	var files: int = cfg.get("files", 7)
	var crates: int = cfg.get("crates", 2)
	# часть лёгких файлов — на антресоли (достижима по пандусам и лифту)
	var spots: Array = _high_spots.duplicate()
	spots.shuffle()
	for i in files:
		var pos: Vector3
		if i < mini(3, spots.size()):
			pos = spots[i]
		else:
			pos = Vector3(randf_range(-24, hall.x * 0.5 - 5.0), 0.7, randf_range(-hall.y * 0.5 + 4.0, hall.y * 0.5 - 4.0))
			if pos.distance_to(PAD_POS) < 8.0:
				pos.x = absf(pos.x)
		items.append(_make_loot_data("file", pos))
	var cspots: = _crate_spots.duplicate()
	cspots.shuffle()
	for i in crates:
		items.append(_make_loot_data("crate", cspots[i % cspots.size()] + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))))
	for data in items:
		_spawn_loot_local(data, false)
	if Net.active:
		Net.send_loot_table(items)

func _make_loot_data(kind: String, pos: Vector3) -> Dictionary:
	var k: Dictionary = GameState.LOOT_KINDS[kind]
	_next_lid += 1
	return {
		"id": _next_lid, "kind": kind, "name": GameState.loot_name(kind),
		"value": float(randi_range(k["value"][0], k["value"][1])),
		"weight": k["weight"], "pos": pos,
	}

func _spawn_loot_local(data: Dictionary, p_puppet: bool) -> LootItem:
	var it: = LootItem.create(data, p_puppet)
	add_child(it)
	loots[it.item_id] = it
	if not p_puppet:
		it.hit_taken.connect(_on_loot_hit)
		it.smashed.connect(_on_loot_smashed)
	return it

func server_grab(item_id: int, sender: int) -> void:
	var it: LootItem = loots.get(item_id)
	if it == null or not is_instance_valid(it) or it.deposited:
		return
	if (Net.active and Net.is_bug(sender)) or (not Net.active and GameState.my_bug):
		return
	if sender in it.carriers:
		return
	for other in loots.values():
		if sender in other.carriers:
			return
	var new_carriers: Array = it.carriers.duplicate()
	new_carriers.append(sender)
	it.last_holder = sender
	it.set_carried(new_carriers)
	_sync_loot_state(it)
	if _carry_strength(new_carriers) < it.weight:
		Net.toast_all("%s тащит «%s» в одиночку — медленно! Второй ускорит" % [Net.player_name(sender), it.loot_name], UIKit.AMBER) if Net.active else hud.toast("тяжело: тащишь один — медленно. Второй ускорит", UIKit.AMBER)

func server_release(item_id: int, sender: int, throw: bool, dir: Vector3) -> void:
	var it: LootItem = loots.get(item_id)
	if it == null or not is_instance_valid(it):
		return
	if not sender in it.carriers:
		return
	_release_item(it, sender, throw, dir)

func _release_item(it: LootItem, sender: int, throw: bool, dir: Vector3) -> void:
	var new_carriers: Array = it.carriers.duplicate()
	new_carriers.erase(sender)
	it.set_carried(new_carriers)
	if new_carriers.is_empty():
		var vel: = Vector3(0, 1.0, 0)
		if throw:
			vel = dir.normalized() * 9.5 + Vector3.UP * 3.5
			server_noise(1.5, it.global_position, sender)
		it.drop_with(vel)
	_sync_loot_state(it)

func _carry_strength(carriers: Array) -> int:
	var s: = 0
	for id in carriers:
		if id is int and id > 0:
			s += 2 if Net.my_class_of(id) == "ransomware" else 1
	return s

func _sync_loot_state(it: LootItem) -> void:
	if Net.active:
		Net.send_loot_state(it.item_id, it.carriers)
	else:
		_apply_my_carry()

func _on_loot_hit(it: LootItem) -> void:
	Sfx.play("trap", -8.0, 1.4)
	if Net.active:
		Net.send_loot_damage(it.item_id, it.value, it.broken)

func _on_loot_smashed(it: LootItem) -> void:
	GameState.apply_alarm(6.0, "crash", "worm")
	server_noise(3.0, it.global_position, it.last_holder)
	if it.last_holder > 0:
		Net.score_event(it.last_holder, "broken")
	if it.last_holder == Net.my_id():
		GameState.stats["broken"] += 1
	var msg: = "💥 «%s» РАЗБИТ! (%s, ну ты чего)" % [it.loot_name, Net.player_name(it.last_holder)]
	if Net.active:
		Net.send_loot_damage(it.item_id, it.value, true)
		Net.toast_all(msg, Color(1.0, 0.45, 0.3))
	else:
		hud.toast(msg, Color(1.0, 0.45, 0.3))

func _deposit(it: LootItem, carriers: Array) -> void:
	var val: = it.value
	GameState.deposit_value(val)
	var clean: Array = []
	for cid in carriers:
		if cid is int and cid > 0:
			Net.score_event(cid, "deposit", val)
			clean.append(cid)
	if clean.is_empty() and it.last_holder > 0:
		clean.append(it.last_holder)
		Net.score_event(it.last_holder, "deposit", val)
	_dlog("депозит «%s» ◈%d → добыча %d%%" % [it.loot_name, int(val), roundi(GameState.access)])
	if Net.active:
		Net.send_loot_deposit(it.item_id, clean, val)
	else:
		_on_loot_deposited(it.item_id, clean, val)
	if not GameState.evac_open and GameState.access >= 100.0:
		_open_evac(false)

func _open_evac(forced: bool) -> void:
	GameState.evac_open = true
	GameState.wipe_forced = forced
	GameState.evac_left = GameState.WIPE_EVAC_TIME if forced else GameState.EVAC_TIME
	if not forced:
		GameState.alarm = maxf(GameState.alarm, GameState.ALARM_PURGE + 3.0)
	var msg: = "⚠ СТИРАНИЕ УЗЛА: %dс — тащите что можете и В КРУГ!" % int(GameState.evac_left) if forced \
		else "КВОТА ВЗЯТА! Эвакуация %dс — добейте бонусный лут и в круг!" % int(GameState.evac_left)
	if Net.active:
		Net.toast_all(msg, Color(1.0, 0.3, 0.35) if forced else UIKit.TEAL)
	else:
		hud.toast(msg, Color(1.0, 0.3, 0.35) if forced else UIKit.TEAL)

func server_noise(amount: float, _pos: Vector3, sender: int) -> void:
	GameState.apply_alarm(amount, "noise", Net.my_class_of(sender) if Net.active else GameState.display_class())

func server_revive(target_id: int, medic_id: int) -> void:
	if phase == "done":
		return
	var cur: int = _host_hp.get(target_id, 0)
	if Net.active and Net.is_bug(target_id):
		_host_hp[target_id] = 1
		Net.set_hp(target_id, 1, false)
		if medic_id != target_id:
			Net.score_event(medic_id, "revive")
			Net.toast_all("⚡ %s дефибрильнул %s — живём!" % [Net.player_name(medic_id), Net.player_name(target_id)], Color("4a90ff"))
		else:
			GameState.apply_alarm(5.0, "revive", "worm")
			Net.toast_all("%s перезапустился у портала (система заметила)" % Net.player_name(target_id), UIKit.TEAL)
	elif not Net.active and GameState.my_bug:
		_host_hp[1] = 1
		GameState.revive_me()
		GameState.apply_alarm(5.0, "revive", "worm")
		player.set_bug(false)
		hud.toast("ПЕРЕЗАПУСК У ПОРТАЛА: 1 HP. Аккуратнее!", UIKit.TEAL)
	elif medic_id == target_id and cur > 0:
		var maxed: = 3 + 2
		_host_hp[target_id] = mini(cur + 1, maxed)
		if Net.active:
			Net.set_hp(target_id, _host_hp[target_id], false)
		else:
			GameState.my_hp = _host_hp[target_id]
			GameState.hp_changed.emit(GameState.my_hp)

func server_hello_hp(id: int, maxhp: int) -> void:
	_host_hp[id] = maxhp
	Net.set_hp(id, maxhp, false)

func server_cooler(sender: int) -> void:
	if cooler_charges <= 0:
		return
	cooler_charges -= 1
	GameState.apply_alarm(-15.0, "cooler", Net.my_class_of(sender) if Net.active else GameState.display_class())
	if Net.active:
		Net.send_cooler(cooler_charges)
		Net.toast_all("КУЛЕР: %s сбросил тревогу −15" % Net.player_name(sender), Color(0.3, 0.8, 1.0))
	else:
		_on_cooler_used(cooler_charges)
		hud.toast("КУЛЕР: тревога −15. Система зевнула", Color(0.3, 0.8, 1.0))

func _on_cooler_used(left: int) -> void:
	cooler_charges = left
	_update_cooler_label()
	Sfx.play("ability", -4.0, 0.7)

# ── хост: полевые задачи ────────────────────────────────────

func server_task_hold(idx: int, sub: int, on: bool, sender: int) -> void:
	if idx < 0 or idx >= tasks_rt.size():
		return
	var rt: Dictionary = tasks_rt[idx]
	if rt["done"] or rt["type"] != "sync":
		return
	if not rt["holders"].has(sub):
		rt["holders"][sub] = {}
	if on:
		var actors: = _all_actor_nodes()
		if actors.has(sender) and sub < rt["stations"].size():
			var st: TaskStation = rt["stations"][sub]
			if actors[sender].global_position.distance_to(st.global_position) < 3.4:
				rt["holders"][sub][sender] = true
				rt["contributors"][sender] = true
	else:
		rt["holders"][sub].erase(sender)

func _task_tick(delta: float) -> void:
	var actors: = _all_actor_nodes()
	for i in tasks_rt.size():
		var rt: Dictionary = tasks_rt[i]
		if rt["done"]:
			continue
		match rt["type"]:
			"sync":
				for sub in 2:
					var held: = false
					var holders: Dictionary = rt["holders"].get(sub, {})
					for id in holders.keys():
						if not actors.has(id):
							holders.erase(id)
							continue
						var st: TaskStation = rt["stations"][sub]
						if actors[id].global_position.distance_to(st.global_position) < 3.6:
							held = true
						else:
							holders.erase(id)
					var key: = "p1" if sub == 0 else "p2"
					if held:
						rt[key] = minf(rt[key] + delta / SYNC_CHARGE_TIME, 1.0)
					else:
						rt[key] = maxf(rt[key] - SYNC_DECAY * delta, 0.0)
					rt["stations"][sub].set_active(held)
				if rt["p1"] >= 1.0 and rt["p2"] >= 1.0:
					_complete_task(i)
			"zone":
				var inside: Array = []
				for id in actors:
					var bugged: = Net.is_bug(id) if Net.active else GameState.my_bug
					if bugged:
						continue
					if actors[id].global_position.distance_to(rt["center"]) < ZONE_RADIUS:
						inside.append(id)
						rt["contributors"][id] = true
				if inside.size() > 0:
					rt["p1"] = minf(rt["p1"] + delta * float(inside.size()) / ZONE_TIME, 1.0)
					GameState.apply_alarm(0.35 * delta, "capture", "worm")
				else:
					rt["p1"] = maxf(rt["p1"] - 0.05 * delta, 0.0)
				rt["p2"] = float(inside.size())
				if rt["p1"] >= 1.0:
					_complete_task(i)
			"relay":
				if rt["step"] > 0:
					rt["timer"] -= delta
					if rt["timer"] <= 0.0:
						rt["step"] = 0
						if Net.active:
							Net.toast_all("⚡ кабель остыл — тяните заново!", UIKit.AMBER)
						else:
							hud.toast("⚡ кабель остыл — тяните заново!", UIKit.AMBER)
				var next: int = rt["step"]
				if next < rt["stations"].size():
					var st: TaskStation = rt["stations"][next]
					for id in actors:
						if actors[id].global_position.distance_to(st.global_position) < 2.4:
							rt["step"] += 1
							rt["timer"] = RELAY_WINDOW
							rt["contributors"][id] = true
							Sfx.play("chain", -6.0, 1.0 + 0.2 * float(next))
							break
				rt["p1"] = float(rt["step"]) / float(rt["stations"].size())
				if rt["step"] >= rt["stations"].size():
					_complete_task(i)

func _complete_task(idx: int) -> void:
	var rt: Dictionary = tasks_rt[idx]
	rt["done"] = true
	var cfg_tasks: Array = GameState.node_config.get("tasks", [])
	if idx < cfg_tasks.size():
		cfg_tasks[idx]["done"] = true
	GameState.apply_alarm(4.0, "task", "worm")
	var participants: Array = rt["contributors"].keys()
	for id in participants:
		if id is int and id > 0:
			Net.score_event(id, "task")
	var pos: Vector3 = rt["center"] + Vector3(randf_range(-1.5, 1.5), 1.2, randf_range(-1.5, 1.5))
	var data: = _make_loot_data("epic", pos)
	_spawn_loot_local(data, false)
	var msg: = "💰 %s выполнена — выпал «%s»!" % [rt["title"], data["name"]]
	if Net.active:
		Net.send_loot_add(data)
		Net.send_task_done(idx, participants)
		Net.toast_all(msg, Color("ffd166"))
	else:
		_on_task_done(idx, participants)
		hud.toast(msg, Color("ffd166"))
	_broadcast_task_state()

func _broadcast_task_state() -> void:
	var batch: Array = []
	for i in tasks_rt.size():
		var rt: Dictionary = tasks_rt[i]
		batch.append([i, 1.0 if rt["done"] else 0.0, rt["p1"], rt["p2"], rt["step"], rt["timer"]])
	if Net.active:
		Net.send_task_state(batch)
	else:
		_on_task_state(batch)

func _on_task_state(batch: Array) -> void:
	for row in batch:
		var i: = int(row[0])
		if i < 0 or i >= tasks_rt.size():
			continue
		var rt: Dictionary = tasks_rt[i]
		if not Net.is_server():
			rt["done"] = row[1] > 0.5
			rt["p1"] = row[2]
			rt["p2"] = row[3]
			rt["step"] = int(row[4])
			rt["timer"] = row[5]
		if rt["done"]:
			continue
		match rt["type"]:
			"sync":
				rt["stations"][0].set_progress(rt["p1"])
				rt["stations"][1].set_progress(rt["p2"])
				rt["stations"][0].set_caption("%s\nрычаг А · %d%%" % [rt["title"], int(rt["p1"] * 100.0)])
				rt["stations"][1].set_caption("%s\nрычаг Б · %d%%" % [rt["title"], int(rt["p2"] * 100.0)])
			"zone":
				rt["stations"][0].set_progress(rt["p1"])
				rt["stations"][0].set_active(rt["p2"] > 0.0)
				rt["stations"][0].set_caption("%s\nмонтаж %d%% · в зоне: %d" % [rt["title"], int(rt["p1"] * 100.0), int(rt["p2"])])
			"relay":
				# протянутые сегменты кабеля рисуем между опорами
				while rt["wired"] < rt["step"] and rt["wired"] < rt["stations"].size() - 0:
					var s: int = rt["wired"]
					if s > 0:
						var a: Vector3 = rt["stations"][s - 1].global_position + Vector3(0, 1.9, 0)
						var b: Vector3 = rt["stations"][s].global_position + Vector3(0, 1.9, 0)
						var seg: = _box(Vector3(0.09, 0.09, a.distance_to(b)), _neon_mat(Color(0.95, 0.6, 0.2), 1.6), (a + b) * 0.5)
						seg.look_at_from_position(seg.position, b, Vector3.UP)
					rt["wired"] += 1
				if rt["step"] == 0:
					rt["wired"] = 0
				for s in rt["stations"].size():
					var st: TaskStation = rt["stations"][s]
					st.set_progress(1.0 if s < rt["step"] else 0.0)
					st.set_active(s == rt["step"])
					if s == rt["step"]:
						var extra: = ""
						if rt["step"] > 0:
							extra = " · %.0fс" % maxf(rt["timer"], 0.0)
						st.set_caption("%s\n▶ опора %d%s" % [rt["title"], s + 1, extra])
					elif s < rt["step"]:
						st.set_caption("%s\nопора %d ✓" % [rt["title"], s + 1])
					else:
						st.set_caption("%s\nопора %d" % [rt["title"], s + 1])

func _on_task_done(idx: int, participants: Array) -> void:
	if idx < 0 or idx >= tasks_rt.size():
		return
	var rt: Dictionary = tasks_rt[idx]
	rt["done"] = true
	for st in rt["stations"]:
		st.set_done()
	if Net.my_id() in participants:
		GameState.stats["tasks"] += 1
	Sfx.play("layer_done")
	_update_objective()

# ── клиент: приём лута ──────────────────────────────────────

func _on_loot_table(items: Array) -> void:
	if Net.is_server():
		return
	for data in items:
		_spawn_loot_local(data, true)

func _on_loot_added(item: Dictionary) -> void:
	if Net.is_server():
		return
	_spawn_loot_local(item, true)

func _on_loot_state(id: int, carriers: Array) -> void:
	var it: LootItem = loots.get(id)
	if it == null or not is_instance_valid(it):
		return
	it.carriers = carriers
	if not Net.is_server():
		it.set_carried(carriers)
	_apply_my_carry()

func _on_loot_tf(batch: Array) -> void:
	if Net.is_server():
		return
	for row in batch:
		var it: LootItem = loots.get(int(row[0]))
		if it != null and is_instance_valid(it):
			it.net_update(Vector3(row[1], row[2], row[3]), row[4])

func _on_loot_damage(id: int, value: float, broken: bool) -> void:
	var it: LootItem = loots.get(id)
	if it == null or not is_instance_valid(it):
		return
	if not Net.is_server():
		it.apply_damage_fx(value, broken)
	if broken and it.last_holder == Net.my_id():
		GameState.stats["broken"] += 1

func _on_loot_deposited(id: int, carriers: Array, value: float) -> void:
	var it: LootItem = loots.get(id)
	var nm: = "лут"
	if it != null and is_instance_valid(it):
		nm = it.loot_name
		loots.erase(id)
		it.deposit_fly(portal.global_position + Vector3(0, 1.9, 0))
	if Net.my_id() in carriers:
		GameState.stats["delivered"] += int(value)
		GameState.stats["deposits"] += 1
	var by_name: = Net.player_name(carriers[0]) if not carriers.is_empty() else "команда"
	hud.toast("◈ +%d — %s внёс «%s»" % [int(value), by_name, nm], UIKit.TEAL)
	Sfx.play("pickup", 0.0, 0.9)
	_apply_my_carry()

func _on_player_hp(id: int, hp_val: int, bug: bool) -> void:
	if id == Net.my_id():
		var was_bug: = GameState.my_bug
		GameState.my_hp = hp_val
		GameState.my_bug = bug
		GameState.hp_changed.emit(hp_val)
		player.set_bug(bug)
		if bug and not was_bug:
			GameState.stats["caught"] += 1
			hud.toast("КРИТИЧЕСКИЙ СБОЙ: ты теперь БАГ. Ползи к порталу или жди дефибриллятор!", Color(1.0, 0.3, 0.3))
		elif was_bug and not bug:
			hud.toast("ТЫ СНОВА В ДЕЛЕ! 1 HP — без героизма", UIKit.TEAL)
	elif avatars.has(id):
		if bug and not avatars[id].is_bug:
			hud.toast("%s разобран — он теперь БАГ! Пусть ползёт к порталу" % Net.player_name(id), Color(1.0, 0.45, 0.3))
		avatars[id].set_bug(bug)

func _on_player_ragdoll(id: int, from: Vector3) -> void:
	if id == Net.my_id():
		player.ragdoll_from(from)
		if not GameState.my_bug:
			GameState.stats["caught"] += 1
		hud.toast("СИСТЕМА УДАРИЛА! HP −1", Color(1.0, 0.3, 0.3))
		Sfx.play("trap", 0.0, 0.8)
	else:
		Sfx.play("trap", -10.0, 0.9)

func _on_player_morph(id: int, on: bool) -> void:
	if id != Net.my_id() and avatars.has(id):
		avatars[id].set_morph(on)

func _on_net_finished(victory: bool, reason: String) -> void:
	_do_local_finish(victory, reason)

# ── цикл ────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if phase == "done":
		return
	ability_cd = maxf(ability_cd - delta, 0.0)

	_apply_my_carry()
	_phase_fx_tick(delta)
	_cams_tick(delta)
	_units_visual_tick(delta)
	_screen_t -= delta
	if _screen_t <= 0.0:
		_screen_t = 0.25
		_refresh_system_screen()

	if Net.is_server():
		_host_tick(delta)

	if GameState.demo_mode:
		_demo_tick(delta)
	_handle_interactions(delta)
	_update_objective()

func _host_tick(delta: float) -> void:
	var creep: float = GameState.node_config.get("creep", 0.3)
	if GameState.evac_open:
		creep *= 1.6
	GameState.apply_alarm(creep * delta, "time", "worm")

	_system_tick(delta)
	_task_tick(delta)
	_task_sync -= delta
	if _task_sync <= 0.0:
		_task_sync = 0.15
		_broadcast_task_state()

	var actors: = _all_actor_nodes()
	for it in loots.values():
		if not is_instance_valid(it) or it.deposited:
			continue
		if not it.carriers.is_empty():
			# груз следует за носильщиками даже в одиночку (просто медленно идут)
			var mid: = Vector3.ZERO
			var n: = 0
			for cid in it.carriers:
				if actors.has(cid):
					mid += actors[cid].global_position
					n += 1
			if n > 0:
				mid /= float(n)
				it.global_position = it.global_position.lerp(mid + Vector3.UP * 2.35, minf(14.0 * delta, 1.0))
				if it.global_position.distance_to(PAD_POS) < PAD_RADIUS + 0.6:
					_deposit(it, it.carriers.duplicate())
		elif it.is_free() and it.global_position.distance_to(PAD_POS) < PAD_RADIUS and it.global_position.y < 2.0:
			_deposit(it, [it.last_holder])

	for id in actors:
		var bugged: = Net.is_bug(id) if Net.active else GameState.my_bug
		if bugged and actors[id].global_position.distance_to(PAD_POS) < PAD_RADIUS:
			_revive_t[id] = _revive_t.get(id, 0.0) + delta
			if _revive_t[id] >= REVIVE_TIME:
				_revive_t[id] = 0.0
				server_revive(id, id)
		else:
			_revive_t.erase(id)

	if GameState.evac_open:
		GameState.evac_left -= delta
		var all_in: = true
		var anyone: = false
		for id in actors:
			var bugged: = Net.is_bug(id) if Net.active else GameState.my_bug
			if bugged:
				continue
			anyone = true
			if actors[id].global_position.distance_to(PAD_POS) > PAD_RADIUS:
				all_in = false
		if GameState.evac_left <= 0.0:
			_finish(GameState.access >= 100.0,
				"Портал закрылся. Вынесено %d%% квоты" % roundi(GameState.access))
			return
		if anyone and all_in and GameState.access >= 100.0 and GameState.evac_left < GameState.EVAC_TIME - 3.0:
			_finish(true, "Чистый уход всей стаей — система в ярости")
			return
	elif GameState.alarm >= 99.9:
		_open_evac(true)

	if Net.active:
		_loot_sync -= delta
		if _loot_sync <= 0.0:
			_loot_sync = 0.1
			var batch: Array = []
			for it in loots.values():
				if is_instance_valid(it) and not it.deposited:
					batch.append([it.item_id, it.global_position.x, it.global_position.y, it.global_position.z, it.rotation.y])
			if not batch.is_empty():
				Net.send_loot_tf(batch)
		_unit_sync -= delta
		if _unit_sync <= 0.0:
			_unit_sync = 0.08
			var ubatch: Array = []
			for uid in sys_units:
				var u: Dictionary = sys_units[uid]
				if is_instance_valid(u["node"]):
					var p: Vector3 = u["node"].global_position
					ubatch.append([uid, p.x, p.y, p.z, u["node"].rotation.y, 0.0])
			if not ubatch.is_empty():
				Net.send_enemies(ubatch)

func _phase_fx_tick(_delta: float) -> void:
	var ph: = GameState.alarm_phase()
	var t: = Time.get_ticks_msec() / 1000.0
	match ph:
		0:
			env.volumetric_fog_albedo = _fog_base
		1:
			env.volumetric_fog_albedo = _fog_base.lerp(Color(0.85, 0.65, 0.3), 0.45)
		2:
			env.volumetric_fog_albedo = _fog_base.lerp(Color(0.85, 0.3, 0.3), 0.65)
		3:
			# 100%: всё мигает красным
			env.volumetric_fog_albedo = Color(0.8, 0.2, 0.25).lerp(Color(0.4, 0.05, 0.1), 0.5 + 0.5 * sin(t * 5.0))
			env.ambient_light_color = Color(0.16, 0.06, 0.08)
	if ph != _my_phase_seen:
		if ph > _my_phase_seen:
			match ph:
				1:
					hud.toast("СИСТЕМА: СКАНИРОВАНИЕ — камеры активированы!", UIKit.AMBER)
					Sfx.play("alarm", -6.0)
				2:
					hud.toast("СИСТЕМА: ЗАЧИСТКА — ловушки летят чаще!", Color(1.0, 0.45, 0.3))
					Sfx.play("hunter")
					player.shake(0.35)
				3:
					hud.toast("СИСТЕМА: ВТОРЖЕНИЕ ПОДТВЕРЖДЕНО — все видны, робот в пути!", Color(1.0, 0.15, 0.25))
					Sfx.play("quarantine")
					player.shake(0.6)
		_my_phase_seen = ph
	if GameState.evac_open:
		pad_mat.albedo_color = Color(0.1, 0.9, 0.75, 0.2 + 0.12 * sin(t * 6.0))
		portal_ring_mat.emission = Color(0.16, 0.95, 0.75)
		portal_ring_mat.emission_energy_multiplier = 2.5 + sin(t * 6.0)
		portal_light.light_energy = 3.0 + sin(t * 6.0)

# ── переноска ───────────────────────────────────────────────

func my_carried_item() -> LootItem:
	for it in loots.values():
		if is_instance_valid(it) and Net.my_id() in it.carriers:
			return it
	return null

func _apply_my_carry() -> void:
	var it: = my_carried_item()
	if it == null:
		player.carrying = false
		player.carry_factor = 1.0
		return
	player.carrying = true
	var f: = 0.78
	if _carry_strength(it.carriers) < it.weight:
		f = 0.38 # тащишь тяжесть в одиночку: ползёшь, но ползёшь
	elif it.weight >= 2:
		f = 0.6 if GameState.has_passive("ransomware") and it.carriers.size() == 1 else 0.66
	if GameState.has_passive("worm"):
		f += 0.08
	player.carry_factor = f

# ── взаимодействия ──────────────────────────────────────────

func _nearest_free_loot(radius: float) -> LootItem:
	var best: LootItem = null
	var best_d: = radius
	for it in loots.values():
		if not is_instance_valid(it) or it.deposited:
			continue
		if not it.carriers.is_empty():
			if _carry_strength(it.carriers) >= it.weight or Net.my_id() in it.carriers:
				continue
		var d: float = player.global_position.distance_to(it.global_position)
		if d < best_d:
			best_d = d
			best = it
	return best

func _nearest_sync_console() -> Array:
	for i in tasks_rt.size():
		var rt: Dictionary = tasks_rt[i]
		if rt["done"] or rt["type"] != "sync":
			continue
		for sub in 2:
			var st: TaskStation = rt["stations"][sub]
			if player.global_position.distance_to(st.global_position) < 3.0:
				return [i, sub]
	return [-1, -1]

func _nearest_wire() -> Dictionary:
	for w in _wires:
		for pair in [[w["a"], w["b"]], [w["b"], w["a"]]]:
			if player.global_position.distance_to(pair[0]) < 2.2:
				return {"from": pair[0], "to": pair[1]}
	return {}

func _nearest_task_hint() -> String:
	for rt in tasks_rt:
		if rt["done"]:
			continue
		match rt["type"]:
			"zone":
				var d: = player.global_position.distance_to(rt["center"])
				if d < ZONE_RADIUS:
					return "МОНТАЖ ИДЁТ: %d%% — стой в зоне (в зоне: %d)" % [int(rt["p1"] * 100.0), int(rt["p2"])]
				elif d < ZONE_RADIUS + 4.0:
					return "%s: встань в кольцо монтажа" % rt["title"]
			"relay":
				var next: int = rt["step"]
				if next < rt["stations"].size():
					var st: TaskStation = rt["stations"][next]
					if player.global_position.distance_to(st.global_position) < 7.0:
						return "%s: дотяни кабель до опоры %d" % [rt["title"], next + 1]
	return ""

func _set_my_hold(idx: int, sub: int) -> void:
	if _my_hold_idx == idx and _my_hold_sub == sub:
		return
	if _my_hold_idx >= 0:
		_send_hold(_my_hold_idx, _my_hold_sub, false)
	_my_hold_idx = idx
	_my_hold_sub = sub
	if idx >= 0:
		_send_hold(idx, sub, true)

func _send_hold(idx: int, sub: int, on: bool) -> void:
	if Net.active and not Net.is_server():
		Net.srv_task_hold.rpc_id(1, idx, sub, on)
	else:
		server_task_hold(idx, sub, on, Net.my_id())

func _ride_wire(from: Vector3, to: Vector3) -> void:
	## путешествие вируса по проводу
	if _riding_wire:
		return
	_riding_wire = true
	player.control_enabled = false
	player.velocity = Vector3.ZERO
	Sfx.play("chain", -4.0, 1.4)
	var dur: = 0.4 + from.distance_to(to) / 30.0
	var step: = func(t: float) -> void:
		if is_instance_valid(player):
			var p: = from.lerp(to, t)
			p.y = 0.3 + sin(t * PI) * 2.2
			player.global_position = p
	var tw: = create_tween()
	tw.tween_method(step, 0.0, 1.0, dur)
	tw.tween_callback(func() -> void:
		_riding_wire = false
		if is_instance_valid(player):
			player.control_enabled = true)

func _handle_interactions(delta: float) -> void:
	if phase == "done" or _riding_wire:
		return
	var prompt: = ""
	var carried: = my_carried_item()

	if GameState.my_bug:
		_set_my_hold(-1, -1)
		var d: = player.global_position.distance_to(PAD_POS)
		if d < PAD_RADIUS:
			prompt = "реанимация у портала… держись в круге!"
		else:
			prompt = "ты — БАГ: ползи в круг у портала (%dм) или жди Botnet" % int(d)
		hud.show_prompt(prompt)
		return

	var sync_at: = _nearest_sync_console()
	if carried == null and sync_at[0] >= 0 and Input.is_action_pressed("interact"):
		_set_my_hold(sync_at[0], sync_at[1])
		var rt: Dictionary = tasks_rt[sync_at[0]]
		var mine: float = rt["p1"] if sync_at[1] == 0 else rt["p2"]
		var other: float = rt["p2"] if sync_at[1] == 0 else rt["p1"]
		prompt = "РУБИЛЬНИК: держи [E] · мой рычаг %d%% · второй %d%%" % [int(mine * 100.0), int(other * 100.0)]
		if other <= 0.01 and (not Net.active or Net.players.size() <= 1):
			prompt += " (беги ко второму, пока этот не остыл!)"
		hud.show_prompt(prompt)
		return
	_set_my_hold(-1, -1)

	if carried != null:
		if _carry_strength(carried.carriers) < carried.weight:
			prompt = "тащишь «%s» ОДИН — медленно (второй ускорит) · [E] бросить" % carried.loot_name
		else:
			prompt = "неси «%s» в круг у портала · [F] бросить" % carried.loot_name
	else:
		var it: = _nearest_free_loot(2.7)
		var wire: = _nearest_wire()
		if it != null:
			if it.weight > 1 and not it.carriers.is_empty():
				prompt = "[E] подхватить «%s» — вдвоём быстрее (%d/%d)" % [it.loot_name, it.carriers.size() + 1, it.weight]
			elif it.weight > _my_strength():
				prompt = "[E] взяться за «%s» — одному МЕДЛЕННО, вдвоём в темпе" % it.loot_name
			else:
				prompt = "[E] схватить «%s» (◈ %d)" % [it.loot_name, roundi(it.value)]
		elif sync_at[0] >= 0:
			prompt = "[E держать] рычаг рубильника (нужны ОБА рычага сразу)"
		elif not wire.is_empty():
			prompt = "[E] нырнуть в провод — переброс на ту сторону"
		elif cooler_charges > 0 and player.global_position.distance_to(cooler_pos) < 2.8:
			if Input.is_action_pressed("interact"):
				_cooler_hold += delta
				prompt = "охлаждение… %d%%" % int(_cooler_hold / COOLER_TIME * 100.0)
				if _cooler_hold >= COOLER_TIME:
					_cooler_hold = 0.0
					_use_cooler()
			else:
				_cooler_hold = 0.0
				prompt = "[E держать] КУЛЕР: тревога −15 (зарядов: %d)" % cooler_charges
		else:
			prompt = _nearest_task_hint()

	if prompt == "":
		hud.hide_prompt()
	else:
		hud.show_prompt(prompt)

	if Input.is_action_just_pressed("interact"):
		if carried != null:
			_request_release(carried, false)
		else:
			var it: = _nearest_free_loot(2.7)
			if it != null:
				_request_grab(it)
			else:
				var wire: = _nearest_wire()
				if not wire.is_empty() and sync_at[0] < 0:
					_ride_wire(wire["from"], wire["to"])

func _my_strength() -> int:
	return 2 if GameState.has_passive("ransomware") else 1

func _request_grab(it: LootItem) -> void:
	player._unmorph_if_needed()
	if Net.active and not Net.is_server():
		Net.srv_grab.rpc_id(1, it.item_id)
	else:
		server_grab(it.item_id, Net.my_id())
	Sfx.play("pickup", -6.0, 1.2)

func _request_release(it: LootItem, throw: bool) -> void:
	var dir: = player.look_dir()
	if Net.active and not Net.is_server():
		Net.srv_release.rpc_id(1, it.item_id, throw, dir)
	else:
		server_release(it.item_id, Net.my_id(), throw, dir)
	if throw:
		Sfx.play("jump", -4.0, 0.7)
		player._noise(1.2)

func _use_cooler() -> void:
	if Net.active and not Net.is_server():
		Net.srv_cooler.rpc_id(1)
	else:
		server_cooler(Net.my_id())

func _unhandled_input(event: InputEvent) -> void:
	if phase == "done":
		return
	if event.is_action_pressed("pause"):
		_toggle_pause()
	elif event.is_action_pressed("ability") and not _paused_by_menu:
		_use_ability(0)
	elif event.is_action_pressed("ability_2") and not _paused_by_menu:
		_use_ability(1)
	elif event.is_action_pressed("ability_3") and not _paused_by_menu:
		_use_ability(2)
	elif event.is_action_pressed("throw") and not _paused_by_menu:
		var it: = my_carried_item()
		if it != null and _carry_strength(it.carriers) >= it.weight:
			_request_release(it, true)

func _toggle_pause() -> void:
	_paused_by_menu = not _paused_by_menu
	if Net.active:
		player.control_enabled = not _paused_by_menu
	else:
		get_tree().paused = _paused_by_menu
	pause_panel.visible = _paused_by_menu
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _paused_by_menu else Input.MOUSE_MODE_CAPTURED

# ── активки: до 3 слотов [Q]/[X]/[C] ────────────────────────

func _use_ability(slot: int) -> void:
	if GameState.my_bug:
		hud.toast("ты баг. у багов нет активок. у багов есть только писк", UIKit.DIM)
		return
	if player.locked():
		hud.toast("умения заблокированы ловушкой!", UIKit.DIM)
		return
	if slot >= GameState.active_abilities.size():
		if GameState.active_abilities.is_empty():
			hud.toast("нет активок: выбери ветку и УР.1 в дереве эволюции [Tab] (в Гриде)", UIKit.DIM)
		return
	if ability_cd > 0.0:
		hud.toast("активка перезаряжается", UIKit.DIM)
		return
	var id: String = GameState.active_abilities[slot]
	var cost: = GameState.ability_cost(id)
	if not GameState.try_spend_bw(cost):
		hud.toast("недостаточно Bandwidth", UIKit.MAGENTA)
		return
	Sfx.play("ability")
	var remote_client: = Net.active and not Net.is_server()
	match id:
		"morph":
			player.set_morph(true)
			Net.send_morph(true)
			hud.toast("ЛОЖНЫЙ ФАЙЛ: замри — камеры тебя не видят. Движение снимает морф", UIKit.CYAN)
		"dash":
			player.dash()
			hud.toast("РЫВОК!", UIKit.TEAL)
		"freeze":
			if remote_client:
				Net.srv_enemy_effect.rpc_id(1, "freeze", 3.0, Vector3.ZERO)
			else:
				apply_enemy_effect("freeze", 3.0, Vector3.ZERO)
			hud.toast("ШИФРОВАНИЕ: система и ловушки заморожены (3с)", UIKit.MAGENTA)
		"xray":
			Net.send_xray()
			hud.toast("СКАН: лут и угрозы подсвечены всей команде (6с)", UIKit.AMBER)
		"decoy":
			var pos: = player.global_position + player.look_dir() * 4.0
			if remote_client:
				Net.srv_enemy_effect.rpc_id(1, "decoy", 5.0, Vector3(pos.x, 1.2, pos.z))
			else:
				apply_enemy_effect("decoy", 5.0, Vector3(pos.x, 1.2, pos.z))
			_spawn_decoy_ghost(pos)
			hud.toast("ФАНТОМ: ловушки ведутся (5с)", UIKit.AMBER)
		"jam":
			GameState.add_alarm(-12.0, "wipe")
			hud.toast("ГЛУШИЛКА: тревога −12", UIKit.VIOLET)
		"heal":
			var target: = _nearest_bug(6.0)
			if target != 0:
				if remote_client:
					Net.srv_revive.rpc_id(1, target)
				else:
					server_revive(target, Net.my_id())
			else:
				if remote_client:
					Net.srv_revive.rpc_id(1, Net.my_id())
				else:
					server_revive(Net.my_id(), Net.my_id())
				hud.toast("РОЙ: подлатал себя (+1 HP)", UIKit.CYAN)
	ability_cd = 8.0 - GameState.evo_bonus("cooldown")
	hud.set_ability_cooldown(ability_cd)

func _nearest_bug(radius: float) -> int:
	if not Net.active:
		return 0
	for id in avatars:
		if Net.is_bug(id) and avatars[id].global_position.distance_to(player.global_position) < radius:
			return id
	return 0

func _spawn_decoy_ghost(pos: Vector3) -> void:
	var ghost: = MeshInstance3D.new()
	var m: = CapsuleMesh.new()
	m.radius = 0.42
	m.height = 1.55
	ghost.mesh = m
	var sh: = ShaderMaterial.new()
	sh.shader = load("res://shaders/hologram.gdshader")
	sh.set_shader_parameter("col", Vector3(1.0, 0.7, 0.3))
	ghost.material_override = sh
	ghost.position = pos + Vector3(0, 0.95, 0)
	add_child(ghost)
	var tw: = create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(ghost, "scale", Vector3(0.01, 1.6, 0.01), 0.4)
	tw.tween_callback(ghost.queue_free)

func _apply_xray() -> void:
	for it in loots.values():
		if is_instance_valid(it):
			it.set_xray(true)
	get_tree().create_timer(6.0).timeout.connect(func() -> void:
		for it in loots.values():
			if is_instance_valid(it):
				it.set_xray(false))

# ── демо-бот ────────────────────────────────────────────────

func _demo_tick(delta: float) -> void:
	_demo_timer += delta
	_demo_grab_cd = maxf(_demo_grab_cd - delta, 0.0)
	if GameState.my_bug:
		player.demo_target = PAD_POS
		return
	var carried: = my_carried_item()
	if carried != null:
		player.demo_target = PAD_POS
		return
	if GameState.evac_open and GameState.access >= 100.0:
		player.demo_target = PAD_POS
		return
	var best: LootItem = null
	var best_d: = 999.0
	for it in loots.values():
		if not is_instance_valid(it) or it.deposited or not it.carriers.is_empty() or it.weight > 1:
			continue
		if it.global_position.y > 1.6:
			continue # демо-бот по антресолям не лазает
		var d: float = player.global_position.distance_to(it.global_position)
		if d < best_d:
			best_d = d
			best = it
	if best != null:
		player.demo_target = best.global_position
		if best_d < 2.4 and _demo_grab_cd <= 0.0:
			_demo_grab_cd = 0.8
			_request_grab(best)
	else:
		player.demo_target = PAD_POS

# ── финал ───────────────────────────────────────────────────

func _finish(victory: bool, reason: String) -> void:
	if phase == "done":
		return
	if Net.active:
		if Net.is_server():
			Net.finish_hack_server(victory, reason)
		return
	_do_local_finish(victory, reason)

func _do_local_finish(victory: bool, reason: String) -> void:
	if phase == "done":
		return
	phase = "done"
	_dlog("ФИНИШ victory=%s (%s) добыча=%d%%" % [victory, reason, roundi(GameState.access)])
	GameState.finish_hack(victory)
	Sfx.play("hack_win" if victory else "hack_fail")
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var results: Control = ResultsScript.new()
	top_layer.add_child(results)
	results.show_result(victory, reason)
