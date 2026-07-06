extends Node3D

## Грид — анфилада зон-комнат, ограниченных стенами (всё с коллизией).
## Зоны: T0 (3 сервера) → T1 (12) → T2 (25) → T3 (39) → ПЕНТАГОН.
## Проход в следующую зону — полупрозрачная стена с синей подсветкой и
## переливающимся кодом; открывается, когда взломаны ВСЕ серверы зоны.
## Прогресс зоны — заполняющаяся линия на стене у прохода.

const HUDScript: = preload("res://scripts/grid_hud.gd")
const EvolutionScript: = preload("res://scripts/evolution_ui.gd")
const HoloShader: = preload("res://shaders/hologram.gdshader")

const TIER_COLORS: = [Color("35e0ff"), Color("ffb454"), Color("ff5d8f"), Color("8b5cff")]
const INFECTED_COLOR: = Color("2fe6b0")
const LOCKED_COLOR: = Color("3a4a55")
const BOSS_COLOR: = Color("ff2d4a")
const WALL_H: = 10.0
const GATE_W: = 14.0
const CODE_GLYPHS: = "01アイウエオ<>#$%&=+?ABCDEF"

var player: VirusPlayer
var node_visuals: = {}
var motes: Array = []
var hud: Control
var env: Environment
var gates: Array = []         # [{label, zone}] — код на воротах переливается

var prompt_target: Dictionary = {}
var _paused: = false
var pause_panel: Control
var top_layer: CanvasLayer
var _win_shown: = false
var evo_panel: Control
var avatars: = {}
var party: PartyFx
var _entering: = false
var _code_t: = 0.0

func _ready() -> void:
	if GameState.grid_nodes.is_empty():
		GameState.new_campaign()
	_build_environment()
	_build_ground()
	_build_zones()
	_build_nodes()
	_build_motes()
	_spawn_player()
	_build_ui()
	if Net.active:
		_setup_coop()
		Net.sync_identity() # после new_campaign уровни сброшены — обновить скины у всех
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
	av.position = Vector3(randf_range(-3.0, 3.0), 0.2, 20.0 + randf_range(-2.0, 2.0))
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
	# процедурное небо и мягкий объёмный свет — живее и реалистичнее
	# ночной город в духе RE2: тёмное небо, луна, свет от фонарей
	var sky_mat: = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.025, 0.035, 0.07)
	sky_mat.sky_horizon_color = Color(0.09, 0.12, 0.2)
	sky_mat.ground_bottom_color = Color(0.01, 0.015, 0.03)
	sky_mat.ground_horizon_color = Color(0.07, 0.09, 0.15)
	sky_mat.sun_angle_max = 20.0
	var sky: = Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.1
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
	env.fog_light_color = Color(0.06, 0.09, 0.16)
	env.fog_density = 0.004
	env.fog_sky_affect = 0.0
	var we: = WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var moon: = DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-55, 35, 0)
	moon.light_color = Color(0.55, 0.65, 0.88)
	moon.light_energy = 0.3
	moon.shadow_enabled = true
	add_child(moon)

func _neon(c: Color, e: = 1.8) -> StandardMaterial3D:
	var m: = StandardMaterial3D.new()
	m.albedo_color = Color(0.02, 0.03, 0.05)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m

func _dark(_metal: = 0.5) -> StandardMaterial3D:
	## тёмный металл с шумовой текстурой (см. Mats)
	return Mats.metal_dark()

func _mesh_box(size: Vector3, mat: Material, pos: Vector3, parent: Node3D = self) -> MeshInstance3D:
	var mi: = MeshInstance3D.new()
	var bm: = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _collide(size: Vector3, pos: Vector3) -> void:
	var sb: = StaticBody3D.new()
	sb.collision_layer = 1
	var cs: = CollisionShape3D.new()
	var box: = BoxShape3D.new()
	box.size = size
	cs.shape = box
	sb.position = pos
	sb.add_child(cs)
	add_child(sb)

func _solid(size: Vector3, mat: Material, pos: Vector3) -> void:
	_mesh_box(size, mat, pos)
	_collide(size, pos)

func _build_ground() -> void:
	var z_far: float = grid_zones_last_z() - 40.0
	var length: = 60.0 - z_far
	# реалистичный тёмный асфальт вместо неоновой сетки
	var floor_mesh: = MeshInstance3D.new()
	var plane: = PlaneMesh.new()
	plane.size = Vector2(240.0, length)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(0, 0, (60.0 + z_far) * 0.5)
	floor_mesh.material_override = Mats.asphalt()
	add_child(floor_mesh)
	_collide(Vector3(240.0, 0.4, length), Vector3(0, -0.2, (60.0 + z_far) * 0.5))

func grid_zones_last_z() -> float:
	if GameState.grid_zones.is_empty():
		return -300.0
	return GameState.grid_zones[-1]["z1"]

# ── зоны: стены, ворота, прогресс ───────────────────────────

func _build_zones() -> void:
	var frontier: = GameState.frontier_zone()
	var wall_mat: = Mats.concrete(Color(0.4, 0.42, 0.46))
	for z in GameState.grid_zones.size():
		var zone: Dictionary = GameState.grid_zones[z]
		var z0: float = zone["z0"]
		var z1: float = zone["z1"]
		var half: float = zone["half"]
		var mid_z: = (z0 + z1) * 0.5
		var length: = z0 - z1
		var open_zone: = z <= frontier
		var tier_color: Color = BOSS_COLOR if z == GameState.grid_zones.size() - 1 else TIER_COLORS[zone["tier"]]
		# боковые стены (коллизия всегда)
		for side in [-1.0, 1.0]:
			_solid(Vector3(1.2, WALL_H, length), wall_mat, Vector3(side * half, WALL_H * 0.5, mid_z))
			if open_zone:
				_mesh_box(Vector3(0.3, 0.15, length * 0.96), _neon(tier_color, 0.45), Vector3(side * (half - 0.7), 3.2, mid_z))
		# передняя стена зоны 0 — глухая (за спиной старта)
		if z == 0:
			_solid(Vector3(half * 2.0 + 2.0, WALL_H, 1.2), wall_mat, Vector3(0, WALL_H * 0.5, z0))
		# дальняя стена с воротами (последняя зона — глухая)
		var next_half: = half
		if z + 1 < GameState.grid_zones.size():
			next_half = GameState.grid_zones[z + 1]["half"]
		var wall_half: = maxf(half, next_half)
		if z == GameState.grid_zones.size() - 1:
			_solid(Vector3(wall_half * 2.0 + 2.0, WALL_H, 1.2), wall_mat, Vector3(0, WALL_H * 0.5, z1))
		else:
			var seg: = wall_half - GATE_W * 0.5
			_solid(Vector3(seg, WALL_H, 1.2), wall_mat, Vector3(-(GATE_W * 0.5 + seg * 0.5), WALL_H * 0.5, z1))
			_solid(Vector3(seg, WALL_H, 1.2), wall_mat, Vector3(GATE_W * 0.5 + seg * 0.5, WALL_H * 0.5, z1))
			# перемычка над воротами
			_solid(Vector3(GATE_W, WALL_H - 6.0, 1.2), wall_mat, Vector3(0, 6.0 + (WALL_H - 6.0) * 0.5, z1))
			_build_gate(z, z1)
		# наполнение зоны — только если она открыта (территория растёт)
		if open_zone:
			_fill_zone(z, zone, tier_color)

func _build_gate(z: int, gate_z: float) -> void:
	## проход: полупрозрачная стена с синей подсветкой и кодом
	var done: = GameState.zone_complete(z)
	var gate_mat: = StandardMaterial3D.new()
	gate_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gate_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gate_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gate_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	gate_mat.albedo_color = Color(0.2, 0.55, 1.0, 0.10 if done else 0.30)
	var pane: = _mesh_box(Vector3(GATE_W, 6.0, 0.35), gate_mat, Vector3(0, 3.0, gate_z))
	# рамка с синей подсветкой
	_mesh_box(Vector3(GATE_W + 0.6, 0.3, 0.5), _neon(Color(0.25, 0.6, 1.0), 2.2), Vector3(0, 6.15, gate_z))
	for side in [-1.0, 1.0]:
		_mesh_box(Vector3(0.3, 6.3, 0.5), _neon(Color(0.25, 0.6, 1.0), 2.2), Vector3(side * (GATE_W * 0.5 + 0.15), 3.0, gate_z))
	var glight: = OmniLight3D.new()
	glight.light_color = Color(0.25, 0.6, 1.0)
	glight.light_energy = 2.0
	glight.omni_range = 12.0
	glight.position = Vector3(0, 4.0, gate_z + 2.0)
	add_child(glight)
	# переливающийся код на стекле
	var code: = Label3D.new()
	code.font_size = 30
	code.modulate = Color(0.5, 0.8, 1.0, 0.85)
	code.position = Vector3(0, 3.1, gate_z + 0.3)
	code.text = _random_code()
	add_child(code)
	var code2: = Label3D.new()
	code2.font_size = 30
	code2.modulate = Color(0.5, 0.8, 1.0, 0.85)
	code2.position = Vector3(0, 3.1, gate_z - 0.3)
	code2.rotation.y = PI
	code2.text = code.text
	add_child(code2)
	gates.append({"labels": [code, code2], "zone": z, "mat": gate_mat, "pane": pane})
	# закрытые ворота не пускают
	if not done:
		_collide(Vector3(GATE_W, 6.0, 0.5), Vector3(0, 3.0, gate_z))
	# статус и полоса прогресса зоны на стене у прохода
	var status: = Label3D.new()
	status.font_size = 44
	status.outline_size = 8
	status.position = Vector3(0, 7.4, gate_z + 0.8)
	if done:
		status.text = "ПРОХОД ОТКРЫТ ▸"
		status.modulate = INFECTED_COLOR
	else:
		status.text = "ЗАБЛОКИРОВАНО · взломайте серверы зоны"
		status.modulate = Color(0.5, 0.8, 1.0)
	add_child(status)
	_build_zone_progress_bar(z, gate_z)

func _build_zone_progress_bar(z: int, gate_z: float) -> void:
	## заполняющаяся линия прогресса зоны — на стене рядом с проходом
	var total: = GameState.zone_total(z)
	var infected: = GameState.zone_infected(z)
	var ratio: = float(infected) / maxf(float(total), 1.0)
	var bar_w: = 12.0
	var bx: = GATE_W * 0.5 + 2.0 + bar_w * 0.5
	_mesh_box(Vector3(bar_w, 0.7, 0.3), _dark(0.7), Vector3(bx, 4.6, gate_z + 0.4))
	if ratio > 0.01:
		var fill_w: = bar_w * ratio - 0.2
		_mesh_box(Vector3(fill_w, 0.5, 0.34), _neon(INFECTED_COLOR, 2.0),
			Vector3(bx - bar_w * 0.5 + 0.1 + fill_w * 0.5, 4.6, gate_z + 0.42))
	var lbl: = Label3D.new()
	lbl.font_size = 34
	lbl.modulate = INFECTED_COLOR if ratio >= 1.0 else Color(0.6, 0.85, 1.0)
	lbl.outline_size = 6
	lbl.text = "ВЗЛОМ ЗОНЫ: %d/%d" % [infected, total]
	lbl.position = Vector3(bx, 5.5, gate_z + 0.5)
	add_child(lbl)

func _random_code() -> String:
	var s: = ""
	for row in 3:
		for i in 14:
			s += CODE_GLYPHS[randi() % CODE_GLYPHS.length()]
		if row < 2:
			s += "\n"
	return s

func _fill_zone(z: int, zone: Dictionary, tier_color: Color) -> void:
	## интерьер зоны: компьютерный рельеф с коллизией
	var rng: = RandomNumberGenerator.new()
	rng.seed = 777 + z * 131
	var z0: float = zone["z0"]
	var z1: float = zone["z1"]
	var half: float = zone["half"]
	var props: = 6 + GameState.zone_total(z) / 2
	for i in mini(props, 22):
		var pos: = Vector3(rng.randf_range(-half + 8.0, half - 8.0), 0.0, rng.randf_range(z1 + 10.0, z0 - 10.0))
		# не заслоняем серверы
		var too_close: = false
		for node in GameState.grid_nodes:
			if node["zone"] == z and Vector2(pos.x - node["pos"].x, pos.z - node["pos"].z).length() < 6.0:
				too_close = true
				break
		if too_close:
			continue
		match rng.randi() % 3:
			0: # системный блок
				var h: = rng.randf_range(3.0, 5.0)
				_solid(Vector3(2.0, h, 3.0), Mats.plastic(Color(0.32, 0.34, 0.38)), pos + Vector3(0, h * 0.5, 0))
				_mesh_box(Vector3(2.06, 0.1, 0.1), _neon(tier_color, 0.7), pos + Vector3(0, h * 0.75, 1.4))
				_mesh_box(Vector3(1.6, h * 0.5, 0.06), Mats.plastic(Color(0.14, 0.15, 0.17)), pos + Vector3(0, h * 0.45, 1.52))
			1: # монитор
				_solid(Vector3(0.4, 1.6, 0.4), Mats.metal_dark(), pos + Vector3(0, 0.8, 0))
				_solid(Vector3(3.2, 2.0, 0.3), Mats.plastic(Color(0.24, 0.26, 0.3)), pos + Vector3(0, 2.6, 0))
				_mesh_box(Vector3(2.9, 1.7, 0.06), _neon(tier_color, 0.45), pos + Vector3(0, 2.6, 0.2))
			2: # клавиатура
				_solid(Vector3(3.4, 0.4, 1.4), Mats.plastic(Color(0.28, 0.3, 0.34)), pos + Vector3(0, 0.2, 0))
				for k in 4:
					_mesh_box(Vector3(0.5, 0.18, 0.5), Mats.plastic(Color(0.18, 0.2, 0.23)), pos + Vector3(-1.2 + float(k) * 0.8, 0.42, 0))
	# центральная дорожка со стрелками к воротам
	var steps: = int((z0 - z1) / 9.0)
	for s in range(1, steps):
		var pz: = z0 - float(s) * 9.0
		var arrow: = MeshInstance3D.new()
		var pm: = PrismMesh.new()
		pm.size = Vector3(1.4, 0.06, 1.2)
		arrow.mesh = pm
		arrow.material_override = _neon(tier_color, 0.8)
		arrow.position = Vector3(0, 0.1, pz)
		arrow.rotation_degrees = Vector3(90, 180, 0)
		add_child(arrow)
	# уличные фонари: тёплые пятна света вдоль зоны (как ночная улица)
	var lamp_head: = _neon(Color(1.0, 0.85, 0.55), 3.0)
	var lamp_z_step: = maxf((z0 - z1) / 3.0, 18.0)
	var lz: = z0 - lamp_z_step * 0.5
	while lz > z1 + 8.0:
		for side in [-1.0, 1.0]:
			var lx: float = side * (half - 6.0)
			_solid(Vector3(0.25, 5.0, 0.25), _dark(0.6), Vector3(lx, 2.5, lz))
			_mesh_box(Vector3(1.4, 0.18, 0.5), _dark(0.6), Vector3(lx - side * 0.6, 5.0, lz))
			_mesh_box(Vector3(0.8, 0.12, 0.35), lamp_head, Vector3(lx - side * 0.75, 4.9, lz))
			var sl: = SpotLight3D.new()
			sl.light_color = Color(1.0, 0.85, 0.55)
			sl.light_energy = 3.5
			sl.spot_range = 12.0
			sl.spot_angle = 50.0
			sl.position = Vector3(lx - side * 0.75, 4.8, lz)
			sl.rotation_degrees = Vector3(-90, 0, 0)
			add_child(sl)
		lz -= lamp_z_step

# ── серверы ─────────────────────────────────────────────────

func _build_nodes() -> void:
	var frontier: = GameState.frontier_zone()
	for node in GameState.grid_nodes:
		if node["zone"] > frontier:
			continue # за закрытыми воротами темно
		_build_node(node)

func _build_node(node: Dictionary) -> void:
	var root: = Node3D.new()
	root.position = node["pos"]
	add_child(root)

	var unlocked: bool = GameState.node_unlocked(node)
	var infected: bool = node["infected"]
	var boss: bool = node["boss"]
	var tier_color: Color = BOSS_COLOR if boss else TIER_COLORS[node["tier"]]
	var color: Color = tier_color
	if infected:
		color = INFECTED_COLOR
	elif not unlocked:
		color = LOCKED_COLOR

	if boss:
		# ПЕНТАГОН — пятигранная крепость
		var penta: = MeshInstance3D.new()
		var pmesh: = CylinderMesh.new()
		pmesh.top_radius = 6.0
		pmesh.bottom_radius = 7.0
		pmesh.height = 7.0
		pmesh.radial_segments = 5
		penta.mesh = pmesh
		penta.material_override = Mats.concrete(Color(0.36, 0.37, 0.4), 0.16)
		penta.position.y = 3.5
		root.add_child(penta)
		var pc: = CylinderShape3D.new()
		pc.radius = 7.0
		pc.height = 7.0
		var psb: = StaticBody3D.new()
		psb.collision_layer = 1
		var pcs: = CollisionShape3D.new()
		pcs.shape = pc
		pcs.position.y = 3.5
		psb.add_child(pcs)
		root.add_child(psb)
		_mesh_box(Vector3(13.0, 0.35, 13.0), _neon(color, 2.0), Vector3(0, 7.3, 0), root)
		var core: = MeshInstance3D.new()
		var sm: = SphereMesh.new()
		sm.radius = 1.3
		sm.height = 2.6
		core.mesh = sm
		core.material_override = _neon(color, 3.0)
		core.position.y = 9.0
		root.add_child(core)
		var light: = OmniLight3D.new()
		light.light_color = color
		light.light_energy = 3.0
		light.omni_range = 20.0
		light.position.y = 9.0
		root.add_child(light)
		var label: = Label3D.new()
		label.font_size = 72
		label.modulate = color
		label.outline_size = 12
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position.y = 12.0
		label.no_depth_test = true
		root.add_child(label)
		node_visuals[node["id"]] = {"root": root, "label": label, "core": core, "tier_color": tier_color, "core_h": 9.0}
		_refresh_node_label(node)
		return

	# обычный сервер: реалистичная стойка — металл, вентрешётки, LED, экранчик
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
	# передняя панель с юнитами
	_mesh_box(Vector3(1.5, h - 0.4, 0.06), Mats.plastic(Color(0.22, 0.24, 0.28)), Vector3(0, h * 0.5, 0.6), root)
	# вентрешётки (тёмные горизонтальные прорези)
	var vent_mat: = Mats.plastic(Color(0.1, 0.11, 0.13))
	var units: = int((h - 0.8) / 0.3)
	for k in units:
		_mesh_box(Vector3(1.3, 0.14, 0.05), vent_mat, Vector3(-0.05, 0.55 + float(k) * 0.3, 0.64), root)
	# ряды маленьких статусных LED (живой сервер, а не неон-вывеска)
	var led_on: = _neon(Color(0.25, 0.9, 0.4) if not node["infected"] else INFECTED_COLOR, 1.6)
	var led_warn: = _neon(Color(0.95, 0.6, 0.15), 1.4)
	for k in mini(units, 6):
		var mat: Material = led_on if (node["id"] + k) % 3 != 0 else led_warn
		_mesh_box(Vector3(0.05, 0.05, 0.03), mat, Vector3(0.62, 0.55 + float(k) * 0.3, 0.65), root)
	# статусный экранчик с цветом состояния
	_mesh_box(Vector3(0.62, 0.4, 0.04), _neon(color, 0.85), Vector3(0.3, h - 0.42, 0.65), root)
	# кабели сверху в лоток
	for k in 2:
		_mesh_box(Vector3(0.07, 0.5, 0.07), vent_mat, Vector3(-0.4 + float(k) * 0.25, h + 0.2, -0.3), root)
	# ядро-индикатор: небольшая сфера в рамке, без слепящего свечения
	_mesh_box(Vector3(0.5, 0.06, 0.5), Mats.metal_dark(0.35), Vector3(0, h + 0.03, 0), root)
	var core: = MeshInstance3D.new()
	var sm: = SphereMesh.new()
	sm.radius = 0.24
	sm.height = 0.48
	core.mesh = sm
	core.material_override = _neon(color, 1.2)
	core.position.y = h + 0.32
	root.add_child(core)
	# свет — только у актуальных целей (экономия: серверов много)
	if unlocked and not infected:
		var light: = OmniLight3D.new()
		light.light_color = color
		light.light_energy = 1.1
		light.omni_range = 7.0
		light.position.y = h + 0.6
		root.add_child(light)
	var label: = Label3D.new()
	label.font_size = 34
	label.modulate = color
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = h + 1.5
	label.no_depth_test = true
	root.add_child(label)
	node_visuals[node["id"]] = {"root": root, "label": label, "core": core, "tier_color": tier_color, "core_h": h + 0.5}
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
	if node["boss"]:
		label.text = "%s\nфинальный сервер · %s\n%s" % [node["name"], node["av"], status]
	else:
		label.text = "%s · %s" % [node["name"], status]

# ── бонусные точки данных ───────────────────────────────────

func _build_motes() -> void:
	var frontier: = GameState.frontier_zone()
	for z in mini(frontier + 1, GameState.grid_zones.size()):
		var zone: Dictionary = GameState.grid_zones[z]
		for i in 4:
			var pos: = Vector3(randf_range(-zone["half"] + 8.0, zone["half"] - 8.0), 1.2,
				randf_range(zone["z1"] + 8.0, zone["z0"] - 8.0))
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
	var spawn: = Vector3(0, 0.2, 22)
	if not GameState.current_node.is_empty():
		spawn = GameState.current_node["pos"] + Vector3(0, 0.2, 5)
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
		var vis: Dictionary = node_visuals[id]
		vis["core"].rotate_y(delta * 0.6)

	# код на воротах переливается
	_code_t += delta
	if _code_t > 0.35:
		_code_t = 0.0
		for g in gates:
			var new_code: = _random_code()
			for lbl in g["labels"]:
				lbl.text = new_code
			var m: StandardMaterial3D = g["mat"]
			m.albedo_color.a = clampf(m.albedo_color.a + randf_range(-0.04, 0.04), 0.08, 0.34)

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

	_update_prompt()
	if _win_shown:
		return
	hud.refresh()

func _update_prompt() -> void:
	prompt_target = {}
	if _entering:
		hud.set_prompt("▸▸ ИНЪЕКЦИЯ В СЕРВЕР…")
		return
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
	else:
		var verb: = "ШТУРМ ПЕНТАГОНА" if prompt_target["boss"] else "ВЗЛОМ СЕРВЕРА"
		hud.set_prompt("[E] %s: %s (%s · %s)" % [verb, prompt_target["name"], GameState.TIERS[prompt_target["tier"]]["short"], prompt_target["av"]])

func _unhandled_input(event: InputEvent) -> void:
	if _win_shown or _entering:
		return
	if event.is_action_pressed("pause"):
		_toggle_pause()
	elif event.is_action_pressed("evolve") and not _paused and evo_panel == null:
		_open_evolution()
	elif event.is_action_pressed("interact") and not _paused:
		if not prompt_target.is_empty() and GameState.node_unlocked(prompt_target) and not prompt_target["infected"]:
			_begin_enter(prompt_target)

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
	var target: Vector3 = node["pos"] + Vector3(0, core_y, 0)

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
	v.add_child(UIKit.label("ПЕНТАГОН ПАЛ // ГРИД ЗАРАЖЁН", 34, INFECTED_COLOR))
	v.add_child(UIKit.label("Полиморфный штамм прошёл все зоны и взломал финальный сервер.", 18, UIKit.WHITE))
	v.add_child(UIKit.label("Собрано Data Fragments: %d · Code Samples: %d · Mutagen: %d · Ghost Tokens: %d" % [
		GameState.resources["data_fragments"], GameState.resources["code_samples"],
		GameState.resources["mutagen"], GameState.resources["ghost_tokens"]], 16, UIKit.DIM))
	var btn: = UIKit.button("  НОВАЯ КАМПАНИЯ  ", 20, UIKit.TEAL)
	btn.pressed.connect(func() -> void:
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	v.add_child(btn)
	top_layer.add_child(root)
