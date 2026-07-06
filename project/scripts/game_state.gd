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
		"active": "—", "cost": 0, "attrs": {"str": 4, "dex": 4, "int": 4},
	},
	"trojan": {
		"name": "ТРОЯН", "role": "Мимик / диверсант", "color": Color("35e0ff"),
		"passive": "Мимикрия: активка превращает его в ящик — камеры его не видят, пока он не двинется",
		"active": "Ложный файл — стать ящиком (до первого движения)", "cost": 20,
		"attrs": {"str": 4, "dex": 7, "int": 9},
	},
	"worm": {
		"name": "ЧЕРВЬ", "role": "Спринтер / курьер", "color": Color("38f0a8"),
		"passive": "Самый быстрый штамм; штраф от груза меньше",
		"active": "Рывок — бросок вперёд (работает даже с грузом)", "cost": 15,
		"attrs": {"str": 3, "dex": 10, "int": 5},
	},
	"ransomware": {
		"name": "RANSOMWARE", "role": "Силач / танк", "color": Color("ff3d6e"),
		"passive": "Тяжёлый лут тащит В ОДИНОЧКУ; +1 HP",
		"active": "Шифрование — заморозка всех ловушек и робота на 3с", "cost": 35,
		"attrs": {"str": 10, "dex": 3, "int": 6},
	},
	"spyware": {
		"name": "SPYWARE", "role": "Разведчик / глаза", "color": Color("ffb454"),
		"passive": "Видит радиусы обзора роботов-охранников и полную сводку системы",
		"active": "Скан — лут и угрозы видны сквозь стены (6с) всем", "cost": 20,
		"attrs": {"str": 3, "dex": 6, "int": 10},
	},
	"adware": {
		"name": "ADWARE", "role": "Дезинформация", "color": Color("a8d84f"),
		"passive": "Ловушки иногда ведутся на его фантомный след и промахиваются",
		"active": "Фантом — приманка уводит ловушки (5с)", "cost": 25,
		"attrs": {"str": 4, "dex": 6, "int": 8},
	},
	"rootkit": {
		"name": "ROOTKIT", "role": "Тихоня / сапёр", "color": Color("8b5cff"),
		"passive": "Бесшумный: его бег, прыжки и броски не поднимают тревогу",
		"active": "Глушилка — тревога −12", "cost": 30,
		"attrs": {"str": 5, "dex": 8, "int": 7},
	},
	"botnet": {
		"name": "BOTNET", "role": "Оператор роя / медик", "color": Color("4a90ff"),
		"passive": "Bandwidth 150, двойная регенерация. Настраивает ВСПОМОГАТЕЛЬНЫЙ ВЗЛОМ: взломанные серверы зоны помогают вдвое сильнее",
		"active": "Дефибрилляция — оживить «бага» рядом (или +1 HP себе)", "cost": 40,
		"attrs": {"str": 6, "dex": 4, "int": 9},
	},
}

const BRANCHES: = ["trojan", "worm", "ransomware", "spyware", "adware", "rootkit", "botnet"]

# ── активные умения (общий пул) ─────────────────────────────
const ABILITIES: = {
	"dash": {"name": "РЫВОК", "desc": "бросок вперёд (работает даже с грузом)", "cost": 15},
	"morph": {"name": "ЛОЖНЫЙ ФАЙЛ", "desc": "стать ящиком — роботы слепы, пока не двинешься", "cost": 20},
	"freeze": {"name": "ШИФРОВАНИЕ", "desc": "заморозка системы, ловушек и роботов на 3с", "cost": 35},
	"xray": {"name": "СКАН", "desc": "лут и угрозы видны сквозь стены (6с) всем", "cost": 20},
	"decoy": {"name": "ФАНТОМ", "desc": "приманка уводит ловушки (5с)", "cost": 25},
	"jam": {"name": "ГЛУШИЛКА", "desc": "тревога −12", "cost": 30},
	"heal": {"name": "ДЕФИБРИЛЛЯЦИЯ", "desc": "оживить бага рядом (или +1 HP себе)", "cost": 40},
	"haste": {"name": "СВЕРХТАКТ", "desc": "разгон себя +45% скорости на 5с", "cost": 20},
	"emp": {"name": "ЭМИ-РАЗРЯД", "desc": "оглушить ближайшего робота на 4с", "cost": 25},
	"cloak": {"name": "СТЕЛС-ПАКЕТ", "desc": "невидим для роботов 4с (движение не выдаёт)", "cost": 30},
	"purge": {"name": "ЧИСТКА", "desc": "сжечь ВСЕ летящие ловушки системы", "cost": 30},
}

## ветка = 5 умений: сигнатурное на УР.1, дальше — по карьерным заданиям.
## полный набор открывается примерно к началу зоны T3
const BRANCH_ABILITIES: = {
	"trojan": ["morph", "cloak", "decoy", "xray", "purge"],
	"worm": ["dash", "haste", "decoy", "jam", "purge"],
	"ransomware": ["freeze", "emp", "heal", "jam", "haste"],
	"spyware": ["xray", "jam", "cloak", "decoy", "emp"],
	"adware": ["decoy", "morph", "freeze", "haste", "purge"],
	"rootkit": ["jam", "cloak", "morph", "xray", "emp"],
	"botnet": ["heal", "purge", "freeze", "dash", "emp"],
}

## разблокировка умений по ГЛУБИНЕ в ветке (карьерные счётчики).
## глубина 0 — сигнатурное, даётся с УР.1
const ABILITY_TASKS: = {
	1: {"desc": "внеси 6 предметов в портал", "key": "deposits", "need": 6},
	2: {"desc": "выполни 4 полевые задачи", "key": "tasks", "need": 4},
	3: {"desc": "переживи 8 рейдов", "key": "raids", "need": 8},
	4: {"desc": "вынеси добычи на ◈350 суммарно", "key": "delivered", "need": 350},
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

# ── полевые кооп-задачи (интерактив в мире) ─────────────────
const TASKS: = {
	"sync": {"title": "ДВОЙНОЙ РУБИЛЬНИК", "icon": "⇄",
		"desc": "два рычага: держите [E] на ОБОИХ одновременно (вдвоём — легко, одному — мучение)"},
	"zone": {"title": "УСТАНОВКА МОДУЛЕЙ", "icon": "◎",
		"desc": "стойте в зоне монтажа: чем больше штаммов, тем быстрее вставляются модули взлома"},
	"relay": {"title": "ПРОТЯЖКА КАБЕЛЯ", "icon": "⚡",
		"desc": "дотяните кабель по опорам по порядку, пока линия не остыла — делите маршрут"},
}

# ── ловушки системы (вылетают из стен) ──────────────────────
const TRAPS: = {
	"laser": {"name": "ТОЧЕЧНЫЙ ЛАЗЕР", "tier": 0, "speed": 8.5, "life": 12.0, "color": Color(1.0, 0.25, 0.3)},
	"cage": {"name": "КЛЕТКА", "tier": 1, "speed": 6.0, "life": 10.0, "color": Color(0.5, 0.75, 1.0)},
	"reset": {"name": "СБРОС ДО НУЛЯ", "tier": 1, "speed": 6.5, "life": 10.0, "color": Color(0.7, 0.7, 0.75)},
	"pull": {"name": "ПРИТЯЖЕНИЕ", "tier": 1, "speed": 7.0, "life": 10.0, "color": Color(0.9, 0.5, 1.0)},
	"mark": {"name": "МЕТКА", "tier": 2, "speed": 7.0, "life": 10.0, "color": Color(1.0, 0.85, 0.3)},
	"reflash": {"name": "ПАТРОН С ПЕРЕПРОШИВКОЙ", "tier": 3, "speed": 5.5, "life": 14.0, "color": Color(0.3, 1.0, 0.6)},
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

# ── тиры узлов: выше тир — чувствительнее СИСТЕМА ───────────
## T0 — обучающий: тревога ползёт еле-еле, ловушек почти нет
const TIERS: = [
	{"name": "Незащищённые ПК", "short": "T0", "av": "WATCHDOG-LITE", "color": Color("35e0ff"), "theme": "home",
		"quota": 40, "creep": 0.06, "files": 6, "crates": 1, "tasks": 1,
		"sensitivity": 1, "trap_interval": 18.0, "cam_range": 10.0, "traps": ["laser"]},
	{"name": "Защищённые ПК и лавки", "short": "T1", "av": "BEHAVIORAL", "color": Color("ffb454"), "theme": "office",
		"quota": 70, "creep": 0.22, "files": 8, "crates": 2, "tasks": 2,
		"sensitivity": 2, "trap_interval": 12.0, "cam_range": 13.0, "traps": ["laser", "cage", "reset", "pull"]},
	{"name": "Дата-центры", "short": "T2", "av": "SANDBOX", "color": Color("ff5d8f"), "theme": "dc",
		"quota": 95, "creep": 0.3, "files": 9, "crates": 3, "tasks": 2,
		"sensitivity": 3, "trap_interval": 9.0, "cam_range": 15.0, "traps": ["laser", "cage", "reset", "pull", "mark"]},
	{"name": "Военные сети", "short": "T3", "av": "AIR-GAPPED", "color": Color("8b5cff"), "theme": "bank",
		"quota": 115, "creep": 0.38, "files": 10, "crates": 4, "tasks": 3,
		"sensitivity": 4, "trap_interval": 7.0, "cam_range": 17.0, "traps": ["laser", "cage", "reset", "pull", "mark", "reflash"]},
]

## серверов на зону Грида: T0 → T3, затем босс ПЕНТАГОН
const ZONES: = [3, 12, 25, 39]

# ── прогрессия игрока (дерево эволюции) ─────────────────────
var branch: = ""              # выбранная ветка ("" = ещё не выбрана)
var secondary_branch: = ""    # доп. ветка (открывается на УР.3)
var virus_level: = 0          # 0..3
var active_abilities: Array = []   # экипированные активки (id)
var career: = {"deposits": 0, "delivered": 0, "tasks": 0, "raids": 0}

var resources: = {"data_fragments": 0, "code_samples": 0, "mutagen": 0, "ghost_tokens": 0}
var grid_nodes: Array = []
var grid_zones: Array = []   # [{tier, z0, z1, half, count}] — комнаты Грида
var reset_until: = 0.0       # ловушка «сброс до нуля»: скин временно базовый
var stolen_abilities: Array = []   # украдено перепрошивкой (вернутся после рейда)
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
	## скин ветки появляется только с УР.1; «сброс до нуля» временно оголяет
	if Time.get_ticks_msec() / 1000.0 < reset_until:
		return "base"
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

func ability_depth(id: String) -> int:
	## глубина умения в ветке (0 = сигнатурное); для доп. ветки — её глубина
	var d: = 99
	for cls in [branch, secondary_branch]:
		if cls == "" or not BRANCH_ABILITIES.has(cls):
			continue
		var idx: int = BRANCH_ABILITIES[cls].find(id)
		if idx >= 0:
			d = mini(d, idx)
	return d

func ability_task_done(depth: int) -> bool:
	## разблокировка по глубине ветки: 0 — свободно, дальше — карьерные задания
	if depth <= 0:
		return true
	if not ABILITY_TASKS.has(depth):
		return false
	var t: Dictionary = ABILITY_TASKS[depth]
	return career.get(t["key"], 0) >= t["need"]

func ability_task_progress(depth: int) -> String:
	if depth <= 0 or not ABILITY_TASKS.has(depth):
		return ""
	var t: Dictionary = ABILITY_TASKS[depth]
	return "%s (%d/%d)" % [t["desc"], mini(career.get(t["key"], 0), t["need"]), t["need"]]

func can_pick_ability(id: String) -> bool:
	if id in active_abilities or not id in ability_pool():
		return false
	if active_abilities.size() >= max_ability_slots():
		return false
	return ability_task_done(ability_depth(id))

func pick_ability(id: String) -> bool:
	if not can_pick_ability(id):
		return false
	active_abilities.append(id)
	evolution_changed.emit()
	return true

func unequip_ability(id: String) -> bool:
	## откат: снять умение со слота (вернуть можно в любой момент бесплатно)
	if not id in active_abilities:
		return false
	active_abilities.erase(id)
	evolution_changed.emit()
	return true

func ability_cost(id: String) -> float:
	var base: = float(ABILITIES[id]["cost"])
	return base * (APEX_COST_MULT if virus_level >= 3 else 1.0)

func steal_ability() -> String:
	## перепрошивка: крадёт умение (глубина 1 — 80%, 2 — 18%, 3 — 2%)
	if active_abilities.is_empty():
		return ""
	var r: = randf()
	var idx: = 0
	if r >= 0.98:
		idx = 2
	elif r >= 0.80:
		idx = 1
	idx = mini(idx, active_abilities.size() - 1)
	var id: String = active_abilities[idx]
	active_abilities.remove_at(idx)
	stolen_abilities.append(id)
	evolution_changed.emit()
	return id

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
	stolen_abilities = []
	reset_until = 0.0
	career = {"deposits": 0, "delivered": 0, "tasks": 0, "raids": 0}
	resources = {"data_fragments": 0, "code_samples": 0, "mutagen": 0, "ghost_tokens": 0}
	grid_heat = 0.0
	campaign_won = false
	last_result = {}
	current_node = {}
	_generate_grid()
	evolution_changed.emit()

func _generate_grid() -> void:
	## Грид — анфилада зон-комнат: T0(3) → T1(12) → T2(25) → T3(39) → ПЕНТАГОН.
	## Проход в следующую зону открывается, когда взломаны ВСЕ серверы текущей.
	grid_nodes.clear()
	grid_zones.clear()
	var id: = 0
	var z_cursor: = 30.0   # вход; зоны уходят в -Z
	for zi in ZONES.size():
		var count: int = ZONES[zi]
		var cols: = int(ceil(sqrt(float(count) * 1.6)))
		var rows: = int(ceil(float(count) / float(cols)))
		var spacing: = 17.0
		var half: = maxf(38.0, float(cols) * spacing * 0.5 + 14.0)
		var length: = float(rows) * spacing + 42.0
		var z0: = z_cursor
		var placed: = 0
		for r in rows:
			for c in cols:
				if placed >= count:
					break
				var x: = (float(c) - float(cols - 1) * 0.5) * spacing + randf_range(-2.0, 2.0)
				var z: = z0 - 26.0 - float(r) * spacing + randf_range(-2.0, 2.0)
				grid_nodes.append({
					"id": id, "zone": zi, "tier": zi, "boss": false,
					"pos": Vector3(x, 0.0, z),
					"name": "%s-%02d" % [_tier_prefix(zi), id],
					"av": TIERS[zi]["av"], "infected": false, "failed": false,
					"seed": randi(),
				})
				placed += 1
				id += 1
		grid_zones.append({"tier": zi, "z0": z0, "z1": z0 - length, "half": half, "count": count})
		z_cursor = z0 - length
	# финальная зона — ПЕНТАГОН
	var bz0: = z_cursor
	grid_nodes.append({
		"id": id, "zone": ZONES.size(), "tier": 3, "boss": true,
		"pos": Vector3(0.0, 0.0, bz0 - 46.0),
		"name": "ПЕНТАГОН", "av": "SENTINEL-X", "infected": false, "failed": false,
		"seed": randi(),
	})
	grid_zones.append({"tier": 3, "z0": bz0, "z1": bz0 - 84.0, "half": 46.0, "count": 1})

func _tier_prefix(tier: int) -> String:
	return ["PC", "SHOP", "DC", "MIL"][tier]

func total_nodes() -> int:
	return grid_nodes.size()

func infected_total() -> int:
	var c: = 0
	for node in grid_nodes:
		if node["infected"]:
			c += 1
	return c

# ── зоны ────────────────────────────────────────────────────

func zone_total(z: int) -> int:
	if z < 0 or z >= grid_zones.size():
		return 0
	return grid_zones[z]["count"]

func zone_infected(z: int) -> int:
	var c: = 0
	for node in grid_nodes:
		if node["zone"] == z and node["infected"]:
			c += 1
	return c

func zone_complete(z: int) -> bool:
	return zone_infected(z) >= zone_total(z)

func zone_open(z: int) -> bool:
	return z == 0 or zone_complete(z - 1)

func frontier_zone() -> int:
	## первая незавершённая зона — дальше территория закрыта
	for z in grid_zones.size():
		if not zone_complete(z):
			return z
	return grid_zones.size() - 1

func node_unlocked(node: Dictionary) -> bool:
	return zone_open(node["zone"])

func node_lock_reason(node: Dictionary) -> String:
	var z: int = node["zone"]
	if z <= 0:
		return ""
	return "взломайте все серверы зоны %d (%d/%d)" % [z - 1, zone_infected(z - 1), zone_total(z - 1)]

# ── вспомогательный взлом (T2+): рой уже взломанных серверов ─

func team_has(cls: String) -> bool:
	if not Net.active:
		return has_passive(cls)
	for id in Net.players:
		if Net.my_class_of(id) == cls:
			return true
	return false

func assist_ratio(node: Dictionary) -> float:
	## каждый взломанный сервер зоны облегчает остальные; BOTNET удваивает
	if node.get("boss", false):
		return 0.0
	if int(node["tier"]) < 2:
		return 0.0
	var per: = 0.03 if team_has("botnet") else 0.015
	return minf(float(zone_infected(node["zone"])) * per, 0.45)

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
	reset_until = 0.0
	stats = {"delivered": 0, "deposits": 0, "broken": 0, "revives": 0, "caught": 0, "tasks": 0, "fails": 0}
	node_config = _build_node_config(node)

func _build_node_config(node: Dictionary) -> Dictionary:
	var tier: int = node["tier"]
	var t: Dictionary = TIERS[tier]
	var quota: int = t["quota"]
	var files: int = t["files"]
	var crates: int = t["crates"]
	var task_count: int = t["tasks"]
	var creep: float = t["creep"]
	var sensitivity: int = t["sensitivity"]
	var trap_interval: float = t["trap_interval"]
	var cam_range: float = t["cam_range"]
	var traps: Array = t["traps"]
	if node["boss"]:
		# ПЕНТАГОН: бой рассчитан примерно на 10 минут
		quota = 260
		files = 16
		crates = 6
		task_count = 3
		creep = 0.3
		sensitivity = 6
		trap_interval = 5.0
		cam_range = 20.0
		traps = TRAPS.keys()
	# вспомогательный взлом: рой взломанных серверов зоны давит на систему
	var assist: = assist_ratio(node)
	quota = int(float(quota) * (1.0 - assist * 0.6))
	trap_interval *= 1.0 + assist
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
	var risk: String = ["ОБУЧЕНИЕ", "НИЗКИЙ", "СРЕДНИЙ", "ВЫСОКИЙ"][tier]
	if node["boss"]:
		risk = "ПЕНТАГОН"
	return {
		"name": node["name"], "tier": tier, "boss": node["boss"],
		"tier_name": t["name"], "tier_short": t["short"], "theme": t["theme"],
		"antivirus": node["av"], "risk": risk, "seed": int(node["seed"]),
		"quota": quota, "files": files, "crates": crates, "tasks": tasks,
		"sensitivity": sensitivity, "trap_interval": trap_interval,
		"cam_range": cam_range, "trap_kinds": traps, "assist": assist,
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
	# украденное перепрошивкой возвращается после рейда
	for id in stolen_abilities:
		if not id in active_abilities and active_abilities.size() < 3:
			active_abilities.append(id)
	stolen_abilities.clear()
	reset_until = 0.0
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
