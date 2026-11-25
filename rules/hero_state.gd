## 던전 탐험 동안 전투와 전투 사이에 이어지는 파티원 한 명의 상태 (HP, 사용 횟수, XP).
## 전투 장면은 이걸로 PC를 만들고, 끝나면 결과를 다시 담습니다. cls: "fighter" 또는 "cleric"
class_name HeroState
extends RefCounted

const NAMES := {"fighter": "파이터", "cleric": "클레릭"}
## v1 파이터는 5레벨까지 (rules 1)
const MAX_LEVEL := 5
## 회복 물약 값 [SRD: Potion of Healing 50 GP]과 들고 다닐 수 있는 수 [변경]
const POTION_PRICE := 50
const MAX_POTIONS := 5

var cls := "fighter"
var xp := 0
## -1이면 최대 HP
var hp := -1
## second_wind, action_surge, potion, slot1~3, channel. 없는 키는 처음 상태
var resources := {}
## 쓴 히트 다이스 수. 남은 수 = 레벨 - 이것 (rules 5.3)
var hit_dice_spent := 0


## 물약은 파이터가 들고 시작 [변경: rules 7.1]
static func fresh(c := "fighter") -> HeroState:
	var h := HeroState.new()
	h.cls = c
	h.resources = {"potion": 1} if c == "fighter" else {}
	return h


func display_name() -> String:
	return NAMES.get(cls, cls)


func stats() -> CreatureStats:
	return Catalog.pc(cls, level())


func level() -> int:
	return mini(Rules.level_for_xp(xp), MAX_LEVEL)


func max_hp() -> int:
	return stats().max_hp


func current_hp() -> int:
	return max_hp() if hp < 0 else hp


func duplicate_state() -> HeroState:
	var h := HeroState.new()
	h.cls = cls
	h.xp = xp
	h.hp = hp
	h.resources = resources.duplicate()
	h.hit_dice_spent = hit_dice_spent
	return h


## 이 상태로 전투용 PC를 만듦
func make_creature() -> Creature:
	var c := Creature.new(stats(), 0, display_name())
	for k in resources:
		c.resources[k] = resources[k]
	if hp >= 0:
		c.hp = clampi(hp, 1, c.stats.max_hp)
	return c


## 전투가 끝났거나 도망쳤을 때 PC 상태를 담고 XP를 더함. 레벨이 오르면 {"level_up": 새 레벨}
func absorb(c: Creature, xp_gain := 0) -> Dictionary:
	var before := stats()
	hp = maxi(c.hp, 1)  # 이겼는데 쓰러져(또는 죽어) 있었으면 1로 일어남 [변경]
	resources = c.resources.duplicate()
	xp += xp_gain
	var after := stats()
	if after.level <= before.level:
		return {}
	# 레벨업: 늘어난 최대 HP만큼 회복하고, 새로 생기거나 늘어난 사용 횟수를 더함
	hp += after.max_hp - before.max_hp
	var probe_old := Creature.new(before, 0)
	var probe_new := Creature.new(after, 0)
	for k in probe_new.resources:
		var gain: int = probe_new.resources.get(k, 0) - probe_old.resources.get(k, 0)
		if gain > 0:
			resources[k] = resources.get(k, 0) + gain
	return {"level_up": after.level}


# --- 상점 ---

func potions() -> int:
	return resources.get("potion", 0)


func can_buy_potion(gold: int) -> bool:
	return gold >= POTION_PRICE and potions() < MAX_POTIONS


## 물약 하나를 사고 남은 금화를 돌려줌. 못 사면 금화 그대로
func buy_potion(gold: int) -> int:
	if not can_buy_potion(gold):
		return gold
	resources["potion"] = potions() + 1
	return gold - POTION_PRICE


# --- 휴식 (rules 5.3) ---

func hit_die() -> int:
	return stats().hit_die


func hit_dice_left() -> int:
	return maxi(level() - hit_dice_spent, 0)


func con_mod() -> int:
	return Rules.ability_mod(stats().scores[Catalog.CON])


## 짧은 휴식 중 히트 다이스 1개: 굴림 + CON (최소 1)만큼 회복. 못 쓰면 빈 사전
func spend_hit_die(dice: Dice) -> Dictionary:
	if hit_dice_left() <= 0 or current_hp() >= max_hp():
		return {}
	var roll := dice.roll_die(hit_die())
	var heal := maxi(roll + con_mod(), 1)
	var before := current_hp()
	hp = mini(before + heal, max_hp())
	hit_dice_spent += 1
	return {"roll": roll, "heal": hp - before}


## 짧은 휴식을 마칠 때: Second Wind 1회, Action Surge 전부, Channel Divinity 1회 [SRD]. 주문 슬롯은 안 돌아옴
func finish_short_rest() -> void:
	var fresh_c := Creature.new(stats(), 0)
	if fresh_c.resources.has("second_wind"):
		resources["second_wind"] = mini(resources.get("second_wind", fresh_c.resources.second_wind) + 1, fresh_c.resources.second_wind)
	if fresh_c.resources.has("action_surge"):
		resources["action_surge"] = fresh_c.resources.action_surge
	if fresh_c.resources.has("channel"):
		resources["channel"] = mini(resources.get("channel", fresh_c.resources.channel) + 1, fresh_c.resources.channel)


## 긴 휴식: HP, 히트 다이스, 기능 사용 횟수, 주문 슬롯 전부 (물약은 그대로)
func long_rest() -> void:
	hp = -1
	hit_dice_spent = 0
	resources = {"potion": resources.potion} if resources.has("potion") else {}
