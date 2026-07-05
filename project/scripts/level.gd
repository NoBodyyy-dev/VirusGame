extends Node3D

## PANIC PROTOCOL — узел как ограбление:
## тащи физический лут в портал, не буди систему, эвакуируйся до СТИРАНИЯ.
## Уровень генерируется по сиду узла: у каждого тира своя локация.
## Вместо мини-игр — полевые кооп-задачи (синхро-консоли, захват, реле).
## Хост владеет: физикой лута, стражами, тревогой, HP, задачами, эвакуацией.

const HUDScript: = preload("res://scripts/hud.gd")
const BriefScript: = preload("res://scripts/brief_ui.gd")
const ResultsScript: = preload("res://scripts/results_ui.gd")

const PAD_POS: = Vector3(-27.0, 0.0, 0.0)
const PAD_RADIUS: = 3.6
const REVIVE_TIME: = 3.0
const COOLER_TIME: = 2.6
const SYNC_CHARGE_TIME: = 2.8    # сек удержания на консоль
const SYNC_DECAY: = 0.16         # заряд утекает без удержания
const ZONE_RADIUS: = 4.5
const ZONE_TIME: = 14.0          # сек захвата в одиночку
const RELAY_WINDOW: = 12.0       # сек на цепь после первого реле

var hall: = Vector2(70.0, 46.0)
var rng: = RandomNumberGenerator.new()
var theme: = "home"

var player: VirusPlayer
var enemies: = {}            # eid -> Antivirus
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
var phase: = "brief"          # brief / heist / done (эвакуация = evac_open)
var _paused_by_menu: = false
var _fog_base: = Color(0.3, 0.6, 0.8)
var _phase_seen: = 0
var _next_lid: = 0
var _next_eid: = 0

# ── кооп и пати ──
var avatars: = {}
var party: PartyFx
var _enemy_sync: = 0.0
var _loot_sync: = 0.0
var _task_sync: = 0.0
var _host_hp: = {}            # id -> hp (владеет хост; для соло — {1: hp})
var _revive_t: = {}           # id -> прогресс реанимации на паде
var _cooler_hold: = 0.0
var _my_hold_idx: = -1        # какую консоль я сейчас держу
var _my_hold_sub: = -1
var _demo_timer: = 0.0
var _demo_grab_cd: = 0.0
var _plat_spots: Array = []
var _crate_spots: Array = []

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
	# позиция кулера выбирается ДО застройки — реквизит его обходит
	cooler_pos = Vector3(rng.randf_range(-6.0, 10.0), 0.0, rng.randf_range(8.0, hall.y * 0.5 - 5.0))
	_build_environment()
	_build_arena()
	_build_theme_props()
	_build_platforms()
	_build_portal_and_pad()
	_build_cooler()
	_spawn_player()
	_spawn_task_stations()
	_build_particles()
	_build_ui()
	if Net.active:
		_setup_coop()
	if Net.is_server():
		_host_init()
	_show_brief()
	Sfx.ambient(true, 0.85 if is_boss else 1.0)

func _dlog(msg: String) -> void:
	## диагностика автотестов — молчит вне демо-режима
	if GameState.demo_mode:
		print("[LVL] %s" % msg)

# ── хост: старт симуляции ───────────────────────────────────

func _host_init() -> void:
	_host_hp[1] = GameState.my_max_hp
	if Net.active:
		Net.set_hp(1, GameState.my_max_hp, false)
	_spawn_loot_table()
	# защита растёт с тиром: сканеров патрулирует всё больше
	var scanners: int = GameState.node_config.get("scanners", 1)
	for i in scanners:
		var ang: = TAU * float(i) / float(maxi(scanners, 1))
		_spawn_enemy("SCANNER", Vector3(cos(ang) * 9.0, 2.3, sin(ang) * 7.0))

# ── окружение ───────────────────────────────────────────────

func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.014, 0.028)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.07, 0.12, 0.18)
	env.ambient_light_energy = 1.3
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.022
	_fog_base = Color(0.55, 0.25, 0.3) if is_boss else [
		Color(0.35, 0.65, 0.8), Color(0.7, 0.55, 0.3), Color(0.7, 0.3, 0.45), Color(0.45, 0.3, 0.75),
	][GameState.node_config.get("difficulty", 0)]
	env.volumetric_fog_albedo = _fog_base
	env.volumetric_fog_emission = Color(0.01, 0.03, 0.05)
	env.volumetric_fog_emission_energy = 0.35
	var we: = WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun: = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_color = Color(0.5, 0.7, 0.9)
	sun.light_energy = 0.22
	sun.shadow_enabled = true
	add_child(sun)

func _neon_mat(c: Color, energy: = 1.6) -> StandardMaterial3D:
	var m: = StandardMaterial3D.new()
	m.albedo_color = Color(0.02, 0.03, 0.05)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m

func _dark_mat() -> StandardMaterial3D:
	var m: = StandardMaterial3D.new()
	m.albedo_color = Color(0.06, 0.085, 0.125)
	m.metallic = 0.55
	m.roughness = 0.35
	return m

func _box(size: Vector3, mat: Material, pos: Vector3, parent: Node = self) -> MeshInstance3D:
	var mi: = MeshInstance3D.new()
	var mesh: = BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _collider(size: Vector3, pos: Vector3) -> void:
	var sb: = StaticBody3D.new()
	sb.collision_layer = 1
	var cs: = CollisionShape3D.new()
	var box: = BoxShape3D.new()
	box.size = size
	cs.shape = box
	sb.position = pos
	sb.add_child(cs)
	add_child(sb)

func _solid_box(size: Vector3, mat: Material, pos: Vector3) -> void:
	_box(size, mat, pos)
	_collider(size, pos)

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
	var floor_mesh: = MeshInstance3D.new()
	var plane: = PlaneMesh.new()
	plane.size = hall
	floor_mesh.mesh = plane
	var fmat: = ShaderMaterial.new()
	fmat.shader = load("res://shaders/floor_grid.gdshader")
	var tier: int = GameState.node_config.get("difficulty", 0)
	var tier_cols: = [Vector3(0.08, 0.75, 0.95), Vector3(0.85, 0.6, 0.2), Vector3(0.9, 0.3, 0.5), Vector3(0.5, 0.3, 0.95)]
	fmat.set_shader_parameter("line_col", Vector3(0.9, 0.15, 0.25) if is_boss else tier_cols[tier])
	floor_mesh.material_override = fmat
	add_child(floor_mesh)
	_collider(Vector3(hall.x, 0.5, hall.y), Vector3(0, -0.25, 0))

	var wall_mat: = _dark_mat()
	var trim_color: = Color(0.7, 0.12, 0.2) if is_boss else Color(0.12, 0.55, 0.75)
	var trim_mat: = _neon_mat(trim_color, 1.1)
	var hx: = hall.x * 0.5
	var hz: = hall.y * 0.5
	for side in [
		{"size": Vector3(hall.x, 6, 0.6), "pos": Vector3(0, 3, -hz)},
		{"size": Vector3(hall.x, 6, 0.6), "pos": Vector3(0, 3, hz)},
		{"size": Vector3(0.6, 6, hall.y), "pos": Vector3(-hx, 3, 0)},
		{"size": Vector3(0.6, 6, hall.y), "pos": Vector3(hx, 3, 0)},
	]:
		_box(side["size"], wall_mat, side["pos"])
		_collider(side["size"], side["pos"])
		var trim_size: Vector3 = side["size"]
		trim_size.y = 0.08
		var trim_pos: Vector3 = side["pos"]
		trim_pos.y = 2.6
		_box(trim_size * Vector3(1.0, 1.0, 1.02), trim_mat, trim_pos)

	# декоративные «свечки» неона
	for i in 16:
		var p: = Vector3(rng.randf_range(-hx + 3, hx - 3), 2.6, rng.randf_range(-hz + 3, hz - 3))
		var c: = Color(0.1, rng.randf_range(0.5, 0.8), rng.randf_range(0.7, 1.0))
		_box(Vector3(0.05, rng.randf_range(2.5, 5.0), 0.05), _neon_mat(c, rng.randf_range(0.5, 1.1)), p)

# ── тематические локации: каждый тир выглядит по-своему ─────

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
	## домашний ПК: гигантские клавиши, планки RAM, башня системника
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
	# планки RAM — длинные барьеры
	for i in 3 + rng.randi() % 3:
		var pos: = Vector3(rng.randf_range(-16.0, 24.0), 1.4, rng.randf_range(4.0, hall.y * 0.5 - 5.0))
		if not _spot_free(pos):
			continue
		_solid_box(Vector3(7.5, 2.8, 0.9), key_mat, pos)
		for k in 4:
			_box(Vector3(0.9, 1.6, 0.1), _neon_mat(Color(0.2, 0.85, 0.5), 1.3), pos + Vector3(-2.6 + k * 1.7, 0.2, 0.51))
	# башня системника у стены
	var tower_pos: = Vector3(hall.x * 0.5 - 5.0, 3.0, rng.randf_range(-10.0, 10.0))
	_solid_box(Vector3(4.5, 6.0, 6.5), key_mat, tower_pos)
	_box(Vector3(0.4, 0.4, 0.4), _neon_mat(Color(0.2, 0.9, 0.6), 2.5), tower_pos + Vector3(-2.3, 1.8, 2.0))

func _theme_office() -> void:
	## офис: кубиклы-перегородки и столы с мониторами
	var desk_mat: = _dark_mat()
	var part_mat: = _dark_mat()
	part_mat.albedo_color = Color(0.09, 0.1, 0.13)
	for row in 2:
		for col in 3:
			var base: = Vector3(-10.0 + col * 14.0 + rng.randf_range(-2, 2), 0.0, -12.0 + row * 16.0 + rng.randf_range(-2, 2))
			if not _spot_free(base, 5.0):
				continue
			# П-образная перегородка
			_solid_box(Vector3(6.0, 2.2, 0.5), part_mat, base + Vector3(0, 1.1, -2.5))
			_solid_box(Vector3(0.5, 2.2, 5.0), part_mat, base + Vector3(-3.0, 1.1, 0))
			# стол и монитор
			_solid_box(Vector3(3.4, 1.0, 1.6), desk_mat, base + Vector3(0.4, 0.5, -1.4))
			var mon_col: = Color(0.2, 0.7, 0.95) if rng.randf() < 0.5 else Color(0.95, 0.7, 0.25)
			var mon: = _box(Vector3(1.5, 1.0, 0.12), _neon_mat(mon_col, 1.4), base + Vector3(0.4, 1.6, -1.7))
			mon.rotation.y = rng.randf_range(-0.3, 0.3)
	# ксерокс, который все ненавидят
	var xerox: = Vector3(rng.randf_range(14.0, 24.0), 1.0, rng.randf_range(-6.0, 6.0))
	if _spot_free(xerox):
		_solid_box(Vector3(2.2, 2.0, 2.2), desk_mat, xerox)
		_box(Vector3(1.8, 0.08, 1.8), _neon_mat(Color(0.9, 0.4, 0.2), 1.6), xerox + Vector3(0, 1.06, 0))

func _theme_bank() -> void:
	## банк: колонны, дверь-сейф, палеты «золотых» блоков
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
	# круглая дверь хранилища в дальней стене
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
	# слитки данных
	for i in 4 + rng.randi() % 4:
		var pos: = Vector3(rng.randf_range(-18.0, 26.0), 0.6, rng.randf_range(-hall.y * 0.5 + 6.0, hall.y * 0.5 - 6.0))
		if not _spot_free(pos):
			continue
		_solid_box(Vector3(1.8, 1.2, 1.2), _neon_mat(Color(0.95, 0.8, 0.35), 0.7), pos)

func _theme_dc() -> void:
	## дата-центр: ровные ряды серверных стоек + кабельные лотки
	var rack_mat: = _dark_mat()
	var strip_colors: = [Color(0.15, 0.7, 0.9), Color(0.12, 0.8, 0.6), Color(0.45, 0.3, 0.9)]
	var row_gap: = rng.randf_range(7.0, 9.0)
	var rows: = int(hall.y / row_gap) - 1
	for r in rows:
		var rz: = -hall.y * 0.5 + row_gap * float(r + 1)
		var gap_at: = rng.randi() % 5
		for c in 6:
			if c == gap_at:
				continue # проход в ряду
			var pos: = Vector3(-18.0 + c * 8.5, 1.5, rz)
			if not _spot_free(pos):
				continue
			_solid_box(Vector3(5.0, 3.0, 1.4), rack_mat, pos)
			var sc: Color = strip_colors[rng.randi() % strip_colors.size()]
			for k in 3:
				_box(Vector3(4.6, 0.06, 0.06), _neon_mat(sc, 1.5), pos + Vector3(0, -0.9 + k * 0.8, 0.74))
		# кабельный лоток над рядом
		_box(Vector3(44.0, 0.15, 0.8), _neon_mat(Color(0.2, 0.5, 0.7), 0.6), Vector3(0, 4.6, rz))

func _theme_boss() -> void:
	## ОРАКУЛ: красные колонны-ядра и кольца вычислений
	var core_mat: = _neon_mat(Color(0.9, 0.2, 0.3), 1.6)
	for i in 5:
		var ang: = TAU * float(i) / 5.0
		var pos: = Vector3(cos(ang) * 14.0, 3.5, sin(ang) * 11.0)
		if not _spot_free(pos, 4.0):
			continue
		_solid_box(Vector3(2.0, 7.0, 2.0), _dark_mat(), pos)
		_box(Vector3(2.2, 0.4, 2.2), core_mat, pos + Vector3(0, rng.randf_range(-2.0, 2.5), 0))
	for k in 3:
		var ring: = MeshInstance3D.new()
		var tor: = TorusMesh.new()
		tor.inner_radius = 6.0 + k * 3.0
		tor.outer_radius = 6.3 + k * 3.0
		ring.mesh = tor
		ring.material_override = _neon_mat(Color(0.8, 0.15, 0.25), 0.8)
		ring.position = Vector3(0, 5.5 + k * 1.2, 0)
		add_child(ring)

func _build_platforms() -> void:
	# парящие платформы: наверху лежит лут — прыжки окупаются
	var plat_mat: = _dark_mat()
	var glow: = _neon_mat(Color(0.16, 0.95, 0.75) if not is_boss else Color(0.9, 0.25, 0.3), 1.4)
	var count: = 5 + rng.randi() % 3
	var placed: Array = []
	for i in count:
		var pos: = Vector3(rng.randf_range(-hall.x * 0.5 + 6.0, hall.x * 0.5 - 6.0), rng.randf_range(1.6, 4.3), rng.randf_range(-hall.y * 0.5 + 6.0, hall.y * 0.5 - 6.0))
		if not _spot_free(pos):
			continue
		var ok: = true
		for prev in placed:
			if Vector2(pos.x - prev.x, pos.z - prev.z).length() < 6.0:
				ok = false
		if not ok:
			continue
		placed.append(pos)
		var size: = Vector3(rng.randf_range(2.4, 3.4), 0.35, rng.randf_range(2.4, 3.4))
		_box(size, plat_mat, pos)
		_collider(size, pos)
		var trim: Vector3 = size
		trim.y = 0.06
		_box(trim * Vector3(1.05, 1.0, 1.05), glow, pos + Vector3(0, size.y * 0.5, 0))
		_plat_spots.append(pos + Vector3(0, size.y * 0.5 + 0.6, 0))
	# точки для тяжёлых ящиков
	for i in 8:
		var pos: = Vector3(rng.randf_range(-hall.x * 0.5 + 8.0, hall.x * 0.5 - 6.0), 0.7, rng.randf_range(-hall.y * 0.5 + 6.0, hall.y * 0.5 - 6.0))
		if _spot_free(pos):
			_crate_spots.append(pos)
	if _crate_spots.is_empty():
		_crate_spots.append(Vector3(12, 0.7, 8))

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

	# зона выноса: сюда приносят лут и сюда приползают баги
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

# ── полевые задачи: станции ─────────────────────────────────

func _spawn_task_stations() -> void:
	var cfg_tasks: Array = GameState.node_config.get("tasks", [])
	var centers: Array = []
	for i in cfg_tasks.size():
		# центр задачи: подальше от портала и других задач
		var center: = Vector3(12, 0, 0)
		for attempt in 24:
			center = Vector3(rng.randf_range(-4.0, hall.x * 0.5 - 9.0), 0.0, rng.randf_range(-hall.y * 0.5 + 8.0, hall.y * 0.5 - 8.0))
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
			"holders": {}, "contributors": {}}
		match cfg["type"]:
			"sync":
				var off: = Vector3(rng.randf_range(-1.0, 1.0), 0, rng.randf_range(-1.0, 1.0)).normalized() * 6.5
				for sub in 2:
					var st: = TaskStation.create("console", color, "%s\nконсоль %s" % [cfg["title"], ["А", "Б"][sub]])
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
					var st: = TaskStation.create("relay", color, "%s\nреле %d" % [cfg["title"], sub + 1])
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
	# рентген и кулер работают и в соло — подключаем всегда
	Net.xray_pulse.connect(_apply_xray)
	Net.cooler_used.connect(_on_cooler_used)
	Net.task_state.connect(_on_task_state)
	Net.task_done.connect(_on_task_done)
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

func _show_brief() -> void:
	if GameState.demo_mode:
		phase = "heist"
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var brief: Control = BriefScript.new()
	top_layer.add_child(brief)
	if Net.active:
		player.control_enabled = false
	else:
		get_tree().paused = true
	brief.started.connect(func() -> void:
		if Net.active:
			player.control_enabled = true
		else:
			get_tree().paused = false
		brief.queue_free()
		phase = "heist"
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		hud.toast("ВЫНОСИМ ВСЁ, ЧТО СВЕТИТСЯ. И ТИХО!", UIKit.TEAL))

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
		for e in enemies.values():
			e.targets.erase(id)
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
	## id -> Node3D всех игроков (хост: для стражей и симуляции)
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
	# лёгкие файлы: часть на платформах, часть по полу
	var spots: Array = _plat_spots.duplicate()
	spots.shuffle()
	for i in files:
		var pos: Vector3
		if i < mini(3, spots.size()):
			pos = spots[i]
		else:
			pos = Vector3(randf_range(-24, hall.x * 0.5 - 5.0), 0.7, randf_range(-hall.y * 0.5 + 4.0, hall.y * 0.5 - 4.0))
			if pos.distance_to(PAD_POS) < 8.0:
				pos.x = absf(pos.x) # не спавнить прямо у портала
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

func _free_light_loot() -> Array:
	var out: Array = []
	for it in loots.values():
		if is_instance_valid(it) and it.weight == 1 and it.is_free() and not it.broken:
			out.append(it)
	return out

func server_grab(item_id: int, sender: int) -> void:
	var it: LootItem = loots.get(item_id)
	if it == null or not is_instance_valid(it) or it.deposited:
		return
	if (Net.active and Net.is_bug(sender)) or (not Net.active and GameState.my_bug):
		return # у багов лапки
	if sender in it.carriers:
		return
	# один штамм — один груз
	for other in loots.values():
		if sender in other.carriers:
			return
	# украдено попапом? отобрать нельзя — попап сам испугается прикосновения
	if not it.carriers.is_empty() and it.carriers[0] is int and it.carriers[0] < 0:
		return
	var new_carriers: Array = it.carriers.duplicate()
	new_carriers.append(sender)
	it.last_holder = sender
	it.set_carried(new_carriers)
	_sync_loot_state(it)
	if _carry_strength(new_carriers) < it.weight:
		Net.toast_all("%s взялся за «%s» — нужен второй!" % [Net.player_name(sender), it.loot_name], UIKit.AMBER) if Net.active else hud.toast("тяжело! нужен второй носильщик", UIKit.AMBER)

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
	# если остался один из двух — груз замирает и ждёт второго
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
	## только хост: груз в зоне выноса
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
		Net.send_loot_deposit(it.item_id, clean, val) # обработчик у всех пиров, включая хост
	else:
		_on_loot_deposited(it.item_id, clean, val)
	if not GameState.evac_open and GameState.access >= 100.0:
		_open_evac(false)

func _open_evac(forced: bool) -> void:
	## только хост
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

# ── хост: стражи ────────────────────────────────────────────

func _spawn_enemy(type: String, pos: Vector3) -> void:
	_next_eid += 1
	var e: = Antivirus.create(_next_eid, type, pos, false)
	e.targets = _all_actor_nodes()
	e.loot_provider = _free_light_loot
	e.waypoints = [Vector3(-18, 2.3, -10), Vector3(18, 2.3, -10), Vector3(18, 2.3, 10), Vector3(-18, 2.3, 10)]
	e.caught_id.connect(_on_enemy_caught)
	e.loot_stolen.connect(_on_loot_stolen)
	e.loot_dropped.connect(_on_loot_dropped_by_enemy)
	add_child(e)
	enemies[e.enemy_id] = e
	if Net.active:
		Net.send_enemy_spawn(e.enemy_id, type, pos)

func _on_enemy_caught(id: int, enemy: Antivirus) -> void:
	## только хост: Хантер укусил
	if phase == "done":
		return
	var cur: int = _host_hp.get(id, 3)
	cur = maxi(cur - 1, 0)
	_host_hp[id] = cur
	var bug: = cur <= 0
	GameState.apply_alarm(4.0, "caught", "worm")
	# жертва роняет груз
	for it in loots.values():
		if id in it.carriers:
			_release_item(it, id, false, Vector3.ZERO)
	if Net.active:
		Net.set_hp(id, cur, bug)
		Net.send_ragdoll(id, enemy.global_position)
		Net.score_event(id, "caught")
	else:
		GameState.my_hp = cur
		GameState.my_bug = bug
		GameState.hp_changed.emit(cur)
		GameState.stats["caught"] += 1
		player.ragdoll_from(enemy.global_position)
		hud.toast("HUNTER ВПИЛСЯ! HP −1", Color(1.0, 0.3, 0.3))
		if bug:
			player.set_bug(true)
			hud.toast("КРИТИЧЕСКИЙ СБОЙ: ты теперь БАГ. Скачи к порталу!", Color(1.0, 0.3, 0.3))
	# конец рана решают таймеры (WIPE), а не смерть: у багов всегда есть шанс доскакать

func _on_loot_stolen(enemy: Antivirus, it: LootItem) -> void:
	if Net.active:
		Net.send_loot_state(it.item_id, it.carriers)
		Net.toast_all("⚠ ПОПАП спёр «%s»! Догоните и ткните его!" % it.loot_name, Color(1.0, 0.85, 0.3))
	else:
		hud.toast("⚠ ПОПАП спёр «%s»! Ткни его [касанием]!" % it.loot_name, Color(1.0, 0.85, 0.3))
	Sfx.play("alarm", -8.0, 1.5)

func _on_loot_dropped_by_enemy(_enemy: Antivirus, it: LootItem) -> void:
	if Net.active:
		Net.send_loot_state(it.item_id, [])

func server_noise(amount: float, pos: Vector3, sender: int) -> void:
	## только хост: шум питает тревогу и слух Хантеров
	GameState.apply_alarm(amount, "noise", Net.my_class_of(sender) if Net.active else GameState.display_class())
	for e in enemies.values():
		if e.enemy_type == "HUNTER" and e.global_position.distance_to(pos) < 32.0:
			e.hear_noise(pos, amount)

func server_revive(target_id: int, medic_id: int) -> void:
	## только хост: Botnet-дефибрилляция или самоподнятие
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
			# перезапуск будит систему — воскресать больно
			GameState.apply_alarm(5.0, "revive", "worm")
			Net.toast_all("%s перезапустился у портала (система заметила)" % Net.player_name(target_id), UIKit.TEAL)
	elif not Net.active and GameState.my_bug:
		_host_hp[1] = 1
		GameState.revive_me()
		GameState.apply_alarm(5.0, "revive", "worm")
		player.set_bug(false)
		hud.toast("ПЕРЕЗАПУСК У ПОРТАЛА: 1 HP. Аккуратнее!", UIKit.TEAL)
	elif medic_id == target_id and cur > 0:
		# самолечение ботнета
		var maxed: = 3 + 2 # потолок не критичен
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
	## только хост: кулер общий на команду
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
	## игрок держит [E] у консоли синхро-взлома
	if idx < 0 or idx >= tasks_rt.size():
		return
	var rt: Dictionary = tasks_rt[idx]
	if rt["done"] or rt["type"] != "sync":
		return
	if not rt["holders"].has(sub):
		rt["holders"][sub] = {}
	if on:
		# проверка дистанции: держать можно только рядом с консолью
		var actors: = _all_actor_nodes()
		if actors.has(sender) and sub < rt["stations"].size():
			var st: TaskStation = rt["stations"][sub]
			if actors[sender].global_position.distance_to(st.global_position) < 3.4:
				rt["holders"][sub][sender] = true
				rt["contributors"][sender] = true
	else:
		rt["holders"][sub].erase(sender)

func _task_tick(delta: float) -> void:
	## только хост: симуляция прогресса задач
	var actors: = _all_actor_nodes()
	for i in tasks_rt.size():
		var rt: Dictionary = tasks_rt[i]
		if rt["done"]:
			continue
		match rt["type"]:
			"sync":
				# двойное удержание: обе консоли должны заряжаться одновременно
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
					# захват шумит — система чувствует вторжение
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
							Net.toast_all("⚡ цепь реле остыла — заново!", UIKit.AMBER)
						else:
							hud.toast("⚡ цепь реле остыла — заново!", UIKit.AMBER)
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
	## только хост
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
	# задача выплёвывает эпик-лут
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
	## у всех пиров: обновить визуал станций
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
				rt["stations"][0].set_caption("%s\nконсоль А · %d%%" % [rt["title"], int(rt["p1"] * 100.0)])
				rt["stations"][1].set_caption("%s\nконсоль Б · %d%%" % [rt["title"], int(rt["p2"] * 100.0)])
			"zone":
				rt["stations"][0].set_progress(rt["p1"])
				rt["stations"][0].set_active(rt["p2"] > 0.0)
				rt["stations"][0].set_caption("%s\nзахват %d%% · в зоне: %d" % [rt["title"], int(rt["p1"] * 100.0), int(rt["p2"])])
			"relay":
				for s in rt["stations"].size():
					var st: TaskStation = rt["stations"][s]
					st.set_progress(1.0 if s < rt["step"] else 0.0)
					st.set_active(s == rt["step"])
					if s == rt["step"]:
						var extra: = ""
						if rt["step"] > 0:
							extra = " · %.0fс" % maxf(rt["timer"], 0.0)
						st.set_caption("%s\n▶ реле %d%s" % [rt["title"], s + 1, extra])
					elif s < rt["step"]:
						st.set_caption("%s\nреле %d ✓" % [rt["title"], s + 1])
					else:
						st.set_caption("%s\nреле %d" % [rt["title"], s + 1])

func _on_task_done(idx: int, participants: Array) -> void:
	## у всех пиров: задача закрыта
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

func apply_enemy_effect(kind: String, arg: float, pos: Vector3) -> void:
	match kind:
		"freeze":
			for e in enemies.values():
				e.freeze_for(arg)
		"decoy":
			for e in enemies.values():
				e.decoy_at(pos, arg)

# ── клиент: приём состояния ─────────────────────────────────

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
	## у всех пиров: лут улетел в портал
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

func _on_enemy_spawned(id: int, type: String, pos: Vector3) -> void:
	if Net.is_server():
		return
	var e: = Antivirus.create(id, type, pos, true)
	add_child(e)
	enemies[id] = e

func _on_enemies_tf(batch: Array) -> void:
	if Net.is_server():
		return
	for row in batch:
		var e: Antivirus = enemies.get(int(row[0]))
		if e != null and is_instance_valid(e):
			e.net_update(Vector3(row[1], row[2], row[3]), row[4], row[5] > 0.5)

func _on_player_hp(id: int, hp_val: int, bug: bool) -> void:
	if id == Net.my_id():
		var was_bug: = GameState.my_bug
		GameState.my_hp = hp_val
		GameState.my_bug = bug
		GameState.hp_changed.emit(hp_val)
		player.set_bug(bug)
		if bug and not was_bug:
			GameState.stats["caught"] += 1
			hud.toast("КРИТИЧЕСКИЙ СБОЙ: ты теперь БАГ. Скачи к порталу или жди дефибриллятор!", Color(1.0, 0.3, 0.3))
		elif was_bug and not bug:
			hud.toast("ТЫ СНОВА В ДЕЛЕ! 1 HP — без героизма", UIKit.TEAL)
	elif avatars.has(id):
		if bug and not avatars[id].is_bug:
			hud.toast("%s разобран — он теперь БАГ! Пусть скачет к порталу" % Net.player_name(id), Color(1.0, 0.45, 0.3))
		avatars[id].set_bug(bug)

func _on_player_ragdoll(id: int, from: Vector3) -> void:
	if id == Net.my_id():
		player.ragdoll_from(from)
		if not GameState.my_bug:
			GameState.stats["caught"] += 1
		hud.toast("HUNTER ВПИЛСЯ! HP −1", Color(1.0, 0.3, 0.3))
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
	if phase == "brief" or phase == "done":
		return
	ability_cd = maxf(ability_cd - delta, 0.0)

	_apply_my_carry()
	_phase_fx_tick(delta)

	if Net.is_server():
		_host_tick(delta)

	if GameState.demo_mode:
		_demo_tick(delta)
	_handle_interactions(delta)
	_update_objective()

func _host_tick(delta: float) -> void:
	# тревога ползёт всегда — отсидка невозможна
	var creep: float = GameState.node_config.get("creep", 0.3)
	if GameState.evac_open:
		creep *= 1.6
	GameState.apply_alarm(creep * delta, "time", "worm")

	# фазы тревоги: спавним стражей
	var ph: = GameState.alarm_phase()
	if ph > _phase_seen:
		for p in range(_phase_seen + 1, ph + 1):
			_enter_alarm_phase(p)
		_phase_seen = ph

	# полевые задачи
	_task_tick(delta)
	_task_sync -= delta
	if _task_sync <= 0.0:
		_task_sync = 0.15
		_broadcast_task_state()

	# кто-то стоит в круге? депозит и реанимация
	var actors: = _all_actor_nodes()
	for it in loots.values():
		if not is_instance_valid(it) or it.deposited:
			continue
		if not it.carriers.is_empty() and _carry_strength(it.carriers) >= it.weight:
			# несомый лут парит над головами носильщиков
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
			# докинутый или доброшенный лут тоже считается
			_deposit(it, [it.last_holder])

	# баги реанимируются на паде
	for id in actors:
		var bugged: = Net.is_bug(id) if Net.active else GameState.my_bug
		if bugged and actors[id].global_position.distance_to(PAD_POS) < PAD_RADIUS:
			_revive_t[id] = _revive_t.get(id, 0.0) + delta
			if _revive_t[id] >= REVIVE_TIME:
				_revive_t[id] = 0.0
				server_revive(id, id)
		else:
			_revive_t.erase(id)

	# эвакуация
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

	# синк лута и стражей
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
		_enemy_sync -= delta
		if _enemy_sync <= 0.0:
			_enemy_sync = 0.08
			var ebatch: Array = []
			var nowt: = Time.get_ticks_msec() / 1000.0
			for e in enemies.values():
				if is_instance_valid(e):
					ebatch.append([e.enemy_id, e.global_position.x, e.global_position.y, e.global_position.z,
						e.rotation.y, 1.0 if nowt < e.frozen_until else 0.0])
			if not ebatch.is_empty():
				Net.send_enemies(ebatch)
		# цели стражей обновляются (пришли/ушли игроки)
		for e in enemies.values():
			e.targets = _all_actor_nodes()

func _enter_alarm_phase(p: int) -> void:
	## только хост: система просыпается
	_dlog("фаза тревоги %d (%s)" % [p, GameState.alarm_phase_name()])
	var cfg: Dictionary = GameState.node_config
	match p:
		1: # SCAN: воришки
			for i in int(cfg.get("popups", 1)):
				_spawn_enemy("POPUP", Vector3(randf_range(-10, 10), 0.6, randf_range(-8, 8)))
		2: # PURGE: охотники
			for i in int(cfg.get("hunters", 1)):
				_spawn_enemy("HUNTER", Vector3(randf_range(-14, 14), 2.3, randf_range(-10, 10)))
		3: # WIPE: всё звереет
			for e in enemies.values():
				e.wipe_boost += 1.4

func _phase_fx_tick(_delta: float) -> void:
	## каждый пир: свет/туман/сирены по фазе тревоги (тревога синкается метрами)
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
			env.volumetric_fog_albedo = Color(0.8, 0.2, 0.25).lerp(Color(0.4, 0.05, 0.1), 0.5 + 0.5 * sin(t * 5.0))
			env.ambient_light_color = Color(0.16, 0.06, 0.08)
	# локальные тосты на смену фазы
	if ph != _my_phase_seen:
		if ph > _my_phase_seen:
			match ph:
				1:
					hud.toast("ТРЕВОГА: SCAN — в систему вышли ПОПАПЫ-воришки", UIKit.AMBER)
					Sfx.play("alarm", -6.0)
				2:
					hud.toast("ТРЕВОГА: PURGE — HUNTER-KILLER В СЕТИ. Он СЛЫШИТ вас!", Color(1.0, 0.45, 0.3))
					Sfx.play("hunter")
					player.shake(0.35)
				3:
					hud.toast("ТРЕВОГА: WIPE — СИСТЕМА СТИРАЕТ УЗЕЛ!", Color(1.0, 0.15, 0.25))
					Sfx.play("quarantine")
					player.shake(0.6)
		_my_phase_seen = ph
	# пад дышит на эвакуации
	if GameState.evac_open:
		pad_mat.albedo_color = Color(0.1, 0.9, 0.75, 0.2 + 0.12 * sin(t * 6.0))
		portal_ring_mat.emission = Color(0.16, 0.95, 0.75)
		portal_ring_mat.emission_energy_multiplier = 2.5 + sin(t * 6.0)
		portal_light.light_energy = 3.0 + sin(t * 6.0)

var _my_phase_seen: = 0

# ── переноска: локальные ощущения ───────────────────────────

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
	if _carry_strength(it.carriers) < it.weight:
		player.carry_factor = 0.22 # держишь угол и ждёшь второго
		return
	var f: = 0.78
	if it.weight >= 2:
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
			# можно подхватить недонесённый тяжёлый
			if _carry_strength(it.carriers) >= it.weight or Net.my_id() in it.carriers:
				continue
			if it.carriers[0] is int and it.carriers[0] < 0:
				continue
		var d: float = player.global_position.distance_to(it.global_position)
		if d < best_d:
			best_d = d
			best = it
	return best

func _nearest_sync_console() -> Array:
	## [task_idx, sub_idx] ближайшей консоли синхро-взлома
	for i in tasks_rt.size():
		var rt: Dictionary = tasks_rt[i]
		if rt["done"] or rt["type"] != "sync":
			continue
		for sub in 2:
			var st: TaskStation = rt["stations"][sub]
			if player.global_position.distance_to(st.global_position) < 3.0:
				return [i, sub]
	return [-1, -1]

func _nearest_task_hint() -> String:
	## подсказка возле зоны/реле
	for rt in tasks_rt:
		if rt["done"]:
			continue
		match rt["type"]:
			"zone":
				var d: = player.global_position.distance_to(rt["center"])
				if d < ZONE_RADIUS:
					return "ЗАХВАТ ИДЁТ: %d%% — стой в зоне (в зоне: %d)" % [int(rt["p1"] * 100.0), int(rt["p2"])]
				elif d < ZONE_RADIUS + 4.0:
					return "%s: встань в кольцо" % rt["title"]
			"relay":
				var next: int = rt["step"]
				if next < rt["stations"].size():
					var st: TaskStation = rt["stations"][next]
					if player.global_position.distance_to(st.global_position) < 7.0:
						return "%s: коснись реле %d" % [rt["title"], next + 1]
	return ""

func _set_my_hold(idx: int, sub: int) -> void:
	if _my_hold_idx == idx and _my_hold_sub == sub:
		return
	# отпустить старую консоль
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

func _handle_interactions(delta: float) -> void:
	if phase == "done":
		return
	var prompt: = ""
	var carried: = my_carried_item()

	if GameState.my_bug:
		_set_my_hold(-1, -1)
		var d: = player.global_position.distance_to(PAD_POS)
		if d < PAD_RADIUS:
			prompt = "реанимация у портала… держись в круге!"
		else:
			prompt = "ты — БАГ: скачи в круг у портала (%dм) или жди Botnet" % int(d)
		hud.show_prompt(prompt)
		return

	# удержание консоли синхро-взлома
	var sync_at: = _nearest_sync_console()
	if carried == null and sync_at[0] >= 0 and Input.is_action_pressed("interact"):
		_set_my_hold(sync_at[0], sync_at[1])
		var rt: Dictionary = tasks_rt[sync_at[0]]
		var mine: float = rt["p1"] if sync_at[1] == 0 else rt["p2"]
		var other: float = rt["p2"] if sync_at[1] == 0 else rt["p1"]
		prompt = "СИНХРО-ВЗЛОМ: держи [E] · моя консоль %d%% · вторая %d%%" % [int(mine * 100.0), int(other * 100.0)]
		if other <= 0.01 and (not Net.active or Net.players.size() <= 1):
			prompt += " (беги заряжать вторую, пока эта не остыла!)"
		hud.show_prompt(prompt)
		return
	_set_my_hold(-1, -1)

	if carried != null:
		if _carry_strength(carried.carriers) < carried.weight:
			prompt = "«%s» тяжёлый: нужен второй! [E] бросить" % carried.loot_name
		else:
			prompt = "неси «%s» в круг у портала · [F] бросить" % carried.loot_name
	else:
		var it: = _nearest_free_loot(2.7)
		if it != null:
			if it.weight > 1 and not it.carriers.is_empty():
				prompt = "[E] подхватить «%s» (вас будет %d/%d)" % [it.loot_name, it.carriers.size() + 1, it.weight]
			elif it.weight > _my_strength():
				prompt = "[E] взяться за «%s» — нужно %d носильщика" % [it.loot_name, it.weight]
			else:
				prompt = "[E] схватить «%s» (◈ %d)" % [it.loot_name, roundi(it.value)]
		elif sync_at[0] >= 0:
			prompt = "[E держать] консоль синхро-взлома (нужны ОБЕ консоли сразу)"
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
	if phase == "brief" or phase == "done":
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
			hud.toast("ЛОЖНЫЙ ФАЙЛ: замри — и ты мебель. Движение снимает морф", UIKit.CYAN)
		"dash":
			player.dash()
			hud.toast("РЫВОК!", UIKit.TEAL)
		"freeze":
			if remote_client:
				Net.srv_enemy_effect.rpc_id(1, "freeze", 3.0, Vector3.ZERO)
			else:
				apply_enemy_effect("freeze", 3.0, Vector3.ZERO)
			hud.toast("ШИФРОВАНИЕ: все стражи заморожены (3с)", UIKit.MAGENTA)
		"xray":
			Net.send_xray()
			hud.toast("СКАН: лут и стражи подсвечены всей команде (6с)", UIKit.AMBER)
		"decoy":
			var pos: = player.global_position + player.look_dir() * 4.0
			if remote_client:
				Net.srv_enemy_effect.rpc_id(1, "decoy", 5.0, Vector3(pos.x, 2.3, pos.z))
			else:
				apply_enemy_effect("decoy", 5.0, Vector3(pos.x, 2.3, pos.z))
			_spawn_decoy_ghost(pos)
			hud.toast("ФАНТОМ: стражи ведутся (5с)", UIKit.AMBER)
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
	for e in enemies.values():
		if is_instance_valid(e):
			e.set_xray(true)
	get_tree().create_timer(6.0).timeout.connect(func() -> void:
		for it in loots.values():
			if is_instance_valid(it):
				it.set_xray(false)
		for e in enemies.values():
			if is_instance_valid(e):
				e.set_xray(false))

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
	# ищем лёгкий свободный лут
	var best: LootItem = null
	var best_d: = 999.0
	for it in loots.values():
		if not is_instance_valid(it) or it.deposited or not it.carriers.is_empty() or it.weight > 1:
			continue
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
