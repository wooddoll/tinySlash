## 몬스터 AI (docs/rules.md 8.1). 게임 전용 규칙입니다.
## 점수(유틸리티) 방식: 공격할 대상과 서 있을 칸을 각각 점수로 매겨 가장 높은 것을 고릅니다.
##   대상 점수 = 명중 확률 + 쓰러뜨릴 수 있음 + 다친 정도 + 집중 중 + 시전자 - Bless 받음
##   칸 점수   = 대상 점수 - 기회 공격 - 이동 거리 + 무리 사냥 + 엄폐(원거리) - 둘러싸임
class_name MonsterAI
extends RefCounted

## 점수 가중치 (튜닝용)
const W_HIT := 100.0          # 명중 확률 1.0당
const W_KILL := 30.0          # 이번 공격으로 쓰러뜨릴 수 있으면 (명중 확률 곱)
const W_HURT := 20.0          # 잃은 HP 비율 1.0당
const W_CONC := 20.0          # 주문 집중 중 (맞으면 집중이 깨질 수 있음)
const W_CASTER := 10.0        # 주문 시전자 (회복·버프를 막음)
const W_BLESSED := -5.0       # Bless 받음 (내성·사망 내성에 강함)
const W_OA := -40.0           # 이동 중 기회 공격 1회당
const W_PACK := 15.0          # 무리 사냥: 대상 옆에 아군
const W_CROWD := -6.0         # 근접: 대상 말고도 옆에 붙은 적 1명당
const W_COVER := 6.0          # 원거리: 적들에게서 받는 평균 엄폐 AC 1당
const W_ADJ := -30.0          # 원거리: 바로 옆에 적
const W_NEAR := -8.0          # 원거리: 적이 3칸 안


static func take_turn(cb: Combat, c: Creature) -> void:
	var foes := _foes(cb, c)
	if foes.is_empty():
		return
	if c.stats.has_feature("cowardly") and c.is_bloodied() and cb.dice.rng.randf() < 0.3:
		_flee(cb, c, foes)
		return
	if c.has_condition("prone"):
		cb.stand_up(c)
	if c.stats.ai_style == "ranged" and c.ranged_weapon() != null:
		if _ranged_turn(cb, c, foes):
			return
	_melee_turn(cb, c, foes)


static func _foes(cb: Combat, c: Creature) -> Array[Creature]:
	var out: Array[Creature] = []
	for x in cb.creatures:
		if x.is_alive() and not x.is_down() and x.is_hostile_to(c):
			out.append(x)
	return out


# --- 점수 ---

## 대상 f를 이 공격(info)으로 노릴 가치. info는 attack_info / attack_info_from 결과
static func target_value(c: Creature, f: Creature, info: Dictionary, w: WeaponData) -> float:
	var chance: float = info.chance
	var v := chance * W_HIT
	if _avg_damage(w, info) >= f.hp + f.temp_hp:
		v += W_KILL * chance
	v += (1.0 - float(f.hp) / maxf(1.0, f.stats.max_hp)) * W_HURT
	v += priority(f)
	return v


## 위치와 상관없는 대상의 중요도 (집중 중인 시전자, 회복 담당 등)
static func priority(f: Creature) -> float:
	var v := 0.0
	if f.concentration != "":
		v += W_CONC
	if f.stats.spell_ability >= 0:
		v += W_CASTER
	if f.has_effect("blessed"):
		v += W_BLESSED
	return v


static func _avg_damage(w: WeaponData, info: Dictionary) -> float:
	if w == null:
		return 0.0
	var mod: int = info.ability_mod if w.add_mod else 0
	return w.dice_count * (w.dice_sides + 1) / 2.0 + mod


## 원거리 칸의 엄폐 점수: 적들이 이 칸을 볼 때의 평균 엄폐 (완전 엄폐는 6으로 침)
static func cover_value(cb: Combat, cell: Vector2i, foes: Array[Creature]) -> float:
	if foes.is_empty():
		return 0.0
	var total := 0.0
	for e in foes:
		total += mini(cb.grid.cover(e.cell, cell), 6)
	return total / foes.size()


static func _best_target(cb: Combat, c: Creature, foes: Array[Creature], w: WeaponData, melee_only: bool) -> Creature:
	var best: Creature = null
	var best_score := -1e9
	for f in foes:
		if not f.is_alive() or f.is_down():
			continue
		var info := cb.attack_info(c, f, w)
		if not info.valid or (melee_only and info.mode != "melee"):
			continue
		var score := target_value(c, f, info, w)
		if score > best_score:
			best_score = score
			best = f
	return best


# --- 근접 ---

static func _melee_turn(cb: Combat, c: Creature, foes: Array[Creature]) -> void:
	var w := c.melee_weapon()
	if w == null:
		w = c.ranged_weapon()
	var target := _best_target(cb, c, foes, w, true)
	if target == null:
		target = _advance(cb, c, foes, w)
	if target != null and cb.attack_info(c, target, w).valid:
		_attack_all(cb, c, target, w, foes)
		return
	# 붙지 못했으면 투척/원거리
	var rw := c.ranged_weapon()
	if rw != null and c.action_available:
		var t := _best_target(cb, c, foes, rw, false)
		if t != null:
			_attack_all(cb, c, t, rw, foes)
			return
	# 그래도 안 되면 질주해서 더 다가감
	if c.action_available and cb.dash(c):
		_advance(cb, c, foes, w)


## 공격할 수 있는 칸 중 점수가 가장 높은 곳으로 이동하고 그 대상을 돌려줍니다.
## 이번 턴에 닿을 곳이 없으면 가장 노릴 만한 적 쪽으로 최대한 다가가고 null.
static func _advance(cb: Combat, c: Creature, foes: Array[Creature], w: WeaponData) -> Creature:
	var budget := c.movement_left
	if budget <= 0:
		return null
	var reach := w.melee_reach() if w else 1
	var r := cb.grid.reachable(c, budget)
	var best_cell := c.cell
	var best_target: Creature = null
	var best_score := -1e9
	for k in r.cost:
		var cell: Vector2i = k
		var occ := cb.grid.occupant(cell)
		if occ != null and occ != c:
			continue
		var oa := -1
		for f in foes:
			if cb.grid.distance(cell, f.cell) > reach:
				continue
			var info := cb.attack_info_from(c, cell, f, w)
			if not info.valid:
				continue
			if oa < 0:
				oa = _oa_count(cb, c, cb.grid.path(r, cell))
			var score := 100.0 + target_value(c, f, info, w) * 0.5 + oa * W_OA - float(r.cost[cell])
			if c.stats.has_feature("pack_tactics") and cb.ally_adjacent_to(c, f):
				score += W_PACK
			for e in foes:
				if e != f and cb.grid.distance(cell, e.cell) <= 1:
					score += W_CROWD
			if score > best_score:
				best_score = score
				best_cell = cell
				best_target = f
	if best_target != null:
		if best_cell != c.cell:
			cb.move_along(c, cb.grid.path(r, best_cell))
		return best_target

	# 닿지 않으면 가까우면서 노릴 만한 적 쪽으로 최대한 이동
	var far := cb.grid.reachable(c, 999)
	var goal := Vector2i(-1, -1)
	var goal_score := 1e9
	for f in foes:
		var pr := priority(f) + (1.0 - float(f.hp) / maxf(1.0, f.stats.max_hp)) * W_HURT
		for k in far.cost:
			var cell: Vector2i = k
			if cb.grid.distance(cell, f.cell) > reach:
				continue
			var occ := cb.grid.occupant(cell)
			if occ != null and occ != c:
				continue
			var s: float = float(far.cost[cell]) - pr * 0.1
			if s < goal_score:
				goal_score = s
				goal = cell
	if goal.x < 0:
		return null
	var full := cb.grid.path(far, goal)
	var spent := 0
	var cur := c.cell
	var last_ok := -1
	for i in full.size():
		var step: Vector2i = full[i]
		var cost := cb.grid.step_cost(cur, step, c)
		if spent + cost > budget:
			break
		spent += cost
		cur = step
		if cb.grid.occupant(cur) == null:
			last_ok = i
	if last_ok >= 0:
		cb.move_along(c, full.slice(0, last_ok + 1))
	return null


static func _oa_count(cb: Combat, c: Creature, steps: Array) -> int:
	if c.disengaged:
		return 0
	var seen := {}
	var cur := c.cell
	for s in steps:
		var step: Vector2i = s
		for e in cb.grid.opportunity_attackers(c, cur, step):
			seen[e] = true
		cur = step
	return seen.size()


static func _attack_all(cb: Combat, c: Creature, target: Creature, w: WeaponData, foes: Array[Creature]) -> void:
	var t := target
	while cb.can_attack(c):
		if t == null or not t.is_alive() or t.is_down():
			t = _best_target(cb, c, foes, w, not w.ranged)
			if t == null:
				break
		if not cb.attack(c, t, w):
			break
		if c.attacks_left <= 0:
			break


# --- 원거리 ---

## 엄폐가 있고 적과 떨어진 칸에서 사격. 쏠 곳이 없으면 false
static func _ranged_turn(cb: Combat, c: Creature, foes: Array[Creature]) -> bool:
	var rw := c.ranged_weapon()
	if cb.enemy_adjacent(c, c.cell) and c.bonus_available:
		cb.nimble_escape(c)
	var r := cb.grid.reachable(c, c.movement_left)
	var best_cell := c.cell
	var best_target: Creature = null
	var best_score := -1e9
	for k in r.cost:
		var cell: Vector2i = k
		var occ := cb.grid.occupant(cell)
		if occ != null and occ != c:
			continue
		var place := -1e9  # 칸 점수는 쏠 대상이 있을 때만 계산
		for f in foes:
			var info := cb.attack_info_from(c, cell, f, rw)
			if not info.valid:
				continue
			if place <= -1e9:
				place = _ranged_place_score(cb, c, r, cell, foes)
			var score := target_value(c, f, info, rw) + place
			if score > best_score:
				best_score = score
				best_cell = cell
				best_target = f
	if best_target == null:
		return false
	if best_cell != c.cell:
		cb.move_along(c, cb.grid.path(r, best_cell))
	if not c.can_act() or cb.over:
		return true
	_attack_all(cb, c, best_target, rw, foes)
	return true


static func _ranged_place_score(cb: Combat, c: Creature, r: Dictionary, cell: Vector2i, foes: Array[Creature]) -> float:
	var s := _oa_count(cb, c, cb.grid.path(r, cell)) * W_OA - float(r.cost[cell]) * 0.5
	var nearest := 999
	for e in foes:
		nearest = mini(nearest, cb.grid.distance(cell, e.cell))
	if nearest <= 1:
		s += W_ADJ
	elif nearest <= 3:
		s += W_NEAR
	s += cover_value(cb, cell, foes) * W_COVER
	return s


# --- 도망 ---

static func _flee(cb: Combat, c: Creature, foes: Array[Creature]) -> void:
	cb.log_msg("%s 겁을 먹고 달아난다!" % c.display_name)
	if c.bonus_available:
		cb.nimble_escape(c)
	if c.action_available:
		cb.dash(c)
	var r := cb.grid.reachable(c, c.movement_left)
	var best_cell := c.cell
	var best_score := -1e9
	for k in r.cost:
		var cell: Vector2i = k
		var occ := cb.grid.occupant(cell)
		if occ != null and occ != c:
			continue
		var nearest := 999
		for f in foes:
			nearest = mini(nearest, cb.grid.distance(cell, f.cell))
		var score := float(nearest) + (5.0 if cb.grid.is_edge(cell) else 0.0)
		if score > best_score:
			best_score = score
			best_cell = cell
	if best_cell != c.cell:
		cb.move_along(c, cb.grid.path(r, best_cell))
	if c.can_act() and cb.grid.is_edge(c.cell):
		cb.flee(c)
