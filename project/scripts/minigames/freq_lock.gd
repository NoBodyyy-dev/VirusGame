extends MinigameBase




var tgt_freq: = 3.0
var tgt_phase: = 0.0
var tgt_freq2: = 0.0
var my_freq: = 2.0
var my_phase: = 0.0
var match_ratio: = 0.0
var threshold: = 0.9
var _drift: = 0.0

func _init() -> void :
 rounds_needed = 3
 hint = "←/→ частота · ↑/↓ фаза · [ПРОБЕЛ] когда совпадение выше порога"

func _apply_difficulty(diff: int) -> void :
 if diff >= 3:
  rounds_needed = 4

func _new_round() -> void :
 tgt_freq = randf_range(1.6, 4.6)
 tgt_phase = randf_range(0.0, TAU)
 tgt_freq2 = 0.0
 if difficulty >= 2 and rounds_done >= 1:
  tgt_freq2 = randf_range(1.0, 2.2)
 my_freq = randf_range(1.6, 4.6)
 my_phase = randf_range(0.0, TAU)
 threshold = clampf(0.88 + 0.02 * float(rounds_done) + 0.015 * float(difficulty), 0.86, 0.965)
 _drift = 0.0
 set_status("настрой волну под шифр…", UIKit.DIM)

func _restart_round() -> void :
 my_freq = randf_range(1.6, 4.6)
 my_phase = randf_range(0.0, TAU)

func _target_at(x: float) -> float:
 var v: = sin(x * tgt_freq + tgt_phase + _drift)
 if tgt_freq2 > 0.0:
  v = (v + 0.6 * sin(x * (tgt_freq + tgt_freq2) + tgt_phase)) / 1.6
 return v

func _mine_at(x: float) -> float:
 return sin(x * my_freq + my_phase)

func _process(delta: float) -> void :
 super._process(delta)
 if _finished:
  return
 var gd: = game_delta(delta)
 var dir: = 1.0
 if mirror:
  dir = -1.0
 if Input.is_action_pressed("mg_left"):
  my_freq -= gd * 1.6 * dir
 if Input.is_action_pressed("mg_right"):
  my_freq += gd * 1.6 * dir
 if Input.is_action_pressed("mg_up"):
  my_phase += gd * 3.2
 if Input.is_action_pressed("mg_down"):
  my_phase -= gd * 3.2
 my_freq = clampf(my_freq, 0.8, 6.0)
 if "haste" in layer["mutators"] or difficulty >= 3:
  _drift += gd * 0.25


 var err: = 0.0
 var samples: = 48
 for i in samples:
  var x: = TAU * float(i) / float(samples)
  err += absf(_target_at(x) - _mine_at(x))
 match_ratio = clampf(1.0 - (err / float(samples)) / 1.4, 0.0, 1.0)
 if match_ratio >= threshold:
  set_status("СИНХРОНИЗАЦИЯ %d%% ✓ — жми [ПРОБЕЛ]" % roundi(match_ratio * 100.0), UIKit.TEAL)
 else:
  set_status("совпадение %d%% (нужно %d%%)" % [roundi(match_ratio * 100.0), roundi(threshold * 100.0)], UIKit.DIM)

func _unhandled_input(event: InputEvent) -> void :
 if _finished:
  return
 if event.is_action_pressed("mg_action"):
  accept_event()
  if match_ratio >= threshold:
   round_success()
  else:
   miss("рассинхрон")

func _draw() -> void :
 _draw_frame()
 var midy: = PLAY.position.y + PLAY.size.y * 0.42
 var amp: = PLAY.size.y * 0.24
 var x0: = PLAY.position.x + 30.0
 var w: = PLAY.size.x - 60.0
 var steps: = 120

 if not blackout or match_ratio > 0.5:
  var pts_t: = PackedVector2Array()
  for i in steps + 1:
   var t: = float(i) / float(steps)
   pts_t.append(Vector2(x0 + t * w, midy - _target_at(t * TAU) * amp))
  draw_polyline(pts_t, Color(UIKit.MAGENTA.r, UIKit.MAGENTA.g, UIKit.MAGENTA.b, 0.55), 2.0)

 var mc: = UIKit.TEAL if match_ratio >= threshold else UIKit.CYAN
 var pts_m: = PackedVector2Array()
 for i in steps + 1:
  var t: = float(i) / float(steps)
  pts_m.append(Vector2(x0 + t * w, midy - _mine_at(t * TAU) * amp))
 draw_polyline(pts_m, mc, 2.5)


 var by: = PLAY.end.y - 54.0
 var bw: = PLAY.size.x - 60.0
 draw_rect(Rect2(x0, by, bw, 18), Color(0.03, 0.07, 0.1), true)
 draw_rect(Rect2(x0, by, bw * match_ratio, 18), mc, true)
 var tx: = x0 + bw * threshold
 draw_line(Vector2(tx, by - 6), Vector2(tx, by + 24), UIKit.AMBER, 2.0)
 var font: = get_theme_default_font()
 draw_string(font, Vector2(x0, by - 12), "СОВПАДЕНИЕ СИГНАЛА", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UIKit.DIM)
 _draw_noise_overlay()
