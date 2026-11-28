## Quaternius "Modular Character Outfits - Fantasy" + "Universal Base Characters" (Standard, CC0)로
## 직업 캐릭터(예전 KayKit 모험가 자리)를 만들어 굽습니다.
##   godot --headless --path . -s tools/bake_heroes.gd [-- ranger rogue ...]
## 원본은 F:/workspace/fab_downloads/godot/quaternius_outfits, quaternius_base 에 둡니다 (저장소에 넣지 않음).
## 무료판 옷에는 머리가 없어서, 기본 몸(Superhero)에서 머리·목 면만 잘라 옷 뼈대에 붙이고 머리카락을 얹습니다.
## 동작은 Universal Animation Library(같은 사람 뼈대, UAL)와 Explosive RPG 팩에서 옮깁니다 (tools/retarget.gd).
## 결과: assets/quaternius/heroes/<이름>/<이름>.scn (AnimationPlayer에 엔진 동작 이름 idle, walk …)
extends SceneTree

const Retarget = preload("res://tools/retarget.gd")
const OUTFITS := "F:/workspace/fab_downloads/godot/quaternius_outfits/x/Modular Character Outfits - Fantasy[Standard]/Exports/glTF (Godot-Unreal)/Outfits/"
const BASE := "F:/workspace/fab_downloads/godot/quaternius_base/x/Universal Base Characters[Standard]/"
const HAIR := BASE + "Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)/"
const OUT := "res://assets/quaternius/heroes/"
const TEX := 1024
## 이름 → 옷, 몸(m/f), 머리카락들, 옷 색, 무기 [MegaKit 소품, 크기]
const HEROES := {
	"ranger": {"outfit": "Male_Ranger", "body": "m", "hair": [], "hair_color": Color(0.35, 0.25, 0.18), "tint": Color(1, 1, 1), "weapon": ["Sword_Bronze", 0.8]},
	"rogue": {"outfit": "Female_Ranger", "body": "f", "hair": [], "hair_color": Color(0.12, 0.1, 0.1), "tint": Color(0.45, 0.42, 0.48), "weapon": ["Sword_Bronze", 0.6]},
	"barbarian": {"outfit": "Male_Peasant", "body": "m", "hair": ["Hair_Long", "Hair_Beard"], "hair_color": Color(0.55, 0.22, 0.1), "tint": Color(0.85, 0.6, 0.5), "weapon": ["Axe_Bronze", 1.0]},
	"monk": {"outfit": "Male_Peasant", "body": "m", "hair": ["Hair_Buzzed"], "hair_color": Color(0.1, 0.08, 0.07), "tint": Color(1.0, 0.72, 0.45), "weapon": []},
	"bard": {"outfit": "Female_Peasant", "body": "f", "hair": ["Hair_Long"], "hair_color": Color(0.75, 0.55, 0.3), "tint": Color(0.9, 0.55, 0.6), "weapon": []},
	"cleric": {"outfit": "Female_Peasant", "body": "f", "hair": ["Hair_Buns"], "hair_color": Color(0.3, 0.18, 0.1), "tint": Color(1.0, 0.97, 0.88), "weapon": []},
	"druid": {"outfit": "Male_Peasant", "body": "m", "hair": ["Hair_SimpleParted", "Hair_Beard"], "hair_color": Color(0.55, 0.55, 0.52), "tint": Color(0.6, 0.85, 0.55), "weapon": []},
	# 예전 다크 판타지(Bento) 자리: 후드를 벗기고 갑옷 색으로
	"fighter": {"outfit": "Male_Ranger", "body": "m", "hair": ["Hair_Buzzed"], "hair_color": Color(0.25, 0.17, 0.1), "no_hood": true, "tint": Color(1, 1, 1), "recolor": Color(0.45, 0.48, 0.55), "weapon": ["Sword_Bronze", 1.0]},
	"paladin": {"outfit": "Male_Ranger", "body": "m", "hair": ["Hair_SimpleParted", "Hair_Beard"], "hair_color": Color(0.7, 0.55, 0.3), "no_hood": true, "tint": Color(1, 1, 1), "recolor": Color(0.85, 0.82, 0.7), "weapon": ["Sword_Bronze", 0.9], "shield": ["Shield_Wooden", 0.55]},
	"wizard": {"outfit": "Male_Peasant", "body": "m", "hair": ["Hair_Long", "Hair_Beard"], "hair_color": Color(0.8, 0.8, 0.8), "tint": Color(0.45, 0.55, 1.0), "weapon": []},
	"sorcerer": {"outfit": "Female_Peasant", "body": "f", "hair": ["Hair_Long"], "hair_color": Color(0.6, 0.12, 0.08), "tint": Color(0.75, 0.5, 0.95), "weapon": []},
	"warlock": {"outfit": "Female_Ranger", "body": "f", "hair": [], "hair_color": Color(0.1, 0.08, 0.1), "tint": Color(1, 1, 1), "recolor": Color(0.35, 0.12, 0.4), "weapon": []},
	# 마을 사람(상인 등 NPC)
	"villager_m": {"outfit": "Male_Peasant", "body": "m", "hair": ["Hair_SimpleParted"], "hair_color": Color(0.3, 0.2, 0.12), "tint": Color(1, 1, 1), "weapon": []},
	"villager_f": {"outfit": "Female_Peasant", "body": "f", "hair": ["Hair_Buns"], "hair_color": Color(0.4, 0.26, 0.14), "tint": Color(1, 1, 1), "weapon": []},
}
const BODIES := {"m": "Superhero_Male_FullBody", "f": "Superhero_Female_FullBody"}
## 머리로 남길 뼈 (이 뼈들에 주로 붙은 면만)
const HEAD_BONES := ["Head", "neck_01"]

## 동작: 엔진 이름 → [팩, 원본 동작, 길이 초(0이면 그대로)]
const ANIM_SRC := {
	"ual": "F:/workspace/fab_downloads/godot/quaternius_ual/Animation Library[Standard]/Godot/AnimationLibrary_Godot_Standard.glb",
	"rpg": "F:/workspace/fab_downloads/godot/explosive_rpg/Unarmed.glb",
}
const ANIMS := {
	"idle": ["ual", "Idle_Loop", 0.0],
	"walk": ["ual", "Walk_Loop", 0.0],
	"sprint": ["ual", "Jog_Fwd_Loop", 0.0],
	"crouch": ["ual", "Crouch_Idle_Loop", 0.0],
	"hurt": ["rpg", "UnarmedIdleInjured", 0.0],
	"jump": ["rpg", "UnarmedJump", 0.0],
	"die": ["ual", "Death01", 0.0],
	"hit": ["ual", "Hit_Chest", 0.0],
	"attack-melee-right": ["ual", "Sword_Attack", 0.0],
	"holding-right-shoot": ["ual", "Spell_Simple_Shoot", 0.0],
	"cast": ["ual", "Spell_Simple_Shoot", 0.0],
	"dodge": ["ual", "Roll", 0.0],
}
const LOOPING := ["idle", "walk", "sprint", "crouch", "hurt"]
## 공통 이름(옷 뼈대 = Bento식) → 원본 팩 뼈 이름. 왼쪽/오른쪽은 {x}/{X}
const SRC_BONES := {
	"ual": {
		"pelvis": "DEF-hips", "spine_01": "DEF-spine.001", "spine_02": "DEF-spine.002", "spine_03": "DEF-spine.003",
		"neck_01": "DEF-neck", "Head": "DEF-head",
		"clavicle_{x}": "DEF-shoulder.{X}", "upperarm_{x}": "DEF-upper_arm.{X}", "lowerarm_{x}": "DEF-forearm.{X}",
		"hand_{x}": "DEF-hand.{X}", "middle_01_{x}": "DEF-f_middle.01.{X}",
		"thigh_{x}": "DEF-thigh.{X}", "calf_{x}": "DEF-shin.{X}", "foot_{x}": "DEF-foot.{X}", "ball_{x}": "DEF-toe.{X}",
	},
	"rpg": {
		"pelvis": "B_Pelvis", "spine_01": "B_Spine", "spine_02": "B_Spine1", "spine_03": "B_Spine2",
		"neck_01": "B_Neck", "Head": "B_Head",
		"clavicle_{x}": "B_{X}_Clavicle", "upperarm_{x}": "B_{X}_UpperArm", "lowerarm_{x}": "B_{X}_Forearm",
		"hand_{x}": "B_{X}_Hand", "middle_01_{x}": "B_{X}_Finger2",
		"thigh_{x}": "B_{X}_Thigh", "calf_{x}": "B_{X}_Calf", "foot_{x}": "B_{X}_Foot", "ball_{x}": "B_{X}_Toe0",
	},
}
const CHAIN := [
	["spine_01", "spine_02"], ["spine_02", "spine_03"], ["spine_03", "neck_01"], ["neck_01", "Head"],
	["clavicle_{x}", "upperarm_{x}"], ["upperarm_{x}", "lowerarm_{x}"], ["lowerarm_{x}", "hand_{x}"], ["hand_{x}", "middle_01_{x}"],
	["thigh_{x}", "calf_{x}"], ["calf_{x}", "foot_{x}"], ["foot_{x}", "ball_{x}"],
]

var _src := {}
var _tex := {}
## 옷 텍스처의 초록(레인저 옷감)을 바꿀 색 (알파 0이면 그대로)
var _recolor := Color(0, 0, 0, 0)


func _init() -> void:
	var only := OS.get_cmdline_user_args()
	for name in HEROES:
		if only.is_empty() or name in only:
			_bake(name, HEROES[name])
	for k in _src:
		(_src[k][0] as Node).free()
	quit()


func _gltf(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(path, st) != OK:
		push_error("못 읽음: " + path)
		return null
	return doc.generate_scene(st) as Node3D


func _bake(name: String, spec: Dictionary) -> void:
	var root := Node3D.new()
	root.name = name
	var outfit := _gltf(OUTFITS + spec.outfit + ".gltf")
	var arm := outfit.get_node("Armature") as Node3D
	outfit.remove_child(arm)
	root.add_child(arm)
	outfit.free()
	var sk := arm.get_node("Skeleton3D") as Skeleton3D
	var tint: Color = spec.tint
	if spec.get("no_hood", false):
		for mi in sk.get_children():
			if String(mi.name).contains("Hood"):
				mi.free()
	_recolor = spec.get("recolor", Color(0, 0, 0, 0))
	for mi in sk.get_children():
		if mi is MeshInstance3D:
			_fix_materials(mi, tint)
	_recolor = Color(0, 0, 0, 0)
	# 머리: 기본 몸에서 머리·목 면만, 눈·눈썹은 그대로
	var body := _gltf(BASE + "Base Characters/Godot - UE/" + BODIES[spec.body] + ".gltf")
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if String(m.name).to_lower().begins_with("superhero"):
			m.mesh = _head_only(m)
		_move_to(m, sk)
		_fix_materials(m, Color(1, 1, 1), spec.hair_color)
	body.free()
	for h in spec.hair:
		var hs := _gltf(HAIR + h + ".gltf")
		for mi in hs.find_children("*", "MeshInstance3D", true, false):
			_move_to(mi, sk)
			_fix_materials(mi, Color(1, 1, 1), spec.hair_color)
		hs.free()
	# 무기 (오른손)
	if not spec.weapon.is_empty():
		var wm := load("res://assets/quaternius/props/%s.res" % spec.weapon[0]) as Mesh
		if wm:
			var ba := BoneAttachment3D.new()
			ba.name = "Weapon"
			ba.bone_name = "hand_r"
			sk.add_child(ba)
			var wi := MeshInstance3D.new()
			wi.name = "WeaponMesh"
			wi.mesh = wm
			# 소품은 바닥(손잡이 끝)이 원점, 위가 +Y. 손 뼈 축에 맞게 돌리고 손바닥 쪽으로 조금 옮김 (미터 단위 뼈대라 0.6m 소품을 키움)
			var s: float = float(spec.weapon[1]) / 0.6
			# 손 뼈: +Y가 손가락 → 소품 +Y(날)를 손가락과 손 -Z 사이 45도로 (서 있으면 다리 옆으로 늘어지고 휘두르면 앞으로), 주먹 가운데에서 손잡이를 쥠
			var grip := Basis(Vector3(0, 0.7071, 0.7071), Vector3(0, 0.7071, -0.7071), Vector3(-1, 0, 0)).scaled(Vector3.ONE * s)
			wi.transform = Transform3D(grip, Vector3(-0.03, 0.09, 0.0)) * Transform3D(Basis.IDENTITY, Vector3(0, -0.12, 0))
			ba.add_child(wi)
	# 방패 (왼손, 손등 쪽으로 면이 향하게)
	if spec.has("shield"):
		var sm := load("res://assets/quaternius/props/%s.res" % spec.shield[0]) as Mesh
		if sm:
			var sa := BoneAttachment3D.new()
			sa.name = "Shield"
			sa.bone_name = "lowerarm_l"
			sk.add_child(sa)
			var si := MeshInstance3D.new()
			si.name = "ShieldMesh"
			si.mesh = sm
			var k: float = float(spec.shield[1]) / 0.6
			# 아래팔 뼈 +Y가 손 쪽: 방패 위(+Y)를 팔을 따라, 앞면(+Z)을 팔 바깥(-X)으로
			si.transform = Transform3D(Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)).scaled(Vector3.ONE * k), Vector3(-0.06, 0.05, 0)) 					* Transform3D(Basis.IDENTITY, Vector3(0, -0.18, 0))
			sa.add_child(si)
	# 동작
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	root.add_child(ap)
	var lib := AnimationLibrary.new()
	var prefix := "Armature/Skeleton3D"
	for key in ANIMS:
		var a := _anim(sk, prefix, ANIMS[key])
		if a:
			a.loop_mode = Animation.LOOP_LINEAR if key in LOOPING else Animation.LOOP_NONE
			lib.add_animation(key, a)
	ap.add_animation_library("", lib)
	_own(root, root)
	var dir := OUT + name + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var packed := PackedScene.new()
	packed.pack(root)
	print(name, " save=", ResourceSaver.save(packed, dir + name + ".scn", ResourceSaver.FLAG_COMPRESS), " anims=", lib.get_animation_list().size())
	root.free()


## 다른 뼈대 아래로 옮김 (스킨을 뼈 이름으로 묶어 새 뼈대를 따라가게)
func _move_to(mi: MeshInstance3D, sk: Skeleton3D) -> void:
	var skin := mi.skin.duplicate() as Skin
	# 원본은 뼈 번호로 묶여 있음: 뼈대마다 순서가 달라 이름으로 바꿔 묶음
	var own := mi.get_parent() as Skeleton3D
	if own:
		for b in skin.get_bind_count():
			if String(skin.get_bind_name(b)) == "":
				skin.set_bind_name(b, own.get_bone_name(skin.get_bind_bone(b)))
	mi.get_parent().remove_child(mi)
	sk.add_child(mi)
	mi.skin = skin
	mi.skeleton = NodePath("..")
	mi.transform = Transform3D.IDENTITY


## 머리·목 뼈에 주로 붙은 삼각형만 남긴 메시
func _head_only(mi: MeshInstance3D) -> ArrayMesh:
	var src := mi.mesh
	var skin := mi.skin
	var sk := mi.get_parent() as Skeleton3D
	var keep_bind := {}
	for b in skin.get_bind_count():
		var bn := String(skin.get_bind_name(b))
		if bn == "" and sk:
			bn = sk.get_bone_name(skin.get_bind_bone(b))
		if bn in HEAD_BONES:
			keep_bind[b] = true
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var arr := src.surface_get_arrays(s)
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var nv: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var per := bones.size() / nv
		var head := PackedByteArray()
		head.resize(nv)
		for v in nv:
			var w := 0.0
			for j in per:
				if keep_bind.has(bones[v * per + j]):
					w += weights[v * per + j]
			head[v] = 1 if w > 0.5 else 0
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():  # 번호 없이 정점이 바로 삼각형인 메시
			idx.resize(nv)
			for v in nv:
				idx[v] = v
		var kept := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			if head[idx[t]] and head[idx[t + 1]] and head[idx[t + 2]]:
				kept.append_array([idx[t], idx[t + 1], idx[t + 2]])
		arr[Mesh.ARRAY_INDEX] = kept
		# 따로 쓰는 정점 자료(custom)는 형식 정보가 없어 다시 넣으면 거부됨: 버림
		for ci in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
			arr[ci] = null
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0)
		out.surface_set_material(out.get_surface_count() - 1, src.surface_get_material(s))
	return out


## 재질 사본: 색 입히고 텍스처를 1024로 줄임 (같은 텍스처는 한 번만)
func _fix_materials(mi: MeshInstance3D, tint: Color, hair := Color.WHITE) -> void:
	var m := mi.mesh
	for s in m.get_surface_count():
		var mat := m.surface_get_material(s) as BaseMaterial3D
		if mat == null:
			continue
		var c := mat.duplicate() as BaseMaterial3D
		var mn := String(mat.resource_name)
		if mn.contains("Hair"):
			c.albedo_color *= hair
		elif not (mn.contains("Regular") or mn.contains("Superhero") or mn.contains("Eyes")):
			c.albedo_color *= tint
		for prop in ["albedo_texture", "normal_texture", "orm_texture", "roughness_texture", "metallic_texture", "ao_texture"]:
			var t = c.get(prop)
			if t is Texture2D:
				var rc: bool = _recolor.a > 0 and prop == "albedo_texture" and not (mn.contains("Regular") or mn.contains("Superhero") or mn.contains("Hair") or mn.contains("Eyes"))
				c.set(prop, _shrink(t, prop == "normal_texture", _recolor if rc else Color(0, 0, 0, 0)))
		m.surface_set_material(s, c)


func _shrink(t: Texture2D, normal: bool, recolor := Color(0, 0, 0, 0)) -> Texture2D:
	var key := [t, recolor]
	if _tex.has(key):
		return _tex[key]
	var img := t.get_image()
	if img == null:
		return t
	img = img.duplicate()
	img.decompress()
	if img.get_width() > TEX:
		img.resize(TEX, TEX * img.get_height() / img.get_width(), Image.INTERPOLATE_LANCZOS)
	if recolor.a > 0:
		# 초록 기운이 있는 픽셀만 색상·채도를 바꾸고 밝기는 둠 (가죽·쇠는 그대로)
		img.convert(Image.FORMAT_RGBA8)
		for y in img.get_height():
			for x in img.get_width():
				var p := img.get_pixel(x, y)
				if p.h > 0.17 and p.h < 0.5 and p.s > 0.15:
					var v := p.v * (0.6 + recolor.v)
					img.set_pixel(x, y, Color.from_hsv(recolor.h, recolor.s, clampf(v, 0, 1), p.a))
	img.generate_mipmaps(normal)
	img.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_NORMAL if normal else Image.COMPRESS_SOURCE_GENERIC)
	var out := ImageTexture.create_from_image(img)
	_tex[key] = out
	return out


func _source(pack: String) -> Array:
	if _src.has(pack):
		return _src[pack]
	var scene := _gltf(ANIM_SRC[pack])
	var sk := scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var ap := scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	_src[pack] = [scene, sk, ap, str(ap.get_node(ap.root_node).get_path_to(sk))]
	return _src[pack]


func _side(s: String, x: String) -> String:
	return s.replace("{x}", x).replace("{X}", x.to_upper())


func _anim(sk: Skeleton3D, prefix: String, spec: Array) -> Animation:
	var src := _source(spec[0])
	var src_anim := (src[2] as AnimationPlayer).get_animation(spec[1])
	if src_anim == null:
		push_error("원본 동작 없음: %s" % [spec])
		return null
	var bones: Dictionary = SRC_BONES[spec[0]]
	var map := []
	for c in CHAIN:
		for x in (["l", "r"] if c[0].contains("{x}") else [""]):
			var a := _side(c[0], x)
			var b := _side(c[1], x)
			if sk.find_bone(a) >= 0 and sk.find_bone(b) >= 0:
				map.append([a, _side(bones[c[0]], x), b, _side(bones[c[1]], x)])
	var hips := ["pelvis", bones["pelvis"], "spine_03", bones["spine_03"],
		"thigh_l", _side(bones["thigh_{x}"], "l"), "thigh_r", _side(bones["thigh_{x}"], "r")]
	var out := Retarget.retarget(src[1], src_anim, src[3], sk, prefix, map, hips)
	# 골반이 흘러가지 않게 (자리는 게임이 정함)
	for t in out.get_track_count():
		if out.track_get_type(t) == Animation.TYPE_POSITION_3D and String(out.track_get_path(t)) == prefix + ":pelvis":
			var first: Vector3 = out.track_get_key_value(t, 0)
			for k in out.track_get_key_count(t):
				var v: Vector3 = out.track_get_key_value(t, k)
				out.track_set_key_value(t, k, Vector3(first.x, v.y, first.z))
	if spec[2] > 0.0:
		var k := float(spec[2]) / out.length
		for t in out.get_track_count():
			for i in range(out.track_get_key_count(t) - 1, -1, -1):
				out.track_set_key_time(t, i, out.track_get_key_time(t, i) * k)
		out.length = spec[2]
	return out


func _own(n: Node, owner: Node) -> void:
	for ch in n.get_children():
		ch.owner = owner
		_own(ch, owner)
