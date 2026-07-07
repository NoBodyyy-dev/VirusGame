extends Node3D

## ПОБЕДА: белый туннель. За окнами в сияющей пустоте летают телевизоры
## с надписями «ORACLE DEAD», «WHERE LOST DATA», «GG». В конце — обычный
## вход на сервер: переход на него завершает игру.

const TUNNEL_W: = 10.0
const TUNNEL_H: = 6.0
const Z_START: = 55.0
const Z_END: = -58.0
const TV_TEXTS: = ["ORACLE DEAD", "WHERE LOST DATA", "GG"]

var player: VirusPlayer
var hud_prompt: Label
var top_layer: CanvasLayer
var _tvs: Array = []       # {node, base_y, speed, phase}
var _finished: = false
var _portal_ring: MeshInstance3D

func _ready() -> void:
	_build_environment()
	_build_tunnel()
	_build_tvs()
	_build_end_server()
	_spawn_player()
	_build_ui()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Sfx.ambient(true, 1.6)
	Sfx.play("hack_win", -4.0, 0.9)

func _build_environment() -> void:
	var env: = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.82, 0.87, 0.93)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.95, 0.97, 1.0)
	env.ambient_light_energy = 1.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.fog_enabled = true
	env.fog_light_color = Color(0.88, 0.92, 0.97)
	env.fog_density = 0.012
	env.fog_sky_affect = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 1.05
	var we: = WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun: = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 20, 0)
	sun.light_color = Color(1.0, 0.98, 0.95)
	sun.light_energy = 0.9
	add_child(sun)

func _mesh_box(size: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi: = MeshInstance3D.new()
	var bm: = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
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

func _build_tunnel() -> void:
	var white: = Mats.white_panel()
	var length: = Z_START - Z_END + 8.0
	var cz: = (Z_START + Z_END) * 0.5
	var hw: = TUNNEL_W * 0.5
	# пол и потолок
	_solid(Vector3(TUNNEL_W, 0.5, length), white, Vector3(0, -0.25, cz))
	_solid(Vector3(TUNNEL_W, 0.4, length), white, Vector3(0, TUNNEL_H + 0.2, cz))
	# световые полосы на потолке
	var strip_mat: = StandardMaterial3D.new()
	strip_mat.emission_enabled = true
	strip_mat.emission = Color(1.0, 1.0, 1.0)
	strip_mat.emission_energy_multiplier = 2.2
	strip_mat.albedo_color = Color(0.9, 0.92, 0.95)
	var z: = Z_START - 4.0
	while z > Z_END + 2.0:
		_mesh_box(Vector3(TUNNEL_W - 3.0, 0.08, 0.8), strip_mat, Vector3(0, TUNNEL_H - 0.05, z))
		z -= 8.0
	# торцы
	_solid(Vector3(TUNNEL_W, TUNNEL_H, 0.5), white, Vector3(0, TUNNEL_H * 0.5, Z_START + 3.0))
	_solid(Vector3(TUNNEL_W, TUNNEL_H, 0.5), white, Vector3(0, TUNNEL_H * 0.5, Z_END - 3.0))
	# стены: чередование панелей и окон (стекло без коллизии, но
	# невидимый коллайдер держит игрока внутри)
	var glass: = StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.85, 0.92, 1.0, 0.16)
	glass.roughness = 0.05
	glass.metallic = 0.2
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	for side in [-1.0, 1.0]:
		var wall_x: float = side * hw
		# сплошной коллайдер стены
		_collide(Vector3(0.5, TUNNEL_H, length), Vector3(wall_x, TUNNEL_H * 0.5, cz))
		var seg_z: = Z_START
		var window: = false
		while seg_z > Z_END:
			var seg_len: = minf(6.0, seg_z - Z_END)
			var seg_c: = seg_z - seg_len * 0.5
			if window:
				# рама + стекло, под и над окном — панель
				_mesh_box(Vector3(0.5, 1.2, seg_len), Mats.white_panel(), Vector3(wall_x, 0.6, seg_c))
				_mesh_box(Vector3(0.5, TUNNEL_H - 4.4, seg_len), Mats.white_panel(), Vector3(wall_x, 4.4 + (TUNNEL_H - 4.4) * 0.5, seg_c))
				_mesh_box(Vector3(0.24, 3.2, seg_len - 0.4), glass, Vector3(wall_x, 2.8, seg_c))
				for fz in [seg_c - seg_len * 0.5 + 0.15, seg_c + seg_len * 0.5 - 0.15]:
					_mesh_box(Vector3(0.4, 3.2, 0.3), Mats.white_panel(), Vector3(wall_x, 2.8, fz))
			else:
				_mesh_box(Vector3(0.5, TUNNEL_H, seg_len), Mats.white_panel(), Vector3(wall_x, TUNNEL_H * 0.5, seg_c))
			seg_z -= seg_len
			window = not window
	# титры на стенах
	_wall_text("ГРИД ОСВОБОЖДЁН", Vector3(0, 4.6, Z_START - 6.0))
	_wall_text("ВСЯ ИНФОРМАЦИЯ УКРАДЕНА", Vector3(0, 4.6, 8.0))
	_wall_text("ЯДРО РАЗРУШЕНО", Vector3(0, 4.6, -22.0))

func _wall_text(text: String, pos: Vector3) -> void:
	var l: = Label3D.new()
	l.text = text
	l.font_size = 64
	l.modulate = Color(0.45, 0.6, 0.75, 0.8)
	l.outline_size = 6
	l.position = pos
	add_child(l)

func _build_tvs() -> void:
	## летающие телевизоры за окнами
	var rng: = RandomNumberGenerator.new()
	rng.seed = 777
	for i in 16:
		var side: = -1.0 if i % 2 == 0 else 1.0
		var root: = Node3D.new()
		var base_y: = rng.randf_range(1.5, 5.0)
		root.position = Vector3(side * rng.randf_range(9.0, 20.0), base_y, rng.randf_range(Z_END, Z_START))
		add_child(root)
		# корпус, экран, ножка-антенна
		var frame: = MeshInstance3D.new()
		var fm: = BoxMesh.new()
		fm.size = Vector3(1.9, 1.3, 0.5)
		frame.mesh = fm
		frame.material_override = Mats.plastic(Color(0.2, 0.21, 0.24))
		root.add_child(frame)
		var scr_mat: = StandardMaterial3D.new()
		scr_mat.emission_enabled = true
		scr_mat.emission = Color(0.75, 0.9, 1.0)
		scr_mat.emission_energy_multiplier = 1.6
		scr_mat.albedo_color = Color(0.05, 0.08, 0.1)
		var scr: = MeshInstance3D.new()
		var sm: = BoxMesh.new()
		sm.size = Vector3(1.6, 1.0, 0.08)
		scr.mesh = sm
		scr.material_override = scr_mat
		scr.position = Vector3(0, 0, 0.26)
		root.add_child(scr)
		var lbl: = Label3D.new()
		lbl.text = TV_TEXTS[i % TV_TEXTS.size()]
		lbl.font_size = 30
		lbl.modulate = Color(0.1, 0.25, 0.4)
		lbl.outline_size = 4
		lbl.position = Vector3(0, 0, 0.33)
		root.add_child(lbl)
		# повернуть экраном к туннелю (локальный +Z → к центру)
		root.rotation.y = -PI * 0.5 if side > 0 else PI * 0.5
		for k in 2:
			var ant: = MeshInstance3D.new()
			var am: = CylinderMesh.new()
			am.top_radius = 0.02
			am.bottom_radius = 0.02
			am.height = 0.7
			ant.mesh = am
			ant.material_override = Mats.metal_dark(0.4)
			ant.position = Vector3(-0.3 + float(k) * 0.6, 0.95, 0)
			ant.rotation.z = deg_to_rad(-25.0 + float(k) * 50.0)
			root.add_child(ant)
		_tvs.append({"node": root, "base_y": base_y, "speed": rng.randf_range(1.2, 3.0), "phase": rng.randf() * TAU})

func _build_end_server() -> void:
	## обычный вход на сервер — как в начале пути. Переход = конец игры
	var pos: = Vector3(0, 0, Z_END + 3.0)
	var h: = 2.6
	_solid(Vector3(1.7, h, 1.2), Mats.metal_dark(0.45), pos + Vector3(0, h * 0.5, 0))
	_mesh_box(Vector3(1.5, h - 0.4, 0.06), Mats.plastic(Color(0.22, 0.24, 0.28)), pos + Vector3(0, h * 0.5, 0.6))
	for k in 5:
		_mesh_box(Vector3(1.3, 0.14, 0.05), Mats.plastic(Color(0.1, 0.11, 0.13)), pos + Vector3(-0.05, 0.55 + float(k) * 0.3, 0.64))
	_portal_ring = MeshInstance3D.new()
	var tor: = TorusMesh.new()
	tor.inner_radius = 1.4
	tor.outer_radius = 1.65
	_portal_ring.mesh = tor
	var ring_mat: = StandardMaterial3D.new()
	ring_mat.emission_enabled = true
	ring_mat.emission = Color("2fe6b0")
	ring_mat.emission_energy_multiplier = 2.0
	ring_mat.albedo_color = Color(0.02, 0.05, 0.05)
	_portal_ring.material_override = ring_mat
	_portal_ring.rotation.x = deg_to_rad(90.0)
	_portal_ring.position = pos + Vector3(0, 1.9, 1.6)
	add_child(_portal_ring)
	var lbl: = Label3D.new()
	lbl.text = "ВХОД НА СЕРВЕР\n[E] — конец игры"
	lbl.font_size = 40
	lbl.modulate = Color("2fe6b0")
	lbl.outline_size = 8
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = pos + Vector3(0, 4.4, 0)
	add_child(lbl)

func _spawn_player() -> void:
	player = VirusPlayer.new()
	player.position = Vector3(0, 0.3, Z_START - 2.0)
	add_child(player)

func _build_ui() -> void:
	var hud_layer: = CanvasLayer.new()
	hud_layer.layer = 1
	add_child(hud_layer)
	var root: = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(root)
	hud_prompt = UIKit.label("", 22, UIKit.WHITE)
	hud_prompt.position = Vector2(360, 780)
	hud_prompt.size = Vector2(880, 40)
	hud_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hud_prompt)
	var title: = UIKit.label("БЕЛЫЙ ТУННЕЛЬ // выход из Грида — в конце", 18, Color(0.35, 0.5, 0.6))
	title.position = Vector2(24, 20)
	root.add_child(title)
	top_layer = CanvasLayer.new()
	top_layer.layer = 10
	top_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(top_layer)

func _process(delta: float) -> void:
	if _finished:
		return
	var t: = Time.get_ticks_msec() / 1000.0
	# телевизоры плывут вдоль туннеля и покачиваются
	for tv in _tvs:
		var node: Node3D = tv["node"]
		node.position.z += tv["speed"] * delta
		if node.position.z > Z_START + 4.0:
			node.position.z = Z_END - 4.0
		node.position.y = tv["base_y"] + sin(t * 0.8 + tv["phase"]) * 0.5
		node.rotation.z = sin(t * 0.5 + tv["phase"]) * 0.08
	if _portal_ring != null:
		_portal_ring.rotate_object_local(Vector3.UP, delta * 1.2)
	# вход на сервер в конце
	var d: = player.global_position.distance_to(Vector3(0, 1.0, Z_END + 4.0))
	if d < 4.0:
		hud_prompt.text = "[E] ВОЙТИ НА СЕРВЕР — конец игры"
		if Input.is_action_just_pressed("interact"):
			_finish_game()
	else:
		hud_prompt.text = ""

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not _finished:
		Net.leave()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _finish_game() -> void:
	_finished = true
	player.control_enabled = false
	Sfx.play("layer_done")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	var root: = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim: = ColorRect.new()
	dim.color = Color(0.9, 0.94, 0.97, 0.9)
	root.add_child(UIKit.full_rect(dim))
	var center: = CenterContainer.new()
	root.add_child(UIKit.full_rect(center))
	var panel: = PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 420)
	panel.add_theme_stylebox_override("panel", UIKit.panel_box(Color("2fe6b0"), Color(0.02, 0.05, 0.06, 0.97), 2, 10, 32))
	center.add_child(panel)
	var v: = VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	v.add_child(UIKit.label("КОНЕЦ ИГРЫ", 40, Color("2fe6b0")))
	v.add_child(UIKit.label("Oracle dead · Where lost data · GG", 20, UIKit.WHITE))
	v.add_child(UIKit.label("Штамм прошёл Грид: 28 серверов, Оракул разрушен, данные украдены.", 17, UIKit.DIM))
	v.add_child(UIKit.label("Data Fragments: %d · Code Samples: %d · Mutagen: %d · Ghost Tokens: %d" % [
		GameState.resources["data_fragments"], GameState.resources["code_samples"],
		GameState.resources["mutagen"], GameState.resources["ghost_tokens"]], 16, UIKit.DIM))
	var btn: = UIKit.button("  В ГЛАВНОЕ МЕНЮ  ", 20, UIKit.TEAL)
	btn.pressed.connect(func() -> void:
		get_tree().paused = false
		Net.leave()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	v.add_child(btn)
	top_layer.add_child(root)
