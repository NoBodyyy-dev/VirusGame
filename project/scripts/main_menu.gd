extends Control


const FUN_NICKS: = [
 "КИБЕР-КОТЛЕТА", "ПИНГВИН_2007", "АДМИН БОЛИ", "ТЁТЯ ЗИНА",
 "СЫН МАМИНОЙ ПОДРУГИ", "ФИКУС", "BARSIK.EXE", "ШАШЛЫЧОК",
 "ГРОЗА РОУТЕРОВ", "ДИРЕКТОР ИНТЕРНЕТА", "КРЕВЕТКА-МСТИТЕЛЬ",
]

var selected: = ""
var cards: = {}
var start_btn: Button
var host_btn: Button
var join_btn: Button
var ip_edit: LineEdit
var nick_edit: LineEdit
var lobby_panel: Control
var lobby_list: VBoxContainer
var lobby_status_label: Label
var lobby_start_btn: Button
var hint_label: Label
var _glyph_timer: = 0.0
var _glyphs: Array = []
var _preview_holder: Node3D
var _preview_model: VirusModel
var _preview_hint: Label

func _ready() -> void :
 Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
 Sfx.ambient(true, 0.9)
 _check_autostart()
 _build()

func _check_autostart() -> void :

 var args: = OS.get_cmdline_user_args()
 # кооп-боты для автотестов: autohost / autojoin (+ autostart=<класс> demo)
 if "autohost" in args or "autojoin" in args:
  var net_cls: = "worm"
  for arg in args:
   if arg.begins_with("autostart="):
    var c: String = arg.get_slice("=", 1)
    if GameState.CLASSES.has(c):
     net_cls = c
  GameState.demo_mode = "demo" in args
  GameState.selected_class = net_cls
  if "autohost" in args:
   Net.host_game(net_cls, "БОТ-ХОСТ")
   Net.players_changed.connect(_auto_start_campaign)
  else:
   Net.join_game("127.0.0.1", net_cls, "БОТ-ГОСТЬ")
  return

 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("autostart="):
   var cls: String = arg.get_slice("=", 1)
   if GameState.CLASSES.has(cls):
    GameState.demo_mode = "demo" in OS.get_cmdline_user_args()
    GameState.new_campaign(cls)
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

func _auto_start_campaign() -> void :
 # автотест коопа: стартуем, как только подключился второй штамм
 if Net.active and Net.is_server() and Net.players.size() >= 2:
  Net.start_campaign()

func _build() -> void :
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
 root.add_theme_constant_override("separation", 10)
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
 root.add_child(UIKit.label("ВЫБЕРИТЕ ШТАММ — класс определяет пассивку и активку [Q]. Лут физический — его роняют и разбивают", 16, UIKit.DIM))

 var spacer: = Control.new()
 spacer.custom_minimum_size = Vector2(0, 8)
 root.add_child(spacer)

 var grid: = GridContainer.new()
 grid.columns = 4
 grid.add_theme_constant_override("h_separation", 14)
 grid.add_theme_constant_override("v_separation", 14)
 root.add_child(grid)

 for cls in GameState.CLASSES:
  var info: Dictionary = GameState.CLASSES[cls]
  var card: = PanelContainer.new()
  card.custom_minimum_size = Vector2(330, 190)
  card.add_theme_stylebox_override("panel", _card_box(info["color"], false))
  card.mouse_filter = Control.MOUSE_FILTER_STOP
  var v: = VBoxContainer.new()
  v.add_theme_constant_override("separation", 5)
  card.add_child(v)
  v.add_child(UIKit.label(info["name"], 24, info["color"]))
  v.add_child(UIKit.label(info["role"], 14, UIKit.DIM))
  var p: = UIKit.label("◈ " + info["passive"], 13, UIKit.WHITE)
  p.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  v.add_child(p)
  var a: = UIKit.label("[Q] " + info["active"] + " · %d BW" % info["cost"], 13, UIKit.CYAN)
  a.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  v.add_child(a)
  card.gui_input.connect(_on_card_input.bind(cls))
  grid.add_child(card)
  cards[cls] = card

 var spacer2: = Control.new()
 spacer2.custom_minimum_size = Vector2(0, 6)
 spacer2.size_flags_vertical = Control.SIZE_EXPAND_FILL
 root.add_child(spacer2)

 var target: = UIKit.label("КАМПАНИЯ: заражение Грида — от домашнего ПК через офисы и банки к дата-центру и боссу ОРАКУЛ", 16, UIKit.AMBER)
 root.add_child(target)

 var bottom: = HBoxContainer.new()
 bottom.add_theme_constant_override("separation", 14)
 root.add_child(bottom)
 start_btn = UIKit.button("  ОДИНОЧНАЯ ▸  ", 22, UIKit.TEAL)
 start_btn.disabled = true
 start_btn.pressed.connect(_on_start)
 bottom.add_child(start_btn)
 host_btn = UIKit.button("  СОЗДАТЬ ЛОББИ  ", 18, UIKit.CYAN)
 host_btn.disabled = true
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
 join_btn.disabled = true
 join_btn.pressed.connect(_on_join)
 bottom.add_child(join_btn)
 hint_label = UIKit.label("выберите класс…", 15, UIKit.DIM)
 bottom.add_child(hint_label)

 _build_preview()
 _build_lobby()

func _build_lobby() -> void :
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
 v.add_child(UIKit.label("ЛОББИ КОМАНДЫ // конвейер ролей", 26, UIKit.TEAL))
 lobby_status_label = UIKit.label("", 15, UIKit.DIM)
 v.add_child(lobby_status_label)
 lobby_list = VBoxContainer.new()
 lobby_list.add_theme_constant_override("separation", 6)
 lobby_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
 v.add_child(lobby_list)
 v.add_child(UIKit.label("совет ТЗ: разные классы = конвейер (пробой → кража → зачистка)", 13, UIKit.DIM))
 v.add_child(UIKit.label("в рейде: [1-4] эмоции · [G] подлянка другу · гонка за MVP узла", 13, UIKit.AMBER))
 var row: = HBoxContainer.new()
 row.add_theme_constant_override("separation", 16)
 v.add_child(row)
 lobby_start_btn = UIKit.button("  СТАРТ РЕЙДА ▸  ", 20, UIKit.TEAL)
 lobby_start_btn.pressed.connect(func() -> void : Net.start_campaign())
 row.add_child(lobby_start_btn)
 var leave: = UIKit.button("  ПОКИНУТЬ  ", 18, UIKit.MAGENTA)
 leave.pressed.connect(func() -> void :
  Net.leave()
  lobby_panel.visible = false)
 row.add_child(leave)
 Net.players_changed.connect(_refresh_lobby)
 Net.lobby_status.connect(func(t: String) -> void : lobby_status_label.text = t)

func _refresh_lobby() -> void :
 for c in lobby_list.get_children():
  c.queue_free()
 for id in Net.players:
  var p: Dictionary = Net.players[id]
  var info: Dictionary = GameState.CLASSES[p["cls"]]
  var line: = UIKit.label("▸ %s — %s (%s)" % [p["name"], info["name"], info["role"]], 17, info["color"])
  lobby_list.add_child(line)
 lobby_start_btn.visible = Net.active and Net.is_server()
 lobby_start_btn.disabled = Net.players.size() < 2

func _on_host() -> void :
 if selected == "":
  return
 if Net.host_game(selected, nick_edit.text.strip_edges()):
  lobby_panel.visible = true
  _refresh_lobby()

func _on_join() -> void :
 if selected == "":
  return
 if Net.join_game(ip_edit.text.strip_edges(), selected, nick_edit.text.strip_edges()):
  lobby_panel.visible = true
  lobby_status_label.text = "подключение к %s…" % (ip_edit.text if ip_edit.text != "" else "127.0.0.1")
  _refresh_lobby()

func _build_preview() -> void :
 # 3D-превью штамма в пустой ячейке сетки (4-я колонка, 2-й ряд)
 var svc: = SubViewportContainer.new()
 svc.stretch = true
 svc.position = Vector2(1122, 448)
 svc.size = Vector2(330, 260)
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

 _preview_hint = UIKit.label("← кликни штамм,\n   чтобы рассмотреть", 15, UIKit.DIM)
 _preview_hint.position = Vector2(1180, 540)
 add_child(_preview_hint)

func _update_preview() -> void :
 if _preview_model != null:
  _preview_model.queue_free()
  _preview_model = null
 if selected == "":
  return
 _preview_hint.visible = false
 _preview_model = VirusModel.create(selected, GameState.CLASSES[selected]["color"])
 _preview_holder.add_child(_preview_model)

func _card_box(color: Color, active: bool) -> StyleBoxFlat:
 if active:
  return UIKit.panel_box(color, Color(color.r * 0.14, color.g * 0.14, color.b * 0.16, 0.95), 2, 8)
 return UIKit.panel_box(Color(color.r, color.g, color.b, 0.35), UIKit.PANEL_DARK, 1, 8)

func _on_card_input(event: InputEvent, cls: String) -> void :
 if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
  selected = cls
  for c in cards:
   var info: Dictionary = GameState.CLASSES[c]
   cards[c].add_theme_stylebox_override("panel", _card_box(info["color"], c == selected))
  start_btn.disabled = false
  host_btn.disabled = false
  join_btn.disabled = false
  hint_label.text = "штамм: %s — %s" % [GameState.CLASSES[cls]["name"], GameState.CLASSES[cls]["role"]]
  Sfx.play("ui_click", -8.0)
  Net.set_class(cls)
  GameState.selected_class = cls
  _update_preview()

func _on_start() -> void :
 if selected == "":
  return
 Net.leave()
 GameState.new_campaign(selected)
 get_tree().change_scene_to_file("res://scenes/grid_world.tscn")

func _process(delta: float) -> void :
 if _preview_holder != null:
  _preview_holder.rotation.y += delta * 0.7
 _glyph_timer += delta
 for g in _glyphs:
  g["pos"].y += g["speed"] * delta
  if g["pos"].y > 920.0:
   g["pos"].y = -20.0
   g["pos"].x = randf() * 1600.0
 queue_redraw()

func _draw() -> void :
 var font: = get_theme_default_font()
 for g in _glyphs:
  draw_string(font, g["pos"], g["char"], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 
   Color(UIKit.CYAN.r, UIKit.CYAN.g, UIKit.CYAN.b, g["alpha"]))
 for x in range(0, 1601, 80):
  draw_line(Vector2(x, 0), Vector2(x, 900), Color(0.1, 0.4, 0.55, 0.05))
 for y in range(0, 901, 80):
  draw_line(Vector2(0, y), Vector2(1600, y), Color(0.1, 0.4, 0.55, 0.05))
