## Quaternius "Medieval Village MegaKit" (Standard, CC0)의 벽·바닥 조각을 던전 칸에 맞게 굽습니다.
##   godot --headless --path . -s tools/bake_village.gd
## 원본은 F:/workspace/fab_downloads/godot/quaternius_village/ 에 둡니다 (저장소에 넣지 않음).
## 결과: assets/quaternius/village/<이름>.res — 바닥 가운데가 원점, 1 유닛 = 1칸.
##   wall: 칸 모서리 하나를 채우는 벽판 (두께 가운데가 원점, -Z 쪽이 벽 칸)
##   post: 벽이 꺾이는 꼭짓점 기둥 · door: 문 뚫린 벽판
##   floor: 1x1 바닥판. 텍스처를 세계 좌표로 입혀(트라이플래너) 칸 경계가 보이지 않음
extends SceneTree

const SRC := "F:/workspace/fab_downloads/godot/quaternius_village/x/Medieval Village MegaKit[Standard]/"
const OUT := "res://assets/quaternius/village/"
const TEX := 1024
## 던전 돌색 (마을용 밝은 색을 어둡고 차게)
const TINT := Color(0.62, 0.58, 0.56)
## 이름 → [원본, 크기(가로, 높이, 두께)]. 원본 벽은 2m 너비·3.1m 높이: 한 칸 너비, 키의 1.3배쯤 높이로
const PIECES := {
	"wall": ["Wall_UnevenBrick_Straight", Vector3(0.5, 0.55, 0.5)],
	"door": ["Wall_UnevenBrick_Door_Round", Vector3(0.5, 0.55, 0.5)],
	"post": ["Corner_Exterior_Brick", Vector3(0.55, 0.57, 0.55)],
	# 방 안 기둥(완전 엄폐): 같은 돌기둥을 두껍게, 벽 높이로
	"column": ["Corner_Exterior_Brick", Vector3(1.0, 0.57, 1.0)],
	# 다음 층 계단: 2m 계단을 한 칸에
	"stairs": ["Stairs_Exterior_Straight", Vector3(0.48, 0.5, 0.48)],
	# 반 엄폐 낮은 울타리
	"fence": ["Prop_WoodenFence_Single", Vector3(0.48, 0.55, 0.6)],
}

var _mats := {}


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for name in PIECES:
		var m := _bake(PIECES[name][0], PIECES[name][1], name == "post")
		if m:
			print(name, " ", m.get_aabb(), " save=", ResourceSaver.save(m, OUT + name + ".res", ResourceSaver.FLAG_COMPRESS))
	var rub := _rubble()
	print("rubble ", rub.get_aabb(), " save=", ResourceSaver.save(rub, OUT + "rubble.res", ResourceSaver.FLAG_COMPRESS))
	var f := _floor()
	print("floor save=", ResourceSaver.save(f, OUT + "floor.res", ResourceSaver.FLAG_COMPRESS))
	quit()


## 조각 하나: 재질마다 면을 합치고, 가로·두께 가운데와 바닥을 원점으로, 칸 크기로 줄임
func _bake(file: String, size: Vector3, keep_corner: bool) -> ArrayMesh:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(SRC + "glTF/" + file + ".gltf", st) != OK:
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
	var c := box.get_center()
	# 기둥은 원래 꼭짓점이 원점이라 그대로 둠
	var origin := Vector3(0, box.position.y, 0) if keep_corner else Vector3(c.x, box.position.y, c.z)
	var shift := Transform3D(Basis.from_scale(size), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -origin)
	var mi_all := parts.map(func(p): return p[0])
	var groups := {}
	for p in parts:
		var mi := p[0] as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			var key := m.resource_name if m else "none"
			# 벽 바깥면(회반죽)도 돌로: 던전에서는 벽 양쪽이 다 보임
			if key == "MI_Plaster":
				key = "MI_UnevenBrick"
				m = _find_mat(mi_all, key)
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


## 잔해(험지): 벽돌 조각 넷을 아무렇게나 흩어 놓은 더미 (한 칸 안)
func _rubble() -> ArrayMesh:
	var spots := [["Prop_Brick1", Vector3(-0.2, 0, -0.15), 0.3], ["Prop_Brick2", Vector3(0.18, 0, -0.05), 1.4],
		["Prop_Brick3", Vector3(-0.05, 0, 0.2), 2.2], ["Prop_Brick4", Vector3(0.05, 0.06, -0.02), 0.9],
		["Prop_Brick1", Vector3(0.25, 0, 0.25), 2.8], ["Prop_Brick3", Vector3(-0.28, 0, 0.12), 0.6]]
	var groups := {}
	for sp in spots:
		var m := _bake(sp[0], Vector3.ONE * 0.6, false)
		var xf := Transform3D(Basis(Vector3.UP, sp[2]), sp[1])
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s)
			if not groups.has(mat):
				groups[mat] = []
			groups[mat].append([m, s, xf])
	var out := ArrayMesh.new()
	for mat in groups:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for e in groups[mat]:
			st.append_from(e[0], e[1], e[2])
		st.commit(out)
		out.surface_set_material(out.get_surface_count() - 1, mat)
	return out


## 바닥: 위를 보는 1x1 사각형 + 세계 좌표 트라이플래너 돌바닥 (원본 2m 타일 = 약 1.4칸마다 반복)
func _floor() -> ArrayMesh:
	var mat := StandardMaterial3D.new()
	mat.resource_name = "DungeonFloor"
	var base := "Textures/T_UnevenBrick_"
	mat.albedo_texture = _tex(base + "BaseColor.png", "floor_albedo", false)
	mat.normal_enabled = true
	mat.normal_texture = _tex("Textures/Normals Godot-Unity/T_UnevenBrick_Normal.png", "floor_normal", true) \
			if FileAccess.file_exists(SRC + "Textures/Normals Godot-Unity/T_UnevenBrick_Normal.png") \
			else _tex(base + "Normal.png", "floor_normal", true)
	mat.roughness_texture = _tex(base + "Roughness.png", "floor_rough", false)
	mat.albedo_color = TINT * Color(0.92, 0.9, 0.88)
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE * 0.7
	ResourceSaver.save(mat, OUT + "mat_floor.res", ResourceSaver.FLAG_COMPRESS)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for v in [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5),
			Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5)]:
		st.set_uv(Vector2(v.x + 0.5, v.z + 0.5))
		st.add_vertex(v)
	st.generate_tangents()
	var m := st.commit()
	m.surface_set_material(0, load(OUT + "mat_floor.res"))
	return m


func _find_mat(mis: Array, name: String) -> Material:
	for mi in mis:
		for s in (mi as MeshInstance3D).mesh.get_surface_count():
			var m := (mi as MeshInstance3D).mesh.surface_get_material(s)
			if m and m.resource_name == name:
				return m
	return null


func _material(key: String, src: Material) -> Material:
	if _mats.has(key):
		return _mats[key]
	var mat: StandardMaterial3D = (src as StandardMaterial3D).duplicate() if src is StandardMaterial3D else StandardMaterial3D.new()
	mat.albedo_color *= TINT
	for prop in ["albedo_texture", "normal_texture", "orm_texture", "roughness_texture", "metallic_texture", "ao_texture"]:
		var t = mat.get(prop)
		if t is Texture2D:
			mat.set(prop, _shrink((t as Texture2D).get_image(), key + "_" + prop.trim_suffix("_texture"), prop == "normal_texture"))
	var path := OUT + "mat_%s.res" % key
	ResourceSaver.save(mat, path, ResourceSaver.FLAG_COMPRESS)
	_mats[key] = load(path)
	return _mats[key]


func _tex(rel: String, name: String, normal: bool) -> Texture2D:
	return _shrink(Image.load_from_file(SRC + rel), name, normal)


func _shrink(src: Image, name: String, normal: bool) -> Texture2D:
	if src == null:
		return null
	var img := src.duplicate() as Image
	img.decompress()
	if img.get_width() > TEX:
		img.resize(TEX, TEX * img.get_height() / img.get_width(), Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps(normal)
	img.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_NORMAL if normal else Image.COMPRESS_SOURCE_GENERIC)
	var path := OUT + "tex_%s.res" % name
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
