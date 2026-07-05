class_name Antivirus
extends CharacterBody3D

## Стражи системы. Три характера:
##  SCANNER — медленный патруль с конусом: попал в луч → тревога растёт
##  HUNTER  — быстрый и слепой: идёт на шум, вблизи чует движение, бьёт больно
##  POPUP   — мелкий воришка: таскает лежащий лут и убегает, боится прикосновений
## Симулирует хост; клиенты видят марионеток.

signal caught_id(id: int, enemy: Antivirus)
signal loot_stolen(enemy: Antivirus, item: LootItem)
signal loot_dropped(enemy: Antivirus, item: LootItem)

const HOVER_Y: = 2.3
const POPUP_Y: = 0.6

var enemy_id: = 0
var enemy_type: = "SCANNER"
var puppet: = false
var targets: = {}            # id -> Node3D: живые штаммы (баги и ящики-трояны не цели)
var loot_provider: Callable  # func() -> Array[LootItem] — свободный лёгкий лут
var waypoints: Array = []
var wipe_boost: = 0.0

var frozen_until: = 0.0
var decoy_pos: = Vector3.INF
var decoy_until: = 0.0

# HUNTER: слух
var noise_pos: = Vector3.INF
var noise_until: = 0.0
# POPUP: воровство
var stolen: LootItem = null
var scare_until: = 0.0
var _flee_to: = Vector3.INF
var _steal_cd: = 0.0

var _wp: = 0
var _wander_to: = Vector3.INF
var _catch_cd: = 0.0
var _net_pos: = Vector3.INF
var _net_roty: = 0.0
var _t: = randf() * 10.0

var body_mat: StandardMaterial3D
var beam_pivot: Node3D
var beam_light: SpotLight3D
var beam_cone: MeshInstance3D
var eye_ring: MeshInstance3D
var _xray_marker: Label3D

static func create(p_id: int, p_type: String, p_pos: Vector3, p_puppet: bool) -> Antivirus:
	var e: = Antivirus.new()
	e.enemy_id = p_id
	e.enemy_type = p_type
	e.position = p_pos
	e.puppet = p_puppet
	return e

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	match enemy_type:
		"SCANNER": _build_scanner()
		"HUNTER": _build_hunter()
		"POPUP": _build_popup()

# ── тела ────────────────────────────────────────────────────

func _core(radius: float, emission: Color) -> void:
	var shape: = CollisionShape3D.new()
	var sph: = SphereShape3D.new()
	sph.radius = radius
	shape.shape = sph
	add_child(shape)
	var mesh: = MeshInstance3D.new()
	var m: = SphereMesh.new()
	m.radius = radius * 0.9
	m.height = radius * 1.8
	mesh.mesh = m
	body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.06, 0.03, 0.05)
	body_mat.metallic = 0.7
	body_mat.roughness = 0.25
	body_mat.emission_enabled = true
	body_mat.emission = emission
	body_mat.emission_energy_multiplier = 1.4
	mesh.material_override = body_mat
	add_child(mesh)

func _build_scanner() -> void:
	_core(0.55, Color(0.9, 0.12, 0.25))
	eye_ring = MeshInstance3D.new()
	var t: = TorusMesh.new()
	t.inner_radius = 0.55
	t.outer_radius = 0.62
	eye_ring.mesh = t
	var tm: = StandardMaterial3D.new()
	tm.albedo_color = Color(0.03, 0.02, 0.03)
	tm.emission_enabled = true
	tm.emission = Color(1.0, 0.2, 0.3)
	tm.emission_energy_multiplier = 1.4
	eye_ring.material_override = tm
	add_child(eye_ring)
	beam_pivot = Node3D.new()
	beam_pivot.rotation.x = deg_to_rad(-38.0)
	add_child(beam_pivot)
	beam_light = SpotLight3D.new()
	beam_light.light_color = Color(1.0, 0.25, 0.3)
	beam_light.light_energy = 4.0
	beam_light.spot_range = 7.5
	beam_light.spot_angle = 16.0
	beam_pivot.add_child(beam_light)
	beam_cone = MeshInstance3D.new()
	var cone: = CylinderMesh.new()
	cone.top_radius = 0.06
	cone.bottom_radius = 1.9
	cone.height = 7.5
	beam_cone.mesh = cone
	var cm: = StandardMaterial3D.new()
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.albedo_color = Color(1.0, 0.15, 0.25, 0.1)
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam_cone.material_override = cm
	beam_cone.rotation.x = deg_to_rad(90.0)
	beam_cone.position.z = -3.75
	beam_pivot.add_child(beam_cone)

func _build_hunter() -> void:
	_core(0.5, Color(1.0, 0.1, 0.2))
	body_mat.emission_energy_multiplier = 2.6
	# шипы — сразу видно, что этот кусается
	for i in 10:
		var dir: = Vector3(randf_range(-1, 1), randf_range(-0.7, 1), randf_range(-1, 1)).normalized()
		var spike: = MeshInstance3D.new()
		var cm: = CylinderMesh.new()
		cm.top_radius = 0.01
		cm.bottom_radius = 0.09
		cm.height = 0.45
		spike.mesh = cm
		var sm: = StandardMaterial3D.new()
		sm.albedo_color = Color(0.05, 0.02, 0.03)
		sm.emission_enabled = true
		sm.emission = Color(1.0, 0.3, 0.2)
		sm.emission_energy_multiplier = 2.0
		spike.material_override = sm
		spike.position = dir * 0.55
		spike.look_at_from_position(spike.position, spike.position + dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT)
		spike.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))
		add_child(spike)
	var light: = OmniLight3D.new()
	light.light_color = Color(1.0, 0.15, 0.2)
	light.light_energy = 2.2
	light.omni_range = 6.0
	add_child(light)
	# «уши» — он ничего не видит, но всё слышит
	for side in [-1.0, 1.0]:
		var ear: = MeshInstance3D.new()
		var em: = CylinderMesh.new()
		em.top_radius = 0.16
		em.bottom_radius = 0.05
		em.height = 0.3
		ear.mesh = em
		var emat: = StandardMaterial3D.new()
		emat.emission_enabled = true
		emat.emission = Color(1.0, 0.5, 0.3)
		emat.emission_energy_multiplier = 1.6
		ear.material_override = emat
		ear.position = Vector3(side * 0.5, 0.35, 0)
		ear.rotation.z = deg_to_rad(-55.0 * side)
		add_child(ear)

func _build_popup() -> void:
	var shape: = CollisionShape3D.new()
	var box: = BoxShape3D.new()
	box.size = Vector3(0.55, 0.5, 0.2)
	shape.shape = box
	add_child(shape)
	var mesh: = MeshInstance3D.new()
	var bm: = BoxMesh.new()
	bm.size = Vector3(0.55, 0.5, 0.12)
	mesh.mesh = bm
	body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.1, 0.09, 0.02)
	body_mat.emission_enabled = true
	body_mat.emission = Color(1.0, 0.85, 0.2)
	body_mat.emission_energy_multiplier = 1.8
	mesh.material_override = body_mat
	add_child(mesh)
	var lbl: = Label3D.new()
	lbl.text = "▲ РЕКЛАМА ▲\nЖМИ СЮДА!!!"
	lbl.font_size = 30
	lbl.modulate = Color(1.0, 0.9, 0.3)
	lbl.outline_size = 8
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position.y = 0.6
	add_child(lbl)

# ── общие эффекты ───────────────────────────────────────────

func freeze_for(sec: float) -> void:
	frozen_until = _now() + sec
	if body_mat:
		body_mat.emission = Color(0.3, 0.7, 1.0)

func decoy_at(pos: Vector3, sec: float) -> void:
	decoy_pos = pos
	decoy_until = _now() + sec

func hear_noise(pos: Vector3, loudness: float) -> void:
	## HUNTER: чем громче, тем дольше помнит
	if enemy_type == "HUNTER":
		noise_pos = pos
		noise_until = _now() + 2.0 + loudness

func set_xray(on: bool) -> void:
	if on and _xray_marker == null:
		_xray_marker = Label3D.new()
		_xray_marker.text = "⚠ %s" % enemy_type
		_xray_marker.font_size = 40
		_xray_marker.modulate = Color(1.0, 0.35, 0.35)
		_xray_marker.outline_size = 10
		_xray_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_xray_marker.no_depth_test = true
		_xray_marker.position.y = 1.5
		add_child(_xray_marker)
	elif not on and _xray_marker != null:
		_xray_marker.queue_free()
		_xray_marker = null

func net_update(pos: Vector3, roty: float, frozen: bool) -> void:
	_net_pos = pos
	_net_roty = roty
	if frozen:
		frozen_until = _now() + 0.3

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

# ── симуляция ───────────────────────────────────────────────

func _alive_targets() -> Array:
	var out: Array = []
	for id in targets:
		var t: Node3D = targets[id]
		if t == null or not is_instance_valid(t):
			continue
		if Net.is_bug(id):
			continue # баги не интересны системе
		if t is VirusPlayer and (t as VirusPlayer).morphed:
			continue # троян-ящик невидим
		if t is RemoteAvatar and (t as RemoteAvatar).get("morph_hidden") == true:
			continue
		out.append([id, t])
	return out

func _physics_process(delta: float) -> void:
	_t += delta
	_catch_cd = maxf(_catch_cd - delta, 0.0)
	_steal_cd = maxf(_steal_cd - delta, 0.0)
	var now: = _now()
	var frozen: = now < frozen_until
	if body_mat:
		if frozen:
			body_mat.emission = Color(0.3, 0.7, 1.0)
		elif enemy_type == "SCANNER" and body_mat.emission != Color(0.9, 0.12, 0.25):
			body_mat.emission = Color(0.9, 0.12, 0.25)

	if eye_ring:
		eye_ring.rotation.y += delta * 2.0
	if beam_pivot:
		beam_pivot.rotation.y += delta * 0.9

	if puppet:
		if _net_pos != Vector3.INF:
			global_position = global_position.lerp(_net_pos, minf(10.0 * delta, 1.0))
			rotation.y = lerp_angle(rotation.y, _net_roty, 8.0 * delta)
		return

	# напуганный попап прячется под полом
	if enemy_type == "POPUP" and now < scare_until:
		global_position.y = -8.0
		return

	var hover: = HOVER_Y if enemy_type != "POPUP" else POPUP_Y
	position.y = hover + sin(now * 1.7 + float(enemy_id)) * 0.12

	if frozen:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	var speed: = 0.0
	var target: = Vector3.INF
	match enemy_type:
		"SCANNER":
			speed = 2.7 + wipe_boost
			if now < decoy_until and decoy_pos != Vector3.INF:
				target = decoy_pos
			elif not waypoints.is_empty():
				var wp: Vector3 = waypoints[_wp]
				if global_position.distance_to(Vector3(wp.x, global_position.y, wp.z)) < 1.2:
					_wp = (_wp + 1) % waypoints.size()
					wp = waypoints[_wp]
				target = wp
		"HUNTER":
			speed = 5.4 + wipe_boost
			if now < decoy_until and decoy_pos != Vector3.INF:
				target = decoy_pos
			else:
				# вблизи чует движение; издалека идёт на шум
				var best_d: = 8.0
				for pair in _alive_targets():
					var d: float = global_position.distance_to(pair[1].global_position)
					if d < best_d:
						best_d = d
						target = pair[1].global_position
				if target == Vector3.INF and now < noise_until and noise_pos != Vector3.INF:
					target = noise_pos
					if global_position.distance_to(Vector3(noise_pos.x, global_position.y, noise_pos.z)) < 2.0:
						noise_until = 0.0 # дошёл, никого — забыл
				if target == Vector3.INF:
					target = _wander(28.0)
		"POPUP":
			speed = 4.6 + wipe_boost * 0.5
			target = _popup_brain(now)

	if target != Vector3.INF:
		var to: = target - global_position
		to.y = 0.0
		if to.length() > 0.4:
			var dir: = to.normalized()
			velocity.x = dir.x * speed
			velocity.z = dir.z * speed
			rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 5.0 * delta)
		else:
			velocity.x = 0.0
			velocity.z = 0.0
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	velocity.y = 0.0
	move_and_slide()

	if enemy_type == "SCANNER":
		_check_beam(delta, now)
	elif enemy_type == "HUNTER":
		_check_contact(now)
	elif enemy_type == "POPUP":
		_check_popup_touch(now)

func _wander(radius: float) -> Vector3:
	if _wander_to == Vector3.INF or global_position.distance_to(Vector3(_wander_to.x, global_position.y, _wander_to.z)) < 1.5:
		_wander_to = Vector3(randf_range(-radius, radius), 0, randf_range(-radius * 0.65, radius * 0.65))
	return _wander_to

# ── POPUP: мозг воришки ─────────────────────────────────────

func _popup_brain(now: float) -> Vector3:
	if stolen != null and not is_instance_valid(stolen):
		stolen = null
	if stolen != null:
		# тащим добычу в угол
		if _flee_to == Vector3.INF:
			_flee_to = Vector3(randf_range(-28, 28), 0, randf_range(-18, 18))
		stolen.global_position = global_position + Vector3(0, 0.75, 0)
		if global_position.distance_to(Vector3(_flee_to.x, global_position.y, _flee_to.z)) < 1.6:
			_popup_drop()
		return _flee_to
	if _steal_cd > 0.0 or not loot_provider.is_valid():
		return _wander(24.0)
	var best: LootItem = null
	var best_d: = 999.0
	for it in loot_provider.call():
		var d: float = global_position.distance_to(it.global_position)
		if d < best_d:
			best_d = d
			best = it
	if best == null:
		return _wander(24.0)
	if best_d < 1.3:
		stolen = best
		_flee_to = Vector3.INF
		best.set_carried([-enemy_id]) # отрицательный id = держит страж
		loot_stolen.emit(self, best)
		return _wander(24.0)
	return best.global_position

func _popup_drop() -> void:
	if stolen != null and is_instance_valid(stolen):
		stolen.drop_with(Vector3(randf_range(-1, 1), 2.0, randf_range(-1, 1)))
		loot_dropped.emit(self, stolen)
	stolen = null
	_steal_cd = 6.0

func scare_away(now_sec: float = 14.0) -> void:
	## тронули воришку — бросил всё и сбежал
	_popup_drop()
	scare_until = _now() + now_sec
	Sfx.play("pickup", -4.0, 0.6)

func _check_popup_touch(_now: float) -> void:
	for pair in _alive_targets():
		var t: Node3D = pair[1]
		if global_position.distance_to(t.global_position + Vector3.UP * 0.6) < 1.4:
			scare_away()
			return
		# пассивка Adware: попапы боятся его издалека
		if Net.my_class_of(pair[0]) == "adware" and global_position.distance_to(t.global_position) < 6.0:
			scare_away(8.0)
			return

# ── SCANNER: луч ────────────────────────────────────────────

func _check_beam(delta: float, now: float) -> void:
	if now < frozen_until:
		return
	var origin: = beam_light.global_position
	var dir: = -beam_light.global_basis.z
	for pair in _alive_targets():
		var t: Node3D = pair[1]
		var to_p: = (t.global_position + Vector3.UP) - origin
		if to_p.length() < beam_light.spot_range and dir.angle_to(to_p) < deg_to_rad(beam_light.spot_angle + 4.0):
			# луч жжёт тревогу с пассивками класса нарушителя
			GameState.apply_alarm(delta * 7.0, "beam", Net.my_class_of(pair[0]))

# ── HUNTER: укус ────────────────────────────────────────────

func _check_contact(now: float) -> void:
	if _catch_cd > 0.0 or now < frozen_until:
		return
	for pair in _alive_targets():
		var t: Node3D = pair[1]
		var d: = global_position.distance_to(t.global_position + Vector3.UP * 1.0)
		if d < 1.5:
			_catch_cd = 2.8
			_wander_to = Vector3.INF
			noise_until = 0.0
			caught_id.emit(pair[0], self)
			return
