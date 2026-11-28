## Quaternius "Stylized Nature MegaKit" (Standard, CC0)의 나무·풀·바위를 야외 지형용으로 굽습니다.
##   godot --headless --path . -s tools/bake_nature.gd
## 원본은 F:/workspace/fab_downloads/godot/quaternius_nature/ 에 둡니다 (저장소에 넣지 않음).
## 모델마다 재질별로 면을 합친 메시 하나를 MeshInstance3D에 담아 장면(.scn)으로 저장합니다
## (Terrain3D 식생 배치는 장면 파일을 받음). 텍스처 세트마다 재질 하나를 1024로 줄여 함께 씁니다.
## 결과: assets/quaternius/nature/<이름>.scn — 바닥 가운데가 원점, 1 유닛 = 1칸 (사람 키 1.28칸 ≈ 1.8m)
extends SceneTree

const SRC := "F:/workspace/fab_downloads/godot/quaternius_nature/x/glTF/"
const OUT := "res://assets/quaternius/nature/"
## 미터 → 칸
const M := 0.7
const TEX := 1024
## 쓸 모델 (이름 앞부분이 맞으면 모두)
const PICK := ["CommonTree_", "Pine_", "TwistedTree_", "DeadTree_", "Bush_Common", "Grass_Common_", "Grass_Wispy_",
	"Fern_1", "Flower_3_Group", "Flower_4_Group", "Clover_", "Plant_1", "Plant_7", "Rock_Medium_", "Mushroom_Common",
	"Pebble_Round_", "RockPath_Round_"]

var _mats := {}


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var n := 0
	for f in DirAccess.get_files_at(SRC):
		if not f.ends_with(".gltf") or not PICK.any(func(p): return f.begins_with(p)):
			continue
		var mesh := _bake(f)
		if mesh == null:
			continue
		var root := MeshInstance3D.new()
		root.name = f.get_basename()
		root.mesh = mesh
		var packed := PackedScene.new()
		packed.pack(root)
		var err := ResourceSaver.save(packed, OUT + f.get_basename() + ".scn", ResourceSaver.FLAG_COMPRESS)
		root.free()
		if err != OK:
			push_error("저장 실패: " + f)
		n += 1
	print("구움: ", n, " 재질: ", _mats.keys())
	quit()


func _bake(file: String) -> ArrayMesh:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(SRC + file, st) != OK:
		push_error("못 읽음: " + file)
		return null
	var scene := doc.generate_scene(st)
	var parts := []
	var box := AABB()
	var first := true
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var xf := _xf(mi, scene)
		var ab: AABB = xf * (mi as MeshInstance3D).get_aabb()
		box = ab if first else box.merge(ab)
		first = false
		parts.append([mi, xf])
	var shift := Transform3D(Basis.from_scale(Vector3.ONE * M), Vector3.ZERO) \
			* Transform3D(Basis.IDENTITY, -Vector3(box.get_center().x, box.position.y, box.get_center().z))
	var groups := {}
	for p in parts:
		var mi := p[0] as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			var key := m.resource_name if m else "none"
			if not groups.has(key):
				groups[key] = [m, []]
			groups[key][1].append([mi.mesh, s, shift * (p[1] as Transform3D)])
	var out := ArrayMesh.new()
	for key in groups:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for e in groups[key][1]:
			tool.append_from(e[0], e[1], e[2])
		tool.generate_tangents()
		tool.commit(out)
		out.surface_set_material(out.get_surface_count() - 1, _material(key, groups[key][0]))
	scene.free()
	return out


## 텍스처 세트마다 재질 하나 (모든 모델이 같은 파일을 가리킴)
func _material(key: String, src: Material) -> Material:
	if _mats.has(key):
		return _mats[key]
	var mat: StandardMaterial3D = (src as StandardMaterial3D).duplicate() if src is StandardMaterial3D else StandardMaterial3D.new()
	for prop in ["albedo_texture", "normal_texture", "orm_texture", "roughness_texture", "metallic_texture", "ao_texture", "emission_texture"]:
		var t = mat.get(prop)
		if t is Texture2D:
			mat.set(prop, _shrink(t as Texture2D, key + "_" + prop.trim_suffix("_texture"), prop == "normal_texture"))
	# 잎·풀: 알파 잘라내기는 그대로, 양면
	if mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var path := OUT + "mat_%s.res" % key.validate_filename()
	ResourceSaver.save(mat, path, ResourceSaver.FLAG_COMPRESS)
	_mats[key] = load(path)
	return _mats[key]


func _shrink(t: Texture2D, name: String, normal: bool) -> Texture2D:
	var img := t.get_image()
	if img == null:
		return t
	img = img.duplicate()
	img.decompress()
	if img.get_width() > TEX:
		img.resize(TEX, TEX * img.get_height() / img.get_width(), Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps(normal)
	img.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_NORMAL if normal else Image.COMPRESS_SOURCE_GENERIC)
	var path := OUT + "tex_%s.res" % name.validate_filename()
	ResourceSaver.save(ImageTexture.create_from_image(img), path, ResourceSaver.FLAG_COMPRESS)
	return load(path)


func _xf(n: Node, top: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var c := n
	while c != top and c != null:
		if c is Node3D:
			xf = (c as Node3D).transform * xf
		c = c.get_parent()
	return xf
