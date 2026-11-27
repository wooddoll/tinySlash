## 실시간 액션 전투 (docs/rules.md 10장). 던전 위를 자유롭게 움직이는 크리처들의 공격·구르기·투사체·AI.
## 화면과 떨어져 있어 테스트에서 tick(delta)만으로 돌릴 수 있습니다. 수치는 D&D 그대로:
## 공격이 닿으면 d20 + 공격 보너스 vs AC를 굴려 맞으면 무기 피해, 못 넘기면 절반(막음), 20은 치명타.
class_name ActionCombat
extends RefCounted

const STR := Rules.Ability.STR
const DEX := Rules.Ability.DEX

## 이벤트: {"type": "swing"|"hit"|"dodge"|"shot"|"down"|"death"|"heal"|"wake"|"text", ...}
signal event(ev: Dictionary)

const RADIUS := 0.3
## D&D 속도(칸/라운드)를 초당 유닛으로: 6칸 → 4.5
const PC_SPEED := 0.75
const MONSTER_SPEED := 0.6
## 공격 시간 (초): 휘두르기 전 준비, 휘두른 뒤 회복. 몬스터는 준비가 길어 보고 피할 수 있음
const PC_WINDUP := 0.16
const PC_RECOVER := 0.26
const HEAVY_EXTRA := 0.12
const MONSTER_WINDUP := 0.7
const MONSTER_RECOVER := 0.7
## 몬스터가 한 번 공격하고 다음 공격까지 더 기다리는 시간 (무작위)
const MONSTER_WAIT_MIN := 0.3
const MONSTER_WAIT_MAX := 1.0
## 구르기: 시간, 속도, 무적 시간, 다시 쓸 때까지
const DODGE_TIME := 0.34
const DODGE_SPEED := 7.5
const DODGE_IFRAME := 0.3
const DODGE_COOLDOWN := 0.45
## 구르기 입력을 이만큼 기억했다가 할 수 있게 되면 구름 (공격 중에 눌러도 놓치지 않게)
const DODGE_BUFFER := 0.3
## 맞으면 잠깐 굳음
const HITSTUN := 0.22
## 근접 공격 범위: 기본 + 칸당 거리, 앞쪽 부채꼴 (cos)
const MELEE_BASE := 0.85
const MELEE_PER_REACH := 0.6
const ARC_COS := 0.3
## 투사체 속도, 크기
const SHOT_SPEED := 13.0
const SHOT_RADIUS := 0.35
## 자동 조준: 바라보는 방향에서 이만큼(cos) 안의 가장 가까운 적
const AIM_COS := 0.82
## AI: 한 대상을 동시에 공격 준비할 수 있는 근접 몬스터 수, 대상 다시 고르는 간격(초), 둘러쌀 때 서로 거리
const MAX_MELEE_ATTACKERS := 2
const RETHINK := 0.6
const SPREAD_DIST := 1.1
## 대상 점수: 거리 1유닛당, 잃은 HP 비율, 시전자·집중(MonsterAI.priority 비율), 지금 대상 유지, 이미 노리는 몬스터 1마리당, (동료) 리더·나를 노리는 적
const T_DIST := 10.0
const T_HURT := 15.0
const T_PRIORITY := 0.5
const T_STICK := 12.0
const T_CROWD := 6.0
const T_GUARD := 10.0
## 겁쟁이 도망 확률, 시간
const FLEE_CHANCE := 0.3
const FLEE_TIME := 4.0
## 동료 구르기: 예고를 보고 반응하는 시간, 구를 확률
const ALLY_REACTION := 0.25
const ALLY_DODGE := 0.7
## 몬스터가 깨어나는 거리
const WAKE_RANGE := 6.5
## 동료가 플레이어 곁에 머무는 거리
const FOLLOW_DIST := 1.4


class Actor:
	var c: Creature
	var pos := Vector2.ZERO
	var facing := Vector2(0, 1)
	## idle, windup, recover, dodge, stun, down, dead
	var state := "idle"
	var t := 0.0
	var cooldown := 0.0
	var dodge_cd := 0.0
	var iframe := 0.0
	## 원하는 이동 방향 (입력이나 AI). 길이 0~1
	var move := Vector2.ZERO
	var want_attack := false
	var want_dodge := false
	var dodge_buf := 0.0
	var dodge_dir := Vector2.ZERO
	var weapon: WeaponData
	## 조종: "player", "ally", "monster"
	var brain := "monster"
	var awake := false
	var room := -1
	var target: Actor = null
	var knock := Vector2.ZERO
	## 몬스터가 다음 공격까지 기다리는 시간
	var wait := 0.0
	## 시간이 정해진 효과: 효과 이름 → 남은 초 (끝나면 크리처에서 지움)
	var timers := {}
	## 클래스 기술을 다시 쓸 수 있을 때까지
	var skill_cd := 0.0
	## AI: 대상을 다시 고를 때까지, 도망 남은 시간, 도망 판정을 했는지, 기다릴 때 도는 방향
	var think_t := 0.0
	var flee := 0.0
	var flee_checked := false
	var orbit := 1.0 if randf() < 0.5 else -1.0
	## 동료가 이미 반응한 공격 예고 (몬스터 id)
	var reacted := {}

	func _init(cr: Creature, p: Vector2) -> void:
		c = cr
		pos = p

	func alive() -> bool:
		return c.is_alive() and c.hp > 0

	func busy() -> bool:
		return state in ["windup", "recover", "dodge", "stun", "down", "dead"]


var dungeon: Dungeon
var dice: Dice
var actors: Array[Actor] = []
## {pos, vel, owner, weapon, left (남은 거리), hostile_to_team}
var shots: Array[Dictionary] = []
## 지나갈 수 없는 칸 (텐트, 상인)
var blocked := {}
## 쓰러뜨린 몬스터 XP (나눠 주기 전)
var xp_pool := 0
var _shot_id := 0
## 길 찾기: 목표 칸 → {칸: 걸음 수}. 한 걸음마다 새로 만듦
var _flow := {}
var _stench_t := 0.0
const FLOW_LIMIT := 40


func _init(d: Dungeon, dc: Dice = null) -> void:
	dungeon = d
	dice = dc if dc else Dice.new()


func add(c: Creature, p: Vector2, brain: String, room := -1) -> Actor:
	var a := Actor.new(c, p)
	a.brain = brain
	a.room = room
	a.weapon = primary_weapon(c)
	a.awake = brain != "monster"
	actors.append(a)
	return a


## 기본 공격 무기: 공격 굴림을 하는 소마법이 있으면 그것(주문 화살), 아니면 첫 무기
static func primary_weapon(c: Creature) -> WeaponData:
	if c.stats.is_pc:
		for id in c.stats.spells:
			if Spells.DMG.has(id) and Spells.DATA[id].level == 0 and Spells.DMG[id].kind == "attack" \
					and Spells.DMG[id].get("ranged", true):
				return Spells.spell_weapon(c, id, 0)
	if c.stats.weapons.is_empty():
		return null
	return c.stats.weapons[0]


static func speed_of(a: Actor) -> float:
	var k := PC_SPEED if a.c.stats.is_pc else MONSTER_SPEED
	if a.c.has_effect("dashing"):
		k *= 1.6
	return a.c.speed() * k


## 근접 무기가 닿는 거리 (유닛)
static func reach_of(w: WeaponData) -> float:
	return MELEE_BASE + MELEE_PER_REACH * (w.melee_reach() if w else 1)


static func is_ranged(w: WeaponData) -> bool:
	return w != null and w.ranged


func party() -> Array[Actor]:
	return actors.filter(func(a: Actor) -> bool: return a.c.team == 0)


func foes_of(a: Actor) -> Array[Actor]:
	return actors.filter(func(b: Actor) -> bool: return b.alive() and b.c.is_hostile_to(a.c))


func can_stand(p: Vector2) -> bool:
	for sx in [-RADIUS, RADIUS]:
		for sy in [-RADIUS, RADIUS]:
			var cc := Vector2i(floori(p.x + sx), floori(p.y + sy))
			if not dungeon.is_walkable(cc) or blocked.has(cc):
				return false
	return true


## a에서 b까지 벽에 막히지 않았는지 (칸을 따라 걸음)
func clear_line(a: Vector2, b: Vector2) -> bool:
	var n := ceili(a.distance_to(b) / 0.35)
	for i in range(1, n):
		var p := a.lerp(b, float(i) / n)
		if not dungeon.is_walkable(Vector2i(floori(p.x), floori(p.y))):
			return false
	return true


# =====================================================================
# 한 걸음
# =====================================================================

func tick(delta: float) -> void:
	_flow.clear()
	for a in actors:
		_think(a, delta)
	for a in actors:
		_step(a, delta)
	_separate()
	_fly(delta)
	_stench(delta)


func _step(a: Actor, delta: float) -> void:
	a.cooldown = maxf(0.0, a.cooldown - delta)
	a.skill_cd = maxf(0.0, a.skill_cd - delta)
	for k in a.timers.keys():
		a.timers[k] -= delta
		if a.timers[k] <= 0.0:
			a.timers.erase(k)
			a.c.remove_effects(k)
			event.emit({"type": "text", "actor": a, "text": "%s 끝" % EFFECT_NAMES.get(k, k)})
	a.dodge_cd = maxf(0.0, a.dodge_cd - delta)
	a.iframe = maxf(0.0, a.iframe - delta)
	if a.state == "dead":
		return
	if a.c.hp <= 0 and a.state != "down":
		_fall(a)
		return
	if a.state == "down":
		if a.c.hp > 0:
			a.state = "idle"
		return
	if a.c.has_effect("paralyzed") and a.state != "stun":
		a.state = "stun"
	if a.c.has_effect("paralyzed"):
		a.t = maxf(a.t, 0.05)
	a.t -= delta
	if a.want_dodge:
		a.dodge_buf = DODGE_BUFFER
	else:
		a.dodge_buf = maxf(0.0, a.dodge_buf - delta)
	var dodge_ok: bool = a.dodge_buf > 0.0 and a.dodge_cd <= 0.0 and a.c.speed() > 0
	var vel := Vector2.ZERO
	# [변경] 파티는 공격 뒤 회복 동작을 구르기로 끊을 수 있음
	if a.state == "recover" and a.c.stats.is_pc and dodge_ok:
		a.state = "idle"
	match a.state:
		"dodge":
			vel = a.dodge_dir * DODGE_SPEED
			if a.t <= 0.0:
				a.state = "idle"
				a.dodge_cd = DODGE_COOLDOWN
		"windup":
			if a.t <= 0.0:
				_release(a)
				a.state = "recover"
				a.t = PC_RECOVER if a.c.stats.is_pc else MONSTER_RECOVER
		"recover", "stun":
			if a.t <= 0.0:
				a.state = "idle"
		_:
			if dodge_ok:
				a.dodge_buf = 0.0
				_dodge(a)
			elif a.want_attack and a.cooldown <= 0.0 and a.weapon != null:
				_swing(a)
			else:
				var m := a.move.limit_length(1.0)
				vel = m * speed_of(a)
				if m.length() > 0.1:
					a.facing = m.normalized()
	a.want_dodge = false
	a.want_attack = false
	vel += a.knock
	a.knock = a.knock.move_toward(Vector2.ZERO, 12.0 * delta)
	_move(a, vel * delta)


func _move(a: Actor, step: Vector2) -> void:
	if step == Vector2.ZERO:
		return
	var p := a.pos
	if can_stand(p + Vector2(step.x, 0)):
		p.x += step.x
	if can_stand(p + Vector2(0, step.y)):
		p.y += step.y
	a.pos = p


## 겹치지 않게 서로 밀어냄
func _separate() -> void:
	for i in actors.size():
		var a := actors[i]
		if not a.alive():
			continue
		for j in range(i + 1, actors.size()):
			var b := actors[j]
			if not b.alive():
				continue
			var d := b.pos - a.pos
			var dist := d.length()
			var need := RADIUS * 2.0
			if dist < need and dist > 0.0001:
				var push := d / dist * (need - dist) * 0.5
				_move(a, -push)
				_move(b, push)


func _dodge(a: Actor) -> void:
	a.state = "dodge"
	a.t = DODGE_TIME
	a.iframe = DODGE_IFRAME
	a.dodge_dir = (a.move if a.move.length() > 0.2 else a.facing).normalized()
	a.facing = a.dodge_dir
	event.emit({"type": "dodge", "actor": a})


func _swing(a: Actor) -> void:
	# 자동 조준: 바라보는 쪽 가까운 적에게 몸을 돌림
	var t := aim_target(a)
	if t:
		a.facing = (t.pos - a.pos).normalized()
	a.state = "windup"
	var w := a.weapon
	if a.c.stats.is_pc:
		a.t = PC_WINDUP + (HEAVY_EXTRA if w.heavy else 0.0)
		a.cooldown = a.t + PC_RECOVER
	else:
		a.t = MONSTER_WINDUP
		a.cooldown = MONSTER_WINDUP + MONSTER_RECOVER
	event.emit({"type": "swing", "actor": a, "ranged": is_ranged(w), "windup": a.t})


## 바라보는 방향 부채꼴 안에서 가장 가까운 적 (사거리 안). 없으면 null
func aim_target(a: Actor) -> Actor:
	var w := a.weapon
	var max_d := float(w.range_normal) if is_ranged(w) else reach_of(w) + 1.2
	var best: Actor = null
	var best_d := INF
	for b in foes_of(a):
		var d := b.pos - a.pos
		var dist := d.length()
		if dist > max_d or dist < 0.001:
			continue
		var cosv := d.normalized().dot(a.facing)
		var lim := AIM_COS if is_ranged(w) else ARC_COS - 0.4
		if cosv < lim:
			continue
		if not clear_line(a.pos, b.pos):
			continue
		if dist < best_d:
			best_d = dist
			best = b
	return best


## 준비가 끝나 실제로 휘두름 / 쏨
func _release(a: Actor) -> void:
	var w := a.weapon
	if is_ranged(w):
		_shot_id += 1
		shots.append({"id": _shot_id, "pos": a.pos + a.facing * 0.4, "vel": a.facing * SHOT_SPEED, "owner": a, "weapon": w,
			"left": float(w.range_long)})
		event.emit({"type": "shot", "actor": a, "weapon": w})
		return
	var reach := reach_of(w)
	var hits: Array[Actor] = []
	for b in foes_of(a):
		var d := b.pos - a.pos
		var dist := d.length()
		if dist > reach + RADIUS or dist < 0.001:
			continue
		if d.normalized().dot(a.facing) < ARC_COS:
			continue
		hits.append(b)
	hits.sort_custom(func(x: Actor, y: Actor) -> bool: return a.pos.distance_to(x.pos) < a.pos.distance_to(y.pos))
	# [변경] 무거운 무기(Heavy)는 부채꼴 안 모두를 벰. 나머지는 가장 가까운 하나
	if not w.heavy and hits.size() > 1:
		hits.resize(1)
	# 몬스터의 여러 번 공격(Multiattack)은 한 번 휘두를 때 같은 대상에게 그만큼 굴림
	var times := maxi(1, a.c.stats.multiattack) if not a.c.stats.is_pc else 1
	for b in hits:
		for i in times:
			if b.alive():
				strike(a, b, w)


func _fly(delta: float) -> void:
	for s in shots.duplicate():
		var step: Vector2 = s.vel * delta
		s.pos += step
		s.left -= step.length()
		var owner: Actor = s.owner
		var hit: Actor = null
		for b in actors:
			if b.alive() and b.c.is_hostile_to(owner.c) and (s.pos as Vector2).distance_to(b.pos) <= SHOT_RADIUS + RADIUS:
				hit = b
				break
		var wall := not dungeon.is_walkable(Vector2i(floori(s.pos.x), floori(s.pos.y)))
		if hit:
			strike(owner, hit, s.weapon)
		if hit or wall or s.left <= 0.0:
			shots.erase(s)


# =====================================================================
# 맞히기 (D&D 굴림)
# =====================================================================

## 공격 보너스와 능력 수정치
static func attack_mods(c: Creature, w: WeaponData) -> Dictionary:
	var am := c.mod(DEX) if w.ranged else c.mod(STR)
	if w.finesse:
		am = maxi(c.mod(STR), c.mod(DEX))
	if w.ability >= 0:
		am = c.mod(w.ability)
	return {"mod": am, "bonus": am + c.pb()}


## a의 무기 w가 b에게 닿음. 구르는 중(무적)이면 피함
func strike(a: Actor, b: Actor, w: WeaponData) -> Dictionary:
	if b.iframe > 0.0:
		event.emit({"type": "text", "actor": b, "text": "회피!"})
		return {"dodged": true}
	var m := attack_mods(a.c, w)
	# 중독되면 공격 불리점 [SRD]
	var r := dice.d20(-1 if a.c.has_effect("poisoned") else 0)
	var nat: int = r.value
	var total: int = nat + m.bonus
	var full: bool = nat == 20 or (nat != 1 and total >= b.c.ac())
	var crit: bool = nat >= a.c.crit_threshold()
	# 마비된 대상을 바로 옆에서 맞히면 치명타 [SRD]
	if full and b.c.has_effect("paralyzed") and a.pos.distance_to(b.pos) <= 1.6:
		crit = true
	var count := w.dice_count
	if a.c.stats.has_feature("swarm") and a.c.is_bloodied():
		count = maxi(1, count / 2)  # 떼: HP가 절반 이하면 주사위 절반 [SRD]
	count *= 2 if crit else 1
	var dmg: int = Dice.sum(dice.roll(count, w.dice_sides)) + (m.mod if w.add_mod else 0)
	if a.c.has_effect("raging") and not w.ranged:
		dmg += ClassFeatures.rage_damage(a.c.stats.level)
	var mark := b.c.find_effect("marked")
	if not mark.is_empty() and mark.owner == a.c:
		dmg += Dice.sum(dice.roll(2 if crit else 1, 6))
	dmg = maxi(1, dmg)
	if not full:
		# [변경] 파티의 공격은 닿았지만 AC를 못 넘기면 절반, 몬스터의 공격은 막혀서 0
		dmg = maxi(1, dmg / 2) if a.c.team == 0 else 0
	if dmg <= 0:
		event.emit({"type": "text", "actor": b, "text": "막음"})
		return {"blocked": true, "damage": 0}
	var res := Damage.apply(b.c, dmg, w.damage_type, crit)
	if res.killed and b.c.stats.has_feature("undead_fortitude") and w.damage_type != "radiant" and not crit:
		# Undead Fortitude [SRD]: 광휘 피해나 치명타가 아니면 CON 내성 DC 5+피해로 HP 1로 버팀
		if save(b.c, Rules.Ability.CON, 5 + res.dealt):
			b.c.dead = false
			b.c.hp = 1
			res.killed = false
			event.emit({"type": "text", "actor": b, "text": "버팀!"})
	if full and res.dealt >= 0 and b.c.is_alive():
		_on_hit(a, b, w, res.dealt)
	b.awake = true
	if b.target == null:
		b.target = a
	# 맞으면 밀리고 굳음 (큰 크리처는 덜)
	# [변경] 몬스터는 공격 준비 중에 버팀 (치명타만 끊음): 계속 때려서 공격을 막을 수 없고, 예고를 보고 굴러야 함
	var armored: bool = b.state == "windup" and not b.c.stats.is_pc and not crit
	var push := (b.pos - a.pos).normalized()
	b.knock = push * (0.5 if armored else 2.5 if b.c.stats.size <= Rules.Size.MEDIUM else 0.8)
	if not armored and b.state in ["idle", "windup", "recover"] and res.dealt > 0 and (b.c.stats.size <= Rules.Size.MEDIUM or crit):
		b.state = "stun"
		b.t = HITSTUN
	var ev := {"type": "hit", "actor": a, "target": b, "damage": res.dealt, "crit": crit, "blocked": not full,
		"roll": total, "ac": b.c.ac()}
	event.emit(ev)
	if b.c.hp <= 0:
		_fall(b)
	return ev


## 내성 굴림 (마비·기절이면 STR·DEX 자동 실패, Bless +1d4)
func save(c: Creature, ability: int, dc: int) -> bool:
	if c.has_effect("paralyzed") and (ability == STR or ability == DEX):
		return false
	var r := dice.d20(signi(ClassFeatures.save_adv(c, ability)))
	var total: int = r.value + c.save_bonus(ability)
	if c.has_effect("blessed"):
		total += dice.roll_die(4)
	return total >= dc


## 몬스터 공격의 추가 효과 (턴제 Combat._apply_on_hit과 같음): 구울 마비, 섀도 근력 흡수, 스펙터 생명 흡수
func _on_hit(a: Actor, b: Actor, w: WeaponData, dealt: int) -> void:
	var eff := w.on_hit_always
	if w.on_hit_save >= 0 and w.on_hit_effect != "":
		if w.on_hit_effect == "paralyzed" and (b.c.stats.creature_type == "undead" or b.c.stats.condition_immunities.has("paralyzed")):
			return
		if save(b.c, w.on_hit_save, w.on_hit_dc):
			return
		eff = w.on_hit_effect
	match eff:
		"paralyzed":
			# [변경] 마비는 1라운드 대신 PARALYZE_TIME초
			b.c.remove_effects("paralyzed")
			b.c.add_effect("paralyzed", a.c, "never")
			b.timers["paralyzed"] = PARALYZE_TIME
			event.emit({"type": "text", "actor": b, "text": "마비!"})
		"drain_max":
			if dealt <= 0:
				return
			b.c.max_hp_loss += dealt
			b.c.stats.max_hp = maxi(0, b.c.stats.max_hp - dealt)
			b.c.hp = mini(b.c.hp, b.c.stats.max_hp)
			event.emit({"type": "text", "actor": b, "text": "최대 HP -%d" % dealt})
			if b.c.stats.max_hp <= 0:
				Damage._kill(b.c)
				_fall(b)
		"str_drain":
			var loss := dice.roll_die(4)
			b.c.str_loss += loss
			event.emit({"type": "text", "actor": b, "text": "근력 -%d" % loss})
			if b.c.stats.scores[STR] - b.c.str_loss <= 0:
				Damage._kill(b.c)
				_fall(b)


## 가스트 Stench [SRD]: 1.6유닛 안에 있으면 6초(1라운드)마다 CON DC 10. 실패하면 6초 중독, 성공하면 그 가스트에 면역
func _stench(delta: float) -> void:
	_stench_t -= delta
	if _stench_t > 0.0:
		return
	_stench_t = ROUND
	for g in actors:
		if not g.alive() or not g.c.stats.has_feature("stench"):
			continue
		for b in actors:
			if b == g or not b.alive() or not b.c.is_hostile_to(g.c) or b.pos.distance_to(g.pos) > 1.6:
				continue
			if b.c.has_effect("poisoned") or b.c.stats.condition_immunities.has("poisoned") 					or not b.c.find_effect("stench_immune", g.c).is_empty():
				continue
			if save(b.c, Rules.Ability.CON, 10):
				b.c.add_effect("stench_immune", b.c, "never", 0, g.c)
			else:
				b.c.add_effect("poisoned", b.c, "never")
				b.timers["poisoned"] = ROUND
				event.emit({"type": "text", "actor": b, "text": "악취: 중독!"})


func _fall(b: Actor) -> void:
	if b.state in ["down", "dead"]:
		return
	if b.c.stats.is_pc and b.c.is_alive():
		b.state = "down"
		event.emit({"type": "down", "actor": b})
	else:
		b.state = "dead"
		if not b.c.stats.is_pc:
			xp_pool += b.c.stats.xp
		event.emit({"type": "death", "actor": b})


# =====================================================================
# 생각 (AI)
# =====================================================================

func _think(a: Actor, delta: float) -> void:
	if not a.alive() or a.brain == "player":
		return
	if a.brain == "monster":
		_think_monster(a, delta)
	else:
		_think_ally(a)


func _nearest(a: Actor, list: Array[Actor]) -> Actor:
	var best: Actor = null
	var bd := INF
	for b in list:
		var d := a.pos.distance_to(b.pos)
		if d < bd:
			bd = d
			best = b
	return best


func _think_monster(a: Actor, delta: float) -> void:
	a.move = Vector2.ZERO
	var foes := foes_of(a)
	if foes.is_empty():
		return
	var near := _nearest(a, foes)
	if not a.awake:
		if a.pos.distance_to(near.pos) <= WAKE_RANGE and clear_line(a.pos, near.pos):
			wake_room(a.room)
		return
	a.wait = maxf(0.0, a.wait - delta)
	# 겁쟁이(cowardly): 처음 반 넘게 다치면 30% 확률로 몇 초 도망
	if a.c.stats.has_feature("cowardly") and not a.flee_checked and a.c.is_bloodied():
		a.flee_checked = true
		if randf() < FLEE_CHANCE:
			a.flee = FLEE_TIME
			event.emit({"type": "text", "actor": a, "text": "도망!"})
	if a.flee > 0.0:
		a.flee -= delta
		var away := (a.pos - near.pos).normalized()
		a.move = steer(a, a.pos + away * 3.0)
		return
	# 대상: 가끔 점수로 다시 고름 (가까움, 다친 정도, 시전자, 이미 몰린 대상은 덜)
	a.think_t -= delta
	if a.target == null or not a.target.alive() or a.think_t <= 0.0:
		a.think_t = RETHINK
		var best: Actor = null
		var bv := -INF
		for b in foes:
			var v := monster_target_score(a, b)
			if v > bv:
				bv = v
				best = b
		a.target = best
	var t := a.target
	var to := t.pos - a.pos
	var dist := to.length()
	if is_ranged(a.weapon):
		# 궁수: 4~7 유닛 거리를 두고 쏨
		if dist < 3.5:
			a.move = -to.normalized()
		elif dist > minf(7.0, a.weapon.range_normal) or not clear_line(a.pos, t.pos):
			a.move = steer(a, t.pos)
		elif a.wait <= 0.0 and a.cooldown <= 0.0:
			a.facing = to.normalized()
			a.want_attack = true
			a.wait = randf_range(MONSTER_WAIT_MIN + 0.2, MONSTER_WAIT_MAX + 0.2)
		return
	var reach := reach_of(a.weapon)
	var spread := _spread(a, t)
	if dist > reach * 0.85:
		a.move = (steer(a, t.pos) + spread).normalized()
		return
	a.facing = to.normalized()
	# 동시에 공격 준비하는 몬스터 수 제한: 차례가 아니면 둘레를 돌며 기다림
	if a.wait <= 0.0 and a.cooldown <= 0.0:
		if _attackers_on(t, a) < MAX_MELEE_ATTACKERS:
			a.want_attack = true
			a.wait = randf_range(MONSTER_WAIT_MIN, MONSTER_WAIT_MAX)
			return
		a.wait = randf_range(0.15, 0.35)
	if a.state == "idle":
		a.move = (to.normalized().orthogonal() * a.orbit * 0.45 + spread).limit_length(0.6)


## 몬스터가 대상 b를 노릴 가치
func monster_target_score(a: Actor, b: Actor) -> float:
	var v := -a.pos.distance_to(b.pos) * T_DIST
	v += (1.0 - float(b.c.hp) / maxf(1.0, b.c.stats.max_hp)) * T_HURT
	v += MonsterAI.priority(b.c) * T_PRIORITY
	if b == a.target:
		v += T_STICK
	v -= _attackers_on(b, a, true) * T_CROWD
	return v


## b를 노리는 다른 근접 몬스터 수. all이면 노리기만 해도, 아니면 지금 공격 준비 중인 것만
func _attackers_on(b: Actor, me: Actor, all := false) -> int:
	var n := 0
	for o in actors:
		if o == me or o.brain != "monster" or not o.alive() or o.target != b or is_ranged(o.weapon):
			continue
		# 같은 걸음에 이미 공격하기로 한 몬스터(want_attack)도 셈
		if all or o.state == "windup" or o.want_attack:
			n += 1
	return n


## 같은 대상을 둘러싼 다른 몬스터에게서 비켜나는 힘 (한쪽에 몰리지 않고 둘러쌈)
func _spread(a: Actor, t: Actor) -> Vector2:
	var push := Vector2.ZERO
	for o in actors:
		if o == a or o.brain != "monster" or not o.alive() or o.target != t:
			continue
		var d := a.pos - o.pos
		var l := d.length()
		if l < SPREAD_DIST and l > 0.001:
			push += d / l * (SPREAD_DIST - l) / SPREAD_DIST
	return push * 0.8


## 동료: 깨어 있는 적이 있으면 싸우고, 없으면 플레이어를 따라감
func _think_ally(a: Actor) -> void:
	a.move = Vector2.ZERO
	var foes := foes_of(a).filter(func(b: Actor) -> bool: return b.awake and a.pos.distance_to(b.pos) < 12.0)
	var leader: Actor = null
	for b in actors:
		if b.brain == "player":
			leader = b
	if foes.is_empty():
		if leader and a.pos.distance_to(leader.pos) > FOLLOW_DIST:
			a.move = steer(a, leader.pos) * minf(1.0, (a.pos.distance_to(leader.pos) - FOLLOW_DIST) + 0.3)
		return
	# 나를 노린 공격 예고를 보면 (반응 시간 뒤) 확률로 구름
	if _ally_dodge(a, foes):
		return
	# 회복 기술이 있으면 많이 다친 동료(쓰러진 동료 먼저)를 고침
	if a.c.stats.id in HEALERS and a.skill_cd <= 0.0 and not a.busy():
		var hurt := _most_hurt(a)
		if hurt and (hurt.c.hp <= 0 or hurt.c.hp < hurt.c.stats.max_hp * 0.4):
			if use_skill(a) == "":
				return
	# 대상: 가까운 적, 리더나 나를 노리는 적, 다친 적
	var t: Actor = null
	var bv := -INF
	for b in foes:
		var v := -a.pos.distance_to(b.pos) * T_DIST + (1.0 - float(b.c.hp) / maxf(1.0, b.c.stats.max_hp)) * T_HURT
		if b.target == leader or b.target == a:
			v += T_GUARD
		if b == a.target:
			v += T_STICK
		if v > bv:
			bv = v
			t = b
	a.target = t
	var to := t.pos - a.pos
	var dist := to.length()
	if is_ranged(a.weapon):
		if dist < 2.5:
			a.move = -to.normalized()
		elif dist > minf(8.0, a.weapon.range_normal) or not clear_line(a.pos, t.pos):
			a.move = steer(a, t.pos)
		elif a.cooldown <= 0.0:
			a.facing = to.normalized()
			a.want_attack = true
		return
	if dist > reach_of(a.weapon) * 0.85:
		a.move = steer(a, t.pos)
	elif a.cooldown <= 0.0:
		a.facing = to.normalized()
		a.want_attack = true


func _ally_dodge(a: Actor, foes: Array[Actor]) -> bool:
	for f in foes:
		if f.state != "windup":
			a.reacted.erase(f.get_instance_id())
			continue
		if MONSTER_WINDUP - f.t < ALLY_REACTION or a.reacted.has(f.get_instance_id()):
			continue
		var ranged := is_ranged(f.weapon)
		var threat := (ranged and f.facing.dot((a.pos - f.pos).normalized()) > 0.9) 			or (not ranged and f.target == a and a.pos.distance_to(f.pos) <= reach_of(f.weapon) + 0.8)
		if not threat:
			continue
		a.reacted[f.get_instance_id()] = true
		if randf() < ALLY_DODGE:
			var away := (a.pos - f.pos).normalized()
			a.move = away.orthogonal() if ranged else away
			a.want_dodge = true
			return true
	return false


## 목표로 가는 이동 방향. 몸 너비로 곧장 갈 수 있으면 곧장, 막혔으면 칸 길 찾기 (기둥·벽 돌아가기)
func steer(a: Actor, goal: Vector2) -> Vector2:
	var to := goal - a.pos
	if to.length() < 0.01:
		return Vector2.ZERO
	if _clear_wide(a.pos, goal):
		return to.normalized()
	var gc := Vector2i(floori(goal.x), floori(goal.y))
	if not _flow.has(gc):
		_flow[gc] = _bfs(gc)
	var field: Dictionary = _flow[gc]
	var here := Vector2i(floori(a.pos.x), floori(a.pos.y))
	var best := here
	var bd: int = field.get(here, 1 << 20)
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var n := here + Vector2i(dx, dy)
			if n == here or not field.has(n):
				continue
			# 대각선은 양옆이 모두 비었을 때만 (모서리 끼임 방지)
			if dx != 0 and dy != 0 and not (field.has(here + Vector2i(dx, 0)) and field.has(here + Vector2i(0, dy))):
				continue
			if field[n] < bd:
				bd = field[n]
				best = n
	if best == here:
		return to.normalized()
	return (Vector2(best) + Vector2(0.5, 0.5) - a.pos).normalized()


func _bfs(goal: Vector2i) -> Dictionary:
	var dist := {goal: 0}
	var queue: Array[Vector2i] = [goal]
	var i := 0
	while i < queue.size():
		var c := queue[i]
		i += 1
		var dc: int = dist[c]
		if dc >= FLOW_LIMIT:
			continue
		for n in [c + Vector2i.RIGHT, c + Vector2i.LEFT, c + Vector2i.UP, c + Vector2i.DOWN]:
			if dist.has(n) or not dungeon.is_walkable(n) or blocked.has(n):
				continue
			dist[n] = dc + 1
			queue.append(n)
	return dist


## 몸 너비(양옆 RADIUS)로 막히지 않고 곧장 갈 수 있는지
func _clear_wide(a: Vector2, b: Vector2) -> bool:
	var side := (b - a).normalized().orthogonal() * (RADIUS + 0.02)
	return clear_line(a, b) and clear_line(a + side, b + side) and clear_line(a - side, b - side)


func wake_room(room: int) -> void:
	for b in actors:
		if b.brain == "monster" and not b.awake and b.alive() and (room < 0 or b.room == room):
			b.awake = true
			event.emit({"type": "wake", "actor": b})


## 깨어 있는 적이 남았는가
func fighting() -> bool:
	for b in actors:
		if b.brain == "monster" and b.awake and b.alive():
			return true
	return false


## 방의 몬스터가 모두 쓰러졌는가
func room_clear(room: int) -> bool:
	for b in actors:
		if b.brain == "monster" and b.room == room and b.alive():
			return false
	return true


## 파티가 모두 쓰러졌는가
func party_down() -> bool:
	for b in party():
		if b.alive():
			return false
	return true


## 싸움이 끝난 뒤 쓰러진 파티원을 HP 1로 일으킴 [변경]
func revive_party() -> void:
	for b in party():
		if b.c.is_alive() and b.c.hp <= 0:
			b.c.hp = 1
			b.c.remove_condition("unconscious")
			b.c.remove_condition("prone")
			b.state = "idle"
			event.emit({"type": "heal", "actor": b, "amount": 1})


# =====================================================================
# 물약과 클래스 기술 (rules 10.4)
# =====================================================================

const EFFECT_NAMES := {"raging": "분노", "dashing": "질주", "marked": "표식", "paralyzed": "마비", "poisoned": "중독"}
## 실시간에서 D&D 1라운드로 치는 시간, 구울 마비 시간 (초)
const ROUND := 6.0
const PARALYZE_TIME := 2.0
const SKILL_COOLDOWN := 1.0
## 동료 AI가 회복 기술을 쓰는 클래스
const HEALERS := ["cleric", "bard", "druid", "paladin"]
## 클래스 기술 이름과 설명
const SKILLS := {
	"fighter": ["Second Wind", "1d10 + 레벨 회복 (짧은 휴식마다)"],
	"barbarian": ["분노", "30초 동안 근접 피해 +2, 베기·찌르기·때리기 피해 절반 (긴 휴식마다 몇 번)"],
	"cleric": ["Healing Word", "가장 다친 아군 2d4 + WIS 회복, 쓰러진 아군도 일으킴 (1레벨 슬롯)"],
	"bard": ["Healing Word", "가장 다친 아군 2d4 + CHA 회복, 쓰러진 아군도 일으킴 (1레벨 슬롯)"],
	"druid": ["Healing Word", "가장 다친 아군 2d4 + WIS 회복, 쓰러진 아군도 일으킴 (1레벨 슬롯)"],
	"paladin": ["Lay on Hands", "가장 다친 아군을 치유 풀로 회복"],
	"wizard": ["Magic Missile", "빗나가지 않는 다트 3개, 하나에 1d4+1 (1레벨 슬롯)"],
	"sorcerer": ["Magic Missile", "빗나가지 않는 다트 3개, 하나에 1d4+1 (1레벨 슬롯)"],
	"warlock": ["Hex", "조준한 적을 저주: 맞힐 때마다 1d6 추가 (계약 슬롯)"],
	"ranger": ["Hunter's Mark", "조준한 적에 표식: 맞힐 때마다 1d6 추가 (무료 횟수, 다음은 슬롯)"],
	"rogue": ["질주", "3초 동안 빠르게 움직임 (6초마다)"],
	"monk": ["연타", "조준한 적에게 맨손 타격 두 번 (집중 1)"],
}


func use_potion(a: Actor) -> String:
	if a.c.resources.get("potion", 0) <= 0:
		return "물약이 없어요"
	if not a.alive() or a.state in ["dodge", "down", "dead"]:
		return "지금은 못 마셔요"
	if a.c.hp >= a.c.stats.max_hp:
		return "HP가 가득 찼어요"
	a.c.resources["potion"] -= 1
	_heal(a, Dice.sum(dice.roll(2, 4)) + 2)
	return ""


func _heal(b: Actor, amount: int) -> void:
	var got := Damage.heal(b.c, amount)
	if b.state == "down" and b.c.hp > 0:
		b.state = "idle"
	event.emit({"type": "heal", "actor": b, "amount": got})


## 가장 다친 파티원 (쓰러진 이 먼저)
func _most_hurt(a: Actor) -> Actor:
	var best: Actor = null
	var br := 2.0
	for b in actors:
		if b.c.team != a.c.team or not b.c.is_alive() or b.c.hp >= b.c.stats.max_hp:
			continue
		if a.pos.distance_to(b.pos) > 12.0:
			continue
		var r := float(b.c.hp) / b.c.stats.max_hp
		if r < br:
			br = r
			best = b
	return best


## 조준한 적, 없으면 가까이 깨어 있는 적
func _skill_target(a: Actor, max_d: float) -> Actor:
	var w := a.weapon
	a.weapon = WeaponData.new()
	a.weapon.ranged = true
	a.weapon.range_normal = int(max_d)
	var t := aim_target(a)
	a.weapon = w
	if t == null:
		var cands := foes_of(a).filter(func(b: Actor) -> bool:
			return a.pos.distance_to(b.pos) <= max_d and clear_line(a.pos, b.pos))
		t = _nearest(a, cands)
	return t


## 클래스 기술 (B). 쓰면 "", 못 쓰면 이유
func use_skill(a: Actor) -> String:
	if not a.alive() or a.busy():
		return "지금은 못 써요"
	if a.skill_cd > 0.0:
		return "잠깐만요"
	var c := a.c
	var msg := ""
	match c.stats.id:
		"fighter":
			if c.resources.get("second_wind", 0) <= 0:
				return "Second Wind를 다 썼어요"
			if c.hp >= c.stats.max_hp:
				return "HP가 가득 찼어요"
			c.resources["second_wind"] -= 1
			_heal(a, dice.roll_die(10) + c.stats.level)
		"barbarian":
			if c.has_effect("raging"):
				return "이미 분노 중"
			if c.resources.get("rage", 0) <= 0:
				return "분노를 다 썼어요"
			c.resources["rage"] -= 1
			c.add_effect("raging", c, "never")
			a.timers["raging"] = 30.0
			msg = "분노!"
		"cleric", "bard", "druid":
			var slot := Spells.lowest_slot(c, 1)
			if slot == 0:
				return "주문 슬롯이 없어요"
			var t := _most_hurt(a)
			if t == null:
				return "다친 아군이 없어요"
			c.resources["slot%d" % slot] -= 1
			_heal(t, Spells.heal_amount(dice, c, "healing_word", slot).amount)
		"paladin":
			var pool: int = c.resources.get("lay_on_hands", 0)
			var t := _most_hurt(a)
			if pool <= 0:
				return "치유 풀이 비었어요"
			if t == null:
				return "다친 아군이 없어요"
			var amount := mini(pool, t.c.stats.max_hp - t.c.hp)
			c.resources["lay_on_hands"] = pool - amount
			_heal(t, amount)
		"wizard", "sorcerer":
			var slot := Spells.lowest_slot(c, 1)
			if slot == 0:
				return "주문 슬롯이 없어요"
			var t := _skill_target(a, 24.0)
			if t == null:
				return "보이는 적이 없어요"
			c.resources["slot%d" % slot] -= 1
			var total := 0
			for i in 2 + slot:
				total += dice.roll_die(4) + 1
			a.facing = (t.pos - a.pos).normalized()
			var res := Damage.apply(t.c, total, "force")
			t.awake = true
			event.emit({"type": "hit", "actor": a, "target": t, "damage": res.dealt, "crit": false, "blocked": false,
				"spell": "magic_missile"})
			if t.c.hp <= 0:
				_fall(t)
		"warlock", "ranger":
			var t := _skill_target(a, 18.0)
			if t == null:
				return "보이는 적이 없어요"
			var free: bool = c.resources.get("free_mark", 0) > 0
			var slot := 0 if free else Spells.lowest_slot(c, 1)
			if not free and slot == 0:
				return "주문 슬롯이 없어요"
			if free:
				c.resources["free_mark"] -= 1
			else:
				c.resources["slot%d" % slot] -= 1
			for b in actors:
				b.c.remove_effects_from(c, ["marked"])
			t.c.add_effect("marked", c, "never")
			t.awake = true
			msg = "%s → %s" % [SKILLS[c.stats.id][0], t.c.display_name]
		"rogue":
			c.add_effect("dashing", c, "never")
			a.timers["dashing"] = 3.0
			a.skill_cd = 6.0
			msg = "질주!"
		"monk":
			if c.resources.get("focus", 0) <= 0:
				return "집중을 다 썼어요"
			var t := _skill_target(a, reach_of(c.unarmed_weapon()) + 0.6)
			if t == null:
				return "가까운 적이 없어요"
			c.resources["focus"] -= 1
			a.facing = (t.pos - a.pos).normalized()
			for i in 2:
				if t.alive():
					strike(a, t, c.unarmed_weapon())
			event.emit({"type": "swing", "actor": a, "ranged": false, "windup": 0.0})
		_:
			return "기술이 없어요"
	a.skill_cd = maxf(a.skill_cd, SKILL_COOLDOWN)
	event.emit({"type": "skill", "actor": a, "text": msg if msg != "" else SKILLS[c.stats.id][0]})
	return ""
