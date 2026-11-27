## 던전 위의 실시간 액션 전투 화면 (docs/rules.md 10장).
## ActionCombat(규칙)을 돌리고, 크리처 모델·HP 바·피해 숫자·공격 예고·투사체를 그립니다.
## 플레이어 입력(키보드·게임패드)도 여기서 읽습니다. 던전 탐험(dungeon_view)이 만들어 씁니다.
extends Node3D

const CharacterModel = preload("res://scripts/character_model.gd")
const Sfx = preload("res://scripts/sfx.gd")

signal message(text: String)
## 파티원 HP·자원이 바뀜
signal party_changed
## 깨어 있는 적이 모두 쓰러짐 (xp: 나눌 XP)
signal fight_over(xp: int)
## 파티가 모두 쓰러짐
signal defeated

var ac: ActionCombat
var dungeon: Dungeon
var player: ActionCombat.Actor
## 입력 방향을 카메라 회전에 맞추기 위한 참조
var camera_rig: Node3D
## 멈춤 (창이 떠 있을 때)
var paused := false
## Actor → {"model", "bar", "fill", "ring"}
var views := {}
## 투사체 id → 노드
var shot_views := {}
var _was_fighting := false
var _sync_in := 0.0
var _lost := false


func setup(d: Dungeon, blocked: Dictionary) -> void:
	dungeon = d
	ac = ActionCombat.new(d)
	ac.blocked = blocked
	ac.event.connect(_on_event)


func _cell_pos(p: Vector2) -> Vector3:
	return Vector3(p.x, dungeon.get_height(Vector2i(floori(p.x), floori(p.y))), p.y)


## 파티원 추가. model이 있으면 그 모델을 쓰고(탐험자 몸), 없으면 새로 만듦
func add_member(c: Creature, cell: Vector2i, brain: String, model: CharacterModel = null) -> ActionCombat.Actor:
	var a := ac.add(c, Vector2(cell.x + 0.5, cell.y + 0.5), brain)
	if brain == "player":
		player = a
	if model == null:
		model = _new_model(c.stats)
		model.position = _cell_pos(a.pos)
	_attach(a, model, false)
	return a


func add_foe(id: String, cell: Vector2i, room: int) -> Node3D:
	var c := Creature.new(Catalog.monster(id), 1)
	var a := ac.add(c, Vector2(cell.x + 0.5, cell.y + 0.5), "monster", room)
	a.facing = Vector2.from_angle(randf() * TAU)
	var m := _new_model(c.stats)
	m.position = _cell_pos(a.pos)
	m.face(Vector3(a.facing.x, 0, a.facing.y), true)
	_attach(a, m, true)
	return m


func _new_model(s: CreatureStats) -> CharacterModel:
	var m := CharacterModel.new()
	add_child(m)
	m.setup(s.model, s.sprite_scale, s.weapon_model)
	m.tint(s.tint)
	if s.has_feature("flying"):
		m.set_hover(0.9)
	return m


func _attach(a: ActionCombat.Actor, m: CharacterModel, enemy: bool) -> void:
	var v := {"model": m}
	# HP 바 (머리 위, 늘 카메라를 봄)
	var bar := Node3D.new()
	bar.position.y = m.height + m.hover + 0.25
	m.add_child(bar)
	var bg := _quad(Vector2(0.8, 0.09), Color(0, 0, 0, 0.6))
	bar.add_child(bg)
	var fill := _quad(Vector2(0.78, 0.07), Color(0.85, 0.15, 0.12) if enemy else Color(0.25, 0.8, 0.3))
	fill.position.z = 0.001
	bar.add_child(fill)
	bar.visible = not enemy
	v.bar = bar
	v.fill = fill
	# 공격 예고: 발밑 붉은 원 (근접 범위)
	if enemy:
		var ring := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		var r := ActionCombat.reach_of(a.weapon) if not ActionCombat.is_ranged(a.weapon) else 0.6
		disc.top_radius = r
		disc.bottom_radius = r
		disc.height = 0.02
		ring.mesh = disc
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1, 0.1, 0.05, 0.35)
		ring.material_override = mat
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.position.y = 0.04
		ring.visible = false
		m.add_child(ring)
		v.ring = ring
	views[a] = v


func _quad(size: Vector2, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test = true
	mat.render_priority = 1
	mat.albedo_color = col
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# =====================================================================
# 매 프레임
# =====================================================================

func _physics_process(delta: float) -> void:
	if ac == null or paused or _lost:
		return
	_read_input()
	ac.tick(delta)
	for a in views:
		_sync_view(a, delta)
	_sync_shots()
	var fighting := ac.fighting()
	if _was_fighting and not fighting:
		ac.revive_party()
		var xp := ac.xp_pool
		ac.xp_pool = 0
		fight_over.emit(xp)
	_was_fighting = fighting
	_sync_in -= delta
	if _sync_in <= 0.0:
		_sync_in = 0.25
		party_changed.emit()
	if ac.party_down() and not _lost:
		_lost = true
		defeated.emit()


func _read_input() -> void:
	if player == null:
		return
	var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if camera_rig:
		v = v.rotated(-camera_rig.global_rotation.y)
	player.move = v
	if Input.is_action_just_pressed("dodge"):
		player.want_dodge = true
	if Input.is_action_pressed("attack"):
		player.want_attack = true  # 누르고 있으면 계속 휘두름
	if Input.is_action_just_pressed("skill"):
		var why := ac.use_skill(player)
		if why != "":
			message.emit(why)
	if Input.is_action_just_pressed("potion"):
		var why := ac.use_potion(player)
		if why != "":
			message.emit(why)
		else:
			message.emit("물약을 마셨어요 (남은 %d)" % player.c.resources.get("potion", 0))


func _sync_view(a: ActionCombat.Actor, delta: float) -> void:
	var v: Dictionary = views[a]
	var m: CharacterModel = v.model
	if a != player:
		var target := _cell_pos(a.pos)
		m.position.x = a.pos.x
		m.position.z = a.pos.y
		m.position.y = lerpf(m.position.y, target.y, 1.0 - exp(-14.0 * delta))
	if a.state in ["down", "dead"]:
		(v.bar as Node3D).visible = false
		if v.has("ring"):
			(v.ring as Node3D).visible = false
		return
	m.face(Vector3(a.facing.x, 0, a.facing.y))
	var moving := a.state == "idle" and a.move.length() > 0.1
	if a.state == "idle" or a.state == "stun":
		m.set_base("sprint" if moving else "idle")
	var ratio := clampf(float(a.c.hp) / a.c.stats.max_hp, 0.0, 1.0)
	var fill: MeshInstance3D = v.fill
	fill.scale.x = maxf(ratio, 0.001)
	fill.position.x = -0.39 * (1.0 - ratio)
	if a.c.team != 0:
		(v.bar as Node3D).visible = a.awake and ratio < 1.0
	if v.has("ring"):
		(v.ring as Node3D).visible = a.state == "windup"


func _sync_shots() -> void:
	var live := {}
	for s in ac.shots:
		live[s.id] = true
		if not shot_views.has(s.id):
			shot_views[s.id] = _shot_node(s)
		var n: Node3D = shot_views[s.id]
		n.position = _cell_pos(s.pos) + Vector3(0, 0.75, 0)
	for id in shot_views.keys():
		if not live.has(id):
			(shot_views[id] as Node3D).queue_free()
			shot_views.erase(id)


func _shot_node(s: Dictionary) -> Node3D:
	var w: WeaponData = s.weapon
	var col: Color = {"fire": Color(1, 0.5, 0.1), "cold": Color(0.5, 0.8, 1), "force": Color(0.8, 0.5, 1),
		"radiant": Color(1, 0.95, 0.6), "necrotic": Color(0.4, 0.9, 0.4), "lightning": Color(0.6, 0.7, 1)}.get(
			w.damage_type, Color(0.9, 0.85, 0.7))
	var mi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	var magic := Spells.DMG.has(w.id)
	sph.radius = 0.14 if magic else 0.06
	sph.height = sph.radius * 2.0
	mi.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mi.material_override = mat
	if magic:
		var light := OmniLight3D.new()
		light.light_color = col
		light.omni_range = 2.5
		light.light_energy = 1.5
		mi.add_child(light)
	add_child(mi)
	return mi


# =====================================================================
# 이벤트 → 연출
# =====================================================================

func _on_event(ev: Dictionary) -> void:
	var a: ActionCombat.Actor = ev.get("actor")
	var m: CharacterModel = views[a].model if a != null and views.has(a) else null
	match ev.type:
		"swing":
			if m:
				var magic := Spells.DMG.has(a.weapon.id) if a.weapon else false
				m.play_once("cast" if magic else ("holding-right-shoot" if ev.ranged else "attack-melee-right"))
			if not ev.ranged:
				Sfx.play(self, "swing", -4.0)
			if a.brain == "monster":
				_reveal(a)
		"dodge":
			if m:
				m.play_once("dodge")
			Sfx.play(self, "step")
		"shot":
			Sfx.play(self, "shoot" if not Spells.DMG.has(ev.weapon.id) else "cast")
		"hit":
			var t: ActionCombat.Actor = ev.target
			var tm: CharacterModel = views[t].model if views.has(t) else null
			if tm:
				tm.flash()
				if t.state == "stun":
					tm.play_once("hit")
				_popup(tm, str(ev.damage) + ("!" if ev.crit else ""),
					Color(1, 0.85, 0.2) if ev.crit else (Color(0.75, 0.75, 0.75) if ev.blocked else
						(Color(1, 0.35, 0.3) if t.c.team == 0 else Color(1, 1, 1))), 1.4 if ev.crit else 1.0)
			Sfx.play(self, "crit" if ev.crit else ("miss" if ev.blocked else "hit"))
			if t.c.team != 0:
				_reveal(t)
		"text":
			if m:
				_popup(m, ev.text, Color(0.7, 0.9, 1.0), 0.8)
		"heal":
			if m:
				_popup(m, "+%d" % ev.amount, Color(0.4, 1, 0.5), 1.0)
				if a.state == "idle":
					m.set_base("idle")
			Sfx.play(self, "heal")
		"skill":
			if m and ev.text != "":
				_popup(m, ev.text, Color(1, 0.9, 0.5), 0.9)
		"down":
			if m:
				m.hold("die")
			message.emit("%s 쓰러짐!" % a.c.display_name)
		"death":
			if m:
				m.hold("die")
				var tw := create_tween()
				tw.tween_interval(1.6)
				tw.tween_property(m, "position:y", m.position.y - 1.2, 1.2)
				tw.tween_callback(func() -> void:
					views.erase(a)
					m.queue_free())
			Sfx.play(self, "death")
		"wake":
			_reveal(a)
			if m:
				m.set_base("idle")


## 깨어난 몬스터는 안개와 상관없이 보이게
func _reveal(a: ActionCombat.Actor) -> void:
	if views.has(a):
		(views[a].model as Node3D).visible = true


func _popup(m: Node3D, text: String, col: Color, size: float) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = int(56 * size)
	l.pixel_size = 0.006
	l.outline_size = 12
	l.modulate = col
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 3
	add_child(l)
	l.global_position = m.global_position + Vector3(randf_range(-0.2, 0.2), 1.6, 0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + 0.8, 0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


## 파티원 크리처를 HeroState에서 다시 만듦 (휴식, 레벨업, 물약 사기 뒤). 위치와 모델은 그대로
func refresh_member(a: ActionCombat.Actor, c: Creature) -> void:
	a.c = c
	a.weapon = ActionCombat.primary_weapon(c)
	if c.hp > 0 and a.state == "down":
		a.state = "idle"
		(views[a].model as CharacterModel).set_base("idle")
