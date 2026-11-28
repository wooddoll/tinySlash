## 바깥 지형의 몬스터 무리. 지형 시드로 자리와 구성이 정해지고(같은 세상이면 같은 자리),
## 무리는 제자리 근처를 어슬렁거리다 플레이어가 가까이 오면 다가옵니다. 닿으면 engaged(무리 번호).
## 전투는 main.gd가 그 자리 지형 위에서 실시간 액션 전투로 엽니다 (OutdoorTerrain.battle_grid).
##   var m := OutdoorMonsters.new(); add_child(m); m.spawn(outdoor, seed, defeated, player)
class_name OutdoorMonsters
extends Node3D

const CharacterModel = preload("res://scripts/character_model.gd")
const Outdoor = preload("res://scripts/outdoor_terrain.gd")
const Sfx = preload("res://scripts/sfx.gd")

## 무리 수
const COUNT := 8
## 빈터·입구에서 이만큼은 떨어짐 (칸)
const KEEP_CLEAR := 22.0
## 이 거리보다 멀면 센 무리
const FAR := 60.0
const NEAR_GROUPS := [["goblin_minion", "goblin_minion"], ["wolf"], ["goblin_warrior", "goblin_minion"]]
const FAR_GROUPS := [["wolf", "wolf"], ["goblin_warrior", "goblin_minion", "goblin_minion"], ["goblin_boss", "goblin_minion"]]
## 알아채는 거리, 쫓는 거리(제자리에서), 닿는 거리 (칸)
const NOTICE := 9.0
const LEASH := 16.0
## 이 거리 안으로 쫓아오면 그 자리에서 실시간 전투 시작 (main.gd)
const ENGAGE := 5.0
const WANDER := 3.0

## 무리가 플레이어에게 닿음
signal engaged(group: int)

## 무리마다 {id, foes, home, node, models, target, wait}
var groups: Array = []
## 모든 무리 (물리친 것 포함): 번호 → {home, foes}
var _all := {}
var player: Node3D = null
var _outdoor: Node3D = null
var _rng := RandomNumberGenerator.new()
## 이 시간 동안은 알아채지 않음 (전투에서 도망쳐 돌아온 직후)
var calm := 0.0


func spawn(outdoor: Node3D, world_seed: int, defeated: Dictionary, who: Node3D) -> void:
	_outdoor = outdoor
	player = who
	_rng.seed = world_seed * 7919 + 13
	var door: Vector3 = (outdoor.entrance as Transform3D).origin
	var half: float = Outdoor.SIZE / 2.0 - 24.0
	var tries := 0
	var spots: Array[Vector3] = []
	while spots.size() < COUNT and tries < 2000:
		tries += 1
		var p := Vector3(_rng.randf_range(-half, half), 0, _rng.randf_range(-half, half))
		if p.length() < KEEP_CLEAR or Vector2(p.x - door.x, p.z - door.z).length() < KEEP_CLEAR * 0.7:
			continue
		if spots.any(func(q: Vector3) -> bool: return q.distance_to(p) < 18.0):
			continue
		if _steep(p):
			continue
		spots.append(p)
	for i in spots.size():
		var p := spots[i]
		var far := p.length() > FAR
		var pool: Array = FAR_GROUPS if far else NEAR_GROUPS
		var foes: Array = pool[_rng.randi() % pool.size()]
		_all[i] = {"home": p, "foes": foes}
		if not defeated.has(i):
			_spawn_group(i)


## 무리 하나를 제자리에 세움
func _spawn_group(i: int) -> void:
	var p: Vector3 = _all[i].home
	var foes: Array = _all[i].foes
	var node := Node3D.new()
	node.name = "Group%d" % i
	add_child(node)
	var models: Array = []
	for j in foes.size():
		var st := Catalog.monster(str(foes[j]))
		var m := CharacterModel.new()
		node.add_child(m)
		m.setup(st.model, st.sprite_scale, st.weapon_model)
		m.tint(st.tint)
		m.position = p + Vector3(cos(j * 2.1), 0, sin(j * 2.1)) * (0.0 if j == 0 else 1.3)
		m.position.y = _outdoor.height_at(m.position)
		m.face(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)), true)
		models.append(m)
	groups.append({"id": i, "foes": foes, "home": p, "node": node, "models": models,
			"target": p, "wait": _rng.randf_range(0.5, 3.0), "chasing": false})


## 싸움에 들어간 무리를 지도에서 빼고 몬스터마다 [id, 월드 자리]를 돌려줌 (전투가 자기 모델을 만듦)
func take_group(id: int) -> Array:
	var out: Array = []
	for g in groups:
		if g.id == id:
			for k in g.foes.size():
				out.append([g.foes[k], (g.models[k] as Node3D).global_position])
			(g.node as Node).queue_free()
			groups.erase(g)
			break
	return out


## 도망치거나 져서 다시 제자리에 세움
func restore_group(id: int) -> void:
	if _all.has(id) and not groups.any(func(g: Dictionary) -> bool: return g.id == id):
		_spawn_group(id)


## 이 무리의 전투 이름 (예: "고블린 졸개 2")
func label(group: int) -> String:
	if not _all.has(group):
		return ""
	var names := {}
	for f in _all[group].foes:
		var n := Catalog.monster(str(f)).display_name
		names[n] = int(names.get(n, 0)) + 1
	var parts := PackedStringArray()
	for n in names:
		parts.append(n if names[n] == 1 else "%s %d" % [n, names[n]])
	return " + ".join(parts)


func foes_of(group: int) -> Array:
	return _all[group].foes if _all.has(group) else []


func _steep(p: Vector3) -> bool:
	var h := _outdoor.height_at(p) as float
	for d in [Vector3(2, 0, 0), Vector3(-2, 0, 0), Vector3(0, 0, 2), Vector3(0, 0, -2)]:
		if absf(_outdoor.height_at(p + d) - h) > 1.0:
			return true
	return false


func _process(delta: float) -> void:
	if player == null or _outdoor == null:
		return
	calm = maxf(calm - delta, 0.0)
	var me := player.global_position
	for g in groups:
		var lead: Node3D = g.models[0]
		var to_player := Vector2(me.x - lead.position.x, me.z - lead.position.z)
		var from_home := Vector2(lead.position.x - g.home.x, lead.position.z - g.home.z)
		var chase: bool = calm <= 0.0 and to_player.length() < NOTICE and from_home.length() < LEASH
		if chase and not g.chasing:
			Sfx.play(self, "alert")
		g.chasing = chase
		if chase and to_player.length() < ENGAGE:
			engaged.emit(g.id)
			set_process(false)
			return
		var goal: Vector3 = me if chase else g.target
		var speed := 3.4 if chase else 1.1
		var moved := false
		for k in g.models.size():
			var m: Node3D = g.models[k]
			var aim := goal + (Vector3.ZERO if k == 0 else Vector3(cos(k * 2.1), 0, sin(k * 2.1)) * 1.3)
			var step := Vector3(aim.x - m.position.x, 0, aim.z - m.position.z)
			if step.length() > 0.15:
				var mv := step.normalized() * minf(speed * delta, step.length())
				m.position += mv
				m.position.y = _outdoor.height_at(m.position)
				(m as CharacterModel).face(mv)
				(m as CharacterModel).set_base("sprint" if chase else "walk")
				moved = true
			else:
				(m as CharacterModel).set_base("idle")
		if not chase and not moved:
			g.wait -= delta
			if g.wait <= 0.0:
				g.wait = _rng.randf_range(2.0, 5.0)
				g.target = g.home + Vector3(_rng.randf_range(-WANDER, WANDER), 0, _rng.randf_range(-WANDER, WANDER))
