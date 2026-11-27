## 이미 구운 다크 판타지 캐릭터(.scn)에 무료 동작 팩의 동작을 옮겨 더하거나 바꿉니다.
##   godot --headless --path . -s tools/bake_extra_anims.gd [-- knight witch ...]
## bake_dark / bake_undead / bake_zombie 로 캐릭터를 다시 구웠다면 이 스크립트도 다시 돌려야 합니다.
## 동작 출처 (프로젝트 밖 F:/workspace/fab_downloads/godot/ 에 둠):
##   ual: Quaternius "Universal Animation Library" Standard (CC0) — Rigify 뼈대(DEF-…)
##   rpg: Explosive LLC "RPG Animations GLB FREE" (MIT) — B_… 뼈대
## 대상 뼈대는 Bento(pelvis, spine_01 …)나 Character Creator(CC_Base_…) 둘 다 됩니다.
extends SceneTree

const Retarget = preload("res://tools/retarget.gd")
const SRC := {
	"ual": "F:/workspace/fab_downloads/godot/quaternius_ual/Animation Library[Standard]/Godot/AnimationLibrary_Godot_Standard.glb",
	"rpg": "F:/workspace/fab_downloads/godot/explosive_rpg/Unarmed.glb",
}
## 공통 뼈 이름(Bento) → 원본 팩 뼈 이름. 왼쪽/오른쪽은 {x}/{X}로 적음
const SRC_BONES := {
	"ual": {
		"pelvis": "DEF-hips", "spine_01": "DEF-spine.001", "spine_02": "DEF-spine.002", "spine_03": "DEF-spine.003",
		"neck_01": "DEF-neck", "head": "DEF-head",
		"clavicle_{x}": "DEF-shoulder.{X}", "upperarm_{x}": "DEF-upper_arm.{X}", "lowerarm_{x}": "DEF-forearm.{X}",
		"hand_{x}": "DEF-hand.{X}", "middle_01_{x}": "DEF-f_middle.01.{X}",
		"thigh_{x}": "DEF-thigh.{X}", "calf_{x}": "DEF-shin.{X}", "foot_{x}": "DEF-foot.{X}", "ball_{x}": "DEF-toe.{X}",
	},
	"rpg": {
		"pelvis": "B_Pelvis", "spine_01": "B_Spine", "spine_02": "B_Spine1", "spine_03": "B_Spine2",
		"neck_01": "B_Neck", "head": "B_Head",
		"clavicle_{x}": "B_{X}_Clavicle", "upperarm_{x}": "B_{X}_UpperArm", "lowerarm_{x}": "B_{X}_Forearm",
		"hand_{x}": "B_{X}_Hand", "middle_01_{x}": "B_{X}_Finger2",
		"thigh_{x}": "B_{X}_Thigh", "calf_{x}": "B_{X}_Calf", "foot_{x}": "B_{X}_Foot", "ball_{x}": "B_{X}_Toe0",
	},
}
## Character Creator 뼈 이름 (CC_Base_<이름> 또는 CC_Base_<이름>_<번호>)
const CC_BONES := {
	"pelvis": "Hip", "spine_01": "Waist", "spine_02": "Spine01", "spine_03": "Spine02", "neck_01": "NeckTwist01", "head": "Head",
	"clavicle_{x}": "{X}_Clavicle", "upperarm_{x}": "{X}_Upperarm", "lowerarm_{x}": "{X}_Forearm", "hand_{x}": "{X}_Hand",
	"middle_01_{x}": "{X}_Mid1", "thigh_{x}": "{X}_Thigh", "calf_{x}": "{X}_Calf", "foot_{x}": "{X}_Foot", "ball_{x}": "{X}_ToeBase",
}
## 방향 맞추기 사슬: [뼈, 자식]
const CHAIN := [
	["spine_01", "spine_02"], ["spine_02", "spine_03"], ["spine_03", "neck_01"], ["neck_01", "head"],
	["clavicle_{x}", "upperarm_{x}"], ["upperarm_{x}", "lowerarm_{x}"], ["lowerarm_{x}", "hand_{x}"], ["hand_{x}", "middle_01_{x}"],
	["thigh_{x}", "calf_{x}"], ["calf_{x}", "foot_{x}"], ["foot_{x}", "ball_{x}"],
]
## 모든 인간형에게 더하는 동작: 엔진 이름 → [팩, 원본 동작, 길이 초(0이면 그대로)]
##   crouch: 넘어짐(prone) 상태 · hurt: 체력 절반 이하일 때 서 있는 자세 · jump: 바깥 시험장 점프
const COMMON := {
	"crouch": ["ual", "Crouch_Idle_Loop", 0.0],
	"hurt": ["rpg", "UnarmedIdleInjured", 0.0],
	"jump": ["rpg", "UnarmedJump", 0.0],
}
## 캐릭터별로 더하거나 바꾸는 동작
const CHARS := {
	"knight": {},
	"witch": {},
	"goblin": {},
	"skeleton": {},
	# 좀비: 기사 전투 자세 대신 비틀거리는 몸짓과 맨손 휘두르기
	"zombie": {
		"idle": ["rpg", "UnarmedIdleInjured", 0.0],
		"walk": ["rpg", "UnarmedWalkInjured", 0.0],
		"sprint": ["rpg", "UnarmedWalkInjured", 0.62],
		"hit": ["rpg", "UnarmedGetHitF1", 0.0],
		"attack-melee-right": ["rpg", "UnarmedAttackR2", 0.0],
		"holding-right-shoot": ["rpg", "UnarmedAttackL1", 0.0],
		"cast": ["rpg", "UnarmedAttackR3", 0.0],
		"die": ["rpg", "UnarmedDeath1", 0.0],
	},
}
const LOOPING := ["idle", "walk", "sprint", "crouch", "hurt"]

var _src := {}  # 팩 → [장면, Skeleton3D, AnimationPlayer, 트랙 앞부분]


func _init() -> void:
	var only := OS.get_cmdline_user_args()
	for name in CHARS:
		if not only.is_empty() and not name in only:
			continue
		_bake(name)
	for k in _src:
		(_src[k][0] as Node).free()
	quit()


func _source(pack: String) -> Array:
	if _src.has(pack):
		return _src[pack]
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(SRC[pack], st) != OK:
		push_error("동작 팩 못 읽음: " + SRC[pack])
		return []
	var scene := doc.generate_scene(st)
	var sk := scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var ap := scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var root := ap.get_node(ap.root_node)
	_src[pack] = [scene, sk, ap, str(root.get_path_to(sk))]
	return _src[pack]


func _side(s: String, x: String) -> String:
	return s.replace("{x}", x).replace("{X}", x.to_upper())


## 공통 이름 → 대상 뼈대의 실제 뼈 이름 ("" 이면 없음)
func _tgt_bone(sk: Skeleton3D, canon: String, cc_key: String, x: String) -> String:
	if sk.find_bone(canon) >= 0:
		return canon
	if not CC_BONES.has(cc_key):
		return ""
	var want := "CC_Base_" + _side(CC_BONES[cc_key], x)
	for i in sk.get_bone_count():
		var b := sk.get_bone_name(i)
		if b == want or (b.begins_with(want + "_") and b.substr(want.length() + 1).is_valid_int()):
			return b
	return ""


## 공통 이름 하나를 [대상, 원본] 이름으로
func _pair(sk: Skeleton3D, pack: String, key: String, x: String) -> Array:
	return [_tgt_bone(sk, _side(key, x), key, x), _side(SRC_BONES[pack][key], x)]


func _bake(name: String) -> void:
	var path := "res://assets/dark/%s/%s.scn" % [name, name]
	var ps := load(path) as PackedScene
	if ps == null:
		push_error("캐릭터 없음: " + path)
		return
	var root := ps.instantiate()
	# 원본 모델에 딸린 플레이어도 있을 수 있어 idle이 있는 것을 고름
	var ap: AnimationPlayer = null
	for n in root.find_children("*", "AnimationPlayer", true, false):
		if (n as AnimationPlayer).has_animation("idle"):
			ap = n
	var lib := ap.get_animation_library("")
	# 대상 트랙 앞부분은 이미 있는 idle 동작에서 읽음 ("Body/…/Skeleton3D")
	var idle := lib.get_animation("idle")
	var prefix := String(idle.track_get_path(0)).get_slice(":", 0)
	var sk := ap.get_node(ap.root_node).get_node(prefix) as Skeleton3D
	var want: Dictionary = COMMON.duplicate()
	want.merge(CHARS[name], true)
	for key in want:
		var spec: Array = want[key]
		var src := _source(spec[0])
		if src.is_empty():
			continue
		var src_anim := (src[2] as AnimationPlayer).get_animation(spec[1])
		if src_anim == null:
			push_error("원본 동작 없음: %s %s" % spec)
			continue
		var map := []
		for c in CHAIN:
			for x in (["l", "r"] if c[0].contains("{x}") else [""]):
				var a := _pair(sk, spec[0], c[0], x)
				var b := _pair(sk, spec[0], c[1], x)
				if a[0] != "" and b[0] != "":
					map.append([a[0], a[1], b[0], b[1]])
		var hp := _pair(sk, spec[0], "pelvis", "")
		var up := _pair(sk, spec[0], "spine_03", "")
		var tl := _pair(sk, spec[0], "thigh_{x}", "l")
		var tr := _pair(sk, spec[0], "thigh_{x}", "r")
		var hips := [hp[0], hp[1], up[0], up[1], tl[0], tl[1], tr[0], tr[1]]
		var out := Retarget.retarget(src[1], src_anim, src[3], sk, prefix, map, hips)
		_in_place(out, prefix + ":" + hp[0])
		if spec[2] > 0.0:
			_retime(out, spec[2])
		out.loop_mode = Animation.LOOP_LINEAR if key in LOOPING else Animation.LOOP_NONE
		if lib.has_animation(key):
			lib.remove_animation(key)
		lib.add_animation(key, out)
		print(name, " ", key, " <- ", spec[0], ":", spec[1], " ", snappedf(out.length, 0.01), "s bones=", map.size())
	var packed := PackedScene.new()
	packed.pack(root)
	print(name, " save=", ResourceSaver.save(packed, path, ResourceSaver.FLAG_COMPRESS))
	root.free()


## 골반이 앞뒤·옆으로 흘러가지 않게 (게임이 자리를 정함). 첫 프레임 자리에 고정하고 높이만 둠
func _in_place(anim: Animation, hip_path: String) -> void:
	for t in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_POSITION_3D or String(anim.track_get_path(t)) != hip_path:
			continue
		var first: Vector3 = anim.track_get_key_value(t, 0)
		for k in anim.track_get_key_count(t):
			var v: Vector3 = anim.track_get_key_value(t, k)
			anim.track_set_key_value(t, k, Vector3(first.x, v.y, first.z))


func _retime(anim: Animation, length: float) -> void:
	var k := length / anim.length
	for t in anim.get_track_count():
		for i in range(anim.track_get_key_count(t) - 1, -1, -1):
			anim.track_set_key_time(t, i, anim.track_get_key_time(t, i) * k)
	anim.length = length
