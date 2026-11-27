## Quaternius "Fantasy Props MegaKit" (Standard, CC0) 소품을 던전 장식 메시로 굽습니다.
##   godot --headless --path . -s tools/bake_megakit.gd
## 원본 glTF(모델마다 2048 텍스처를 따로 불러옴)는 F:/workspace/fab_downloads/godot/quaternius_props/ 에 두고,
## 텍스처 세트(Trim_Metal·Furniture·Props·Cloth 등)마다 재질을 하나만 만들어 1024로 줄여 따로 저장한 뒤
## 모델 메시가 그 재질을 함께 쓰게 합니다.
## 결과: assets/quaternius/props/<모델 이름>.res (바닥 가운데가 원점, 앞이 +Z, 1 유닛 = 1칸)
extends SceneTree

const SRC := "F:/workspace/fab_downloads/godot/quaternius_props/Exports/glTF/"
const OUT := "res://assets/quaternius/props/"
## 미터 → 칸. 이 팩은 실제보다 조금 크게 만들어져 있어 0.6 (놓을 때 칸에 맞게 한 번 더 줄임)
const M := 0.6
const TEX := 1024
## 밝은 원색을 던전 돌색에 맞게 조금 누름 (Unity 소품과 같은 값)
const TINT := Color(0.78, 0.72, 0.68)

var _mats := {}


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var n := 0
	for f in DirAccess.get_files_at(SRC):
		if not f.ends_with(".gltf"):
			continue
		var mesh := _bake(f)
		if mesh == null:
			continue
		var err := ResourceSaver.save(mesh, OUT + f.get_basename() + ".res", ResourceSaver.FLAG_COMPRESS)
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
	var shift := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * M), Vector3.ZERO) \
			* Transform3D(Basis.IDENTITY, -Vector3(box.get_center().x, box.position.y, box.get_center().z))
	# 보물상자는 뚜껑을 열 수 있게 몸통·뚜껑을 따로도 저장 (Chest_Wood_Base.res, Chest_Wood_Lid.res)
	if file == "Chest_Wood.gltf":
		for p in parts:
			var pmi := p[0] as MeshInstance3D
			var one := ArrayMesh.new()
			for s in pmi.mesh.get_surface_count():
				var sm := pmi.mesh.surface_get_material(s)
				var stl := SurfaceTool.new()
				stl.begin(Mesh.PRIMITIVE_TRIANGLES)
				stl.append_from(pmi.mesh, s, shift * (p[1] as Transform3D))
				stl.generate_tangents()
				stl.commit(one)
				one.surface_set_material(one.get_surface_count() - 1, _material(sm.resource_name if sm else "none", sm))
			ResourceSaver.save(one, OUT + String(pmi.name) + ".res", ResourceSaver.FLAG_COMPRESS)
	# 재질 이름마다 면을 모음
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


## 텍스처 세트마다 재질 하나 (텍스처를 줄여 따로 저장해, 모든 소품 메시가 같은 파일을 가리킴)
func _material(key: String, src: Material) -> Material:
	if _mats.has(key):
		return _mats[key]
	var mat: StandardMaterial3D = (src as StandardMaterial3D).duplicate() if src is StandardMaterial3D else StandardMaterial3D.new()
	mat.albedo_color *= TINT
	for prop in ["albedo_texture", "normal_texture", "orm_texture", "roughness_texture", "metallic_texture", "ao_texture", "emission_texture"]:
		if not prop in mat:
			continue
		var t = mat.get(prop)
		if t is Texture2D:
			mat.set(prop, _shrink(t as Texture2D, key + "_" + prop.trim_suffix("_texture"), prop == "normal_texture"))
	var path := OUT + "mat_%s.res" % key
	ResourceSaver.save(mat, path, ResourceSaver.FLAG_COMPRESS)
	var saved := load(path) as Material
	_mats[key] = saved
	return saved


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
	var tex := ImageTexture.create_from_image(img)
	var path := OUT + "tex_%s.res" % name
	ResourceSaver.save(tex, path, ResourceSaver.FLAG_COMPRESS)
	return load(path) as Texture2D


func _xf(n: Node, top: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var c := n
	while c != top and c != null:
		if c is Node3D:
			xf = (c as Node3D).transform * xf
		c = c.get_parent()
	return xf
