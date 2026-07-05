extends Node

## Глобальное состояние PANIC PROTOCOL: кампания, узел, добыча, тревога,
## дерево эволюции (ветка + уровни 0..3 + активки за задания), экономика.

signal access_changed(value: float)
signal alarm_changed(value: float)
signal bandwidth_changed(value: float)
signal hp_changed(value: int)
signal evolution_changed

# ── фазы тревоги ────────────────────────────────────────────
const ALARM_SCAN: = 25.0
const ALARM_PURGE: = 55.0
const ALARM_WIPE: = 90.0
const EVAC_TIME: = 75.0        # секунд на эвакуацию после набора квоты
const WIPE_EVAC_TIME: = 45.0   # принудительная эвакуация при тревоге 100

# ── классы: "base" — общий старт, остальные — ветки дерева ──
const CLASSES: = {
	"base": {
		"name": "ПРОТО-ШТАММ", "role": "Болванка без специализации", "color": Color("9ab8c8"),
		"passive": "Все начинают одинаково. Ветку развития выбирают в дереве эволюции [Tab]",
		"active": "—", "cost": 0,
	},
	"trojan": {
		"name": "ТРОЯН", "role": "Мимик / диверсант", "color": Color("35e0ff"),
		"passive": "Мимикрия: активка превращает его в ящик — враги слепы, пока он не двинется",
		"active": "Ложный файл — стать ящиком (до первого движения)", "cost": 20,
	},
	"worm": {
		"name": "ЧЕРВЬ", "role": "Спринтер / курьер", "color": Color("38f0a8"),
		"passive": "Самый быстрый штамм; штраф от груза меньше",
		"active": "Рывок — бросок вперёд (работает даже с грузом)", "cost": 15,
	},
	"ransomware": {
		"name": "RANSOMWARE", "role": "Силач / танк", "color": Color("ff3d6e"),
		"passive": "Тяжёлый лут тащит В ОДИНОЧКУ; +1 HP",
		"active": "Шифрование — заморозка ВСЕХ стражей на 3с", "cost": 35,
	},
	"spyware": {
		"name": "SPYWARE", "role": "Разведчик / глаза", "color": Color("ffb454"),
		"passive": "Полный бриф узла до старта",
		"active": "Скан — лут и стражи видны сквозь стены (6с) всем", "cost": 20,
	},
	"adware": {
		"name": "ADWARE", "role": "Дезинформация", "color": Color("a8d84f"),
		"passive": "Попап-воришки боятся его и бросают украденное",
		"active": "Фантом — приманка уводит стражей (5с)", "cost": 25,
	},
	"rootkit": {
		"name": "ROOTKIT", "role": "Тихоня / сапёр", "color": Color("8b5cff"),
		"passive": "Бесшумный: его бег, прыжки и броски не поднимают тревогу",
		"active": "Глушилка — тревога −12", "cost": 30,
	},
	"botnet": {
		"name": "BOTNET", "role": "Медик роя", "color": Color("4a90ff"),
		"passive": "Bandwidth 150 и двойная регенерация",
		"active": "Дефибрилляция — оживить «бага» рядом (или +1 HP себе)", "cost": 40,
	},
}

const BRANCHES: = ["trojan", "worm", "ransomware", "spyware", "adware", "rootkit", "botnet"]

# ── активные умения (общий пул) ─────────────────────────────
const ABILITIES: = {
	"dash": {"name": "РЫВОК", "desc": "бросок вперёд (работает даже с грузом)", "cost": 15},
	"morph": {"name": "ЛОЖНЫЙ ФАЙЛ", "desc": "стать ящиком — враги слепы, пока не двинешься", "cost": 20},
	"freeze": {"name": "ШИФРОВАНИЕ", "desc": "заморозка всех стражей на 3с", "cost": 35},
	"xray": {"name": "СКАН", "desc": "лут и стражи видны сквозь стены (6с) всем", "cost": 20},
	"decoy": {"name": "ФАНТОМ", "desc": "приманка уводит стражей (5с)", "cost": 25},
	"jam": {"name": "ГЛУШИЛКА", "desc": "тревога −12", "cost": 30},
	"heal": {"name": "ДЕФИБРИЛЛЯЦИЯ", "desc": "оживить бага рядом (или +1 HP себе)", "cost": 40},
}

## первая активка ветки выдаётся на УР.1, остальные открываются заданиями
const BRANCH_ABILITIES: = {
	"trojan": ["morph", "decoy", "xray"],
	"worm": ["dash", "decoy", "jam"],
	"ransomware": ["freeze", "heal", "jam"],
	"spyware": ["xray", "jam", "decoy"],
	"adware": ["decoy", "morph", "freeze"],
	"rootkit": ["jam", "morph", "xray"],
	"botnet": ["heal", "freeze", "dash"],
}

## задания на разблокировку 2-й и 3-й активки (карьерные счётчики)
const ABILITY_TASKS: = {
	1: {"desc": "внеси 6 предметов в портал", "key": "deposits", "need": 6},
	2: {"desc": "выполни 4 полевые задачи", "key": "tasks", "need": 4},
}

# ── уровни развития штамма 0..3 ─────────────────────────────
const LEVELS: = [
	{"title": "УР.0 · ПРОТО", "cost": {},
		"perks": "базовые навыки: бег, прыжок, переноска"},
	{"title": "УР.1 · СПЕЦИАЛИЗАЦИЯ", "cost": {"data_fragments": 60},
		"perks": "скин ветки · пассивка · 1-я активка · +навыки"},
	{"title": "УР.2 · МУТАЦИЯ", "cost": {"data_fragments": 150, "code_samples": 1},
		"perks": "+1 HP · до 2 активок (за задания) · продвинутый скин"},
	{"title": "УР.3 · АПЕКС", "cost": {"data_fragments": 280, "code_samples": 2, "mutagen": 1},
		"perks": "3 активки · доп. ветка · финальный скин · расход BW ×1.5"},
]

const APEX_COST_MULT: = 1.5   # УР.3: навыки мощнее — «мана» дороже

# ── полевые кооп-задачи (вместо мини-игр) ───────────────────
const TASKS: = {
	"sync": {"title": "СИНХРО-ВЗЛОМ", "icon": "⇄",
		"desc": "две консоли: держите [E] у ОБЕИХ одновременно (вдвоём — легко, одному — мучение)"},
	"zone": {"title": "ЗАХВАТ СЕКТОРА", "icon": "◎",
		"desc": "стойте в зоне: чем больше штаммов внутри, тем быстрее захват"},
	"relay": {"title": "ЦЕПЬ РЕЛЕ", "icon": "⚡",
		"desc": "коснитесь реле по порядку, пока цепь не остыла — делите маршрут на команду"},
}

# ── лут: физические предметы ────────────────────────────────
const LOOT_KINDS: = {
	# value: [min,max] · weight: сколько носильщиков нужно · hits: сколько ударов держит
	"file": {"value": [7, 11], "weight": 1, "hits": 2, "size": Vector3(0.55, 0.5, 0.42)},
	"crate": {"value": [16, 24], "weight": 2, "hits": 3, "size": Vector3(1.05, 0.85, 0.9)},
	"epic": {"value": [28, 38], "weight": 2, "hits": 4, "size": Vector3(0.8, 0.7, 0.7)},
}

const LOOT_NAMES_FILE: = [
	"пароли_НЕ_УДАЛЯТЬ.txt", "диплом_ФИНАЛ_2_НОВЫЙ.docx", "фотки_с_корпоратива.zip",
	"seed-фраза_(не_скам).txt", "СЕКРЕТНО_зарплаты.xlsx", "браузерная_история.db",
	"сохранёнки_2007.rar", "переписка_с_бывшей.pdf", "налоговая_НЕ_СМОТРЕТЬ.7z",
	"курсач_скачанный.doc", "рецепт_борща_(легенд.).md",
]
const LOOT_NAMES_CRATE: = [
	"МАЙНИНГ-ФЕРМА (б/у)", "БАЗА КЛИЕНТОВ ЦЕЛИКОМ", "СЕРВЕР (выносить аккуратно)",
	"АРХИВ БУХГАЛТЕРИИ 1998—2026", "НЕЙРОСЕТЬ (недообученная)", "КОРПОРАТИВНАЯ ТАЙНА (тяжёлая)",
]
const LOOT_NAMES_EPIC: = [
	"ЗОЛОТОЙ БИТКОИН", "ИСХОДНИКИ WINDOWS", "КЛЮЧИ ОТ ВСЕГО.pem", "НУЛЕВОЙ ПАЦИЕНТ.iso",
]

# ── тиры узлов: выше тир — больше стражей и защиты ──────────
const TIERS: = [
	{"name": "Домашний ПК", "short": "T1", "av": "DEFENDER", "color": Color("35e0ff"), "theme": "home",
		"quota": 60, "creep": 0.28, "files": 7, "crates": 2, "tasks": 1, "popups": 1, "hunters": 1, "scanners": 1},
	{"name": "Офисная сеть", "short": "T2", "av": "BEHAVIORAL", "color": Color("ffb454"), "theme": "office",
		"quota": 80, "creep": 0.34, "files": 8, "crates": 3, "tasks": 2, "popups": 1, "hunters": 1, "scanners": 2},
	{"name": "Банк / IoT", "short": "T3", "av": "SANDBOX", "color": Color("ff5d8f"), "theme": "bank",
		"quota": 100, "creep": 0.4, "files": 9, "crates": 3, "tasks": 2, "popups": 2, "hunters": 2, "scanners": 3},
	{"name": "Дата-центр", "short": "T4", "av": "AIR-GAPPED", "color": Color("8b5cff"), "theme": "dc",
		"quota": 115, "creep": 0.46, "files": 10, "crates": 4, "tasks": 3, "popups": 2, "hunters": 2, "scanners": 4},
]

# ── прогрессия игрока (дерево эволюции) ─────────────────────
var branch: = ""              # выбранная ветка ("" = ещё не выбрана)
var secondary_branch: = ""    # доп. ветка (открывается на УР.3)
var virus_level: = 0          # 0..3
var active_abilities: Array = []   # экипированные активки (id)
var career: = {"deposits": 0, "delivered": 0, "tasks": 0, "raids": 0}

var resources: = {"data_fragments": 0, "code_samples": 0, "mutagen": 0, "ghost_tokens": 0}
var grid_nodes: Array = []
var grid_heat: = 0.0
var current_node: Dictionary = {}
var last_result: Dictionary = {}
var campaign_won: = false
var demo_mode: = false
var debug_class: = ""   # автотесты: ветка выдаётся сразу при новой кампании

# ── состояние взлома ────────────────────────────────────────
var node_config: = {}
var access: = 0.0          # % квоты добычи, внесённой в портал
var alarm: = 0.0           # тревога системы 0..100 (не падает сама!)
var max_bandwidth: = 100.0
var bandwidth: = 100.0
var bw_regen: = 4.0
var my_hp: = 3
var my_max_hp: = 3
var my_bug: = false        # 0 HP: ты — пищащий баг
var evac_open: = false
var evac_left: = 0.0
var wipe_forced: = false   # эвакуация объявлена тревогой 100, а не квотой
var stats: = {"delivered": 0, "deposits": 0, "broken": 0, "revives": 0, "caught": 0, "tasks": 0, "fails": 0}

func _ready() -> void:
	randomize()
	_setup_input()

func _process(delta: float) -> void:
	# в коопе Bandwidth регенерирует хост, клиенты получают синк
	if bandwidth < max_bandwidth and (not Net.active or Net.is_server()):
		bandwidth = minf(bandwidth + bw_regen * delta, max_bandwidth)
		bandwidth_changed.emit(bandwidth)
	if grid_heat > 0.0:
		grid_heat = maxf(grid_heat - delta * 1.5, 0.0)

# ── идентичность штамма ─────────────────────────────────────

func display_class() -> String:
	## скин ветки появляется только с УР.1
	return branch if branch != "" and virus_level >= 1 else "base"

func display_secondary() -> String:
	return secondary_branch if virus_level >= 3 else ""

func class_info() -> Dictionary:
	return CLASSES[display_class()]

func has_passive(cls: String) -> bool:
	if virus_level < 1:
		return false
	return branch == cls or (virus_level >= 3 and secondary_branch == cls)

func recon_full() -> bool:
	return has_passive("spyware")

# ── дерево эволюции: ветка и уровни ─────────────────────────

func choose_branch(cls: String) -> bool:
	if branch != "" or not cls in BRANCHES:
		return false
	branch = cls
	evolution_changed.emit()
	Net.sync_identity()
	return true

func choose_secondary(cls: String) -> bool:
	if virus_level < 3 or secondary_branch != "" or cls == branch or not cls in BRANCHES:
		return false
	secondary_branch = cls
	evolution_changed.emit()
	Net.sync_identity()
	return true

func level_cost(lvl: int) -> Dictionary:
	return LEVELS[clampi(lvl, 0, 3)]["cost"]

func can_level_up() -> bool:
	if virus_level >= 3:
		return false
	if branch == "":
		return false # сперва выбери направленность
	var cost: Dictionary = level_cost(virus_level + 1)
	for key in cost:
		if resources.get(key, 0) < cost[key]:
			return false
	return true

func level_up() -> bool:
	if not can_level_up():
		return false
	var cost: Dictionary = level_cost(virus_level + 1)
	for key in cost:
		resources[key] -= cost[key]
	virus_level += 1
	if virus_level == 1:
		# сигнатурная активка ветки выдаётся бесплатно
		var sig: String = BRANCH_ABILITIES[branch][0]
		if not sig in active_abilities:
			active_abilities.append(sig)
	evolution_changed.emit()
	Net.sync_identity()
	return true

# ── активки: слоты, пул, задания ────────────────────────────

func max_ability_slots() -> int:
	return [0, 1, 2, 3][virus_level]

func ability_pool() -> Array:
	## УР.3 с доп. веткой расширяет выбор её умениями
	if branch == "":
		return []
	var pool: Array = BRANCH_ABILITIES[branch].duplicate()
	if display_secondary() != "":
		for id in BRANCH_ABILITIES[secondary_branch]:
			if not id in pool:
				pool.append(id)
	return pool

func ability_task_done(slot: int) -> bool:
	## slot 1 и 2 требуют выполненного задания; slot 0 — сигнатурный
	if slot <= 0:
		return true
	var t: Dictionary = ABILITY_TASKS[slot]
	return career.get(t["key"], 0) >= t["need"]

func ability_task_progress(slot: int) -> String:
	if slot <= 0:
		return ""
	var t: Dictionary = ABILITY_TASKS[slot]
	return "%s (%d/%d)" % [t["desc"], mini(career.get(t["key"], 0), t["need"]), t["need"]]

func can_pick_ability(id: String) -> bool:
	if id in active_abilities or not id in ability_pool():
		return false
	var slot: = active_abilities.size()
	if slot >= max_ability_slots():
		return false
	return ability_task_done(slot)

func pick_ability(id: String) -> bool:
	if not can_pick_ability(id):
		return false
	active_abilities.append(id)
	evolution_changed.emit()
	return true

func ability_cost(id: String) -> float:
	var base: = float(ABILITIES[id]["cost"])
	return base * (APEX_COST_MULT if virus_level >= 3 else 1.0)

# ── базовые навыки растут с уровнем ─────────────────────────

func evo_bonus(id: String) -> float:
	var lvl: = float(virus_level)
	match id:
		"bw": return lvl * 15.0
		"stealth": return lvl * 0.08
		"vitality": return 1.0 if virus_level >= 2 else 0.0
		"speed": return lvl * 0.35
		"cooldown": return lvl * 0.8
	return 0.0

func evolve_stage() -> int:
	## стадия скина = уровень штамма
	return virus_level

# ── кампания и Грид ─────────────────────────────────────────

func new_campaign() -> void:
	branch = ""
	secondary_branch = ""
	virus_level = 0
	active_abilities = []
	if debug_class in BRANCHES:
		# автотесты: сразу УР.1 выбранной ветки
		branch = debug_class
		virus_level = 1
		active_abilities = [BRANCH_ABILITIES[debug_class][0]]
	career = {"deposits": 0, "delivered": 0, "tasks": 0, "raids": 0}
	resources = {"data_fragments": 0, "code_samples": 0, "mutagen": 0, "ghost_tokens": 0}
	grid_heat = 0.0
	campaign_won = false
	last_result = {}
	current_node = {}
	_generate_grid()
	evolution_changed.emit()

func _generate_grid() -> void:
	## линейная цепочка развития: T1 → T1 → T2 → T2 → T3 → T3 → T4 → БОСС
	grid_nodes.clear()
	var chain: = [0, 0, 1, 1, 2, 2, 3]
	var pos: = Vector3.ZERO
	var heading: = 0.0   # цепочка уходит на -Z, змейкой
	var id: = 0
	for tier in chain:
		if id > 0:
			heading = clampf(heading + randf_range(-0.6, 0.6), -0.9, 0.9)
			var step: = 30.0 + 4.0 * float(tier)
			pos = pos + Vector3(sin(heading) * step, 0.0, -cos(heading) * step)
		grid_nodes.append({
			"id": id, "tier": tier, "boss": false, "pos": pos,
			"name": "%s-%02d" % [_tier_prefix(tier), id],
			"av": TIERS[tier]["av"], "infected": false, "failed": false,
			"seed": randi(),
		})
		id += 1
	heading = clampf(heading + randf_range(-0.3, 0.3), -0.9, 0.9)
	pos = pos + Vector3(sin(heading) * 46.0, 0.0, -cos(heading) * 46.0)
	grid_nodes.append({
		"id": id, "tier": 3, "boss": true, "pos": pos,
		"name": "ОРАКУЛ", "av": "HEURISTIC AI", "infected": false, "failed": false,
		"seed": randi(),
	})

func _tier_prefix(tier: int) -> String:
	return ["HOME", "OFFICE", "BANK", "DCENTER"][tier]

func total_nodes() -> int:
	return grid_nodes.size()

func infected_total() -> int:
	var c: = 0
	for node in grid_nodes:
		if node["infected"]:
			c += 1
	return c

func node_unlocked(node: Dictionary) -> bool:
	## строгий порядок: следующий узел открывается после захвата предыдущего
	var idx: int = node["id"]
	if idx == 0:
		return true
	if idx - 1 >= grid_nodes.size():
		return false
	return grid_nodes[idx - 1]["infected"]

func node_lock_reason(node: Dictionary) -> String:
	var idx: int = node["id"]
	if idx <= 0 or idx - 1 >= grid_nodes.size():
		return ""
	return "сначала захватите %s" % grid_nodes[idx - 1]["name"]

func frontier_index() -> int:
	## id первого незаражённого узла — граница освоенной территории
	for node in grid_nodes:
		if not node["infected"]:
			return node["id"]
	return grid_nodes.size()

# ── взлом узла ──────────────────────────────────────────────

func start_hack(node: Dictionary) -> void:
	current_node = node
	access = 0.0
	alarm = grid_heat * 0.3
	max_bandwidth = (150.0 if has_passive("botnet") else 100.0) + evo_bonus("bw")
	bw_regen = (8.0 if has_passive("botnet") else 4.0) + evo_bonus("bw") * 0.08
	bandwidth = max_bandwidth
	my_max_hp = 3 + int(evo_bonus("vitality")) + (1 if has_passive("ransomware") else 0)
	my_hp = my_max_hp
	my_bug = false
	evac_open = false
	evac_left = 0.0
	wipe_forced = false
	stats = {"delivered": 0, "deposits": 0, "broken": 0, "revives": 0, "caught": 0, "tasks": 0, "fails": 0}
	node_config = _build_node_config(node)

func _build_node_config(node: Dictionary) -> Dictionary:
	var tier: int = node["tier"]
	var t: Dictionary = TIERS[tier]
	var quota: int = t["quota"]
	var files: int = t["files"]
	var crates: int = t["crates"]
	var task_count: int = t["tasks"]
	var popups: int = t["popups"]
	var hunters: int = t["hunters"]
	var scanners: int = t["scanners"]
	var creep: float = t["creep"]
	if node["boss"]:
		quota = 150
		files = 11
		crates = 5
		task_count = 3
		popups = 2
		hunters = 3
		scanners = 5
		creep = 0.5
	# генерация задач по сиду узла — у всех пиров одинаково
	var rng: = RandomNumberGenerator.new()
	rng.seed = int(node["seed"])
	var kinds: Array = TASKS.keys()
	var tasks: Array = []
	for i in task_count:
		var kind: String = kinds[rng.randi() % kinds.size()]
		tasks.append({
			"id": i, "type": kind,
			"title": "%s %s-%02d" % [TASKS[kind]["icon"], TASKS[kind]["title"], i + 1],
			"done": false,
		})
	var risk: String = ["НИЗКИЙ", "СРЕДНИЙ", "ВЫСОКИЙ", "КРИТИЧЕСКИЙ"][tier]
	if node["boss"]:
		risk = "ОРАКУЛ"
	return {
		"name": node["name"], "tier": tier, "boss": node["boss"],
		"tier_name": t["name"], "tier_short": t["short"], "theme": t["theme"],
		"antivirus": node["av"], "risk": risk, "seed": int(node["seed"]),
		"quota": quota, "files": files, "crates": crates,
		"tasks": tasks, "popups": popups, "hunters": hunters, "scanners": scanners,
		"creep": creep, "difficulty": tier,
	}

# ── добыча / доступ ─────────────────────────────────────────

func quota() -> float:
	return float(node_config.get("quota", 100))

func deposit_value(value: float) -> void:
	## только хост/соло: лут внесён в портал
	apply_access(value / quota() * 100.0)

func apply_access(amount: float) -> void:
	access = clampf(access + amount, 0.0, 999.0)
	access_changed.emit(access)

# ── тревога (не падает сама!) ───────────────────────────────

func alarm_phase() -> int:
	if alarm >= ALARM_WIPE:
		return 3
	if alarm >= ALARM_PURGE:
		return 2
	if alarm >= ALARM_SCAN:
		return 1
	return 0

func alarm_phase_name() -> String:
	return ["SLEEP", "SCAN", "PURGE", "WIPE"][alarm_phase()]

func add_alarm(amount: float, source: = "misc") -> void:
	## в коопе тревогой владеет хост — клиент шлёт запрос
	if Net.active and not Net.is_server():
		Net.srv_add_alarm.rpc_id(1, amount, source)
		return
	apply_alarm(amount, source, display_class())

func apply_alarm(amount: float, source: String, cls: String) -> void:
	## скидки применяются по классу ИСТОЧНИКА шума
	if amount > 0.0:
		if cls == "rootkit":
			amount *= 0.5
		amount *= 1.0 - evo_bonus("stealth")
	alarm = clampf(alarm + amount, 0.0, 100.0)
	alarm_changed.emit(alarm)

func noise(amount: float) -> void:
	## шумовое событие от локального игрока (бег/прыжок/бросок)
	if has_passive("rootkit"):
		return # пассивка: бесшумный
	add_alarm(amount, "noise")

# ── ресурсы способностей ────────────────────────────────────

func try_spend_bw(cost: float) -> bool:
	if bandwidth < cost:
		return false
	bandwidth -= cost
	bandwidth_changed.emit(bandwidth)
	if Net.active and not Net.is_server():
		Net.srv_spend_bw.rpc_id(1, cost)
	return true

func damage_me() -> void:
	my_hp = maxi(my_hp - 1, 0)
	hp_changed.emit(my_hp)

func revive_me() -> void:
	my_hp = 1
	my_bug = false
	hp_changed.emit(my_hp)

# ── лут-генерация имён ──────────────────────────────────────

func loot_name(kind: String) -> String:
	match kind:
		"file": return LOOT_NAMES_FILE.pick_random()
		"crate": return LOOT_NAMES_CRATE.pick_random()
		"epic": return LOOT_NAMES_EPIC.pick_random()
	return "данные.bin"

# ── итоги ───────────────────────────────────────────────────

func compute_loot(victory: bool) -> Dictionary:
	var tier: int = node_config.get("difficulty", 0)
	var delivered: = float(stats["delivered"])
	var frags: = int(delivered * (1.1 + 0.35 * float(tier)))
	var perfect: bool = victory and stats["broken"] == 0 and stats["caught"] == 0
	var loot: = {
		"data_fragments": maxi(frags, 8),
		"code_samples": stats["tasks"] + (2 if node_config.get("boss", false) and victory else 0),
		"mutagen": (1 if perfect else 0) + (1 if tier >= 2 and victory else 0),
		"ghost_tokens": 3 if perfect else 0,
		"perfect": perfect,
	}
	if not victory:
		loot["data_fragments"] = int(loot["data_fragments"] * 0.4)
		loot["code_samples"] = 0
		loot["mutagen"] = 0
		loot["ghost_tokens"] = 0
	return loot

func finish_hack(victory: bool) -> Dictionary:
	var loot: = compute_loot(victory)
	# карьерные счётчики — топливо заданий на активки
	career["deposits"] += stats["deposits"]
	career["delivered"] += stats["delivered"]
	career["tasks"] += stats["tasks"]
	career["raids"] += 1
	if victory:
		current_node["infected"] = true
		current_node["failed"] = false
		grid_heat = maxf(grid_heat - 10.0, 0.0)
		for key in loot:
			if resources.has(key):
				resources[key] += loot[key]
		if current_node.get("boss", false):
			campaign_won = true
	else:
		current_node["failed"] = true
		grid_heat = minf(grid_heat + 25.0, 100.0)
		resources["data_fragments"] += loot["data_fragments"]
	last_result = {"victory": victory, "loot": loot, "boss": current_node.get("boss", false)}
	evolution_changed.emit()
	return loot

# ── input map ───────────────────────────────────────────────

func _setup_input() -> void:
	_add_action("move_forward", [KEY_W])
	_add_action("move_back", [KEY_S])
	_add_action("move_left", [KEY_A])
	_add_action("move_right", [KEY_D])
	_add_action("sprint", [KEY_SHIFT])
	_add_action("jump", [KEY_SPACE])
	_add_action("interact", [KEY_E])
	_add_action("ability", [KEY_Q])
	_add_action("ability_2", [KEY_X])
	_add_action("ability_3", [KEY_C])
	_add_action("throw", [KEY_F])
	_add_action("evolve", [KEY_TAB])
	_add_action("pause", [KEY_ESCAPE])
	_add_action("emote_1", [KEY_1])
	_add_action("emote_2", [KEY_2])
	_add_action("emote_3", [KEY_3])
	_add_action("emote_4", [KEY_4])
	_add_action("prank", [KEY_G])

func _add_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev: = InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
