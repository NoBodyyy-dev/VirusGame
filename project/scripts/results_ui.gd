extends Control

## Итоги выноса: добыча, статистика хаоса, номинации гонки штаммов.

func show_result(victory: bool, reason: String) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim: = ColorRect.new()
	dim.color = Color(0.0, 0.005, 0.015, 0.88)
	add_child(UIKit.full_rect(dim))

	var accent: = UIKit.TEAL if victory else UIKit.MAGENTA
	var center: = CenterContainer.new()
	add_child(UIKit.full_rect(center))
	var coop: = Net.active and Net.players.size() >= 2
	var panel: = PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 620) if coop else Vector2(680, 500)
	panel.add_theme_stylebox_override("panel", UIKit.panel_box(accent, Color(0.008, 0.02, 0.036, 0.98), 2, 10, 30))
	center.add_child(panel)

	var v: = VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	var loot: Dictionary = GameState.last_result.get("loot", GameState.compute_loot(victory))
	var boss: bool = GameState.node_config.get("boss", false)
	var head: = "УЗЕЛ ОГРАБЛЕН // ЭКФИЛЬТРАЦИЯ УСПЕШНА"
	if victory and boss:
		head = "ОРАКУЛ ОБНЕСЁН ПОДЧИСТУЮ // ГРИД ПАЛ"
	elif not victory:
		head = "ВЫНОС СОРВАЛСЯ"
	v.add_child(UIKit.label(head, 30, accent))
	v.add_child(UIKit.label("%s — %s" % [GameState.node_config["name"], reason], 17, UIKit.DIM))
	if loot["perfect"] and victory:
		v.add_child(UIKit.label("★ ЧИСТОЕ ОГРАБЛЕНИЕ — ничего не разбито, никто не пойман", 20, UIKit.AMBER))

	var sep: = Control.new()
	sep.custom_minimum_size = Vector2(0, 8)
	v.add_child(sep)

	v.add_child(UIKit.label("ДОБЫЧА:", 18, UIKit.CYAN))
	v.add_child(UIKit.label("  Data Fragments: +%d" % loot["data_fragments"], 17))
	v.add_child(UIKit.label("  Code Samples: +%d  (за выполненные полевые задачи)" % loot["code_samples"], 17))
	v.add_child(UIKit.label("  Mutagen: +%d   ·   Ghost Tokens: +%d" % [loot["mutagen"], loot["ghost_tokens"]], 17))
	if not victory:
		v.add_child(UIKit.label("  … большая часть добычи потеряна; тревога Грида выросла", 15, UIKit.MAGENTA))

	var stats: Dictionary = GameState.stats
	v.add_child(UIKit.label("Твой вклад: ◈ %d за %d ходок · задач: %d · разбито: %d · перехватов: %d" % [
		stats["delivered"], stats["deposits"], stats["tasks"], stats["broken"], stats["caught"]], 15, UIKit.DIM))
	v.add_child(UIKit.label("Всего заражено Грида: %d / %d" % [GameState.infected_total(), GameState.total_nodes()], 15, UIKit.TEAL))

	if coop:
		var sep_n: = Control.new()
		sep_n.custom_minimum_size = Vector2(0, 8)
		v.add_child(sep_n)
		v.add_child(UIKit.label("ГОНКА ШТАММОВ // номинации узла:", 18, UIKit.CYAN))
		for nom in _nominations():
			v.add_child(UIKit.label("  " + nom["text"], 16, nom["color"]))

	var sep2: = Control.new()
	sep2.custom_minimum_size = Vector2(0, 10)
	sep2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sep2)

	var row: = HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	v.add_child(row)
	if not victory and not Net.active:
		var retry: = UIKit.button("  ПОВТОРИТЬ УЗЕЛ  ", 20, UIKit.AMBER)
		retry.pressed.connect(_on_retry)
		row.add_child(retry)
	var grid: = UIKit.button("  ВЕРНУТЬСЯ В ГРИД ▸  ", 20, UIKit.TEAL)
	grid.pressed.connect(_on_grid)
	row.add_child(grid)

func _nominations() -> Array:
	## шуточные номинации по итогам гонки штаммов
	var res: Array = []
	var ids: Array = Net.scores.keys()
	if ids.is_empty():
		return res
	var by_score: = ids.duplicate()
	by_score.sort_custom(func(a: int, b: int) -> bool: return Net.scores[a]["score"] > Net.scores[b]["score"])
	var mvp: int = by_score[0]
	res.append({"text": "★ MVP ВЫНОСА: %s — %d очков" % [Net.player_name(mvp), Net.scores[mvp]["score"]],
		"color": UIKit.AMBER})
	var mule: = -1
	for id in ids:
		var d: int = Net.scores[id]["delivered"]
		if d > 0 and (mule < 0 or d > Net.scores[mule]["delivered"]):
			mule = id
	if mule >= 0:
		res.append({"text": "▸ НОСИЛЬЩИК: %s — притащил ◈ %d" % [Net.player_name(mule), Net.scores[mule]["delivered"]],
			"color": UIKit.TEAL})
	var butter: = -1
	for id in ids:
		var b: int = Net.scores[id]["broken"]
		if b > 0 and (butter < 0 or b > Net.scores[butter]["broken"]):
			butter = id
	if butter >= 0:
		res.append({"text": "💥 РУКОЖОП: %s — разбил лута ×%d (руки-крюки, но мы любим)" % [
			Net.player_name(butter), Net.scores[butter]["broken"]], "color": Color(1.0, 0.6, 0.4)})
	var bait: = -1
	for id in ids:
		var c: int = Net.scores[id]["caught"]
		if c > 0 and (bait < 0 or c > Net.scores[bait]["caught"]):
			bait = id
	if bait >= 0:
		res.append({"text": "⚠ ПРИМАНКА: %s — HUNTER кусал его %d раз(а), это уже отношения" % [
			Net.player_name(bait), Net.scores[bait]["caught"]], "color": UIKit.MAGENTA})
	var medic: = -1
	for id in ids:
		var r: int = Net.scores[id]["revives"]
		if r > 0 and (medic < 0 or r > Net.scores[medic]["revives"]):
			medic = id
	if medic >= 0:
		res.append({"text": "⚡ РЕАНИМАТОЛОГ: %s — поднял друзей ×%d" % [Net.player_name(medic), Net.scores[medic]["revives"]],
			"color": Color("4a90ff")})
	var last: int = by_score[by_score.size() - 1]
	if last != mvp and Net.scores[last]["score"] < Net.scores[mvp]["score"]:
		res.append({"text": "✖ ТУРИСТ: %s — был рядом и морально поддерживал (%d очков)" % [
			Net.player_name(last), Net.scores[last]["score"]], "color": UIKit.DIM})
	return res

func _on_retry() -> void:
	GameState.start_hack(GameState.current_node)
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_grid() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/grid_world.tscn")
