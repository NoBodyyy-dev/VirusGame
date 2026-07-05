extends Node

## Глобальное состояние PANIC PROTOCOL: кампания, узел, добыча, тревога,
## классы, эволюция, экономика.

signal access_changed(value: float)
signal alarm_changed(value: float)
signal bandwidth_changed(value: float)
signal hp_changed(value: int)

# ── фазы тревоги ────────────────────────────────────────────
const ALARM_SCAN: = 25.0
const ALARM_PURGE: = 55.0
const ALARM_WIPE: = 90.0
const EVAC_TIME: = 75.0        # секунд на эвакуацию после набора квоты
const WIPE_EVAC_TIME: = 45.0   # принудительная эвакуация при тревоге 100

const CLASSES: = {
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
		"passive": "Полный бриф; таймеры сейфов мягче",
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

# ── мини-игры (теперь это замки СЕЙФОВ) ─────────────────────
const MINIGAMES: = {
	"packet_route": {"title": "«Маршрутизация пакета»", "skill": "логика + скорость", "best": "ЧЕРВЬ"},
	"ring_polarity": {"title": "«Полярность колец»", "skill": "реакция", "best": "ТРОЯН / ЧЕРВЬ"},
	"signature_match": {"title": "«Маскировка подписи»", "skill": "сопоставление", "best": "ТРОЯН"},
	"hash_crack": {"title": "«Взлом хэша»", "skill": "скорость", "best": "SPYWARE"},
	"freq_lock": {"title": "«Подбор частоты»", "skill": "точность", "best": "SPYWARE"},
	"sequence_recall": {"title": "«Последовательность портов»", "skill": "память", "best": "универсальный"},
	"cipher_wheel": {"title": "«Шифровальное колесо»", "skill": "логика", "best": "RANSOMWARE / SPYWARE"},
	"overload_hold": {"title": "«Переполнение буфера»", "skill": "удержание", "best": "BOTNET"},
	"logic_gates": {"title": "«Логические вентили»", "skill": "головоломка", "best": "думающий класс"},
	"pulse_sync": {"title": "«Совмещение сигналов»", "skill": "точность", "best": "ADWARE"},
	"log_wipe": {"title": "«Зачистка логов»", "skill": "реакция (whack)", "best": "ROOTKIT"},
}

const MUTATORS: = {
	"mirror": "ЗЕРКАЛО — инвертированное управление",
	"blackout": "ЗАТЕМНЕНИЕ — часть поля скрыта, нужна память",
	"haste": "УСКОРЕНИЕ — жёсткий таймер",
	"noise": "ПОМЕХИ — визуальный шум на экране",
	"moving": "ПОДВИЖНАЯ ЦЕЛЬ — элементы двигаются",
	"silent": "ТИХИЙ РЕЖИМ — нельзя провалить ни разу",
}

const MUTATOR_HINTS: = {
	"mirror": "ЗЕРКАЛО: не торопись — управление наоборот",
	"blackout": "ЗАТЕМНЕНИЕ: Spyware подсвечивает скрытое",
	"haste": "УСКОРЕНИЕ: лучший «медвежатник» команды — к замку",
	"noise": "ПОМЕХИ: Adware вычищает шум с экрана",
	"moving": "ПОДВИЖНАЯ ЦЕЛЬ: Червь читает траектории",
	"silent": "ТИХИЙ РЕЖИМ: один провал — сейф захлопнется. Ставь 0-day",
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

# ── тиры узлов ──────────────────────────────────────────────
const TIERS: = [
	{"name": "Домашний ПК", "short": "T1", "av": "DEFENDER", "color": Color("35e0ff"),
		"quota": 60, "creep": 0.28, "files": 7, "crates": 2, "safes": 1, "popups": 1, "hunters": 1},
	{"name": "Офисная сеть", "short": "T2", "av": "BEHAVIORAL", "color": Color("ffb454"),
		"quota": 80, "creep": 0.34, "files": 8, "crates": 3, "safes": 1, "popups": 1, "hunters": 1},
	{"name": "Банк / IoT", "short": "T3", "av": "SANDBOX", "color": Color("ff5d8f"),
		"quota": 100, "creep": 0.4, "files": 9, "crates": 3, "safes": 2, "popups": 2, "hunters": 2},
	{"name": "Дата-центр", "short": "T4", "av": "AIR-GAPPED", "color": Color("8b5cff"),
		"quota": 115, "creep": 0.46, "files": 10, "crates": 4, "safes": 2, "popups": 2, "hunters": 2},
]

# ── Эволюция ────────────────────────────────────────────────
const EVOLUTION: = {
	"bw": {"name": "Пропускная", "desc": "+25 Bandwidth и +2 регенерация", "max": 3, "base_cost": 60, "res": "data_fragments"},
	"stealth": {"name": "Скрытность", "desc": "−12% к росту Тревоги от твоих действий", "max": 3, "base_cost": 60, "res": "data_fragments"},
	"vitality": {"name": "Живучесть", "desc": "+1 HP на взломе", "max": 2, "base_cost": 90, "res": "data_fragments"},
	"speed": {"name": "Реплика", "desc": "+0.6 к скорости движения", "max": 2, "base_cost": 50, "res": "data_fragments"},
	"cooldown": {"name": "Overclock", "desc": "−1.5с перезарядка активки", "max": 2, "base_cost": 70, "res": "data_fragments"},
}

const MUTATIONS: = {
	"armor": {"name": "Полиморфная броня", "desc": "+1 бесплатный промах в каждом раунде сейфа", "cost": 2},
	"ghost_start": {"name": "Нулевой след", "desc": "Каждый взлом начинается с Тревогой −15", "cost": 2},
	"chain_master": {"name": "Стальной хват", "desc": "Штраф скорости от груза вдвое меньше", "cost": 3},
}

var selected_class: = "worm"
var resources: = {"data_fragments": 0, "code_samples": 0, "mutagen": 0, "ghost_tokens": 0}
var evolution: = {}
var mutations: = {}
var zero_days: = 0
var grid_nodes: Array = []
var grid_heat: = 0.0
var current_node: Dictionary = {}
var last_result: Dictionary = {}
var campaign_won: = false
var demo_mode: = false

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
var stats: = {"delivered": 0, "deposits": 0, "broken": 0, "revives": 0, "caught": 0, "safes": 0, "perfect_safes": 0, "fails": 0, "rounds": 0}

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

func class_info() -> Dictionary:
	return CLASSES[selected_class]

func recon_full() -> bool:
	return selected_class == "spyware"

# ── эволюция ────────────────────────────────────────────────

func evo_level(id: String) -> int:
	return evolution.get(id, 0)

func evo_cost(id: String) -> int:
	return EVOLUTION[id]["base_cost"] * (evo_level(id) + 1)

func evo_can_buy(id: String) -> bool:
	return evo_level(id) < EVOLUTION[id]["max"] and resources["data_fragments"] >= evo_cost(id)

func evo_buy(id: String) -> bool:
	if not evo_can_buy(id):
		return false
	resources["data_fragments"] -= evo_cost(id)
	evolution[id] = evo_level(id) + 1
	return true

func evo_bonus(id: String) -> float:
	var lvl: = float(evo_level(id))
	match id:
		"bw": return lvl * 25.0
		"stealth": return lvl * 0.12
		"vitality": return lvl
		"speed": return lvl * 0.6
		"cooldown": return lvl * 1.5
	return 0.0

func mutation_owned(id: String) -> bool:
	return mutations.get(id, false)

func mutation_can_buy(id: String) -> bool:
	return not mutation_owned(id) and resources["mutagen"] >= MUTATIONS[id]["cost"]

func mutation_buy(id: String) -> bool:
	if not mutation_can_buy(id):
		return false
	resources["mutagen"] -= MUTATIONS[id]["cost"]
	mutations[id] = true
	return true

func can_craft_zero_day() -> bool:
	return resources["code_samples"] >= 2

func craft_zero_day() -> bool:
	if not can_craft_zero_day():
		return false
	resources["code_samples"] -= 2
	zero_days += 1
	return true

func use_zero_day() -> bool:
	if zero_days <= 0:
		return false
	zero_days -= 1
	return true

func evolve_stage() -> int:
	var total: = 0
	for id in evolution:
		total += evolution[id]
	for id in mutations:
		if mutations[id]:
			total += 2
	if total >= 6:
		return 2
	if total >= 2:
		return 1
	return 0

# ── кампания и Грид ─────────────────────────────────────────

func new_campaign(cls: String) -> void:
	selected_class = cls
	resources = {"data_fragments": 0, "code_samples": 0, "mutagen": 0, "ghost_tokens": 0}
	evolution = {}
	mutations = {}
	zero_days = 0
	grid_heat = 0.0
	campaign_won = false
	last_result = {}
	current_node = {}
	_generate_grid()

func _generate_grid() -> void:
	grid_nodes.clear()
	var id: = 0
	var layout: = [
		{"tier": 0, "count": 1, "radius": 0.0},
		{"tier": 1, "count": 3, "radius": 34.0},
		{"tier": 2, "count": 2, "radius": 58.0},
		{"tier": 3, "count": 1, "radius": 80.0},
	]
	for ring in layout:
		var n: int = ring["count"]
		for i in n:
			var ang: = TAU * (float(i) / float(n)) + randf_range(-0.25, 0.25)
			if ring["tier"] == 0:
				ang = 0.0
			var r: float = ring["radius"]
			var pos: = Vector3(cos(ang) * r, 0.0, sin(ang) * r)
			var tier: int = ring["tier"]
			grid_nodes.append({
				"id": id, "tier": tier, "boss": false, "pos": pos,
				"name": "%s-%02d" % [_tier_prefix(tier), id],
				"av": TIERS[tier]["av"], "infected": false, "failed": false,
			})
			id += 1
	grid_nodes.append({
		"id": id, "tier": 3, "boss": true, "pos": Vector3(0.0, 0.0, -108.0),
		"name": "ОРАКУЛ", "av": "HEURISTIC AI", "infected": false, "failed": false,
	})

func _tier_prefix(tier: int) -> String:
	return ["HOME", "OFFICE", "BANK", "DCENTER"][tier]

func infected_count(tier: int) -> int:
	var c: = 0
	for node in grid_nodes:
		if node["tier"] == tier and node["infected"] and not node["boss"]:
			c += 1
	return c

func total_nodes() -> int:
	return grid_nodes.size()

func infected_total() -> int:
	var c: = 0
	for node in grid_nodes:
		if node["infected"]:
			c += 1
	return c

func node_unlocked(node: Dictionary) -> bool:
	if node["boss"]:
		return infected_count(3) >= 1
	match node["tier"]:
		0: return true
		1: return infected_count(0) >= 1
		2: return infected_count(1) >= 2
		3: return infected_count(2) >= 1
	return false

func node_lock_reason(node: Dictionary) -> String:
	if node["boss"]:
		return "нужен захваченный дата-центр T4"
	match node["tier"]:
		1: return "сначала заразите домашний ПК"
		2: return "нужно 2 захваченных офиса T2"
		3: return "нужен захваченный банк T3"
	return ""

# ── взлом узла ──────────────────────────────────────────────

func start_hack(node: Dictionary) -> void:
	current_node = node
	var cls: = selected_class
	access = 0.0
	alarm = grid_heat * 0.3
	if mutation_owned("ghost_start"):
		alarm = maxf(alarm - 15.0, 0.0)
	max_bandwidth = (150.0 if cls == "botnet" else 100.0) + evo_bonus("bw")
	bw_regen = (8.0 if cls == "botnet" else 4.0) + evo_bonus("bw") * 0.08
	bandwidth = max_bandwidth
	my_max_hp = 3 + int(evo_bonus("vitality")) + (1 if cls == "ransomware" else 0)
	my_hp = my_max_hp
	my_bug = false
	evac_open = false
	evac_left = 0.0
	wipe_forced = false
	stats = {"delivered": 0, "deposits": 0, "broken": 0, "revives": 0, "caught": 0, "safes": 0, "perfect_safes": 0, "fails": 0, "rounds": 0}
	node_config = _build_node_config(node)

func _build_node_config(node: Dictionary) -> Dictionary:
	var tier: int = node["tier"]
	var t: Dictionary = TIERS[tier]
	var quota: int = t["quota"]
	var files: int = t["files"]
	var crates: int = t["crates"]
	var safe_count: int = t["safes"]
	var popups: int = t["popups"]
	var hunters: int = t["hunters"]
	var creep: float = t["creep"]
	if node["boss"]:
		quota = 150
		files = 11
		crates = 5
		safe_count = 3
		popups = 2
		hunters = 3
		creep = 0.5
	var mut_chance: = 0.25 + 0.12 * float(tier)
	var safes: Array = []
	for i in safe_count:
		var muts: Array = []
		if randf() < mut_chance:
			muts.append(MUTATORS.keys().pick_random())
		safes.append({
			"id": i, "title": "СЕЙФ-%02d" % (i + 1),
			"game": MINIGAMES.keys().pick_random(),
			"mutators": muts, "done": false,
			"color": Color("ffb454"),
		})
	var risk: String = ["НИЗКИЙ", "СРЕДНИЙ", "ВЫСОКИЙ", "КРИТИЧЕСКИЙ"][tier]
	if node["boss"]:
		risk = "ОРАКУЛ"
	return {
		"name": node["name"], "tier": tier, "boss": node["boss"],
		"tier_name": t["name"], "tier_short": t["short"],
		"antivirus": node["av"], "risk": risk,
		"quota": quota, "files": files, "crates": crates,
		"safes": safes, "popups": popups, "hunters": hunters, "creep": creep,
		"difficulty": tier,
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
	apply_alarm(amount, source, selected_class)

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
	if selected_class == "rootkit":
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
		"code_samples": stats["perfect_safes"] + (2 if node_config.get("boss", false) and victory else 0),
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
	_add_action("zeroday", [KEY_F])
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
