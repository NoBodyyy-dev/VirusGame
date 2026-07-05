extends Node3D

## PANIC PROTOCOL — узел как ограбление:
## тащи физический лут в портал, не буди систему, эвакуируйся до СТИРАНИЯ.
## Хост владеет: физикой лута, стражами, тревогой, HP, эвакуацией.

const MG_SCRIPTS: = {
	"logic_gates": preload("res://scripts/minigames/logic_gates.gd"),
	"sequence_recall": preload("res://scripts/minigames/sequence_recall.gd"),
	"freq_lock": preload("res://scripts/minigames/freq_lock.gd"),
	"pulse_sync": preload("res://scripts/minigames/pulse_sync.gd"),
	"overload_hold": preload("res://scripts/minigames/overload_hold.gd"),
	"packet_route": preload("res://scripts/minigames/packet_route.gd"),
	"cipher_wheel": preload("res://scripts/minigames/cipher_wheel.gd"),
	"log_wipe": preload("res://scripts/minigames/log_wipe.gd"),
	"signature_match": preload("res://scripts/minigames/signature_match.gd"),
	"hash_crack": preload("res://scripts/minigames/hash_crack.gd"),
	"ring_polarity": preload("res://scripts/minigames/ring_polarity.gd"),
}
const HUDScript: = preload("res://scripts/hud.gd")
const BriefScript: = preload("res://scripts/brief_ui.gd")
const ResultsScript: = preload("res://scripts/results_ui.gd")

const HALL: = Vector2(70.0, 46.0)
const PAD_POS: = Vector3(-27.0, 0.0, 0.0)
const PAD_RADIUS: = 3.6
const COOLER_POS: = Vector3(-2.0, 0.0, 16.0)
const SAFE_SPOTS: = [Vector3(15, 0, 12), Vector3(27, 0, -9), Vector3(-23, 0, -13)]
const CRATE_SPOTS: = [
	Vector3(25, 0.7, -11), Vector3(19, 0.7, 15), Vector3(-7, 0.7, -17),
	Vector3(7, 0.7, 18), Vector3(29, 0.7, 5), Vector3(12, 0.7, -18),
]
const REVIVE_TIME: = 3.0
const COOLER_TIME: = 2.6

var player: VirusPlayer
var enemies: = {}            # eid -> Antivirus
var loots: = {}              # lid -> LootItem
var safes: Array = []        # HackTerminal
var portal: Node3D
var portal_ring_mat: StandardMaterial3D
var portal_light: OmniLight3D
var pad_mat: StandardMaterial3D
var cooler: Node3D
var cooler_label: Label3D
var cooler_charges: = 3
var env: Environment
var is_boss: = false

var hud_layer: CanvasLayer
var mg_layer: CanvasLayer
var top_layer: CanvasLayer
var hud: Control
var pause_panel: Control

var minigame: MinigameBase
var current_safe: HackTerminal
var safe_fails: = 0
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
var busy_safes: = {}
var busy_view: Array = []
var _enemy_sync: = 0.0
var _loot_sync: = 0.0
var _host_hp: = {}            # id -> hp (владеет хост; для соло — {1: hp})
var _revive_t: = {}           # id -> прогресс реанимации на паде
var _cooler_hold: = 0.0
var _demo_timer: = 0.0
var _demo_grab_cd: = 0.0

func _ready() -> void:
	if GameState.node_config.is_empty():
		if GameState.grid_nodes.is_empty():
			GameState.new_campaign(GameState.selected_class)
		GameState.start_hack(GameState.grid_nodes[0])
	is_boss = GameState.node_config.get("boss", false)
	_build_environment()
	_build_arena()
	_build_platforms()
	_build_portal_and_pad()
	_build_cooler()
	_spawn_player()
	_spawn_safes()
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
	_spawn_enemy("SCANNER", Vector3(0, 2.3, -9))
	if is_boss:
		_spawn_enemy("SCANNER", Vector3(8, 2.3, 9))

# ── окружение (стиль сохранён) ──────────────────────────────

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
	_fog_base = Color(0.55, 0.25, 0.3) if is_boss else Color(0.35, 0.65, 0.8)
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

func _build_arena() -> void:
	var floor_mesh: = MeshInstance3D.new()
	var plane: = PlaneMesh.new()
	plane.size = HALL
	floor_mesh.mesh = plane
	var fmat: = ShaderMaterial.new()
	fmat.shader = load("res://shaders/floor_grid.gdshader")
	var tier: int = GameState.node_config.get("difficulty", 0)
	var tier_cols: = [Vector3(0.08, 0.75, 0.95), Vector3(0.85, 0.6, 0.2), Vector3(0.9, 0.3, 0.5), Vector3(0.5, 0.3, 0.95)]
	fmat.set_shader_parameter("line_col", Vector3(0.9, 0.15, 0.25) if is_boss else tier_cols[tier])
	floor_mesh.material_override = fmat
	add_child(floor_mesh)
	_collider(Vector3(HALL.x, 0.5, HALL.y), Vector3(0, -0.25, 0))

	var wall_mat: = _dark_mat()
	var trim_color: = Color(0.7, 0.12, 0.2) if is_boss else Color(0.12, 0.55, 0.75)
	var trim_mat: = _neon_mat(trim_color, 1.1)
	var hx: = HALL.x * 0.5
	var hz: = HALL.y * 0.5
	for side in [
		{"size": Vector3(HALL.x, 6, 0.6), "pos": Vector3(0, 3, -hz)},
		{"size": Vector3(HALL.x, 6, 0.6), "pos": Vector3(0, 3, hz)},
		{"size": Vector3(0.6, 6, HALL.y), "pos": Vector3(-hx, 3, 0)},
		{"size": Vector3(0.6, 6, HALL.y), "pos": Vector3(hx, 3, 0)},
	]:
		_box(side["size"], wall_mat, side["pos"])
		_collider(side["size"], side["pos"])
		var trim_size: Vector3 = side["size"]
		trim_size.y = 0.08
		var trim_pos: Vector3 = side["pos"]
		trim_pos.y = 2.6
		_box(trim_size * Vector3(1.0, 1.0, 1.02), trim_mat, trim_pos)

	var rack_mat: = _dark_mat()
	var strip_colors: = [Color(0.15, 0.7, 0.9), Color(0.12, 0.8, 0.6), Color(0.45, 0.3, 0.9)]
	if is_boss:
		strip_colors = [Color(0.9, 0.2, 0.3), Color(0.7, 0.15, 0.4)]
	for rz in [-14.0, -5.0, 5.0, 14.0]:
		for rx in range(-26, 27, 6):
			if absf(float(rx)) < 4.0 or randf() < 0.22:
				continue
			var pos: = Vector3(float(rx), 1.3, rz)
			var skip: = false
			for spot in SAFE_SPOTS:
				if pos.distance_to(Vector3(spot.x, 1.3, spot.z)) < 3.5:
					skip = true
			if pos.distance_to(Vector3(COOLER_POS.x, 1.3, COOLER_POS.z)) < 3.5:
				skip = true
			if pos.distance_to(Vector3(-30, 1.3, 0)) < 6.5 or (pos.x < -14.0 and absf(pos.z) < 4.0):
				skip = true
			if skip:
				continue
			_box(Vector3(2.4, 2.6, 1.2), rack_mat, pos)
			_collider(Vector3(2.4, 2.6, 1.2), pos)
			var sc: Color = strip_colors.pick_random()
			_box(Vector3(2.3, 0.06, 0.06), _neon_mat(sc, 1.5), pos + Vector3(0, 0.7, 0.64))
			_box(Vector3(2.3, 0.06, 0.06), _neon_mat(sc * 0.8, 1.1), pos + Vector3(0, -0.4, 0.64))
			# ящик-ступень рядом с частью стоек — паркур на крышу
			if randf() < 0.35:
				var cpos: = pos + Vector3(randf_range(-1.0, 1.0), -0.65, 1.6)
				_box(Vector3(1.4, 1.3, 1.4), rack_mat, cpos)
				_collider(Vector3(1.4, 1.3, 1.4), cpos)

	for i in 16:
		var p: = Vector3(randf_range(-hx + 3, hx - 3), 2.6, randf_range(-hz + 3, hz - 3))
		var c: = Color(0.1, randf_range(0.5, 0.8), randf_range(0.7, 1.0))
		_box(Vector3(0.05, randf_range(2.5, 5.0), 0.05), _neon_mat(c, randf_range(0.5, 1.1)), p)

var _plat_spots: Array = []

func _build_platforms() -> void:
	# парящие платформы: наверху лежит лут — прыжки окупаются
	var plat_mat: = _dark_mat()
	var glow: = _neon_mat(Color(0.16, 0.95, 0.75) if not is_boss else Color(0.9, 0.25, 0.3), 1.4)
	var spots: = [
		{"pos": Vector3(-18, 1.6, -18), "size": Vector3(3.4, 0.35, 3.4)},
		{"pos": Vector3(-13, 3.0, -20), "size": Vector3(2.8, 0.35, 2.8)},
		{"pos": Vector3(-7, 4.3, -19), "size": Vector3(2.4, 0.35, 2.4)},
		{"pos": Vector3(20, 1.7, 16), "size": Vector3(3.2, 0.35, 3.2)},
		{"pos": Vector3(25, 3.2, 12), "size": Vector3(2.6, 0.35, 2.6)},
		{"pos": Vector3(6, 1.8, -2), "size": Vector3(2.8, 0.35, 2.8)},
	]
	for s in spots:
		_box(s["size"], plat_mat, s["pos"])
		_collider(s["size"], s["pos"])
		var trim: Vector3 = s["size"]
		trim.y = 0.06
		_box(trim * Vector3(1.05, 1.0, 1.05), glow, s["pos"] + Vector3(0, s["size"].y * 0.5, 0))
		_plat_spots.append(s["pos"] + Vector3(0, s["size"].y * 0.5 + 0.6, 0))

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
	cooler.position = COOLER_POS
	add_child(cooler)
	_box(Vector3(1.4, 1.8, 1.0), _dark_mat(), Vector3(0, 0.9, 0), cooler)
	_collider(Vector3(1.4, 1.8, 1.0), COOLER_POS + Vector3(0, 0.9, 0))
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

func _spawn_safes() -> void:
	var cfg_safes: Array = GameState.node_config.get("safes", [])
	for i in cfg_safes.size():
		var t: = HackTerminal.new()
		t.setup(cfg_safes[i])
		t.position = SAFE_SPOTS[i % SAFE_SPOTS.size()]
		t.rotation.y = randf_range(0.0, TAU)
		add_child(t)
		safes.append(t)

func _build_particles() -> void:
	var parts: = GPUParticles3D.new()
	parts.amount = 220
	parts.lifetime = 9.0
	parts.preprocess = 5.0
	var pm: = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(HALL.x * 0.5, 3.5, HALL.y * 0.5)
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

	mg_layer = CanvasLayer.new()
	mg_layer.layer = 5
	add_child(mg_layer)

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

func _update_objective() -> void:
	if GameState.evac_open:
		hud.set_objective("ЭВАКУАЦИЯ: все в круг у портала!")
	else:
		hud.set_objective("%s (%s) · вынести ◈ на %d%%" % [
			GameState.node_config["name"], GameState.node_config["tier_short"], 100])

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
	Net.safe_state.connect(_on_safe_state)
	Net.hack_finished.connect(_on_net_finished)
	Net.net_toast.connect(_on_net_toast)
	Net.claim_denied.connect(_on_claim_denied)
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
		for idx in busy_safes.keys():
			if busy_safes[idx] == id:
				busy_safes.erase(idx)
		_broadcast_safe_state()

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
			pos = Vector3(randf_range(-24, 30), 0.7, randf_range(-19, 19))
			if pos.distance_to(PAD_POS) < 8.0:
				pos.x = absf(pos.x) # не спавнить прямо у портала
		items.append(_make_loot_data("file", pos))
	var cspots: = CRATE_SPOTS.duplicate()
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
	GameState.apply_alarm(amount, "noise", Net.my_class_of(sender) if Net.active else GameState.selected_class)
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
	GameState.apply_alarm(-15.0, "cooler", Net.my_class_of(sender) if Net.active else GameState.selected_class)
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

# ── хост: сейфы ─────────────────────────────────────────────

func server_claim_safe(idx: int, claim: bool, sender: int) -> void:
	if claim:
		if busy_safes.get(idx, sender) != sender:
			Net.deny_claim(sender, idx)
			return
		busy_safes[idx] = sender
	elif busy_safes.get(idx, 0) == sender:
		busy_safes.erase(idx)
	_broadcast_safe_state()

func server_safe_done(idx: int, perfect: bool, sender: int) -> void:
	var cfg_safes: Array = GameState.node_config["safes"]
	if idx < 0 or idx >= cfg_safes.size() or cfg_safes[idx]["done"]:
		return
	cfg_safes[idx]["done"] = true
	busy_safes.erase(idx)
	Net.score_event(sender, "safe")
	GameState.apply_alarm(4.0, "safe", "worm")
	# сейф выплёвывает эпик-лут
	var pos: Vector3 = safes[idx].global_position + Vector3(randf_range(-1.5, 1.5), 1.2, randf_range(-1.5, 1.5))
	var data: = _make_loot_data("epic", pos)
	_spawn_loot_local(data, false)
	var msg: = "💰 %s вскрыл %s — выпал «%s»!" % [Net.player_name(sender), cfg_safes[idx]["title"], data["name"]]
	if Net.active:
		Net.send_loot_add(data)
		Net.toast_all(msg, Color("ffd166"))
	else:
		hud.toast(msg, Color("ffd166"))
	if perfect:
		GameState.stats["perfect_safes"] += 0 # локальная стата взломщика начисляется на его пире
	_broadcast_safe_state()

func _broadcast_safe_state() -> void:
	var cfg_safes: Array = GameState.node_config["safes"]
	var dones: Array = []
	var busy: Array = []
	for i in cfg_safes.size():
		dones.append(cfg_safes[i]["done"])
		busy.append(busy_safes.get(i, 0))
	if Net.active:
		Net.send_safe_state(dones, busy)
	else:
		_on_safe_state(dones, busy)

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

func _on_safe_state(dones: Array, busy: Array) -> void:
	busy_view = busy
	for i in mini(dones.size(), safes.size()):
		var t: HackTerminal = safes[i]
		if dones[i]:
			if not t.done:
				t.set_done()
				t.layer["done"] = true
		else:
			var holder: int = busy[i] if i < busy.size() else 0
			t.set_busy_name(Net.player_name(holder) if holder != 0 and holder != Net.my_id() else "")

func _on_claim_denied(idx: int) -> void:
	if minigame != null and current_safe != null and _safe_index(current_safe) == idx:
		hud.toast("этот сейф уже ковыряет другой штамм!", UIKit.AMBER)
		minigame.abort()

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
		f = 0.6 if GameState.selected_class == "ransomware" and it.carriers.size() == 1 else 0.66
	if GameState.selected_class == "worm":
		f += 0.08
	if GameState.mutation_owned("chain_master"):
		f = 1.0 - (1.0 - f) * 0.5
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

func _nearest_safe() -> HackTerminal:
	for t in safes:
		if t.done:
			continue
		if player.global_position.distance_to(t.global_position) < 2.9:
			return t
	return null

func _safe_index(t: HackTerminal) -> int:
	return safes.find(t)

func _handle_interactions(delta: float) -> void:
	if minigame != null or phase == "done":
		return
	var prompt: = ""
	var carried: = my_carried_item()

	if GameState.my_bug:
		var d: = player.global_position.distance_to(PAD_POS)
		if d < PAD_RADIUS:
			prompt = "реанимация у портала… держись в круге!"
		else:
			prompt = "ты — БАГ: скачи в круг у портала (%dм) или жди Botnet" % int(d)
		hud.show_prompt(prompt)
		return

	if carried != null:
		if _carry_strength(carried.carriers) < carried.weight:
			prompt = "«%s» тяжёлый: нужен второй! [E] бросить" % carried.loot_name
		else:
			prompt = "неси «%s» в круг у портала · [F] бросить" % carried.loot_name
	else:
		var it: = _nearest_free_loot(2.7)
		var safe: = _nearest_safe()
		if it != null:
			if it.weight > 1 and not it.carriers.is_empty():
				prompt = "[E] подхватить «%s» (вас будет %d/%d)" % [it.loot_name, it.carriers.size() + 1, it.weight]
			elif it.weight > _my_strength():
				prompt = "[E] взяться за «%s» — нужно %d носильщика" % [it.loot_name, it.weight]
			else:
				prompt = "[E] схватить «%s» (◈ %d)" % [it.loot_name, roundi(it.value)]
		elif safe != null:
			var idx: = _safe_index(safe)
			var holder: = _busy_holder(idx)
			if holder != 0 and holder != Net.my_id():
				prompt = "сейф уже ковыряет %s" % Net.player_name(holder)
			else:
				prompt = "[E] вскрыть %s → %s" % [safe.layer["title"], GameState.MINIGAMES[safe.layer["game"]]["title"]]
		elif cooler_charges > 0 and player.global_position.distance_to(COOLER_POS) < 2.8:
			if Input.is_action_pressed("interact"):
				_cooler_hold += delta
				prompt = "охлаждение… %d%%" % int(_cooler_hold / COOLER_TIME * 100.0)
				if _cooler_hold >= COOLER_TIME:
					_cooler_hold = 0.0
					_use_cooler()
			else:
				_cooler_hold = 0.0
				prompt = "[E держать] КУЛЕР: тревога −15 (зарядов: %d)" % cooler_charges

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
				var safe: = _nearest_safe()
				if safe != null:
					var idx: = _safe_index(safe)
					var holder: = _busy_holder(idx)
					if holder == 0 or holder == Net.my_id():
						_open_safe(safe)

func _my_strength() -> int:
	return 2 if GameState.selected_class == "ransomware" else 1

func _busy_holder(idx: int) -> int:
	if idx >= 0 and idx < busy_view.size():
		return busy_view[idx]
	return 0

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
		if minigame != null:
			minigame.abort()
		else:
			_toggle_pause()
	elif event.is_action_pressed("ability") and not _paused_by_menu and minigame == null:
		_use_ability()
	elif event.is_action_pressed("throw") and minigame == null and not _paused_by_menu:
		var it: = my_carried_item()
		if it != null and _carry_strength(it.carriers) >= it.weight:
			_request_release(it, true)
	elif event.is_action_pressed("zeroday") and minigame != null:
		if GameState.use_zero_day():
			Sfx.play("chain", 0.0, 0.8)
			minigame.force_layer_success()
		else:
			hud.toast("нет 0-day эксплойтов — крафт в Гриде [Tab]", UIKit.DIM)

func _toggle_pause() -> void:
	_paused_by_menu = not _paused_by_menu
	if Net.active:
		if minigame == null:
			player.control_enabled = not _paused_by_menu
	else:
		get_tree().paused = _paused_by_menu
	pause_panel.visible = _paused_by_menu
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if (_paused_by_menu or minigame != null) else Input.MOUSE_MODE_CAPTURED

# ── сейфы (мини-игры) ───────────────────────────────────────

func _open_safe(safe: HackTerminal) -> void:
	current_safe = safe
	safe_fails = 0
	var idx: = _safe_index(safe)
	if Net.active:
		if Net.is_server():
			server_claim_safe(idx, true, 1)
		else:
			Net.srv_claim_safe.rpc_id(1, idx, true)
	var script: GDScript = MG_SCRIPTS[safe.layer["game"]]
	minigame = script.new()
	var diff: int = GameState.node_config.get("difficulty", 1)
	minigame.setup(safe.layer, diff)
	minigame.round_result.connect(_on_round_result)
	minigame.finished.connect(_on_minigame_finished)
	mg_layer.add_child(minigame)
	player.control_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_round_result(success: bool) -> void:
	if not success:
		safe_fails += 1
		var spike: = randf_range(7.0, 11.0)
		GameState.add_alarm(spike, "fail")
		Net.send_noise(2.0, player.global_position)
		player.shake(0.25)

func _on_minigame_finished(success: bool) -> void:
	var safe: = current_safe
	current_safe = null
	if minigame != null:
		minigame.queue_free()
		minigame = null
	player.control_enabled = true
	if not _paused_by_menu and phase != "done":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if safe == null:
		return
	var idx: = _safe_index(safe)
	if success:
		GameState.stats["safes"] += 1
		if safe_fails == 0:
			GameState.stats["perfect_safes"] += 1
		if Net.active and not Net.is_server():
			Net.srv_safe_done.rpc_id(1, idx, safe_fails == 0)
		else:
			server_safe_done(idx, safe_fails == 0, Net.my_id())
	else:
		if Net.active and not Net.is_server():
			Net.srv_claim_safe.rpc_id(1, idx, false)
		else:
			server_claim_safe(idx, false, Net.my_id())

# ── активки ─────────────────────────────────────────────────

func _use_ability() -> void:
	if GameState.my_bug:
		hud.toast("ты баг. у багов нет активок. у багов есть только писк", UIKit.DIM)
		return
	if ability_cd > 0.0:
		hud.toast("активка перезаряжается", UIKit.DIM)
		return
	var cls: = GameState.selected_class
	var info: Dictionary = GameState.class_info()
	if not GameState.try_spend_bw(float(info["cost"])):
		hud.toast("недостаточно Bandwidth", UIKit.MAGENTA)
		return
	Sfx.play("ability")
	var remote_client: = Net.active and not Net.is_server()
	match cls:
		"trojan":
			player.set_morph(true)
			Net.send_morph(true)
			hud.toast("ЛОЖНЫЙ ФАЙЛ: замри — и ты мебель. Движение снимает морф", UIKit.CYAN)
		"worm":
			player.dash()
			hud.toast("РЫВОК!", UIKit.TEAL)
		"ransomware":
			if remote_client:
				Net.srv_enemy_effect.rpc_id(1, "freeze", 3.0, Vector3.ZERO)
			else:
				apply_enemy_effect("freeze", 3.0, Vector3.ZERO)
			hud.toast("ШИФРОВАНИЕ: все стражи заморожены (3с)", UIKit.MAGENTA)
		"spyware":
			Net.send_xray()
			hud.toast("СКАН: лут и стражи подсвечены всей команде (6с)", UIKit.AMBER)
		"adware":
			var pos: = player.global_position + player.look_dir() * 4.0
			if remote_client:
				Net.srv_enemy_effect.rpc_id(1, "decoy", 5.0, Vector3(pos.x, 2.3, pos.z))
			else:
				apply_enemy_effect("decoy", 5.0, Vector3(pos.x, 2.3, pos.z))
			_spawn_decoy_ghost(pos)
			hud.toast("ФАНТОМ: стражи ведутся (5с)", UIKit.AMBER)
		"rootkit":
			GameState.add_alarm(-12.0, "wipe")
			hud.toast("ГЛУШИЛКА: тревога −12", UIKit.VIOLET)
		"botnet":
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
	if minigame != null:
		minigame.abort()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var results: Control = ResultsScript.new()
	top_layer.add_child(results)
	results.show_result(victory, reason)
