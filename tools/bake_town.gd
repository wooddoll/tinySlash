## Quaternius "Medieval Village MegaKit" (Standard, CC0)의 집 조각(벽·모서리·지붕·문·창·소품)을 마을 크기로 굽습니다.
##   godot --headless --path . -s tools/bake_town.gd
## 원본은 F:/workspace/fab_downloads/godot/quaternius_village/ 에 둡니다 (저장소에 넣지 않음, docs/assets.md).
## 결과: assets/quaternius/town/<원본 이름>.res (ArrayMesh, 재질별 면 하나) + mat_*.res, tex_*.res
## 원본의 원점과 방향은 그대로 두고 크기만 SCALE배 (원본 2m 벽 = 1.4칸, 사람 키 1.28칸에 맞춤).
## 그래서 조각끼리 원본 키트의 2m 격자 그대로 맞물립니다 (scripts/town_builder.gd가 조립).
extends SceneTree

const SRC := "F:/workspace/fab_downloads/godot/quaternius_village/x/Medieval Village MegaKit[Standard]/"
const OUT := "res://assets/quaternius/town/"
const SCALE := 0.7
const TEX := 1024
const PIECES := [
	"Wall_Plaster_Straight", "Wall_Plaster_Door_Round", "Wall_Plaster_Window_Wide_Round",
	"Wall_Plaster_Window_Thin_Round", "Wall_Plaster_WoodGrid",
	"Wall_UnevenBrick_Straight", "Wall_UnevenBrick_Door_Round", "Wall_UnevenBrick_Window_Wide_Round",
	"Wall_UnevenBrick_Window_Thin_Round",
	"Corner_Exterior_Wood", "Corner_Exterior_Brick",
	"Roof_RoundTiles_4x4", "Roof_RoundTiles_4x6", "Roof_RoundTiles_4x8",
	"Roof_RoundTiles_6x6", "Roof_RoundTiles_6x8", "Roof_RoundTiles_6x10",
	"Roof_RoundTiles_8x8", "Roof_RoundTiles_8x10",
	"Roof_Front_Brick4", "Roof_Front_Brick6", "Roof_Front_Brick8",
	"Door_1_Round", "Window_Wide_Round1", "Window_Thin_Round1",
	"WindowShutters_Wide_Round_Open", "WindowShutters_Thin_Round_Open",
	"Wall_BottomCover", "Prop_Chimney", "Prop_Wagon", "Prop_Crate",
	"Prop_WoodenFence_Single", "Prop_WoodenFence_Extension1", "Prop_Support", "Prop_Vine1", "Prop_Vine4",
]

var _mats := {}


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var ok := 0
	for name in PIECES:
		var m := _bake(name)
		if m and ResourceSaver.save(m, OUT + name + ".res", ResourceSaver.FLAG_COMPRESS) == OK:
			ok += 1
			print(name, " ", m.get_aabb())
	print("구움 %d/%d" % [ok, PIECES.size()])
	quit()


func _bake(file: String) -> ArrayMesh:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(SRC + "glTF/" + file + ".gltf", st) != OK:
		push_error("못 읽음: " + file)
		return null
	var scene := doc.generate_scene(st)
	var shift := Transform3D(Basis.from_scale(Vector3.ONE * SCALE), Vector3.ZERO)
	var groups := {}
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var xf := shift * _xf(mi, scene)
		var mesh := (mi as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			var key := m.resource_name if m else "none"
			if not groups.has(key):
				groups[key] = [m, []]
			groups[key][1].append([mesh, s, xf])
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


func _material(key: String, src: Material) -> Material:
	if _mats.has(key):
		return _mats[key]
	var mat: StandardMaterial3D = (src as StandardMaterial3D).duplicate() if src is StandardMaterial3D else StandardMaterial3D.new()
	for prop in ["albedo_texture", "normal_texture", "orm_texture", "roughness_texture", "metallic_texture", "ao_texture"]:
		var t = mat.get(prop)
		if t is Texture2D:
			mat.set(prop, _shrink((t as Texture2D).get_image(), key + "_" + prop.trim_suffix("_texture"), prop == "normal_texture"))
	var path := OUT + "mat_%s.res" % key.validate_filename()
	ResourceSaver.save(mat, path, ResourceSaver.FLAG_COMPRESS)
	_mats[key] = load(path)
	return _mats[key]


func _shrink(src: Image, name: String, normal: bool) -> Texture2D:
	if src == null:
		return null
	var path := OUT + "tex_%s.res" % name.validate_filename()
	var img := src.duplicate() as Image
	img.decompress()
	if img.get_width() > TEX:
		img.resize(TEX, TEX * img.get_height() / img.get_width(), Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps(normal)
	img.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_NORMAL if normal else Image.COMPRESS_SOURCE_GENERIC)
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
