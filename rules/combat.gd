## 전투 진행: 이니셔티브, 턴, 행동, 공격 판정 (docs/rules.md 3~4장)
## 화면과 분리된 순수 로직입니다. 일어난 일은 event 시그널로 알립니다.
class_name Combat
extends RefCounted

## ev.type: log, turn_start, move, teleport, attack, cast, hp, condition, death, fled, end
signal event(ev: Dictionary)

const STR := Rules.Ability.STR
const DEX := Rules.Ability.DEX
const CON := Rules.Ability.CON
const WIS := Rules.Ability.WIS

var grid: CombatGrid
var dice: Dice
var creatures: Array[Creature] = []
var order: Array[Creature] = []
var turn_index := -1
var round_num := 0
var over := false
var winner := -1
var xp_earned := 0


func _init(g: CombatGrid, d: Dice) -> void:
	grid = g
	dice = d


func add(c: Creature, cell: Vector2i) -> void:
	creatures.append(c)
	grid.place(c, cell)


func log_msg(text: String) -> void:
	event.emit({"type": "log", "text": text})


func current() -> Creature:
	if turn_index < 0 or turn_index >= order.size():
		return null
	return order[turn_index]


# =====================================================================
# 전투 흐름
# =====================================================================

func start(surprised_team := -1) -> void:
	log_msg("[b]전투 시작![/b]")
	roll_initiative(surprised_team)
	for c in creatures:
		ClassFeatures.on_initiative(self, c)
	round_num = 1
	log_msg("— 1 라운드 —")
	turn_index = -1
	next_turn()


func roll_initiative(surprised_team := -1) -> void:
	var group_rolls := {}
	for c in creatures:
		var key := "" if c.stats.is_pc else c.stats.id
		if key != "" and group_rolls.has(key):
			c.initiative = group_rolls[key]
			continue
		var adv := []
		var dis := []
		if c.stats.has_feature("remarkable_athlete"):
			adv.append("Remarkable Athlete")
		if c.team == surprised_team:
			dis.append("기습당함")
		var r := dice.d20(Rules.combine_advantage(adv, dis))
		c.initiative = r.value + c.stats.initiative_bonus
		if key != "":
			group_rolls[key] = c.initiative
		log_msg("이니셔티브 %s: d20 %s %+d = %d" % [c.display_name, _rolls_text(r), c.stats.initiative_bonus, c.initiative])
	order = creatures.duplicate()
	order.sort_custom(_initiative_before)


func _initiative_before(a: Creature, b: Creature) -> bool:
	if a.initiative != b.initiative:
		return a.initiative > b.initiative
	if a.mod(DEX) != b.mod(DEX):
		return a.mod(DEX) > b.mod(DEX)
	return a.stats.is_pc and not b.stats.is_pc


func next_turn() -> void:
	if over:
		return
	var prev := current()
	if prev != null:
		_end_turn(prev)
	for guard in order.size() * 2 + 2:
		turn_index += 1
		if turn_index >= order.size():
			turn_index = 0
			round_num += 1
			log_msg("— %d 라운드 —" % round_num)
		var c := order[turn_index]
		if not c.is_alive():
			# 죽은 크리처가 건 효과도 시간이 지나면 풀려야 합니다
			for x in creatures:
				x.process_phase(c, "start")
				x.process_phase(c, "end")
			continue
		_begin_turn(c)
		if check_end():
			return
		if c.can_act():
			event.emit({"type": "turn_start", "creature": c})
			return
		_end_turn(c)


## 지금 턴을 가리키는 번호 (턴마다 한 번만 일어나는 효과에 씀)
func turn_serial() -> int:
	return round_num * 1000 + turn_index + 1  # 시작 전(-1)에도 0 이상


func end_turn(c: Creature) -> void:
	if current() == c and not over:
		next_turn()


func _begin_turn(c: Creature) -> void:
	for x in creatures:
		x.process_phase(c, "start")
	c.start_turn_reset()
	if c.is_incapacitated():
		ClassFeatures.on_incapacitated(self, c)
	if c.is_alive() and not c.is_down():
		_stench(c)
		ClassFeatures.on_turn_start(self, c)
	if c.is_down() and not c.stable:
		var bless := dice.roll_die(4) if c.has_effect("blessed") else 0
		var r := Damage.death_save(c, dice, bless)
		log_msg("%s 사망 내성: %d%s → %s (성공 %d / 실패 %d)" % [c.display_name, r.roll,
				(" + Bless %d" % bless) if bless > 0 else "", r.result, c.death_successes, c.death_failures])
		if c.dead:
			event.emit({"type": "death", "creature": c})


## Stench [SRD 가스트]: 가스트 1칸 안에서 턴을 시작하면 CON DC 10, 실패하면 다음 턴 시작까지 중독. 성공하면 그 가스트의 악취에 면역
func _stench(c: Creature) -> void:
	for x in creatures:
		var g: Creature = x
		if g == c or not g.is_alive() or g.is_down() or not g.stats.has_feature("stench"):
			continue
		if grid.distance(g.cell, c.cell) > 1 or c.has_effect("poisoned"):
			continue
		if c.stats.condition_immunities.has("poisoned") or not c.find_effect("stench_immune", g).is_empty():
			continue
		var sv := saving_throw(c, CON, 10)
		log_msg("%s의 악취: %s" % [g.display_name, sv.text])
		if sv.success:
			c.add_effect("stench_immune", c, "never", 0, g)
		else:
			c.add_effect("poisoned", c, "start", 0)
			log_msg("  [color=orange]%s 중독![/color]" % c.display_name)
			event.emit({"type": "condition", "creature": c})


func _end_turn(c: Creature) -> void:
	if c.is_alive() and not c.is_down():
		Spells.on_turn_end(self, c)
		ClassFeatures.on_turn_end(self, c)
	for x in creatures:
		x.process_phase(c, "end")


func check_end() -> bool:
	if over:
		return true
	var foes_left := creatures.any(func(x: Creature) -> bool: return x.team == 1 and x.is_alive())
	var heroes_up := creatures.any(func(x: Creature) -> bool: return x.team == 0 and x.is_alive() and not x.is_down())
	if foes_left and heroes_up:
		return false
	over = true
	winner = 0 if not foes_left else 1
	if winner == 0:
		for x in creatures:
			if x.team == 1:
				xp_earned += x.stats.xp
		log_msg("[b][color=lime]승리![/color][/b] 경험치 %d 획득" % xp_earned)
	else:
		log_msg("[b][color=red]패배...[/color][/b]")
	event.emit({"type": "end", "winner": winner, "xp": xp_earned})
	return true


# =====================================================================
# 이동
# =====================================================================

## 이번 턴에 쓸 수 있는 이동력 (넘어져 있으면 일어서는 비용을 뺀 값)
func move_budget(c: Creature) -> int:
	var b := c.movement_left
	if c.has_condition("prone"):
		b -= floori(c.speed() / 2.0)
	return b


## 이동 가능한 칸 {칸: 비용}
func move_options(c: Creature) -> Dictionary:
	var out := {}
	if not c.can_act() or over:
		return out
	var r := grid.reachable(c, move_budget(c))
	for cell in r.cost:
		if grid.can_stop(cell, c):
			out[cell] = r.cost[cell]
	return out


func move(c: Creature, dest: Vector2i) -> bool:
	if not c.can_act() or over or dest == c.cell:
		return false
	var budget := move_budget(c)
	if budget <= 0:
		return false
	var r := grid.reachable(c, budget)
	if not r.cost.has(dest) or not grid.can_stop(dest, c):
		return false
	if c.has_condition("prone") and not stand_up(c):
		return false
	return move_along(c, grid.path(r, dest))


func stand_up(c: Creature) -> bool:
	if not c.has_condition("prone"):
		return true
	var cost := floori(c.speed() / 2.0)
	if c.movement_left < cost or c.speed() == 0:
		return false
	c.movement_left -= cost
	c.remove_condition("prone")
	log_msg("%s 일어섬 (이동력 %d 사용)" % [c.display_name, cost])
	event.emit({"type": "condition", "creature": c})
	return true


## 경로를 한 칸씩 따라 움직입니다. 기회 공격으로 쓰러지거나 넘어지면 멈춥니다.
func move_along(c: Creature, steps: Array) -> bool:
	var moved := false
	grid.remove(c)
	var last_free := c.cell
	for s in steps:
		var step: Vector2i = s
		var cost := grid.step_cost(c.cell, step, c)
		if cost >= CombatGrid.INF or cost > c.movement_left:
			break
		var stopped := false
		if not c.disengaged:
			for e in grid.opportunity_attackers(c, c.cell, step):
				opportunity_attack(e, c)
				if not c.can_act() or c.has_condition("prone"):
					stopped = true
					break
		if stopped or over:
			break
		var from := c.cell
		c.movement_left -= cost
		c.cell = step
		c.facing = step - from
		moved = true
		c.once_per_turn["moved"] = true
		if grid.can_stop(step, c):
			last_free = step
		event.emit({"type": "move", "creature": c, "from": from, "to": step})
		Spells.on_step(self, c, from)
		if over or not c.can_act():
			break
	if not c.is_alive():
		return moved
	if not grid.can_stop(c.cell, c):
		c.cell = last_free
		event.emit({"type": "teleport", "creature": c, "to": last_free})
	grid.place(c, c.cell)
	return moved


# =====================================================================
# 공격
# =====================================================================

func can_attack(c: Creature) -> bool:
	return not over and c.can_act() and (c.bonus_attacks > 0 or c.attacks_left > 0 or c.action_available)


func attack_info(c: Creature, t: Creature, w: WeaponData) -> Dictionary:
	return attack_info_from(c, c.cell, t, w)


## from 칸에서 공격한다고 가정한 판정 정보 (AI가 위치를 고를 때도 씁니다)
func attack_info_from(c: Creature, from: Vector2i, t: Creature, w: WeaponData) -> Dictionary:
	var info := {
		"valid": false, "reason": "", "mode": "", "adv": 0, "adv_src": [], "dis_src": [],
		"cover": 0, "bonus": 0, "ability_mod": 0, "chance": 0.0, "target_ac": 0,
	}
	if w == null:
		info.reason = "무기 없음"
		return info
	if not t.is_alive():
		info.reason = "대상 없음"
		return info
	var dist := grid.distance(from, t.cell)
	if not w.ranged and dist <= w.melee_reach():
		info.mode = "melee"
	elif (w.ranged or w.thrown) and dist <= w.range_long:
		info.mode = "ranged"
	else:
		info.reason = "사거리 밖"
		return info
	var cov := grid.cover(from, t.cell)
	if cov >= CombatGrid.TOTAL_COVER:
		info.reason = "완전 엄폐"
		return info

	var am := c.mod(DEX) if w.ranged else c.mod(STR)
	if w.finesse:
		am = maxi(c.mod(STR), c.mod(DEX))
	if w.ability >= 0:
		am = c.mod(w.ability)

	var adv := []
	var dis := []
	if t.has_condition("unconscious"):
		adv.append("의식 없음")
	elif t.has_effect("paralyzed"):
		adv.append("마비")
	elif t.has_effect("stunned"):
		adv.append("기절")
	elif t.has_condition("prone"):
		if dist <= 1:
			adv.append("대상 넘어짐")
		else:
			dis.append("대상 넘어짐")
	if c.has_condition("prone"):
		dis.append("넘어짐")
	if t.has_effect("dodging") and t.can_act() and t.speed() > 0:
		dis.append("회피")
	if info.mode == "ranged":
		if dist > w.range_normal:
			dis.append("장거리")
		if enemy_adjacent(c, from):
			dis.append("근접한 적")
	if w.heavy:
		var score: int = c.stats.scores[DEX] if w.ranged else c.stats.scores[STR]
		if score < 13:
			dis.append("Heavy")
	if c.has_effect("sapped"):
		dis.append("Sap")
	if c.has_effect("poisoned"):
		dis.append("중독")
	if not c.find_effect("vex", t).is_empty():
		adv.append("Vex")
	if t.has_effect("outlined"):
		adv.append("요정불")
	if c.stats.has_feature("pack_tactics") and ally_adjacent_to(c, t):
		adv.append("Pack Tactics")
	if t.has_effect("guided"):
		adv.append("Guiding Bolt")
	ClassFeatures.attack_mods(c, t, w, am, adv, dis)

	info.adv = Rules.combine_advantage(adv, dis)
	info.adv_src = adv
	info.dis_src = dis
	info.cover = cov
	info.ability_mod = am
	info.bonus = am + c.pb() + ClassFeatures.attack_bonus(c, w, info.mode)
	info.target_ac = t.ac() + cov
	info.chance = hit_chance(info.bonus, info.target_ac, info.adv)
	if c.has_effect("blessed"):
		# Bless 1d4: 네 경우의 평균
		var sum := 0.0
		for k in range(1, 5):
			sum += hit_chance(info.bonus + k, info.target_ac, info.adv)
		info.chance = sum / 4.0
	info.valid = true
	return info


static func hit_chance(bonus: int, target_ac: int, adv: int) -> float:
	var hits := 0
	for d in range(1, 21):
		if d == 20 or (d != 1 and d + bonus >= target_ac):
			hits += 1
	var p := hits / 20.0
	if adv > 0:
		return 1.0 - (1.0 - p) * (1.0 - p)
	if adv < 0:
		return p * p
	return p


## 공격 행동(또는 그 안의 추가 공격) 1회
func attack(c: Creature, t: Creature, w: WeaponData) -> bool:
	if not can_attack(c):
		return false
	# 보너스 행동으로 얻은 맨손 타격이 남아 있으면 그것부터 씀
	var bonus_strike := c.bonus_attacks > 0 and c.unarmed_weapon() != null
	if bonus_strike:
		w = c.unarmed_weapon()
	var info := attack_info(c, t, w)
	if not info.valid:
		log_msg("공격할 수 없음: %s" % info.reason)
		return false
	var flurry := false
	if bonus_strike:
		c.bonus_attacks -= 1
		flurry = c.toggles.get("flurry", false)
	else:
		if c.attacks_left <= 0:
			c.action_available = false
			c.attacks_left = c.attacks_per_action()
		c.attacks_left -= 1
	var target := _redirect(c, t)
	if target != t:
		info = attack_info(c, target, w)
		if not info.valid:
			return true
	info["flurry"] = flurry
	resolve_attack(c, target, w, info)
	return true


## extra: attack 이벤트에 더할 값 (예: {"spirit": true}는 영적 무기가 때림)
func resolve_attack(c: Creature, t: Creature, w: WeaponData, info: Dictionary, cleave := false, extra := {}) -> Dictionary:
	var r := dice.d20(info.adv)
	var nat: int = r.value
	var total: int = nat + info.bonus
	var bless_txt := ""
	if c.has_effect("blessed"):
		var b := dice.roll_die(4)
		total += b
		bless_txt = " + Bless %d" % b
	var target_ac: int = info.target_ac
	var hit: bool = nat == 20 or (nat != 1 and total >= target_ac)
	if hit and nat != 20:
		var cut := ClassFeatures.cutting_words(self, c, t, total, target_ac)
		if cut > 0:
			total -= cut
			bless_txt += " − Cutting Words %d" % cut
			hit = total >= target_ac
	if not hit and nat != 1:
		var insp := ClassFeatures.use_inspiration(self, c, total, target_ac)
		if insp > 0:
			total += insp
			bless_txt += " + 영감 %d" % insp
			hit = total >= target_ac
	if hit and nat != 20 and ClassFeatures.try_shield(self, t, total, target_ac):
		target_ac += 5
		info.target_ac = target_ac
		hit = total >= target_ac
	var crit: bool = hit and nat >= c.crit_threshold()
	ClassFeatures.on_attack_roll(c)
	if hit and (t.has_condition("unconscious") or t.has_effect("paralyzed")) and grid.distance(c.cell, t.cell) <= 1:
		crit = true

	# 1회성 효과는 굴리고 나면 사라집니다
	c.remove_effects("sapped")
	t.remove_effects("guided")
	t.remove_effects("exposed")
	var vex := c.find_effect("vex", t)
	if not vex.is_empty():
		c.effects.erase(vex)
	if t.cell != c.cell:
		c.facing = t.cell - c.cell

	var adv_txt := ""
	if info.adv > 0:
		adv_txt = " [이점: %s]" % ", ".join(info.adv_src)
	elif info.adv < 0:
		adv_txt = " [불리점: %s]" % ", ".join(info.dis_src)
	var cover_txt: String = (" (엄폐 +%d)" % info.cover) if info.cover > 0 else ""
	var line := "%s → %s (%s): d20 %s %+d%s = %d vs AC %d%s%s" % [
		c.display_name, t.display_name, w.display_name, _rolls_text(r), info.bonus, bless_txt,
		total, info.target_ac, cover_txt, adv_txt]
	var result := {"hit": hit, "crit": crit, "damage": 0}

	if not hit:
		log_msg(line + " → [color=gray]빗나감[/color]")
		event.emit({"type": "attack", "attacker": c, "target": t, "hit": false, "crit": false, "ranged": info.mode == "ranged"}.merged(extra))
		if c.can_use_mastery(w) and w.mastery == "graze" and info.ability_mod > 0:
			_deal(t, info.ability_mod, w.damage_type, false, "Graze")
		check_end()
		return result

	log_msg(line + (" → [color=yellow]치명타![/color]" if crit else " → 명중"))
	event.emit({"type": "attack", "attacker": c, "target": t, "hit": true, "crit": crit, "ranged": info.mode == "ranged"}.merged(extra))
	var dmg := roll_weapon_damage(c, w, crit, info.adv > 0, info.ability_mod, cleave)
	var extra_dmg := ClassFeatures.bonus_damage(self, c, t, w, info, crit)
	if extra_dmg.amount > 0:
		dmg += extra_dmg.amount
		log_msg("  (%s)" % extra_dmg.text)
	dmg = ClassFeatures.on_hit_taken(self, c, t, w, info, dmg)
	var res := _deal(t, dmg, w.damage_type, crit, "")
	result.damage = res.dealt
	if res.killed or res.downed:
		ClassFeatures.on_kill(self, c, t)
	if t.is_alive() and not t.is_down():
		ClassFeatures.after_hit(self, c, t, w, info, extra_dmg)
		if res.dealt > 0:
			ClassFeatures.on_damaged(self, c, t)
	if t.is_alive() and w.knocks_prone and t.stats.size <= Rules.Size.MEDIUM and not t.has_condition("prone"):
		if t.add_condition("prone"):
			log_msg("  %s 넘어짐!" % t.display_name)
			event.emit({"type": "condition", "creature": t})
	if t.is_alive() and not t.is_down():
		_apply_on_hit(c, t, w, res.dealt)
	if c.can_use_mastery(w):
		_apply_mastery(c, t, w, info, res.dealt)
	check_end()
	return result


## 몬스터 공격의 추가 효과 (구울 마비, 섀도 근력 흡수)
func _apply_on_hit(c: Creature, t: Creature, w: WeaponData, dealt := 0) -> void:
	var eff := w.on_hit_always
	if w.on_hit_save >= 0 and w.on_hit_effect != "":
		if w.on_hit_effect == "paralyzed" and (t.stats.creature_type == "undead" or t.stats.condition_immunities.has("paralyzed")):
			return
		var sv := saving_throw(t, w.on_hit_save, w.on_hit_dc)
		log_msg("  " + sv.text)
		if sv.success:
			return
		eff = w.on_hit_effect
	match eff:
		"paralyzed":
			t.remove_effects("paralyzed")
			t.add_effect("paralyzed", c, "end", 1)  # 때린 쪽의 다음 턴이 끝날 때까지
			log_msg("  [color=orange]%s 마비![/color]" % t.display_name)
			event.emit({"type": "condition", "creature": t})
		"drain_max":
			# 스펙터 Life Drain: 받은 피해만큼 최대 HP 감소 (긴 휴식까지). 0이 되면 죽음
			if dealt <= 0:
				return
			t.max_hp_loss += dealt
			t.stats.max_hp = maxi(0, t.stats.max_hp - dealt)
			t.hp = mini(t.hp, t.stats.max_hp)
			log_msg("  %s 최대 HP -%d (최대 HP %d)" % [t.display_name, dealt, t.stats.max_hp])
			event.emit({"type": "hp", "creature": t, "delta": 0, "hp": t.hp, "crit": false})
			if t.stats.max_hp <= 0:
				Damage._kill(t)
				log_msg("  [color=orange]%s 생명이 다해 쓰러짐[/color]" % t.display_name)
				grid.remove(t)
				event.emit({"type": "death", "creature": t})
		"str_drain":
			var loss := dice.roll_die(4)
			t.str_loss += loss
			log_msg("  %s 근력 -%d (근력 %d)" % [t.display_name, loss, t.stats.scores[STR] - t.str_loss])
			if t.stats.scores[STR] - t.str_loss <= 0:
				Damage._kill(t)
				log_msg("  [color=orange]%s 근력이 다해 쓰러짐[/color]" % t.display_name)
				grid.remove(t)
				event.emit({"type": "death", "creature": t})


func roll_weapon_damage(c: Creature, w: WeaponData, crit: bool, had_adv: bool, am: int, cleave := false) -> int:
	var count := w.dice_count
	if c.stats.has_feature("swarm") and c.is_bloodied():
		count = maxi(1, count / 2)  # 떼: HP가 절반 이하면 주사위 절반 [SRD]
	count *= 2 if crit else 1
	var total := Dice.sum(dice.roll(count, w.dice_sides))
	if c.stats.has_feature("savage_attacker") and not c.once_per_turn.has("savage"):
		c.once_per_turn["savage"] = true
		total = maxi(total, Dice.sum(dice.roll(count, w.dice_sides)))
	if had_adv and w.bonus_die_on_advantage > 0:
		total += Dice.sum(dice.roll(2 if crit else 1, w.bonus_die_on_advantage))
	if not w.add_mod:
		pass
	elif cleave:
		total += mini(am, 0)
	else:
		total += am
	return maxi(0, total)


func _deal(t: Creature, amount: int, type: String, crit: bool, label: String) -> Dictionary:
	var res := Damage.apply(t, amount, type, crit)
	if res.killed and t.stats.has_feature("undead_fortitude") and type != "radiant" and not crit:
		# Undead Fortitude [SRD]: 광휘 피해나 치명타가 아니면 CON 내성 DC 5+피해로 HP 1로 버팀
		var sv := saving_throw(t, CON, 5 + res.dealt)
		log_msg("  Undead Fortitude: " + sv.text)
		if sv.success:
			t.dead = false
			t.hp = 1
			res.killed = false
	var note := ""
	if t.stats.immunities.has(type):
		note = " (면역)"
	elif t.stats.vulnerabilities.has(type):
		note = " (취약)"
	elif t.stats.resistances.has(type):
		note = " (저항)"
	var prefix := (label + ": ") if label != "" else ""
	log_msg("  %s%s %d 피해%s → HP %d/%d" % [prefix, t.display_name, res.dealt, note, t.hp, t.stats.max_hp])
	event.emit({"type": "hp", "creature": t, "delta": -res.dealt, "hp": t.hp, "crit": crit})
	if res.dealt > 0 and t.has_effect("turned"):
		t.remove_effects("turned")
		log_msg("  %s: 피해를 입어 Turn Undead가 풀림" % t.display_name)
	if res.killed or res.downed:
		_lose_focus(t)
		ClassFeatures.on_creature_down(self, t)
	elif res.dealt > 0 and t.concentration != "":
		Spells.concentration_check(self, t, res.dealt)
	if res.killed:
		log_msg("  [color=orange]%s 쓰러짐[/color]" % t.display_name)
		grid.remove(t)
		event.emit({"type": "death", "creature": t})
	elif res.downed:
		log_msg("  [color=orange]%s 의식을 잃음[/color]" % t.display_name)
		event.emit({"type": "condition", "creature": t})
	return res


func _apply_mastery(c: Creature, t: Creature, w: WeaponData, info: Dictionary, dealt: int) -> void:
	match w.mastery:
		"sap":
			if t.is_alive():
				t.add_effect("sapped", c, "start")
				log_msg("  Sap: %s의 다음 공격에 불리점" % t.display_name)
		"slow":
			if t.is_alive() and dealt > 0 and not t.has_effect("slowed"):
				t.add_effect("slowed", c, "start")
				log_msg("  Slow: %s 속도 -2칸" % t.display_name)
		"vex":
			if t.is_alive() and dealt > 0:
				c.add_effect("vex", c, "end", 1, t)
				log_msg("  Vex: %s에 대한 다음 공격에 이점" % t.display_name)
		"topple":
			if t.is_alive():
				var dc := Rules.save_dc(info.ability_mod, c.pb())
				var sv := saving_throw(t, CON, dc)
				if not sv.success and t.add_condition("prone"):
					log_msg("  Topple: %s → 넘어짐!" % sv.text)
					event.emit({"type": "condition", "creature": t})
				else:
					log_msg("  Topple: %s → 버팀" % sv.text)
		"push":
			if t.is_alive() and t.stats.size <= Rules.Size.LARGE:
				_push(c, t, 2)
		"cleave":
			if info.mode == "melee" and not c.once_per_turn.has("cleave"):
				for x in creatures:
					if x == t or not x.is_alive() or not x.is_hostile_to(c):
						continue
					if grid.distance(x.cell, t.cell) > 1 or grid.distance(c.cell, x.cell) > w.melee_reach():
						continue
					c.once_per_turn["cleave"] = true
					var second := attack_info(c, x, w)
					if second.valid:
						log_msg("  Cleave!")
						resolve_attack(c, x, w, second, true)
					break


## 주문 피해로 대상을 쓰러뜨렸을 때 (워락 Dark One's Blessing 같은 기능)
func on_spell_hit(c: Creature, t: Creature) -> void:
	if not t.is_alive() or t.is_down():
		ClassFeatures.on_kill(self, c, t)


func _push(c: Creature, t: Creature, tiles: int) -> void:
	var dir := Vector2i(signi(t.cell.x - c.cell.x), signi(t.cell.y - c.cell.y))
	var moved := 0
	for i in tiles:
		var nxt := t.cell + dir
		if grid.occupant(nxt) != null or grid.step_cost(t.cell, nxt, t) >= CombatGrid.INF:
			break
		grid.place(t, nxt)
		moved += 1
	if moved > 0:
		log_msg("  Push: %s %d칸 밀려남" % [t.display_name, moved])
		event.emit({"type": "teleport", "creature": t, "to": t.cell})


## 고블린 대장의 Redirect Attack (반응)
func _redirect(c: Creature, t: Creature) -> Creature:
	if not t.stats.has_feature("redirect_attack") or not t.reaction_available or not t.can_act():
		return t
	for x in creatures:
		if x == t or x == c or x.team != t.team or not x.can_act():
			continue
		if x.stats.size > Rules.Size.MEDIUM or grid.distance(x.cell, t.cell) > 1:
			continue
		t.reaction_available = false
		var a := t.cell
		var b := x.cell
		grid.remove(t)
		grid.remove(x)
		grid.place(t, b)
		grid.place(x, a)
		log_msg("%s: Redirect Attack! %s와 자리를 바꿈" % [t.display_name, x.display_name])
		event.emit({"type": "teleport", "creature": t, "to": b})
		event.emit({"type": "teleport", "creature": x, "to": a})
		return x
	return t


func opportunity_attack(e: Creature, mover: Creature) -> void:
	e.reaction_available = false
	var w := e.melee_weapon()
	log_msg("[color=orange]%s의 기회 공격![/color]" % e.display_name)
	var info := attack_info_from(e, e.cell, mover, w)
	if info.valid:
		resolve_attack(e, mover, w, info)


# =====================================================================
# 기타 행동
# =====================================================================

func _use_action(c: Creature) -> bool:
	if over or not c.can_act():
		return false
	if not c.action_available:
		log_msg("행동을 이미 사용했습니다")
		return false
	c.action_available = false
	c.attacks_left = 0
	return true


func _use_bonus(c: Creature) -> bool:
	if over or not c.can_act():
		return false
	if not c.bonus_available:
		log_msg("보너스 행동을 이미 사용했습니다")
		return false
	c.bonus_available = false
	return true


func dash(c: Creature) -> bool:
	if not _use_action(c):
		return false
	c.movement_left += c.speed()
	log_msg("%s 질주 (이동력 +%d)" % [c.display_name, c.speed()])
	return true


func disengage(c: Creature) -> bool:
	if not _use_action(c):
		return false
	c.disengaged = true
	log_msg("%s 이탈 (이번 턴 기회 공격 없음)" % c.display_name)
	return true


func dodge(c: Creature) -> bool:
	if not _use_action(c):
		return false
	c.add_effect("dodging", c, "start")
	log_msg("%s 회피 자세" % c.display_name)
	return true


func second_wind(c: Creature) -> bool:
	if not c.stats.has_feature("second_wind") or c.resources.get("second_wind", 0) <= 0:
		log_msg("Second Wind를 쓸 수 없습니다")
		return false
	if not _use_bonus(c):
		return false
	c.resources["second_wind"] -= 1
	var roll := dice.roll_die(10)
	var healed := Damage.heal(c, roll + c.stats.level)
	log_msg("%s Second Wind: 1d10(%d) + %d → HP +%d" % [c.display_name, roll, c.stats.level, healed])
	event.emit({"type": "hp", "creature": c, "delta": healed, "hp": c.hp, "crit": false})
	return true


func action_surge(c: Creature) -> bool:
	if over or not c.can_act():
		return false
	if c.resources.get("action_surge", 0) <= 0 or c.action_surge_used:
		log_msg("Action Surge를 쓸 수 없습니다")
		return false
	c.resources["action_surge"] -= 1
	c.action_surge_used = true
	c.action_available = true
	log_msg("%s Action Surge! 행동 1회 추가" % c.display_name)
	return true


func drink_potion(c: Creature) -> bool:
	if c.resources.get("potion", 0) <= 0:
		log_msg("물약이 없습니다")
		return false
	if not _use_bonus(c):
		return false
	c.resources["potion"] -= 1
	var rolls := dice.roll(2, 4)
	var healed := Damage.heal(c, Dice.sum(rolls) + 2)
	log_msg("%s 회복 물약: 2d4%s + 2 → HP +%d" % [c.display_name, str(rolls), healed])
	event.emit({"type": "hp", "creature": c, "delta": healed, "hp": c.hp, "crit": false})
	return true


func nimble_escape(c: Creature) -> bool:
	if not c.stats.has_feature("nimble_escape") or not _use_bonus(c):
		return false
	c.disengaged = true
	log_msg("%s Nimble Escape (이탈)" % c.display_name)
	return true


func flee(c: Creature) -> void:
	c.fled = true
	grid.remove(c)
	log_msg("%s 전장에서 도망침" % c.display_name)
	event.emit({"type": "fled", "creature": c})
	check_end()


## 몬스터 턴을 AI로 처리하고 다음 턴으로 넘깁니다.
func run_monster_turn() -> void:
	var c := current()
	if c == null or over or c.team == 0:
		return
	MonsterAI.take_turn(self, c)
	if not over:
		next_turn()


# =====================================================================
# 도우미
# =====================================================================

## 내성 굴림 (Bless 1d4 포함). 반환 {"total", "success", "text"}
func saving_throw(t: Creature, ability: int, dc: int, adv := 0) -> Dictionary:
	if (t.has_effect("paralyzed") or t.has_effect("stunned")) and (ability == STR or ability == DEX):
		var txt := "%s %s 내성 → 실패 (%s)" % [t.display_name, Rules.ABILITY_NAMES[ability], "마비" if t.has_effect("paralyzed") else "기절"]
		return {"total": 0, "success": false, "text": txt}
	var r := dice.d20(signi(adv + ClassFeatures.save_adv(t, ability)))
	var bonus := t.save_bonus(ability)
	var total: int = r.value + bonus
	var extra := ""
	if t.has_effect("blessed"):
		var b := dice.roll_die(4)
		total += b
		extra = " + Bless %d" % b
	if total < dc:
		var insp := ClassFeatures.use_inspiration(self, t, total, dc)
		if insp > 0:
			total += insp
			extra += " + 영감 %d" % insp
	var ok := total >= dc
	var text := "%s %s 내성 d20 %s %+d%s = %d vs DC %d → %s" % [t.display_name, Rules.ABILITY_NAMES[ability],
		_rolls_text(r), bonus, extra, total, dc, "성공" if ok else "실패"]
	return {"total": total, "success": ok, "text": text}


## 쓰러지거나 죽으면 집중과 그 크리처가 건 Turn Undead가 끝남 (rules 7.5)
func _lose_focus(t: Creature) -> void:
	ClassFeatures.on_incapacitated(self, t)
	if t.concentration != "":
		Spells.end_concentration(self, t)
	for x in creatures:
		if x.remove_effects_from(t, ["turned"]):
			log_msg("  %s의 Turn Undead가 풀림" % x.display_name)


## from 칸 1칸 안에, c를 볼 수 있고 행동 가능한 적이 있는가
func enemy_adjacent(c: Creature, from: Vector2i) -> bool:
	for x in creatures:
		if x != c and x.is_hostile_to(c) and x.can_act() and grid.distance(from, x.cell) <= 1:
			return true
	return false


## t의 1칸 안에 c의 (행동 가능한) 아군이 있는가
func ally_adjacent_to(c: Creature, t: Creature) -> bool:
	for x in creatures:
		if x != c and x.team == c.team and x.can_act() and grid.distance(x.cell, t.cell) <= 1:
			return true
	return false


func _rolls_text(r: Dictionary) -> String:
	var rolls: Array = r.rolls
	if rolls.size() == 1:
		return str(rolls[0])
	return "%s→%d" % [str(rolls), r.value]
