## 좀비(Fab, Hotstrike Studio, Character Creator 뼈대)에 고블린(Bento Pack) 동작을 옮겨 굽습니다.
##   godot --headless --path . -s tools/bake_zombie.gd
## 원본 동작은 F:/workspace/fab_downloads/src/goblin 에서 읽고, 결과는 assets/dark/zombie/zombie.scn
extends SceneTree

const Retarget = preload("res://tools/retarget.gd")
const GOBLIN := "F:/workspace/fab_downloads/src/goblin/BentoPack_Goblin_Free/"
const P := "CC_Base_"
## 엔진 동작 이름 → [고블린 동작, 길이(0이면 그대로)]
const ANIMS := {
	"idle": ["km_idle_combat", 0.0],
	"walk": ["km_walk_forward_inplace", 0.0],
	"sprint": ["run_inplace", 0.0],
	"crouch": ["km_idle_combat", 0.0],
	"die": ["km_death_forward_inplace", 1.4],
	"hit": ["km_hit_front_inplace", 0.5],
	"attack-melee-right": ["km_stab_frenzy", 0.8],
	"holding-right-shoot": ["km_stab_frenzy", 0.8],
	"dodge": ["km_roll_forward_inplace", 0.5],
	"cast": ["km_stab_frenzy", 0.8],
}
const LOOPING := ["idle", "walk", "sprint", "crouch"]


func _map() -> Array:
	var m := [
		[P + "Waist_99", "spine_01", P + "Spine01_98", "spine_02"],
		[P + "Spine01_98", "spine_02", P + "Spine02_97", "spine_03"],
		[P + "Spine02_97", "spine_03", P + "NeckTwist01_44", "neck_01"],
		[P + "NeckTwist01_44", "neck_01", P + "Head_42", "head"],
	]
	for s in [["L", "l", "68", "67", "64", "63", "50", "15", "12", "8", "7"], ["R", "r", "92", "91", "90", "89", "76", "30", "29", "25", "23"]]:
		var S: String = s[0]
		var x: String = s[1]
		m.append_array([
			[P + S + "_Clavicle_" + s[2], "clavicle_" + x, P + S + "_Upperarm_" + s[3], "upperarm_" + x],
			[P + S + "_Upperarm_" + s[3], "upperarm_" + x, P + S + "_Forearm_" + s[4], "lowerarm_" + x],
			[P + S + "_Forearm_" + s[4], "lowerarm_" + x, P + S + "_Hand_" + s[5], "hand_" + x],
			[P + S + "_Hand_" + s[5], "hand_" + x, P + S + "_Mid1_" + s[6], "middle_01_" + x],
			[P + S + "_Thigh_" + s[7], "thigh_" + x, P + S + "_Calf_" + s[8], "calf_" + x],
			[P + S + "_Calf_" + s[8], "calf_" + x, P + S + "_Foot_" + s[9], "foot_" + x],
			[P + S + "_Foot_" + s[9], "foot_" + x, P + S + "_ToeBase_" + s[10], "ball_" + x],
		])
	return m


func _init() -> void:
	var base: String = GOBLIN + DirAccess.get_directories_at(GOBLIN)[0] + "/Character/Goblin/FBX/"
	var src := _fbx(base + "SK_Goblin.fbx")
	var src_skel := src.find_child("Skeleton3D", true, false) as Skeleton3D
	var body_scene := load("res://assets/dark/zombie/szombie.glb") as PackedScene
	var root := Node3D.new()
	root.name = "Zombie"
	var body := body_scene.instantiate() as Node3D
	body.name = "Body"
	root.add_child(body)
	var skel := body.find_child("Skeleton3D", true, false) as Skeleton3D
	# 같은 모양의 움직이지 않는 메시(스킨 없음)는 숨김
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).skin == null:
			(mi as MeshInstance3D).visible = false
	var prefix := "Body/" + str(body.get_path_to(skel))
	var hips := [P + "Hip_100", "pelvis", P + "Spine02_97", "spine_03", P + "L_Thigh_15", "thigh_l", P + "R_Thigh_30", "thigh_r"]
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	root.add_child(ap)
	var lib := AnimationLibrary.new()
	var map := _map()
	for key in ANIMS:
		var file := _find(base + "Animations/", "A_Goblin_%s.fbx" % ANIMS[key][0])
		var s := _fbx(file)
		var sap := s.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var a := sap.get_animation(sap.get_animation_list()[0])
		var out: Animation = Retarget.retarget(src_skel, a, "Armature/Skeleton3D", skel, prefix, map, hips)
		var dur: float = ANIMS[key][1]
		if dur > 0.0:
			_retime(out, dur / out.length)
		out.loop_mode = Animation.LOOP_LINEAR if key in LOOPING else Animation.LOOP_NONE
		lib.add_animation(key, out)
		s.free()
		print(key, " ok ", out.get_track_count(), " tracks")
	ap.add_animation_library("", lib)
	# glb 장면을 통째로 이 장면에 담음 (숨김 같은 바꾼 값이 저장되게)
	body.scene_file_path = ""
	for n in body.find_children("*", "", true, false):
		n.owner = root
	body.owner = root
	ap.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	print("save ", ResourceSaver.save(packed, "res://assets/dark/zombie/zombie.scn", ResourceSaver.FLAG_COMPRESS))
	root.free()
	src.free()
	quit()


func _fbx(path: String) -> Node:
	var doc := FBXDocument.new()
	var st := FBXState.new()
	doc.append_from_file(path, st)
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
