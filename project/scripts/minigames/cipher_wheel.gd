extends MinigameBase

## «Шифровальное колесо»: три кольца с hex-цифрами. Крути кольца так,
## чтобы верхняя колонка дала нужную сумму. Логическая головоломка.

const SLOTS: = 8

var rings: Array = []      # массив из 3 колец, каждое — массив значений
var offsets: Array[int] = [0, 0, 0]
var sel_ring: = 0
var target_sum: = 0
var round_time: = 26.0
var time_left: = 26.0
var _anim_off: = [0.0, 0.0, 0.0]

func _init() -> void:
	rounds_needed = 2
	hint = "↑/↓ — выбрать кольцо · ←/→ — вращать · [ПРОБЕЛ] когда сумма сверху = ЦЕЛЬ"

func _apply_difficulty(diff: int) -> void:
	if diff >= 2:
		rounds_needed = 3

func _new_round() -> void:
	round_time = maxf(28.0 - 3.0 * float(rounds_done) - 2.0 * float(difficulty), 12.0) * timer_mult
	time_left = round_time
	rings = []
	for r in 3:
		var ring: Array = []
		for i in SLOTS:
			ring.append(randi_range(0, 9))
		rings.append(ring)
	# гарантируем решение: выбираем случайные смещения и считаем их сумму
	var sol: = [randi_range(0, SLOTS - 1), randi_range(0, SLOTS - 1), randi_range(0, SLOTS - 1)]
	target_sum = 0
	for r in 3:
		target_sum += rings[r][sol[r]]
	offsets = [0, 0, 0]
	sel_ring = 0
	set_status("ЦЕЛЬ: %d — вращай кольца" % target_sum, UIKit.DIM)

func _restart_round() -> void:
	offsets = [0, 0, 0]
	time_left = round_time

func _top_value(r: int) -> int:
	return rings[r][((offsets[r]) % SLOTS + SLOTS) % SLOTS]

func _current_sum() -> int:
	return _top_value(0) + _top_value(1) + _top_value(2)

func _process(delta: float) -> void:
	super._process(delta)
	if _finished:
		return
	time_left -= game_delta(delta)
	for r in 3:
		_anim_off[r] = lerpf(_anim_off[r], float(offsets[r]), 12.0 * delta)
	if time_left <= 0.0:
		miss("ключ ротации истёк")

func _unhandled_input(event: InputEvent) -> void:
	if _finished or not (event is InputEventKey) or not event.pressed:
		return
	if event.is_action_pressed("mg_up"):
		accept_event()
		sel_ring = (sel_ring + 2) % 3
	elif event.is_action_pressed("mg_down"):
		accept_event()
		sel_ring = (sel_ring + 1) % 3
	elif event.is_action_pressed("mg_left") or event.is_action_pressed("mg_right"):
		accept_event()
		var d: = 1 if event.is_action_pressed("mg_right") else -1
		if mirror:
			d = -d
		offsets[sel_ring] += d
		Sfx.play("ui_click", -12.0, 0.9 + 0.15 * float(sel_ring))
	elif event.is_action_pressed("mg_action"):
		accept_event()
		if _current_sum() == target_sum:
			round_success()
		else:
			miss("сумма %d ≠ %d" % [_current_sum(), target_sum])

func _draw() -> void:
	_draw_frame()
	var font: = get_theme_default_font()
	var center: = Vector2(PLAY.position.x + PLAY.size.x * 0.5, PLAY.position.y + PLAY.size.y * 0.56)
	var radii: = [170.0, 120.0, 70.0]
	# метка сверху
	draw_line(center - Vector2(0, 195), center - Vector2(0, 40), Color(UIKit.AMBER.r, UIKit.AMBER.g, UIKit.AMBER.b, 0.4), 2.0)
	for r in 3:
		var rad: float = radii[r]
		var selected: = (r == sel_ring)
		var ring_col: Color = layer["color"] if selected else Color(0.25, 0.4, 0.5)
		draw_arc(center, rad, 0, TAU, 64, Color(ring_col.r, ring_col.g, ring_col.b, 0.8 if selected else 0.35), 3.0 if selected else 1.5)
		for i in SLOTS:
			var ang: = TAU * float(i - _anim_off[r]) / float(SLOTS) - PI * 0.5
			var pos: = center + Vector2(cos(ang), sin(ang)) * rad
			var is_top: bool = i == ((int(offsets[r])) % SLOTS + SLOTS) % SLOTS
			if blackout and not is_top:
				draw_circle(pos, 14.0, Color(0.05, 0.1, 0.14, 0.8))
				continue
			var vc: = UIKit.AMBER if is_top else (UIKit.WHITE if selected else UIKit.DIM)
			draw_circle(pos, 15.0, Color(0.03, 0.07, 0.1, 0.9))
			draw_string(font, pos - Vector2(6, -7), str(rings[r][i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, vc)
	# сумма и цель
	var s: = _current_sum()
	var ok: = s == target_sum
	draw_string(font, center - Vector2(30, -8), "Σ %d" % s, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, UIKit.TEAL if ok else UIKit.WHITE)
	draw_string(font, Vector2(PLAY.position.x + 30, PLAY.position.y + 44), "ЦЕЛЬ СУММЫ: %d" % target_sum, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UIKit.AMBER)
	if ok:
		draw_string(font, Vector2(PLAY.position.x + 30, PLAY.position.y + 74), "▸ жми [ПРОБЕЛ]", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UIKit.TEAL)
	_draw_timer_bar(time_left / round_time)
	_draw_noise_overlay()
