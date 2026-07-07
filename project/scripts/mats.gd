class_name Mats

## Процедурные реалистичные материалы: шумовые albedo/normal текстуры
## (NoiseTexture2D) вместо голых цветных боксов. Триплан — чтобы текстура
## не растягивалась на боксах любых размеров. Кэш — текстуры общие.

static var _cache: Dictionary = {}

static func _noise(p_seed: int, freq: float, octaves: int) -> FastNoiseLite:
	var n: = FastNoiseLite.new()
	n.seed = p_seed
	n.frequency = freq
	n.fractal_octaves = octaves
	return n

static func _tex(key: String, p_seed: int, freq: float, octaves: int = 4, as_normal: bool = false, bump: float = 4.0) -> NoiseTexture2D:
	if _cache.has(key):
		return _cache[key]
	var t: = NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.noise = _noise(p_seed, freq, octaves)
	if as_normal:
		t.as_normal_map = true
		t.bump_strength = bump
	_cache[key] = t
	return t

static func _cell_tex(key: String, p_seed: int, freq: float) -> NoiseTexture2D:
	## клеточный шум: окна высоток, плитка, панели
	if _cache.has(key):
		return _cache[key]
	var n: = FastNoiseLite.new()
	n.seed = p_seed
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	n.frequency = freq
	var t: = NoiseTexture2D.new()
	t.width = 128
	t.height = 128
	t.seamless = true
	t.noise = n
	_cache[key] = t
	return t

static func concrete(tint: = Color(0.44, 0.45, 0.48), uv: = 0.3) -> StandardMaterial3D:
	## шершавый бетон стен и потолков
	var m: = StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = _tex("conc_a", 11, 0.05, 5)
	m.normal_enabled = true
	m.normal_texture = _tex("conc_n", 12, 0.09, 4, true, 3.2)
	m.normal_scale = 0.55
	m.roughness = 0.92
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(uv, uv, uv)
	return m

static func metal(tint: = Color(0.62, 0.65, 0.7), rough: = 0.4, uv: = 0.6) -> StandardMaterial3D:
	## шлифованный металл: корпуса, робот, станции
	var m: = StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = _tex("met_a", 21, 0.03, 2)
	m.metallic = 0.85
	m.roughness = rough
	m.normal_enabled = true
	m.normal_texture = _tex("met_n", 22, 0.02, 2, true, 1.6)
	m.normal_scale = 0.3
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(uv * 3.0, uv * 0.2, uv)
	return m

static func metal_dark(rough: = 0.5) -> StandardMaterial3D:
	return metal(Color(0.34, 0.36, 0.4), rough)

static func plastic(tint: = Color(0.36, 0.39, 0.44), uv: = 0.5) -> StandardMaterial3D:
	## матовый пластик корпусов техники
	var m: = StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = _tex("pl_a", 31, 0.12, 3)
	m.metallic = 0.15
	m.roughness = 0.62
	m.normal_enabled = true
	m.normal_texture = _tex("pl_n", 32, 0.16, 3, true, 1.4)
	m.normal_scale = 0.25
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(uv, uv, uv)
	return m

static func asphalt(tint: = Color(0.3, 0.31, 0.34), uv: = 0.22) -> StandardMaterial3D:
	## тёмный асфальт Грида
	var m: = StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = _tex("asp_a", 41, 0.18, 5)
	m.roughness = 0.88
	m.normal_enabled = true
	m.normal_texture = _tex("asp_n", 42, 0.22, 5, true, 4.5)
	m.normal_scale = 0.7
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(uv, uv, uv)
	return m

static func wet_floor(tint: = Color(0.2, 0.22, 0.26), uv: = 0.18) -> StandardMaterial3D:
	## мокрый бетон уровней: глянец для SSR-отражений + шум под ним
	var m: = StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = _tex("wet_a", 51, 0.1, 5)
	m.metallic = 0.08
	m.roughness = 0.24
	m.roughness_texture = _tex("wet_r", 53, 0.07, 4)
	m.normal_enabled = true
	m.normal_texture = _tex("wet_n", 52, 0.12, 4, true, 2.0)
	m.normal_scale = 0.35
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(uv, uv, uv)
	return m

static func rubber() -> StandardMaterial3D:
	## шины робота
	var m: = StandardMaterial3D.new()
	m.albedo_color = Color(0.13, 0.13, 0.14)
	m.albedo_texture = _tex("rub_a", 61, 0.3, 3)
	m.roughness = 0.95
	m.normal_enabled = true
	m.normal_texture = _tex("rub_n", 62, 0.35, 3, true, 2.5)
	m.normal_scale = 0.4
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(1.2, 1.2, 1.2)
	return m

# ── этап 1: ночной мегаполис ────────────────────────────────

static func brick(tint: = Color(0.32, 0.26, 0.24), uv: = 0.55) -> StandardMaterial3D:
	## тёмный кирпич фасадов ночного города
	var m: = StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = _tex("brk_a", 71, 0.25, 4)
	m.roughness = 0.9
	m.normal_enabled = true
	m.normal_texture = _tex("brk_n", 72, 0.5, 3, true, 5.0)
	m.normal_scale = 0.75
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(uv, uv * 2.2, uv)
	return m

static func city_windows(p_seed: = 81, tint: = Color(0.05, 0.06, 0.09)) -> StandardMaterial3D:
	## фасад высотки: тёмная башня со случайно горящими окнами
	var m: = StandardMaterial3D.new()
	m.albedo_color = tint
	m.roughness = 0.4
	m.metallic = 0.3
	m.emission_enabled = true
	m.emission = Color(0.85, 0.75, 0.5)
	m.emission_energy_multiplier = 1.1
	m.emission_texture = _cell_tex("win_%d" % p_seed, p_seed, 0.11)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.35, 0.35, 0.35)
	return m

static func sidewalk(uv: = 0.4) -> StandardMaterial3D:
	## тротуарная плитка мокрого города
	var m: = StandardMaterial3D.new()
	m.albedo_color = Color(0.26, 0.27, 0.3)
	m.albedo_texture = _cell_tex("side_a", 91, 0.5)
	m.roughness = 0.55
	m.roughness_texture = _tex("side_r", 92, 0.09, 4)
	m.normal_enabled = true
	m.normal_texture = _tex("side_n", 93, 0.3, 4, true, 3.0)
	m.normal_scale = 0.45
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(uv, uv, uv)
	return m

# ── этап 2: затхлые офисы ───────────────────────────────────

static func plaster_old(tint: = Color(0.5, 0.48, 0.42), uv: = 0.35) -> StandardMaterial3D:
	## облупившаяся штукатурка со следами потёков
	var m: = StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = _tex("pls_a", 101, 0.08, 5)
	m.roughness = 0.95
	m.normal_enabled = true
	m.normal_texture = _tex("pls_n", 102, 0.14, 5, true, 4.2)
	m.normal_scale = 0.7
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(uv, uv, uv)
	return m

static func wood_old(tint: = Color(0.32, 0.24, 0.17), uv: = 0.5) -> StandardMaterial3D:
	## рассохшееся дерево столов и панелей
	var m: = StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = _tex("wd_a", 111, 0.06, 4)
	m.roughness = 0.85
	m.normal_enabled = true
	m.normal_texture = _tex("wd_n", 112, 0.04, 3, true, 2.6)
	m.normal_scale = 0.5
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(uv * 3.0, uv * 0.4, uv)
	return m

static func carpet_rot(tint: = Color(0.24, 0.26, 0.2), uv: = 0.3) -> StandardMaterial3D:
	## гнилой офисный ковролин
	var m: = StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = _tex("cpt_a", 121, 0.35, 4)
	m.roughness = 1.0
	m.normal_enabled = true
	m.normal_texture = _tex("cpt_n", 122, 0.45, 3, true, 2.0)
	m.normal_scale = 0.35
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(uv, uv, uv)
	return m

static func moss(tint: = Color(0.2, 0.34, 0.14), uv: = 0.5) -> StandardMaterial3D:
	## мох и плесень: бархатистые пятна
	var m: = StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = _tex("mos_a", 131, 0.28, 5)
	m.roughness = 1.0
	m.normal_enabled = true
	m.normal_texture = _tex("mos_n", 132, 0.4, 4, true, 3.5)
	m.normal_scale = 0.6
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(uv, uv, uv)
	return m

static func vine() -> StandardMaterial3D:
	## лианы, свисающие с потолков
	var m: = StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.28, 0.1)
	m.albedo_texture = _tex("vin_a", 141, 0.5, 3)
	m.roughness = 0.9
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(2.0, 2.0, 2.0)
	return m

static func cobweb() -> StandardMaterial3D:
	## паутина: полупрозрачная дымка в углах
	var m: = StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(0.85, 0.88, 0.9, 0.16)
	m.albedo_texture = _tex("web_a", 151, 0.6, 2)
	m.uv1_scale = Vector3(2.0, 2.0, 2.0)
	return m

# ── этап 3: бункер ──────────────────────────────────────────

static func bunker_wall(tint: = Color(0.3, 0.31, 0.3), uv: = 0.25) -> StandardMaterial3D:
	## литой бетон бункера с опалубкой
	var m: = StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = _tex("bnk_a", 161, 0.04, 5)
	m.roughness = 0.97
	m.normal_enabled = true
	m.normal_texture = _tex("bnk_n", 162, 0.06, 5, true, 4.5)
	m.normal_scale = 0.8
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(uv, uv, uv)
	return m

static func rust(tint: = Color(0.38, 0.24, 0.16), uv: = 0.45) -> StandardMaterial3D:
	## ржавый металл дверей и решёток
	var m: = StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = _tex("rst_a", 171, 0.16, 5)
	m.metallic = 0.6
	m.roughness = 0.8
	m.normal_enabled = true
	m.normal_texture = _tex("rst_n", 172, 0.2, 4, true, 3.4)
	m.normal_scale = 0.55
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(uv, uv, uv)
	return m

static func deck_metal(tint: = Color(0.36, 0.38, 0.42), uv: = 0.8) -> StandardMaterial3D:
	## рифлёный стальной настил мостков и лифтов
	var m: = StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = _cell_tex("dck_a", 181, 0.9)
	m.metallic = 0.8
	m.roughness = 0.5
	m.normal_enabled = true
	m.normal_texture = _tex("dck_n", 182, 0.7, 3, true, 2.8)
	m.normal_scale = 0.5
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(uv, uv, uv)
	return m

static func hazard() -> StandardMaterial3D:
	## сигнальная окраска: жёлто-чёрные зоны опасности
	var m: = StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.6, 0.12)
	m.albedo_texture = _tex("hzd_a", 191, 0.4, 2)
	m.roughness = 0.7
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(1.5, 1.5, 1.5)
	return m

# ── Оракул и туннель победы ─────────────────────────────────

static func obsidian(uv: = 0.3) -> StandardMaterial3D:
	## чёрный полированный камень зала Оракула
	var m: = StandardMaterial3D.new()
	m.albedo_color = Color(0.07, 0.08, 0.1)
	m.albedo_texture = _tex("obs_a", 201, 0.05, 4)
	m.metallic = 0.4
	m.roughness = 0.18
	m.normal_enabled = true
	m.normal_texture = _tex("obs_n", 202, 0.08, 3, true, 1.6)
	m.normal_scale = 0.2
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(uv, uv, uv)
	return m

static func white_panel(uv: = 0.4) -> StandardMaterial3D:
	## светлые панели белого туннеля победы
	var m: = StandardMaterial3D.new()
	m.albedo_color = Color(0.92, 0.94, 0.97)
	m.albedo_texture = _cell_tex("wht_a", 211, 0.25)
	m.roughness = 0.35
	m.metallic = 0.1
	m.normal_enabled = true
	m.normal_texture = _tex("wht_n", 212, 0.1, 2, true, 1.2)
	m.normal_scale = 0.12
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(uv, uv, uv)
	return m
