## 캐릭터 모델 하나. 애니메이션, 방향 돌리기, 맞았을 때 번쩍임, 무기 붙이기.
## 모델 경로는 "팩/이름":
##   "kaykit/Knight"          KayKit 캐릭터 (assets/kaykit/characters, CC0)
##   "quaternius/orc"         Quaternius 몬스터 (assets/quaternius/monsters, CC0)
##   "animals/wolf"           Quaternius 동물 (assets/quaternius/animals, CC0)
##   끝에 "*3"을 붙이면 작은 몸 셋을 한 칸에 모아 세웁니다 (떼: "animals/rat*3")
##   "dark/knight"            다크 판타지 (Fab Bento Pack을 tools/bake_dark.gd로 줄인 것, assets/dark)
##   "mini-characters/..."    Kenney 모델 (옛 캐릭터 이름은 ALIASES로 새 모델에 연결)
## 무기: Kenney는 "팩/이름" 하나를 오른팔에 붙입니다.
##   KayKit은 "+"로 이은 이름들: 모델 안에 든 장비(예: "2H_Sword")는 보이게 하고,
##   없으면 assets/kaykit/items/<이름>.gltf를 손에 쥐어 줍니다 (방패는 왼손)
extends Node3D

const Kenney = preload("res://scripts/kenney.gd")
const KAYKIT := "res://assets/kaykit/characters/%s.glb"
const KAYKIT_ITEM := "res://assets/kaykit/items/%s.gltf"
const QUATERNIUS := "res://assets/quaternius/monsters/%s.glb"
const ANIMALS := "res://assets/quaternius/animals/%s.glb"
const DARK := "res://assets/dark/%s/%s.scn"
## 떼의 몸들 자리 (칸 안, 월드 유닛)
## 나는 떼의 몸마다 더하는 높이 (월드 유닛). 같은 높이로 붙어 다니지 않게
const SWARM_LIFT := [0.14, -0.1, 0.24, 0.02, -0.14]
const SWARM_SPOTS := [Vector3(-0.2, 0, -0.12), Vector3(0.22, 0, -0.05), Vector3(0.0, 0, 0.22), Vector3(-0.15, 0, 0.2), Vector3(0.2, 0, 0.24)]
const LOOPING := ["idle", "walk", "sprint", "crouch", "hurt"]
const CHAR_LAYER := 2
## Kenney 모델 원래 키는 약 0.8 유닛. 1칸(1 유닛)에 맞게 키웁니다.
const BASE_SCALE := 1.6
## 다른 팩 모델은 이 키(유닛)에 맞춰 크기를 정합니다 (Kenney 0.8 x 1.6과 같음)
const TARGET_HEIGHT := 1.28
## 잰 키가 실제와 다른 모델(뼈대 바깥까지 잡히는 것)은 직접 적은 키를 씁니다
const RAW_HEIGHT := {
	"quaternius/blue_demon": 2.1,
	"animals/rat": 4.0,
	"dark/zombie": 1.81,
	"dark/skeleton": 1.8,
	"dark/ghost": 0.028,
	# 보스는 키 대신 너비로 크기를 맞춤 (대형 = 약 2칸 너비)
	"dark/bellwarden": 4.5,
	"dark/cantor": 2.4,
	"dark/regent": 4.8,
	"dark/burrwheel": 1.6,
	"dark/heron": 2.2,
	"dark/silkgrafter": 2.4,
	"dark/winterscion": 2.1,
	"dark/aurochs": 1.9,
}
## 옛 Kenney 캐릭터 이름 → 새 모델 (예전 시나리오 팩도 그대로 돌아가게)
const ALIASES := {
	"mini-characters/character-knight": "kaykit/Knight",
	"mini-characters/character-female-a": "kaykit/Rogue",
	"mini-characters/character-female-b": "kaykit/Mage",
	"mini-characters/character-female-c": "kaykit/Rogue_Hooded",
	"mini-characters/character-female-d": "kaykit/Rogue",
	"mini-characters/character-female-e": "kaykit/Rogue_Hooded",
	"mini-characters/character-female-f": "kaykit/Mage",
	"mini-characters/character-male-a": "kaykit/Barbarian",
	"mini-characters/character-male-b": "kaykit/Barbarian",
	"mini-characters/character-male-c": "kaykit/Barbarian",
	"mini-characters/character-male-d": "kaykit/Rogue_Hooded",
	"mini-characters/character-male-e": "kaykit/Barbarian",
	"mini-characters/character-male-f": "kaykit/Barbarian",
	"mini-characters/character-worker": "kaykit/Barbarian",
	"mini-characters/character-raider": "kaykit/Rogue_Hooded",
	"mini-characters/character-zombie": "quaternius/zombie",
	"mini-dungeon/character-orc": "quaternius/orc",
	"mini-dungeon/character-human": "kaykit/Knight",
}
## 엔진이 부르는 동작 이름 → 팩마다 다른 실제 이름 후보 (앞에서부터 있는 것)
## Quaternius 이름은 "CharacterArmature|Idle"처럼 뼈대 이름이 앞에 붙어 있어 끝부분으로 찾습니다
const ANIMS := {
	"idle": ["Idle", "Flying_Idle", "Rat_Idle"],
	# 체력 절반 이하일 때 서 있는 자세 (없는 모델은 보통 서 있기)
	"hurt": ["Idle", "Flying_Idle", "Rat_Idle"],
	"walk": ["Walking_A", "Walk", "Fast_Flying", "Flying_Idle", "Rat_Walk"],
	"sprint": ["Running_A", "Run", "Gallop", "Walk", "Fast_Flying", "Rat_Run"],
	"crouch": ["Lie_Idle", "Duck", "Idle_2_HeadLow", "Idle", "Flying_Idle", "Rat_Idle"],
	"die": ["Death_A", "Death", "Rat_Death"],
	"jump": ["Jump_Full_Short", "Jump", "Gallop_Jump", "Rat_Jump"],
	"hit": ["Hit_A", "HitReact", "HitRecieve", "Idle_HitReact_Left"],
	"attack-melee-right": ["1H_Melee_Attack_Chop", "Punch", "Bite_Front", "Headbutt", "Attack", "Rat_Attack"],
	"holding-right-shoot": ["1H_Ranged_Shoot", "Punch", "Bite_Front", "Headbutt", "Attack", "Rat_Attack"],
	"dodge": ["Dodge_Forward", "Roll", "Jump_Full_Short", "Jump", "Gallop_Jump", "Rat_Jump"],
	"cast": ["Spellcast_Shoot", "Spellcasting", "1H_Ranged_Shoot", "Punch", "Attack"],
}
const ONCE := ["die", "hit", "jump", "attack-melee-right", "holding-right-shoot", "dodge", "cast"]

var model: Node3D
var anim: AnimationPlayer
var skeleton: Skeleton3D
## 높이 (월드 유닛). 이름표 위치에 씁니다.
var height := 1.25
var _base := "idle"
var _yaw := 0.0
var _flash_mat: StandardMaterial3D
var _weapon: Node3D
var _held := ""
## 공중에 떠 있는 높이 (비행 크리처). 0이면 바닥에 섬
var hover := 0.0
var _bob := 0.0
var _shadow: MeshInstance3D
## 엔진 동작 이름 → 이 모델의 실제 애니메이션 이름
var _names := {}
## 떼처럼 몸이 여럿일 때 나머지 몸들의 애니메이션 (anim은 첫 몸)
var _extra_anims: Array[AnimationPlayer] = []
## 떼의 몸들 (하나뿐이면 비어 있음)
var _bodies: Array[Node3D] = []


func setup(path: String, size := 1.0, weapon := "") -> void:
	path = ALIASES.get(path, path)
	var copies := 1
	if path.contains("*"):
		copies = clampi(int(path.get_slice("*", 1)), 1, SWARM_SPOTS.size())
		path = path.get_slice("*", 0)
	var parts := path.split("/")
	var kenney := not parts[0] in ["kaykit", "quaternius", "animals", "dark"]
	var scene: PackedScene = null
	match parts[0]:
		"kaykit": scene = load(KAYKIT % parts[1])
		"quaternius": scene = load(QUATERNIUS % parts[1])
		"animals": scene = load(ANIMALS % parts[1])
		"dark": scene = load(DARK % [parts[1], parts[1]])
	if scene:
		model = scene.instantiate() as Node3D
	else:
		model = Kenney.instance(parts[1], parts[0])
	if copies > 1:
		# 떼: 빈 그릇 노드 아래에 몸 여럿. 크기는 그릇에, 자리는 아래에서 정함
		var holder := Node3D.new()
		holder.add_child(model)
		for i in copies - 1:
			holder.add_child(scene.instantiate() if scene else Kenney.instance(parts[1], parts[0]))
		model = holder
	add_child(model)
	# 맨 위에 있는 것을 먼저 (dark/zombie처럼 모델 안의 빈 플레이어 위에 동작을 덧붙인 경우)
	anim = model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim == null:
		anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	var gear: PackedStringArray = []
	if parts[0] == "kaykit" and skeleton:
		gear = _kaykit_gear(weapon)
	if kenney:
		var s := BASE_SCALE * size
		model.scale = Vector3.ONE * s
		height = 0.8 * s
	else:
		var raw: float = RAW_HEIGHT.get(path, 0.0)
		if raw <= 0.0:
			raw = maxf(_visible_aabb(model, Transform3D.IDENTITY).size.y, 0.01)
		height = TARGET_HEIGHT * size
		model.scale = Vector3.ONE * (height / raw)
	if copies > 1:
		var bodies := model.get_children()
		for i in bodies.size():
			var b := bodies[i] as Node3D
			_bodies.append(b)
			b.position = SWARM_SPOTS[i] / model.scale.x
			b.rotation.y = (i * 1.7) - 0.8
			if i > 0:
				var ap := b.find_child("AnimationPlayer", true, false) as AnimationPlayer
				if ap:
					ap.speed_scale = 0.85 + 0.12 * i
					_extra_anims.append(ap)
	# 렌더 층 2: 어두운 던전에서 캐릭터만 비추는 보조광(dungeon_view._set_mood)이 이 층만 비춤
	for m in _meshes(model):
		m.layers |= CHAR_LAYER
	if anim:
		_map_anims(gear)
		for a in LOOPING + ONCE:
			var real: String = _names.get(a, a)
			if anim.has_animation(real):
				anim.get_animation(real).loop_mode = Animation.LOOP_LINEAR if a in LOOPING else Animation.LOOP_NONE
		anim.animation_finished.connect(_on_finished)
	if kenney and weapon.contains("/") and skeleton:
		_attach_weapon(weapon)
	set_base("idle")


## 동작 이름 대응표. KayKit은 쥔 무기에 따라 양손·맨손 공격, 쇠뇌·주문 동작을 고릅니다
func _map_anims(gear: PackedStringArray) -> void:
	var list := anim.get_animation_list()
	var two := false
	var bow := false
	var magic := false
	for g in gear:
		var lg := g.to_lower()
		two = two or g.begins_with("2H_") or lg.contains("2handed") or lg.contains("staff")
		bow = bow or lg.contains("bow")
		magic = magic or lg.contains("staff") or lg.contains("wand") or lg.contains("spellbook")
	var extra := {}
	if anim.has_animation("Unarmed_Idle"):
		if gear.is_empty():
			extra["attack-melee-right"] = ["Unarmed_Melee_Attack_Punch_A"]
		elif two:
			extra["attack-melee-right"] = ["2H_Melee_Attack_Chop"]
		if magic:
			extra["holding-right-shoot"] = ["Spellcast_Shoot"]
		elif bow:
			extra["holding-right-shoot"] = ["2H_Ranged_Shoot" if two else "1H_Ranged_Shoot"]
	for key in ANIMS:
		var cands: Array = [key] + extra.get(key, []) + ANIMS[key]
		for c in cands:
			var found := _find_anim(list, c)
			if found != "":
				_names[key] = found
				break


static func _find_anim(list: PackedStringArray, n: String) -> String:
	for a in list:
		if a == n or a.ends_with("|" + n):
			return a
	return ""


## KayKit 손 장비: 원하는 것만 보이게 하고, 모델에 없는 것은 items 폴더에서 가져와 쥐어 줍니다
func _kaykit_gear(weapon: String) -> PackedStringArray:
	var want: PackedStringArray = []
	if weapon != "" and not weapon.contains("/"):
		want = weapon.split("+", false)
	var have := {}
	for ba in skeleton.find_children("*", "BoneAttachment3D", false, false):
		var b := ba as BoneAttachment3D
		if not b.bone_name.begins_with("handslot"):
			continue
		for mi in b.get_children():
			if mi is MeshInstance3D:
				mi.visible = want.has(String(mi.name))
				have[String(mi.name)] = true
	for w in want:
		if have.has(w):
			continue
		var res := load(KAYKIT_ITEM % w) as PackedScene
		if res == null:
			push_error("KayKit 장비 없음: " + w)
			continue
		var holder := BoneAttachment3D.new()
		holder.bone_name = "handslot.l" if w.to_lower().contains("shield") else "handslot.r"
		skeleton.add_child(holder)
		holder.add_child(res.instantiate())
	return want


## 보이는 메시만 합친 상자 (장비를 숨긴 뒤 키를 잽니다)
func _visible_aabb(n: Node, xf: Transform3D) -> AABB:
	var t := xf
	if n is Node3D:
		if not (n as Node3D).visible:
			return AABB()
		t = xf * (n as Node3D).transform
	var box := AABB()
	var has := false
	if n is MeshInstance3D:
		box = t * (n as MeshInstance3D).get_aabb()
		has = true
	for c in n.get_children():
		var b := _visible_aabb(c, t)
		if b.size != Vector3.ZERO:
			box = b if not has else box.merge(b)
			has = true
	return box


## 계속 반복할 기본 동작 (idle, walk, crouch)
func set_base(n: String) -> void:
	if _base == n and anim and anim.current_animation == n:
		return
	_held = ""
	_base = n
	_play(n, 0.15)


## 한 번만 하고 기본 동작으로 돌아감 (공격 등)
func play_once(n: String) -> void:
	if _held != "":
		return
	_play(n, 0.06)


## 한 번 하고 마지막 자세로 멈춤 (쓰러짐)
func hold(n: String) -> void:
	if _held == n:
		return
	_held = n
	_base = ""
	_play(n, 0.06)


## 공중에 띄움: 위아래로 살짝 흔들리고 바닥에 그림자를 둠. 쓰러지면(die) 바닥으로 떨어짐
func set_hover(h: float) -> void:
	hover = h
	_bob = randf() * TAU
	if h > 0.0 and _shadow == null:
		_shadow = MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.32
		disc.bottom_radius = 0.32
		disc.height = 0.01
		_shadow.mesh = disc
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0, 0, 0, 0.4)
		_shadow.material_override = mat
		_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_shadow.position.y = 0.03
		add_child(_shadow)
	model.position.y = h


func face(dir: Vector3, instant := false) -> void:
	if Vector2(dir.x, dir.z).length() < 0.01:
		return
	_yaw = atan2(dir.x, dir.z)
	if instant:
		rotation.y = _yaw


## 몸 색을 곱해 바꿈 (같은 모델을 쓰는 몬스터 구별). 알파가 1보다 작으면 반투명하게 빛나는 유령
func tint(col: Color) -> void:
	if col == Color.WHITE or model == null:
		return
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var src := m.get_active_material(s)
			if src is BaseMaterial3D:
				var copy: BaseMaterial3D = src.duplicate()
				copy.albedo_color = copy.albedo_color * col
				if col.a < 1.0:
					# 반투명 색(유령류): 비쳐 보이고 그 색으로 은은하게 빛남
					copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					copy.emission_enabled = true
					copy.emission = Color(col.r, col.g, col.b)
					copy.emission_energy_multiplier = 0.8
				m.set_surface_override_material(s, copy)


## 맞았을 때 붉게 번쩍임
func flash(color := Color(1, 0.15, 0.1)) -> void:
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		for m in _meshes(model):
			m.material_overlay = _flash_mat
	_flash_mat.albedo_color = Color(color, 0.7)
	var tw := create_tween()
	tw.tween_property(_flash_mat, "albedo_color:a", 0.0, 0.25)


func _process(delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, _yaw, 1.0 - exp(-14.0 * delta))
	if _shadow:
		_bob += delta * 2.6
		var target := 0.0 if _held == "die" else hover + sin(_bob) * 0.08
		model.position.y = lerpf(model.position.y, target, 1.0 - exp(-8.0 * delta))
		_shadow.visible = model.position.y > 0.05
		# 나는 떼: 몸마다 다른 높이에서 따로 출렁임. 쓰러지면 모두 바닥으로
		for i in _bodies.size():
			var lift: float = 0.0 if _held == "die" else SWARM_LIFT[i] + sin(_bob * 1.4 + i * 2.1) * 0.07
			var by := lerpf(_bodies[i].position.y, lift / model.scale.x, 1.0 - exp(-8.0 * delta))
			_bodies[i].position.y = by
		var k := clampf(1.0 - model.position.y * 0.25, 0.6, 1.0)
		_shadow.scale = Vector3(k, 1, k)
	if _weapon:
		# 위치는 손을 따라가고, 방향은 몸 기준으로 날이 위·앞을 향하게 고정
		var b := model.global_basis
		_weapon.global_basis = b * Basis(Vector3.RIGHT, deg_to_rad(35.0))


func _play(n: String, blend: float) -> void:
	var real: String = _names.get(n, n)
	if anim and anim.has_animation(real):
		anim.play(real, blend)
		for ap in _extra_anims:
			ap.play(real, blend)


func _on_finished(_n: StringName) -> void:
	if _base != "":
		_play(_base, 0.15)


## 오른팔 뼈에 무기 모델을 붙입니다 (Mini Dungeon / Mini Characters의 weapon-*.glb)
func _attach_weapon(path: String) -> void:
	var parts := path.split("/")
	var holder := BoneAttachment3D.new()
	holder.bone_name = "arm-right"
	skeleton.add_child(holder)
	var w := Kenney.instance(parts[1], parts[0])
	# 뼈 공간: 어깨가 원점이고 손은 아래쪽 바깥
	w.position = Vector3(-0.1, -0.15, 0.04)
	holder.add_child(w)
	_weapon = w


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out
