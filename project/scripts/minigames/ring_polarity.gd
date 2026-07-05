extends MinigameBase

## «Полярность колец»: два кольца вращаются навстречу, у каждого есть
## заряженный разрыв. Жми [ПРОБЕЛ] в момент совмещения разрывов.

var ang_a: = 0.0
var ang_b: = PI
var speed_a: = 1.6
var speed_b: = -2.1
var hits_needed: = 3
var hits: = 0
var window: = 0.3
var _flash: = 0.0
var _miss_flash: = 0.0
var center: = Vector2.ZERO

func _init() -> void:
	rounds_needed = 3
	hint = "[ПРОБЕЛ] когда разрывы колец совместились — полярности замкнутся"

func _apply_difficulty(diff: int) -> void:
	if diff >= 3:
		rounds_needed = 4

func _ready() -> void:
	super._ready()
	center = Vector2(PLAY.position.x + PLAY.size.x * 0.5, PLAY.position.y + PLAY.size.y * 0.5)

func _new_round() -> void:
	hits = 0
	hits_needed = 2 + rounds_done + (1 if difficulty >= 2 else 0)
	var base: = 1.5 + 0.3 * float(rounds_done) + 0.25 * float(difficulty)
	speed_a = base * (1.0 if randf() > 0.5 else -1.0)
	speed_b = -(base * randf_range(1.15, 1.5)) * signf(speed_a)
	if mirror:
		speed_a = -speed_a
		speed_b = -speed_b
	window = clampf(0.34 - 0.03 * float(rounds_done) - 0.02 * float(difficulty), 0.16, 0.34)
	ang_a = randf() * TAU
	ang_b = randf() * TAU
	set_status("замыкай полярности (%d)" % hits_needed, UIKit.DIM)

func _restart_round() -> void:
	_new_round()

func _diff() -> float:
	return absf(fmod(ang_a - ang_b + PI, TAU) - PI)

func _process(delta: float) -> void:
	super._process(delta)
	if _finished:
		return
	var gd: = game_delta(delta)
	ang_a = fmod(ang_a + speed_a * gd, TAU)
	ang_b = fmod(ang_b + speed_b * gd, TAU)
	if moving:
		# подвижная цель: скорости плавают
		speed_a += sin(_noise_seed * 1.1) * gd * 0.8
		speed_b -= cos(_noise_seed * 0.9) * gd * 0.8
	_flash = maxf(_flash - delta * 3.0, 0.0)
	_miss_flash = maxf(_miss_flash - delta * 3.0, 0.0)

func _unhandled_input(event: InputEvent) -> void:
	if _finished:
		return
	if event.is_action_pressed("mg_action"):
		accept_event()
		if _diff() <= window:
			hits += 1
			_flash = 1.0
			Sfx.play("round_ok", -6.0, 1.0 + 0.15 * float(hits))
			# после замыкания кольца разлетаются
			ang_b = ang_a + PI + randf_range(-0.6, 0.6)
			set_status("замкнуто %d/%d" % [hits, hits_needed], UIKit.TEAL)
			if hits >= hits_needed:
				round_success()
		else:
			_miss_flash = 1.0
			miss("полярности не совпали")

func _draw() -> void:
	_draw_frame()
	var c: Color = layer["color"]
	var r_a: = 150.0
	var r_b: = 105.0
	var gap: = 0.55
	var aligned: = _diff() <= window
	# кольцо A
	var col_a: = UIKit.CYAN if not aligned else UIKit.TEAL
	draw_arc(center, r_a, ang_a + gap * 0.5, ang_a + TAU - gap * 0.5, 72, Color(col_a.r, col_a.g, col_a.b, 0.75), 7.0)
	# заряды на краях разрыва A
	for s in [-1.0, 1.0]:
		var p: = center + Vector2(cos(ang_a + s * gap * 0.5), sin(ang_a + s * gap * 0.5)) * r_a
		draw_circle(p, 8.0, UIKit.AMBER if s > 0 else UIKit.MAGENTA)
	# кольцо B
	var col_b: = UIKit.VIOLET if not aligned else UIKit.TEAL
	draw_arc(center, r_b, ang_b + gap * 0.5, ang_b + TAU - gap * 0.5, 72, Color(col_b.r, col_b.g, col_b.b, 0.75), 7.0)
	for s in [-1.0, 1.0]:
		var p: = center + Vector2(cos(ang_b + s * gap * 0.5), sin(ang_b + s * gap * 0.5)) * r_b
		draw_circle(p, 7.0, UIKit.MAGENTA if s > 0 else UIKit.AMBER)
	# ядро
	var core_col: = UIKit.TEAL if aligned else Color(0.2, 0.3, 0.4)
	draw_circle(center, 30.0 + (6.0 * sin(_noise_seed * 8.0) if aligned else 0.0), Color(core_col.r, core_col.g, core_col.b, 0.35))
	draw_circle(center, 18.0, core_col)
	if aligned and not blackout:
		# дуга-молния между разрывами
		draw_line(center + Vector2(cos(ang_a), sin(ang_a)) * r_a, center + Vector2(cos(ang_b), sin(ang_b)) * r_b,
			Color(1.0, 1.0, 0.8, 0.7 + 0.3 * sin(_noise_seed * 30.0)), 3.0)
	if _flash > 0.0:
		draw_arc(center, r_a + 14.0, 0, TAU, 72, Color(UIKit.TEAL.r, UIKit.TEAL.g, UIKit.TEAL.b, _flash * 0.6), 4.0)
	if _miss_flash > 0.0:
		draw_arc(center, r_a + 14.0, 0, TAU, 72, Color(1.0, 0.2, 0.3, _miss_flash * 0.6), 4.0)
	var font: = get_theme_default_font()
	draw_string(font, Vector2(PLAY.position.x + 30, PLAY.position.y + 44),
		"замыканий: %d/%d" % [hits, hits_needed], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UIKit.DIM)
	_draw_noise_overlay()
