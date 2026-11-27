## Unity 에셋 스토어 소품 팩을 Godot 소품 메시로 굽습니다 (Unity 없이).
##   1) python -I tools/unitypackage_extract.py <팩.unitypackage> <폴더> --only fbx,png,tga,mat,prefab
##   2) godot --headless --path . -s tools/bake_unity_props.gd
## 프리팹(.prefab)에서 원본 FBX와 면마다 쓰는 재질(.mat)을 GUID로 찾고, 재질의 텍스처를 Godot 재질로 옮깁니다.
##   Standard 셰이더: _MainTex(색) · _BumpMap(노멀, OpenGL) · _MetallicGlossMap(R 금속, A 매끈함) · _OcclusionMap(G)
##   → ORMMaterial3D (R 가림, G 거칠기 = 1 - 매끈함, B 금속). 텍스처는 1024로 줄여 VRAM 압축 후 .res 안에 넣습니다.
## 결과: assets/dark/props/<이름>.res (바닥 가운데가 원점, 앞이 +Z, 1 유닛 = 1칸 ≈ 1.4m)
extends SceneTree

## 미터 → 칸 (캐릭터 1.8m가 1.28칸)
const M := 0.71
const TEX := 1024
const OUT := "res://assets/dark/props/%s.res"
## 팩 이름 → 압축을 푼 폴더 (안에 Assets/와 _guids.tsv)
const PACKS := {
	"cobra": "F:/workspace/fab_downloads/unity/cobra_props/",
}
const COBRA := "Assets/CobraGamesAssets/Stylized_Dungeon_Props_Pack/Prefabs/"
## 소품 이름 → [팩, 프리팹 경로, 크기 배율]. 이끼 버전은 초록이 강해서 통 하나만 씀.
## 던전 벽 높이가 1칸이라 책장은 벽보다 낮게 줄임
const PROPS := {
	"barrel": ["cobra", COBRA + "Props/Barrel", 1.0],
	"barrel-moss": ["cobra", COBRA + "Props/Moss/Barrel_Moss", 1.0],
	"crate-large": ["cobra", COBRA + "Props/Crate_Large", 0.7],
	"crate-small": ["cobra", COBRA + "Props/Crate_Small", 1.0],
	"pot-large": ["cobra", COBRA + "Props/Pot_Large", 1.0],
	"pot-small": ["cobra", COBRA + "Props/Pot_Small", 1.0],
	"fire-bin": ["cobra", COBRA + "Props/Fire_Bin", 1.0],
	"bookshelf-a": ["cobra", COBRA + "Furniture/Bookshelf_A", 0.52],
	"bookshelf-b": ["cobra", COBRA + "Furniture/Bookshelf_B", 0.52],
	"drawers": ["cobra", COBRA + "Furniture/Chest_With_Drawers", 0.85],
	"chest-empty": ["cobra", COBRA + "Furniture/Chest_Empty", 0.85],
}
## 원색(주황 나무)이 밝아서 던전 돌색에 맞게 곱하는 색
const TINT := Color(0.78, 0.72, 0.68)

var _guids := {}  # 팩 → {guid: 경로}
var _tex := {}    # 캐시 키 → Texture2D
var _mats := {}   # .mat 경로 → Material


func _init() -> void:
	for pack in PACKS:
		var map := {}
		for line in FileAccess.get_file_as_string(PACKS[pack] + "_guids.tsv").split("\n", false):
			var kv := line.split("\t")
			map[kv[0]] = kv[1].strip_edges()
		_guids[pack] = map
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/dark/props"))
	var only := OS.get_cmdline_user_args()
	for prop in PROPS:
		if not only.is_empty() and not prop in only:
			continue
		var t0 := Time.get_ticks_msec()
		var mesh := _bake(PROPS[prop][0], PROPS[prop][1] + ".prefab", PROPS[prop][2])
		if mesh == null:
			continue
		var err := ResourceSaver.save(mesh, OUT % prop, ResourceSaver.FLAG_COMPRESS)
		print(prop, " size=", mesh.get_aabb().size.snapped(Vector3.ONE * 0.01), " surfaces=", mesh.get_surface_count(),
			" save=", err, " ", Time.get_ticks_msec() - t0, "ms")
	quit()


func _bake(pack: String, prefab: String, scale: float) -> ArrayMesh:
	var root: String = PACKS[pack]
	var text := FileAccess.get_file_as_string(root + prefab)
	if text == "":
		push_error("프리팹 없음: " + prefab)
		return null
	# 원본 FBX와 면별 재질
	var src := _ref(text, "m_SourcePrefab:")
	var fbx: String = _guids[pack].get(src, "")
	var mat_paths := {}
	var re := RegEx.create_from_string("propertyPath: m_Materials\\.Array\\.data\\[(\\d+)\\][\\s\\S]*?objectReference: \\{[^}]*guid: ([0-9a-f]+)")
	for m in re.search_all(text):
		mat_paths[int(m.get_string(1))] = _guids[pack].get(m.get_string(2), "")
	if fbx == "":
		# 옛 방식 프리팹: MeshFilter의 m_Mesh와 MeshRenderer의 m_Materials 목록
		fbx = _guids[pack].get(_ref(text, "m_Mesh:"), "")
		var i := text.find("m_Materials:")
		if i >= 0:
			var lst := RegEx.create_from_string("^\\s*- \\{fileID: \\d+, guid: ([0-9a-f]+)")
			var n := 0
			for line in text.substr(i).split("\n").slice(1):
				var m := lst.search(line)
				if m == null:
					break
				mat_paths[n] = _guids[pack].get(m.get_string(1), "")
				n += 1
	if fbx == "":
		push_error("FBX 못 찾음: " + prefab)
		return null
	var doc := FBXDocument.new()
	var st := FBXState.new()
	if doc.append_from_file(root + fbx, st) != OK:
		push_error("FBX 못 읽음: " + fbx)
		return null
	var scene := doc.generate_scene(st)
	var mis := scene.find_children("*", "MeshInstance3D", true, false)
	var mi := mis[0] as MeshInstance3D
	var xf := _xf(mi, scene)
	var box: AABB = xf * mi.get_aabb()
	var k := M * scale
	var shift := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * k), Vector3.ZERO) \
			* Transform3D(Basis.IDENTITY, -Vector3(box.get_center().x, box.position.y, box.get_center().z)) * xf
	var out := ArrayMesh.new()
	for s in mi.mesh.get_surface_count():
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.append_from(mi.mesh, s, shift)
		tool.generate_tangents()
		tool.commit(out)
		var mp: String = mat_paths.get(s, "")
		out.surface_set_material(s, _material(pack, mp) if mp != "" else _fallback(mi.mesh.surface_get_material(s)))
	scene.free()
	return out


## "key: {fileID: .., guid: X, ..}" 에서 X
func _ref(text: String, key: String) -> String:
	var i := text.find(key)
	if i < 0:
		return ""
	var m := RegEx.create_from_string("guid: ([0-9a-f]+)").search(text, i)
	return m.get_string(1) if m else ""


func _tex_guid(text: String, prop: String) -> String:
	var m := RegEx.create_from_string("- " + prop + ":\\s*\\n\\s*m_Texture: \\{fileID: \\d+(?:, guid: ([0-9a-f]+))?").search(text)
	return m.get_string(1) if m else ""


func _float(text: String, prop: String, def: float) -> float:
	var m := RegEx.create_from_string("- " + prop + ": ([-0-9.e]+)").search(text)
	return float(m.get_string(1)) if m else def


func _color(text: String, prop: String, def: Color) -> Color:
	var m := RegEx.create_from_string("- " + prop + ": \\{r: ([-0-9.e]+), g: ([-0-9.e]+), b: ([-0-9.e]+), a: ([-0-9.e]+)\\}").search(text)
	return Color(float(m.get_string(1)), float(m.get_string(2)), float(m.get_string(3)), float(m.get_string(4))) if m else def


func _material(pack: String, mat_path: String) -> Material:
	var key := pack + ":" + mat_path
	if _mats.has(key):
		return _mats[key]
	var root: String = PACKS[pack]
	var text := FileAccess.get_file_as_string(root + mat_path)
	var mat := ORMMaterial3D.new()
	mat.resource_name = mat_path.get_file().get_basename()
	mat.albedo_color = _color(text, "_Color", Color.WHITE) * TINT
	var main := _tex_guid(text, "_MainTex")
	if main == "":
		main = _tex_guid(text, "_BaseMap")
	if main != "":
		mat.albedo_texture = _image_tex(pack, main, "color")
	var bump := _tex_guid(text, "_BumpMap")
	if bump != "":
		mat.normal_enabled = true
		mat.normal_texture = _image_tex(pack, bump, "normal")
		mat.normal_scale = _float(text, "_BumpScale", 1.0)
	var mg := _tex_guid(text, "_MetallicGlossMap")
	var occ := _tex_guid(text, "_OcclusionMap")
	if mg != "":
		mat.orm_texture = _orm(pack, mg, occ, _float(text, "_GlossMapScale", 1.0))
		mat.metallic = 1.0
		mat.roughness = 1.0
		mat.ao_light_affect = 0.6
	else:
		mat.metallic = _float(text, "_Metallic", 0.0)
		mat.roughness = 1.0 - _float(text, "_Glossiness", 0.3)
	var em := _tex_guid(text, "_EmissionMap")
	var emc := _color(text, "_EmissionColor", Color.BLACK)
	if em != "" and emc.get_luminance() > 0.01:
		mat.emission_enabled = true
		mat.emission = emc
		mat.emission_texture = _image_tex(pack, em, "color")
	_mats[key] = mat
	return mat


func _fallback(src: Material) -> Material:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = (src as BaseMaterial3D).albedo_color if src is BaseMaterial3D else Color.GRAY
	mat.roughness = 0.85
	return mat


func _load(pack: String, guid: String) -> Image:
	var path: String = _guids[pack].get(guid, "")
	var img := Image.load_from_file(PACKS[pack] + path) if path != "" else null
	if img == null:
		push_error("텍스처 못 읽음: " + path)
		return null
	img.decompress()
	if img.get_width() > TEX or img.get_height() > TEX:
		img.resize(mini(TEX, img.get_width()), mini(TEX, img.get_height()), Image.INTERPOLATE_LANCZOS)
	return img


func _finish(img: Image, normal := false) -> ImageTexture:
	img.generate_mipmaps(normal)
	img.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_NORMAL if normal else Image.COMPRESS_SOURCE_GENERIC)
	return ImageTexture.create_from_image(img)


func _image_tex(pack: String, guid: String, kind: String) -> Texture2D:
	var key := pack + guid + kind
	if not _tex.has(key):
		var img := _load(pack, guid)
		if img == null:
			return null
		img.convert(Image.FORMAT_RGBA8 if kind == "color" else Image.FORMAT_RGB8)
		_tex[key] = _finish(img, kind == "normal")
	return _tex[key]


## Unity 금속·매끈함(+가림) → Godot ORM
func _orm(pack: String, mg: String, occ: String, gloss: float) -> Texture2D:
	var key := pack + mg + occ + str(gloss)
	if _tex.has(key):
		return _tex[key]
	var a := _load(pack, mg)
	a.convert(Image.FORMAT_RGBA8)
	var o: Image = null
	if occ != "" and occ != mg:
		o = _load(pack, occ)
		o.convert(Image.FORMAT_RGBA8)
		o.resize(a.get_width(), a.get_height())
	var src := a.get_data()
	var od := o.get_data() if o else src
	var dst := PackedByteArray()
	dst.resize(a.get_width() * a.get_height() * 3)
	var n := a.get_width() * a.get_height()
	for i in n:
		dst[i * 3] = od[i * 4 + 1] if occ != "" else 255
		dst[i * 3 + 1] = 255 - int(src[i * 4 + 3] * gloss)
		dst[i * 3 + 2] = src[i * 4]
	var img := Image.create_from_data(a.get_width(), a.get_height(), false, Image.FORMAT_RGB8, dst)
	_tex[key] = _finish(img)
	return _tex[key]


func _xf(n: Node, top: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var c := n
	while c != top and c != null:
		if c is Node3D:
			xf = (c as Node3D).transform * xf
		c = c.get_parent()
	return xf
