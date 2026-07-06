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
