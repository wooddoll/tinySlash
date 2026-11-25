## 몬스터 AI (docs/rules.md 8.1). 게임 전용 규칙입니다.
class_name MonsterAI
extends RefCounted


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


# --- 근접 ---

static func _melee_turn(cb: Combat, c: Creature, foes: Array[Creature]) -> void:
	var w := c.melee_weapon()
	if w == null:
		w = c.ranged_weapon()
	var target := _target_in_reach(cb, c, foes, w)
	if target == null:
		_advance(cb, c, foes, w)
		target = _target_in_reach(cb, c, foes, w)
	if target != null:
		_attack_all(cb, c, target, w, foes)
		return
	# 붙지 못했으면 투척/원거리
	var rw := c.ranged_weapon()
	if rw != null and c.action_available:
		var t := _best_ranged_target(cb, c, foes, rw)
		if t != null:
			_attack_all(cb, c, t, rw, foes)
			return
	# 그래도 안 되면 질주해서 더 다가감
	if c.action_available and cb.dash(c):
		_advance(cb, c, foes, w)


static func _target_in_reach(cb: Combat, c: Creature, foes: Array[Creature], w: WeaponData) -> Creature:
	var best: Creature = null
	var best_score := -1e9
	for f in foes:
		if not f.is_alive() or f.is_down():
			continue
		var info := cb.attack_info(c, f, w)
		if not info.valid or info.mode != "melee":
			continue
		var score: float = info.chance * 100.0 - f.hp
		if score > best_score:
			best_score = score
			best = f
	return best


## 공격할 수 있는 칸으로 이동. 기회 공격을 유발하는 경로는 피합니다.
static func _advance(cb: Combat, c: Creature, foes: Array[Creature], w: WeaponData) -> void:
	var budget := c.movement_left
	if budget <= 0:
		return
	var reach := w.melee_reach() if w else 1
	var r := cb.grid.reachable(c, budget)
	var best_cell := c.cell
	var best_score := -1e9
	var found := false
	for k in r.cost:
		var cell: Vector2i = k
		var occ := cb.grid.occupant(cell)
		if occ != null and occ != c:
			continue
		for f in foes:
			if cb.grid.distance(cell, f.cell) > reach:
				continue
			var p := cb.grid.path(r, cell)
			var score := 100.0 - _oa_count(cb, c, p) * 40.0 - float(r.cost[cell])
			if c.stats.has_feature("pack_tactics") and cb.ally_adjacent_to(c, f):
				score += 15.0
			if f.is_bloodied():
				score += 5.0
			if score > best_score:
				best_score = score
				best_cell = cell
				found = true
	if found:
		if best_cell != c.cell:
			cb.move_along(c, cb.grid.path(r, best_cell))
		return

	# 닿지 않으면 가장 가까운 적 쪽으로 최대한 이동
	var far := cb.grid.reachable(c, 999)
	var goal := Vector2i(-1, -1)
	var goal_cost := CombatGrid.INF
	for f in foes:
		for k in far.cost:
			var cell: Vector2i = k
			if cb.grid.distance(cell, f.cell) > reach:
				continue
			var occ := cb.grid.occupant(cell)
			if occ != null and occ != c:
				continue
			if far.cost[cell] < goal_cost:
				goal_cost = far.cost[cell]
				goal = cell
	if goal.x < 0:
		return
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
			t = _target_in_reach(cb, c, foes, w) if not w.ranged else _best_ranged_target(cb, c, foes, w)
			if t == null:
				break
		if not cb.attack(c, t, w):
			break
		if c.attacks_left <= 0:
			break


# --- 원거리 ---

static func _best_ranged_target(cb: Combat, c: Creature, foes: Array[Creature], w: WeaponData) -> Creature:
	var best: Creature = null
	var best_score := -1e9
	for f in foes:
		if not f.is_alive() or f.is_down():
			continue
		var info := cb.attack_info(c, f, w)
		if not info.valid:
			continue
		var score: float = info.chance * 100.0 - f.hp
		if score > best_score:
			best_score = score
			best = f
	return best


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
		var p := cb.grid.path(r, cell)
		var oa := _oa_count(cb, c, p)
		var adj := cb.enemy_adjacent(c, cell)
		for f in foes:
			var info := cb.attack_info_from(c, cell, f, rw)
			if not info.valid:
				continue
			var score: float = info.chance * 100.0 - oa * 40.0 - (30.0 if adj else 0.0) - float(r.cost[cell]) * 0.5
			if f.is_bloodied():
				score += 5.0
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
