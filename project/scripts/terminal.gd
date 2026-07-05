class_name HackTerminal
extends Node3D


var layer: Dictionary
var done: = false

var screen_mat: StandardMaterial3D
var light: OmniLight3D
var title_label: Label3D
var _t: = 0.0

func setup(p_layer: Dictionary) -> void :
 layer = p_layer

func _ready() -> void :
 var c: Color = layer["color"]

 var base: = MeshInstance3D.new()
 var base_mesh: = BoxMesh.new()
 base_mesh.size = Vector3(0.9, 1.1, 0.55)
 base.mesh = base_mesh
 var base_mat: = StandardMaterial3D.new()
 base_mat.albedo_color = Color(0.04, 0.06, 0.09)
 base_mat.metallic = 0.6
 base_mat.roughness = 0.3
 base.material_override = base_mat
 base.position.y = 0.55
 add_child(base)

 var trim: = MeshInstance3D.new()
 var trim_mesh: = BoxMesh.new()
 trim_mesh.size = Vector3(0.94, 0.05, 0.59)
 trim.mesh = trim_mesh
 var trim_mat: = StandardMaterial3D.new()
 trim_mat.emission_enabled = true
 trim_mat.emission = c
 trim_mat.emission_energy_multiplier = 2.0
 trim_mat.albedo_color = Color(0.02, 0.03, 0.05)
 trim.material_override = trim_mat
 trim.position.y = 1.08
 add_child(trim)

 var screen: = MeshInstance3D.new()
 var quad: = QuadMesh.new()
 quad.size = Vector2(1.35, 0.85)
 screen.mesh = quad
 screen_mat = StandardMaterial3D.new()
 screen_mat.albedo_color = Color(0.02, 0.04, 0.06)
 screen_mat.emission_enabled = true
 screen_mat.emission = c
 screen_mat.emission_energy_multiplier = 1.8
 screen_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
 screen.material_override = screen_mat
 screen.position.y = 1.75
 screen.rotation.x = deg_to_rad(-12.0)
 add_child(screen)

 title_label = Label3D.new()
 title_label.text = "%s\n%s" % [layer["title"], GameState.MINIGAMES[layer["game"]]["title"]]
 title_label.font_size = 52
 title_label.modulate = c
 title_label.outline_size = 8
 title_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
 title_label.position.y = 2.6
 add_child(title_label)

 light = OmniLight3D.new()
 light.light_color = c
 light.light_energy = 2.2
 light.omni_range = 6.0
 light.position.y = 1.8
 add_child(light)

 var col: = StaticBody3D.new()
 col.collision_layer = 1
 var cs: = CollisionShape3D.new()
 var box: = BoxShape3D.new()
 box.size = Vector3(0.9, 1.9, 0.6)
 cs.shape = box
 cs.position.y = 0.95
 col.add_child(cs)
 add_child(col)

func _process(delta: float) -> void :
 _t += delta
 if not done:
  screen_mat.emission_energy_multiplier = 1.5 + 0.6 * sin(_t * 2.4)

func set_busy_name(nick: String) -> void :
 ## кооп: слой держит другой штамм
 if done:
  return
 if nick == "":
  refresh_title()
 else:
  title_label.text = "%s\n⚡ ВЗЛАМЫВАЕТ %s" % [layer["title"], nick]
  title_label.modulate = Color(1.0, 0.85, 0.4)

func refresh_title() -> void :
 if done:
  return
 title_label.modulate = layer["color"]
 var mut_suffix: = ""
 if not layer["mutators"].is_empty():
  mut_suffix = "\n⚠ МУТАЦИЯ"
  title_label.modulate = Color(1.0, 0.5, 0.4)
 title_label.text = "%s\n%s%s" % [layer["title"], GameState.MINIGAMES[layer["game"]]["title"], mut_suffix]

func set_done() -> void :
 done = true
 var green: = Color(0.25, 1.0, 0.55)
 screen_mat.emission = green
 screen_mat.emission_energy_multiplier = 1.2
 light.light_color = green
 light.light_energy = 1.2
 title_label.modulate = green
 title_label.text = "%s\n// ВСКРЫТ И ПУСТ" % layer["title"]
