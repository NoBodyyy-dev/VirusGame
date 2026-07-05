class_name VirusModel
extends Node3D

## Уникальное процедурное тело для каждого класса вируса.
## Полиморфный визуал: evolve_stage (0..2) добавляет детали по мере прокачки.

var cls: = "worm"
var color: = Color(0.2, 0.85, 1.0)
var move_ratio: = 0.0
var evolve_stage: = 0

var _t: = randf() * 10.0
var _spin: Array = []
var _orbit: Array = []
var _segments: Array = []
var _breath_node: Node3D
var _mask: Node3D
var _shackle: Node3D
var _pupil: Node3D
var _eye_root: Node3D
var _stalks: Array = []
var _popups: Array = []
var _drill: Node3D

static func create(p_cls: String, p_color: Color, p_stage: = 0) -> VirusModel:
	var m: = VirusModel.new()
	m.cls = p_cls
	m.color = p_color
	m.evolve_stage = p_stage
	return m

static func create_bug(p_color: Color) -> Node3D:
	## «баг»: глючный пищащий краб — форма игрока при 0 HP
	var root: = Node3D.new()
	var body: = MeshInstance3D.new()
	var bm: = BoxMesh.new()
	bm.size = Vector3(0.5, 0.32, 0.42)
	body.mesh = bm
	var mat: = StandardMaterial3D.new()
	mat.albedo_color = Color(0.04, 0.05, 0.08)
	mat.emission_enabled = true
	mat.emission = p_color * 0.7
	mat.emission_energy_multiplier = 1.4
	body.material_override = mat
	body.position.y = 0.35
	root.add_child(body)
	# выпученные глаза — паника в чистом виде
	for side in [-1.0, 1.0]:
		var eye: = MeshInstance3D.new()
		var sm: = SphereMesh.new()
		sm.radius = 0.09
		sm.height = 0.18
		eye.mesh = sm
		var em: = StandardMaterial3D.new()
		em.emission_enabled = true
		em.emission = Color.WHITE
		em.emission_energy_multiplier = 3.0
		eye.material_override = em
		eye.position = Vector3(side * 0.13, 0.52, -0.18)
		root.add_child(eye)
		var pupil: = MeshInstance3D.new()
		var pm: = SphereMesh.new()
		pm.radius = 0.04
		pm.height = 0.08
		pupil.mesh = pm
		var pmat: = StandardMaterial3D.new()
		pmat.albedo_color = Color(0.02, 0.02, 0.03)
		pupil.material_override = pmat
		pupil.position = Vector3(side * 0.13, 0.52, -0.26)
		root.add_child(pupil)
	# лапки
	for i in 3:
		for side in [-1.0, 1.0]:
			var leg: = MeshInstance3D.new()
			var lm: = BoxMesh.new()
			lm.size = Vector3(0.22, 0.04, 0.04)
			leg.mesh = lm
			var lmat: = StandardMaterial3D.new()
			lmat.emission_enabled = true
			lmat.emission = p_color
			lmat.emission_energy_multiplier = 1.6
			leg.material_override = lmat
			leg.position = Vector3(side * 0.32, 0.2, -0.12 + 0.14 * float(i))
			leg.rotation.z = deg_to_rad(-30.0 * side)
			root.add_child(leg)
	var lbl: = Label3D.new()
	lbl.text = "SEGFAULT"
	lbl.font_size = 26
	lbl.modulate = Color(1.0, 0.35, 0.4)
	lbl.outline_size = 8
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position.y = 0.95
	root.add_child(lbl)
	return root

static func create_crate() -> Node3D:
	## ящик-маскировка трояна: неотличим от обычного лута
	var root: = Node3D.new()
	var body: = MeshInstance3D.new()
	var bm: = BoxMesh.new()
	bm.size = Vector3(1.0, 0.85, 0.9)
	body.mesh = bm
	var mat: = StandardMaterial3D.new()
	mat.albedo_color = Color(0.04, 0.06, 0.09)
	mat.metallic = 0.5
	mat.roughness = 0.35
	mat.emission_enabled = true
	mat.emission = Color("4a90ff")
	mat.emission_energy_multiplier = 0.9
	body.material_override = mat
	body.position.y = 0.45
	root.add_child(body)
	var lbl: = Label3D.new()
	lbl.text = "точно_не_вирус.box\n◈ 18"
	lbl.font_size = 30
	lbl.modulate = Color("4a90ff")
	lbl.outline_size = 8
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position.y = 1.35
	root.add_child(lbl)
	return root

func _ready() -> void:
	match cls:
		"worm": _build_worm()
		"trojan": _build_trojan()
		"ransomware": _build_ransomware()
		"spyware": _build_spyware()
		"adware": _build_adware()
		"rootkit": _build_rootkit()
		"botnet": _build_botnet()
		_: _build_worm()

# ── материалы ──────────────────────────────────────────────

func _holo_mat(c: Color, brightness: = 1.4) -> ShaderMaterial:
	var sh: = ShaderMaterial.new()
	sh.shader = load("res://shaders/hologram.gdshader")
	sh.set_shader_parameter("col", Vector3(c.r, c.g, c.b))
	sh.set_shader_parameter("brightness", brightness)
	return sh

func _core_mat(c: Color, energy: = 3.0) -> StandardMaterial3D:
	var m: = StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.08, 0.1)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m

func _dark_mat(metal: = 0.7) -> StandardMaterial3D:
	var m: = StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.06, 0.09)
	m.metallic = metal
	m.roughness = 0.3
	return m

func _mesh(mesh: Mesh, mat: Material, pos: Vector3, parent: Node3D = self) -> MeshInstance3D:
	var mi: = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _sphere(r: float, mat: Material, pos: Vector3, parent: Node3D = self) -> MeshInstance3D:
	var sm: = SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	return _mesh(sm, mat, pos, parent)

func _box(size: Vector3, mat: Material, pos: Vector3, parent: Node3D = self) -> MeshInstance3D:
	var bm: = BoxMesh.new()
	bm.size = size
	return _mesh(bm, mat, pos, parent)

func _torus(inner: float, outer: float, mat: Material, pos: Vector3, parent: Node3D = self) -> MeshInstance3D:
	var tm: = TorusMesh.new()
	tm.inner_radius = inner
	tm.outer_radius = outer
	return _mesh(tm, mat, pos, parent)

func _cone(bottom: float, height: float, mat: Material, pos: Vector3, parent: Node3D = self) -> MeshInstance3D:
	var cm: = CylinderMesh.new()
	cm.top_radius = 0.005
	cm.bottom_radius = bottom
	cm.height = height
	return _mesh(cm, mat, pos, parent)

func _spikes(parent: Node3D, r: float, count: int, len: float, c: Color) -> void:
	## шипы-рецепторы по сфере — классический «вирионный» силуэт
	for i in count:
		var dir: = Vector3(randf_range(-1, 1), randf_range(-0.6, 1), randf_range(-1, 1)).normalized()
		var sp: = _cone(len * 0.22, len, _core_mat(c, 1.8), dir * (r + len * 0.4), parent)
		sp.look_at_from_position(sp.position, sp.position + dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT)
		sp.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))
		# светящийся узелок на конце шипа
		_sphere(len * 0.16, _core_mat(c.lightened(0.3), 2.6), dir * (r + len * 0.95), parent)

# ── ЧЕРВЬ: членистый бур-паразит, извивается и гребёт ресничками ──

func _build_worm() -> void:
	var head: = Node3D.new()
	head.position.y = 0.95
	add_child(head)
	_breath_node = head
	# голова-капсула с пластинами
	_sphere(0.34, _holo_mat(color), Vector3.ZERO, head)
	_torus(0.28, 0.36, _core_mat(color, 1.4), Vector3(0, 0.05, 0.05), head).rotation.x = deg_to_rad(78.0)
	# вращающийся бур
	_drill = Node3D.new()
	_drill.position = Vector3(0, 0.0, -0.42)
	head.add_child(_drill)
	var drill_mesh: = CylinderMesh.new()
	drill_mesh.top_radius = 0.02
	drill_mesh.bottom_radius = 0.24
	drill_mesh.height = 0.6
	var d: = _mesh(drill_mesh, _core_mat(color, 2.2), Vector3.ZERO, _drill)
	d.rotation.x = deg_to_rad(-90.0)
	# спиральная резьба бура
	for k in 3:
		var thread: = _torus(0.06 + 0.05 * k, 0.09 + 0.05 * k, _core_mat(color.lightened(0.25), 2.8), Vector3(0, 0, -0.05 - 0.12 * k), _drill)
		thread.rotation.x = deg_to_rad(90.0)
	# усики-антенны
	for side in [-1.0, 1.0]:
		var ant: = _cone(0.03, 0.35, _core_mat(color, 2.2), Vector3(side * 0.18, 0.3, -0.15), head)
		ant.rotation.z = deg_to_rad(-28.0 * side)
	# глазки
	for side in [-1.0, 1.0]:
		_sphere(0.07, _core_mat(Color.WHITE.lerp(color, 0.3), 4.0), Vector3(side * 0.16, 0.12, -0.28), head)
	# сегменты хвоста с ресничками
	var count: = 5 + evolve_stage
	for i in count:
		var seg_root: = Node3D.new()
		seg_root.position = Vector3(0, 0.95 - 0.05 * float(i), 0.42 + 0.38 * float(i))
		add_child(seg_root)
		var r: = 0.27 - 0.03 * float(i)
		_sphere(r, _holo_mat(color, 1.15 - 0.12 * float(i)), Vector3.ZERO, seg_root)
		var band: = _torus(r * 0.8, r * 1.02, _core_mat(color, 1.7), Vector3.ZERO, seg_root)
		band.rotation.x = deg_to_rad(90.0)
		# реснички-лапки по бокам
		for side in [-1.0, 1.0]:
			var cil: = _cone(0.025, r * 1.1, _core_mat(color * 0.85, 1.3), Vector3(side * r * 0.95, -r * 0.4, 0), seg_root)
			cil.rotation.z = deg_to_rad(-125.0 * side)
		_segments.append(seg_root)

# ── ТРОЯН: шахматный конь с дрейфующей маской ──

func _build_trojan() -> void:
	# постамент-призма
	var prism: = PrismMesh.new()
	prism.size = Vector3(0.66, 1.1, 0.55)
	var body: = _mesh(prism, _holo_mat(color, 1.2), Vector3(0, 0.72, 0))
	body.rotation.y = PI
	_breath_node = body
	_sphere(0.13, _core_mat(color, 3.5), Vector3(0, 0.8, 0))
	# шея коня — наклонённый блок
	var neck: = _box(Vector3(0.3, 0.62, 0.34), _dark_mat(0.85), Vector3(0, 1.42, 0.02))
	neck.rotation.x = deg_to_rad(-16.0)
	# голова — вытянутая морда вперёд
	var head: = _box(Vector3(0.26, 0.24, 0.56), _dark_mat(0.85), Vector3(0, 1.74, -0.16))
	head.rotation.x = deg_to_rad(8.0)
	# уши
	for side in [-1.0, 1.0]:
		var ear: = _cone(0.05, 0.16, _core_mat(color, 2.0), Vector3(side * 0.08, 1.9, 0.02))
		ear.rotation.x = deg_to_rad(-10.0)
	# грива — светящиеся пластины по шее
	for k in 4:
		_box(Vector3(0.05, 0.16, 0.1), _core_mat(color, 2.2), Vector3(0, 1.36 + 0.14 * k, 0.2 - 0.03 * k))
	# маска: щит с прорезями, дрейфует перед мордой (обман)
	_mask = Node3D.new()
	_mask.position = Vector3(0, 1.72, -0.52)
	add_child(_mask)
	var plate: = BoxMesh.new()
	plate.size = Vector3(0.4, 0.44, 0.05)
	_mesh(plate, _holo_mat(color, 1.6), Vector3.ZERO, _mask)
	for sx in [-0.1, 0.1]:
		_box(Vector3(0.1, 0.04, 0.02), _core_mat(color, 4.0), Vector3(sx, 0.06, -0.035), _mask)
	# кольцо «легитимности»
	var ring: = _torus(0.5, 0.55, _core_mat(color, 1.5), Vector3(0, 0.3, 0))
	_spin.append({"node": ring, "axis": Vector3(0, 1, 0), "speed": 1.2})
	if evolve_stage >= 1:
		var halo: = _torus(0.3, 0.34, _core_mat(color, 2.2), Vector3(0, 2.05, -0.1))
		halo.rotation.x = deg_to_rad(70.0)
		_spin.append({"node": halo, "axis": Vector3(0, 1, 0), "speed": -2.0})

# ── RANSOMWARE: тяжёлый замок в летающих цепях ──

func _build_ransomware() -> void:
	var body_root: = Node3D.new()
	body_root.position.y = 0.75
	add_child(body_root)
	_breath_node = body_root
	_box(Vector3(0.95, 0.85, 0.6), _dark_mat(0.8), Vector3.ZERO, body_root)
	_box(Vector3(0.97, 0.87, 0.56), _holo_mat(color, 1.0), Vector3.ZERO, body_root)
	# скважина
	_sphere(0.09, _core_mat(color, 4.5), Vector3(0, 0.13, -0.31), body_root)
	_box(Vector3(0.05, 0.22, 0.02), _core_mat(color, 4.5), Vector3(0, -0.07, -0.31), body_root)
	# заклёпки
	for sx in [-0.4, 0.4]:
		for sy in [-0.33, 0.33]:
			_sphere(0.06, _core_mat(color, 2.0), Vector3(sx, sy, -0.28), body_root)
	# дужка
	_shackle = Node3D.new()
	_shackle.position = Vector3(0, 1.18, 0)
	add_child(_shackle)
	var arc: = TorusMesh.new()
	arc.inner_radius = 0.3
	arc.outer_radius = 0.4
	_mesh(arc, _core_mat(color, 1.8), Vector3.ZERO, _shackle)
	# летающие звенья цепей вокруг — на двух наклонённых орбитах
	for k in 2 + evolve_stage:
		var orbit: = Node3D.new()
		orbit.position.y = 0.75
		orbit.rotation_degrees = Vector3(randf_range(-30, 30), randf_range(0, 180), randf_range(-20, 20))
		add_child(orbit)
		var links: = 5
		for i in links:
			var ang: = TAU * float(i) / float(links)
			var link: = _torus(0.05, 0.09, _dark_mat(0.9), Vector3(cos(ang) * 0.85, 0, sin(ang) * 0.85), orbit)
			link.rotation_degrees = Vector3(randf_range(0, 90), randf_range(0, 90), 0)
			if i % 2 == 0:
				link.material_override = _core_mat(color * 0.8, 1.2)
		_orbit.append({"node": orbit, "speed": randf_range(0.5, 1.0) * (1.0 if k % 2 == 0 else -1.0), "axis": Vector3(0, 1, 0)})

# ── SPYWARE: всевидящее око на щупальцах-камерах ──

func _build_spyware() -> void:
	_eye_root = Node3D.new()
	_eye_root.position.y = 1.15
	add_child(_eye_root)
	_breath_node = _eye_root
	_sphere(0.45, _holo_mat(color, 1.1), Vector3.ZERO, _eye_root)
	# веко-кольцо
	var lid: = _torus(0.4, 0.48, _dark_mat(0.85), Vector3.ZERO, _eye_root)
	lid.rotation.x = deg_to_rad(14.0)
	# радужка и зрачок
	_pupil = Node3D.new()
	_eye_root.add_child(_pupil)
	_sphere(0.2, _core_mat(color, 2.5), Vector3(0, 0, -0.32), _pupil)
	_sphere(0.1, _core_mat(Color(0.05, 0.02, 0.02), 0.2), Vector3(0, 0, -0.44), _pupil)
	# орбитальные линзы
	for i in 1 + evolve_stage:
		var orbit_root: = Node3D.new()
		orbit_root.rotation_degrees = Vector3(randf_range(-40, 40), randf_range(0, 180), randf_range(-30, 30))
		_eye_root.add_child(orbit_root)
		var lens: = _torus(0.6 + 0.12 * float(i), 0.63 + 0.12 * float(i), _core_mat(color, 1.2), Vector3.ZERO, orbit_root)
		lens.rotation.x = deg_to_rad(90.0)
		_orbit.append({"node": orbit_root, "speed": 0.9 + 0.5 * float(i), "axis": Vector3(0, 1, 0)})
	# щупальца-камеры: три стебля с мини-объективами
	for i in 3:
		var ang: = TAU * float(i) / 3.0 + 0.5
		var stalk: = Node3D.new()
		stalk.position = Vector3(cos(ang) * 0.25, 0.75, sin(ang) * 0.25)
		add_child(stalk)
		var stem: = CylinderMesh.new()
		stem.top_radius = 0.03
		stem.bottom_radius = 0.05
		stem.height = 0.85
		var st: = _mesh(stem, _dark_mat(), Vector3(cos(ang) * 0.28, -0.1, sin(ang) * 0.28), stalk)
		st.rotation.z = -cos(ang) * 0.55
		st.rotation.x = sin(ang) * 0.55
		var cam: = _sphere(0.09, _core_mat(color, 3.0), Vector3(cos(ang) * 0.5, 0.32, sin(ang) * 0.5), stalk)
		_sphere(0.04, _core_mat(Color(1, 0.3, 0.3), 4.0), cam.position + Vector3(cos(ang) * 0.07, 0.03, sin(ang) * 0.07), stalk)
		_stalks.append({"node": stalk, "phase": randf() * TAU})
	# ножка-штатив
	var leg: = CylinderMesh.new()
	leg.top_radius = 0.08
	leg.bottom_radius = 0.16
	leg.height = 0.6
	_mesh(leg, _dark_mat(), Vector3(0, 0.35, 0))

# ── ADWARE: кричащий рой поп-ап окон ──

func _build_adware() -> void:
	var core: = _sphere(0.22, _core_mat(color, 3.0), Vector3(0, 1.0, 0))
	_breath_node = core
	var ring: = _torus(0.3, 0.34, _core_mat(color, 1.6), Vector3(0, 1.0, 0))
	ring.rotation.z = deg_to_rad(20.0)
	_spin.append({"node": ring, "axis": Vector3(0, 1, 0), "speed": 2.5})
	var ads: = ["WIN!", "$$$", "CLICK", "18+", "FREE", "!!!"]
	var pop_colors: = [color, Color(1.0, 0.7, 0.35), Color(0.21, 0.85, 1.0), Color(1.0, 0.26, 0.46), Color(0.6, 0.42, 1.0)]
	var count: = 5 + evolve_stage * 2
	for i in count:
		var pivot: = Node3D.new()
		pivot.position.y = 1.0
		pivot.rotation.y = TAU * float(i) / float(count)
		add_child(pivot)
		var quad: = QuadMesh.new()
		quad.size = Vector2(randf_range(0.32, 0.5), randf_range(0.22, 0.36))
		var pc: Color = pop_colors[i % pop_colors.size()]
		var pm: = StandardMaterial3D.new()
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.albedo_color = Color(pc.r, pc.g, pc.b, 0.4)
		pm.cull_mode = BaseMaterial3D.CULL_DISABLED
		var q: = _mesh(quad, pm, Vector3(0, randf_range(-0.3, 0.55), -randf_range(0.55, 0.9)), pivot)
		# рамка и заголовок окна
		_box(Vector3(quad.size.x * 1.04, 0.035, 0.005), _core_mat(pc, 2.2), q.position + Vector3(0, quad.size.y * 0.5, 0), pivot)
		var lbl: = Label3D.new()
		lbl.text = ads[i % ads.size()]
		lbl.font_size = 40
		lbl.pixel_size = 0.004
		lbl.modulate = pc.lightened(0.3)
		lbl.outline_size = 6
		lbl.position = q.position + Vector3(0, 0, -0.01)
		lbl.no_depth_test = false
		pivot.add_child(lbl)
		_popups.append(q)
		_orbit.append({"node": pivot, "speed": randf_range(0.6, 1.4) * (1.0 if i % 2 == 0 else -1.0), "axis": Vector3(0, 1, 0)})

# ── ROOTKIT: призрачный клинок в дымном плаще ──

func _build_rootkit() -> void:
	var blade: = PrismMesh.new()
	blade.size = Vector3(0.5, 1.3, 0.28)
	var body: = _mesh(blade, _holo_mat(color, 0.9), Vector3(0, 0.75, 0))
	body.rotation.x = deg_to_rad(58.0)
	body.rotation.y = PI
	_breath_node = body
	_sphere(0.1, _core_mat(color, 3.0), Vector3(0, 0.72, -0.1))
	# капюшон
	var hood: = _cone(0.3, 0.5, _holo_mat(color * 0.8, 0.7), Vector3(0, 1.28, 0.05))
	hood.rotation.x = deg_to_rad(190.0)
	# плащ-лепестки
	for side in [-1.0, 1.0]:
		var petal: = PrismMesh.new()
		petal.size = Vector3(0.32, 0.9, 0.1)
		var p: = _mesh(petal, _holo_mat(color * 0.7, 0.6), Vector3(side * 0.3, 0.62, 0.16))
		p.rotation.z = deg_to_rad(-24.0 * side)
		p.rotation.x = deg_to_rad(35.0)
	# дымные кольца у земли, вращаются в противофазе
	for k in 3:
		var haze: = _torus(0.3 + 0.12 * k, 0.44 + 0.12 * k, _holo_mat(color * (0.7 - 0.15 * k), 0.4), Vector3(0, 0.1 + 0.08 * k, 0))
		_spin.append({"node": haze, "axis": Vector3(0, 1, 0), "speed": (-0.8 + 0.5 * k) * (1.0 if k % 2 == 0 else -1.0)})
	if evolve_stage >= 1:
		var crown: = _torus(0.2, 0.24, _core_mat(color, 1.8), Vector3(0, 1.5, 0))
		crown.rotation.x = deg_to_rad(28.0)
		_spin.append({"node": crown, "axis": Vector3(0, 1, 0), "speed": 3.0})

# ── BOTNET: командный хаб с дронами на лучах ──

func _build_botnet() -> void:
	var hub: = _sphere(0.32, _holo_mat(color, 1.3), Vector3(0, 1.0, 0))
	_breath_node = hub
	_sphere(0.15, _core_mat(color, 3.5), Vector3(0, 1.0, 0))
	var frame: = _torus(0.42, 0.46, _core_mat(color, 1.4), Vector3(0, 1.0, 0))
	frame.rotation.x = deg_to_rad(90.0)
	_spin.append({"node": frame, "axis": Vector3(1, 0, 0), "speed": 1.1})
	# шипы-антенны на хабе (вирионный силуэт)
	_spikes(hub, 0.3, 8, 0.22, color)
	var count: = 3 + evolve_stage
	for i in count:
		var pivot: = Node3D.new()
		pivot.position.y = 1.0
		pivot.rotation.y = TAU * float(i) / float(count)
		pivot.rotation.x = deg_to_rad(randf_range(-24.0, 24.0))
		add_child(pivot)
		# дрон
		_sphere(0.11, _core_mat(color, 2.4), Vector3(0.72, 0, 0), pivot)
		_box(Vector3(0.16, 0.02, 0.02), _dark_mat(), Vector3(0.72, 0.08, 0), pivot)
		_sphere(0.04, _core_mat(Color(1, 0.4, 0.4), 3.0), Vector3(0.78, 0.03, -0.08), pivot)
		# луч связи хаб→дрон
		var beam: = BoxMesh.new()
		beam.size = Vector3(0.5, 0.012, 0.012)
		var bmat: = StandardMaterial3D.new()
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		bmat.albedo_color = Color(color.r, color.g, color.b, 0.35)
		_mesh(beam, bmat, Vector3(0.42, 0, 0), pivot)
		_orbit.append({"node": pivot, "speed": randf_range(1.2, 2.4), "axis": Vector3(0, 1, 0)})

# ── анимация ────────────────────────────────────────────────

func _process(delta: float) -> void:
	_t += delta
	for s in _spin:
		s["node"].rotate(s["axis"].normalized(), s["speed"] * delta)
	for o in _orbit:
		o["node"].rotate(o["axis"].normalized(), o["speed"] * delta)
	# дыхание тела — живой организм, а не статуя
	if _breath_node:
		var breath: = 1.0 + sin(_t * 2.1) * (0.035 - 0.02 * move_ratio)
		_breath_node.scale = Vector3(breath, 1.0 / breath, breath).lerp(Vector3.ONE, 0.5)
	match cls:
		"worm":
			# бур крутится всегда, при беге — бешено
			if _drill:
				_drill.rotate_z(delta * (4.0 + move_ratio * 14.0))
			# хвост: бегущая волна, амплитуда растёт со скоростью
			var amp: = 0.09 + 0.22 * move_ratio
			for i in _segments.size():
				var seg: Node3D = _segments[i]
				seg.position.x = sin(_t * (4.0 + move_ratio * 4.5) - float(i) * 0.95) * amp * (0.35 + 0.22 * float(i))
				seg.position.y = 0.95 - 0.05 * float(i) + cos(_t * 3.0 - float(i) * 0.7) * 0.045
				seg.rotation.y = sin(_t * 4.0 - float(i) * 0.95) * 0.35
		"trojan":
			if _mask:
				_mask.position.x = sin(_t * 0.8) * 0.1
				_mask.rotation.y = sin(_t * 0.6) * 0.16
		"ransomware":
			if _shackle:
				_shackle.position.y = 1.18 + absf(sin(_t * 1.4)) * 0.05
		"spyware":
			if _pupil:
				_pupil.rotation.y = sin(_t * 0.7) * 0.5
				_pupil.rotation.x = cos(_t * 1.1) * 0.25
			for s in _stalks:
				var st: Node3D = s["node"]
				st.rotation.y = sin(_t * 0.9 + s["phase"]) * 0.3
				st.rotation.x = cos(_t * 0.7 + s["phase"]) * 0.12
		"adware":
			for i in _popups.size():
				var q: MeshInstance3D = _popups[i]
				q.scale = Vector3.ONE * (0.8 + 0.3 * absf(sin(_t * 2.0 + float(i) * 1.7)))
		"rootkit":
			scale.y = lerpf(scale.y, 1.0 - 0.25 * move_ratio, 6.0 * delta)
