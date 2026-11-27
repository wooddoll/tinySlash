## 다크 판타지 캐릭터(Fab, Bento Pack)를 게임용으로 가볍게 굽습니다.
## 원본(약 50만 삼각형, 4K 텍스처, 수백 개 동작)은 프로젝트 밖 F:/workspace/fab_downloads/src 에 두고,
## 줄인 결과만 res://assets/dark/<이름>/ 에 씁니다.
##   1단계: godot --headless --path . -s tools/bake_dark.gd -- textures   (텍스처 1024/512로 줄여 PNG 저장)
##   (그다음 godot --headless --path . --import)
##   2단계: godot --headless --path . -s tools/bake_dark.gd -- scene      (메시 줄이기 + 동작 골라 .scn 저장)
extends SceneTree

const OUT := "res://assets/dark/%s/"
const TEX_SIZE := 1024
const ORM_SIZE := 512
## 캐릭터 전체 목표 삼각형 수 (메시 부위마다 원래 크기 비율로 나눔)
const TARGET_TRIS := 16000

## 이름 → 무기, 동작 (엔진 이름: [원본 파일 이름, 길이 초(0이면 그대로)])
const CHARS := {
	"knight": {
		"weapon": "Longsword",
		"anims": {
			"idle": ["km_idle_combat", 0.0],
			"walk": ["km_walk_forward_inplace", 0.0],
			"sprint": ["run_inplace", 0.0],
			"crouch": ["km_idle_combat", 0.0],
			"die": ["km_death_backward_inplace", 1.4],
			"hit": ["km_hit_front", 0.5],
			"attack-melee-right": ["km_attack_slash", 0.6],
			"holding-right-shoot": ["km_attack_overhead", 0.7],
			"dodge": ["km_roll_forward_inplace", 0.5],
			"cast": ["cast_a_spell", 0.9],
		},
	},
	"witch": {
		"weapon": "Staff",
		"anims": {
			"idle": ["km_idle_combat", 0.0],
			"walk": ["km_walk_forward_inplace", 0.0],
			"sprint": ["run_inplace", 0.0],
			"crouch": ["km_idle_combat", 0.0],
			"die": ["km_death_backward_inplace", 1.4],
			"hit": ["km_hit_front_inplace", 0.5],
			"attack-melee-right": ["km_staff_sweep_2h", 0.6],
			"holding-right-shoot": ["km_cast_bolt", 0.7],
			"dodge": ["km_roll_forward_inplace", 0.5],
			"cast": ["km_cast_bolt", 0.8],
		},
	},
	"goblin": {
		"weapon": "Spear",
		"anims": {
			"idle": ["km_idle_combat", 0.0],
			"walk": ["km_walk_forward_inplace", 0.0],
			"sprint": ["run_inplace", 0.0],
			"crouch": ["km_idle_combat", 0.0],
			"die": ["km_death_forward_inplace", 1.4],
			"hit": ["km_hit_front_inplace", 0.5],
			"attack-melee-right": ["km_attack_thrust", 0.7],
			"holding-right-shoot": ["km_stab_frenzy", 0.8],
			"dodge": ["km_roll_forward_inplace", 0.5],
			"cast": ["km_stab_frenzy", 0.8],
		},
	},
}
const LOOPING := ["idle", "walk", "sprint", "crouch"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var phase := args[0] if args.size() > 0 else "scene"
	var only := args[1] if args.size() > 1 else ""
	for name in CHARS:
		if only != "" and name != only:
			continue
		if phase == "textures":
			_bake_textures(name)
		else:
			_bake_scene(name)
	quit()


func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1)


func _src(name: String) -> String:
	var c := _cap(name)
	var base := "F:/workspace/fab_downloads/src/%s/BentoPack_%s_Free/" % [name, c]
	for d in DirAccess.get_directories_at(base):
		if d.ends_with("_" + c):
			return base + d + "/"
	return base


# --- 1단계: 텍스처 ---

func _bake_textures(name: String) -> void:
	var out := OUT % name
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var c := _cap(name)
	var dirs := [_src(name) + "Character/%s/Textures/" % c, _src(name) + "Weapons/%s/%s/Textures/" % [CHARS[name].weapon, c]]
	for d in dirs:
		var common: String = d + "Common/"
		for f in DirAccess.get_files_at(common):
			if not f.ends_with("_BaseColor.png"):
				continue
			var part := f.trim_prefix("T_%s_" % c).trim_suffix("_BaseColor.png").to_lower()
			_shrink(common + f, out + part + "_albedo.png", TEX_SIZE)
			_shrink(d + "Unity/" + f.replace("_BaseColor", "_Normal_OpenGL"), out + part + "_normal.png", TEX_SIZE)
			# Unity 금속 지도(RGB 금속, A 매끄러움) → ORM (R 1, G 거칠기, B 금속)
			var ms := Image.load_from_file(d + "Unity/" + f.replace("_BaseColor", "_MetallicSmoothness"))
			if ms:
				ms.convert(Image.FORMAT_RGBA8)
				ms.resize(ORM_SIZE, ORM_SIZE, Image.INTERPOLATE_LANCZOS)
				var orm := Image.create(ORM_SIZE, ORM_SIZE, false, Image.FORMAT_RGB8)
				for y in ORM_SIZE:
					for x in ORM_SIZE:
						var p := ms.get_pixel(x, y)
						orm.set_pixel(x, y, Color(1.0, 1.0 - p.a, p.r))
				orm.save_png(ProjectSettings.globalize_path(out + part + "_orm.png"))
			print(name, ": ", part)


func _shrink(src: String, dst: String, size: int) -> void:
	var img := Image.load_from_file(src)
	if img == null:
		push_error("없음: " + src)
		return
	img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	img.save_png(ProjectSettings.globalize_path(dst))


# --- 2단계: 메시와 동작 ---

func _load_fbx(path: String) -> Node:
	var doc := FBXDocument.new()
	var st := FBXState.new()
	if doc.append_from_file(path, st) != OK:
		push_error("FBX 못 읽음: " + path)
		return null
	return doc.generate_scene(st)


func _bake_scene(name: String) -> void:
	var c := _cap(name)
	var out := OUT % name
	var src := _load_fbx(_src(name) + "Character/%s/FBX/SK_%s.fbx" % [c, c])
	var skel := src.find_child("Skeleton3D", true, false) as Skeleton3D
	var parts: Array[MeshInstance3D] = []
	var weapons: Array[MeshInstance3D] = []
	for n in skel.get_children():
		if n is MeshInstance3D:
			parts.append(n)
	# 무기: 같은 뼈대에 입힌 메시 (weapon_r 뼈 100%)
	var wsrc := _load_fbx(_src(name) + "Weapons/%s/%s/FBX/Props/SK_%s_%s.fbx" % [CHARS[name].weapon, c, c, CHARS[name].weapon])
	if wsrc:
		for n in wsrc.find_children("*", "MeshInstance3D", true, false):
			parts.append(n)
			weapons.append(n)
	var total := 0
	for p in parts:
		total += _tri_count(p.mesh)
	var before := 0
	var after := 0
	var new_meshes: Array[MeshInstance3D] = []
	for p in parts:
		var tris := _tri_count(p.mesh)
		var target := maxi(300, int(float(TARGET_TRIS) * tris / total))
		if p in weapons:
			target = tris  # 가는 자루는 줄이면 끊어지므로 그대로 (5~6천 개)
		var mi := MeshInstance3D.new()
		mi.name = p.name
		mi.mesh = _simplify(p.mesh, target, out)
		if p in weapons:
			# 무기는 스킨 대신 weapon_r 뼈에 붙임 (묶음 자세 = 뼈 기준 위치)
			mi.mesh = _unskinned(mi.mesh)
			mi.transform = _bind_pose(p, "weapon_r")
			mi.set_meta("bone", "weapon_r")
		else:
			mi.skin = _named_skin(p, skel)
		before += tris
		after += _tri_count(mi.mesh)
		new_meshes.append(mi)
	print("%s: %d → %d 삼각형" % [name, before, after])
	# 새 장면: Root / Armature / Skeleton3D / 메시들, Root / AnimationPlayer
	var root := Node3D.new()
	root.name = c
	var arm := Node3D.new()
	arm.name = "Armature"
	arm.transform = (skel.get_parent() as Node3D).transform
	root.add_child(arm)
	var sk := skel.duplicate() as Skeleton3D
	for ch in sk.get_children():
		sk.remove_child(ch)
		ch.free()
	sk.name = "Skeleton3D"
	arm.add_child(sk)
	for mi in new_meshes:
		if mi.has_meta("bone"):
			var ba := BoneAttachment3D.new()
			ba.name = "Weapon"
			ba.bone_name = mi.get_meta("bone")
			mi.remove_meta("bone")
			sk.add_child(ba)
			ba.add_child(mi)
			continue
		sk.add_child(mi)
		mi.skeleton = NodePath("..")
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	root.add_child(ap)
	var lib := AnimationLibrary.new()
	var adir := _src(name) + "Character/%s/FBX/Animations/" % c
	var anims: Dictionary = CHARS[name].anims
	for key in anims:
		var file := _find_anim(adir, "A_%s_%s.fbx" % [c, anims[key][0]])
		var a := _load_anim(file)
		if a == null:
			push_error("동작 없음: " + str(anims[key]))
			continue
		_strip_root_motion(a)
		_drop_weapon_scale(a)
		var dur: float = anims[key][1]
		if dur > 0.0:
			_retime(a, dur / a.length)
		a.loop_mode = Animation.LOOP_LINEAR if key in LOOPING else Animation.LOOP_NONE
		lib.add_animation(key, a)
	ap.add_animation_library("", lib)
	_own(root, root)
	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, out + name + ".scn", ResourceSaver.FLAG_COMPRESS)
	print(name, " 저장: ", err)
	root.free()
	src.free()
	if wsrc:
		wsrc.free()


func _bind_pose(p: MeshInstance3D, bone: String) -> Transform3D:
	var own := p.get_parent() as Skeleton3D
	for b in p.skin.get_bind_count():
		if own.get_bone_name(p.skin.get_bind_bone(b)) == bone:
			return p.skin.get_bind_pose(b)
	push_error("묶음 뼈 없음: " + bone)
	return Transform3D.IDENTITY


func _unskinned(m: ArrayMesh) -> ArrayMesh:
	var am := ArrayMesh.new()
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		a[Mesh.ARRAY_BONES] = null
		a[Mesh.ARRAY_WEIGHTS] = null
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		am.surface_set_material(s, m.surface_get_material(s))
	return am


## 뼈 번호로 묶인 스킨을 캐릭터 뼈대의 같은 이름 뼈 번호로 바꿈 (무기 파일은 번호 순서가 다름)
func _named_skin(p: MeshInstance3D, skel: Skeleton3D) -> Skin:
	var own := p.get_parent() as Skeleton3D
	if p.skin == null or own == null:
		return p.skin
	var sk := p.skin.duplicate() as Skin
	for b in sk.get_bind_count():
		var bone_name := own.get_bone_name(sk.get_bind_bone(b))
		var idx := skel.find_bone(bone_name)
		if idx >= 0:
			sk.set_bind_bone(b, idx)
	return sk


func _own(n: Node, owner: Node) -> void:
	for ch in n.get_children():
		ch.owner = owner
		_own(ch, owner)


func _find_anim(dir: String, file: String) -> String:
	for sub in DirAccess.get_directories_at(dir):
		if FileAccess.file_exists(dir + sub + "/" + file):
			return dir + sub + "/" + file
	return ""


func _load_anim(path: String) -> Animation:
	if path == "":
		return null
	var s := _load_fbx(path)
	var ap := s.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var a: Animation = null
	if ap and ap.get_animation_list().size() > 0:
		a = ap.get_animation(ap.get_animation_list()[0]).duplicate(true)
	s.free()
	return a


## 뿌리 뼈의 위치 이동(루트 모션)을 뺌. 이동은 게임이 함
func _strip_root_motion(a: Animation) -> void:
	for i in range(a.get_track_count() - 1, -1, -1):
		if a.track_get_type(i) == Animation.TYPE_POSITION_3D and String(a.track_get_path(i)).ends_with(":root"):
			a.remove_track(i)


func _drop_weapon_scale(a: Animation) -> void:
	for i in range(a.get_track_count() - 1, -1, -1):
		if a.track_get_type(i) == Animation.TYPE_SCALE_3D:
			a.remove_track(i)


## 시간을 f배로 (f < 1이면 빨라짐)
func _retime(a: Animation, f: float) -> void:
	for t in a.get_track_count():
		var n := a.track_get_key_count(t)
		var order: Array = range(n) if f <= 1.0 else range(n - 1, -1, -1)
		for k in order:
			a.track_set_key_time(t, k, a.track_get_key_time(t, k) * f)
	a.length *= f


func _tri_count(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		n += m.surface_get_array_index_len(s) / 3
	return n


## 삼각형을 target개쯤으로 줄이고, 쓰지 않는 꼭짓점을 빼서 새 메시로
func _simplify(m: Mesh, target: int, out: String) -> ArrayMesh:
	var am := ArrayMesh.new()
	for s in m.get_surface_count():
		var arrays := m.surface_get_arrays(s)
		var idx := _lod_indices(arrays, target * 3)
		var flags: int = m.surface_get_format(s)
		var compact := _compact(arrays, idx)
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, compact, [], {}, flags & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
		am.surface_set_material(am.get_surface_count() - 1, _material(m.surface_get_material(s), out))
	return am


## Godot 가져오기와 같은 LOD 만들기(이음매를 붙여서 줄임)로 목표에 가장 가까운 단계를 고름
func _lod_indices(arrays: Array, want: int) -> PackedInt32Array:
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	im.generate_lods(60.0, 25.0, [])
	var best: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for l in im.get_surface_lod_count(0):
		var li := im.get_surface_lod_indices(0, l)
		if li.size() < 3:
			continue
		# 목표에 가장 가까운 단계 (비율로)
		if absf(log(float(li.size()) / want)) < absf(log(float(best.size()) / want)):
			best = li
	return best


func _compact(arrays: Array, idx: PackedInt32Array) -> Array:
	var remap := {}
	var order: PackedInt32Array = []
	var new_idx := PackedInt32Array()
	new_idx.resize(idx.size())
	for i in idx.size():
		var v := idx[i]
		if not remap.has(v):
			remap[v] = order.size()
			order.append(v)
		new_idx[i] = remap[v]
	var res := []
	res.resize(Mesh.ARRAY_MAX)
	var bones_per := 4
	if arrays[Mesh.ARRAY_BONES] != null and arrays[Mesh.ARRAY_VERTEX] != null:
		bones_per = arrays[Mesh.ARRAY_BONES].size() / arrays[Mesh.ARRAY_VERTEX].size()
	for k in Mesh.ARRAY_MAX:
		var src = arrays[k]
		if src == null or k == Mesh.ARRAY_INDEX:
			continue
		var per := 1
		match k:
			Mesh.ARRAY_TANGENT: per = 4
			Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS: per = bones_per
		var dst = src.duplicate()
		dst.resize(order.size() * per)
		for i in order.size():
			for j in per:
				dst[i * per + j] = src[order[i] * per + j]
		res[k] = dst
	res[Mesh.ARRAY_INDEX] = new_idx
	return res


## 원래 재질 이름(M_Knight_Body)으로 줄인 텍스처를 찾아 ORM 재질을 만듦
func _material(src: Material, out: String) -> Material:
	var part := ""
	if src:
		var n := src.resource_name
		part = n.get_slice("_", n.get_slice_count("_") - 1).to_lower()
	var mat := ORMMaterial3D.new()
	mat.resource_name = part
	var alb := out + part + "_albedo.png"
	if part == "" or not ResourceLoader.exists(alb):
		push_warning("텍스처 없음: " + alb)
		return mat
	mat.albedo_texture = load(alb)
	mat.normal_enabled = true
	mat.normal_texture = load(out + part + "_normal.png")
	mat.orm_texture = load(out + part + "_orm.png")
	# 어두운 던전에는 비칠 것이 없어 금속이 까맣게 보임 → 금속 느낌을 줄여 등불 빛을 받게
	mat.metallic = 0.4
	return mat
