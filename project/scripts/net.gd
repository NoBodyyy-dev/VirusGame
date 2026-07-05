extends Node

## Сетевое ядро кооператива (ENet, хост-авторитарный).
## Хост владеет: тревогой, лутом (физика), стражами, HP игроков, счётом гонки.

signal players_changed
signal lobby_status(text: String)
signal campaign_started
signal hack_started
signal hack_finished(victory: bool, reason: String)
signal remote_pos(id: int, pos: Vector3, yaw: float, ratio: float)
signal player_hp(id: int, hp: int, bug: bool)
signal player_morph(id: int, on: bool)
signal player_ragdoll(id: int, from: Vector3)
signal loot_table(items: Array)
signal loot_added(item: Dictionary)
signal loot_state(id: int, carriers: Array)
signal loot_tf(batch: Array)
signal loot_damage(id: int, value: float, broken: bool)
signal loot_deposited(id: int, carriers: Array, value: float)
signal cooler_used(left: int)
signal enemy_spawned(id: int, type: String, pos: Vector3)
signal enemies_tf(batch: Array)
signal enemy_fx(id: int, kind: String)
signal task_state(batch: Array)
signal task_done(idx: int, participants: Array)
signal net_toast(text: String, color: Color)
signal peer_left(id: int)
signal emote_shown(id: int, idx: int)
signal prank_applied(from_id: int, target_id: int, kind: String)
signal scores_changed
signal enter_fx(node_id: int)
signal xray_pulse

const PORT: = 24565
const MAX_CLIENTS: = 7   # хост + 7 = кооп на 8 штаммов

## Пати-набор: эмоции [1-4] и подлянки [G]
const EMOTES: = [
	{"text": "ГОУ-ГОУ ▸▸", "color": Color("38f0a8")},
	{"text": "ПОМОГИТЕ! ⚠", "color": Color("ffb454")},
	{"text": "ИЗИ ★", "color": Color("35e0ff")},
	{"text": "ВСЁ ПРОПАЛО ✖", "color": Color("ff3d6e")},
]

const PRANKS: = {
	"glitch": "ПОМЕХИ — экран в глитчах",
	"mirror": "ЗЕРКАЛО — управление наоборот",
	"popup": "СПАМ — реклама на весь экран",
	"shrink": "СЖАТИЕ — штамм стал крошкой",
}
const PRANK_COST: = 20.0
const PRANK_CD: = 12.0

var active: = false              # идёт сетевая сессия
var players: = {}                # id -> {"cls": String, "name": String}
var scores: = {}                 # id -> счёт гонки (владеет хост)
var hp: = {}                     # id -> {"hp": int, "bug": bool}
var hack_t0: = 0.0
var _sync_timer: = 0.0

func _ready() -> void:
	# сеть не должна замирать, когда локальный клиент ставит паузу
	process_mode = Node.PROCESS_MODE_ALWAYS

func _log(msg: String) -> void:
	## диагностика автотестов — молчит вне демо-режима
	if GameState.demo_mode:
		print("[NET %d] %s" % [my_id(), msg])

func is_server() -> bool:
	return not active or multiplayer.is_server()

func my_id() -> int:
	return multiplayer.get_unique_id() if active else 1

func my_name() -> String:
	return player_name(my_id())

func player_name(id: int) -> String:
	if not active and id == 1:
		return "ТЫ"
	return players.get(id, {}).get("name", "ШТАММ-%d" % id)

func player_color(id: int) -> Color:
	return GameState.CLASSES.get(my_class_of(id), {}).get("color", Color.WHITE)

func my_class_of(id: int) -> String:
	## отображаемый класс: "base", пока не взят УР.1 ветки
	if not active and id == 1:
		return GameState.display_class()
	return players.get(id, {}).get("cls", "base")

func my_level_of(id: int) -> int:
	if not active and id == 1:
		return GameState.virus_level
	return players.get(id, {}).get("lvl", 0)

func my_second_of(id: int) -> String:
	if not active and id == 1:
		return GameState.display_secondary()
	return players.get(id, {}).get("cls2", "")

# ── лобби ───────────────────────────────────────────────────

func host_game(nick: String) -> bool:
	var peer: = ENetMultiplayerPeer.new()
	if peer.create_server(PORT, MAX_CLIENTS) != OK:
		lobby_status.emit("не удалось открыть порт %d" % PORT)
		return false
	multiplayer.multiplayer_peer = peer
	active = true
	players = {1: {"cls": "base", "name": nick if nick != "" else "ХОСТ", "lvl": 0, "cls2": ""}}
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	players_changed.emit()
	lobby_status.emit("лобби открыто · порт %d · ждём штаммы (до 8)…" % PORT)
	return true

func join_game(ip: String, nick: String) -> bool:
	var peer: = ENetMultiplayerPeer.new()
	if peer.create_client(ip if ip != "" else "127.0.0.1", PORT) != OK:
		lobby_status.emit("не удалось подключиться")
		return false
	multiplayer.multiplayer_peer = peer
	active = true
	players = {}
	multiplayer.connected_to_server.connect(func() -> void:
		srv_register.rpc_id(1, nick)
		lobby_status.emit("подключено · ждём старта от хоста"))
	multiplayer.connection_failed.connect(func() -> void:
		leave()
		lobby_status.emit("сервер не ответил"))
	multiplayer.server_disconnected.connect(func() -> void:
		leave()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	return true

func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	active = false
	players = {}
	scores = {}
	hp = {}

func sync_identity() -> void:
	## эволюция локального игрока изменилась — раздать скин/уровень всем
	if not active:
		return
	var cls: = GameState.display_class()
	var lvl: = GameState.virus_level
	var cls2: = GameState.display_secondary()
	if multiplayer.is_server():
		players[1]["cls"] = cls
		players[1]["lvl"] = lvl
		players[1]["cls2"] = cls2
		_broadcast_players()
	else:
		srv_identity.rpc_id(1, cls, lvl, cls2)

@rpc("any_peer", "call_remote", "reliable")
func srv_identity(cls: String, lvl: int, cls2: String) -> void:
	if not multiplayer.is_server():
		return
	var id: = multiplayer.get_remote_sender_id()
	if not players.has(id):
		return
	players[id]["cls"] = cls
	players[id]["lvl"] = lvl
	players[id]["cls2"] = cls2
	_broadcast_players()

func _on_peer_connected(_id: int) -> void:
	pass # ждём srv_register

func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	scores.erase(id)
	hp.erase(id)
	_broadcast_players()
	peer_left.emit(id)

@rpc("any_peer", "call_remote", "reliable")
func srv_register(nick: String) -> void:
	if not multiplayer.is_server():
		return
	var id: = multiplayer.get_remote_sender_id()
	var name_taken: = false
	for pid in players:
		if pid != id and players[pid]["name"] == nick:
			name_taken = true
	if nick == "" or name_taken:
		nick = "ШТАММ-%d" % (players.size() + 1)
	players[id] = {"cls": "base", "name": nick, "lvl": 0, "cls2": ""}
	_log("зарегистрирован %d: %s, всего %d" % [id, nick, players.size()])
	_broadcast_players()

func _broadcast_players() -> void:
	players_changed.emit()
	cl_players.rpc(players)

@rpc("authority", "call_remote", "reliable")
func cl_players(p: Dictionary) -> void:
	players = p
	players_changed.emit()

# ── старт кампании и взлома ─────────────────────────────────

func start_campaign() -> void:
	## только хост: раздать сетку Грида всем
	_log("старт кампании, игроков: %d" % players.size())
	GameState.new_campaign()
	cl_campaign.rpc(GameState.grid_nodes)
	campaign_started.emit()
	get_tree().change_scene_to_file("res://scenes/grid_world.tscn")

@rpc("authority", "call_remote", "reliable")
func cl_campaign(nodes: Array) -> void:
	GameState.new_campaign()
	GameState.grid_nodes = nodes
	campaign_started.emit()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/grid_world.tscn")

func start_hack(node: Dictionary) -> void:
	## только хост
	_log("взлом узла %s" % node["name"])
	GameState.start_hack(node)
	_reset_scores()
	_reset_hp()
	hack_t0 = Time.get_ticks_msec() / 1000.0
	cl_hack.rpc(node["id"], GameState.node_config)
	hack_started.emit()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/level.tscn")

func start_hack_with_fx(node: Dictionary) -> void:
	## только хост: анимация «нырка» у всех, затем смена сцены
	cl_enter_fx.rpc(node["id"])
	enter_fx.emit(node["id"])
	await get_tree().create_timer(1.5).timeout
	if active and multiplayer.is_server():
		start_hack(node)

@rpc("authority", "call_remote", "reliable")
func cl_enter_fx(node_id: int) -> void:
	enter_fx.emit(node_id)

@rpc("any_peer", "call_remote", "reliable")
func srv_request_hack(node_id: int) -> void:
	## клиент в Гриде предлагает узел — кто первый добежал, тот и выбрал
	if not multiplayer.is_server():
		return
	for n in GameState.grid_nodes:
		if n["id"] == node_id and not n["infected"] and GameState.node_unlocked(n):
			toast_all("%s выбирает цель: %s" % [player_name(multiplayer.get_remote_sender_id()), n["name"]], Color("35e0ff"))
			start_hack_with_fx(n)
			return

@rpc("authority", "call_remote", "reliable")
func cl_hack(node_id: int, config: Dictionary) -> void:
	for n in GameState.grid_nodes:
		if n["id"] == node_id:
			GameState.start_hack(n)
			break
	GameState.node_config = config
	hack_t0 = Time.get_ticks_msec() / 1000.0
	_log("клиент входит в узел %d" % node_id)
	hack_started.emit()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/level.tscn")

func finish_hack_server(victory: bool, reason: String) -> void:
	## только хост: развязка узла для всех
	cl_finish.rpc(victory, reason)
	_do_finish(victory, reason)

@rpc("authority", "call_remote", "reliable")
func cl_finish(victory: bool, reason: String) -> void:
	_do_finish(victory, reason)

func _do_finish(victory: bool, reason: String) -> void:
	_log("финиш узла: victory=%s (%s)" % [victory, reason])
	hack_finished.emit(victory, reason)

# ── метры (сервер владеет) ──────────────────────────────────

@rpc("any_peer", "call_remote", "reliable")
func srv_add_alarm(amount: float, source: String) -> void:
	if multiplayer.is_server():
		var cls: = my_class_of(multiplayer.get_remote_sender_id())
		GameState.apply_alarm(amount, source, cls)

@rpc("any_peer", "call_remote", "reliable")
func srv_spend_bw(cost: float) -> void:
	if multiplayer.is_server():
		GameState.bandwidth = maxf(GameState.bandwidth - cost, 0.0)

func _process(delta: float) -> void:
	if not active or not multiplayer.is_server():
		return
	_sync_timer -= delta
	if _sync_timer <= 0.0:
		_sync_timer = 0.12
		cl_meters.rpc(GameState.access, GameState.alarm, GameState.bandwidth,
			GameState.evac_open, GameState.evac_left, GameState.wipe_forced)

@rpc("authority", "call_remote", "unreliable_ordered")
func cl_meters(access: float, alarm: float, bw: float, evac_open: bool, evac_left: float, wipe_forced: bool) -> void:
	GameState.access = access
	GameState.alarm = alarm
	GameState.bandwidth = bw
	GameState.evac_open = evac_open
	GameState.evac_left = evac_left
	GameState.wipe_forced = wipe_forced

# ── позиции игроков ─────────────────────────────────────────

func send_pos(pos: Vector3, yaw: float, ratio: float) -> void:
	if not active:
		return
	if multiplayer.is_server():
		cl_pos.rpc(1, pos, yaw, ratio)
		remote_pos.emit(1, pos, yaw, ratio) # для серверной логики стражей
	else:
		srv_pos.rpc_id(1, pos, yaw, ratio)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func srv_pos(pos: Vector3, yaw: float, ratio: float) -> void:
	if multiplayer.is_server():
		var id: = multiplayer.get_remote_sender_id()
		remote_pos.emit(id, pos, yaw, ratio)
		cl_pos.rpc(id, pos, yaw, ratio)

@rpc("authority", "call_remote", "unreliable_ordered")
func cl_pos(id: int, pos: Vector3, yaw: float, ratio: float) -> void:
	if id != my_id():
		remote_pos.emit(id, pos, yaw, ratio)

# ── HP и баги (сервер владеет) ──────────────────────────────

func _reset_hp() -> void:
	hp = {}

func set_hp(id: int, p_hp: int, bug: bool) -> void:
	## только хост
	hp[id] = {"hp": p_hp, "bug": bug}
	cl_hp.rpc(id, p_hp, bug)
	player_hp.emit(id, p_hp, bug)

@rpc("authority", "call_remote", "reliable")
func cl_hp(id: int, p_hp: int, bug: bool) -> void:
	hp[id] = {"hp": p_hp, "bug": bug}
	player_hp.emit(id, p_hp, bug)

func is_bug(id: int) -> bool:
	return hp.get(id, {}).get("bug", false)

func send_ragdoll(id: int, from: Vector3) -> void:
	## только хост: игрока швырнуло
	cl_ragdoll.rpc(id, from)
	player_ragdoll.emit(id, from)

@rpc("authority", "call_remote", "reliable")
func cl_ragdoll(id: int, from: Vector3) -> void:
	player_ragdoll.emit(id, from)

@rpc("any_peer", "call_remote", "reliable")
func srv_revive(target_id: int) -> void:
	## Botnet-дефибрилляция: хост проверяет и оживляет
	if multiplayer.is_server():
		var lvl: = get_tree().current_scene
		if lvl != null and lvl.has_method("server_revive"):
			lvl.server_revive(target_id, multiplayer.get_remote_sender_id())

# ── морф трояна ─────────────────────────────────────────────

func send_morph(on: bool) -> void:
	if not active:
		player_morph.emit(1, on)
		return
	if multiplayer.is_server():
		cl_morph.rpc(1, on)
		player_morph.emit(1, on)
	else:
		srv_morph.rpc_id(1, on)
		player_morph.emit(my_id(), on)

@rpc("any_peer", "call_remote", "reliable")
func srv_morph(on: bool) -> void:
	if multiplayer.is_server():
		var id: = multiplayer.get_remote_sender_id()
		cl_morph.rpc(id, on)
		player_morph.emit(id, on)

@rpc("authority", "call_remote", "reliable")
func cl_morph(id: int, on: bool) -> void:
	if id != my_id():
		player_morph.emit(id, on)

# ── лут (физика на хосте) ───────────────────────────────────

func send_loot_table(items: Array) -> void:
	cl_loot_table.rpc(items)
	loot_table.emit(items)

@rpc("authority", "call_remote", "reliable")
func cl_loot_table(items: Array) -> void:
	loot_table.emit(items)

func send_loot_add(item: Dictionary) -> void:
	cl_loot_add.rpc(item)
	loot_added.emit(item)

@rpc("authority", "call_remote", "reliable")
func cl_loot_add(item: Dictionary) -> void:
	loot_added.emit(item)

@rpc("any_peer", "call_remote", "reliable")
func srv_grab(item_id: int) -> void:
	if multiplayer.is_server():
		var lvl: = get_tree().current_scene
		if lvl != null and lvl.has_method("server_grab"):
			lvl.server_grab(item_id, multiplayer.get_remote_sender_id())

@rpc("any_peer", "call_remote", "reliable")
func srv_release(item_id: int, throw: bool, dir: Vector3) -> void:
	if multiplayer.is_server():
		var lvl: = get_tree().current_scene
		if lvl != null and lvl.has_method("server_release"):
			lvl.server_release(item_id, multiplayer.get_remote_sender_id(), throw, dir)

func send_loot_state(id: int, carriers: Array) -> void:
	cl_loot_state.rpc(id, carriers)
	loot_state.emit(id, carriers)

@rpc("authority", "call_remote", "reliable")
func cl_loot_state(id: int, carriers: Array) -> void:
	loot_state.emit(id, carriers)

func send_loot_tf(batch: Array) -> void:
	cl_loot_tf.rpc(batch)

@rpc("authority", "call_remote", "unreliable_ordered")
func cl_loot_tf(batch: Array) -> void:
	loot_tf.emit(batch)

func send_loot_damage(id: int, value: float, broken: bool) -> void:
	cl_loot_damage.rpc(id, value, broken)

@rpc("authority", "call_remote", "reliable")
func cl_loot_damage(id: int, value: float, broken: bool) -> void:
	loot_damage.emit(id, value, broken)

func send_loot_deposit(id: int, carriers: Array, value: float) -> void:
	cl_loot_deposit.rpc(id, carriers, value)
	loot_deposited.emit(id, carriers, value)

@rpc("authority", "call_remote", "reliable")
func cl_loot_deposit(id: int, carriers: Array, value: float) -> void:
	loot_deposited.emit(id, carriers, value)

# ── кулер (общий на команду) ────────────────────────────────

@rpc("any_peer", "call_remote", "reliable")
func srv_cooler() -> void:
	if multiplayer.is_server():
		var lvl: = get_tree().current_scene
		if lvl != null and lvl.has_method("server_cooler"):
			lvl.server_cooler(multiplayer.get_remote_sender_id())

func send_cooler(left: int) -> void:
	cl_cooler.rpc(left)
	cooler_used.emit(left)

@rpc("authority", "call_remote", "reliable")
func cl_cooler(left: int) -> void:
	cooler_used.emit(left)

# ── регистрация HP клиента у хоста ──────────────────────────

@rpc("any_peer", "call_remote", "reliable")
func srv_hello_hp(maxhp: int) -> void:
	if multiplayer.is_server():
		var lvl: = get_tree().current_scene
		if lvl != null and lvl.has_method("server_hello_hp"):
			lvl.server_hello_hp(multiplayer.get_remote_sender_id(), maxhp)

# ── стражи (сервер симулирует) ──────────────────────────────

func send_enemy_spawn(id: int, type: String, pos: Vector3) -> void:
	cl_enemy_spawn.rpc(id, type, pos)
	enemy_spawned.emit(id, type, pos)

@rpc("authority", "call_remote", "reliable")
func cl_enemy_spawn(id: int, type: String, pos: Vector3) -> void:
	enemy_spawned.emit(id, type, pos)

func send_enemies(batch: Array) -> void:
	cl_enemies.rpc(batch)

@rpc("authority", "call_remote", "unreliable_ordered")
func cl_enemies(batch: Array) -> void:
	enemies_tf.emit(batch)

func send_enemy_fx(id: int, kind: String) -> void:
	cl_enemy_fx.rpc(id, kind)
	enemy_fx.emit(id, kind)

@rpc("authority", "call_remote", "reliable")
func cl_enemy_fx(id: int, kind: String) -> void:
	enemy_fx.emit(id, kind)

@rpc("any_peer", "call_remote", "reliable")
func srv_enemy_effect(kind: String, arg: float, pos: Vector3) -> void:
	# freeze / decoy от активок клиентов
	if multiplayer.is_server():
		var lvl: = get_tree().current_scene
		if lvl != null and lvl.has_method("apply_enemy_effect"):
			lvl.apply_enemy_effect(kind, arg, pos)

# ── шум (питает тревогу и слух Хантера) ─────────────────────

func send_noise(amount: float, pos: Vector3) -> void:
	if not active or multiplayer.is_server():
		var lvl: = get_tree().current_scene
		if lvl != null and lvl.has_method("server_noise"):
			lvl.server_noise(amount, pos, my_id())
	else:
		srv_noise.rpc_id(1, amount, pos)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func srv_noise(amount: float, pos: Vector3) -> void:
	if multiplayer.is_server():
		var lvl: = get_tree().current_scene
		if lvl != null and lvl.has_method("server_noise"):
			lvl.server_noise(amount, pos, multiplayer.get_remote_sender_id())

# ── полевые задачи (хост симулирует прогресс) ───────────────

@rpc("any_peer", "call_local", "reliable")
func srv_task_hold(idx: int, sub: int, on: bool) -> void:
	## игрок держит [E] у консоли задачи
	if multiplayer.is_server():
		var lvl: = get_tree().current_scene
		if lvl != null and lvl.has_method("server_task_hold"):
			lvl.server_task_hold(idx, sub, on, multiplayer.get_remote_sender_id())

func send_task_state(batch: Array) -> void:
	cl_task_state.rpc(batch)
	task_state.emit(batch)

@rpc("authority", "call_remote", "unreliable_ordered")
func cl_task_state(batch: Array) -> void:
	task_state.emit(batch)

func send_task_done(idx: int, participants: Array) -> void:
	cl_task_done.rpc(idx, participants)
	task_done.emit(idx, participants)

@rpc("authority", "call_remote", "reliable")
func cl_task_done(idx: int, participants: Array) -> void:
	var tasks: Array = GameState.node_config.get("tasks", [])
	if idx >= 0 and idx < tasks.size():
		tasks[idx]["done"] = true
	task_done.emit(idx, participants)

# ── рентген Spyware ─────────────────────────────────────────

func send_xray() -> void:
	if active:
		if multiplayer.is_server():
			cl_xray.rpc()
		else:
			srv_xray.rpc_id(1)
	xray_pulse.emit()

@rpc("any_peer", "call_remote", "reliable")
func srv_xray() -> void:
	if multiplayer.is_server():
		cl_xray.rpc()
		xray_pulse.emit()

@rpc("authority", "call_remote", "reliable")
func cl_xray() -> void:
	xray_pulse.emit()

# ── гонка штаммов: счёт (владеет хост) ──────────────────────

func _blank_score() -> Dictionary:
	return {"score": 0, "delivered": 0, "deposits": 0, "tasks": 0,
		"caught": 0, "broken": 0, "revives": 0}

func _reset_scores() -> void:
	scores = {}
	for id in players:
		scores[id] = _blank_score()
	_broadcast_scores()

func score_event(id: int, kind: String, arg: = 0.0) -> void:
	## только хост. kind: deposit / task / revive / caught / broken
	if active and not multiplayer.is_server():
		return
	if not scores.has(id):
		scores[id] = _blank_score()
	var s: Dictionary = scores[id]
	_log("очки: %s → %s (%.0f)" % [player_name(id), kind, arg])
	match kind:
		"deposit":
			s["deposits"] += 1
			s["delivered"] += int(arg)
			s["score"] += int(arg)
		"task":
			s["tasks"] += 1
			s["score"] += 15
		"revive":
			s["revives"] += 1
			s["score"] += 15
		"caught":
			s["caught"] += 1
			s["score"] -= 5
		"broken":
			s["broken"] += 1
			s["score"] -= 8
	_broadcast_scores()

func _broadcast_scores() -> void:
	scores_changed.emit()
	if active and multiplayer.is_server():
		cl_scores.rpc(scores)

@rpc("authority", "call_remote", "reliable")
func cl_scores(s: Dictionary) -> void:
	scores = s
	scores_changed.emit()

# ── эмоции [1-4] ────────────────────────────────────────────

func send_emote(idx: int) -> void:
	if not active:
		emote_shown.emit(1, idx) # соло: покривляться можно и одному
		return
	if multiplayer.is_server():
		cl_emote.rpc(1, idx)
		emote_shown.emit(1, idx)
	else:
		srv_emote.rpc_id(1, idx)
		emote_shown.emit(my_id(), idx) # свою эмоцию видим сразу

@rpc("any_peer", "call_remote", "reliable")
func srv_emote(idx: int) -> void:
	if multiplayer.is_server():
		var id: = multiplayer.get_remote_sender_id()
		cl_emote.rpc(id, idx)
		emote_shown.emit(id, idx)

@rpc("authority", "call_remote", "reliable")
func cl_emote(id: int, idx: int) -> void:
	if id != my_id():
		emote_shown.emit(id, idx)

# ── подлянки [G] ────────────────────────────────────────────

func send_prank() -> void:
	## жертва и вид подлянки — случайные (решает хост)
	if not active or players.size() < 2:
		return
	if multiplayer.is_server():
		_server_prank(1)
	else:
		srv_prank.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func srv_prank() -> void:
	if multiplayer.is_server():
		_server_prank(multiplayer.get_remote_sender_id())

func _server_prank(from_id: int) -> void:
	var pool: = players.keys()
	pool.erase(from_id)
	if pool.is_empty():
		return
	var target: int = pool.pick_random()
	var kind: String = PRANKS.keys().pick_random()
	cl_prank.rpc(from_id, target, kind)
	prank_applied.emit(from_id, target, kind)

@rpc("authority", "call_remote", "reliable")
func cl_prank(from_id: int, target_id: int, kind: String) -> void:
	prank_applied.emit(from_id, target_id, kind)

# ── тосты ───────────────────────────────────────────────────

func toast_all(text: String, color: Color) -> void:
	cl_toast.rpc(text, color)
	net_toast.emit(text, color)

@rpc("authority", "call_remote", "reliable")
func cl_toast(text: String, color: Color) -> void:
	net_toast.emit(text, color)
