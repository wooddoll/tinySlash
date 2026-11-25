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
