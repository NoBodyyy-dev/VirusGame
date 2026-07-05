extends Control

## Дерево эволюции: ствол уровней 0..3, ветки-специализации (одна!),
## активки за задания, доп. ветка на УР.3.

signal closed

const COL_TRUNK: = Vector2(70, 120)     # колонка уровней
const COL_BRANCH: = Vector2(330, 120)   # колонка веток
const COL_ABILITY: = Vector2(760, 120)  # колонка активок

var res_label: Label
var level_boxes: Array = []
var levelup_btn: Button
var branch_cards: = {}
var ability_rows: = {}
var ability_hint: Label
var secondary_row: HBoxContainer
var secondary_label: Label
var tree_area: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim: = ColorRect.new()
	dim.color = Color(0, 0.005, 0.015, 0.85)
	add_child(UIKit.full_rect(dim))

	var center: = CenterContainer.new()
	add_child(UIKit.full_rect(center))
	var panel: = PanelContainer.new()
	panel.custom_minimum_size = Vector2(1460, 820)
	panel.add_theme_stylebox_override("panel", UIKit.panel_box(UIKit.TEAL, Color(0.008, 0.02, 0.036, 0.97), 1, 8, 20))
	center.add_child(panel)

	var v: = VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)

	var head: = HBoxContainer.new()
	head.add_theme_constant_override("separation", 24)
	v.add_child(head)
	head.add_child(UIKit.label("ДЕРЕВО ЭВОЛЮЦИИ", 28, UIKit.TEAL))
	res_label = UIKit.label("", 17, UIKit.WHITE)
	head.add_child(res_label)

	tree_area = Control.new()
	tree_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree_area.draw.connect(_draw_links)
	v.add_child(tree_area)

	_build_trunk()
	_build_branches()
	_build_abilities()
	_build_secondary()

	var close: = UIKit.button("  ЗАКРЫТЬ [Tab]  ", 18, UIKit.TEAL)
	close.pressed.connect(func() -> void: closed.emit())
	v.add_child(close)
	_refresh()

# ── ствол уровней ───────────────────────────────────────────

func _build_trunk() -> void:
	tree_area.add_child(_area_label("СТВОЛ // уровень штамма", Vector2(COL_TRUNK.x, 0), UIKit.CYAN))
	# снизу вверх: УР.0 внизу, УР.3 наверху
	for lvl in 4:
		var box: = PanelContainer.new()
		box.custom_minimum_size = Vector2(230, 96)
		box.position = Vector2(COL_TRUNK.x, COL_TRUNK.y + (3 - lvl) * 130.0)
		tree_area.add_child(box)
		var bv: = VBoxContainer.new()
		bv.add_theme_constant_override("separation", 2)
		box.add_child(bv)
		var info: Dictionary = GameState.LEVELS[lvl]
		bv.add_child(UIKit.label(info["title"], 17, UIKit.WHITE))
		var perks: = UIKit.label(info["perks"], 12, UIKit.DIM)
		perks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		perks.custom_minimum_size = Vector2(210, 0)
		bv.add_child(perks)
		level_boxes.append(box)
	levelup_btn = UIKit.button("", 15, UIKit.TEAL)
	levelup_btn.position = Vector2(COL_TRUNK.x, COL_TRUNK.y + 4 * 130.0 + 6.0)
	levelup_btn.pressed.connect(_on_level_up)
	tree_area.add_child(levelup_btn)

func _on_level_up() -> void:
	if GameState.level_up():
		Sfx.play("hack_win", -4.0, 1.4)
	else:
		Sfx.play("ui_click", -4.0, 0.6)
	_refresh()

func _cost_text(cost: Dictionary) -> String:
	var parts: Array = []
	var icons: = {"data_fragments": "◈", "code_samples": "◇", "mutagen": "✦"}
	for key in cost:
		parts.append("%s %d" % [icons.get(key, key), cost[key]])
	return " · ".join(parts) if not parts.is_empty() else "бесплатно"

# ── ветки ───────────────────────────────────────────────────

func _build_branches() -> void:
	tree_area.add_child(_area_label("ВЕТКА РАЗВИТИЯ // только одна", Vector2(COL_BRANCH.x, 0), UIKit.CYAN))
	var y: = COL_BRANCH.y - 30.0
	for cls in GameState.BRANCHES:
		var info: Dictionary = GameState.CLASSES[cls]
		var card: = PanelContainer.new()
		card.custom_minimum_size = Vector2(380, 78)
		card.position = Vector2(COL_BRANCH.x, y)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.gui_input.connect(_on_branch_input.bind(cls))
		tree_area.add_child(card)
		var bv: = VBoxContainer.new()
		bv.add_theme_constant_override("separation", 1)
		card.add_child(bv)
		bv.add_child(UIKit.label("%s — %s" % [info["name"], info["role"]], 16, info["color"]))
		var p: = UIKit.label("◈ %s" % info["passive"], 11, UIKit.DIM)
		p.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		p.custom_minimum_size = Vector2(360, 0)
		bv.add_child(p)
		branch_cards[cls] = card
		y += 84.0

func _on_branch_input(event: InputEvent, cls: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if GameState.branch == "":
			if GameState.choose_branch(cls):
				Sfx.play("hack_win", -6.0, 1.3)
			_refresh()

# ── активки ─────────────────────────────────────────────────

func _build_abilities() -> void:
	tree_area.add_child(_area_label("АКТИВНЫЕ УМЕНИЯ // слоты за уровни, доступ за задания", Vector2(COL_ABILITY.x, 0), UIKit.CYAN))
	ability_hint = UIKit.label("", 14, UIKit.DIM)
	ability_hint.position = Vector2(COL_ABILITY.x, COL_ABILITY.y - 32.0)
	ability_hint.custom_minimum_size = Vector2(620, 0)
	ability_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tree_area.add_child(ability_hint)
	var y: = COL_ABILITY.y + 10.0
	for id in GameState.ABILITIES:
		var info: Dictionary = GameState.ABILITIES[id]
		var row: = HBoxContainer.new()
		row.position = Vector2(COL_ABILITY.x, y)
		row.add_theme_constant_override("separation", 10)
		tree_area.add_child(row)
		var take: = UIKit.button("  ВЗЯТЬ  ", 13, UIKit.TEAL)
		take.pressed.connect(_on_pick.bind(id))
		row.add_child(take)
		var name_l: = UIKit.label("[%s] %s — %s" % ["Q/X/C", info["name"], info["desc"]], 14, UIKit.WHITE)
		name_l.custom_minimum_size = Vector2(430, 0)
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(name_l)
		var state_l: = UIKit.label("", 13, UIKit.DIM)
		state_l.custom_minimum_size = Vector2(150, 0)
		row.add_child(state_l)
		ability_rows[id] = {"row": row, "take": take, "name": name_l, "state": state_l}
		y += 62.0

func _on_pick(id: String) -> void:
	if GameState.pick_ability(id):
		Sfx.play("layer_done", -4.0, 1.2)
	else:
		Sfx.play("ui_click", -4.0, 0.6)
	_refresh()

# ── доп. ветка (УР.3) ───────────────────────────────────────

func _build_secondary() -> void:
	secondary_label = UIKit.label("", 15, UIKit.VIOLET)
	secondary_label.position = Vector2(COL_ABILITY.x, 570)
	tree_area.add_child(secondary_label)
	secondary_row = HBoxContainer.new()
	secondary_row.position = Vector2(COL_ABILITY.x, 600)
	secondary_row.add_theme_constant_override("separation", 8)
	tree_area.add_child(secondary_row)

func _rebuild_secondary_buttons() -> void:
	for c in secondary_row.get_children():
		c.queue_free()
	if GameState.virus_level < 3 or GameState.secondary_branch != "":
		return
	for cls in GameState.BRANCHES:
		if cls == GameState.branch:
			continue
		var info: Dictionary = GameState.CLASSES[cls]
		var b: = UIKit.button("  +%s  " % info["name"], 12, info["color"])
		b.pressed.connect(func() -> void:
			if GameState.choose_secondary(cls):
				Sfx.play("hack_win", -4.0, 1.5)
			_refresh())
		secondary_row.add_child(b)

# ── линии дерева ────────────────────────────────────────────

func _draw_links() -> void:
	var trunk_x: = COL_TRUNK.x + 115.0
	# ствол: связи уровней снизу вверх
	for lvl in 3:
		var y_from: = COL_TRUNK.y + (3 - lvl) * 130.0 + 48.0
		var y_to: = COL_TRUNK.y + (2 - lvl) * 130.0 + 48.0
		var col: = UIKit.TEAL if GameState.virus_level > lvl else Color(0.2, 0.35, 0.42)
		tree_area.draw_line(Vector2(trunk_x, y_from), Vector2(trunk_x, y_to), col, 3.0)
	# УР.1 → ветки
	var lvl1_pos: = Vector2(COL_TRUNK.x + 230.0, COL_TRUNK.y + 2 * 130.0 + 48.0)
	var y: = COL_BRANCH.y - 30.0
	for cls in GameState.BRANCHES:
		var target: = Vector2(COL_BRANCH.x, y + 39.0)
		var col: Color = GameState.CLASSES[cls]["color"] if GameState.branch == cls else Color(0.18, 0.3, 0.38)
		var width: = 3.0 if GameState.branch == cls else 1.0
		tree_area.draw_line(lvl1_pos, target, col, width)
		# выбранная ветка → колонка активок
		if GameState.branch == cls or GameState.secondary_branch == cls:
			tree_area.draw_line(Vector2(target.x + 380.0, target.y), Vector2(COL_ABILITY.x, COL_ABILITY.y + 40.0), col * Color(1, 1, 1, 0.6), 2.0)
		y += 84.0

# ── refresh ─────────────────────────────────────────────────

func _refresh() -> void:
	var r: Dictionary = GameState.resources
	res_label.text = "◈ Data %d   ◇ Code %d   ✦ Mutagen %d   ◆ Ghost %d" % [
		r["data_fragments"], r["code_samples"], r["mutagen"], r["ghost_tokens"]]

	# ствол
	for lvl in 4:
		var box: PanelContainer = level_boxes[lvl]
		var reached: = GameState.virus_level >= lvl
		var col: = UIKit.TEAL if reached else Color(0.25, 0.4, 0.48)
		box.add_theme_stylebox_override("panel", UIKit.panel_box(col, Color(col.r * 0.1, col.g * 0.1, col.b * 0.12, 0.95), 2 if GameState.virus_level == lvl else 1, 8, 8))
	if GameState.virus_level >= 3:
		levelup_btn.text = "  МАКСИМУМ: АПЕКС  "
		levelup_btn.disabled = true
	elif GameState.branch == "":
		levelup_btn.text = "  сначала выбери ветку →  "
		levelup_btn.disabled = true
	else:
		levelup_btn.text = "  ЭВОЛЮЦИЯ до УР.%d (%s)  " % [GameState.virus_level + 1, _cost_text(GameState.level_cost(GameState.virus_level + 1))]
		levelup_btn.disabled = not GameState.can_level_up()

	# ветки
	for cls in branch_cards:
		var info: Dictionary = GameState.CLASSES[cls]
		var card: PanelContainer = branch_cards[cls]
		var c: Color = info["color"]
		if GameState.branch == cls:
			card.add_theme_stylebox_override("panel", UIKit.panel_box(c, Color(c.r * 0.16, c.g * 0.16, c.b * 0.18, 0.95), 2, 8, 8))
		elif GameState.secondary_branch == cls:
			card.add_theme_stylebox_override("panel", UIKit.panel_box(c, Color(c.r * 0.1, c.g * 0.1, c.b * 0.12, 0.9), 2, 8, 8))
		elif GameState.branch == "":
			card.add_theme_stylebox_override("panel", UIKit.panel_box(Color(c.r, c.g, c.b, 0.5), UIKit.PANEL_DARK, 1, 8, 8))
		else:
			card.add_theme_stylebox_override("panel", UIKit.panel_box(Color(0.2, 0.28, 0.33, 0.4), Color(0.01, 0.02, 0.035, 0.85), 1, 8, 8))

	# активки
	var pool: = GameState.ability_pool()
	var keys: = ["Q", "X", "C"]
	for id in ability_rows:
		var row: Dictionary = ability_rows[id]
		var in_pool: bool = id in pool
		row["row"].visible = GameState.branch == "" or in_pool
		var info: Dictionary = GameState.ABILITIES[id]
		var equipped: = GameState.active_abilities.find(id)
		if equipped >= 0:
			row["name"].text = "[%s] %s — %s" % [keys[equipped], info["name"], info["desc"]]
			row["state"].text = "ЭКИПИРОВАНА"
			row["state"].add_theme_color_override("font_color", UIKit.TEAL)
			row["take"].disabled = true
		else:
			var cost: = GameState.ability_cost(id) if GameState.branch != "" else float(info["cost"])
			row["name"].text = "%s — %s · %d BW" % [info["name"], info["desc"], int(cost)]
			row["take"].disabled = not GameState.can_pick_ability(id)
			var slot: = GameState.active_abilities.size()
			if not in_pool and GameState.branch != "":
				row["state"].text = ""
			elif GameState.branch == "":
				row["state"].text = "нужна ветка"
			elif slot >= GameState.max_ability_slots():
				row["state"].text = "нужен УР.%d" % (slot + 1) if slot < 3 else "слоты заняты"
				row["state"].add_theme_color_override("font_color", UIKit.DIM)
			elif not GameState.ability_task_done(slot):
				row["state"].text = "ЗАДАНИЕ: %s" % GameState.ability_task_progress(slot)
				row["state"].add_theme_color_override("font_color", UIKit.AMBER)
			else:
				row["state"].text = "ДОСТУПНА"
				row["state"].add_theme_color_override("font_color", UIKit.CYAN)

	if GameState.branch == "":
		ability_hint.text = "Выбери ветку — откроется её набор умений. УР.1 даёт сигнатурную активку, УР.2 — второй слот, УР.3 — третий."
	else:
		ability_hint.text = "Слоты: %d/%d · на УР.3 расход BW ×%.1f (навыки мощнее — мана дороже)" % [
			GameState.active_abilities.size(), GameState.max_ability_slots(), GameState.APEX_COST_MULT if GameState.virus_level >= 3 else 1.0]

	# доп. ветка
	if GameState.virus_level < 3:
		secondary_label.text = "ДОП. ВЕТКА: откроется на УР.3"
	elif GameState.secondary_branch == "":
		secondary_label.text = "ДОП. ВЕТКА: выбери вторую направленность — её элементы добавятся к скину"
	else:
		secondary_label.text = "ДОП. ВЕТКА: %s — пассивка и умения добавлены" % GameState.CLASSES[GameState.secondary_branch]["name"]
	_rebuild_secondary_buttons()
	tree_area.queue_redraw()

func _area_label(text: String, pos: Vector2, color: Color) -> Label:
	var l: = UIKit.label(text, 18, color)
	l.position = pos
	return l

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
