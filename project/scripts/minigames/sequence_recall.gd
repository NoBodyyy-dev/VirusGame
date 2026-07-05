extends MinigameBase




const PORTS: = 6
const COLORS: = [Color("35e0ff"), Color("38f0a8"), Color("ffb454"), Color("ff5d8f"), Color("8b5cff"), Color("2fe6b0")]

var buttons: Array = []
var centers: Array = []
var sequence: Array = []
var state: = "wait"
var show_index: = 0
var show_timer: = 0.0
var input_index: = 0
var flash_port: = -1
var _wait_timer: = 0.0
var _drift: = 0.0

func _init() -> void :
 rounds_needed = 3
 hint = "запомни порядок вспышек · затем кликай порты в той же последовательности"

func _apply_difficulty(diff: int) -> void :
 if diff >= 3:
  rounds_needed = 4

func _ready() -> void :
 super._ready()
 var cx: = PLAY.position.x + PLAY.size.x * 0.5
 var cy: = PLAY.position.y + PLAY.size.y * 0.5 + 10.0
 var rad: = 150.0
 for i in PORTS:
  var ang: = TAU * float(i) / float(PORTS) - PI * 0.5
  var c: = Vector2(cx + cos(ang) * rad * 1.35, cy + sin(ang) * rad)
  centers.append(c)
  var btn: = Button.new()
  btn.custom_minimum_size = Vector2(96, 96)
  btn.size = Vector2(96, 96)
  btn.position = c - Vector2(48, 48)
  btn.focus_mode = Control.FOCUS_NONE
  btn.flat = true
  btn.pressed.connect(_on_port.bind(i))
  add_child(btn)
  buttons.append(btn)

 _start_sequence()

func _new_round() -> void :
 if centers.is_empty():
  return
 _start_sequence()

func _restart_round() -> void :
 _start_sequence()

func _start_sequence() -> void :
 var length: = 3 + rounds_done + (1 if difficulty >= 2 else 0)
 sequence.clear()
 for i in length:
  sequence.append(randi() % PORTS)
 state = "show"
 show_index = 0
 show_timer = 0.55
 flash_port = -1
 _wait_timer = 0.4
 set_status("HONEYPOT ПЕРЕДАЁТ ПОСЛЕДОВАТЕЛЬНОСТЬ…", UIKit.AMBER)

func _process(delta: float) -> void :
 super._process(delta)
 if _finished:
  return
 var gd: = game_delta(delta) / timer_mult
 if moving:
  # подвижная цель: порты медленно плывут по кругу
  _drift += gd * 0.3
  var cx: = PLAY.position.x + PLAY.size.x * 0.5
  var cy: = PLAY.position.y + PLAY.size.y * 0.5 + 10.0
  var rad: = 150.0
  for i in PORTS:
   var ang: = TAU * float(i) / float(PORTS) - PI * 0.5 + _drift
   centers[i] = Vector2(cx + cos(ang) * rad * 1.35, cy + sin(ang) * rad)
   buttons[i].position = centers[i] - Vector2(48, 48)
 match state:
  "show":
   if _wait_timer > 0.0:
    _wait_timer -= gd
    return
   show_timer -= gd
   var on_time: = 0.34
   if show_timer > 0.0:
    var elapsed: = 0.55 - show_timer
    flash_port = sequence[show_index] if elapsed < on_time else -1
   else:
    show_index += 1
    show_timer = 0.55
    flash_port = -1
    if show_index >= sequence.size():
     state = "input"
     input_index = 0
     set_status("ПОВТОРИ: кликай порты по памяти (%d)" % sequence.size(), UIKit.TEAL)

func _on_port(i: int) -> void :
 if _finished or state != "input":
  return
 flash_port = i
 get_tree().create_timer(0.14).timeout.connect( func() -> void : flash_port = -1)
 if sequence[input_index] == i:
  input_index += 1
  if input_index >= sequence.size():
   round_success()
 else:
  miss("неверный порт")

func _draw() -> void :
 _draw_frame()
 var font: = get_theme_default_font()
 for i in PORTS:
  var c: Vector2 = centers[i]
  var col: Color = COLORS[i]
  var active: = (i == flash_port)
  var r: = 44.0
  draw_circle(c, r + 8.0, Color(col.r, col.g, col.b, 0.25 if active else 0.06))
  draw_circle(c, r, Color(col.r, col.g, col.b, 0.95) if active else Color(0.03, 0.06, 0.09, 0.95))
  draw_arc(c, r, 0, TAU, 40, Color(col.r, col.g, col.b, 1.0 if active else 0.5), 2.5)
  if not blackout:
   var num: = "%d" % (i + 1)
   draw_string(font, c - Vector2(7, -8), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 
    Color.BLACK if active else Color(col.r, col.g, col.b, 0.8))

 if state == "input":
  var bx: = PLAY.position.x + 30.0
  var by: = PLAY.end.y - 30.0
  for i in sequence.size():
   var done: = i < input_index
   draw_rect(Rect2(bx + i * 26.0, by, 20, 12), UIKit.TEAL if done else Color(0.1, 0.2, 0.26), true)
 _draw_noise_overlay()
