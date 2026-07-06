extends Control

## Дерево эволюции в стиле созвездия: тёмное полотно, орбы-узлы,
## светящиеся связи, ветки по кругу, панель атрибутов справа.
## Колесо мыши — зум, наведение — тултип, клик — прокачка. [Tab]/[Esc] — закрыть.

signal closed

const BG_TOP: = Color(0.10, 0.03, 0.14)
const BG_BOTTOM: = Color(0.03, 0.01, 0.06)
const EDGE_DIM: = Color(0.45, 0.25, 0.12, 0.5)
const ORB_LOCKED: = Color(0.16, 0.15, 0.17)
const ORB_OPEN: = Color(0.85, 0.62, 0.3)
const ORB_DONE: = Color(1.0, 0.85, 0.5)

var zoom: = 1.0
var nodes: Array = []        # модель узлов дерева
var hover_id: = -1
var _t: = 0.0
var _stars: Array = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	for i in 90:
		_stars.append({
			"pos": Vector2(randf() * 1600.0, randf() * 900.0),
			"r": randf_range(1.0, 3.2), "a": randf_range(0.05, 0.3), "ph": randf() * TAU,
		})
	_build_model()
	set_process(true)

func _center() -> Vector2:
	return size * 0.5 if size.length() > 10.0 else Vector2(800, 450)

# ── модель дерева ───────────────────────────────────────────

func _build_model() -> void:
	## позиции в «мировых» координатах дерева (до зума), центр = (0,0)
	nodes.clear()
	# ядро — прото-штамм
	nodes.append({"id": 0, "kind": "core", "pos": Vector2.ZERO, "r": 34.0, "link": -1})
	var nid: = 1
	var count: = GameState.BRANCHES.size()
	for i in count:
		var cls: String = GameState.BRANCHES[i]
		var ang: = TAU * float(i) / float(count) - PI * 0.5
		var dir: = Vector2(cos(ang), sin(ang))
		# УР.1 → ворота ветки → УР.2 → активки → УР.3 → финальная активка
		var lvl1: = nid
		nodes.append({"id": nid, "kind": "level", "lvl": 1, "cls": cls, "pos": dir * 105.0, "r": 13.0, "link": 0})
		nid += 1
		var gate: = nid
		nodes.append({"id": nid, "kind": "branch", "cls": cls, "pos": dir * 175.0, "r": 26.0, "link": lvl1})
		nid += 1
		var lvl2: = nid
		nodes.append({"id": nid, "kind": "level", "lvl": 2, "cls": cls, "pos": dir * 245.0, "r": 13.0, "link": gate})
		nid += 1
		# три активки веером
		var pool: Array = GameState.BRANCH_ABILITIES[cls]
		var fan: = [-0.16, 0.0, 0.16]
		var ab_ids: Array = []
		for k in 3:
			var a2: float = ang + fan[k]
			var d2: = Vector2(cos(a2), sin(a2))
			var rr: = 310.0 if k != 1 else 330.0
			nodes.append({"id": nid, "kind": "ability", "cls": cls, "ability": pool[k],
				"slot": k, "pos": d2 * rr, "r": 17.0 if k == 0 else 15.0, "link": lvl2 if k != 2 else -1})
			ab_ids.append(nid)
			nid += 1
		var lvl3: = nid
		nodes.append({"id": nid, "kind": "level", "lvl": 3, "cls": cls, "pos": dir * 395.0, "r": 13.0, "link": ab_ids[1]})
		nid += 1
		# третья активка цепляется за УР.3
		nodes[ab_ids[2]]["link"] = lvl3
		nodes[ab_ids[2]]["pos"] = Vector2(cos(ang + 0.24), sin(ang + 0.24)) * 415.0
		# узел доп. ветки (виден на УР.3)
		nodes.append({"id": nid, "kind": "secondary", "cls": cls, "pos": dir * 455.0, "r": 15.0, "link": lvl3})
		nid += 1

func _node_screen_pos(n: Dictionary) -> Vector2:
	var p: Vector2 = n["pos"]
	return _center() + p * zoom

func _my_branch_active(cls: String) -> bool:
	return GameState.branch == cls or GameState.secondary_branch == cls

# ── состояние узла: locked / open (можно взять) / done ──────

func _node_state(n: Dictionary) -> String:
	match n["kind"]:
		"core":
			return "done"
		"level":
			var cls: String = n["cls"]
			var lvl: int = n["lvl"]
			if GameState.branch == cls and GameState.virus_level >= lvl:
				return "done"
			if GameState.branch == cls and GameState.virus_level == lvl - 1 and GameState.can_level_up():
				return "open"
			if GameState.branch == "" and lvl == 1:
				return "hint" # сначала ветка
			return "locked"
		"branch":
			var cls2: String = n["cls"]
			if _my_branch_active(cls2):
				return "done"
			if GameState.branch == "":
				return "open"
			if GameState.virus_level >= 3 and GameState.secondary_branch == "":
				return "open" # доп. ветка
			return "locked"
		"ability":
			var ab: String = n["ability"]
			if ab in GameState.active_abilities:
				return "done"
			if GameState.can_pick_ability(ab):
				return "open"
			if n["cls"] in [GameState.branch, GameState.secondary_branch] and ab in GameState.ability_pool():
				return "task" # видна, но заперта заданием/уровнем
			return "locked"
		"secondary":
			if GameState.secondary_branch == n["cls"]:
				return "done"
			if GameState.virus_level >= 3 and GameState.secondary_branch == "" and n["cls"] != GameState.branch:
				return "open"
			return "locked"
	return "locked"

func _node_color(n: Dictionary, state: String) -> Color:
	var cls_col: Color = GameState.CLASSES.get(n.get("cls", "base"), {}).get("color", ORB_OPEN)
	match state:
		"done":
			return ORB_DONE if n["kind"] == "level" or n["kind"] == "core" else cls_col
		"open":
			return ORB_OPEN
		"task":
			return Color(0.55, 0.45, 0.3)
		"hint":
			return Color(0.5, 0.42, 0.28)
	return ORB_LOCKED

# ── отрисовка ───────────────────────────────────────────────

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var sz: = size
	# фон: тёмно-фиолетовый градиент + звёзды
	draw_rect(Rect2(Vector2.ZERO, sz), BG_BOTTOM)
	var steps: = 14
	for i in steps:
		var f: = float(i) / float(steps)
		var col: = BG_TOP.lerp(BG_BOTTOM, f)
		col.a = 0.5
		draw_rect(Rect2(Vector2(0, sz.y * f / 1.6), Vector2(sz.x, sz.y / float(steps))), col)
	for s in _stars:
		var a: float = s["a"] * (0.6 + 0.4 * sin(_t * 1.4 + s["ph"]))
		draw_circle(Vector2(s["pos"].x / 1600.0 * sz.x, s["pos"].y / 900.0 * sz.y), s["r"], Color(0.7, 0.6, 0.9, a))
	# золотая арка сверху (как в референсе)
	draw_arc(Vector2(sz.x * 0.5, -sz.y * 0.9), sz.y * 1.12, PI * 0.28, PI * 0.72, 60, Color(0.85, 0.65, 0.3, 0.35), 3.0)

	# связи
	for n in nodes:
		var link: int = n["link"]
		if link < 0:
			continue
		var a: = _node_screen_pos(nodes[link])
		var b: = _node_screen_pos(n)
		var st: = _node_state(n)
		var active: = st == "done"
		var col: = EDGE_DIM
		var w: = 2.0
		if active:
			var cc: = _node_color(n, "done")
			col = Color(cc.r, cc.g, cc.b, 0.9)
			w = 3.5
		elif st == "open":
			col = Color(0.9, 0.65, 0.3, 0.75)
			w = 2.5
		draw_line(a, b, Color(col.r, col.g, col.b, col.a * 0.35), w + 4.0)
		draw_line(a, b, col, w)
		# бегущая искра по активным связям
		if active:
			var f: = fmod(_t * 0.6 + float(n["id"]) * 0.13, 1.0)
			draw_circle(a.lerp(b, f), 3.0, Color(1.0, 0.85, 0.5, 0.9))

	# узлы-орбы
	for n in nodes:
		var p: = _node_screen_pos(n)
		var st: = _node_state(n)
		var col: = _node_color(n, st)
		var r: float = n["r"] * zoom
		var hovered: bool = n["id"] == hover_id
		# свечение
		if st != "locked":
			var pulse: = 1.0 + 0.12 * sin(_t * 2.4 + float(n["id"]))
			draw_circle(p, r * 1.7 * pulse, Color(col.r, col.g, col.b, 0.10))
			draw_circle(p, r * 1.32 * pulse, Color(col.r, col.g, col.b, 0.16))
		# тело орба с бликом
		draw_circle(p, r, col.darkened(0.35))
		draw_circle(p, r * 0.86, col)
		draw_circle(p + Vector2(-r * 0.25, -r * 0.3), r * 0.34, Color(1, 1, 1, 0.28 if st != "locked" else 0.08))
		# кольца выделения
		if st == "done":
			draw_arc(p, r + 3.0 * zoom, 0, TAU, 40, Color(col.r, col.g, col.b, 0.9), 2.0)
		if st == "open":
			draw_arc(p, r + 4.0 * zoom + sin(_t * 3.0) * 1.5, 0, TAU, 40, Color(1.0, 0.8, 0.4, 0.8), 2.0)
		if hovered:
			draw_arc(p, r + 7.0 * zoom, 0, TAU, 40, Color(1, 1, 1, 0.85), 2.0)
		# руна/буква
		var font: = get_theme_default_font()
		var glyph: = ""
		match n["kind"]:
			"core": glyph = "◉"
			"level": glyph = str(n["lvl"])
			"branch": glyph = GameState.CLASSES[n["cls"]]["name"].left(1)
			"ability": glyph = GameState.ABILITIES[n["ability"]]["name"].left(1)
			"secondary": glyph = "+"
		var fsize: = int(maxf(r * 0.95, 10.0))
		var tsz: = font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, fsize)
		draw_string(font, p + Vector2(-tsz.x * 0.5, tsz.y * 0.32), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize,
			Color(0.08, 0.05, 0.1) if st != "locked" else Color(0.35, 0.35, 0.4))

	# подписи веток по кругу
	var font2: = get_theme_default_font()
	for n in nodes:
		if n["kind"] != "branch":
			continue
		var p: = _node_screen_pos(n)
		var cls: String = n["cls"]
		var info: Dictionary = GameState.CLASSES[cls]
		var name_s: String = info["name"]
		var active: = _my_branch_active(cls)
		var col: Color = info["color"] if active or GameState.branch == "" else Color(0.4, 0.38, 0.45)
		var tsz: = font2.get_string_size(name_s, HORIZONTAL_ALIGNMENT_CENTER, -1, 19)
		var dir: Vector2 = (n["pos"] as Vector2).normalized()
		var lp: = p + dir * (34.0 * zoom + 22.0) + Vector2(-tsz.x * 0.5, 6.0)
		draw_string(font2, lp + Vector2(1, 1), name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0, 0, 0, 0.7))
		draw_string(font2, lp, name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, col)

	_draw_stats_panel()
	_draw_tooltip()
	_draw_footer()

func _draw_stats_panel() -> void:
	## атрибуты справа, как в референсе
	var font: = get_theme_default_font()
	var x: = size.x - 40.0
	var y: = 40.0
	var info: Dictionary = GameState.class_info()
	var attrs: Dictionary = info.get("attrs", {})
	var rows: = [
		["ШТАММ", String(info["name"])],
		["УРОВЕНЬ", str(GameState.virus_level)],
		["", ""],
		["СИЛА", str(int(attrs.get("str", 4)))],
		["ЛОВКОСТЬ", str(int(attrs.get("dex", 4)))],
		["ИНТЕЛЛЕКТ", str(int(attrs.get("int", 4)))],
		["", ""],
		["СКОРОСТЬ", "+%.1f" % GameState.evo_bonus("speed")],
		["СКРЫТНОСТЬ", "+%d%%" % int(GameState.evo_bonus("stealth") * 100.0)],
		["BANDWIDTH", "+%d" % int(GameState.evo_bonus("bw"))],
		["HP", "+%d" % int(GameState.evo_bonus("vitality"))],
	]
	for row in rows:
		var label: String = row[0]
		var value: String = row[1]
		if label == "":
			y += 14.0
			continue
		var lsz: = font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 15)
		draw_string(font, Vector2(x - lsz.x, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.65, 0.6, 0.75))
		y += 24.0
		var vsz: = font.get_string_size(value, HORIZONTAL_ALIGNMENT_CENTER, -1, 24)
		draw_string(font, Vector2(x - vsz.x, y), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.95, 0.92, 1.0))
		y += 30.0
	# ресурсы слева сверху (монетка)
	var r: Dictionary = GameState.resources
	draw_circle(Vector2(46, 44), 15.0, Color(0.9, 0.7, 0.3))
	draw_circle(Vector2(46, 44), 11.0, Color(0.65, 0.45, 0.15))
	draw_string(font, Vector2(70, 52), "%d ◈  ·  %d ◇  ·  %d ✦" % [r["data_fragments"], r["code_samples"], r["mutagen"]],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.95, 0.9, 1.0))

func _draw_tooltip() -> void:
	if hover_id < 0 or hover_id >= nodes.size():
		return
	var n: Dictionary = nodes[hover_id]
	var st: = _node_state(n)
	var title: = ""
	var lines: Array = []
	match n["kind"]:
		"core":
			title = "ПРОТО-ШТАММ"
			lines.append("исходная форма — с этого начинают все")
		"level":
			var lvl: int = n["lvl"]
			title = String(GameState.LEVELS[lvl]["title"])
			lines.append(String(GameState.LEVELS[lvl]["perks"]))
			if st == "open":
				lines.append("КЛИК: эволюция за %s" % _cost_text(GameState.level_cost(lvl)))
			elif st == "hint":
				lines.append("сначала выбери ветку (большой узел)")
			elif st == "locked" and GameState.branch != "" and n["cls"] != GameState.branch:
				lines.append("это спица другой ветки")
		"branch":
			var info: Dictionary = GameState.CLASSES[n["cls"]]
			title = "%s — %s" % [info["name"], info["role"]]
			lines.append(String(info["passive"]))
			if GameState.branch == "":
				lines.append("КЛИК: выбрать направленность (только одна!)")
			elif st == "open":
				lines.append("КЛИК: взять ДОП. ВЕТКОЙ (УР.3)")
		"ability":
			var ab: Dictionary = GameState.ABILITIES[n["ability"]]
			title = String(ab["name"])
			lines.append(String(ab["desc"]))
			lines.append("расход: %d BW" % int(GameState.ability_cost(n["ability"])))
			var slot: = GameState.active_abilities.size()
			if st == "open":
				lines.append("КЛИК: экипировать в слот %d" % (slot + 1))
			elif st == "task":
				if slot < 3 and not GameState.ability_task_done(slot):
					lines.append("ЗАДАНИЕ: %s" % GameState.ability_task_progress(slot))
				else:
					lines.append("нужен уровень штамма выше")
		"secondary":
			title = "ДОП. ВЕТКА: %s" % GameState.CLASSES[n["cls"]]["name"]
			lines.append("элементы её скина и умения добавятся к текущим")
			if st == "open":
				lines.append("КЛИК: взять вторую направленность")
			elif GameState.virus_level < 3:
				lines.append("откроется на УР.3")
	# панель
	var font: = get_theme_default_font()
	var w: = 380.0
	var h: = 44.0 + float(lines.size()) * 24.0
	var mp: = get_local_mouse_position() + Vector2(24, -h * 0.5)
	mp.x = clampf(mp.x, 10.0, size.x - w - 10.0)
	mp.y = clampf(mp.y, 10.0, size.y - h - 10.0)
	draw_rect(Rect2(mp, Vector2(w, h)), Color(0.06, 0.03, 0.1, 0.94))
	draw_rect(Rect2(mp, Vector2(w, h)), Color(0.85, 0.65, 0.3, 0.7), false, 2.0)
	draw_string(font, mp + Vector2(14, 28), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(1.0, 0.85, 0.5))
	var yy: = 52.0
	for line in lines:
		draw_string(font, mp + Vector2(14, yy), String(line), HORIZONTAL_ALIGNMENT_LEFT, w - 28.0, 15, Color(0.85, 0.82, 0.95))
		yy += 24.0

func _draw_footer() -> void:
	var font: = get_theme_default_font()
	var text: = "🖱 Колесо — зум · клик — прокачка · ESC/Tab — закрыть"
	var tsz: = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 17)
	draw_string(font, Vector2(size.x - tsz.x - 30.0, size.y - 22.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.75, 0.7, 0.85))
	if GameState.branch == "":
		var hint: = "выбери направленность: кликни большой узел ветки"
		draw_string(font, Vector2(30.0, size.y - 22.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.9, 0.7, 0.4))

func _cost_text(cost: Dictionary) -> String:
	var parts: Array = []
	var icons: = {"data_fragments": "◈", "code_samples": "◇", "mutagen": "✦"}
	for key in cost:
		parts.append("%s %d" % [icons.get(key, key), cost[key]])
	return " · ".join(parts) if not parts.is_empty() else "бесплатно"

# ── ввод ────────────────────────────────────────────────────

func _pick_node(mp: Vector2) -> int:
	var best: = -1
	var best_d: = 999.0
	for n in nodes:
		var d: = mp.distance_to(_node_screen_pos(n))
		if d < maxf(n["r"] * zoom + 8.0, 16.0) and d < best_d:
			best_d = d
			best = n["id"]
	return best

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hover_id = _pick_node(event.position)
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				zoom = clampf(zoom * 1.1, 0.55, 1.7)
			MOUSE_BUTTON_WHEEL_DOWN:
				zoom = clampf(zoom / 1.1, 0.55, 1.7)
			MOUSE_BUTTON_LEFT:
				_click_node(_pick_node(event.position))

func _click_node(id: int) -> void:
	if id < 0 or id >= nodes.size():
		return
	var n: Dictionary = nodes[id]
	var st: = _node_state(n)
	if st != "open":
		Sfx.play("ui_click", -8.0, 0.6)
		return
	var ok: = false
	match n["kind"]:
		"level":
			ok = GameState.level_up()
		"branch":
			if GameState.branch == "":
				ok = GameState.choose_branch(n["cls"])
			else:
				ok = GameState.choose_secondary(n["cls"])
		"ability":
			ok = GameState.pick_ability(n["ability"])
		"secondary":
			ok = GameState.choose_secondary(n["cls"])
	if ok:
		Sfx.play("hack_win", -5.0, 1.3)
	else:
		Sfx.play("ui_click", -6.0, 0.6)

var _open_time: = 0.0

func _unhandled_input(event: InputEvent) -> void:
	# защита от закрытия тем же нажатием Tab, что открыло панель
	if Time.get_ticks_msec() / 1000.0 - _open_time < 0.2:
		return
	if event.is_action_pressed("evolve") or event.is_action_pressed("pause"):
		accept_event()
		closed.emit()

func _enter_tree() -> void:
	_open_time = Time.get_ticks_msec() / 1000.0
