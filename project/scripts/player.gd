class_name VirusPlayer
extends CharacterBody3D

## Контроллер штамма ОТ ТРЕТЬЕГО ЛИЦА: инерция, прыжок с койот-таймом,
## спринт с FOV, переноска лута, стан, режим «бага», морф трояна,
## эффекты ловушек системы (клетка/замедление).

const GRAVITY: = 26.0
const JUMP_VELOCITY: = 9.5
const COYOTE_TIME: = 0.12
const JUMP_BUFFER: = 0.14
const MOUSE_SENS: = 0.0028
const ACCEL_GROUND: = 42.0
const ACCEL_AIR: = 16.0
const BUG_SPEED: = 3.4

var control_enabled: = true
var base_speed: = 6.0
var sprint_speed: = 9.2
var demo_target: = Vector3.INF
var invert_until: = 0.0     # подлянка «зеркало»
var shrink_until: = 0.0     # подлянка «сжатие»
var locked_until: = 0.0     # клетка/перепрошивка: движение запрещено
var slow_until: = 0.0       # перепрошивка: замедление
var haste_until: = 0.0      # СВЕРХТАКТ: разгон
var carry_factor: = 1.0     # штраф скорости от груза (ставит level)
var carrying: = false       # несёт лут (ставит level)
var is_bug: = false         # 0 HP: пищащий баг
var morphed: = false        # троян прикинулся ящиком

var yaw_pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D
var model: VirusModel
var _bug_model: Node3D
var _crate_model: Node3D
var _coyote: = 0.0
var _jump_buffer: = 0.0
var _was_on_floor: = true
var _base_fov: = 68.0
var _shake: = 0.0
var _net_timer: = 0.0
var _stun_t: = 0.0
var _beep_t: = 0.0
var _sprint_noise_t: = 0.0
var _fall_peak: = 0.0
var _emote_label: Label3D
var _emote_tween: Tween

func _ready() -> void:
	collision_layer = 1
	collision_mask = 1 | 4
	if GameState.has_passive("worm"):
		base_speed *= 1.15
		sprint_speed *= 1.15
	base_speed += GameState.evo_bonus("speed")
	sprint_speed += GameState.evo_bonus("speed")
	_build_body()
	_build_camera()

func _build_body() -> void:
	var shape: = CollisionShape3D.new()
	var cap: = CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 1.7
	shape.shape = cap
	shape.position.y = 0.95
	add_child(shape)

	var cls_color: Color = GameState.class_info()["color"]
	model = VirusModel.create(GameState.display_class(), cls_color, GameState.virus_level, GameState.display_secondary())
	add_child(model)

	var light: = OmniLight3D.new()
	light.light_color = cls_color
	light.light_energy = 1.4
	light.omni_range = 5.0
	light.position.y = 1.2
	add_child(light)

func _build_camera() -> void:
	# третье лицо: камера на пружинной штанге за спиной штамма
	yaw_pivot = Node3D.new()
	yaw_pivot.position.y = 1.5
	add_child(yaw_pivot)
	spring = SpringArm3D.new()
	spring.spring_length = 5.2
	spring.margin = 0.3
	spring.rotation.x = deg_to_rad(-16.0)
	spring.add_excluded_object(get_rid())
	yaw_pivot.add_child(spring)
	camera = Camera3D.new()
	camera.fov = _base_fov
	camera.current = true
	spring.add_child(camera)

func locked() -> bool:
	return Time.get_ticks_msec() / 1000.0 < locked_until

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw_pivot.rotate_y(-event.relative.x * MOUSE_SENS)
		spring.rotation.x = clampf(spring.rotation.x - event.relative.y * MOUSE_SENS, deg_to_rad(-65.0), deg_to_rad(18.0))

func shake(power: = 0.35) -> void:
	_shake = maxf(_shake, power)

func look_dir() -> Vector3:
	var d: = -yaw_pivot.global_basis.z
	d.y = 0.0
	return d.normalized() if d.length() > 0.01 else Vector3.FORWARD

# ── шум: слышит Хантер, растёт тревога ──────────────────────

func _noise(amount: float) -> void:
	if GameState.has_passive("rootkit"):
		return # пассивка: бесшумный
	Net.send_noise(amount, global_position)

func _physics_process(delta: float) -> void:
	_stun_t = maxf(_stun_t - delta, 0.0)
	var stunned: = _stun_t > 0.0
	var on_floor: = is_on_floor()
	if not on_floor:
		velocity.y -= GRAVITY * delta
		_coyote = maxf(_coyote - delta, 0.0)
		_fall_peak = maxf(_fall_peak, -velocity.y)
	else:
		_coyote = COYOTE_TIME
		if not _was_on_floor:
			_land()
	_was_on_floor = on_floor

	var can_control: = control_enabled and not stunned and not locked()
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	if can_control and not carrying and not is_bug and Input.is_action_just_pressed("jump"):
		_jump_buffer = JUMP_BUFFER
	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_VELOCITY
		_jump_buffer = 0.0
		_coyote = 0.0
		Sfx.play("jump")
		_noise(2.5)
		_unmorph_if_needed()
		if model:
			model.scale = Vector3(0.82, 1.25, 0.82)

	var dir: = Vector3.ZERO
	if can_control:
		var input_2d: = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if Time.get_ticks_msec() / 1000.0 < invert_until:
			input_2d = -input_2d
		dir = (yaw_pivot.global_basis * Vector3(input_2d.x, 0.0, input_2d.y))
		dir.y = 0.0
		if input_2d.length() > 0.1:
			_unmorph_if_needed()
		if demo_target != Vector3.INF:
			var to_target: = demo_target - global_position
			to_target.y = 0.0
			if to_target.length() > 2.0:
				dir = to_target.normalized()
			else:
				demo_target = Vector3.INF

	var sprinting: = Input.is_action_pressed("sprint") and can_control and not is_bug
	var speed: = (sprint_speed if sprinting else base_speed) * carry_factor
	if Time.get_ticks_msec() / 1000.0 < slow_until:
		speed *= 0.5 # перепрошивка: ноги вязнут в чужом коде
	if Time.get_ticks_msec() / 1000.0 < haste_until:
		speed *= 1.45 # сверхтакт
	if is_bug:
		speed = BUG_SPEED
	var accel: = ACCEL_GROUND if on_floor else ACCEL_AIR
	if dir.length() > 0.01:
		dir = dir.normalized()
		velocity.x = move_toward(velocity.x, dir.x * speed, accel * delta)
		velocity.z = move_toward(velocity.z, dir.z * speed, accel * delta)
		if model:
			model.rotation.y = lerp_angle(model.rotation.y, atan2(-dir.x, -dir.z), 10.0 * delta)
		if _bug_model:
			_bug_model.rotation.y = lerp_angle(_bug_model.rotation.y, atan2(-dir.x, -dir.z), 10.0 * delta)
		# баг скачет, как блоха
		if is_bug and on_floor:
			velocity.y = 4.2
		# спринт шумит
		if sprinting and on_floor:
			_sprint_noise_t -= delta
			if _sprint_noise_t <= 0.0:
				_sprint_noise_t = 0.8
				_noise(0.6)
	else:
		var brake: = accel * 1.4 if on_floor else accel * 0.4
		velocity.x = move_toward(velocity.x, 0.0, brake * delta)
		velocity.z = move_toward(velocity.z, 0.0, brake * delta)
	move_and_slide()

	# писк бага
	if is_bug:
		_beep_t -= delta
		if _beep_t <= 0.0:
			_beep_t = randf_range(1.8, 3.2)
			Sfx.play("ui_click", -6.0, randf_range(1.8, 2.4))

	# модель: восстановление после squash + передача скорости для анимации
	if model:
		var target_scale: = Vector3.ONE
		if Time.get_ticks_msec() / 1000.0 < shrink_until:
			target_scale = Vector3(0.4, 0.4, 0.4)
		model.scale = model.scale.lerp(target_scale, 8.0 * delta)
		var planar: = Vector2(velocity.x, velocity.z).length()
		model.move_ratio = clampf(planar / sprint_speed, 0.0, 1.0)

	# репликация позиции в кооперативе
	if Net.active:
		_net_timer -= delta
		if _net_timer <= 0.0:
			_net_timer = 0.06
			var ratio: = model.move_ratio if model else 0.0
			var yaw: = model.rotation.y if model else 0.0
			Net.send_pos(global_position, yaw, ratio)

	# FOV-кик на спринте, тряска камеры
	var target_fov: = _base_fov + (6.0 if sprinting and Vector2(velocity.x, velocity.z).length() > 4.0 else 0.0)
	camera.fov = lerpf(camera.fov, target_fov, 6.0 * delta)
	if _shake > 0.003:
		camera.h_offset = randf_range(-_shake, _shake) * 0.5
		camera.v_offset = randf_range(-_shake, _shake) * 0.5
		_shake = lerpf(_shake, 0.0, 9.0 * delta)
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0

func _land() -> void:
	if model:
		model.scale = Vector3(1.2, 0.78, 1.2)
	Sfx.play("land", -8.0)
	if _fall_peak > 7.0:
		_noise(1.5)
	_fall_peak = 0.0

# ── рэгдолл и удары ─────────────────────────────────────────

func ragdoll_from(from: Vector3) -> void:
	## швыряет от точки удара с вращением — смешно и больно
	var push: = (global_position - from)
	push.y = 0.0
	if push.length() < 0.1:
		push = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	velocity = push.normalized() * 11.0 + Vector3.UP * 7.0
	_stun_t = 1.1
	shake(0.6)
	if model:
		var tw: = create_tween()
		tw.tween_property(model, "rotation:x", TAU * (1.0 if randf() > 0.5 else -1.0), 0.9)
		tw.tween_callback(func() -> void:
			if model:
				model.rotation.x = 0.0)

func knockback(from: Vector3) -> void:
	ragdoll_from(from)

# ── баг (0 HP) ──────────────────────────────────────────────

func set_bug(on: bool) -> void:
	if is_bug == on:
		return
	is_bug = on
	carrying = false
	carry_factor = 1.0
	morphed = false
	if model:
		model.visible = not on
	if on:
		if _bug_model == null:
			_bug_model = VirusModel.create_bug(GameState.class_info()["color"])
			add_child(_bug_model)
		_bug_model.visible = true
		Sfx.play("trap", -2.0, 1.6)
	else:
		if _bug_model != null:
			_bug_model.visible = false
		Sfx.play("ability", -2.0, 1.3)

# ── морф трояна ─────────────────────────────────────────────

func set_morph(on: bool) -> void:
	morphed = on
	if model:
		model.visible = not on
	if on:
		if _crate_model == null:
			_crate_model = VirusModel.create_crate()
			add_child(_crate_model)
		_crate_model.visible = true
	elif _crate_model != null:
		_crate_model.visible = false

func _unmorph_if_needed() -> void:
	if morphed:
		set_morph(false)
		Net.send_morph(false)

# ── рывок червя ─────────────────────────────────────────────

func dash() -> void:
	var d: = look_dir()
	velocity.x = d.x * 22.0
	velocity.z = d.z * 22.0
	velocity.y = maxf(velocity.y, 2.5)
	shake(0.25)
	_noise(1.5)

func set_shrunk(sec: float) -> void:
	shrink_until = Time.get_ticks_msec() / 1000.0 + sec

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
	_emote_label.position.y = 2.6
	add_child(_emote_label)
	var lbl: = _emote_label
	_emote_tween = create_tween()
	_emote_tween.tween_property(lbl, "position:y", 3.1, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_emote_tween.tween_interval(1.6)
	_emote_tween.tween_property(lbl, "modulate:a", 0.0, 0.4)
	_emote_tween.tween_callback(lbl.queue_free)
