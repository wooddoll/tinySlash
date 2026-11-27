## 클래스 기능: 스킬 메뉴에 나오는 행동, 사용 횟수 자원, 공격·피해·내성에 붙는 효과 (docs/rules.md 7장)
## 주문은 rules/spells.gd, 공격 판정 본체는 rules/combat.gd에 있고 여기서는 클래스마다 다른 부분만 다룹니다.
class_name ClassFeatures
extends RefCounted

const STR := Rules.Ability.STR
const DEX := Rules.Ability.DEX
const CON := Rules.Ability.CON

## 사용 횟수 자원의 표시 이름
const RESOURCE_NAMES := {
	"second_wind": "Second Wind", "action_surge": "Action Surge", "channel": "Channel Divinity",
	"rage": "Rage", "focus": "Focus", "lay_on_hands": "치유 풀",
	"free_smite": "무료 Smite", "free_mark": "무료 Hunter's Mark", "innate": "Innate Sorcery", "sp": "마법 점수",
	"bardic_inspiration": "영감", "wild_shape": "Wild Shape",
}
## 마법 점수로 슬롯 만들기: 슬롯 레벨 → [점수, 최소 소서러 레벨] [SRD]
const SLOT_COST := {1: [2, 2], 2: [3, 3], 3: [5, 5]}
## 이계 존재: Protection from Evil and Good이 막는 크리처 종류
const OTHERWORLDLY := ["aberration", "celestial", "elemental", "fey", "fiend", "undead"]
## 짧은 휴식을 마치면 돌아오는 수 (99 = 전부) [SRD]. 여기 없는 자원은 긴 휴식에만 돌아옴
const SHORT_REST := {"second_wind": 1, "action_surge": 99, "channel": 1, "rage": 1, "focus": 99, "wild_shape": 1}
## 몽크 무기 (Martial Arts, Stunning Strike)
const MONK_WEAPONS := ["unarmed", "spear"]
## 열린 손 기술 순서와 이름
const OPEN_HAND := ["topple", "push", "addle"]
const OPEN_HAND_NAMES := {"topple": "넘어뜨리기", "push": "밀쳐내기", "addle": "어지럽히기"}
## 몸에 B/P/S 저항을 주는 효과
const PHYSICAL := ["bludgeoning", "piercing", "slashing"]


# =====================================================================
# 자원
# =====================================================================

## 새 크리처의 사용 횟수 (Creature._init에서 부름)
static func init_resources(c: Creature) -> void:
	var s := c.stats
	if s.has_feature("second_wind"):
		c.resources["second_wind"] = c.second_wind_max()
	if s.has_feature("action_surge"):
		c.resources["action_surge"] = 1
	if s.has_feature("rage"):
		c.resources["rage"] = rage_max(s.level)
	if s.has_feature("monks_focus"):
		c.resources["focus"] = s.level
	if s.has_feature("uncanny_metabolism"):
		c.resources["metabolism"] = 1
	if s.has_feature("lay_on_hands"):
		c.resources["lay_on_hands"] = 5 * s.level
	if s.has_feature("paladins_smite"):
		c.resources["free_smite"] = 1
	if s.has_feature("favored_enemy"):
		c.resources["free_mark"] = 2
	if s.has_feature("arcane_recovery"):
		c.resources["arcane_recovery"] = 1
	if s.has_feature("innate_sorcery"):
		c.resources["innate"] = 2
	if s.has_feature("wild_shape"):
		c.resources["wild_shape"] = 2
	if s.has_feature("bardic_inspiration"):
		c.resources["bardic_inspiration"] = maxi(1, s.ability_mod(Rules.Ability.CHA))
	if s.has_feature("font_of_magic"):
		c.resources["sp"] = s.level
	if s.has_feature("sorcerous_restoration"):
		c.resources["restoration"] = 1
	for i in s.spell_slots.size():
		if s.spell_slots[i] > 0:
			c.resources["slot%d" % (i + 1)] = s.spell_slots[i]
	if s.channel_divinity > 0:
		c.resources["channel"] = s.channel_divinity


## 바바리안 Rage 횟수 [SRD 표: 1~2레벨 2, 3~5레벨 3]
static func rage_max(level: int) -> int:
	return 3 if level >= 3 else 2


## 바바리안 Rage 피해 보너스 [SRD 표: 1~8레벨 +2]
static func rage_damage(_level: int) -> int:
	return 2


## 상태 줄과 정보 창에 쓰는 남은 자원 ("Rage 2" 같은 글자들). 주문 슬롯과 물약은 따로
static func resource_labels(c: Creature) -> Array[String]:
	var out: Array[String] = []
	for k in RESOURCE_NAMES:
		if c.resources.has(k):
			out.append("%s %d" % [RESOURCE_NAMES[k], c.resources[k]])
	return out


## 짧은 휴식에 클래스마다 더 돌아오는 것: 위저드 Arcane Recovery (긴 휴식마다 1회, 레벨 절반(올림)만큼 슬롯 레벨 합)
static func short_rest_extra(level: int, features: PackedStringArray, now: Dictionary, full: Dictionary) -> Dictionary:
	var out := now.duplicate()
	if features.has("font_of_inspiration") and full.has("bardic_inspiration"):
		out["bardic_inspiration"] = full.bardic_inspiration
	if features.has("pact_magic"):
		for l in range(1, 6):
			if full.has("slot%d" % l):
				out["slot%d" % l] = full["slot%d" % l]
	if features.has("sorcerous_restoration") and int(out.get("restoration", 1)) > 0 and full.has("sp"):
		var sp := int(out.get("sp", full.sp))
		if sp < full.sp:
			out["sp"] = mini(full.sp, sp + level / 2)
			out["restoration"] = 0
	if features.has("arcane_recovery") and int(out.get("arcane_recovery", 1)) > 0:
		var budget := ceili(level / 2.0)
		var got := false
		for l in range(5, 0, -1):
			var k := "slot%d" % l
			while full.has(k) and int(out.get(k, full[k])) < full[k] and l <= budget:
				out[k] = int(out.get(k, full[k])) + 1
				budget -= l
				got = true
		if got:
			out["arcane_recovery"] = 0
	return out


## 짧은 휴식 후 자원 (now: 지금 남은 것, full: 처음 상태)
static func after_short_rest(now: Dictionary, full: Dictionary) -> Dictionary:
	var out := now.duplicate()
	for k in SHORT_REST:
		if full.has(k):
			out[k] = mini(int(now.get(k, full[k])) + SHORT_REST[k], full[k])
	return out


# =====================================================================
# 스킬 메뉴의 클래스 행동
# =====================================================================

## {id, name, sub, desc, reason} 목록. reason이 빈 문자열이면 쓸 수 있음
static func actions(cb: Combat, c: Creature) -> Array:
	var out: Array = []
	var bonus := "" if c.bonus_available else "보너스 행동을 이미 썼음"
	if c.resources.has("second_wind"):
		var n: int = c.resources.second_wind
		out.append(_item("second_wind", "Second Wind", "보너스 · %d회" % n, "1d10 + %d 회복" % c.stats.level,
			"남은 횟수 없음" if n <= 0 else bonus))
	if c.resources.has("action_surge"):
		var n: int = c.resources.action_surge
		out.append(_item("action_surge", "Action Surge", "%d회" % n, "이번 턴에 행동 1회 추가",
			"남은 횟수 없음" if n <= 0 else ("이번 턴에 이미 씀" if c.action_surge_used else "")))
	if c.resources.has("rage"):
		var n: int = c.resources.rage
		if c.has_effect("raging"):
			out.append(_item("rage_keep", "분노 유지", "보너스", "공격하지 않아도 분노를 다음 턴 끝까지 이어 감",
				"이번 턴에는 이미 이어짐" if c.once_per_turn.has("rage_kept") else bonus))
		else:
			out.append(_item("rage", "Rage", "보너스 · %d회" % n,
				"분노: B/P/S 피해 저항, 근력 공격 피해 +%d, 근력 판정·내성 이점. 공격하지 않은 턴이 끝나면 풀림" % rage_damage(c.stats.level),
				"남은 횟수 없음" if n <= 0 else bonus))
	if c.stats.has_feature("reckless_attack"):
		var why := ""
		if c.has_effect("reckless"):
			why = "이미 무모하게 공격 중"
		elif c.once_per_turn.has("attacked"):
			why = "이번 턴 첫 공격 전에만"
		out.append(_item("reckless", "무모한 공격", "무료",
			"다음 내 턴 시작까지 내 근력 공격에 이점. 대신 나를 노리는 공격도 이점%s" %
			(" · 분노 중이면 Frenzy: 처음 맞힌 대상에 %dd6 추가" % rage_damage(c.stats.level) if c.stats.has_feature("frenzy") else ""), why))
	if c.stats.has_feature("martial_arts"):
		var fp: int = c.resources.get("focus", 0)
		var no_fp := "Focus가 없음" if fp <= 0 else bonus
		out.append(_item("martial_bonus", "맨손 타격", "보너스", "Martial Arts: 맨손 타격 1회 (1d%d + DEX)" % Catalog.martial_arts_die(c.stats.level), bonus))
		if c.stats.has_feature("monks_focus"):
			var oh := (" · 맞으면 열린 손 기술(%s)" % OPEN_HAND_NAMES[open_hand(c)]) if c.stats.has_feature("open_hand_technique") else ""
			out.append(_item("flurry", "연타", "보너스 · Focus 1", "Flurry of Blows: 맨손 타격 2회%s" % oh, no_fp))
			out.append(_item("patient_defense", "인내의 방어", "보너스 · Focus 1", "Patient Defense: 이탈 + 회피", no_fp))
			out.append(_item("step_of_wind", "바람의 걸음", "보너스 · Focus 1", "Step of the Wind: 이탈 + 질주 (+%d칸)" % c.speed(), no_fp))
		out.append(_item("monk_disengage", "물러서기", "보너스", "Patient Defense(Focus 없이): 이탈", bonus))
		out.append(_item("monk_dash", "내달리기", "보너스", "Step of the Wind(Focus 없이): 질주 (+%d칸)" % c.speed(), bonus))
		if c.stats.has_feature("open_hand_technique"):
			out.append(_item("open_hand", "열린 손 기술: %s" % OPEN_HAND_NAMES[open_hand(c)], "무료",
				"연타가 맞으면 쓸 기술을 바꿈: 넘어뜨리기(DEX 내성 실패 시 넘어짐), 밀쳐내기(STR 내성 실패 시 3칸), 어지럽히기(기회 공격 못 함)", ""))
		if c.stats.has_feature("stunning_strike"):
			var on: bool = c.toggles.get("stun", false)
			out.append(_item("stun", "기절 일격%s" % (" ✓" if on else ""), "무료 · 맞으면 Focus 1",
				"켜 두면 턴에 한 번 몽크 무기로 맞힐 때 Focus 1을 써서 CON 내성(DC %d). 실패하면 다음 내 턴까지 기절, 성공해도 속도 절반·다음 공격에 이점" % focus_dc(c), ""))
	if c.true_stats != null:
		out.append(_item("revert", "본모습으로", "보너스", "Wild Shape를 끝내고 본모습으로 돌아옴", bonus))
	elif c.stats.has_feature("wild_shape"):
		var n: int = c.resources.get("wild_shape", 0)
		out.append(_item("wild_shape", "Wild Shape: 늑대", "보너스 · %d회" % n,
			"늑대로 변신: STR 14·DEX 15·CON 12, AC 12, 속도 8칸, 물기 1d6+2 (Pack Tactics). 임시 HP %d. 주문은 못 쓰지만 집중은 유지" % c.stats.level,
			"남은 횟수 없음" if n <= 0 else bonus))
	if c.stats.has_feature("innate_sorcery"):
		var n: int = c.resources.get("innate", 0)
		out.append(_item("innate_sorcery", "Innate Sorcery", "보너스 · %d회" % n,
			"전투가 끝날 때까지 주문 내성 DC +1, 주문 공격에 이점",
			"이미 켜져 있음" if c.has_effect("innate_sorcery") else ("남은 횟수 없음" if n <= 0 else bonus)))
	if c.stats.has_feature("font_of_magic"):
		var sp: int = c.resources.get("sp", 0)
		for l in SLOT_COST:
			if c.stats.level >= SLOT_COST[l][1]:
				var cost: int = SLOT_COST[l][0]
				out.append(_item("make_slot:%d" % l, "%d레벨 슬롯 만들기" % l, "보너스 · 점수 %d" % cost,
					"마법 점수 %d으로 %d레벨 슬롯 하나 (긴 휴식에 사라짐). 남은 점수 %d" % [cost, l, sp],
					"마법 점수가 모자람" if sp < cost else bonus))
		for l in range(1, 4):
			if c.resources.get("slot%d" % l, 0) > 0:
				out.append(_item("burn_slot:%d" % l, "%d레벨 슬롯 → 점수" % l, "무료",
					"%d레벨 슬롯 하나를 마법 점수 %d로 바꿈" % [l, l], ""))
	if c.stats.has_feature("metamagic"):
		var sp: int = c.resources.get("sp", 0)
		var q: bool = c.toggles.get("quicken", false)
		var cf: bool = c.toggles.get("careful", false)
		out.append(_item("quicken", "Quickened Spell%s" % (" ✓" if q else ""), "점수 2",
			"켜 두면 다음 행동 주문을 보너스 행동으로 씀 (마법 점수 2). 다시 누르면 끔", "" if q or sp >= 2 else "마법 점수가 모자람"))
		out.append(_item("careful", "Careful Spell%s" % (" ✓" if cf else ""), "점수 1",
			"켜 두면 다음 범위 주문에서 아군은 내성에 저절로 성공하고 피해를 받지 않음 (마법 점수 1). 다시 누르면 끔",
			"" if cf or sp >= 1 else "마법 점수가 모자람"))
	if c.stats.has_feature("cunning_action"):
		out.append(_item("cunning_dash", "교활한 질주", "보너스", "Cunning Action: 이번 턴 이동력 +%d칸" % c.speed(), bonus))
		out.append(_item("cunning_disengage", "교활한 이탈", "보너스", "Cunning Action: 이번 턴에는 움직여도 기회 공격을 받지 않음", bonus))
	if c.stats.has_feature("steady_aim"):
		var why := bonus
		if why == "" and c.once_per_turn.has("moved"):
			why = "이번 턴에 이미 움직였음"
		elif why == "" and c.has_effect("steady_aim"):
			why = "이미 조준 중"
		out.append(_item("steady_aim", "정조준", "보너스", "Steady Aim: 이번 턴 다음 공격에 이점. 대신 이번 턴에는 더 못 움직임", why))
	if c.stats.has_feature("cunning_strike"):
		var on := c.has_effect("cs_trip")
		out.append(_item("cs_trip", "교활한 일격: 넘어뜨리기%s" % (" ✓" if on else ""), "무료",
			"다음 Sneak Attack의 d6 하나를 빼고, 대상이 DEX 내성(DC %d)에 실패하면 넘어짐. 다시 누르면 취소" % cunning_dc(c), ""))
	return out


static func _item(id: String, text: String, sub: String, desc: String, reason: String) -> Dictionary:
	return {"id": id, "text": text, "sub": sub, "desc": desc, "disabled": reason != "", "reason": reason}


## 클래스 행동이면 쓰고 true (쓰지 못해도 그 행동이 맞으면 true)
static func use(cb: Combat, c: Creature, id: String) -> bool:
	match id:
		"second_wind": cb.second_wind(c)
		"action_surge": cb.action_surge(c)
		"rage": rage(cb, c)
		"rage_keep": keep_rage(cb, c)
		"reckless": reckless(cb, c)
		"cunning_dash":
			if cb._use_bonus(c):
				c.movement_left += c.speed()
				cb.log_msg("%s 교활한 질주 (이동력 +%d)" % [c.display_name, c.speed()])
		"cunning_disengage":
			if cb._use_bonus(c):
				c.disengaged = true
				cb.log_msg("%s 교활한 이탈 (이번 턴 기회 공격 없음)" % c.display_name)
		"steady_aim": steady_aim(cb, c)
		"martial_bonus":
			if cb._use_bonus(c):
				c.bonus_attacks = 1
				c.toggles["flurry"] = false
				cb.log_msg("%s 맨손 타격 준비 (보너스)" % c.display_name)
		"flurry":
			if _spend_focus(cb, c, "연타"):
				c.bonus_attacks = 2
				c.toggles["flurry"] = true
				cb.log_msg("%s 연타! 맨손 타격 2회" % c.display_name)
		"patient_defense":
			if _spend_focus(cb, c, "인내의 방어"):
				c.disengaged = true
				c.add_effect("dodging", c, "start")
				cb.log_msg("%s 인내의 방어 (이탈 + 회피)" % c.display_name)
		"step_of_wind":
			if _spend_focus(cb, c, "바람의 걸음"):
				c.disengaged = true
				c.movement_left += c.speed()
				cb.log_msg("%s 바람의 걸음 (이탈 + 이동력 +%d)" % [c.display_name, c.speed()])
		"monk_disengage":
			if cb._use_bonus(c):
				c.disengaged = true
				cb.log_msg("%s 물러서기 (이번 턴 기회 공격 없음)" % c.display_name)
		"monk_dash":
			if cb._use_bonus(c):
				c.movement_left += c.speed()
				cb.log_msg("%s 내달리기 (이동력 +%d)" % [c.display_name, c.speed()])
		"wild_shape":
			if c.resources.get("wild_shape", 0) > 0 and c.true_stats == null and cb._use_bonus(c):
				c.resources["wild_shape"] -= 1
				wild_shape(cb, c)
		"revert":
			if c.true_stats != null and cb._use_bonus(c):
				revert(cb, c)
		"innate_sorcery":
			if c.resources.get("innate", 0) > 0 and not c.has_effect("innate_sorcery") and cb._use_bonus(c):
				c.resources["innate"] -= 1
				c.add_effect("innate_sorcery", c, "never")
				cb.log_msg("[color=#e8d27a]%s Innate Sorcery! (주문 DC +1, 주문 공격 이점)[/color]" % c.display_name)
				cb.event.emit({"type": "condition", "creature": c})
		"quicken":
			c.toggles["quicken"] = not c.toggles.get("quicken", false)
		"careful":
			c.toggles["careful"] = not c.toggles.get("careful", false)
		_ when id.begins_with("make_slot:"):
			var l := int(id.get_slice(":", 1))
			var cost: int = SLOT_COST[l][0]
			if c.resources.get("sp", 0) >= cost and cb._use_bonus(c):
				c.resources["sp"] -= cost
				c.resources["slot%d" % l] = c.resources.get("slot%d" % l, 0) + 1
				cb.log_msg("%s 마법 점수 %d → %d레벨 슬롯" % [c.display_name, cost, l])
		_ when id.begins_with("burn_slot:"):
			var l := int(id.get_slice(":", 1))
			if c.resources.get("slot%d" % l, 0) > 0:
				c.resources["slot%d" % l] -= 1
				c.resources["sp"] = c.resources.get("sp", 0) + l
				cb.log_msg("%s %d레벨 슬롯 → 마법 점수 %d" % [c.display_name, l, l])
		"open_hand":
			c.toggles["open_hand"] = OPEN_HAND[(OPEN_HAND.find(open_hand(c)) + 1) % OPEN_HAND.size()]
		"stun":
			c.toggles["stun"] = not c.toggles.get("stun", false)
		"cs_trip":
			if c.has_effect("cs_trip"):
				c.remove_effects("cs_trip")
				cb.log_msg("교활한 일격 취소")
			else:
				c.add_effect("cs_trip", c, "never")
				cb.log_msg("%s 다음 Sneak Attack에 넘어뜨리기를 섞음" % c.display_name)
		_: return false
	return true


static func rage(cb: Combat, c: Creature) -> bool:
	if c.resources.get("rage", 0) <= 0 or c.has_effect("raging"):
		cb.log_msg("Rage를 쓸 수 없습니다")
		return false
	if not cb._use_bonus(c):
		return false
	c.resources["rage"] -= 1
	c.add_effect("raging", c, "never")
	c.once_per_turn["rage_kept"] = true
	if c.concentration != "":
		Spells.end_concentration(cb, c)  # 분노 중에는 집중할 수 없음 [SRD]
	cb.log_msg("[color=#ff7a5a]%s 분노! (B/P/S 저항, 근력 공격 피해 +%d)[/color]" % [c.display_name, rage_damage(c.stats.level)])
	cb.event.emit({"type": "condition", "creature": c})
	return true


static func keep_rage(cb: Combat, c: Creature) -> bool:
	if not c.has_effect("raging") or c.once_per_turn.has("rage_kept") or not cb._use_bonus(c):
		return false
	c.once_per_turn["rage_kept"] = true
	cb.log_msg("%s 분노를 이어 감" % c.display_name)
	return true


static func reckless(cb: Combat, c: Creature) -> bool:
	if not c.stats.has_feature("reckless_attack") or c.has_effect("reckless") or c.once_per_turn.has("attacked"):
		return false
	c.add_effect("reckless", c, "start")
	cb.log_msg("%s 무모한 공격! (근력 공격에 이점, 나를 노리는 공격에도 이점)" % c.display_name)
	cb.event.emit({"type": "condition", "creature": c})
	return true


## Focus 1과 보너스 행동을 씀
static func _spend_focus(cb: Combat, c: Creature, what: String) -> bool:
	if c.resources.get("focus", 0) <= 0:
		cb.log_msg("%s: Focus가 없습니다" % what)
		return false
	if not cb._use_bonus(c):
		return false
	c.resources["focus"] -= 1
	return true


static func open_hand(c: Creature) -> String:
	return c.toggles.get("open_hand", "topple")


## 몽크 Focus 내성 DC = 8 + WIS + PB
static func focus_dc(c: Creature) -> int:
	return Rules.save_dc(c.mod(Rules.Ability.WIS), c.pb())


static func steady_aim(cb: Combat, c: Creature) -> bool:
	if not c.stats.has_feature("steady_aim") or c.once_per_turn.has("moved") or c.has_effect("steady_aim"):
		return false
	if not cb._use_bonus(c):
		return false
	c.add_effect("steady_aim", c, "end")
	c.movement_left = 0
	cb.log_msg("%s 정조준 (다음 공격에 이점, 이번 턴 이동 불가)" % c.display_name)
	cb.event.emit({"type": "condition", "creature": c})
	return true


## 로그 Sneak Attack 주사위 수 [SRD 표: 1~2레벨 1d6, 3~4레벨 2d6, 5레벨 3d6]
static func sneak_dice(level: int) -> int:
	return (level + 1) / 2


## 교활한 일격 내성 DC = 8 + DEX + PB
static func cunning_dc(c: Creature) -> int:
	return Rules.save_dc(c.mod(DEX), c.pb())


## Sneak Attack을 넣을 수 있는가: 턴에 한 번, Finesse나 원거리 무기, 이점이 있거나 대상 옆에 행동 가능한 아군(불리점 없이)
static func can_sneak(cb: Combat, c: Creature, t: Creature, w: WeaponData, adv: int) -> bool:
	if not c.stats.has_feature("sneak_attack") or c.once_per_turn.has("sneak") or w == null:
		return false
	if not (w.finesse or w.ranged):
		return false
	return adv > 0 or (adv == 0 and cb.ally_adjacent_to(c, t))


# =====================================================================
# 공격·피해·내성에 붙는 효과 (Combat이 부름)
# =====================================================================

## 근력으로 하는 공격인가 (원거리 무기가 아니고, 고른 능력치가 근력)
static func str_based(c: Creature, w: WeaponData, ability_mod: int) -> bool:
	return w != null and not w.ranged and w.ability < 0 and ability_mod == c.mod(STR)


## 공격 굴림의 이점·불리점 출처를 더함
## 공격 굴림 보너스 (숙련·능력치 말고): Archery +2, Sacred Weapon +CHA
static func attack_bonus(c: Creature, w: WeaponData, mode: String) -> int:
	var b := 0
	if w.ranged and c.stats.has_feature("archery"):
		b += 2
	if Spells.DMG.has(w.id):
		return b  # 주문 공격에는 무기 보너스가 붙지 않음
	if mode == "melee" and c.has_effect("sacred_weapon"):
		b += maxi(c.mod(Rules.Ability.CHA), 1)
	return b


static func attack_mods(c: Creature, t: Creature, w: WeaponData, ability_mod: int, adv: Array, _dis: Array) -> void:
	if c.has_effect("reckless") and str_based(c, w, ability_mod):
		adv.append("무모한 공격")
	if t.has_effect("reckless"):
		adv.append("대상이 무모함")
	if c.has_effect("steady_aim"):
		adv.append("정조준")
	if t.has_effect("exposed"):
		adv.append("기절 일격")
	if c.has_effect("innate_sorcery") and Spells.DMG.has(w.id):
		adv.append("Innate Sorcery")
	if t.has_effect("protected") and OTHERWORLDLY.has(c.stats.creature_type):
		_dis.append("Protection from Evil")


## 공격 굴림을 했을 때 (명중과 상관없이)
static func on_attack_roll(c: Creature) -> void:
	c.once_per_turn["attacked"] = true
	c.remove_effects("steady_aim")
	if c.has_effect("raging"):
		c.once_per_turn["rage_kept"] = true


## 명중한 무기 피해에 더하는 값 {amount, text}. 피해 주사위와 같은 종류로 들어감
static func bonus_damage(cb: Combat, c: Creature, t: Creature, w: WeaponData, info: Dictionary, crit: bool) -> Dictionary:
	var amount := 0
	var parts: Array[String] = []
	var trip := false
	if can_sneak(cb, c, t, w, info.adv):
		c.once_per_turn["sneak"] = true
		var n := sneak_dice(c.stats.level)
		if c.has_effect("cs_trip") and n > 1:
			n -= 1
			trip = true
			c.remove_effects("cs_trip")
		n *= 2 if crit else 1
		var rolls := cb.dice.roll(n, 6)
		amount += Dice.sum(rolls)
		parts.append("Sneak Attack %dd6%s" % [n, str(rolls)])
	if c.has_effect("raging") and str_based(c, w, info.ability_mod):
		var rd := rage_damage(c.stats.level)
		amount += rd
		parts.append("분노 +%d" % rd)
		if c.stats.has_feature("frenzy") and c.has_effect("reckless") and not c.once_per_turn.has("frenzy") and cb.current() == c:
			c.once_per_turn["frenzy"] = true
			var n := rd * (2 if crit else 1)
			var rolls := cb.dice.roll(n, 6)
			amount += Dice.sum(rolls)
			parts.append("Frenzy %dd6%s" % [n, str(rolls)])
	if c.stats.has_feature("colossus_slayer") and t.hp < t.stats.max_hp and not c.once_per_turn.has("colossus"):
		c.once_per_turn["colossus"] = true
		var n := 2 if crit else 1
		var rolls := cb.dice.roll(n, 8)
		amount += Dice.sum(rolls)
		parts.append("Colossus Slayer %dd8%s" % [n, str(rolls)])
	return {"amount": amount, "text": ", ".join(parts), "trip": trip, "crit": crit}


## 맞아서 피해를 받기 직전: Deflect Attacks(반응으로 줄임), Uncanny Dodge(반응으로 절반). [변경] 반응이 있으면 자동
static func on_hit_taken(cb: Combat, c: Creature, t: Creature, w: WeaponData, info: Dictionary, dmg: int) -> int:
	if dmg > 0 and t.stats.has_feature("deflect_attacks") and t.reaction_available and t.can_act() and PHYSICAL.has(w.damage_type):
		t.reaction_available = false
		var r := cb.dice.roll_die(10)
		var cut := r + t.mod(DEX) + t.stats.level
		var left := maxi(0, dmg - cut)
		cb.log_msg("  %s 공격 쳐내기! 1d10(%d) + %d → 피해 %d → %d" % [t.display_name, r, t.mod(DEX) + t.stats.level, dmg, left])
		if left == 0 and t.resources.get("focus", 0) > 0 and c.is_alive() \
				and cb.grid.distance(t.cell, c.cell) <= (1 if info.get("mode", "") == "melee" else 12):
			t.resources["focus"] -= 1
			var sv := cb.saving_throw(c, DEX, focus_dc(t))
			if sv.success:
				cb.log_msg("  되돌려 보냄 (Focus 1): %s → 피함" % sv.text)
			else:
				var ma := Catalog.martial_arts_die(t.stats.level)
				var back := Dice.sum(cb.dice.roll(2, ma)) + t.mod(DEX)
				cb.log_msg("  되돌려 보냄 (Focus 1): %s" % sv.text)
				cb._deal(c, back, w.damage_type, false, "되돌린 공격")
		return left
	if dmg > 0 and t.stats.has_feature("uncanny_dodge") and t.reaction_available and t.can_act():
		t.reaction_available = false
		cb.log_msg("  %s Uncanny Dodge! 피해 절반 (%d → %d)" % [t.display_name, dmg, dmg / 2])
		return dmg / 2
	return dmg


## 맞힌 뒤 대상이 아직 서 있을 때: 교활한 일격(넘어뜨리기), 열린 손 기술, 기절 일격
static func after_hit(cb: Combat, c: Creature, t: Creature, w: WeaponData, info: Dictionary, extra: Dictionary) -> void:
	var crit: bool = extra.get("crit", false)
	# Hunter's Mark / Hex: 표식한 적을 맞히면 1d6 (역장 / 사령)
	if not t.find_effect("marked").is_empty() and t.find_effect("marked").owner == c:
		var rolls := cb.dice.roll(2 if crit else 1, 6)
		var mt: String = Spells.MARKS.get(c.concentration, "force")
		cb._deal(t, Dice.sum(rolls), mt, crit, "%s %s" % [Spells.spell_name(c.concentration), str(rolls)])
		if not t.is_alive() or t.is_down():
			on_kill(cb, c, t)
			return
	# Divine Smite: 켜 두었고 근접 공격이 맞으면 보너스 행동과 슬롯(또는 무료 1회)을 씀
	if c.toggles.get("divine_smite", false) and info.get("mode", "") == "melee" and c.bonus_available:
		var free: bool = c.resources.get("free_smite", 0) > 0
		var slot := 1 if free else Spells.lowest_slot(c, 1)
		if slot > 0 and (free or not c.once_per_turn.has("slot")):
			c.bonus_available = false
			if free:
				c.resources["free_smite"] -= 1
			else:
				c.resources["slot%d" % slot] -= 1
				c.once_per_turn["slot"] = true
			var n := 2 + (slot - 1) + (1 if t.stats.creature_type in ["undead", "fiend"] else 0)
			n *= 2 if crit else 1
			var rolls := cb.dice.roll(n, 8)
			cb.log_msg("[color=#e8d27a]%s: Divine Smite%s[/color]" % [c.display_name, " (슬롯 없이)" if free else " (%d레벨 슬롯)" % slot])
			cb._deal(t, Dice.sum(rolls), "radiant", crit, "Divine Smite %dd8%s" % [n, str(rolls)])
			if not t.is_alive() or t.is_down():
				return
	if info.get("flurry", false) and c.stats.has_feature("open_hand_technique"):
		_open_hand(cb, c, t)
	if c.toggles.get("stun", false) and c.stats.has_feature("stunning_strike") and MONK_WEAPONS.has(w.id) \
			and not c.once_per_turn.has("stun") and c.resources.get("focus", 0) > 0 and t.is_alive() and not t.is_down():
		c.once_per_turn["stun"] = true
		c.resources["focus"] -= 1
		var sv := cb.saving_throw(t, CON, focus_dc(c))
		if sv.success:
			t.add_effect("staggered", c, "start")
			t.add_effect("exposed", c, "start")
			cb.log_msg("  기절 일격 (Focus 1): %s → 버팀 (속도 절반, 다음 공격에 이점)" % sv.text)
		else:
			t.add_effect("stunned", c, "start")
			cb.log_msg("  [color=orange]기절 일격 (Focus 1): %s → 기절![/color]" % sv.text)
		cb.event.emit({"type": "condition", "creature": t})
	if extra.get("trip", false) and t.stats.size <= Rules.Size.LARGE and not t.has_condition("prone"):
		var sv := cb.saving_throw(t, DEX, cunning_dc(c))
		if not sv.success and t.add_condition("prone"):
			cb.log_msg("  교활한 일격: %s → 넘어짐!" % sv.text)
			cb.event.emit({"type": "condition", "creature": t})
		else:
			cb.log_msg("  교활한 일격: %s → 버팀" % sv.text)


## 내성 굴림 이점(+1)·불리점(-1) 출처
static func save_adv(t: Creature, ability: int) -> int:
	if ability == STR and t.has_effect("raging"):
		return 1
	if ability == DEX and t.stats.has_feature("danger_sense") and not t.is_incapacitated():
		return 1
	return 0


## 이 피해 종류에 저항이 있는가 (스탯의 저항 말고 클래스 효과로)
static func resists(t: Creature, type: String) -> bool:
	return t.has_effect("raging") and PHYSICAL.has(type)


## 턴이 끝날 때: 이번 턴에 이어 가지 않은 분노는 풀림
static func on_turn_end(cb: Combat, c: Creature) -> void:
	if c.has_effect("raging") and not c.once_per_turn.has("rage_kept"):
		end_rage(cb, c)


## 턴을 시작할 때: Heroism 임시 HP
static func on_turn_start(cb: Combat, c: Creature) -> void:
	for e in c.effects:
		if e.type == "heroism":
			var thp := maxi((e.owner as Creature).spell_mod(), 1)
			if c.temp_hp < thp:
				c.temp_hp = thp
				cb.log_msg("%s Heroism: 임시 HP %d" % [c.display_name, thp])
				cb.event.emit({"type": "hp", "creature": c, "delta": 0, "hp": c.hp, "crit": false})


## 크리처가 쓰러졌을 때: 표식이 붙어 있었으면 레인저가 옮길 수 있게 됨
static func on_creature_down(cb: Combat, t: Creature) -> void:
	for x in cb.creatures:
		if x.concentration in Spells.MARKS and not t.find_effect("marked").is_empty() and t.find_effect("marked").owner == x:
			t.remove_effects_from(x, ["marked"])
			x.toggles["mark_free"] = true


## 맞을 공격을 Shield(1레벨 슬롯, 반응)로 막을 수 있으면 막음. [변경] 막을 수 있을 때 자동
static func try_shield(cb: Combat, t: Creature, total: int, target_ac: int) -> bool:
	if not t.stats.spells.has("shield") or not t.reaction_available or not t.can_act() or t.has_effect("raging"):
		return false
	if total >= target_ac + 5:
		return false
	var slot := Spells.lowest_slot(t, 1)
	if slot == 0:
		return false
	t.reaction_available = false
	t.resources["slot%d" % slot] -= 1
	t.add_effect("shield_spell", t, "start")
	cb.log_msg("[color=#e8d27a]%s: Shield! (반응, %d레벨 슬롯) AC +5[/color]" % [t.display_name, slot])
	cb.event.emit({"type": "condition", "creature": t})
	return true


## 드루이드 Wild Shape: 늑대 모습 스탯. HP·INT·WIS·CHA·숙련·클래스 기능은 그대로 [SRD]
static func beast_form(s: CreatureStats) -> CreatureStats:
	var wolf := Catalog.monster("wolf")
	var f: CreatureStats = s.duplicate()
	f.scores = s.scores.duplicate()
	for a in [Rules.Ability.STR, Rules.Ability.DEX, Rules.Ability.CON]:
		f.scores[a] = wolf.scores[a]
	f.ac = wolf.ac
	f.speed = wolf.speed
	f.size = wolf.size
	f.weapons = wolf.weapons
	f.model = wolf.model
	f.weapon_model = ""
	f.tint = Color.WHITE
	f.sprite_scale = wolf.sprite_scale
	f.initiative_bonus = f.ability_mod(Rules.Ability.DEX)
	f.spells = PackedStringArray()  # 변신 중에는 주문을 못 씀
	var feats := s.features.duplicate()
	feats.append("pack_tactics")
	f.features = feats
	return f


static func wild_shape(cb: Combat, c: Creature) -> void:
	var before := c.speed()
	c.true_stats = c.stats
	c.stats = beast_form(c.true_stats)
	c.movement_left = maxi(0, c.movement_left + c.speed() - before)
	c.temp_hp = maxi(c.temp_hp, c.true_stats.level)
	cb.log_msg("[color=#e8d27a]%s Wild Shape: 늑대로 변신! (임시 HP %d)[/color]" % [c.display_name, c.temp_hp])
	cb.event.emit({"type": "reshape", "creature": c})
	cb.event.emit({"type": "hp", "creature": c, "delta": 0, "hp": c.hp, "crit": false})


static func revert(cb: Combat, c: Creature) -> void:
	if c.true_stats == null:
		return
	var before := c.speed()
	c.stats = c.true_stats
	c.true_stats = null
	c.movement_left = maxi(0, c.movement_left + c.speed() - before)
	cb.log_msg("%s 본모습으로 돌아옴" % c.display_name)
	cb.event.emit({"type": "reshape", "creature": c})


## 바드의 영감 주사위 크기 (5레벨 d8) [SRD]
static func inspiration_die(bard: Creature) -> int:
	return 8 if bard != null and bard.stats.level >= 5 else 6


## 영감 주사위를 가진 c가 굴림에 실패했을 때: 주사위로 넘길 수 있으면 저절로 굴려 더함. 더한 값 (안 쓰면 0)
## [변경] 플레이어가 고르지 않고, 성공할 가능성이 있을 때만 씀
static func use_inspiration(cb: Combat, c: Creature, total: int, need: int) -> int:
	var e := c.find_effect("inspired")
	if e.is_empty():
		return 0
	var die := inspiration_die(e.owner)
	if total + die < need:
		return 0
	c.effects.erase(e)
	var r := cb.dice.roll_die(die)
	cb.log_msg("[color=#e8d27a]%s 영감 주사위 d%d → %d[/color]" % [c.display_name, die, r])
	cb.event.emit({"type": "condition", "creature": c})
	return r


## Cutting Words (로어 바드 3레벨, 반응): 적 c의 공격이 아군 t를 맞힐 때, 영감 주사위로 빗나가게 할 수 있으면 저절로 씀
## 빼는 값 (안 쓰면 0). [변경] 피해 굴림·능력 판정에는 쓰지 않음
static func cutting_words(cb: Combat, c: Creature, t: Creature, total: int, ac: int) -> int:
	for b in cb.creatures:
		if not b.stats.has_feature("cutting_words") or b.is_hostile_to(t) or not b.reaction_available or not b.can_act():
			continue
		if b.resources.get("bardic_inspiration", 0) <= 0 or cb.grid.distance(b.cell, c.cell) > 12:
			continue
		var die := inspiration_die(b)
		if total - die >= ac:
			continue
		b.reaction_available = false
		b.resources["bardic_inspiration"] -= 1
		var r := cb.dice.roll_die(die)
		cb.log_msg("[color=#e8d27a]%s: Cutting Words! (반응) d%d → −%d[/color]" % [b.display_name, die, r])
		return r
	return 0


## t가 c에게 맞고도 서 있을 때: 워락 Hellish Rebuke (반응, 자동) [변경: 슬롯이 있으면 늘 씀]
static func on_damaged(cb: Combat, c: Creature, t: Creature) -> void:
	if not t.stats.spells.has("hellish_rebuke") or not t.reaction_available or not t.can_act():
		return
	if c == null or not c.is_alive() or c.is_down() or not c.is_hostile_to(t):
		return
	if cb.grid.distance(t.cell, c.cell) > Spells.DATA.hellish_rebuke.range:
		return
	var slot := Spells.lowest_slot(t, 1)
	if slot == 0:
		return
	t.reaction_available = false
	t.resources["slot%d" % slot] -= 1
	cb.log_msg("[color=#e8d27a]%s: Hellish Rebuke! (반응, %d레벨 슬롯)[/color]" % [t.display_name, slot])
	Spells.damage_spell(cb, t, "hellish_rebuke", c, slot)


## c가 t를 쓰러뜨렸을 때: 워락 Dark One's Blessing (임시 HP = CHA + 레벨)
static func on_kill(cb: Combat, c: Creature, t: Creature) -> void:
	if c == null or not c.stats.has_feature("dark_ones_blessing") or not t.is_hostile_to(c):
		return
	var thp := maxi(1, c.mod(Rules.Ability.CHA) + c.stats.level)
	if thp > c.temp_hp:
		c.temp_hp = thp
		cb.log_msg("[color=#e8d27a]%s Dark One's Blessing: 임시 HP %d[/color]" % [c.display_name, thp])
		cb.event.emit({"type": "hp", "creature": c, "delta": 0, "hp": c.hp, "crit": false})
	pass


## 쓰러지거나 행동 불능이 되면 분노가 풀림
static func on_incapacitated(cb: Combat, c: Creature) -> void:
	if c.has_effect("raging"):
		end_rage(cb, c)
	if c.true_stats != null:
		revert(cb, c)


## 열린 손 기술 (연타가 맞았을 때)
static func _open_hand(cb: Combat, c: Creature, t: Creature) -> void:
	if not t.is_alive() or t.is_down():
		return
	match open_hand(c):
		"topple":
			if t.has_condition("prone"):
				return
			var sv := cb.saving_throw(t, DEX, focus_dc(c))
			if not sv.success and t.add_condition("prone"):
				cb.log_msg("  열린 손: %s → 넘어짐!" % sv.text)
				cb.event.emit({"type": "condition", "creature": t})
			else:
				cb.log_msg("  열린 손: %s → 버팀" % sv.text)
		"push":
			var sv := cb.saving_throw(t, STR, focus_dc(c))
			cb.log_msg("  열린 손: %s" % sv.text)
			if not sv.success:
				cb._push(c, t, 3)
		"addle":
			t.reaction_available = false
			cb.log_msg("  열린 손: %s 어지러움 (다음 턴까지 기회 공격 못 함)" % t.display_name)


## 이니셔티브를 굴린 뒤: Uncanny Metabolism (Focus를 썼거나 다쳤으면 자동으로 씀 [변경])
static func on_initiative(cb: Combat, c: Creature) -> void:
	if c.resources.get("metabolism", 0) <= 0:
		return
	var full_fp := c.stats.level
	if c.resources.get("focus", 0) >= full_fp and c.hp >= c.stats.max_hp:
		return
	c.resources["metabolism"] = 0
	c.resources["focus"] = full_fp
	var r := cb.dice.roll_die(Catalog.martial_arts_die(c.stats.level))
	var healed := Damage.heal(c, r + c.stats.level)
	cb.log_msg("%s Uncanny Metabolism: Focus 모두 회복, HP +%d" % [c.display_name, healed])
	cb.event.emit({"type": "hp", "creature": c, "delta": healed, "hp": c.hp, "crit": false})


static func end_rage(cb: Combat, c: Creature) -> void:
	c.remove_effects("raging")
	cb.log_msg("%s의 분노가 가라앉음" % c.display_name)
	cb.event.emit({"type": "condition", "creature": c})
