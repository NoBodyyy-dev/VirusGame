class_name MinigameBase
extends Control

## База мини-игры: раунды, мутаторы, пассивки классов, 0-day.

signal round_result(success: bool)
signal finished(success: bool)

const PANEL: = Rect2(320, 110, 960, 680)
const PLAY: = Rect2(350, 262, 900, 420)

var layer: Dictionary
var difficulty: = 1
var rounds_needed: = 3
var rounds_done: = 0
var free_miss_per_round: = 0
var free_miss_left: = 0
var timer_mult: = 1.0
var slow_until: = 0.0

var mirror: = false
var blackout: = false
var noise: = false
var moving: = false
var silent: = false

var hint: = ""
var status_label: Label
var pips_label: Label
var zeroday_label: Label
var _finished: = false
var _noise_seed: = 0.0

func setup(p_layer: Dictionary, p_difficulty: = 1, rounds_override: = -1) -> void:
	layer = p_layer
	difficulty = p_difficulty
	_apply_difficulty(p_difficulty)
	if rounds_override > 0:
		rounds_needed = rounds_override
	var muts: Array = layer["mutators"]
	mirror = "mirror" in muts
	blackout = "blackout" in muts
	noise = "noise" in muts
	moving = "moving" in muts
	silent = "silent" in muts
	if GameState.selected_class == "spyware":
		timer_mult *= 1.3
	if "haste" in muts:
		timer_mult *= 0.85
	if GameState.selected_class == "ransomware":
		free_miss_per_round += 1
	if GameState.mutation_owned("armor"):
		free_miss_per_round += 1
	if silent:
		free_miss_per_round = 0

func _apply_difficulty(_diff: int) -> void:
	pass

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim: = ColorRect.new()
	dim.color = Color(0.0, 0.008, 0.02, 0.7)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UIKit.full_rect(dim))

	var c: Color = layer["color"]
	var mg: Dictionary = GameState.MINIGAMES[layer["game"]]
	var title: = UIKit.label("%s  →  замок %s" % [layer["title"], mg["title"]], 26, c)
	title.position = Vector2(PANEL.position.x + 30, PANEL.position.y + 22)
	add_child(title)

	var sub: = "навык: %s" % mg["skill"]
	var mut_names: = []
	for m in layer["mutators"]:
		mut_names.append(GameState.MUTATORS[m].get_slice(" — ", 0))
	if not mut_names.is_empty():
		sub += "   ·   МУТАТОР: " + ", ".join(mut_names)
	var sub_l: = UIKit.label(sub, 16, UIKit.AMBER if not mut_names.is_empty() else UIKit.DIM)
	sub_l.position = Vector2(PANEL.position.x + 30, PANEL.position.y + 62)
	add_child(sub_l)

	pips_label = UIKit.label("", 22, UIKit.TEAL)
	pips_label.position = Vector2(PANEL.end.x - 260, PANEL.position.y + 26)
	add_child(pips_label)

	status_label = UIKit.label("", 18, UIKit.DIM)
	status_label.position = Vector2(PANEL.position.x + 30, PANEL.end.y - 84)
	add_child(status_label)

	var hint_l: = UIKit.label(hint + "   ·   [Esc] отойти", 15, UIKit.DIM)
	hint_l.position = Vector2(PANEL.position.x + 30, PANEL.end.y - 46)
	add_child(hint_l)

	zeroday_label = UIKit.label("", 16, UIKit.AMBER)
	zeroday_label.position = Vector2(PANEL.end.x - 260, PANEL.end.y - 46)
	add_child(zeroday_label)
	_update_zeroday()

	free_miss_left = free_miss_per_round
	_update_pips()
	_new_round()

func _process(_delta: float) -> void:
	_noise_seed += _delta
	queue_redraw()

func game_delta(delta: float) -> float:
	if Time.get_ticks_msec() / 1000.0 < slow_until:
		return delta * 0.45
	return delta

func slow_for(sec: float) -> void:
	slow_until = Time.get_ticks_msec() / 1000.0 + sec
	set_status("ТЕРМОЗРЕНИЕ: время замедлено", UIKit.AMBER)

func set_status(text: String, color: = UIKit.DIM) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", color)

func miss(what: = "промах") -> bool:
	if silent:
		set_status("ТИХИЙ РЕЖИМ НАРУШЕН — сейф захлопнулся", UIKit.MAGENTA)
		Sfx.play("round_fail")
		GameState.stats["fails"] += 1
		round_result.emit(false)
		_finished = true
		finished.emit(false)
		return true
	if free_miss_left > 0:
		free_miss_left -= 1
		set_status("%s — прощён (пассивка)" % what, UIKit.AMBER)
		Sfx.play("ui_click", -6.0, 0.7)
		return false
	round_fail()
	return true

func round_success() -> void:
	if _finished:
		return
	GameState.stats["rounds"] += 1
	rounds_done += 1
	free_miss_left = free_miss_per_round
	round_result.emit(true)
	_update_pips()
	if rounds_done >= rounds_needed:
		_finish(true)
	else:
		Sfx.play("round_ok")
		set_status("СЕГМЕНТ ВЗЛОМАН ▸ следующий", UIKit.TEAL)
		_new_round()

func round_fail() -> void:
	if _finished:
		return
	GameState.stats["rounds"] += 1
	GameState.stats["fails"] += 1
	free_miss_left = free_miss_per_round
	round_result.emit(false)
	Sfx.play("round_fail")
	set_status("ПРОВАЛ — СИСТЕМА УСЛЫШАЛА (тревога растёт)", UIKit.MAGENTA)
	_restart_round()

func abort() -> void:
	if _finished:
		return
	_finished = true
	finished.emit(false)

func force_round_success() -> void:
	set_status("ЭКСПЛОЙТ: сегмент вскрыт мгновенно", UIKit.TEAL)
	round_success()

func force_layer_success() -> void:
	## 0-day: сейф вскрывается целиком
	if _finished:
		return
	set_status("0-DAY: ЗАМОК ВЫБИТ МГНОВЕННО", UIKit.AMBER)
	while rounds_done < rounds_needed - 1:
		rounds_done += 1
		round_result.emit(true)
	_update_pips()
	round_success()

func _finish(success: bool) -> void:
	_finished = true
	Sfx.play("layer_done")
	set_status("СЕЙФ ВСКРЫТ // забирай, пока не спалили", UIKit.TEAL)
	await get_tree().create_timer(0.7).timeout
	finished.emit(success)

func _update_pips() -> void:
	pips_label.text = "СЕГМЕНТЫ  " + "▰".repeat(rounds_done) + "▱".repeat(maxi(rounds_needed - rounds_done, 0))

func _update_zeroday() -> void:
	if GameState.zero_days > 0:
		zeroday_label.text = "[F] 0-day эксплойт × %d" % GameState.zero_days
	else:
		zeroday_label.text = ""

func _new_round() -> void:
	pass

func _restart_round() -> void:
	_new_round()

# ── отрисовка общих элементов ──────────────────────────────

func _draw_frame() -> void:
	var c: Color = layer["color"]
	draw_rect(PANEL, Color(0.008, 0.02, 0.036, 0.96), true)
	draw_rect(PANEL, Color(c.r, c.g, c.b, 0.8), false, 2.0)
	draw_rect(PLAY, Color(0.004, 0.012, 0.024, 0.9), true)
	draw_rect(PLAY, Color(c.r, c.g, c.b, 0.25), false, 1.0)
	if silent:
		draw_rect(PANEL.grow(4.0), Color(1.0, 0.26, 0.46, 0.5 + 0.3 * sin(_noise_seed * 4.0)), false, 2.0)

func _draw_noise_overlay() -> void:
	if not noise:
		return
	var rng: = RandomNumberGenerator.new()
	rng.seed = int(_noise_seed * 14.0)
	for i in 26:
		var r: = Rect2(
			PLAY.position.x + rng.randf() * PLAY.size.x,
			PLAY.position.y + rng.randf() * PLAY.size.y,
			rng.randf_range(20.0, 150.0), rng.randf_range(2.0, 7.0))
		draw_rect(r, Color(0.5, 0.85, 1.0, rng.randf_range(0.03, 0.16)), true)
	for y in range(int(PLAY.position.y), int(PLAY.end.y), 5):
		draw_line(Vector2(PLAY.position.x, y), Vector2(PLAY.end.x, y), Color(0.0, 0.0, 0.0, 0.12))

func _draw_timer_bar(ratio: float) -> void:
	var r: = Rect2(PLAY.position.x, PLAY.end.y + 12, PLAY.size.x * clampf(ratio, 0.0, 1.0), 8)
	var col: = UIKit.CYAN if ratio > 0.35 else UIKit.MAGENTA
	draw_rect(Rect2(PLAY.position.x, PLAY.end.y + 12, PLAY.size.x, 8), Color(0.03, 0.07, 0.1), true)
	draw_rect(r, col, true)
