extends Node3D




const HUDScript: = preload("res://scripts/grid_hud.gd")
const EvolutionScript: = preload("res://scripts/evolution_ui.gd")
const FloorGrid: = preload("res://shaders/floor_grid.gdshader")
const HoloShader: = preload("res://shaders/hologram.gdshader")

const TIER_COLORS: = [Color("35e0ff"), Color("ffb454"), Color("ff5d8f"), Color("8b5cff")]
const INFECTED_COLOR: = Color("2fe6b0")
const LOCKED_COLOR: = Color("3a4a55")
const BOSS_COLOR: = Color("ff2d4a")

var player: VirusPlayer
var node_visuals: = {}
var motes: Array = []
var hud: Control
var env: Environment

var prompt_target: Dictionary = {}
var _paused: = false
var pause_panel: Control
var top_layer: CanvasLayer
var _win_shown: = false
var evo_panel: Control
var avatars: = {}
var party: PartyFx

func _ready() -> void :
 if GameState.grid_nodes.is_empty():
  GameState.new_campaign(GameState.selected_class)
 _build_environment()
 _build_ground()
 _build_highways()
 _build_nodes()
 _build_motes()
 _build_particles()
 _spawn_player()
 _build_ui()
 if Net.active:
  _setup_coop()
 Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
 Sfx.ambient(true, 1.15)
 if GameState.campaign_won:
  _show_win()

func _setup_coop() -> void :
 for id in Net.players:
  if id != Net.my_id():
   _spawn_avatar(id)
 Net.remote_pos.connect(_on_remote_pos)
 Net.peer_left.connect(_on_peer_left)
 Net.net_toast.connect(_on_net_toast)

func _spawn_avatar(id: int) -> void :
 var av: = RemoteAvatar.new()
 av.setup(id, Net.my_class_of(id), Net.player_name(id))
 av.position = Vector3(randf_range(-3.0, 3.0), 0.2, 10.0 + randf_range(-2.0, 2.0))
 av.target_pos = av.position
 add_child(av)
 avatars[id] = av

func _on_remote_pos(id: int, pos: Vector3, yaw: float, ratio: float) -> void :
 if id == Net.my_id():
  return
 if not avatars.has(id):
  if not Net.players.has(id):
   return
  _spawn_avatar(id)
 avatars[id].net_update(pos, yaw, ratio)

func _on_peer_left(id: int) -> void :
 if avatars.has(id):
  hud.flash_pickup("%s отключился" % Net.player_name(id))
  avatars[id].queue_free()
  avatars.erase(id)

func _on_net_toast(text: String, _color: Color) -> void :
 hud.flash_pickup(text)

func _actor_for(id: int) -> Node3D:
 if id == Net.my_id():
  return player
 return avatars.get(id)



func _build_environment() -> void :
 env = Environment.new()
 env.background_mode = Environment.BG_COLOR
 env.background_color = Color(0.006, 0.011, 0.024)
 env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 env.ambient_light_color = Color(0.06, 0.1, 0.16)
 env.ambient_light_energy = 1.2
 env.tonemap_mode = Environment.TONE_MAPPER_ACES
 env.glow_enabled = true
 env.glow_intensity = 0.95
 env.glow_bloom = 0.15
 env.glow_hdr_threshold = 0.85
 env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
 env.fog_enabled = true
 env.fog_light_color = Color(0.03, 0.08, 0.13)
 env.fog_density = 0.006
 env.fog_sky_affect = 0.0
 env.volumetric_fog_enabled = true
 env.volumetric_fog_density = 0.014
 env.volumetric_fog_albedo = Color(0.3, 0.6, 0.8)
 env.volumetric_fog_emission = Color(0.008, 0.025, 0.045)
 env.volumetric_fog_emission_energy = 0.3
 var we: = WorldEnvironment.new()
 we.environment = env
 add_child(we)

 var sun: = DirectionalLight3D.new()
 sun.rotation_degrees = Vector3(-58, 40, 0)
 sun.light_color = Color(0.45, 0.62, 0.85)
 sun.light_energy = 0.2
 add_child(sun)

func _neon(c: Color, e: = 1.8) -> StandardMaterial3D:
 var m: = StandardMaterial3D.new()
 m.albedo_color = Color(0.02, 0.03, 0.05)
 m.emission_enabled = true
 m.emission = c
 m.emission_energy_multiplier = e
 return m

func _build_ground() -> void :
 var floor_mesh: = MeshInstance3D.new()
 var plane: = PlaneMesh.new()
 plane.size = Vector2(320, 320)
 floor_mesh.mesh = plane
 var fmat: = ShaderMaterial.new()
 fmat.shader = FloorGrid
 fmat.set_shader_parameter("cell", 4.0)
 fmat.set_shader_parameter("line_col", Vector3(0.06, 0.5, 0.7))
 fmat.set_shader_parameter("energy", 0.85)
 floor_mesh.material_override = fmat
 add_child(floor_mesh)

 var sb: = StaticBody3D.new()
 var cs: = CollisionShape3D.new()
 var box: = BoxShape3D.new()
 box.size = Vector3(320, 0.4, 320)
 cs.shape = box
 cs.position.y = -0.2
 sb.add_child(cs)
 add_child(sb)


 for i in 46:
  var ang: = randf() * TAU
  var dist: = randf_range(60.0, 150.0)
  var p: = Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
  var h: = randf_range(6.0, 26.0)
  var tower: = MeshInstance3D.new()
  var bm: = BoxMesh.new()
  bm.size = Vector3(randf_range(2.5, 6.0), h, randf_range(2.5, 6.0))
  tower.mesh = bm
  var mat: = StandardMaterial3D.new()
  mat.albedo_color = Color(0.03, 0.045, 0.07)
  mat.metallic = 0.5
  mat.roughness = 0.4
  tower.mesh.surface_get_material(0)
  tower.material_override = mat
  tower.position = p + Vector3(0, h * 0.5, 0)
  add_child(tower)
  var c: Color = TIER_COLORS.pick_random()
  var strip: = MeshInstance3D.new()
  var sm: = BoxMesh.new()
  sm.size = Vector3(bm.size.x * 1.02, 0.12, 0.12)
  strip.mesh = sm
  strip.material_override = _neon(c, 1.4)
  strip.position = p + Vector3(0, randf_range(2.0, h), bm.size.z * 0.5)
  add_child(strip)

func _build_particles() -> void :
 # взвесь данных над Гридом — «живая» сеть
 var parts: = GPUParticles3D.new()
 parts.amount = 320
 parts.lifetime = 12.0
 parts.preprocess = 6.0
 var pm: = ParticleProcessMaterial.new()
 pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
 pm.emission_box_extents = Vector3(110, 5.0, 110)
 pm.direction = Vector3(0, 1, 0)
 pm.spread = 20.0
 pm.initial_velocity_min = 0.2
 pm.initial_velocity_max = 0.7
 pm.gravity = Vector3.ZERO
 pm.turbulence_enabled = true
 pm.turbulence_noise_strength = 0.5
 pm.turbulence_noise_scale = 2.5
 parts.process_material = pm
 var quad: = QuadMesh.new()
 quad.size = Vector2(0.07, 0.07)
 var qm: = StandardMaterial3D.new()
 qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
 qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
 qm.albedo_color = Color(0.22, 0.75, 0.95, 0.45)
 quad.material = qm
 parts.draw_pass_1 = quad
 parts.position.y = 4.0
 add_child(parts)

func _build_highways() -> void :

 var origin: = Vector3.ZERO
 for node in GameState.grid_nodes:
  var to: Vector3 = node["pos"]
  if to.length() < 1.0:
   continue
  var mid: = (origin + to) * 0.5
  var length: = origin.distance_to(to)
  var strip: = MeshInstance3D.new()
  var bm: = BoxMesh.new()
  bm.size = Vector3(0.6, 0.05, length)
  strip.mesh = bm
  var col: Color = INFECTED_COLOR if node["infected"] else Color(0.08, 0.35, 0.5)
  strip.material_override = _neon(col, 1.2 if node["infected"] else 0.6)
  strip.position = mid + Vector3(0, 0.06, 0)
  strip.look_at_from_position(strip.position, to + Vector3(0, 0.06, 0), Vector3.UP)
  add_child(strip)



func _build_nodes() -> void :
 for node in GameState.grid_nodes:
  _build_node(node)

func _build_node(node: Dictionary) -> void :
 var root: = Node3D.new()
 root.position = node["pos"]
 add_child(root)

 var unlocked: bool = GameState.node_unlocked(node)
 var infected: bool = node["infected"]
 var boss: bool = node["boss"]
 var tier_color: Color = BOSS_COLOR if boss else TIER_COLORS[node["tier"]]
 var color: Color = tier_color
 if infected:
  color = INFECTED_COLOR
 elif not unlocked:
  color = LOCKED_COLOR


 var plat: = MeshInstance3D.new()
 var cyl: = CylinderMesh.new()
 cyl.top_radius = 4.2
 cyl.bottom_radius = 4.6
 cyl.height = 0.5
 plat.mesh = cyl
 var pm: = StandardMaterial3D.new()
 pm.albedo_color = Color(0.04, 0.06, 0.09)
 pm.metallic = 0.5
 pm.roughness = 0.35
 plat.material_override = pm
 plat.position.y = 0.25
 root.add_child(plat)
 var plat_ring: = MeshInstance3D.new()
 var tor: = TorusMesh.new()
 tor.inner_radius = 4.0
 tor.outer_radius = 4.35
 plat_ring.mesh = tor
 plat_ring.material_override = _neon(color, 1.6)
 plat_ring.position.y = 0.52
 root.add_child(plat_ring)


 var h: = 3.0 + float(node["tier"]) * 1.4 + (3.0 if boss else 0.0)
 var tower: = MeshInstance3D.new()
 var bm: = BoxMesh.new()
 bm.size = Vector3(2.2, h, 2.2)
 tower.mesh = bm
 var tm: = StandardMaterial3D.new()
 tm.albedo_color = Color(0.03, 0.045, 0.07)
 tm.metallic = 0.6
 tm.roughness = 0.3
 tower.material_override = tm
 tower.position.y = 0.5 + h * 0.5
 root.add_child(tower)

 var core: = MeshInstance3D.new()
 var sm: = SphereMesh.new()
 sm.radius = 0.7 if not boss else 1.1
 sm.height = sm.radius * 2.0
 core.mesh = sm
 core.material_override = _neon(color, 3.0)
 core.position.y = 0.5 + h + 0.4
 root.add_child(core)

 for s in 4:
  var strip: = MeshInstance3D.new()
  var stm: = BoxMesh.new()
  stm.size = Vector3(0.12, h * 0.85, 0.12)
  strip.mesh = stm
  strip.material_override = _neon(color, 1.3)
  var off: = 1.12
  strip.position = Vector3([off, - off, off, - off][s], 0.5 + h * 0.5, [off, off, - off, - off][s])
  root.add_child(strip)

 var light: = OmniLight3D.new()
 light.light_color = color
 light.light_energy = 2.4 if not ( not unlocked and not infected) else 0.6
 light.omni_range = 12.0
 light.position.y = 0.5 + h
 root.add_child(light)


 var label: = Label3D.new()
 label.font_size = 64 if boss else 48
 label.modulate = color
 label.outline_size = 10
 label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
 label.position.y = 0.5 + h + 1.8
 label.no_depth_test = true
 root.add_child(label)


 var sb: = StaticBody3D.new()
 sb.collision_layer = 1
 var cs: = CollisionShape3D.new()
 var cbox: = BoxShape3D.new()
 cbox.size = Vector3(2.2, h, 2.2)
 cs.shape = cbox
 cs.position.y = 0.5 + h * 0.5
 sb.add_child(cs)
 root.add_child(sb)

 node_visuals[node["id"]] = {
  "root": root, "ring_mat": plat_ring.material_override, "core_mat": core.material_override, 
  "light": light, "label": label, "core": core, "tier_color": tier_color, 
 }
 _refresh_node_label(node)

func _refresh_node_label(node: Dictionary) -> void :
 var vis: Dictionary = node_visuals[node["id"]]
 var label: Label3D = vis["label"]
 var boss: bool = node["boss"]
 var tier_name: String = "БОСС · ОРАКУЛ" if boss else GameState.TIERS[node["tier"]]["name"]
 var status: = ""
 if node["infected"]:
  status = "✓ ЗАРАЖЁН"
 elif not GameState.node_unlocked(node):
  status = "🔒 " + GameState.node_lock_reason(node)
 elif node["failed"]:
  status = "⚠ ПОВТОР"
 else:
  status = "[E] ВЗЛОМ · %s" % node["av"]
 label.text = "%s\n%s\n%s" % [node["name"], tier_name, status]



func _build_motes() -> void :
 for i in 24:
  var ang: = randf() * TAU
  var dist: = randf_range(12.0, 72.0)
  var pos: = Vector3(cos(ang) * dist, 1.2, sin(ang) * dist)
  var m: = MeshInstance3D.new()
  var sm: = SphereMesh.new()
  sm.radius = 0.32
  sm.height = 0.64
  m.mesh = sm
  var sh: = ShaderMaterial.new()
  sh.shader = HoloShader
  sh.set_shader_parameter("col", Vector3(0.16, 0.95, 0.75))
  m.material_override = sh
  m.position = pos
  add_child(m)
  motes.append({"node": m, "pos": pos, "phase": randf() * TAU})



func _spawn_player() -> void :
 player = VirusPlayer.new()
 var spawn: = Vector3(0, 0.2, 10)
 if not GameState.current_node.is_empty():
  spawn = GameState.current_node["pos"] + Vector3(0, 0.2, 7)
 player.position = spawn
 add_child(player)

func _build_ui() -> void :
 var hud_layer: = CanvasLayer.new()
 hud_layer.layer = 1
 add_child(hud_layer)
 hud = HUDScript.new()
 hud_layer.add_child(hud)

 party = PartyFx.new()
 party.local_player = player
 party.get_actor = _actor_for
 party.toast_request.connect(_on_net_toast)
 hud_layer.add_child(party)

 top_layer = CanvasLayer.new()
 top_layer.layer = 10
 top_layer.process_mode = Node.PROCESS_MODE_ALWAYS
 add_child(top_layer)
 pause_panel = _build_pause_panel()
 pause_panel.visible = false
 top_layer.add_child(pause_panel)

func _build_pause_panel() -> Control:
 var root: = Control.new()
 root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var dim: = ColorRect.new()
 dim.color = Color(0, 0.005, 0.015, 0.75)
 root.add_child(UIKit.full_rect(dim))
 var center: = CenterContainer.new()
 root.add_child(UIKit.full_rect(center))
 var panel: = PanelContainer.new()
 panel.custom_minimum_size = Vector2(440, 240)
 panel.add_theme_stylebox_override("panel", UIKit.panel_box(UIKit.CYAN, Color(0.008, 0.02, 0.036, 0.97), 1, 8, 24))
 center.add_child(panel)
 var v: = VBoxContainer.new()
 v.add_theme_constant_override("separation", 14)
 panel.add_child(v)
 v.add_child(UIKit.label("ГРИД // пауза", 24, UIKit.CYAN))
 var resume: = UIKit.button("  ПРОДОЛЖИТЬ  ", 19, UIKit.TEAL)
 resume.pressed.connect(_toggle_pause)
 v.add_child(resume)
 var menu: = UIKit.button("  ВЫЙТИ В МЕНЮ  ", 19, UIKit.MAGENTA)
 menu.pressed.connect( func() -> void :
  Net.leave()
  get_tree().paused = false
  get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
 v.add_child(menu)
 return root



var _demo_grid_timer: = 0.0

func _process(delta: float) -> void :
 var t: = Time.get_ticks_msec() / 1000.0

 # демо-бот: сам ныряет в первый доступный узел (и в коопе — хостом)
 if GameState.demo_mode and not _win_shown:
  _demo_grid_timer += delta
  if _demo_grid_timer > 4.0 and (not Net.active or Net.is_server()):
   _demo_grid_timer = -INF
   for node in GameState.grid_nodes:
    if not node["infected"] and GameState.node_unlocked(node):
     if Net.active:
      Net.start_hack(node)
     else:
      GameState.start_hack(node)
      get_tree().change_scene_to_file("res://scenes/level.tscn")
     return

 for id in node_visuals:
  var vis: Dictionary = node_visuals[id]
  vis["core"].position.y += sin(t * 1.5 + float(id)) * 0.003
  vis["core"].rotate_y(delta * 0.6)

 for mote in motes:
  if mote["node"] == null:
   continue
  var m: MeshInstance3D = mote["node"]
  m.position.y = mote["pos"].y + sin(t * 2.0 + mote["phase"]) * 0.25
  m.rotate_y(delta * 1.5)
  if player.global_position.distance_to(m.global_position) < 1.8:
   GameState.resources["data_fragments"] += 3
   hud.flash_pickup("+3 Data Fragments")
   Sfx.play("pickup")
   m.queue_free()
   mote["node"] = null

 _update_prompt()
 if _win_shown:
  return
 hud.refresh()

func _update_prompt() -> void :
 prompt_target = {}
 var best: = 6.0
 for node in GameState.grid_nodes:
  if node["infected"]:
   continue
  var d: = player.global_position.distance_to(node["pos"])
  if d < best:
   best = d
   prompt_target = node
 if prompt_target.is_empty():
  hud.set_prompt("")
  return
 if not GameState.node_unlocked(prompt_target):
  hud.set_prompt("🔒 %s — %s" % [prompt_target["name"], GameState.node_lock_reason(prompt_target)])
 else:
  var verb: = "ШТУРМ БОССА" if prompt_target["boss"] else "ВЗЛОМ УЗЛА"
  hud.set_prompt("[E] %s: %s (%s · антивирус %s)" % [verb, prompt_target["name"], GameState.TIERS[prompt_target["tier"]]["short"], prompt_target["av"]])

func _unhandled_input(event: InputEvent) -> void :
 if _win_shown:
  return
 if event.is_action_pressed("pause"):
  _toggle_pause()
 elif event.is_action_pressed("evolve") and not _paused and evo_panel == null:
  _open_evolution()
 elif event.is_action_pressed("interact") and not _paused:
  if not prompt_target.is_empty() and GameState.node_unlocked(prompt_target) and not prompt_target["infected"]:
   if Net.active:
    # кто первый добежал до узла — тот и выбрал цель рейда
    if Net.is_server():
     Net.start_hack(prompt_target)
    else:
     Net.srv_request_hack.rpc_id(1, prompt_target["id"])
     hud.set_prompt("цель предложена — врываемся…")
   else:
    GameState.start_hack(prompt_target)
    get_tree().change_scene_to_file("res://scenes/level.tscn")

func _open_evolution() -> void :
 evo_panel = EvolutionScript.new()
 top_layer.add_child(evo_panel)
 if Net.active:
  player.control_enabled = false # в коопе Грид не замирает
 else:
  get_tree().paused = true
 Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
 Sfx.play("ui_click")
 evo_panel.closed.connect(func() -> void :
  get_tree().paused = false
  Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
  evo_panel.queue_free()
  evo_panel = null
  # пересобрать тело: полиморфизм и скорость могли измениться
  var pos: = player.global_position
  var yaw: float = player.yaw_pivot.rotation.y
  player.queue_free()
  player = VirusPlayer.new()
  player.position = pos
  add_child(player)
  player.yaw_pivot.rotation.y = yaw
  party.local_player = player)

func _toggle_pause() -> void :
 _paused = not _paused
 if Net.active:
  player.control_enabled = not _paused
 else:
  get_tree().paused = _paused
 pause_panel.visible = _paused
 Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _paused else Input.MOUSE_MODE_CAPTURED

func _show_win() -> void :
 _win_shown = true
 get_tree().paused = true
 Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
 var root: = Control.new()
 root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var dim: = ColorRect.new()
 dim.color = Color(0.0, 0.01, 0.02, 0.9)
 root.add_child(UIKit.full_rect(dim))
 var center: = CenterContainer.new()
 root.add_child(UIKit.full_rect(center))
 var panel: = PanelContainer.new()
 panel.custom_minimum_size = Vector2(720, 400)
 panel.add_theme_stylebox_override("panel", UIKit.panel_box(INFECTED_COLOR, Color(0.008, 0.03, 0.04, 0.98), 2, 10, 32))
 center.add_child(panel)
 var v: = VBoxContainer.new()
 v.add_theme_constant_override("separation", 12)
 panel.add_child(v)
 v.add_child(UIKit.label("ГРИД ЗАРАЖЁН // ОРАКУЛ ПАЛ", 34, INFECTED_COLOR))
 v.add_child(UIKit.label("Полиморфный штамм захватил сеть. Кампания пройдена.", 18, UIKit.WHITE))
 v.add_child(UIKit.label("Собрано Data Fragments: %d · Code Samples: %d · Mutagen: %d · Ghost Tokens: %d" % [
  GameState.resources["data_fragments"], GameState.resources["code_samples"], 
  GameState.resources["mutagen"], GameState.resources["ghost_tokens"]], 16, UIKit.DIM))
 var btn: = UIKit.button("  НОВАЯ КАМПАНИЯ  ", 20, UIKit.TEAL)
 btn.pressed.connect( func() -> void :
  get_tree().paused = false
  get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
 v.add_child(btn)
 top_layer.add_child(root)
