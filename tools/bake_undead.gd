## 해골·유령(Fab 무료)을 게임용 장면으로 굽습니다.
##   godot --headless --path . -s tools/bake_undead.gd -- textures   (텍스처를 assets/dark에 줄여 저장)
##   godot --headless --path . --import
##   godot --headless --path . -s tools/bake_undead.gd -- scene
## 원본은 프로젝트 밖 F:/workspace/fab_downloads 에 둡니다 (zip은 _tools/ext.py로 필요한 것만 풂).
##   해골: Hotstrike Studio "Stylized Dark Fantasy Skeleton" (CC-BY). Character Creator 뼈대라 기사(Bento) 동작을 옮겨 붙임
##   유령: SR Studios Kerala "Dark Big Ghost (LITE)". 동작 2개(위아래 둥실, 두리번)를 나눠 씀
extends SceneTree

const Retarget = preload("res://tools/retarget.gd")
const FAB := "F:/workspace/fab_downloads/"
const SKEL_DIR := FAB + "skeleton/x/Stylized Skeleton/"
const KNIGHT := FAB + "src/knight/BentoPack_Knight_Free/01_Knight/Character/Knight/FBX/"
const GHOST_DIR := FAB + "ghost/"
const P := "CC_Base_"
## 엔진 동작 이름 → [기사 동작, 길이(0이면 그대로)]
const SKEL_ANIMS := {
	"idle": ["km_idle_combat", 0.0],
	"walk": ["km_walk_forward_inplace", 0.0],
	"sprint": ["run_inplace", 0.0],
	"crouch": ["km_idle_combat", 0.0],
	"die": ["km_death_backward_inplace", 1.4],
	"hit": ["km_hit_front", 0.5],
	"attack-melee-right": ["km_attack_slash", 0.6],
	"holding-right-shoot": ["km_attack_overhead", 0.7],
	"dodge": ["km_roll_forward_inplace", 0.5],
	"cast": ["km_attack_overhead", 0.7],
}
const LOOPING := ["idle", "walk", "sprint", "crouch"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0] == "textures":
		_textures()
	else:
		_skeleton()
		_ghost()
	quit()


func _textures() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/dark/skeleton"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/dark/ghost"))
	var t := SKEL_DIR + "Textures/T_Skeleton_Variant_1_"
	_shrink(t + "A_Albedo.png", "res://assets/dark/skeleton/albedo.png", 1024)
	_shrink(t + "N_OpenGL.png", "res://assets/dark/skeleton/normal.png", 1024)
	_shrink(t + "Emissive.png", "res://assets/dark/skeleton/emissive.png", 512)
	_shrink(GHOST_DIR + "x/Dirt_Skin_Base.png", "res://assets/dark/ghost/albedo.png", 1024)


func _shrink(src: String, dst: String, size: int) -> void:
	var img := Image.load_from_file(src)
	if img == null:
		push_error("없음: " + src)
		return
	img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	img.save_png(ProjectSettings.globalize_path(dst))
	print("tex ", dst)


# --- 해골 ---

func _map() -> Array:
	var m := [
		[P + "Waist", "spine_01", P + "Spine01", "spine_02"],
		[P + "Spine01", "spine_02", P + "Spine02", "spine_03"],
		[P + "Spine02", "spine_03", P + "NeckTwist01", "neck_01"],
		[P + "NeckTwist01", "neck_01", P + "Head", "head"],
	]
	for s in [["L", "l"], ["R", "r"]]:
		var S: String = s[0]
		var x: String = s[1]
		m.append_array([
			[P + S + "_Clavicle", "clavicle_" + x, P + S + "_Upperarm", "upperarm_" + x],
			[P + S + "_Upperarm", "upperarm_" + x, P + S + "_Forearm", "lowerarm_" + x],
			[P + S + "_Forearm", "lowerarm_" + x, P + S + "_Hand", "hand_" + x],
			[P + S + "_Hand", "hand_" + x, P + S + "_Mid1", "middle_01_" + x],
			[P + S + "_Thigh", "thigh_" + x, P + S + "_Calf", "calf_" + x],
			[P + S + "_Calf", "calf_" + x, P + S + "_Foot", "foot_" + x],
			[P + S + "_Foot", "foot_" + x, P + S + "_ToeBase", "ball_" + x],
		])
	return m


func _skeleton() -> void:
	var src := _fbx(KNIGHT + "SK_Knight.fbx")
	var src_skel := src.find_child("Skeleton3D", true, false) as Skeleton3D
	var root := Node3D.new()
	root.name = "Skeleton"
	var body := _fbx(SKEL_DIR + "Mesh/SKM_Skeleton_Var_1.fbx") as Node3D
	body.name = "Body"
	# 원본은 +X를 바라봄. 게임은 +Z가 앞
	body.rotation.y = -PI / 2
	root.add_child(body)
	var skel := body.find_child("Skeleton3D", true, false) as Skeleton3D
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/dark/skeleton/albedo.png")
	mat.normal_enabled = true
	mat.normal_texture = load("res://assets/dark/skeleton/normal.png")
	# 빛나는 부분 지도(금 간 곳)는 은은하게만
	mat.emission_enabled = true
	mat.emission_texture = load("res://assets/dark/skeleton/emissive.png")
	mat.emission = Color(1.0, 0.75, 0.3)
	mat.emission_energy_multiplier = 0.25
	mat.roughness = 0.8
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			m.set_surface_override_material(i, mat)
	var prefix := "Body/" + str(body.get_path_to(skel))
	var hips := [P + "Hip", "pelvis", P + "Spine02", "spine_03", P + "L_Thigh", "thigh_l", P + "R_Thigh", "thigh_r"]
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	root.add_child(ap)
	var lib := AnimationLibrary.new()
	var map := _map()
	for key in SKEL_ANIMS:
		var file := _find(KNIGHT + "Animations/", "A_Knight_%s.fbx" % SKEL_ANIMS[key][0])
		if file == "":
			push_error("동작 없음 " + SKEL_ANIMS[key][0])
			continue
		var s := _fbx(file)
		var sap := s.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var a := sap.get_animation(sap.get_animation_list()[0])
		var out: Animation = Retarget.retarget(src_skel, a, "Armature/Skeleton3D", skel, prefix, map, hips)
		var dur: float = SKEL_ANIMS[key][1]
		if dur > 0.0:
			_retime(out, dur / out.length)
		out.loop_mode = Animation.LOOP_LINEAR if key in LOOPING else Animation.LOOP_NONE
		lib.add_animation(key, out)
		s.free()
		print("skeleton ", key, " ok ", out.get_track_count(), " tracks")
	ap.add_animation_library("", lib)
	_add_sword(skel, root)
	_save(root, body, "res://assets/dark/skeleton/skeleton.scn")
	src.free()


## 기사 장면의 장검을 해골 오른손에 붙임. 쉬는 자세에서 기사 손에 대한 칼의 놓임(모델 공간)을 그대로 옮기고, 골반 높이 비율로 크기를 맞춤
func _add_sword(skel: Skeleton3D, root: Node3D) -> void:
	var knight := (load("res://assets/dark/knight/knight.scn") as PackedScene).instantiate() as Node3D
	var ks := knight.find_child("Skeleton3D", true, false) as Skeleton3D
	var sword := knight.find_child("SM_Knight_Longsword", true, false) as MeshInstance3D
	var att := sword.get_parent() as BoneAttachment3D
	var kx := _model_xf(ks, knight)
	var tx := _model_xf(skel, root)
	var k_hand := kx * ks.get_bone_global_rest(ks.find_bone("hand_r"))
	var k_sword := kx * ks.get_bone_global_rest(ks.find_bone(att.bone_name)) * sword.transform
	var t_hand := tx * skel.get_bone_global_rest(skel.find_bone(P + "R_Hand"))
	var k := (tx * skel.get_bone_global_rest(skel.find_bone(P + "Hip"))).origin.y / maxf((kx * ks.get_bone_global_rest(ks.find_bone("pelvis"))).origin.y, 0.001)
	# 모델 공간에서 손 위치 기준으로 칼을 놓고 크기만 키 비율로
	var want := Transform3D(k_sword.basis.scaled(Vector3.ONE * k), t_hand.origin + (k_sword.origin - k_hand.origin) * k)
	var holder := BoneAttachment3D.new()
	holder.name = "Weapon"
	holder.bone_name = P + "R_Hand"
	skel.add_child(holder)
	var w := MeshInstance3D.new()
	w.name = "Sword"
	w.mesh = sword.mesh
	for i in sword.mesh.get_surface_count():
		w.set_surface_override_material(i, sword.get_active_material(i))
	w.transform = t_hand.affine_inverse() * want
	holder.add_child(w)
	print("sword k=", k, " local=", w.transform)
	knight.free()


func _model_xf(n: Node, top: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var c := n
	while c != top and c != null:
		if c is Node3D:
			xf = (c as Node3D).transform * xf
		c = c.get_parent()
	return xf


# --- 유령 ---

func _ghost() -> void:
	var root := Node3D.new()
	root.name = "Ghost"
	var body := _fbx(GHOST_DIR + "big_ghost_lite.fbx") as Node3D
	body.name = "Body"
	root.add_child(body)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/dark/ghost/albedo.png")
	mat.roughness = 0.9
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.name == "Hat":
			m.visible = false  # 마녀 모자는 빼기
			continue
		for i in m.mesh.get_surface_count():
			m.set_surface_override_material(i, mat)
	var sap := body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var bob := sap.get_animation("idle_up_down")
	var look := sap.get_animation("look")
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	root.add_child(ap)
	var lib := AnimationLibrary.new()
	# 트랙 경로를 새 AnimationPlayer(root 아래) 기준으로 바꿈
	var rel := str(root.get_path_to(sap.get_node(sap.root_node))) + "/"
	for key in ["idle", "walk", "sprint", "crouch"]:
		var a := _repath(bob, rel)
		if key == "sprint":
			_retime(a, 0.6)
		a.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(key, a)
	# 두리번 동작의 앞부분을 짧게 줄여 공격·맞음·주문으로
	for key in ["attack-melee-right", "holding-right-shoot", "cast", "hit", "dodge", "die"]:
		var a := _repath(look, rel)
		var dur := {"hit": 0.4, "dodge": 0.5, "die": 1.2}.get(key, 0.7) as float
		_retime(a, dur / a.length)
		a.loop_mode = Animation.LOOP_NONE
		lib.add_animation(key, a)
	ap.add_animation_library("", lib)
	sap.get_parent().remove_child(sap)
	sap.free()
	_save(root, body, "res://assets/dark/ghost/ghost.scn")


func _repath(a: Animation, rel: String) -> Animation:
	var out := a.duplicate(true) as Animation
	for t in out.get_track_count():
		var p := str(out.track_get_path(t))
		out.track_set_path(t, NodePath(rel + p))
	return out


# --- 공통 ---

func _save(root: Node3D, body: Node3D, path: String) -> void:
	body.scene_file_path = ""
	for n in root.find_children("*", "", true, false):
		n.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	print("save ", path, " ", ResourceSaver.save(packed, path, ResourceSaver.FLAG_COMPRESS))
	root.free()


func _fbx(path: String) -> Node:
	var doc := FBXDocument.new()
	var st := FBXState.new()
	if doc.append_from_file(path, st) != OK:
		push_error("FBX 못 읽음: " + path)
		return null
	return doc.generate_scene(st)


func _find(dir: String, file: String) -> String:
	for sub in DirAccess.get_directories_at(dir):
		if FileAccess.file_exists(dir + sub + "/" + file):
			return dir + sub + "/" + file
	return ""


func _retime(a: Animation, f: float) -> void:
	for t in a.get_track_count():
		for k in a.track_get_key_count(t):
			a.track_set_key_time(t, k, a.track_get_key_time(t, k) * f)
	a.length *= f
