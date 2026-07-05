class_name UIKit


const BG: = Color(0.014, 0.028, 0.052)
const PANEL: = Color(0.028, 0.055, 0.095, 0.94)
const PANEL_DARK: = Color(0.012, 0.026, 0.048, 0.97)
const CYAN: = Color(0.21, 0.85, 1.0)
const TEAL: = Color(0.16, 0.95, 0.75)
const MAGENTA: = Color(1.0, 0.26, 0.46)
const AMBER: = Color(1.0, 0.7, 0.35)
const VIOLET: = Color(0.6, 0.42, 1.0)
const DIM: = Color(0.5, 0.68, 0.78)
const WHITE: = Color(0.88, 0.95, 1.0)

static func panel_box(border: Color = CYAN, bg: Color = PANEL, border_w: int = 1, radius: int = 6, margin: int = 14) -> StyleBoxFlat:
 var sb: = StyleBoxFlat.new()
 sb.bg_color = bg
 sb.border_color = border
 sb.set_border_width_all(border_w)
 sb.set_corner_radius_all(radius)
 sb.set_content_margin_all(margin)
 return sb

static func label(text: String, size: int, color: Color = WHITE) -> Label:
 var l: = Label.new()
 l.text = text
 l.add_theme_font_size_override("font_size", size)
 l.add_theme_color_override("font_color", color)
 return l

static func button(text: String, size: int = 20, accent: Color = CYAN) -> Button:
 var b: = Button.new()
 b.text = text
 b.add_theme_font_size_override("font_size", size)
 var dim_accent: = Color(accent.r, accent.g, accent.b, 0.65)
 b.add_theme_stylebox_override("normal", panel_box(dim_accent, Color(0.035, 0.08, 0.13, 0.9), 1, 4, 10))
 b.add_theme_stylebox_override("hover", panel_box(accent, Color(0.06, 0.14, 0.2, 0.95), 1, 4, 10))
 b.add_theme_stylebox_override("pressed", panel_box(accent, Color(0.09, 0.19, 0.26, 1.0), 2, 4, 10))
 b.add_theme_stylebox_override("disabled", panel_box(Color(0.3, 0.4, 0.45, 0.35), Color(0.02, 0.04, 0.07, 0.7), 1, 4, 10))
 b.add_theme_color_override("font_color", WHITE)
 b.add_theme_color_override("font_hover_color", Color.WHITE)
 b.add_theme_color_override("font_disabled_color", Color(0.42, 0.52, 0.58))
 b.pressed.connect(func() -> void : b.get_node("/root/Sfx").play("ui_click", -6.0))
 return b

static func full_rect(c: Control) -> Control:
 c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 return c


static func meter(width: float, height: float, fill_color: Color, text: String) -> Dictionary:
 var root: = Panel.new()
 root.custom_minimum_size = Vector2(width, height)
 root.add_theme_stylebox_override("panel", panel_box(Color(fill_color.r, fill_color.g, fill_color.b, 0.5), PANEL_DARK, 1, 3, 0))
 var fill: = ColorRect.new()
 fill.color = fill_color
 fill.position = Vector2(2, 2)
 fill.size = Vector2(0, height - 4)
 root.add_child(fill)
 var cap: = label(text, int(height * 0.55), WHITE)
 cap.position = Vector2(8, height * 0.14)
 root.add_child(cap)
 return {"root": root, "fill": fill, "label": cap, "width": width}

static func set_meter(m: Dictionary, ratio: float, color: = Color.TRANSPARENT) -> void :
 var fill: ColorRect = m["fill"]
 fill.size.x = maxf((float(m["width"]) - 4.0) * clampf(ratio, 0.0, 1.0), 0.0)
 if color != Color.TRANSPARENT:
  fill.color = color
