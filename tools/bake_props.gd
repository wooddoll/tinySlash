## 던전 장식 소품(Fab, AZ 3D studio "Stylized Modular Medieval Dungeon Kit")을 골라 굽습니다.
##   godot --headless --path . -s tools/bake_props.gd
## 원본 FBX 하나에 조각 176개가 데모 방처럼 놓여 있어서, 이름으로 골라 한 메시로 합칩니다.
## 결과: assets/dark/props/<이름>.res (바닥 가운데가 원점, 바닥면 y=0, 앞이 +Z, 1 유닛 = 1칸)
## 원본은 텍스처 없는 단색 재질이라, 색을 조금 어둡게 눌러 던전 돌색에 맞춥니다.
extends SceneTree

const SRC := "F:/workspace/fab_downloads/dungeon_kit/modular_stylized_dungeon_kit.fbx"
const OUT := "res://assets/dark/props/%s.res"
## 원본 단위 → 칸 (선반 너비 9.85 → 약 1칸)
const K := 0.1
## 소품 이름 → [조각 이름들, 크기 배율]
const PROPS := {
	"rack-swords": [["wood 4_005", "sword 1", "sword 2", "sword 3", "sword 4", "sword 5", "sword 6", "sword 7", "sword 8"], 1.0],
	"rack-shields": [["wood 4_004", "sheild 1", "sheild 2", "sheild 3", "sheild 4", "sheild 5", "sheild 6", "sheild 7", "sheild 8"], 1.0],
	"rack-spears": [["wood 4_001", "spear 1", "spear 2", "spear 3", "spear 4", "spear 5", "spear 6"], 1.3],
}
## 단색에 곱하는 색 (밝은 회색 칼날·갈색 나무를 조금 어둡고 따뜻하게)
const DARKEN := Color(0.7, 0.64, 0.6)


func _init() -> void:
	var doc := FBXDocument.new()
	var st := FBXState.new()
	if doc.append_from_file(SRC, st) != OK:
		push_error("FBX 못 읽음")
		quit(1)
		return
	var scene := doc.generate_scene(st)
	var by_name := {}
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		by_name[String(mi.name)] = mi
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/dark/props"))
	var mats := {}
	for prop in PROPS:
		var parts: Array = PROPS[prop][0]
		# 재질마다 면을 모음
		var groups := {}
		var box := AABB()
		var first := true
		for pn in parts:
			var mi := by_name.get(pn) as MeshInstance3D
			if mi == null:
				push_error("조각 없음: " + pn)
				continue
			var xf := _xf(mi, scene)
			var ab := xf * mi.get_aabb()
			box = ab if first else box.merge(ab)
			first = false
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s)
				var key := m.resource_name if m else "none"
				if not groups.has(key):
					groups[key] = [m, []]
				groups[key][1].append([mi.mesh, s, xf])
		var k: float = K * PROPS[prop][1]
		# 바닥 가운데로 옮기고 줄임
		var shift := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * k), Vector3.ZERO) \
				* Transform3D(Basis.IDENTITY, -Vector3(box.get_center().x, box.position.y, box.get_center().z))
		var out := ArrayMesh.new()
		for key in groups:
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			for e in groups[key][1]:
				tool.append_from(e[0], e[1], shift * (e[2] as Transform3D))
			tool.generate_normals()
			tool.commit(out)
			if not mats.has(key):
				var src := groups[key][0] as BaseMaterial3D
				var mat := StandardMaterial3D.new()
				mat.albedo_color = (src.albedo_color if src else Color.GRAY) * DARKEN
				mat.roughness = 0.85
				mats[key] = mat
			out.surface_set_material(out.get_surface_count() - 1, mats[key])
		var size := box.size * k
		print(prop, " size=", size.snapped(Vector3.ONE * 0.01), " surfaces=", out.get_surface_count(),
			" save=", ResourceSaver.save(out, OUT % prop, ResourceSaver.FLAG_COMPRESS))
	scene.free()
	quit()


func _xf(n: Node, top: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var c := n
	while c != top and c != null:
		if c is Node3D:
			xf = (c as Node3D).transform * xf
		c = c.get_parent()
	return xf
