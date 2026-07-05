extends Control

## Главное меню: без выбора ролей — все начинают одинаковым ПРОТО-ШТАММОМ.
## Специализация выбирается в игре, в дереве эволюции [Tab].

const FUN_NICKS: = [
	"КИБЕР-КОТЛЕТА", "ПИНГВИН_2007", "АДМИН БОЛИ", "ТЁТЯ ЗИНА",
	"СЫН МАМИНОЙ ПОДРУГИ", "ФИКУС", "BARSIK.EXE", "ШАШЛЫЧОК",
	"ГРОЗА РОУТЕРОВ", "ДИРЕКТОР ИНТЕРНЕТА", "КРЕВЕТКА-МСТИТЕЛЬ",
]

var start_btn: Button
var host_btn: Button
var join_btn: Button
var ip_edit: LineEdit
var nick_edit: LineEdit
var lobby_panel: Control
var lobby_list: VBoxContainer
var lobby_status_label: Label
var lobby_start_btn: Button
var _glyph_timer: = 0.0
var _glyphs: Array = []
var _preview_holder: Node3D

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.ambient(true, 0.9)
	_check_autostart()
	_build()

func _apply_debug_class(cls: String) -> void:
	## автотесты: старая нотация autostart=<класс> — сразу ветка + УР.1
	## (debug_class переживает new_campaign при старте кооп-кампании)
	GameState.debug_class = cls
	GameState.branch = cls
	GameState.virus_level = 1
	var sig: String = GameState.BRANCH_ABILITIES[cls][0]
	if not sig in GameState.active_abilities:
		GameState.active_abilities.append(sig)

func _check_autostart() -> void:
	var args: = OS.get_cmdline_user_args()
	# кооп-боты для автотестов: autohost / autojoin (+ autostart=<класс> demo)
	if "autohost" in args or "autojoin" in args:
		var net_cls: = ""
		for arg in args:
			if arg.begins_with("autostart="):
				var c: String = arg.get_slice("=", 1)
				if c in GameState.BRANCHES:
					net_cls = c
		GameState.demo_mode = "demo" in args
		if "autohost" in args:
			Net.host_game("БОТ-ХОСТ")
			Net.players_changed.connect(_auto_start_campaign)
		else:
			Net.join_game("127.0.0.1", "БОТ-ГОСТЬ")
		if net_cls != "":
			_apply_debug_class(net_cls)
			Net.sync_identity()
		return

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("autostart="):
			var cls: String = arg.get_slice("=", 1)
			GameState.demo_mode = "demo" in OS.get_cmdline_user_args()
			GameState.new_campaign()
			if cls in GameState.BRANCHES:
				_apply_debug_class(cls)
			if "world" in OS.get_cmdline_user_args():
				get_tree().change_scene_to_file.call_deferred("res://scenes/grid_world.tscn")
			else:
				var target: Dictionary = GameState.grid_nodes[0]
				for a2 in OS.get_cmdline_user_args():
					if a2.begins_with("tier="):
						var tn: = int(a2.get_slice("=", 1))
						for node in GameState.grid_nodes:
							if node["tier"] == tn and not node["boss"]:
								target = node
								break
				if "boss" in OS.get_cmdline_user_args():
					for node in GameState.grid_nodes:
						if node["boss"]:
							target = node
							break
				GameState.start_hack(target)
				get_tree().change_scene_to_file.call_deferred("res://scenes/level.tscn")

func _auto_start_campaign() -> void:
	# автотест коопа: стартуем, как только подключился второй штамм
	if Net.active and Net.is_server() and Net.players.size() >= 2:
		Net.start_campaign()

func _build() -> void:
	var bg: = ColorRect.new()
	bg.color = UIKit.BG
	add_child(UIKit.full_rect(bg))

	var glyph_set: = "0123456789ABCDEF<>/\\|#$%&*+=?"
	for i in 26:
		_glyphs.append({
			"pos": Vector2(randf() * 1600.0, randf() * 900.0),
			"speed": randf_range(12.0, 45.0), "char": glyph_set[randi() % glyph_set.length()],
			"alpha": randf_range(0.04, 0.14),
		})

	var root: = VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	var pad: = MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 90)
	pad.add_theme_constant_override("margin_right", 90)
	pad.add_theme_constant_override("margin_top", 46)
	pad.add_theme_constant_override("margin_bottom", 40)
	add_child(pad)
	pad.add_child(root)

	var title_row: = HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 18)
	var prompt: = UIKit.label(">_", 64, UIKit.TEAL)
	var title: = UIKit.label("VIRUS", 64, UIKit.WHITE)
	title_row.add_child(prompt)
	title_row.add_child(title)
	root.add_child(title_row)
	var tw: = create_tween().set_loops()
	tw.tween_property(prompt, "modulate:a", 0.25, 0.6)
	tw.tween_property(prompt, "modulate:a", 1.0, 0.6)

	root.add_child(UIKit.label("PANIC PROTOCOL · кооп-ограбление сети: тащи лут, не буди систему, эвакуируйся", 20, UIKit.CYAN))
	root.add_child(UIKit.label("Все начинают одинаковым ПРОТО-ШТАММОМ. Ветку развития выбираешь в игре — дерево эволюции [Tab]", 16, UIKit.DIM))

	# карточка прото-штамма + путь развития
	var info_panel: = PanelContainer.new()
	info_panel.custom_minimum_size = Vector2(720, 0)
	info_panel.add_theme_stylebox_override("panel", UIKit.panel_box(UIKit.CYAN, UIKit.PANEL_DARK, 1, 8, 18))
	root.add_child(info_panel)
	var iv: = VBoxContainer.new()
	iv.add_theme_constant_override("separation", 6)
	info_panel.add_child(iv)
	iv.add_child(UIKit.label("ПРОТО-ШТАММ → УР.1 ветка и скин → УР.2 активки за задания → УР.3 апекс + доп. ветка", 16, UIKit.TEAL))
	iv.add_child(UIKit.label("Ветки: ТРОЯН · ЧЕРВЬ · RANSOMWARE · SPYWARE · ADWARE · ROOTKIT · BOTNET", 14, UIKit.DIM))
	iv.add_child(UIKit.label("Уровни Грида идут цепочкой: захватил узел — открылся следующий, территория растёт", 14, UIKit.DIM))
	iv.add_child(UIKit.label("Полевые задачи в узлах рассчитаны на команду: синхро-консоли, захват сектора, цепь реле", 14, UIKit.DIM))

	var spacer2: = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 6)
	spacer2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer2)

	var target: = UIKit.label("КАМПАНИЯ: заражение Грида — от домашнего ПК по цепочке к дата-центру и боссу ОРАКУЛ", 16, UIKit.AMBER)
	root.add_child(target)

	var bottom: = HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 14)
	root.add_child(bottom)
	start_btn = UIKit.button("  ОДИНОЧНАЯ ▸  ", 22, UIKit.TEAL)
	start_btn.pressed.connect(_on_start)
	bottom.add_child(start_btn)
	host_btn = UIKit.button("  СОЗДАТЬ ЛОББИ  ", 18, UIKit.CYAN)
	host_btn.pressed.connect(_on_host)
	bottom.add_child(host_btn)
	nick_edit = LineEdit.new()
	nick_edit.text = FUN_NICKS.pick_random()
	nick_edit.placeholder_text = "ник"
	nick_edit.max_length = 16
	nick_edit.custom_minimum_size = Vector2(190, 0)
	nick_edit.add_theme_font_size_override("font_size", 15)
	bottom.add_child(nick_edit)
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "IP хоста (пусто = 127.0.0.1)"
	ip_edit.custom_minimum_size = Vector2(240, 0)
	ip_edit.add_theme_font_size_override("font_size", 15)
	bottom.add_child(ip_edit)
	join_btn = UIKit.button("  ПОДКЛЮЧИТЬСЯ  ", 18, UIKit.VIOLET)
	join_btn.pressed.connect(_on_join)
	bottom.add_child(join_btn)

	_build_preview()
	_build_lobby()

func _build_lobby() -> void:
	lobby_panel = Control.new()
	lobby_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lobby_panel.visible = false
	add_child(lobby_panel)
	var dim: = ColorRect.new()
	dim.color = Color(0, 0.005, 0.015, 0.85)
	lobby_panel.add_child(UIKit.full_rect(dim))
	var center: = CenterContainer.new()
	lobby_panel.add_child(UIKit.full_rect(center))
	var panel: = PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 460)
	panel.add_theme_stylebox_override("panel", UIKit.panel_box(UIKit.CYAN, Color(0.008, 0.02, 0.036, 0.97), 1, 8, 26))
	center.add_child(panel)
	var v: = VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	v.add_child(UIKit.label("ЛОББИ КОМАНДЫ // рой прото-штаммов", 26, UIKit.TEAL))
	lobby_status_label = UIKit.label("", 15, UIKit.DIM)
	v.add_child(lobby_status_label)
	lobby_list = VBoxContainer.new()
	lobby_list.add_theme_constant_override("separation", 6)
	lobby_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(lobby_list)
	v.add_child(UIKit.label("специализация выбирается ВНУТРИ рейда: дерево эволюции [Tab], одна ветка на штамм", 13, UIKit.DIM))
	v.add_child(UIKit.label("в рейде: [1-4] эмоции · [G] подлянка другу · гонка за MVP узла", 13, UIKit.AMBER))
	var row: = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	lobby_start_btn = UIKit.button("  СТАРТ РЕЙДА ▸  ", 20, UIKit.TEAL)
	lobby_start_btn.pressed.connect(func() -> void: Net.start_campaign())
	row.add_child(lobby_start_btn)
	var leave: = UIKit.button("  ПОКИНУТЬ  ", 18, UIKit.MAGENTA)
	leave.pressed.connect(func() -> void:
		Net.leave()
		lobby_panel.visible = false)
	row.add_child(leave)
	Net.players_changed.connect(_refresh_lobby)
	Net.lobby_status.connect(func(t: String) -> void: lobby_status_label.text = t)

func _refresh_lobby() -> void:
	for c in lobby_list.get_children():
		c.queue_free()
	for id in Net.players:
		var p: Dictionary = Net.players[id]
		var info: Dictionary = GameState.CLASSES[p.get("cls", "base")]
		var line: = UIKit.label("▸ %s — %s · ур.%d" % [p["name"], info["name"], p.get("lvl", 0)], 17, info["color"])
		lobby_list.add_child(line)
	lobby_start_btn.visible = Net.active and Net.is_server()
	lobby_start_btn.disabled = Net.players.size() < 2

func _on_host() -> void:
	if Net.host_game(nick_edit.text.strip_edges()):
		lobby_panel.visible = true
		_refresh_lobby()

func _on_join() -> void:
	if Net.join_game(ip_edit.text.strip_edges(), nick_edit.text.strip_edges()):
		lobby_panel.visible = true
		lobby_status_label.text = "подключение к %s…" % (ip_edit.text if ip_edit.text != "" else "127.0.0.1")
		_refresh_lobby()

func _build_preview() -> void:
	# 3D-превью прото-штамма справа
	var svc: = SubViewportContainer.new()
	svc.stretch = true
	svc.position = Vector2(1122, 380)
	svc.size = Vector2(360, 320)
	add_child(svc)
	var sv: = SubViewport.new()
	sv.transparent_bg = true
	sv.own_world_3d = true
	svc.add_child(sv)

	var cam: = Camera3D.new()
	cam.position = Vector3(0, 1.25, 2.7)
	cam.fov = 50.0
	sv.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0, 1.0, 0), Vector3.UP)

	var sun: = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 0.8
	sv.add_child(sun)
	var fill: = OmniLight3D.new()
	fill.position = Vector3(0, 2.0, 2.0)
	fill.light_color = Color(0.4, 0.7, 0.9)
	fill.light_energy = 1.2
	sv.add_child(fill)

	_preview_holder = Node3D.new()
	sv.add_child(_preview_holder)
	_preview_holder.add_child(VirusModel.create("base", GameState.CLASSES["base"]["color"]))

	var hint: = UIKit.label("ПРОТО-ШТАММ\nтаким начинают все", 15, UIKit.DIM)
	hint.position = Vector2(1190, 706)
	add_child(hint)

func _on_start() -> void:
	Net.leave()
	GameState.new_campaign()
	get_tree().change_scene_to_file("res://scenes/grid_world.tscn")

func _process(delta: float) -> void:
	if _preview_holder != null:
		_preview_holder.rotation.y += delta * 0.7
	_glyph_timer += delta
	for g in _glyphs:
		g["pos"].y += g["speed"] * delta
		if g["pos"].y > 920.0:
			g["pos"].y = -20.0
			g["pos"].x = randf() * 1600.0
	queue_redraw()

func _draw() -> void:
	var font: = get_theme_default_font()
	for g in _glyphs:
		draw_string(font, g["pos"], g["char"], HORIZONTAL_ALIGNMENT_LEFT, -1, 22,
			Color(UIKit.CYAN.r, UIKit.CYAN.g, UIKit.CYAN.b, g["alpha"]))
	for x in range(0, 1601, 80):
		draw_line(Vector2(x, 0), Vector2(x, 900), Color(0.1, 0.4, 0.55, 0.05))
	for y in range(0, 901, 80):
		draw_line(Vector2(0, y), Vector2(1600, y), Color(0.1, 0.4, 0.55, 0.05))
