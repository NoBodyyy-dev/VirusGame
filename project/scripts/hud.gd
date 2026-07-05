extends Control

## HUD PANIC PROTOCOL: добыча, тревога с фазами, HP, эвакуация, гонка штаммов.

var access_m: Dictionary
var alarm_m: Dictionary
var bw_m: Dictionary
var phase_label: Label
var hp_label: Label
var objective_label: Label
var prompt_label: Label
var toast_label: Label
var evac_label: Label
var ability_label: Label
var vignette: ColorRect
var score_box: VBoxContainer
var _vignette_mat: ShaderMaterial
var _damage_flash: = 0.0
var _ability_cd: = 0.0
var _t: = 0.0
var _last_hp: = 99

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	vignette = ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_mat = ShaderMaterial.new()
	_vignette_mat.shader = load("res://shaders/vignette.gdshader")
	vignette.material = _vignette_mat
	add_child(vignette)

	var top_left: = VBoxContainer.new()
	top_left.position = Vector2(24, 20)
	top_left.add_theme_constant_override("separation", 8)
	add_child(top_left)

	access_m = UIKit.meter(380, 28, UIKit.TEAL, "ДОБЫЧА 0%")
	top_left.add_child(access_m["root"])
	alarm_m = UIKit.meter(380, 28, UIKit.CYAN, "ТРЕВОГА 0%")
	top_left.add_child(alarm_m["root"])

	var row: = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	top_left.add_child(row)
	phase_label = UIKit.label("СИСТЕМА: SLEEP", 17, UIKit.DIM)
	row.add_child(phase_label)
	hp_label = UIKit.label("HP ◆◆◆", 17, UIKit.MAGENTA)
	row.add_child(hp_label)

	var bottom_left: = VBoxContainer.new()
	bottom_left.position = Vector2(24, 775)
	bottom_left.add_theme_constant_override("separation", 6)
	add_child(bottom_left)
	bw_m = UIKit.meter(300, 22, Color(0.35, 0.6, 1.0), "BANDWIDTH")
	bottom_left.add_child(bw_m["root"])
	var info: Dictionary = GameState.class_info()
	ability_label = UIKit.label("[Q] %s · %d BW" % [info["active"], info["cost"]], 15, UIKit.DIM)
	bottom_left.add_child(ability_label)
	var help_text: = "[E] схватить/бросить · [F] швырнуть · ПРОБЕЛ — прыжок (не с грузом!)"
	if Net.active:
		help_text += "\n[1-4] — эмоции · [G] — подлянка другу (%d BW)" % int(Net.PRANK_COST)
	var help: = UIKit.label(help_text, 13, UIKit.DIM)
	bottom_left.add_child(help)

	objective_label = UIKit.label("", 18, UIKit.AMBER)
	objective_label.position = Vector2(980, 22)
	objective_label.size = Vector2(596, 60)
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(objective_label)

	if Net.active:
		score_box = VBoxContainer.new()
		score_box.position = Vector2(1330, 110)
		score_box.add_theme_constant_override("separation", 3)
		add_child(score_box)

	prompt_label = UIKit.label("", 22, UIKit.WHITE)
	prompt_label.position = Vector2(400, 720)
	prompt_label.size = Vector2(800, 40)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(prompt_label)

	toast_label = UIKit.label("", 26, UIKit.MAGENTA)
	toast_label.position = Vector2(400, 90)
	toast_label.size = Vector2(800, 44)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.modulate.a = 0.0
	add_child(toast_label)

	evac_label = UIKit.label("", 34, Color(1.0, 0.2, 0.3))
	evac_label.position = Vector2(400, 140)
	evac_label.size = Vector2(800, 54)
	evac_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	evac_label.visible = false
	add_child(evac_label)

	GameState.hp_changed.connect(_on_hp)

func _on_hp(v: int) -> void:
	if v < _last_hp:
		_damage_flash = 1.0
	_last_hp = v

func set_objective(text: String) -> void:
	objective_label.text = text

func show_prompt(text: String) -> void:
	prompt_label.text = text

func hide_prompt() -> void:
	prompt_label.text = ""

func toast(text: String, color: = UIKit.MAGENTA) -> void:
	toast_label.text = text
	toast_label.add_theme_color_override("font_color", color)
	toast_label.modulate.a = 0.0
	var tw: = create_tween()
	tw.tween_property(toast_label, "modulate:a", 1.0, 0.15)
	tw.tween_interval(2.2)
	tw.tween_property(toast_label, "modulate:a", 0.0, 0.6)

func set_ability_cooldown(sec: float) -> void:
	_ability_cd = sec

func set_scores(rows: Array) -> void:
	## гонка штаммов: [{name, color, score}] по убыванию
	if score_box == null:
		return
	for c in score_box.get_children():
		c.queue_free()
	if rows.is_empty():
		return
	score_box.add_child(UIKit.label("ГОНКА ШТАММОВ", 14, UIKit.DIM))
	for i in rows.size():
		var r: Dictionary = rows[i]
		var mark: = "★ " if i == 0 else "%d. " % (i + 1)
		var line: = UIKit.label("%s%s  %d" % [mark, r["name"], r["score"]], 15, r["color"])
		score_box.add_child(line)

func _process(delta: float) -> void:
	_t += delta
	_damage_flash = maxf(_damage_flash - delta * 1.5, 0.0)

	UIKit.set_meter(access_m, clampf(GameState.access / 100.0, 0.0, 1.0))
	if GameState.access >= 100.0:
		access_m["label"].text = "ДОБЫЧА %d%% ★ КВОТА ВЗЯТА" % roundi(GameState.access)
	else:
		access_m["label"].text = "ДОБЫЧА %d%%" % roundi(GameState.access)

	var al: = GameState.alarm / 100.0
	var acol: Color
	if al < 0.25:
		acol = UIKit.CYAN
	elif al < 0.55:
		acol = UIKit.AMBER
	elif al < 0.9:
		acol = Color(1.0, 0.45, 0.3)
	else:
		acol = Color(1.0, 0.15, 0.25).lerp(Color(1.0, 0.5, 0.5), 0.5 + 0.5 * sin(_t * 8.0))
	UIKit.set_meter(alarm_m, al, acol)
	alarm_m["label"].text = "ТРЕВОГА %d%%" % roundi(GameState.alarm)

	UIKit.set_meter(bw_m, GameState.bandwidth / GameState.max_bandwidth)
	bw_m["label"].text = "BANDWIDTH %d" % roundi(GameState.bandwidth)

	_ability_cd = maxf(_ability_cd - delta, 0.0)
	var info: Dictionary = GameState.class_info()
	if _ability_cd > 0.0:
		ability_label.text = "[Q] перезарядка %.1fс" % _ability_cd
		ability_label.add_theme_color_override("font_color", UIKit.DIM)
	else:
		ability_label.text = "[Q] %s · %d BW" % [info["active"], info["cost"]]
		ability_label.add_theme_color_override("font_color", UIKit.CYAN)

	match GameState.alarm_phase():
		0: _set_phase("СИСТЕМА СПИТ · zZz", UIKit.DIM)
		1: _set_phase("▲ SCAN — попапы вышли на охоту", UIKit.AMBER)
		2: _set_phase("▲▲ PURGE — HUNTER слышит вас", Color(1.0, 0.45, 0.3))
		3: _set_phase("▲▲▲ WIPE — СТИРАНИЕ УЗЛА", Color(1.0, 0.15, 0.25))

	if GameState.my_bug:
		hp_label.text = "ТЫ — БАГ · ползи к порталу"
		hp_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.4))
	else:
		hp_label.text = "HP " + "◆".repeat(GameState.my_hp) + "◇".repeat(maxi(GameState.my_max_hp - GameState.my_hp, 0))
		hp_label.add_theme_color_override("font_color", UIKit.MAGENTA)

	if GameState.evac_open:
		evac_label.visible = true
		var word: = "СТИРАНИЕ" if GameState.wipe_forced else "ЭВАКУАЦИЯ"
		evac_label.text = "%s: %.1fс — ВСЕ В КРУГ!" % [word, maxf(GameState.evac_left, 0.0)]
		evac_label.modulate.a = 0.7 + 0.3 * sin(_t * 6.0)
	else:
		evac_label.visible = false

	var base_v: = clampf((GameState.alarm - 50.0) / 110.0, 0.0, 0.5)
	if GameState.my_bug:
		base_v = 0.45 + 0.1 * sin(_t * 4.0)
	_vignette_mat.set_shader_parameter("intensity", clampf(base_v + _damage_flash, 0.0, 0.95))

func _set_phase(text: String, color: Color) -> void:
	phase_label.text = text
	phase_label.add_theme_color_override("font_color", color)
