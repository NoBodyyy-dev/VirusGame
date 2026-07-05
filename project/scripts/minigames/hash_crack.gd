extends MinigameBase

## «Взлом хэша»: набери ключ, кликая глифы на клавиатуре в правильном
## порядке — быстро, пока не сменился salt. Чистая скорость.

const KEYS: = "0123456789ABCDEF"

var target: = ""
var typed: = ""
var buttons: Array = []
var round_time: = 9.0
var time_left: = 9.0
var key_order: Array = []

func _init() -> void:
	rounds_needed = 3
	hint = "кликай символы ключа по порядку · ошибка сбрасывает ввод"

func _apply_difficulty(diff: int) -> void:
	if diff >= 3:
		rounds_needed = 4

func _ready() -> void:
	super._ready()
	_layout_keys()

func _layout_keys() -> void:
	for b in buttons:
		b.queue_free()
	buttons.clear()
	key_order = range(KEYS.length())
	if mirror:
		key_order.reverse()
	for i in KEYS.length():
		var btn: = Button.new()
		btn.text = KEYS[key_order[i]]
		btn.add_theme_font_size_override("font_size", 26)
		btn.custom_minimum_size = Vector2(88, 66)
		var col: = i % 8
		var row: = i / 8
		btn.position = Vector2(PLAY.position.x + 84 + float(col) * 96.0, PLAY.position.y + 210 + float(row) * 80.0)
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_stylebox_override("normal", UIKit.panel_box(Color(0.3, 0.45, 0.55, 0.6), Color(0.02, 0.05, 0.08, 0.9), 1, 6, 8))
		btn.add_theme_stylebox_override("hover", UIKit.panel_box(UIKit.CYAN, Color(0.04, 0.1, 0.14, 0.95), 1, 6, 8))
		btn.add_theme_color_override("font_color", UIKit.WHITE)
		btn.pressed.connect(_on_key_index.bind(i))
		add_child(btn)
		buttons.append(btn)

func _new_round() -> void:
	var length: = 5 + rounds_done + (1 if difficulty >= 2 else 0)
	target = ""
	for i in length:
		target += KEYS[randi() % KEYS.length()]
	typed = ""
	# скорость — ядро игры: время впритык
	round_time = (1.15 * float(length)) * timer_mult
	time_left = round_time
	set_status("ключ дампится — вводи!", UIKit.DIM)
	if moving:
		_shuffle_keys()

func _restart_round() -> void:
	_new_round()

func _shuffle_keys() -> void:
	key_order.shuffle()
	for i in buttons.size():
		buttons[i].text = KEYS[key_order[i]]

func _on_key_index(i: int) -> void:
	_on_key(KEYS[key_order[i]])

func _on_key(ch: String) -> void:
	if _finished:
		return
	if typed.length() < target.length() and target[typed.length()] == ch:
		typed += ch
		Sfx.play("ui_click", -8.0, 1.0 + 0.4 * float(typed.length()) / float(target.length()))
		if typed == target:
			round_success()
	else:
		typed = ""
		Sfx.play("ui_click", -4.0, 0.6)
		set_status("неверный символ — ввод сброшен", UIKit.MAGENTA)

func _process(delta: float) -> void:
	super._process(delta)
	if _finished:
		return
	time_left -= game_delta(delta)
	if time_left <= 0.0:
		miss("salt сменился")

func _draw() -> void:
	_draw_frame()
	var font: = get_theme_default_font()
	draw_string(font, Vector2(PLAY.position.x + 30, PLAY.position.y + 52), "КЛЮЧ:", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UIKit.DIM)
	var x: = PLAY.position.x + 150.0
	for i in target.length():
		var done: = i < typed.length()
		var ch: = target[i]
		if blackout and not done and i > typed.length() + 1:
			ch = "▓"
		var col: = UIKit.TEAL if done else (UIKit.WHITE if i == typed.length() else UIKit.DIM)
		draw_string(font, Vector2(x, PLAY.position.y + 58), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, col)
		if i == typed.length():
			draw_rect(Rect2(x - 4, PLAY.position.y + 68, 34, 3), UIKit.CYAN, true)
		x += 44.0
	draw_string(font, Vector2(PLAY.position.x + 30, PLAY.position.y + 120),
		"взломано %d/%d сегментов" % [rounds_done, rounds_needed], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UIKit.DIM)
	_draw_timer_bar(time_left / round_time)
	_draw_noise_overlay()
