## 클레릭 주문과 Channel Divinity (docs/rules.md 7.5, 7.6). 화면과 분리된 규칙입니다.
## 시전은 Combat의 행동 자원과 피해/회복 처리를 그대로 씁니다.
class_name Spells
extends RefCounted

const DEX := Rules.Ability.DEX
const CON := Rules.Ability.CON
const WIS := Rules.Ability.WIS

## level: 0 소마법, 1 이상 슬롯 주문, -1 Channel Divinity
## time: action / bonus. range: 칸. conc: 집중
## target: enemy(적 하나), ally(아군 하나, 자신 포함), downed(쓰러진 아군), any(누구든), area(대상 없이 바로)
const DATA := {
	"sacred_flame": {"name": "Sacred Flame", "level": 0, "time": "action", "range": 12, "target": "enemy"},
	"spare_the_dying": {"name": "Spare the Dying", "level": 0, "time": "action", "range": 3, "target": "downed"},
	"guiding_bolt": {"name": "Guiding Bolt", "level": 1, "time": "action", "range": 24, "target": "enemy"},
	"cure_wounds": {"name": "Cure Wounds", "level": 1, "time": "action", "range": 1, "target": "ally"},
	"healing_word": {"name": "Healing Word", "level": 1, "time": "bonus", "range": 12, "target": "ally"},
	"bless": {"name": "Bless", "level": 1, "time": "action", "range": 6, "target": "area", "conc": true},
	"shield_of_faith": {"name": "Shield of Faith", "level": 1, "time": "bonus", "range": 12, "target": "ally", "conc": true},
	"aid": {"name": "Aid", "level": 2, "time": "action", "range": 6, "target": "area"},
	"spiritual_weapon": {"name": "Spiritual Weapon", "level": 2, "time": "bonus", "range": 12, "target": "enemy", "conc": true},
	"spirit_guardians": {"name": "Spirit Guardians", "level": 3, "time": "action", "range": 3, "target": "area", "conc": true},
	## level -2: 이미 쓴 주문의 후속 행동 (슬롯을 쓰지 않음). range는 영적 무기에서 잼
	"spirit_strike": {"name": "영적 무기 공격", "level": -2, "time": "bonus", "range": 5, "target": "enemy"},
	"divine_spark": {"name": "Divine Spark", "level": -1, "time": "action", "range": 6, "target": "any"},
	"turn_undead": {"name": "Turn Undead", "level": -1, "time": "action", "range": 6, "target": "area"},
	"preserve_life": {"name": "Preserve Life", "level": -1, "time": "action", "range": 6, "target": "area"},
}
## 원형 메뉴에 보여줄 한 줄 설명
const SUMMARY := {
	"sacred_flame": "적 하나가 DEX 내성에 실패하면 1d8 광휘. 엄폐로 피할 수 없음",
	"spare_the_dying": "쓰러진 아군을 안정시킴 (사망 내성을 더 굴리지 않음)",
	"guiding_bolt": "원거리 주문 공격 4d6 광휘. 맞으면 그 적을 노리는 다음 공격에 이점",
	"cure_wounds": "옆 칸 아군(자신 포함) 2d8 + WIS 회복",
	"healing_word": "멀리 있는 아군 2d4 + WIS 회복. 쓰러진 아군도 일으킴",
	"bless": "주변 아군 3명의 공격과 내성에 +1d4 (집중)",
	"shield_of_faith": "아군 하나 AC +2 (집중)",
	"aid": "주변 아군 3명의 최대 HP와 현재 HP +5 (전투가 끝날 때까지)",
	"spiritual_weapon": "적 옆에 떠다니는 무기를 만들고 근접 주문 공격 1d8 + WIS 역장. 다음 턴부터 보너스 행동으로 4칸 옮겨 다시 공격 (집중)",
	"spirit_guardians": "주위 3칸에 수호령. 그 안의 적은 속도가 절반이고, 들어오거나 턴을 끝내면 WIS 내성 실패 시 3d8 광휘 (성공 절반, 집중)",
	"spirit_strike": "영적 무기를 4칸까지 옮겨 옆의 적에게 근접 주문 공격",
	"divine_spark": "아군은 1d8 + WIS 회복, 적은 CON 내성 실패 시 1d8 + WIS 광휘",
	"turn_undead": "6칸 안 언데드가 WIS 내성에 실패하면 행동 불능",
	"preserve_life": "클레릭 레벨 × 5 HP를 다친 아군에게 나눔 (최대 HP 절반까지)",
}
## 집중이 끝나면 같이 사라지는 효과
const CONC_EFFECTS := ["blessed", "shield_of_faith"]
const HEALS := ["cure_wounds", "healing_word"]


static func spell_name(id: String) -> String:
	return DATA[id].name


static func range_of(c: Creature, id: String) -> int:
	var r: int = DATA[id].range
	if id == "spare_the_dying" and c.stats.level >= 5:
		r *= 2  # 소마법 강화 [SRD]
	return r


## min_level 이상에서 남아 있는 가장 낮은 슬롯 (없으면 0). 슬롯을 고르지 않았을 때 씀
static func lowest_slot(c: Creature, min_level := 1) -> int:
	for l in range(maxi(min_level, 1), 10):
		if c.resources.get("slot%d" % l, 0) > 0:
			return l
	return 0


## min_level 이상에서 남아 있는 슬롯 레벨들 (오름차순)
static func slot_levels(c: Creature, min_level := 1) -> Array[int]:
	var out: Array[int] = []
	for l in range(maxi(min_level, 1), 10):
		if c.resources.get("slot%d" % l, 0) > 0:
			out.append(l)
	return out


## 이 주문에 실제로 쓸 슬롯. slot이 0이면 가장 낮은 것 (쓸 수 없으면 0)
static func pick_slot(c: Creature, id: String, slot := 0) -> int:
	var lv: int = DATA[id].level
	if lv < 1:
		return 0
	if slot <= 0:
		return lowest_slot(c, lv)
	if slot < lv or c.resources.get("slot%d" % slot, 0) <= 0:
		return 0
	return slot


## 이 주문을 알고 있는지 (영적 무기 공격은 Spiritual Weapon이 떠 있을 때만)
static func knows(c: Creature, id: String) -> bool:
	if id == "spirit_strike":
		return c.concentration == "spiritual_weapon" and c.spirit_cell.x >= 0
	return c.stats.spells.has(id)


static func cantrip_dice(c: Creature) -> int:
	return 2 if c.stats.level >= 5 else 1


# =====================================================================
# 쓸 수 있는지
# =====================================================================

## 지금 이 주문을 쓸 수 없는 이유. 빈 문자열이면 가능
static func why_not(cb: Combat, c: Creature, id: String, slot := 0) -> String:
	if cb.over or not c.can_act():
		return "행동할 수 없음"
	if not knows(c, id):
		return "Spiritual Weapon이 없음" if id == "spirit_strike" else "모르는 주문"
	var d: Dictionary = DATA[id]
	if d.time == "action" and not c.action_available:
		return "행동을 이미 썼음"
	if d.time == "bonus" and not c.bonus_available:
		return "보너스 행동을 이미 썼음"
	if d.level == -1 and c.resources.get("channel", 0) <= 0:
		return "Channel Divinity를 다 썼음"
	if d.level >= 1:
		if pick_slot(c, id, slot) == 0:
			return "주문 슬롯이 없음" if slot <= 0 else "%d레벨 슬롯을 쓸 수 없음" % slot
		if c.once_per_turn.has("slot"):
			return "슬롯 주문은 턴에 하나만"
	if id == "turn_undead" and _undead_near(cb, c).is_empty():
		return "6칸 안에 언데드가 없음"
	if id == "preserve_life" and _preserve_targets(cb, c).is_empty():
		return "6칸 안에 HP가 절반 이하인 아군이 없음"
	return ""


## t에게 쓸 수 없는 이유. 빈 문자열이면 가능
static func target_error(cb: Combat, c: Creature, id: String, t: Creature) -> String:
	var d: Dictionary = DATA[id]
	if t == null or not t.is_alive():
		return "대상 없음"
	# 영적 무기 공격은 무기가 있는 칸에서 잽니다
	var from := c.spirit_cell if id == "spirit_strike" else c.cell
	if cb.grid.distance(from, t.cell) > range_of(c, id):
		return ("무기에서 %d칸 넘게 떨어짐" if id == "spirit_strike" else "사거리 밖 (%d칸)") % range_of(c, id)
	if t != c and id != "spirit_strike" and cb.grid.cover(c.cell, t.cell) >= CombatGrid.TOTAL_COVER:
		return "보이지 않음"
	var ally := not t.is_hostile_to(c)
	match d.target:
		"enemy":
			if ally:
				return "적에게만"
		"ally":
			if not ally:
				return "아군에게만"
			if HEALS.has(id) and t.hp >= t.stats.max_hp:
				return "HP가 가득 참"
		"downed":
			if not ally or not t.is_down():
				return "쓰러진 아군에게만"
			if t.stable:
				return "이미 안정됨"
		"any":
			if ally and t.hp >= t.stats.max_hp:
				return "HP가 가득 참"
	return ""


static func needs_target(id: String) -> bool:
	return DATA[id].target != "area"


# =====================================================================
# 시전
# =====================================================================

## slot: 쓸 슬롯 레벨 (0이면 가장 낮은 것)
static func cast(cb: Combat, c: Creature, id: String, t: Creature = null, slot := 0) -> bool:
	var why := why_not(cb, c, id, slot)
	if why == "" and needs_target(id):
		why = target_error(cb, c, id, t)
	if why != "":
		cb.log_msg("%s: 쓸 수 없음 (%s)" % [spell_name(id), why])
		return false
	var d: Dictionary = DATA[id]
	if d.time == "action":
		c.action_available = false
		c.attacks_left = 0
	else:
		c.bonus_available = false
	slot = pick_slot(c, id, slot)
	var cost := ""
	if d.level >= 1:
		c.resources["slot%d" % slot] -= 1
		c.once_per_turn["slot"] = true
		cost = " (%d레벨 슬롯)" % slot
	elif d.level == -1:
		c.resources["channel"] -= 1
		cost = " (Channel Divinity)"
	if d.get("conc", false):
		end_concentration(cb, c)
		c.conc_slot = slot
	if t != null and t.cell != c.cell:
		c.facing = t.cell - c.cell
	var on := (" → %s" % t.display_name) if t != null and t != c else ""
	cb.log_msg("[color=#e8d27a]%s: %s%s%s[/color]" % [c.display_name, spell_name(id), cost, on])
	cb.event.emit({"type": "cast", "caster": c, "target": t, "spell": id})
	match id:
		"sacred_flame":
			_sacred_flame(cb, c, t)
		"spare_the_dying":
			t.stable = true
			t.death_successes = 0
			t.death_failures = 0
			cb.log_msg("  %s 안정됨 (사망 내성을 더 굴리지 않음)" % t.display_name)
			cb.event.emit({"type": "condition", "creature": t})
		"guiding_bolt":
			var w := bolt_weapon(slot)
			var info := cb.attack_info(c, t, w)
			if info.valid:
				var res := cb.resolve_attack(c, t, w, info)
				if res.hit and t.is_alive():
					t.add_effect("guided", c, "end", 1)
					cb.log_msg("  %s에 대한 다음 공격에 이점" % t.display_name)
		"cure_wounds", "healing_word":
			_heal(cb, c, t, heal_amount(cb.dice, c, id, slot), slot)
		"bless":
			_bless(cb, c, slot)
		"shield_of_faith":
			t.add_effect("shield_of_faith", c, "never")
			c.concentration = id
			cb.log_msg("  %s AC +2 (집중)" % t.display_name)
			cb.event.emit({"type": "condition", "creature": t})
		"aid":
			_aid(cb, c, slot)
		"spiritual_weapon":
			c.concentration = id
			_spirit_attack(cb, c, t, _spirit_spot(cb, t.cell, c.cell))
		"spirit_strike":
			_spirit_attack(cb, c, t, _spirit_spot(cb, t.cell, c.spirit_cell))
		"spirit_guardians":
			c.concentration = id
			cb.log_msg("  수호령이 %s 주위 3칸을 감쌈 (적 속도 절반, 집중)" % c.display_name)
			cb.event.emit({"type": "condition", "creature": c})
			# 처음 나타날 때 범위 안에 있는 적도 내성을 굴림
			for x in cb.creatures.duplicate():
				if x.is_alive() and x.is_hostile_to(c) and cb.grid.distance(c.cell, x.cell) <= 3:
					guardian_save(cb, c, x)
		"divine_spark":
			_divine_spark(cb, c, t)
		"turn_undead":
			_turn_undead(cb, c)
		"preserve_life":
			_preserve_life(cb, c)
	cb.check_end()
	return true


## Guiding Bolt를 원거리 주문 공격 무기로: 4d6 광휘 + 슬롯 레벨마다 1d6, 수정치는 더하지 않음
static func bolt_weapon(slot := 1) -> WeaponData:
	var w := WeaponData.new()
	w.id = "guiding_bolt"
	w.display_name = "Guiding Bolt"
	w.dice_count = 4 + maxi(slot, 1) - 1
	w.dice_sides = 6
	w.damage_type = "radiant"
	w.ranged = true
	w.range_normal = 24
	w.range_long = 24
	w.ability = WIS
	w.add_mod = false
	return w


## Spiritual Weapon: 근접 주문 공격 1d8 + 수정치 역장, 2레벨 위 슬롯마다 1d8
static func spirit_weapon(slot := 2) -> WeaponData:
	var w := WeaponData.new()
	w.id = "spiritual_weapon"
	w.display_name = "Spiritual Weapon"
	w.dice_count = 1 + maxi(slot, 2) - 2
	w.dice_sides = 8
	w.damage_type = "force"
	w.ability = WIS
	return w


## 영적 무기가 갈 칸: 대상 옆 칸 중 near에서 가장 가까운 곳 (비어 있는 칸 우선)
static func _spirit_spot(cb: Combat, target: Vector2i, near: Vector2i) -> Vector2i:
	var best := target
	var best_score := 1e9
	for n in CombatGrid.NEIGHBORS:
		var cell: Vector2i = target + n
		if not cb.grid.in_bounds(cell) or cb.grid.is_wall(cell):
			continue
		var score := float(cb.grid.distance(cell, near)) + (0.0 if cb.grid.occupant(cell) == null else 0.5)
		if score < best_score:
			best_score = score
			best = cell
	return best


static func _spirit_attack(cb: Combat, c: Creature, t: Creature, cell: Vector2i) -> void:
	c.spirit_cell = cell
	cb.event.emit({"type": "spirit", "caster": c, "cell": cell})
	var w := spirit_weapon(c.conc_slot)
	var info := cb.attack_info_from(c, cell, t, w)
	if info.valid:
		cb.resolve_attack(c, t, w, info, false, {"spirit": true})


## Aid: 아군 3명의 최대 HP와 현재 HP +5, 2레벨 위 슬롯마다 +5 [변경: 대상 자동, 8시간 대신 전투 끝까지]
## 같은 주문은 겹치지 않으므로 이미 받은 값보다 클 때만 차이만큼 올립니다.
static func _aid(cb: Combat, c: Creature, slot: int) -> void:
	var amount := 5 * (maxi(slot, 2) - 1)
	var names: Array[String] = []
	for x in aid_targets(cb, c):
		if amount <= x.aid_bonus:
			names.append("%s (이미 받음)" % x.display_name)
			continue
		var gain := amount - x.aid_bonus
		x.stats = x.stats.duplicate()  # 다른 크리처와 스탯을 같이 쓰지 않게
		x.stats.max_hp += gain
		x.aid_bonus = amount
		var was_down := x.is_down()
		var healed := Damage.heal(x, gain)
		names.append("%s +%d" % [x.display_name, gain])
		cb.event.emit({"type": "hp", "creature": x, "delta": healed, "hp": x.hp, "crit": false})
		cb.event.emit({"type": "condition", "creature": x})
		if was_down and x.hp > 0:
			cb.log_msg("  %s 의식을 되찾음" % x.display_name)
	cb.log_msg("  최대 HP와 HP 증가: %s" % ", ".join(names))


## Aid 대상: 6칸 안 아군 중 최대 HP 대비 HP가 낮은 순으로 3명 (쓰러진 아군 먼저)
static func aid_targets(cb: Combat, c: Creature) -> Array[Creature]:
	var out := _allies_near(cb, c, 6)
	out.sort_custom(func(a: Creature, b: Creature) -> bool:
		return float(a.hp) / a.stats.max_hp < float(b.hp) / b.stats.max_hp)
	return out.slice(0, 3)


static func _allies_near(cb: Combat, c: Creature, r: int) -> Array[Creature]:
	var out: Array[Creature] = []
	for x in cb.creatures:
		if x.is_alive() and not x.is_hostile_to(c) and cb.grid.distance(c.cell, x.cell) <= r:
			if x == c or cb.grid.cover(c.cell, x.cell) < CombatGrid.TOTAL_COVER:
				out.append(x)
	return out


# =====================================================================
# Spirit Guardians (rules 7.6)
# =====================================================================

## cell이 mover에게 적대적인 Spirit Guardians 안인지
static func in_guardians(cb: Combat, cell: Vector2i, mover: Creature) -> Creature:
	for x in cb.creatures:
		if x.concentration == "spirit_guardians" and x.is_alive() and x != mover and x.is_hostile_to(mover) \
				and cb.grid.distance(x.cell, cell) <= 3:
			return x
	return null


## WIS 내성 실패 시 3d8 광휘, 성공 시 절반. 3레벨 위 슬롯마다 1d8. 한 턴에 한 번만 [SRD]
static func guardian_save(cb: Combat, caster: Creature, x: Creature) -> void:
	var turn := cb.turn_serial()
	if x.guardian_turn == turn or not x.is_alive() or x.is_down():
		return
	x.guardian_turn = turn
	var n := 3 + maxi(caster.conc_slot, 3) - 3
	var rolls := cb.dice.roll(n, 8)
	var sv := cb.saving_throw(x, WIS, caster.spell_dc())
	var dmg := Dice.sum(rolls)
	if sv.success:
		dmg = floori(dmg / 2.0)
	cb.log_msg("  수호령 → %s: %s → %dd8%s 광휘%s" % [x.display_name, sv.text, n, str(rolls), " 절반" if sv.success else ""])
	cb._deal(x, dmg, "radiant", false, "Spirit Guardians")


## 한 걸음 움직인 뒤: 수호령 범위에 들어왔거나, 수호령을 두른 시전자가 움직여 범위가 적에게 닿았는지
static func on_step(cb: Combat, c: Creature, from: Vector2i) -> void:
	for x in cb.creatures:
		if x.concentration == "spirit_guardians" and x.is_alive() and x != c and x.is_hostile_to(c):
			if cb.grid.distance(x.cell, c.cell) <= 3 and cb.grid.distance(x.cell, from) > 3:
				guardian_save(cb, x, c)
	if c.concentration == "spirit_guardians":
		for x in cb.creatures.duplicate():
			if x.is_alive() and x.is_hostile_to(c) and cb.grid.distance(c.cell, x.cell) <= 3 \
					and cb.grid.distance(from, x.cell) > 3:
				guardian_save(cb, c, x)


## 턴이 끝날 때 수호령 범위 안이면 내성
static func on_turn_end(cb: Combat, c: Creature) -> void:
	var g := in_guardians(cb, c.cell, c)
	if g != null:
		guardian_save(cb, g, c)


static func heal_amount(dice: Dice, c: Creature, id: String, slot: int) -> Dictionary:
	var sides := 8 if id == "cure_wounds" else 4
	var rolls := dice.roll(2 * slot, sides)
	var bonus := c.spell_mod()
	var life := (2 + slot) if c.stats.has_feature("disciple_of_life") else 0
	return {"amount": maxi(Dice.sum(rolls) + bonus + life, 0),
		"text": "%dd%d%s %+d%s" % [2 * slot, sides, str(rolls), bonus, (" + Disciple of Life %d" % life) if life > 0 else ""]}


static func _heal(cb: Combat, _c: Creature, t: Creature, h: Dictionary, _slot: int) -> void:
	var was_down := t.is_down()
	var healed := Damage.heal(t, h.amount)
	cb.log_msg("  %s HP +%d (%s) → %d/%d%s" % [t.display_name, healed, h.text, t.hp, t.stats.max_hp,
			" — 의식을 되찾음" if was_down and t.hp > 0 else ""])
	cb.event.emit({"type": "hp", "creature": t, "delta": healed, "hp": t.hp, "crit": false})
	if was_down:
		cb.event.emit({"type": "condition", "creature": t})


static func _sacred_flame(cb: Combat, c: Creature, t: Creature) -> void:
	# 절반, 3/4 엄폐는 이 내성에 도움이 안 됨 [SRD]
	var sv := cb.saving_throw(t, DEX, c.spell_dc())
	if sv.success:
		cb.log_msg("  %s → 피함" % sv.text)
		return
	var n := cantrip_dice(c)
	var rolls := cb.dice.roll(n, 8)
	cb.log_msg("  %s → %dd8%s 광휘 피해" % [sv.text, n, str(rolls)])
	cb._deal(t, Dice.sum(rolls), "radiant", false, "Sacred Flame")


## 6칸 안의 아군을 가까운 순으로 최대 3명 (+ 슬롯 레벨마다 1명) [변경: 대상을 자동으로 고름]
static func bless_targets(cb: Combat, c: Creature, slot := 1) -> Array[Creature]:
	var out: Array[Creature] = []
	for x in cb.creatures:
		if x.is_alive() and not x.is_hostile_to(c) and cb.grid.distance(c.cell, x.cell) <= 6:
			if x == c or cb.grid.cover(c.cell, x.cell) < CombatGrid.TOTAL_COVER:
				out.append(x)
	out.sort_custom(func(a: Creature, b: Creature) -> bool:
		return cb.grid.distance(c.cell, a.cell) < cb.grid.distance(c.cell, b.cell))
	return out.slice(0, 3 + maxi(slot, 1) - 1)


static func _bless(cb: Combat, c: Creature, slot: int) -> void:
	var names: Array[String] = []
	for x in bless_targets(cb, c, slot):
		x.add_effect("blessed", c, "never")
		names.append(x.display_name)
		cb.event.emit({"type": "condition", "creature": x})
	c.concentration = "bless"
	cb.log_msg("  축복: %s (공격과 내성에 +1d4, 집중)" % ", ".join(names))


static func _divine_spark(cb: Combat, c: Creature, t: Creature) -> void:
	var roll := cb.dice.roll_die(8)
	var total := maxi(roll + c.spell_mod(), 0)
	if not t.is_hostile_to(c):
		_heal(cb, c, t, {"amount": total, "text": "1d8[%d] %+d" % [roll, c.spell_mod()]}, 0)
		return
	var sv := cb.saving_throw(t, CON, c.spell_dc())
	var dmg := total if not sv.success else floori(total / 2.0)
	cb.log_msg("  %s → 1d8[%d] %+d%s 광휘 피해" % [sv.text, roll, c.spell_mod(), " 절반" if sv.success else ""])
	cb._deal(t, dmg, "radiant", false, "Divine Spark")


static func _undead_near(cb: Combat, c: Creature) -> Array[Creature]:
	var out: Array[Creature] = []
	for x in cb.creatures:
		if x.is_alive() and x.is_hostile_to(c) and x.stats.creature_type == "undead" \
				and cb.grid.distance(c.cell, x.cell) <= 6 and not x.has_effect("turned"):
			out.append(x)
	return out


## 실패한 언데드는 1분(10라운드) 동안 행동 불능. 피해를 입으면 풀림 [변경: 도망치지 않고 그 자리에서 멈춤]
static func _turn_undead(cb: Combat, c: Creature) -> void:
	for x in _undead_near(cb, c):
		var sv := cb.saving_throw(x, WIS, c.spell_dc())
		if sv.success:
			cb.log_msg("  %s → 버팀" % sv.text)
			continue
		cb.log_msg("  %s → 겁에 질려 행동 불능" % sv.text)
		if c.stats.has_feature("sear_undead"):
			# Sear Undead: WIS 수정치만큼 d8 (최소 1개). 이 피해로는 Turn이 풀리지 않음 [SRD]
			var rolls := cb.dice.roll(maxi(c.spell_mod(), 1), 8)
			cb._deal(x, Dice.sum(rolls), "radiant", false, "Sear Undead %s" % str(rolls))
		if x.is_alive():
			x.add_effect("turned", c, "end", 9)
			cb.event.emit({"type": "condition", "creature": x})


static func _preserve_targets(cb: Combat, c: Creature) -> Array[Creature]:
	var out: Array[Creature] = []
	for x in cb.creatures:
		if x.is_alive() and not x.is_hostile_to(c) and cb.grid.distance(c.cell, x.cell) <= 6 \
				and x.hp < floori(x.stats.max_hp / 2.0):
			out.append(x)
	return out


## 클레릭 레벨 × 5를 HP 절반 이하 아군에게 나눔. 각자 최대 HP의 절반까지 [변경: 한 HP씩 돌아가며 자동 배분]
static func _preserve_life(cb: Combat, c: Creature) -> void:
	var targets := _preserve_targets(cb, c)
	var pool := 5 * c.stats.level
	var give := {}
	var progress := true
	while pool > 0 and progress:
		progress = false
		for x in targets:
			if pool > 0 and x.hp + give.get(x, 0) < floori(x.stats.max_hp / 2.0):
				give[x] = give.get(x, 0) + 1
				pool -= 1
				progress = true
	for x in give:
		_heal(cb, c, x, {"amount": give[x], "text": "Preserve Life"}, 0)


# =====================================================================
# 집중 (rules 7.5)
# =====================================================================

static func end_concentration(cb: Combat, c: Creature) -> void:
	if c.concentration == "":
		return
	var id := c.concentration
	c.concentration = ""
	if c.spirit_cell.x >= 0:
		c.spirit_cell = Vector2i(-1, -1)
		cb.event.emit({"type": "spirit", "caster": c, "cell": c.spirit_cell})
	cb.event.emit({"type": "condition", "creature": c})
	for x in cb.creatures:
		if x.remove_effects_from(c, CONC_EFFECTS):
			cb.event.emit({"type": "condition", "creature": x})
	cb.log_msg("  %s의 %s 집중이 끝남" % [c.display_name, spell_name(id)])


## 피해를 입으면 CON 내성 DC max(10, 피해의 절반), 최대 30 [SRD]
static func concentration_check(cb: Combat, c: Creature, dealt: int) -> void:
	if c.concentration == "" or dealt <= 0:
		return
	var sv := cb.saving_throw(c, CON, clampi(floori(dealt / 2.0), 10, 30))
	cb.log_msg("  집중 유지: %s" % sv.text)
	if not sv.success:
		end_concentration(cb, c)


# =====================================================================
# 화면 설명
# =====================================================================

## 대상에 마우스를 올렸을 때 보여줄 한 줄
static func describe(cb: Combat, c: Creature, id: String, t: Creature, slot := 0) -> String:
	slot = maxi(pick_slot(c, id, slot), maxi(DATA[id].level, 1))
	match id:
		"spiritual_weapon", "spirit_strike":
			var s := slot if id == "spiritual_weapon" else c.conc_slot
			var from := _spirit_spot(cb, t.cell, c.cell if id == "spiritual_weapon" else c.spirit_cell)
			var info := cb.attack_info_from(c, from, t, spirit_weapon(s))
			return "명중 확률 %d%% · %dd8 %+d 역장" % [roundi(info.chance * 100), s - 1, c.spell_mod()]
		"sacred_flame":
			return "DEX 내성 DC %d · 실패 확률 %d%% · %dd8 광휘" % [c.spell_dc(),
				roundi(fail_chance(t.save_bonus(DEX), c.spell_dc()) * 100), cantrip_dice(c)]
		"guiding_bolt":
			var info := cb.attack_info(c, t, bolt_weapon(slot))
			return "명중 확률 %d%% · %dd6 광휘, 맞으면 다음 공격에 이점" % [roundi(info.chance * 100), 3 + slot]
		"cure_wounds":
			return "%dd8 %+d 회복" % [2 * slot, c.spell_mod() + (2 + slot if c.stats.has_feature("disciple_of_life") else 0)]
		"healing_word":
			return "%dd4 %+d 회복" % [2 * slot, c.spell_mod() + (2 + slot if c.stats.has_feature("disciple_of_life") else 0)]
		"shield_of_faith":
			return "AC +2 (집중)"
		"spare_the_dying":
			return "안정시킴 — 사망 내성을 더 굴리지 않음"
		"divine_spark":
			if t.is_hostile_to(c):
				return "CON 내성 DC %d · 1d8 %+d 광휘 (성공하면 절반)" % [c.spell_dc(), c.spell_mod()]
			return "1d8 %+d 회복" % c.spell_mod()
	return ""


## 슬롯 레벨을 고를 때 보여줄 효과 (그 슬롯으로 쓰면 어떻게 되는지)
static func upcast_text(c: Creature, id: String, slot: int) -> String:
	var life := (2 + slot) if c.stats.has_feature("disciple_of_life") else 0
	match id:
		"guiding_bolt":
			return "%dd6 광휘" % (3 + slot)
		"cure_wounds":
			return "%dd8 %+d 회복" % [2 * slot, c.spell_mod() + life]
		"healing_word":
			return "%dd4 %+d 회복" % [2 * slot, c.spell_mod() + life]
		"bless":
			return "아군 %d명" % (2 + slot)
		"aid":
			return "최대 HP +%d" % (5 * (slot - 1))
		"spiritual_weapon":
			return "%dd8 %+d 역장" % [slot - 1, c.spell_mod()]
		"spirit_guardians":
			return "%dd8 광휘" % slot
	return "높은 슬롯이어도 효과 같음"


## d20 + bonus < dc 일 확률 (내성은 1, 20 자동 판정 없음)
static func fail_chance(bonus: int, dc: int) -> float:
	return clampf((dc - 1 - bonus) / 20.0, 0.0, 1.0)
