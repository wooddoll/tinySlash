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


## min_level 이상에서 남아 있는 가장 낮은 슬롯 (없으면 0) [변경: 슬롯을 고르지 않고 자동]
static func lowest_slot(c: Creature, min_level := 1) -> int:
	for l in range(maxi(min_level, 1), 10):
		if c.resources.get("slot%d" % l, 0) > 0:
			return l
	return 0


static func cantrip_dice(c: Creature) -> int:
	return 2 if c.stats.level >= 5 else 1


# =====================================================================
# 쓸 수 있는지
# =====================================================================

## 지금 이 주문을 쓸 수 없는 이유. 빈 문자열이면 가능
static func why_not(cb: Combat, c: Creature, id: String) -> String:
	if cb.over or not c.can_act():
		return "행동할 수 없음"
	if not c.stats.spells.has(id):
		return "모르는 주문"
	var d: Dictionary = DATA[id]
	if d.time == "action" and not c.action_available:
		return "행동을 이미 썼음"
	if d.time == "bonus" and not c.bonus_available:
		return "보너스 행동을 이미 썼음"
	if d.level == -1 and c.resources.get("channel", 0) <= 0:
		return "Channel Divinity를 다 썼음"
	if d.level >= 1:
		if lowest_slot(c, d.level) == 0:
			return "주문 슬롯이 없음"
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
	if cb.grid.distance(c.cell, t.cell) > range_of(c, id):
		return "사거리 밖 (%d칸)" % range_of(c, id)
	if t != c and cb.grid.cover(c.cell, t.cell) >= CombatGrid.TOTAL_COVER:
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

static func cast(cb: Combat, c: Creature, id: String, t: Creature = null) -> bool:
	var why := why_not(cb, c, id)
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
	var slot := 0
	var cost := ""
	if d.level >= 1:
		slot = lowest_slot(c, d.level)
		c.resources["slot%d" % slot] -= 1
		c.once_per_turn["slot"] = true
		cost = " (%d레벨 슬롯)" % slot
	elif d.level == -1:
		c.resources["channel"] -= 1
		cost = " (Channel Divinity)"
	if d.get("conc", false):
		end_concentration(cb, c)
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
static func describe(cb: Combat, c: Creature, id: String, t: Creature) -> String:
	var slot := maxi(lowest_slot(c, DATA[id].level), 1)
	match id:
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


## d20 + bonus < dc 일 확률 (내성은 1, 20 자동 판정 없음)
static func fail_chance(bonus: int, dc: int) -> float:
	return clampf((dc - 1 - bonus) / 20.0, 0.0, 1.0)
