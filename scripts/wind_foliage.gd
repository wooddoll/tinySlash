## Quaternius Stylized Nature MegaKit 모델(tools/bake_nature.gd로 구운 장면)을 바람에 흔들리게 바꿉니다.
## 재질(StandardMaterial3D)을 shaders/foliage_wind.gdshader 셰이더 재질로 바꾼 메시 복사본을 장면으로 돌려줌.
## 바위·버섯·돌길은 그대로 (흔들리지 않음). 같은 원본 재질·장면은 한 번만 만듦.
##   var scene := WindFoliage.scene("res://assets/quaternius/nature/CommonTree_1.scn")
extends RefCounted

const SHADER := preload("res://shaders/foliage_wind.gdshader")
## 재질 이름(앞부분) → [휘는 정도, 잎 떨림]. 없는 재질은 흔들지 않음
const WIND := {
	"mat_Bark_": [0.035, 0.0],
	"mat_Leaves_NormalTree": [0.035, 0.012],
	"mat_Leaves_Pine": [0.03, 0.006],
	"mat_Leaves_TwistedTree": [0.04, 0.015],
	"mat_Leaves": [0.06, 0.02],
	"mat_Flowers": [0.06, 0.02],
	"mat_Grass": [0.08, 0.01],
}

static var _mats := {}
static var _scenes := {}


## 바람 재질 (흔들지 않을 재질이면 원본 그대로)
static func material(src: Material) -> Material:
	if not (src is StandardMaterial3D):
		return src
	var key := src.resource_path.get_file().get_basename()
	if _mats.has(key):
		return _mats[key]
	# 가장 길게 맞는 이름 (mat_Leaves_Pine은 mat_Leaves보다 mat_Leaves_Pine)
	var w: Array = []
	var best := 0
	for prefix: String in WIND:
		if key.begins_with(prefix) and prefix.length() > best:
			best = prefix.length()
			w = WIND[prefix]
	if w.is_empty():
		_mats[key] = src
		return src
	var s := src as StandardMaterial3D
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("albedo_texture", s.albedo_texture)
	m.set_shader_parameter("use_vertex_color", s.vertex_color_use_as_albedo)
	if s.normal_enabled and s.normal_texture:
		m.set_shader_parameter("normal_texture", s.normal_texture)
		m.set_shader_parameter("use_normal", true)
	m.set_shader_parameter("cutoff", s.alpha_scissor_threshold if s.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED else 0.0)
	m.set_shader_parameter("sway", w[0])
	m.set_shader_parameter("flutter", w[1])
	_mats[key] = m
	return m


## 바람에 흔들리는 장면 (원본 장면이 없으면 null)
static func scene(path: String) -> PackedScene:
	if _scenes.has(path):
		return _scenes[path]
	if not ResourceLoader.exists(path):
		return null
	var src := (load(path) as PackedScene).instantiate()
	var mi := src as MeshInstance3D
	if mi == null or mi.mesh == null:
		src.free()
		return load(path)
	var mesh := mi.mesh.duplicate() as Mesh
	for i in mesh.get_surface_count():
		mesh.surface_set_material(i, material(mi.mesh.surface_get_material(i)))
	mi.mesh = mesh
	var packed := PackedScene.new()
	packed.pack(mi)
	src.free()
	_scenes[path] = packed
	return packed
