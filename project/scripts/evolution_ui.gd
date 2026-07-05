extends Control

## Экран «Эволюция»: ствол прокачки за Data Fragments, крафт 0-day
## из Code Samples, престиж-мутации за Mutagen.

signal closed

var res_label: Label
var rows: = {}
var mut_rows: = {}
var craft_btn: Button
var craft_label: Label
var stage_label: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim: = ColorRect.new()
	dim.color = Color(0, 0.005, 0.015, 0.82)
	add_child(UIKit.full_rect(dim))

	var center: = CenterContainer.new()
	add_child(UIKit.full_rect(center))
	var panel: = PanelContainer.new()
	panel.custom_minimum_size = Vector2(940, 700)
	panel.add_theme_stylebox_override("panel", UIKit.panel_box(UIKit.TEAL, Color(0.008, 0.02, 0.036, 0.97), 1, 8, 26))
	center.add_child(panel)

	var v: = VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	v.add_child(UIKit.label("ЭВОЛЮЦИЯ ШТАММА // %s" % GameState.class_info()["name"], 28, UIKit.TEAL))
	res_label = UIKit.label("", 17, UIKit.WHITE)
	v.add_child(res_label)
	stage_label = UIKit.label("", 15, UIKit.VIOLET)
	v.add_child(stage_label)

	v.add_child(_sep())
	v.add_child(UIKit.label("СТВОЛ ПРОКАЧКИ — Data Fragments", 19, UIKit.CYAN))
	for id in GameState.EVOLUTION:
		v.add_child(_upgrade_row(id))

	v.add_child(_sep())
	v.add_child(UIKit.label("КРАФТ — Code Samples", 19, UIKit.CYAN))
	var crow: = HBoxContainer.new()
	crow.add_theme_constant_override("separation", 14)
	v.add_child(crow)
	craft_btn = UIKit.button("  СОБРАТЬ 0-DAY (2 Code Samples)  ", 16, UIKit.AMBER)
	craft_btn.pressed.connect(_on_craft)
	crow.add_child(craft_btn)
	craft_label = UIKit.label("", 15, UIKit.DIM)
	crow.add_child(craft_label)

	v.add_child(_sep())
	v.add_child(UIKit.label("ПРЕСТИЖ-МУТАЦИИ — Mutagen", 19, UIKit.CYAN))
	for id in GameState.MUTATIONS:
		v.add_child(_mutation_row(id))

	var spacer: = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var close: = UIKit.button("  ЗАКРЫТЬ [Tab]  ", 18, UIKit.TEAL)
	close.pressed.connect(func() -> void: closed.emit())
	v.add_child(close)
	_refresh()

func _sep() -> Control:
	var s: = ColorRect.new()
	s.color = Color(0.16, 0.4, 0.5, 0.35)
	s.custom_minimum_size = Vector2(0, 1)
	return s

func _upgrade_row(id: String) -> Control:
	var info: Dictionary = GameState.EVOLUTION[id]
	var row: = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var buy: = UIKit.button("  +  ", 16, UIKit.TEAL)
	buy.pressed.connect(_on_buy.bind(id))
	row.add_child(buy)
	var name_l: = UIKit.label("%s — %s" % [info["name"], info["desc"]], 16, UIKit.WHITE)
	name_l.custom_minimum_size = Vector2(560, 0)
	row.add_child(name_l)
	var lvl_l: = UIKit.label("", 16, UIKit.TEAL)
	lvl_l.custom_minimum_size = Vector2(120, 0)
	row.add_child(lvl_l)
	var cost_l: = UIKit.label("", 16, UIKit.AMBER)
	row.add_child(cost_l)
	rows[id] = {"buy": buy, "lvl": lvl_l, "cost": cost_l}
	return row

func _mutation_row(id: String) -> Control:
	var info: Dictionary = GameState.MUTATIONS[id]
	var row: = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var buy: = UIKit.button("  ✦  ", 16, UIKit.VIOLET)
	buy.pressed.connect(_on_mutate.bind(id))
	row.add_child(buy)
	var name_l: = UIKit.label("%s — %s" % [info["name"], info["desc"]], 16, UIKit.WHITE)
	name_l.custom_minimum_size = Vector2(560, 0)
	row.add_child(name_l)
	var state_l: = UIKit.label("", 16, UIKit.VIOLET)
	row.add_child(state_l)
	mut_rows[id] = {"buy": buy, "state": state_l}
	return row

func _on_buy(id: String) -> void:
	if GameState.evo_buy(id):
		Sfx.play("layer_done", -4.0, 1.2)
	else:
		Sfx.play("ui_click", -4.0, 0.6)
	_refresh()

func _on_mutate(id: String) -> void:
	if GameState.mutation_buy(id):
		Sfx.play("hack_win", -6.0, 1.4)
	else:
		Sfx.play("ui_click", -4.0, 0.6)
	_refresh()

func _on_craft() -> void:
	if GameState.craft_zero_day():
		Sfx.play("chain", -2.0)
	else:
		Sfx.play("ui_click", -4.0, 0.6)
	_refresh()

func _refresh() -> void:
	var r: Dictionary = GameState.resources
	res_label.text = "◈ Data %d   ◇ Code %d   ✦ Mutagen %d   ◆ Ghost %d   ⚡ 0-day × %d" % [
		r["data_fragments"], r["code_samples"], r["mutagen"], r["ghost_tokens"], GameState.zero_days]
	stage_label.text = "стадия полиморфизма: %d/2 — тело штамма мутирует с прокачкой" % GameState.evolve_stage()
	for id in rows:
		var lvl: = GameState.evo_level(id)
		var mx: int = GameState.EVOLUTION[id]["max"]
		rows[id]["lvl"].text = "▰".repeat(lvl) + "▱".repeat(mx - lvl)
		if lvl >= mx:
			rows[id]["cost"].text = "MAX"
			rows[id]["buy"].disabled = true
		else:
			rows[id]["cost"].text = "◈ %d" % GameState.evo_cost(id)
			rows[id]["buy"].disabled = not GameState.evo_can_buy(id)
	for id in mut_rows:
		if GameState.mutation_owned(id):
			mut_rows[id]["state"].text = "ПРИОБРЕТЕНА"
			mut_rows[id]["buy"].disabled = true
		else:
			mut_rows[id]["state"].text = "✦ %d Mutagen" % GameState.MUTATIONS[id]["cost"]
			mut_rows[id]["buy"].disabled = not GameState.mutation_can_buy(id)
	craft_btn.disabled = not GameState.can_craft_zero_day()
	craft_label.text = "0-day в запасе: %d — [F] у замка сейфа выбивает его мгновенно" % GameState.zero_days

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
