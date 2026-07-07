class_name PuzzleUI
extends Control

## Головоломка «СХЕМА ВЗЛОМА»: на сетке 4×4 вспыхивает маршрут сигнала —
## повтори его в том же порядке. Ошибка — новый маршрут, попытки бесконечны.
## Открывает двери комнат, туннели и пилоны Оракула.

signal finished(success: bool)

const GRID_N: = 4
const SHOW_STEP: = 0.5     # сек подсветки одной ячейки при показе
const CELL_PX: = 72

var difficulty: = 1         # 1..5 → длина маршрута 4..8
var title_text: = "СХЕМА ВЗЛОМА"

var _cells: Array = []      # Button
var _seq: Array = []        # индексы ячеек маршрута
var _input_at: = 0          # сколько уже повторено
var _phase: = "show"        # show / input / done
var _show_t: = 0.0
var _show_i: = -1
var _status: Label
var _tries: = 0

static func open(parent: Node, p_difficulty: int, p_title: String) -> PuzzleUI:
	var p: = PuzzleUI.new()
	p.difficulty = clampi(p_difficulty, 1, 5)
	p.title_text = p_title
	parent.add_child(p)
	return p

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim: = ColorRect.new()
	dim.color = Color(0, 0.006, 0.014, 0.82)
	add_child(UIKit.full_rect(dim))
	var center: = CenterContainer.new()
	add_child(UIKit.full_rect(center))
	var panel: = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.panel_box(UIKit.CYAN, Color(0.008, 0.022, 0.04, 0.97), 1, 10, 22))
	center.add_child(panel)
	var v: = VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	v.add_child(UIKit.label(title_text, 24, UIKit.CYAN))
	_status = UIKit.label("СЛЕДИ ЗА СИГНАЛОМ…", 17, UIKit.AMBER)
	v.add_child(_status)
	var grid: = GridContainer.new()
	grid.columns = GRID_N
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	for i in GRID_N * GRID_N:
		var b: = Button.new()
		b.custom_minimum_size = Vector2(CELL_PX, CELL_PX)
		b.text = "%X" % (randi() % 16)
		b.add_theme_font_size_override("font_size", 20)
		b.add_theme_color_override("font_color", Color(0.3, 0.5, 0.6))
		b.add_theme_stylebox_override("normal", UIKit.panel_box(Color(0.14, 0.3, 0.4), Color(0.015, 0.04, 0.07, 0.95), 1, 6, 0))
		b.add_theme_stylebox_override("hover", UIKit.panel_box(UIKit.CYAN, Color(0.03, 0.08, 0.12, 0.95), 1, 6, 0))
		b.add_theme_stylebox_override("pressed", UIKit.panel_box(UIKit.TEAL, Color(0.05, 0.14, 0.16, 1.0), 2, 6, 0))
		b.pressed.connect(_on_cell.bind(i))
		grid.add_child(b)
		_cells.append(b)
	var cancel: = UIKit.button("  ОТОЙТИ ОТ ТЕРМИНАЛА  ", 16, UIKit.MAGENTA)
	cancel.pressed.connect(func() -> void: _close(false))
	v.add_child(cancel)
	_new_sequence()

func _new_sequence() -> void:
	_seq.clear()
	var len_needed: = 3 + difficulty
	var cur: = randi() % (GRID_N * GRID_N)
	_seq.append(cur)
	while _seq.size() < len_needed:
		# маршрут ходит по соседним ячейкам — читается как «сигнал по плате»
		var cx: = cur % GRID_N
		var cy: = cur / GRID_N
		var options: Array = []
		for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx: int = cx + d[0]
			var ny: int = cy + d[1]
			var ni: = ny * GRID_N + nx
			if nx >= 0 and nx < GRID_N and ny >= 0 and ny < GRID_N and not ni in _seq:
				options.append(ni)
		if options.is_empty():
			# тупик: начать маршрут заново
			_seq.clear()
			cur = randi() % (GRID_N * GRID_N)
			_seq.append(cur)
			continue
		cur = options.pick_random()
		_seq.append(cur)
	_phase = "show"
	_show_t = 0.6
	_show_i = -1
	_input_at = 0
	_status.text = "СЛЕДИ ЗА СИГНАЛОМ… (%d шагов)" % _seq.size()
	_status.add_theme_color_override("font_color", UIKit.AMBER)

func _process(delta: float) -> void:
	if _phase != "show":
		return
	_show_t -= delta
	if _show_t > 0.0:
		return
	# погасить предыдущую
	if _show_i >= 0:
		_flash(_seq[_show_i], false)
	_show_i += 1
	if _show_i >= _seq.size():
		_phase = "input"
		_status.text = "ПОВТОРИ МАРШРУТ: 0/%d" % _seq.size()
		_status.add_theme_color_override("font_color", UIKit.CYAN)
		return
	_flash(_seq[_show_i], true)
	Sfx.play("ui_click", -10.0, 1.0 + 0.12 * float(_show_i))
	_show_t = SHOW_STEP

func _flash(idx: int, on: bool) -> void:
	var b: Button = _cells[idx]
	if on:
		b.add_theme_stylebox_override("normal", UIKit.panel_box(UIKit.TEAL, Color(0.06, 0.35, 0.3, 1.0), 2, 6, 0))
		b.add_theme_color_override("font_color", Color.WHITE)
	else:
		b.add_theme_stylebox_override("normal", UIKit.panel_box(Color(0.14, 0.3, 0.4), Color(0.015, 0.04, 0.07, 0.95), 1, 6, 0))
		b.add_theme_color_override("font_color", Color(0.3, 0.5, 0.6))

func _on_cell(idx: int) -> void:
	if _phase != "input":
		return
	if idx == _seq[_input_at]:
		_input_at += 1
		_flash(idx, true)
		Sfx.play("ui_click", -8.0, 1.3)
		get_tree().create_timer(0.18).timeout.connect(func() -> void:
			if is_instance_valid(self) and _phase == "input":
				_flash(idx, false))
		_status.text = "ПОВТОРИ МАРШРУТ: %d/%d" % [_input_at, _seq.size()]
		if _input_at >= _seq.size():
			_phase = "done"
			_status.text = "// ДОСТУП РАЗРЕШЁН //"
			_status.add_theme_color_override("font_color", UIKit.TEAL)
			Sfx.play("hack_win", -6.0, 1.4)
			get_tree().create_timer(0.55).timeout.connect(func() -> void:
				if is_instance_valid(self):
					_close(true))
	else:
		_tries += 1
		Sfx.play("hack_fail", -8.0, 1.3)
		_status.text = "СБОЙ ТРАССИРОВКИ — новый маршрут (попытка %d)" % (_tries + 1)
		_status.add_theme_color_override("font_color", UIKit.MAGENTA)
		for c in _seq:
			_flash(c, false)
		_phase = "show"
		_show_t = 1.0
		_show_i = -1
		get_tree().create_timer(0.6).timeout.connect(func() -> void:
			if is_instance_valid(self) and _phase == "show":
				_new_sequence())

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_close(false)
		get_viewport().set_input_as_handled()

func _close(success: bool) -> void:
	finished.emit(success)
	queue_free()
