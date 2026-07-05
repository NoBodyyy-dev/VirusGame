extends MinigameBase




var sweep: = 0.0
var speed: = 2.0
var blips: Array = []
var tol: = 0.22
var center: = Vector2.ZERO
var radius: = 150.0
var _flash: = 0.0
var _miss_flash: = 0.0

func _init() -> void :
 rounds_needed = 3
 hint = "[ПРОБЕЛ] в момент, когда луч развёртки касается пакета"

func _apply_difficulty(diff: int) -> void :
 if diff >= 3:
  rounds_needed = 4

func _ready() -> void :
 super._ready()
 center = Vector2(PLAY.position.x + PLAY.size.x * 0.5, PLAY.position.y + PLAY.size.y * 0.5 + 8.0)
 radius = PLAY.size.y * 0.34

func _new_round() -> void :
 var count: = 3 + rounds_done + (1 if difficulty >= 2 else 0)
 speed = (1.7 + 0.25 * float(rounds_done) + 0.2 * float(difficulty)) / timer_mult
 if "haste" in layer["mutators"]:
  speed *= 1.25
 tol = clampf(0.24 - 0.02 * float(rounds_done) - 0.015 * float(difficulty), 0.11, 0.24)
 sweep = 0.0
 blips.clear()
 var used: Array = []
 for i in count:
  var a: = 0.0
  for attempt in 20:
   a = randf() * TAU
   var ok: = true
   for u in used:
    if absf(_ang_diff(a, u)) < tol * 2.6:
     ok = false
   if ok:
    break
  used.append(a)
  blips.append({"angle": a, "hit": false})
 set_status("развёртка пошла — сбивай пакеты", UIKit.DIM)

func _restart_round() -> void :
 for b in blips:
  b["hit"] = false
 sweep = 0.0

func _ang_diff(a: float, b: float) -> float:
 var d: = fmod(a - b + PI, TAU) - PI
 return d

func _process(delta: float) -> void :
 super._process(delta)
 if _finished:
  return
 _flash = maxf(_flash - delta * 3.0, 0.0)
 _miss_flash = maxf(_miss_flash - delta * 3.0, 0.0)
 if moving:
  for b in blips:
   if not b["hit"]:
    b["angle"] = fmod(b["angle"] + game_delta(delta) * 0.35, TAU)
 var prev: = sweep
 sweep = fmod(sweep + game_delta(delta) * speed, TAU)

 if prev > sweep:
  for b in blips:
   if not b["hit"]:
    if miss("пакет ушёл в IDS"):
     return

func _unhandled_input(event: InputEvent) -> void :
 if _finished:
  return
 if event.is_action_pressed("mg_action"):
  accept_event()
  var target: Dictionary = {}
  var best: = 999.0
  for b in blips:
   if b["hit"]:
    continue
   var d: float = absf(_ang_diff(sweep, b["angle"]))
   if d < best:
    best = d
    target = b
  if not target.is_empty() and best <= tol:
   target["hit"] = true
   _flash = 1.0
   set_status("сбит (%d/%d)" % [_hit_count(), blips.size()], UIKit.TEAL)
   if _hit_count() >= blips.size():
    round_success()
  else:
   _miss_flash = 1.0
   miss("мимо цели")

func _hit_count() -> int:
 var c: = 0
 for b in blips:
  if b["hit"]:
   c += 1
 return c

func _draw() -> void :
 _draw_frame()
 var c: Color = layer["color"]

 draw_arc(center, radius, 0, TAU, 64, Color(c.r, c.g, c.b, 0.3), 2.0)
 draw_arc(center, radius * 0.5, 0, TAU, 48, Color(c.r, c.g, c.b, 0.12), 1.0)

 for i in 12:
  var a: = sweep - float(i) * 0.05
  var col: = Color(UIKit.CYAN.r, UIKit.CYAN.g, UIKit.CYAN.b, 0.28 * (1.0 - float(i) / 12.0))
  draw_line(center, center + Vector2(cos(a), sin(a)) * radius, col, 3.0)
 var tip: = center + Vector2(cos(sweep), sin(sweep)) * radius
 draw_line(center, tip, Color.WHITE if _flash > 0.0 else UIKit.CYAN, 3.0)

 for b in blips:
  var bp: Vector2 = center + Vector2(cos(b["angle"]), sin(b["angle"])) * radius
  if b["hit"]:
   draw_circle(bp, 13.0, UIKit.TEAL)
   continue
  var near: bool = absf(_ang_diff(sweep, b["angle"])) <= tol
  if blackout and not near:
   continue
  var pc: = UIKit.AMBER if near else Color(1.0, 0.35, 0.45)
  draw_circle(bp, 15.0, Color(pc.r, pc.g, pc.b, 0.25))
  draw_circle(bp, 9.0, pc)
 if _miss_flash > 0.0:
  draw_arc(center, radius + 6.0, 0, TAU, 64, Color(1.0, 0.2, 0.3, _miss_flash * 0.6), 3.0)
 var font: = get_theme_default_font()
 draw_string(font, Vector2(PLAY.position.x + 30, PLAY.position.y + 40), 
  "оборот %d/%d · сбито %d/%d" % [rounds_done + 1, rounds_needed, _hit_count(), blips.size()], 
  HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UIKit.DIM)
 _draw_noise_overlay()
