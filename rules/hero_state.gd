## 던전 탐험 동안 전투와 전투 사이에 이어지는 파이터 상태 (HP, 사용 횟수, XP).
## 전투 장면은 이걸로 PC를 만들고, 끝나면 결과를 다시 담습니다.
class_name HeroState
extends RefCounted

const NAME := "파이터"
## v1 파이터는 5레벨까지 (rules 1)
const MAX_LEVEL := 5

var xp := 0
## -1이면 최대 HP
var hp := -1
## second_wind, action_surge, potion. 비어 있으면 처음 상태
var resources := {}
## 쓴 히트 다이스 수. 남은 수 = 레벨 - 이것 (rules 5.3)
var hit_dice_spent := 0


static func fresh() -> HeroState:
	var h := HeroState.new()
	h.resources = {"potion": 1}
	return h


func level() -> int:
	return mini(Rules.level_for_xp(xp), MAX_LEVEL)


func max_hp() -> int:
	return Catalog.fighter(level()).max_hp


func current_hp() -> int:
	return max_hp() if hp < 0 else hp


func duplicate_state() -> HeroState:
	var h := HeroState.new()
	h.xp = xp
	h.hp = hp
	h.resources = resources.duplicate()
	h.hit_dice_spent = hit_dice_spent
	return h


## 이 상태로 전투용 PC를 만듦
func make_creature() -> Creature:
	var c := Creature.new(Catalog.fighter(level()), 0, NAME)
	for k in resources:
		c.resources[k] = resources[k]
	if hp >= 0:
		c.hp = clampi(hp, 1, c.stats.max_hp)
	return c


## 전투가 끝났거나 도망쳤을 때 PC 상태를 담고 XP를 더함. 레벨이 오르면 {"level_up": 새 레벨}
func absorb(c: Creature, xp_gain := 0) -> Dictionary:
	var before := Catalog.fighter(level())
	hp = maxi(c.hp, 1)  # 이겼는데 쓰러져 있었으면 1로 일어남
	resources = {}
	for k in ["second_wind", "action_surge", "potion"]:
		if c.resources.has(k):
			resources[k] = c.resources[k]
	xp += xp_gain
	var after := Catalog.fighter(level())
	if after.level <= before.level:
		return {}
	# 레벨업: 늘어난 최대 HP만큼 회복하고, 새로 생기거나 늘어난 사용 횟수를 더함
	hp += after.max_hp - before.max_hp
	var probe_old := Creature.new(before, 0)
	var probe_new := Creature.new(after, 0)
	for k in ["second_wind", "action_surge"]:
		var gain: int = probe_new.resources.get(k, 0) - probe_old.resources.get(k, 0)
		if gain > 0:
			resources[k] = resources.get(k, 0) + gain
	return {"level_up": after.level}


# --- 휴식 (rules 5.3) ---

func hit_die() -> int:
	return Catalog.fighter(level()).hit_die


func hit_dice_left() -> int:
	return maxi(level() - hit_dice_spent, 0)


func con_mod() -> int:
	return Rules.ability_mod(Catalog.fighter(level()).scores[Catalog.CON])


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


## 짧은 휴식을 마칠 때: Second Wind 1회, Action Surge 전부 [SRD]
func finish_short_rest() -> void:
	var fresh_c := Creature.new(Catalog.fighter(level()), 0)
	if fresh_c.resources.has("second_wind"):
		resources["second_wind"] = mini(resources.get("second_wind", fresh_c.resources.second_wind) + 1, fresh_c.resources.second_wind)
	if fresh_c.resources.has("action_surge"):
		resources["action_surge"] = fresh_c.resources.action_surge


## 긴 휴식: HP, 히트 다이스, 기능 사용 횟수 전부 (물약은 그대로)
func long_rest() -> void:
	hp = -1
	hit_dice_spent = 0
	var potion: int = resources.get("potion", 0)
	resources = {"potion": potion}
