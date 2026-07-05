extends MinigameBase

## «Маршрутизация пакета»: проведи пакет через лабиринт портов до цели.
## Стрелки двигают пакет по клеткам; закрытые узлы сжигают пакет.
## Мутатор «подвижная цель» — стены перестраиваются каждые несколько секунд.

const CW: = 11
const CH: = 7

var walls: = {}
var packet: = Vector2i.ZERO
var goal: = Vector2i.ZERO
var trail: Array = []
var round_time: = 22.0
var time_left: = 22.0
var _shift_timer: = 0.0
var _burn_flash: = 0.0

func _init() -> void:
	rounds_needed = 2
	hint = "стрелки/WASD — вести пакет · красные порты закрыты · дойди до ЦЕЛИ"

func _apply_difficulty(diff: int) -> void:
	if diff >= 2:
		rounds_needed = 3

func _new_round() -> void:
	round_time = maxf(24.0 - 2.0 * float(rounds_done) - 2.0 * float(difficulty), 11.0) * timer_mult
	time_left = round_time
	_generate_maze()
	packet = Vector2i(0, CH / 2)
	goal = Vector2i(CW - 1, randi_range(0, CH - 1))
	trail = [packet]
	while walls.get(goal, false):
		goal = Vector2i(CW - 1, randi_range(0, CH - 1))
	set_status("ведите пакет к цели", UIKit.DIM)

func _restart_round() -> void:
	packet = Vector2i(0, CH / 2)
	trail = [packet]
	time_left = round_time

func _generate_maze() -> void:
	var density: = 0.26 + 0.04 * float(difficulty) + 0.03 * float(rounds_done)
	for attempt in 40:
		walls.clear()
		for x in CW:
			for y in CH:
				if x == 0 or randf() > density:
					continue
				walls[Vector2i(x, y)] = true
		if _path_exists(Vector2i(0, CH / 2), Vector2i(CW - 1, 0), true):
			return
	walls.clear()

func _path_exists(from: Vector2i, _to: Vector2i, any_right_col: = false) -> bool:
	var seen: = {from: true}
	var queue: = [from]
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		if any_right_col and p.x == CW - 1:
			return true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var np: Vector2i = p + d
			if np.x < 0 or np.y < 0 or np.x >= CW or np.y >= CH:
				continue
			if seen.has(np) or walls.get(np, false):
				continue
			seen[np] = true
			queue.append(np)
	return false

func _shift_walls() -> void:
	# подвижная цель: пара стен телепортируется (с гарантией прохода)
	for attempt in 10:
		var keys: Array = walls.keys()
		if keys.size() < 4:
			return
		for i in 3:
			walls.erase(keys.pick_random())
		for i in 3:
			var p: = Vector2i(randi_range(1, CW - 2), randi_range(0, CH - 1))
			if p != packet and p != goal:
				walls[p] = true
		if _path_exists(packet, goal, true):
			return
	# не нашли валидную перестановку — просто чистим пару стен
	for i in 3:
		if not walls.is_empty():
			walls.erase(walls.keys().pick_random())

func _cell_rect(c: Vector2i) -> Rect2:
	var cell_w: = (PLAY.size.x - 60.0) / float(CW)
	var cell_h: = (PLAY.size.y - 60.0) / float(CH)
	var s: = minf(cell_w, cell_h)
	var ox: = PLAY.position.x + (PLAY.size.x - s * CW) * 0.5
	var oy: = PLAY.position.y + (PLAY.size.y - s * CH) * 0.5
	return Rect2(ox + s * c.x + 2, oy + s * c.y + 2, s - 4, s - 4)

func _process(delta: float) -> void:
	super._process(delta)
	if _finished:
		return
	_burn_flash = maxf(_burn_flash - delta * 3.0, 0.0)
	time_left -= game_delta(delta)
	if time_left <= 0.0:
		miss("пакет истёк (TTL)")
		return
	if moving:
		_shift_timer += game_delta(delta)
		if _shift_timer > 3.5:
			_shift_timer = 0.0
			_shift_walls()

func _unhandled_input(event: InputEvent) -> void:
	if _finished or not (event is InputEventKey) or not event.pressed:
		return
	var dir: = Vector2i.ZERO
	if event.is_action_pressed("mg_left"):
		dir = Vector2i(-1, 0)
	elif event.is_action_pressed("mg_right"):
		dir = Vector2i(1, 0)
	elif event.is_action_pressed("mg_up"):
		dir = Vector2i(0, -1)
	elif event.is_action_pressed("mg_down"):
		dir = Vector2i(0, 1)
	if dir == Vector2i.ZERO:
		return
	accept_event()
	if mirror:
		dir = -dir
	var np: = packet + dir
	if np.x < 0 or np.y < 0 or np.x >= CW or np.y >= CH:
		return
	if walls.get(np, false):
		_burn_flash = 1.0
		miss("пакет сгорел в закрытом порту")
		return
	packet = np
	trail.append(packet)
	Sfx.play("ui_click", -14.0, randf_range(1.1, 1.3))
	if packet == goal:
		round_success()

func _draw() -> void:
	_draw_frame()
	var font: = get_theme_default_font()
	for x in CW:
		for y in CH:
			var c: = Vector2i(x, y)
			var r: = _cell_rect(c)
			if walls.get(c, false):
				var hide: = blackout and c.distance_to(packet) > 2.6
				if not hide:
					draw_rect(r, Color(0.55, 0.1, 0.16, 0.85), true)
					draw_rect(r, Color(1.0, 0.3, 0.35, 0.5), false, 1.0)
			else:
				draw_rect(r, Color(0.05, 0.12, 0.18, 0.5), true)
	# след пакета
	for i in trail.size():
		var a: = float(i) / float(maxi(trail.size(), 1))
		draw_rect(_cell_rect(trail[i]).grow(-6.0), Color(UIKit.CYAN.r, UIKit.CYAN.g, UIKit.CYAN.b, 0.08 + 0.2 * a), true)
	# цель
	var gr: = _cell_rect(goal)
	draw_rect(gr, Color(UIKit.TEAL.r, UIKit.TEAL.g, UIKit.TEAL.b, 0.25 + 0.15 * sin(_noise_seed * 5.0)), true)
	draw_rect(gr, UIKit.TEAL, false, 2.0)
	draw_string(font, gr.position + Vector2(4, gr.size.y * 0.62), "ЦЕЛЬ", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.TEAL)
	# пакет
	var pr: = _cell_rect(packet)
	var pc: = Color.WHITE if _burn_flash <= 0.0 else Color(1.0, 0.3, 0.3)
	draw_rect(pr.grow(-4.0), UIKit.CYAN, true)
	draw_rect(pr.grow(-4.0), pc, false, 2.0)
	_draw_timer_bar(time_left / round_time)
	_draw_noise_overlay()
