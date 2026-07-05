class_name PartyFx
extends Control

## Пати-слой: эмоции [1-4], подлянки [G] и их визуальные эффекты.
## Вешается в HUD-слой сцены; сцена отдаёт колбэк get_actor(id) -> Node3D.

signal toast_request(text: String, color: Color)

const AD_TEXTS: = [
	"▲ ГОРЯЧИЕ ОДИНОКИЕ БОТНЕТЫ В ТВОЕЙ ПОДСЕТИ",
	"ПОЗДРАВЛЯЕМ! ВЫ 1 000 000-Й ПАКЕТ! ЗАБЕРИТЕ ПРИЗ",
	"УВЕЛИЧЬ СВОЙ BANDWIDTH БЕЗ СМС И РЕГИСТРАЦИИ",
	"ВРАЧИ НЕНАВИДЯТ ЭТОТ ВИРУС! УЗНАЙ ПОЧЕМУ",
	"СКАЧАТЬ БОЛЬШЕ ОЗУ — БЕСПЛАТНО",
	"ТВОЙ ПК ЗАРАЖЁН! (да, тобой, поздравляем)",
	"КАЗИНО «ТРИ ФАЕРВОЛА» — ПЕРВЫЙ ВЗЛОМ В ПОДАРОК",
]

var local_player: VirusPlayer
var get_actor: Callable        # func(id: int) -> Node3D (или null)

var _glitch_until: = 0.0
var _prank_cd_until: = 0.0
var _ads: Array = []           # {"node": Control, "speed": float}
var _rng: = RandomNumberGenerator.new()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Net.emote_shown.connect(_on_emote)
	Net.prank_applied.connect(_on_prank)

func _exit_tree() -> void:
	Net.emote_shown.disconnect(_on_emote)
	Net.prank_applied.disconnect(_on_prank)

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _unhandled_input(event: InputEvent) -> void:
	for i in Net.EMOTES.size():
		if event.is_action_pressed("emote_%d" % (i + 1)):
			Net.send_emote(i)
			Sfx.play("ui_click", -6.0, 1.2)
			return
	if event.is_action_pressed("prank"):
		_try_prank()

func _try_prank() -> void:
	if not Net.active or Net.players.size() < 2:
		toast_request.emit("подлянки [G] работают только в коопе", UIKit.DIM)
		return
	if _now() < _prank_cd_until:
		toast_request.emit("подлянка перезаряжается (%.1fс)" % (_prank_cd_until - _now()), UIKit.DIM)
		return
	if not GameState.try_spend_bw(Net.PRANK_COST):
		toast_request.emit("нужно %d Bandwidth на подлянку" % int(Net.PRANK_COST), UIKit.MAGENTA)
		return
	_prank_cd_until = _now() + Net.PRANK_CD
	Net.send_prank()
	Sfx.play("ability", -4.0, 1.3)

# ── эмоции ──────────────────────────────────────────────────

func _on_emote(id: int, idx: int) -> void:
	var e: Dictionary = Net.EMOTES[clampi(idx, 0, Net.EMOTES.size() - 1)]
	var actor: Node3D = null
	if get_actor.is_valid():
		actor = get_actor.call(id)
	if actor != null and actor.has_method("show_emote"):
		actor.show_emote(e["text"], e["color"])

# ── подлянки ────────────────────────────────────────────────

func _on_prank(from_id: int, target_id: int, kind: String) -> void:
	var from_name: = Net.player_name(from_id)
	var kind_name: String = Net.PRANKS.get(kind, kind)
	# сжатие видно всем — жертва уменьшается у каждого на экране
	if kind == "shrink":
		var actor: Node3D = null
		if get_actor.is_valid():
			actor = get_actor.call(target_id)
		if actor != null and actor.has_method("set_shrunk"):
			actor.set_shrunk(5.0)
	if target_id == Net.my_id():
		Sfx.play("trap", -2.0, 1.4)
		toast_request.emit("🃏 %s подкинул тебе подлянку: %s" % [from_name, kind_name], Color("ffb454"))
		match kind:
			"glitch":
				_glitch_until = _now() + 4.0
			"mirror":
				if local_player != null:
					local_player.invert_until = _now() + 4.0
			"popup":
				_spawn_ads(5)
			"shrink":
				if local_player != null:
					local_player.set_shrunk(5.0)
	elif from_id == Net.my_id():
		toast_request.emit("🃏 подлянка «%s» улетела в %s" % [kind_name.get_slice(" — ", 0), Net.player_name(target_id)], UIKit.CYAN)
	else:
		toast_request.emit("🃏 %s разыграл %s" % [from_name, Net.player_name(target_id)], UIKit.DIM)

func _spawn_ads(count: int) -> void:
	for i in count:
		var panel: = PanelContainer.new()
		panel.add_theme_stylebox_override("panel",
			UIKit.panel_box(Color("a8d84f"), Color(0.05, 0.07, 0.02, 0.94), 2, 4, 12))
		var v: = VBoxContainer.new()
		panel.add_child(v)
		v.add_child(UIKit.label(AD_TEXTS.pick_random(), 17, Color("d8f07a")))
		v.add_child(UIKit.label("реклама · закроется сама (или нет)", 11, UIKit.DIM))
		panel.position = Vector2(1650.0 + _rng.randf() * 500.0, _rng.randf_range(80.0, 760.0))
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(panel)
		_ads.append({"node": panel, "speed": _rng.randf_range(180.0, 320.0)})

func _process(delta: float) -> void:
	for ad in _ads.duplicate():
		var n: Control = ad["node"]
		n.position.x -= ad["speed"] * delta
		if n.position.x < -700.0:
			n.queue_free()
			_ads.erase(ad)
	if _now() < _glitch_until or not _ads.is_empty():
		queue_redraw()
	elif _was_glitching:
		_was_glitching = false
		queue_redraw()
	if _now() < _glitch_until:
		_was_glitching = true

var _was_glitching: = false

func _draw() -> void:
	if _now() >= _glitch_until:
		return
	# глитч-помехи на весь экран
	_rng.seed = int(_now() * 16.0)
	var vr: = get_viewport_rect().size
	for i in 34:
		var r: = Rect2(_rng.randf() * vr.x, _rng.randf() * vr.y,
			_rng.randf_range(60.0, 480.0), _rng.randf_range(2.0, 10.0))
		draw_rect(r, Color(0.5, 0.85, 1.0, _rng.randf_range(0.05, 0.22)), true)
	for i in 6:
		var r2: = Rect2(_rng.randf() * vr.x, _rng.randf() * vr.y,
			_rng.randf_range(120.0, 380.0), _rng.randf_range(14.0, 44.0))
		draw_rect(r2, Color(1.0, 0.3, 0.5, _rng.randf_range(0.04, 0.1)), true)
	for y in range(0, int(vr.y), 6):
		draw_line(Vector2(0, y), Vector2(vr.x, y), Color(0.0, 0.0, 0.0, 0.1))
