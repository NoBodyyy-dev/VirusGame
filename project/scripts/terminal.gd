class_name TaskStation
extends Node3D

## Станция полевой задачи: консоль синхро-взлома, маяк захвата сектора
## или реле цепи. Прогресс приходит с хоста и отражается на экране.

var kind: = "console"     # console / zone / relay
var color: = Color("ffb454")
var title: = ""
var done: = false

var screen_mat: StandardMaterial3D
var light: OmniLight3D
var title_label: Label3D
var ring_mat: StandardMaterial3D
var _t: = 0.0
var _progress: = 0.0
var _active: = false

static func create(p_kind: String, p_color: Color, p_title: String) -> TaskStation:
	var s: = TaskStation.new()
	s.kind = p_kind
	s.color = p_color
	s.title = p_title
	return s

func _ready() -> void:
	match kind:
		"console": _build_console()
		"zone": _build_zone()
		"relay": _build_relay()
	title_label = Label3D.new()
	title_label.text = title
	title_label.font_size = 44
	title_label.modulate = color
	title_label.outline_size = 8
	title_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title_label.position.y = 2.7 if kind != "zone" else 3.4
	add_child(title_label)

func _neon(c: Color, e: = 1.8) -> StandardMaterial3D:
	var m: = StandardMaterial3D.new()
	m.albedo_color = Color(0.02, 0.03, 0.05)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m

func _build_console() -> void:
	var base: = MeshInstance3D.new()
	var base_mesh: = BoxMesh.new()
	base_mesh.size = Vector3(0.9, 1.1, 0.55)
	base.mesh = base_mesh
	var base_mat: = StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.04, 0.06, 0.09)
	base_mat.metallic = 0.6
	base_mat.roughness = 0.3
	base.material_override = base_mat
	base.position.y = 0.55
	add_child(base)

	var screen: = MeshInstance3D.new()
	var quad: = QuadMesh.new()
	quad.size = Vector2(1.2, 0.75)
	screen.mesh = quad
	screen_mat = _neon(color, 1.6)
	screen_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	screen.material_override = screen_mat
	screen.position.y = 1.6
	screen.rotation.x = deg_to_rad(-12.0)
	add_child(screen)

	# рычаг рубильника — за него и «держат» [E]
	var lever: = MeshInstance3D.new()
	var lmesh: = CylinderMesh.new()
	lmesh.top_radius = 0.05
	lmesh.bottom_radius = 0.05
	lmesh.height = 0.7
	lever.mesh = lmesh
	lever.material_override = _neon(color, 2.2)
	lever.rotation.z = deg_to_rad(35.0)
	lever.position = Vector3(0.35, 1.25, 0.25)
	add_child(lever)
	var knob: = MeshInstance3D.new()
	var kmesh: = SphereMesh.new()
	kmesh.radius = 0.11
	kmesh.height = 0.22
	knob.mesh = kmesh
	knob.material_override = _neon(Color(1.0, 0.4, 0.3), 2.6)
	knob.position = Vector3(0.55, 1.53, 0.25)
	add_child(knob)

	light = OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.8
	light.omni_range = 5.0
	light.position.y = 1.7
	add_child(light)

	var col: = StaticBody3D.new()
	col.collision_layer = 1
	var cs: = CollisionShape3D.new()
	var box: = BoxShape3D.new()
	box.size = Vector3(0.9, 1.7, 0.6)
	cs.shape = box
	cs.position.y = 0.85
	col.add_child(cs)
	add_child(col)

func _build_zone() -> void:
	# кольцо на полу + маяк в центре
	var ring: = MeshInstance3D.new()
	var tor: = TorusMesh.new()
	tor.inner_radius = 4.1
	tor.outer_radius = 4.5
	ring.mesh = tor
	ring_mat = _neon(color, 1.2)
	ring.material_override = ring_mat
	ring.position.y = 0.12
	add_child(ring)

	var beacon: = MeshInstance3D.new()
	var cyl: = CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.3
	cyl.height = 2.6
	beacon.mesh = cyl
	beacon.material_override = _neon(color, 1.6)
	beacon.position.y = 1.3
	add_child(beacon)
	screen_mat = beacon.material_override

	light = OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.6
	light.omni_range = 7.0
	light.position.y = 2.4
	add_child(light)

func _build_relay() -> void:
	var post: = MeshInstance3D.new()
	var cyl: = CylinderMesh.new()
	cyl.top_radius = 0.16
	cyl.bottom_radius = 0.28
	cyl.height = 1.7
	post.mesh = cyl
	var pm: = StandardMaterial3D.new()
	pm.albedo_color = Color(0.05, 0.07, 0.1)
	pm.metallic = 0.6
	post.material_override = pm
	post.position.y = 0.85
	add_child(post)

	var orb: = MeshInstance3D.new()
	var sm: = SphereMesh.new()
	sm.radius = 0.26
	sm.height = 0.52
	orb.mesh = sm
	screen_mat = _neon(color, 1.4)
	orb.material_override = screen_mat
	orb.position.y = 1.95
	add_child(orb)

	light = OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.2
	light.omni_range = 4.5
	light.position.y = 1.9
	add_child(light)

func _process(delta: float) -> void:
	_t += delta
	if done or screen_mat == null:
		return
	var pulse: = 1.2 + 0.5 * sin(_t * (5.0 if _active else 2.2))
	screen_mat.emission_energy_multiplier = pulse + _progress * 1.6

func set_progress(p: float) -> void:
	_progress = clampf(p, 0.0, 1.0)

func set_active(on: bool) -> void:
	_active = on

func set_caption(text: String) -> void:
	if not done:
		title_label.text = text

func set_done() -> void:
	done = true
	var green: = Color(0.25, 1.0, 0.55)
	if screen_mat:
		screen_mat.emission = green
		screen_mat.emission_energy_multiplier = 1.2
	if ring_mat:
		ring_mat.emission = green
	if light:
		light.light_color = green
		light.light_energy = 1.0
	title_label.modulate = green
	title_label.text = "%s\n// ВЫПОЛНЕНО" % title
