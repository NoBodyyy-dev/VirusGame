class_name LootItem
extends RigidBody3D

## Физический лут: его тащат, роняют, разбивают и вносят в портал.
## Физику считает хост; клиенты видят марионетку.

signal hit_taken(item: LootItem)
signal smashed(item: LootItem)

const KIND_COLORS: = {
	"file": Color("38f0a8"),
	"crate": Color("4a90ff"),
	"epic": Color("ffd166"),
}
const BREAK_SPEED: = 5.2   # м/с удара, после которых лут страдает

var item_id: = 0
var kind: = "file"
var loot_name: = "данные.bin"
var value: = 10.0
var base_value: = 10.0
var weight: = 1            # сколько носильщиков нужно
var hits_left: = 2
var broken: = false
var deposited: = false
var carriers: Array = []   # peer ids, кто сейчас несёт
var last_holder: = 0       # кто трогал последним (для «РУКОЖОПА»)
var puppet: = false

var _net_pos: = Vector3.INF
var _net_roty: = 0.0
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _label: Label3D
var _prev_speed: = 0.0
var _hit_cd: = 0.0
var _xray_marker: Label3D

static func create(data: Dictionary, p_puppet: bool) -> LootItem:
	var it: = LootItem.new()
	it.item_id = data["id"]
	it.kind = data["kind"]
	it.loot_name = data["name"]
	it.value = data["value"]
	it.base_value = data["value"]
	it.weight = data["weight"]
	it.hits_left = GameState.LOOT_KINDS[it.kind]["hits"]
	it.position = data["pos"]
	it.puppet = p_puppet
	return it

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 4
	mass = 4.0 * float(weight)
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	if puppet:
		freeze = true
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	linear_damp = 0.4
	angular_damp = 1.2

	var size: Vector3 = GameState.LOOT_KINDS[kind]["size"]
	var col: Color = KIND_COLORS[kind]
	var shape: = CollisionShape3D.new()
	var box: = BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)

	_mesh = MeshInstance3D.new()
	var bm: = BoxMesh.new()
	bm.size = size
	_mesh.mesh = bm
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.04, 0.06, 0.09)
	_mat.metallic = 0.5
	_mat.roughness = 0.35
	_mat.emission_enabled = true
	_mat.emission = col
	_mat.emission_energy_multiplier = 0.9 if kind != "epic" else 1.8
	_mesh.material_override = _mat
	add_child(_mesh)
	# светящийся кант
	var trim: = MeshInstance3D.new()
	var tm: = BoxMesh.new()
	tm.size = Vector3(size.x * 1.04, size.y * 0.12, size.z * 1.04)
	trim.mesh = tm
	var trim_mat: = StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.02, 0.03, 0.05)
	trim_mat.emission_enabled = true
	trim_mat.emission = col.lightened(0.2)
	trim_mat.emission_energy_multiplier = 2.2
	trim.material_override = trim_mat
	add_child(trim)

	_label = Label3D.new()
	_label.font_size = 30
	_label.modulate = col
	_label.outline_size = 8
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.position.y = size.y * 0.5 + 0.45
	add_child(_label)
	_update_label()

func _update_label() -> void:
	var w_mark: = "" if weight <= 1 else "  [%d чел.]" % weight
	var state: = ""
	if broken:
		state = "  ✖ РАЗБИТ"
	_label.text = "%s\n◈ %d%s%s" % [loot_name, roundi(value), w_mark, state]
	if broken:
		_label.modulate = Color(0.6, 0.4, 0.4)
		_mat.emission_energy_multiplier = 0.25

func _physics_process(delta: float) -> void:
	_hit_cd = maxf(_hit_cd - delta, 0.0)
	if puppet:
		if _net_pos != Vector3.INF:
			global_position = global_position.lerp(_net_pos, minf(14.0 * delta, 1.0))
			rotation.y = lerp_angle(rotation.y, _net_roty, 10.0 * delta)
		return
	_prev_speed = linear_velocity.length()

func net_update(pos: Vector3, roty: float) -> void:
	_net_pos = pos
	_net_roty = roty

func is_free() -> bool:
	return carriers.is_empty() and not deposited

func set_carried(ids: Array) -> void:
	carriers = ids
	if puppet:
		return
	if carriers.is_empty():
		freeze = false
	else:
		freeze = true
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		rotation.x = 0.0
		rotation.z = 0.0

func drop_with(vel: Vector3) -> void:
	set_carried([])
	if not puppet:
		linear_velocity = vel

func _on_body_entered(_body: Node) -> void:
	# хрупкость: жёсткое приземление бьёт ценность
	if puppet or deposited or not carriers.is_empty() or _hit_cd > 0.0:
		return
	if _prev_speed > BREAK_SPEED:
		take_hit()

func take_hit() -> void:
	## только хост: лут пострадал
	if broken or deposited:
		return
	_hit_cd = 0.5
	hits_left -= 1
	value = maxf(value * 0.72, base_value * 0.2)
	if hits_left <= 0:
		broken = true
		smashed.emit(self)
	else:
		hit_taken.emit(self)
	apply_damage_fx(value, broken)

func apply_damage_fx(new_value: float, now_broken: bool) -> void:
	## визуал удара — вызывается и на клиентах через RPC
	value = new_value
	broken = now_broken
	_update_label()
	Sfx.play("round_fail", -4.0, 1.5 if not now_broken else 0.8)
	# осыпающиеся биты
	for i in 7:
		var bit: = MeshInstance3D.new()
		var bm: = BoxMesh.new()
		bm.size = Vector3(0.07, 0.07, 0.07)
		bit.mesh = bm
		var m: = StandardMaterial3D.new()
		m.emission_enabled = true
		m.emission = KIND_COLORS[kind]
		m.emission_energy_multiplier = 3.0
		m.albedo_color = Color(0.02, 0.04, 0.05)
		bit.material_override = m
		get_parent().add_child(bit)
		bit.global_position = global_position + Vector3(randf_range(-0.3, 0.3), 0.3, randf_range(-0.3, 0.3))
		var target: = bit.global_position + Vector3(randf_range(-1.4, 1.4), randf_range(0.6, 1.6), randf_range(-1.4, 1.4))
		var tw: = bit.create_tween()
		tw.tween_property(bit, "global_position", target, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(bit, "scale", Vector3(0.05, 0.05, 0.05), 0.55)
		tw.tween_callback(bit.queue_free)
	var flash: = create_tween()
	flash.tween_property(_mat, "emission_energy_multiplier", 4.0, 0.06)
	flash.tween_property(_mat, "emission_energy_multiplier", 0.25 if now_broken else 0.9, 0.3)

func deposit_fly(to: Vector3) -> void:
	## красивый улёт в портал; нода удаляется в конце
	deposited = true
	set_carried([])
	freeze = true
	_label.text = "◈ +%d" % roundi(value)
	_label.modulate = Color("2fe6b0")
	var tw: = create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "global_position", to + Vector3(0, 1.9, 0), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "scale", Vector3(0.05, 0.05, 0.05), 0.45)
	tw.chain().tween_callback(queue_free)

func set_xray(on: bool) -> void:
	## подсветка Spyware сквозь стены
	if on and _xray_marker == null and not deposited:
		_xray_marker = Label3D.new()
		_xray_marker.text = "◈ %d" % roundi(value)
		_xray_marker.font_size = 44
		_xray_marker.modulate = Color("ffd166")
		_xray_marker.outline_size = 10
		_xray_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_xray_marker.no_depth_test = true
		_xray_marker.position.y = 1.4
		add_child(_xray_marker)
	elif not on and _xray_marker != null:
		_xray_marker.queue_free()
		_xray_marker = null
