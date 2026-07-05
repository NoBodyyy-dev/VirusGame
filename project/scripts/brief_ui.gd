extends Control

## Бриф выноса: квота, стражи, сейфы, советы. Коротко — и грабить.

signal started

var _rich: RichTextLabel
var _chars_tween: Tween

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim: = ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.02, 0.82)
	add_child(UIKit.full_rect(dim))

	var center: = CenterContainer.new()
	add_child(UIKit.full_rect(center))
	var panel: = PanelContainer.new()
	panel.custom_minimum_size = Vector2(880, 620)
	panel.add_theme_stylebox_override("panel", UIKit.panel_box(UIKit.CYAN, Color(0.008, 0.02, 0.036, 0.98), 1, 8, 26))
	center.add_child(panel)

	var v: = VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)

	v.add_child(UIKit.label("ПЛАН ОГРАБЛЕНИЯ · %s (%s · %s)" % [GameState.node_config["name"], GameState.node_config["tier_short"], GameState.node_config["tier_name"]], 28, UIKit.TEAL))

	_rich = RichTextLabel.new()
	_rich.bbcode_enabled = true
	_rich.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rich.add_theme_font_size_override("normal_font_size", 17)
	_rich.text = _compose()
	v.add_child(_rich)

	var row: = HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	v.add_child(row)
	var btn: = UIKit.button("  НАЧАТЬ ВЫНОС ▸  ", 22, UIKit.TEAL)
	btn.pressed.connect(func() -> void: started.emit())
	row.add_child(btn)
	var recon: = "разведка: ПОЛНАЯ (Spyware)" if GameState.recon_full() else "разведка: СТАНДАРТНАЯ — замки сейфов неизвестны"
	row.add_child(UIKit.label(recon, 15, UIKit.DIM))

	_rich.visible_characters = 0
	_chars_tween = create_tween()
	_chars_tween.tween_property(_rich, "visible_characters", _rich.get_total_character_count(), 1.4)

func _compose() -> String:
	var cfg: Dictionary = GameState.node_config
	var full: = GameState.recon_full()
	var cyan: = UIKit.CYAN.to_html(false)
	var amber: = UIKit.AMBER.to_html(false)
	var teal: = UIKit.TEAL.to_html(false)
	var dim: = UIKit.DIM.to_html(false)
	var s: = ""
	s += "[color=#%s]Задача:[/color] вынести добычу на [color=#%s]◈ %d[/color] в круг у портала. Лут физический: хватай [E], тащи, не роняй!\n" % [
		dim, teal, cfg["quota"]]
	s += "[color=#%s]Стражи:[/color] %s · СКАНЕР патрулирует сразу; на 25%% тревоги придут ПОПАПЫ-воришки; на 55%% — HUNTER (он вас СЛЫШИТ); 90%% — СТИРАНИЕ\n" % [dim, cfg["antivirus"]]
	s += "[color=#%s]Тревога сама НЕ падает.[/color] Сброс — только КУЛЕР (3 заряда на команду)\n\n" % amber
	var i: = 0
	for safe in cfg["safes"]:
		i += 1
		var mg: Dictionary = GameState.MINIGAMES[safe["game"]]
		var mut_text: = ""
		if full:
			if not safe["mutators"].is_empty():
				var names: = []
				for m in safe["mutators"]:
					names.append(GameState.MUTATORS[m].get_slice(" — ", 0))
				mut_text = "  [color=#%s][мутатор: %s][/color]" % [amber, ", ".join(names)]
		elif not safe["mutators"].is_empty():
			mut_text = "  [color=#%s][??? аномалия замка][/color]" % dim
		s += "[color=#%s]%s[/color] → %s%s   [color=#%s]внутри: ЭПИК-ЛУТ · реком.: %s[/color]\n" % [
			cyan, safe["title"], mg["title"], mut_text, dim, mg["best"]]
	s += "\n[color=#%s]ПАМЯТКА СТАИ:[/color]\n" % cyan
	for line in _hints(cfg, full):
		s += "  • %s\n" % line
	return s

func _hints(cfg: Dictionary, full: bool) -> Array:
	var hints: = []
	hints.append("Тяжёлые ящики несут ВДВОЁМ (Ransomware — один). С грузом нельзя прыгать")
	hints.append("Уронил с высоты — лут треснул и подешевел. Три удара — РАЗБИТ")
	hints.append("[F] — швырнуть груз: можно пасовать и добрасывать в круг. Но это шумно")
	hints.append("HUNTER слепой: замри — и он пролетит мимо. Бег и прыжки он слышит")
	hints.append("0 HP = ты БАГ: скачи в круг реанимации или жди дефибриллятор Botnet")
	if full:
		for safe in cfg["safes"]:
			for m in safe["mutators"]:
				hints.append(GameState.MUTATOR_HINTS[m])
	hints.append("Квота взята → эвакуация %dс: жадничайте с умом" % int(GameState.EVAC_TIME))
	return hints
