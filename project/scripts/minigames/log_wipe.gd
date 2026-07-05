extends MinigameBase

## «Зачистка логов»: записи о вашем следе всплывают в консоли IDS.
## Кликай их до фиксации. 3 зафиксированных записи = провал раунда.

var entries: Array = []
var wiped: = 0
var wipe_target: = 8
var committed: = 0
var spawn_timer: = 0.0
var spawn_interval: = 1.1
var life_time: = 2.2

const LINES: = [
	"TRACE: аномальный процесс PID %d",
	"WARN: подпись не верифицирована 0x%04X",
	"NET: неопознанный трафик порт %d",
	"AUTH: несанкционированный ключ #%d",
	"HEUR: поведенческий триггер %d",
]

func _init() -> void:
	rounds_needed = 2
	hint = "кликай записи журнала, пока IDS их не зафиксировал · 3 фиксации = провал"

func _apply_difficulty(diff: int) -> void:
	if diff >= 2:
		rounds_needed = 3

func _new_round() -> void:
	entries.clear()
	wiped = 0
	committed = 0
	wipe_target = 7 + rounds_done * 2 + difficulty
	spawn_interval = maxf(1.25 - 0.12 * float(rounds_done) - 0.08 * float(difficulty), 0.55) * timer_mult
	life_time = maxf(2.5 - 0.15 * float(rounds_done) - 0.12 * float(difficulty), 1.3) * timer_mult
	spawn_timer = 0.4
	set_status("журнал IDS пишет ваш след — стирайте!", UIKit.DIM)

func _restart_round() -> void:
	_new_round()

func _spawn_entry() -> void:
	var y: = PLAY.position.y + 30.0 + randf() * (PLAY.size.y - 90.0)
	var x: = PLAY.position.x + 30.0 + randf() * (PLAY.size.x - 420.0)
	entries.append({
		"pos": Vector2(x, y),
		"text": LINES.pick_random() % randi_range(100, 9999),
		"life": life_time,
		"drift": Vector2(randf_range(-30, 30), randf_range(-14, 14)) if moving else Vector2.ZERO,
	})

func _process(delta: float) -> void:
	super._process(delta)
	if _finished:
		return
	var gd: = game_delta(delta)
	spawn_timer -= gd
	if spawn_timer <= 0.0 and wiped + entries.size() + committed < wipe_target + 3:
		spawn_timer = spawn_interval
		_spawn_entry()
	for e in entries.duplicate():
		e["life"] -= gd
		e["pos"] += e["drift"] * gd
		if e["life"] <= 0.0:
			entries.erase(e)
			committed += 1
			Sfx.play("trap", -10.0, 1.4)
			if committed >= 3:
				miss("IDS зафиксировал след")
				return
	if wiped >= wipe_target:
		round_success()

func _gui_input(event: InputEvent) -> void:
	if _finished:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mp: Vector2 = event.position
		for e in entries:
			var rect: = Rect2(e["pos"] - Vector2(8, 18), Vector2(360, 30))
			if rect.has_point(mp):
				entries.erase(e)
				wiped += 1
				Sfx.play("ui_click", -6.0, 1.2)
				set_status("стёрто %d/%d" % [wiped, wipe_target], UIKit.TEAL)
				accept_event()
				return

func _draw() -> void:
	_draw_frame()
	var font: = get_theme_default_font()
	# псевдо-фон консоли
	for i in 14:
		var y: = PLAY.position.y + 24.0 + float(i) * 28.0
		draw_string(font, Vector2(PLAY.position.x + 16, y), "0x%08X  ..  ok" % (i * 4919 + int(_noise_seed * 3.0) * 13),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.2, 0.35, 0.42, 0.35))
	for e in entries:
		var urgency: float = 1.0 - e["life"] / life_time
		var col: = UIKit.AMBER.lerp(Color(1.0, 0.2, 0.28), urgency)
		var rect: = Rect2(e["pos"] - Vector2(8, 18), Vector2(360, 30))
		if blackout and urgency < 0.35:
			# затемнение: запись видна только когда почти зафиксирована
			draw_rect(rect, Color(col.r, col.g, col.b, 0.06), true)
			continue
		draw_rect(rect, Color(0.08, 0.03, 0.04, 0.85), true)
		draw_rect(rect, Color(col.r, col.g, col.b, 0.6 + 0.4 * urgency), false, 1.5)
		draw_string(font, e["pos"], "▶ " + e["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)
		draw_rect(Rect2(rect.position.x, rect.end.y - 3, rect.size.x * (e["life"] / life_time), 3), col, true)
	var font2: = get_theme_default_font()
	draw_string(font2, Vector2(PLAY.position.x + 24, PLAY.position.y + PLAY.size.y - 12),
		"стёрто %d/%d · фиксаций %d/3" % [wiped, wipe_target, committed], HORIZONTAL_ALIGNMENT_LEFT, -1, 17,
		UIKit.MAGENTA if committed >= 2 else UIKit.DIM)
	_draw_noise_overlay()
