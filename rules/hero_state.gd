## 던전 탐험 동안 전투와 전투 사이에 이어지는 파티원 한 명의 상태 (HP, 사용 횟수, XP).
## 전투 장면은 이걸로 PC를 만들고, 끝나면 결과를 다시 담습니다. cls: Catalog.CLASSES 중 하나
class_name HeroState
extends RefCounted

const NAMES := {"fighter": "파이터", "cleric": "클레릭", "barbarian": "바바리안", "rogue": "로그", "monk": "몽크",
	"paladin": "팔라딘", "ranger": "레인저", "wizard": "위저드", "sorcerer": "소서러", "warlock": "워락",
	"bard": "바드", "druid": "드루이드"}
## 새로 시작할 때의 파티 (주인공, 동료). 던전 생성기와 시나리오 고르기 창에서 바꿈
static var party_classes: Array = ["fighter", "cleric"]
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
## 줄어든 최대 HP (스펙터 Life Drain). 긴 휴식으로 돌아옴 [SRD]
var max_hp_loss := 0
## 레벨업 때 고른 것 {레벨: {"asi": {능력치: 증가}, "spell": id}} (LevelUp, rules 7.17)
var choices := {}


## 물약은 주인공(파티 첫 번째)이 들고 시작 [변경: rules 7.1]. lead를 주지 않으면 파이터만
static func fresh(c := "fighter", lead := -1) -> HeroState:
	var h := HeroState.new()
	h.cls = c
	var holds := (c == "fighter") if lead < 0 else lead > 0
	h.resources = {"potion": 1} if holds else {}
	return h


func display_name() -> String:
	return NAMES.get(cls, cls)


func stats() -> CreatureStats:
	var s := Catalog.pc(cls, level(), choices)
	s.max_hp = maxi(1, s.max_hp - max_hp_loss)
	return s


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
	h.max_hp_loss = max_hp_loss
	h.choices = choices.duplicate(true)
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
	max_hp_loss += c.max_hp_loss
	var before := stats()
	hp = clampi(c.hp, 1, before.max_hp)  # 이겼는데 쓰러져(또는 죽어) 있었으면 1로 일어남 [변경]. Aid로 늘어난 HP는 사라짐
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


# --- 레벨업 고르기 (rules 7.17) ---

## 아직 고르지 않은 레벨들 (LevelUp.pending)
func pending_choices() -> Array:
	return LevelUp.pending(cls, level(), choices)


## level에 고른 것을 남김 (key: "asi" 또는 "spell"). 최대 HP가 바뀌면 지금 HP도 그만큼
func choose(level: int, key: String, value: Variant) -> void:
	var before := max_hp()
	var c: Dictionary = choices.get(level, {})
	c[key] = value
	choices[level] = c
	var after := max_hp()
	if hp >= 0:
		hp = clampi(hp + after - before, 1, after)


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


## 짧은 휴식을 마칠 때: Second Wind 1회, Action Surge 전부, Channel Divinity 1회, Rage 1회 ... [SRD]
## (ClassFeatures.SHORT_REST). 주문 슬롯은 안 돌아옴
func finish_short_rest() -> void:
	var full := Creature.new(stats(), 0).resources
	resources = ClassFeatures.after_short_rest(resources, full)
	resources = ClassFeatures.short_rest_extra(level(), stats().features, resources, full)


## 긴 휴식: HP, 히트 다이스, 기능 사용 횟수, 주문 슬롯 전부 (물약은 그대로)
func long_rest() -> void:
	hp = -1
	hit_dice_spent = 0
	max_hp_loss = 0
	resources = {"potion": resources.potion} if resources.has("potion") else {}
