extends MinigameBase




var charge: = 0.0
var holding: = false
var fill_rate: = 0.55
var band_lo: = 0.6
var band_hi: = 0.78
var _result_flash: = 0.0
var _result_col: = Color.WHITE

func _init() -> void :
 rounds_needed = 3
 hint = "зажми и держи [ПРОБЕЛ], отпусти внутри зелёной полосы · перелив = провал"

func _apply_difficulty(diff: int) -> void :
 if diff >= 3:
  rounds_needed = 4

func _new_round() -> void :
 charge = 0.0
 holding = false
 fill_rate = (0.5 + 0.09 * float(rounds_done) + 0.06 * float(difficulty)) / timer_mult
 if "haste" in layer["mutators"]:
  fill_rate *= 1.3
 var width: = clampf(0.2 - 0.03 * float(rounds_done) - 0.02 * float(difficulty), 0.08, 0.2)
 var lo: = randf_range(0.5, 0.82 - width)
 band_lo = lo
 band_hi = lo + width
 set_status("зажми [ПРОБЕЛ] чтобы заполнять буфер", UIKit.DIM)

func _restart_round() -> void :
 charge = 0.0
 holding = false

func _process(delta: float) -> void :
 super._process(delta)
 if _finished:
  return
 _result_flash = maxf(_result_flash - delta * 2.5, 0.0)
 holding = Input.is_action_pressed("mg_action")
 if holding:
  charge += game_delta(delta) * fill_rate
  if charge >= 1.0:
   charge = 1.0
   holding = false
   _result_col = Color(1.0, 0.2, 0.3)
   _result_flash = 1.0
   miss("переполнение буфера")

func _unhandled_input(event: InputEvent) -> void :
 if _finished:
  return
 if event.is_action_released("mg_action") and charge > 0.02 and charge < 1.0:
  if charge >= band_lo and charge <= band_hi:
   _result_col = UIKit.TEAL
   _result_flash = 1.0
   round_success()
  else:
   _result_col = UIKit.AMBER
   _result_flash = 1.0
   miss("буфер не в полосе")
  charge = 0.0

func _draw() -> void :
 _draw_frame()
 var bar: = Rect2(PLAY.position.x + PLAY.size.x * 0.5 - 44, PLAY.position.y + 46, 88, PLAY.size.y - 130)

 draw_rect(bar, Color(0.02, 0.05, 0.08, 0.95), true)
 draw_rect(bar, Color(0.2, 0.4, 0.5, 0.6), false, 2.0)

 var band_y: = bar.position.y + bar.size.y * (1.0 - band_hi)
 var band_h: = bar.size.y * (band_hi - band_lo)
 draw_rect(Rect2(bar.position.x - 10, band_y, bar.size.x + 20, band_h), Color(0.16, 0.95, 0.75, 0.22), true)
 draw_rect(Rect2(bar.position.x - 10, band_y, bar.size.x + 20, band_h), UIKit.TEAL, false, 2.0)

 var fill_h: = bar.size.y * charge
 var fc: = UIKit.CYAN
 if charge > band_hi:
  fc = Color(1.0, 0.35, 0.3)
 elif charge >= band_lo:
  fc = UIKit.TEAL
 draw_rect(Rect2(bar.position.x + 3, bar.end.y - fill_h, bar.size.x - 6, fill_h), fc, true)

 draw_rect(Rect2(bar.position.x, bar.position.y, bar.size.x, bar.size.y * 0.12), Color(1.0, 0.2, 0.3, 0.14), true)

 if _result_flash > 0.0:
  draw_rect(bar.grow(8.0), Color(_result_col.r, _result_col.g, _result_col.b, _result_flash * 0.5), false, 4.0)

 var font: = get_theme_default_font()
 draw_string(font, Vector2(bar.end.x + 26, band_y + band_h * 0.5), "◄ ОКНО ПРОШИВКИ", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UIKit.TEAL)
 draw_string(font, Vector2(bar.position.x - 200, bar.position.y + 30), "буфер %d%%" % roundi(charge * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UIKit.DIM)
 draw_string(font, Vector2(bar.position.x - 200, bar.position.y + 4), "сегмент %d/%d" % [rounds_done + 1, rounds_needed], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UIKit.DIM)
 _draw_noise_overlay()
