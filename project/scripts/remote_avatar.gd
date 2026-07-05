class_name RemoteAvatar
extends Node3D

## Аватар удалённого игрока: модель класса + плавная интерполяция позиции.

var peer_id: = 0
var cls: = "worm"
var target_pos: = Vector3.ZERO
var target_yaw: = 0.0
var model: VirusModel
var name_label: Label3D
var shrink_until: = 0.0
var _emote_label: Label3D
var _emote_tween: Tween
var _bug_model: Node3D
var _crate_model: Node3D
var is_bug: = false
var morph_hidden: = false

func setup(p_id: int, p_cls: String, p_name: String) -> void:
	peer_id = p_id
	cls = p_cls
	name = "Remote%d" % p_id
	var color: Color = GameState.CLASSES[p_cls]["color"]
	model = VirusModel.create(p_cls, color)
	add_child(model)
	var light: = OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.0
	light.omni_range = 4.0
	light.position.y = 1.2
	add_child(light)
	name_label = Label3D.new()
	name_label.text = "%s · %s" % [p_name, GameState.CLASSES[p_cls]["name"]]
	name_label.font_size = 36
	name_label.modulate = color
	name_label.outline_size = 8
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.no_depth_test = true
	name_label.position.y = 2.4
	add_child(name_label)

func net_update(pos: Vector3, yaw: float, ratio: float) -> void:
	target_pos = pos
	target_yaw = yaw
	if model:
		model.move_ratio = ratio

func _process(delta: float) -> void:
	global_position = global_position.lerp(target_pos, minf(12.0 * delta, 1.0))
	if model:
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, 10.0 * delta)
		var target_scale: = Vector3.ONE
		if Time.get_ticks_msec() / 1000.0 < shrink_until:
			target_scale = Vector3(0.4, 0.4, 0.4)
		model.scale = model.scale.lerp(target_scale, 8.0 * delta)

func set_shrunk(sec: float) -> void:
	shrink_until = Time.get_ticks_msec() / 1000.0 + sec

func set_bug(on: bool) -> void:
	is_bug = on
	if model:
		model.visible = not on
	if on:
		if _bug_model == null:
			_bug_model = VirusModel.create_bug(GameState.CLASSES[cls]["color"])
			add_child(_bug_model)
		_bug_model.visible = true
		if name_label:
			name_label.text = "%s · БАГ (тащи к порталу!)" % Net.player_name(peer_id)
			name_label.modulate = Color(1.0, 0.4, 0.45)
	else:
		if _bug_model != null:
			_bug_model.visible = false
		if name_label:
			name_label.text = "%s · %s" % [Net.player_name(peer_id), GameState.CLASSES[cls]["name"]]
			name_label.modulate = GameState.CLASSES[cls]["color"]

func set_morph(on: bool) -> void:
	morph_hidden = on
	if model:
		model.visible = not on
	if name_label:
		name_label.visible = not on
	if on:
		if _crate_model == null:
			_crate_model = VirusModel.create_crate()
			add_child(_crate_model)
		_crate_model.visible = true
	elif _crate_model != null:
		_crate_model.visible = false

func show_emote(text: String, color: Color) -> void:
	if _emote_tween != null and _emote_tween.is_valid():
		_emote_tween.kill()
	if _emote_label != null and is_instance_valid(_emote_label):
		_emote_label.queue_free()
	_emote_label = Label3D.new()
	_emote_label.text = text
	_emote_label.font_size = 52
	_emote_label.modulate = color
	_emote_label.outline_size = 10
	_emote_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_emote_label.no_depth_test = true
	_emote_label.position.y = 3.0
	add_child(_emote_label)
	var lbl: = _emote_label
	_emote_tween = create_tween()
	_emote_tween.tween_property(lbl, "position:y", 3.5, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_emote_tween.tween_interval(1.6)
	_emote_tween.tween_property(lbl, "modulate:a", 0.0, 0.4)
	_emote_tween.tween_callback(lbl.queue_free)
