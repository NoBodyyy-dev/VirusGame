extends Control



var res_label: Label
var progress_label: Label
var heat_label: Label
var class_label: Label
var prompt_label: Label
var pickup_label: Label
var _t: = 0.0

func _ready() -> void :
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter = Control.MOUSE_FILTER_IGNORE

 var top: = VBoxContainer.new()
 top.position = Vector2(24, 20)
 top.add_theme_constant_override("separation", 6)
 add_child(top)
 var info: Dictionary = GameState.class_info()
 class_label = UIKit.label("ШТАММ: %s" % info["name"], 20, info["color"])
 top.add_child(class_label)
 progress_label = UIKit.label("", 18, UIKit.TEAL)
 top.add_child(progress_label)
 heat_label = UIKit.label("", 16, UIKit.DIM)
 top.add_child(heat_label)

 res_label = UIKit.label("", 17, UIKit.WHITE)
 res_label.position = Vector2(24, 812)
 add_child(res_label)

 var help_text: = "WASD — движение · ПРОБЕЛ — прыжок · Shift — спринт · Tab — ЭВОЛЮЦИЯ · [E] у узла — взлом"
 if Net.active:
  help_text += " · [1-4] эмоции · [G] подлянка"
 var help: = UIKit.label(help_text, 15, UIKit.DIM)
 help.position = Vector2(24, 862)
 add_child(help)

 prompt_label = UIKit.label("", 22, UIKit.WHITE)
 prompt_label.position = Vector2(360, 780)
 prompt_label.size = Vector2(880, 40)
 prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 add_child(prompt_label)

 pickup_label = UIKit.label("", 22, UIKit.TEAL)
 pickup_label.position = Vector2(600, 120)
 pickup_label.size = Vector2(400, 40)
 pickup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 pickup_label.modulate.a = 0.0
 add_child(pickup_label)

 refresh()

func set_prompt(text: String) -> void :
 prompt_label.text = text

func flash_pickup(text: String) -> void :
 pickup_label.text = text
 pickup_label.modulate.a = 0.0
 pickup_label.position.y = 120
 var tw: = create_tween()
 tw.parallel().tween_property(pickup_label, "modulate:a", 1.0, 0.15)
 tw.parallel().tween_property(pickup_label, "position:y", 96, 0.6)
 tw.tween_property(pickup_label, "modulate:a", 0.0, 0.5)

func refresh() -> void :
 var r: Dictionary = GameState.resources
 res_label.text = "◈ Data %d   ◇ Code %d   ✦ Mutagen %d   ◆ Ghost %d   ⚡ 0-day %d" % [
  r["data_fragments"], r["code_samples"], r["mutagen"], r["ghost_tokens"], GameState.zero_days]
 progress_label.text = "ЗАРАЖЕНИЕ ГРИДА: %d / %d узлов" % [GameState.infected_total(), GameState.total_nodes()]
 var heat: = GameState.grid_heat
 if heat > 1.0:
  heat_label.text = "ТРЕВОГА ГРИДА: %d%% — узлы стартуют с повышенным Trace" % roundi(heat)
  heat_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.35).lerp(Color(1.0, 0.2, 0.25), heat / 100.0))
 else:
  heat_label.text = "тревога Грида: спокойно"
  heat_label.add_theme_color_override("font_color", UIKit.DIM)
