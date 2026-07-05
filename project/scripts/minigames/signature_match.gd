extends MinigameBase

## «Маскировка подписи»: найди среди кандидатов подпись, побайтно совпадающую
## с целевой. Ошибка на одну пару глифов — почти незаметна. Внимание решает.

const GLYPHS: = "◈◇◆▲△▣▤▥▦◉○●□▪◬"

var target_sig: = ""
var options: Array = []
var correct_idx: = 0
var buttons: Array = []
var round_time: = 14.0
var time_left: = 14.0
var hide_target: = false

func _init() -> void:
	rounds_needed = 3
	hint = "выбери кандидата, чья подпись СОВПАДАЕТ с целевой"

func _apply_difficulty(diff: int) -> void:
	if diff >= 3:
		rounds_needed = 4

func _new_round() -> void:
	var sig_len: = 6 + rounds_done + difficulty
	round_time = maxf(15.0 - 1.2 * float(rounds_done) - 1.0 * float(difficulty), 7.0) * timer_mult
	time_left = round_time
	hide_target = false
	target_sig = ""
	for i in sig_len:
		target_sig += GLYPHS[randi() % GLYPHS.length()]
	var count: = 4
	correct_idx = randi() % count
	options.clear()
	for i in count:
		if i == correct_idx:
			options.append(target_sig)
		else:
			options.append(_mutate(target_sig))
	_rebuild_buttons()
	if blackout:
		# затемнение: цель показывается 2.5с и гаснет — работаем по памяти
		get_tree().create_timer(2.5).timeout.connect(func() -> void: hide_target = true)
	set_status("сравнивай побайтно…", UIKit.DIM)

func _restart_round() -> void:
	_new_round()

func _mutate(sig: String) -> String:
	var s: = sig
	var idx: = randi() % s.length()
	var g: = GLYPHS[randi() % GLYPHS.length()]
	while g == s[idx]:
		g = GLYPHS[randi() % GLYPHS.length()]
	s = s.substr(0, idx) + g + s.substr(idx + 1)
	if randf() < 0.3 and s.length() > 2:
		var j: = randi() % (s.length() - 1)
		s = s.substr(0, j) + s[j + 1] + s[j] + s.substr(j + 2)
	return s

func _rebuild_buttons() -> void:
	for b in buttons:
		b.queue_free()
	buttons.clear()
	for i in options.size():
		var btn: = Button.new()
		btn.text = options[i]
		btn.add_theme_font_size_override("font_size", 30)
		btn.custom_minimum_size = Vector2(PLAY.size.x - 260, 62)
		btn.position = Vector2(PLAY.position.x + 130, PLAY.position.y + 116 + float(i) * 74.0)
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_stylebox_override("normal", UIKit.panel_box(Color(0.3, 0.45, 0.55, 0.6), Color(0.02, 0.05, 0.08, 0.9), 1, 6, 8))
		btn.add_theme_stylebox_override("hover", UIKit.panel_box(UIKit.CYAN, Color(0.04, 0.1, 0.14, 0.95), 1, 6, 8))
		btn.add_theme_color_override("font_color", UIKit.WHITE)
		btn.pressed.connect(_on_pick.bind(i))
		add_child(btn)
		buttons.append(btn)

func _on_pick(i: int) -> void:
	if _finished:
		return
	if i == correct_idx:
		round_success()
	else:
		miss("подпись отвергнута")

func _process(delta: float) -> void:
	super._process(delta)
	if _finished:
		return
	time_left -= game_delta(delta)
	if time_left <= 0.0:
		miss("окно проверки закрылось")
	if moving:
		# подвижная цель: кандидаты медленно меняются местами
		for i in buttons.size():
			var base_y: = PLAY.position.y + 116 + float(i) * 74.0
			buttons[i].position.y = base_y + sin(_noise_seed * 1.6 + float(i) * 2.1) * 18.0

func _draw() -> void:
	_draw_frame()
	var font: = get_theme_default_font()
	draw_string(font, Vector2(PLAY.position.x + 30, PLAY.position.y + 52), "ЦЕЛЕВАЯ ПОДПИСЬ:", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UIKit.DIM)
	var shown: = target_sig if not hide_target else "▓".repeat(target_sig.length())
	draw_string(font, Vector2(PLAY.position.x + 260, PLAY.position.y + 56), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 34,
		UIKit.AMBER if not hide_target else Color(0.4, 0.35, 0.3))
	if hide_target:
		draw_string(font, Vector2(PLAY.position.x + 30, PLAY.position.y + 80), "(по памяти)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIKit.DIM)
	_draw_timer_bar(time_left / round_time)
	_draw_noise_overlay()
