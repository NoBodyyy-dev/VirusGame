extends MinigameBase




var num_inputs: = 3
var bits: Array = []
var expr = null
var target: = true
var round_time: = 20.0
var time_left: = 20.0
var in_buttons: Array = []
var _lamp_on: = false

const LETTERS: = "ABCDE"

func _init() -> void :
 rounds_needed = 3
 hint = "клик по входу — переключить бит · [ПРОБЕЛ] — зафиксировать, когда OUT = 1"

func _apply_difficulty(diff: int) -> void :
 if diff >= 3:
  rounds_needed = 4

func _new_round() -> void :
 num_inputs = clampi(3 + rounds_done, 3, 4)
 round_time = maxf(24.0 - 3.0 * float(rounds_done) - 2.0 * float(difficulty), 10.0) * timer_mult
 time_left = round_time
 _generate_circuit()
 _rebuild_buttons()
 _recompute()

func _restart_round() -> void :

 for i in bits.size():
  bits[i] = randf() < 0.5
 time_left = round_time
 _update_buttons()
 _recompute()

func _generate_circuit() -> void :
 var depth: = mini(2 + rounds_done, 3)
 for attempt in 24:
  bits.resize(num_inputs)
  for i in num_inputs:
   bits[i] = randf() < 0.5
  expr = _gen(depth)

  var ones: = 0
  var combos: = 1 << num_inputs
  for mask in combos:
   var test: Array = []
   for i in num_inputs:
    test.append((mask >> i) & 1 == 1)
   if _eval(expr, test):
    ones += 1
  if ones > 0 and ones < combos:
   return
 target = true

func _gen(depth: int):
 if depth <= 0 or (randf() < 0.28 and depth < 3):
  return ["in", randi() % num_inputs]
 var op: String = ["and", "or", "xor"].pick_random()
 var a = _gen(depth - 1)
 var b = _gen(depth - 1)
 if randf() < 0.3:
  a = ["not", a]
 if randf() < 0.2:
  b = ["not", b]
 return [op, a, b]

func _eval(node, test: Array) -> bool:
 match node[0]:
  "in": return test[node[1]]
  "not": return not _eval(node[1], test)
  "and": return _eval(node[1], test) and _eval(node[2], test)
  "or": return _eval(node[1], test) or _eval(node[2], test)
  "xor": return _eval(node[1], test) != _eval(node[2], test)
 return false

func _to_str(node) -> String:
 match node[0]:
  "in": return LETTERS[node[1]]
  "not": return "¬" + _to_str(node[1])
  "and": return "(%s ∧ %s)" % [_to_str(node[1]), _to_str(node[2])]
  "or": return "(%s ∨ %s)" % [_to_str(node[1]), _to_str(node[2])]
  "xor": return "(%s ⊕ %s)" % [_to_str(node[1]), _to_str(node[2])]
 return "?"

func _rebuild_buttons() -> void :
 for b in in_buttons:
  b.queue_free()
 in_buttons.clear()
 var bx: = PLAY.position.x + 60.0
 var gap: = (PLAY.size.y - 120.0) / float(maxi(num_inputs - 1, 1))
 for i in num_inputs:
  var btn: = Button.new()
  btn.custom_minimum_size = Vector2(150, 66)
  btn.size = Vector2(150, 66)
  btn.position = Vector2(bx, PLAY.position.y + 60.0 + gap * float(i) - 33.0)
  btn.add_theme_font_size_override("font_size", 22)
  btn.focus_mode = Control.FOCUS_NONE
  btn.pressed.connect(_on_toggle.bind(i))
  add_child(btn)
  in_buttons.append(btn)
 _update_buttons()

func _update_buttons() -> void :
 for i in in_buttons.size():
  var on: bool = bits[i]
  var col: = UIKit.TEAL if on else Color(0.3, 0.42, 0.5)
  in_buttons[i].text = "%s = %d" % [LETTERS[i], 1 if on else 0]
  in_buttons[i].add_theme_stylebox_override("normal", UIKit.panel_box(col, Color(0.03, 0.09, 0.13, 0.95) if on else Color(0.02, 0.04, 0.06, 0.9), 2, 5, 8))
  in_buttons[i].add_theme_stylebox_override("hover", UIKit.panel_box(Color.WHITE, Color(0.05, 0.12, 0.16, 1.0), 2, 5, 8))
  in_buttons[i].add_theme_color_override("font_color", UIKit.WHITE)

func _on_toggle(i: int) -> void :
 if _finished:
  return
 bits[i] = not bits[i]
 _update_buttons()
 _recompute()

func _recompute() -> void :
 _lamp_on = _eval(expr, bits)
 if _lamp_on:
  set_status("OUT = 1 ✓  — жми [ПРОБЕЛ] чтобы прошить", UIKit.TEAL)
 else:
  set_status("OUT = 0  — подберите входы", UIKit.DIM)

func _process(delta: float) -> void :
 super._process(delta)
 if _finished:
  return
 time_left -= game_delta(delta)
 if time_left <= 0.0:
  miss("таймаут схемы")

func _unhandled_input(event: InputEvent) -> void :
 if _finished:
  return
 if event.is_action_pressed("mg_action"):
  accept_event()
  if _lamp_on == target:
   round_success()
  else:
   miss("выход не совпал")

func _draw() -> void :
 _draw_frame()
 var font: = get_theme_default_font()

 var formula: = "OUT = %s" % _to_str(expr)
 if blackout:
  formula = "OUT = [схема зашифрована — выводите перебором]"
 draw_multiline_string(font, Vector2(PLAY.position.x + 240, PLAY.position.y + 68), formula, 
  HORIZONTAL_ALIGNMENT_LEFT, PLAY.size.x - 470, 22, -1, Color(UIKit.CYAN.r, UIKit.CYAN.g, UIKit.CYAN.b, 0.9))


 var core: = Vector2(PLAY.end.x - 230, PLAY.position.y + PLAY.size.y * 0.5)
 for i in in_buttons.size():
  var from: Vector2 = in_buttons[i].position + Vector2(155, 33)
  var col: = Color(UIKit.TEAL.r, UIKit.TEAL.g, UIKit.TEAL.b, 0.5) if bits[i] else Color(0.25, 0.35, 0.42, 0.4)
  draw_line(from, from + Vector2(60, 0), col, 2.0)
  draw_line(from + Vector2(60, 0), core, col, 2.0)

 draw_circle(core, 46.0, Color(0.02, 0.05, 0.08, 0.9))
 draw_arc(core, 46.0, 0, TAU, 48, Color(UIKit.CYAN.r, UIKit.CYAN.g, UIKit.CYAN.b, 0.6), 2.0)
 draw_string(font, core - Vector2(30, -8), "ЛОГИКА", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UIKit.DIM)


 var lamp: = Vector2(PLAY.end.x - 110, PLAY.position.y + PLAY.size.y * 0.5)
 draw_line(core + Vector2(46, 0), lamp - Vector2(38, 0), Color(0.3, 0.4, 0.5, 0.5), 2.0)
 var lc: = UIKit.TEAL if _lamp_on else Color(0.4, 0.12, 0.16)
 draw_circle(lamp, 38.0, Color(lc.r, lc.g, lc.b, 0.22))
 draw_circle(lamp, 26.0, lc)
 draw_string(font, lamp - Vector2(9, -8), "1" if _lamp_on else "0", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.BLACK)
 draw_string(font, lamp - Vector2(24, -60), "OUT", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UIKit.DIM)

 _draw_timer_bar(time_left / round_time)
 _draw_noise_overlay()
