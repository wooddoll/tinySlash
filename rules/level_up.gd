## 레벨업 때 고르는 것 (docs/rules.md 7.17)
##  - 4레벨: 능력치 향상(ASI). 한 능력치 +2 또는 두 능력치 +1 (최대 20) [SRD: Ability Score Improvement 재주]
##  - 2~5레벨: 클래스 주문 목록에서 주문 하나 더 [변경: SRD의 준비 주문 늘어남을 "하나 고르기"로]
## 고르기는 HeroState.choices에 {레벨: {"asi": {능력치: 증가}, "spell": id}}로 남고,
## 고르지 않은 것은 기본값(ASI는 주 능력치 +2, 주문은 없음)으로 칩니다.
class_name LevelUp
extends RefCounted

const STR := Rules.Ability.STR
const DEX := Rules.Ability.DEX
const CON := Rules.Ability.CON
const INT := Rules.Ability.INT
const WIS := Rules.Ability.WIS
const CHA := Rules.Ability.CHA

const ASI_LEVEL := 4
const MAX_SCORE := 20

## 고르지 않았을 때의 능력치 향상 (예전 고정 구성과 같음)
const DEFAULT_ASI := {
	"fighter": {STR: 2}, "cleric": {WIS: 2}, "barbarian": {STR: 2}, "rogue": {DEX: 2}, "monk": {DEX: 2},
	"paladin": {CHA: 2}, "ranger": {DEX: 2}, "wizard": {INT: 2}, "sorcerer": {CHA: 2}, "warlock": {CHA: 2},
	"bard": {CHA: 2}, "druid": {WIS: 2},
}

## 클래스 주문 목록 중 이 게임에 있는 것 [SRD spells.md의 클래스 표기]
const SPELL_LISTS := {
	"cleric": ["sacred_flame", "spare_the_dying", "guiding_bolt", "cure_wounds", "healing_word", "bless",
		"shield_of_faith", "protection_from_evil", "aid", "spiritual_weapon", "spirit_guardians", "mass_healing_word"],
	"paladin": ["cure_wounds", "bless", "shield_of_faith", "heroism", "protection_from_evil", "aid"],
	"ranger": ["cure_wounds", "hunters_mark", "aid"],
	"wizard": ["fire_bolt", "ray_of_frost", "shocking_grasp", "chill_touch", "magic_missile", "burning_hands",
		"thunderwave", "shield", "chromatic_orb", "protection_from_evil", "scorching_ray", "shatter", "fireball"],
	"sorcerer": ["fire_bolt", "ray_of_frost", "shocking_grasp", "chill_touch", "magic_missile", "burning_hands",
		"thunderwave", "shield", "chromatic_orb", "scorching_ray", "shatter", "fireball"],
	"warlock": ["eldritch_blast", "chill_touch", "hex", "hellish_rebuke", "protection_from_evil"],
	"bard": ["vicious_mockery", "starry_wisp", "dissonant_whispers", "healing_word", "cure_wounds", "faerie_fire",
		"thunderwave", "heroism", "aid", "shatter", "mass_healing_word"],
	"druid": ["starry_wisp", "spare_the_dying", "cure_wounds", "healing_word", "faerie_fire", "thunderwave",
		"protection_from_evil", "aid"],
}


## 빌더가 만든 스탯(s)에 고른 것을 더함
static func apply(s: CreatureStats, cls: String, choices: Dictionary) -> void:
	if s.level >= ASI_LEVEL:
		apply_asi(s, asi_of(cls, choices))
	var sp := s.spells
	for l in choices:
		var id: String = (choices[l] as Dictionary).get("spell", "")
		if int(l) <= s.level and id != "" and not sp.has(id):
			sp.append(id)
	s.spells = sp


static func asi_of(cls: String, choices: Dictionary) -> Dictionary:
	return (choices.get(ASI_LEVEL, {}) as Dictionary).get("asi", DEFAULT_ASI.get(cls, {}))


## 능력치를 올리고, 그 능력치에 기대는 AC(ac_abilities), 최대 HP(CON × 레벨), 이니셔티브(DEX)를 맞춤
static func apply_asi(s: CreatureStats, asi: Dictionary) -> void:
	var old := s.scores.duplicate()
	var sc := s.scores
	for a in asi:
		sc[int(a)] = mini(MAX_SCORE, sc[int(a)] + int(asi[a]))
	s.scores = sc
	for m in s.ac_abilities:
		var cap: int = m[1] if (m as Array).size() > 1 else 99
		s.ac += mini(Rules.ability_mod(sc[m[0]]), cap) - mini(Rules.ability_mod(old[m[0]]), cap)
	s.max_hp += (Rules.ability_mod(sc[CON]) - Rules.ability_mod(old[CON])) * s.level
	s.initiative_bonus += Rules.ability_mod(sc[DEX]) - Rules.ability_mod(old[DEX])


## ASI가 맞는지: 합이 2이고, 하나에 +2 또는 둘에 +1, 20을 넘지 않음
static func valid_asi(scores: PackedInt32Array, asi: Dictionary) -> bool:
	var total := 0
	for a in asi:
		var n := int(asi[a])
		if n < 1 or n > 2 or scores[int(a)] + n > MAX_SCORE:
			return false
		total += n
	return total == 2


## level에 쓸 수 있는 가장 높은 슬롯 레벨
static func max_spell_level(cls: String, level: int) -> int:
	var slots := Catalog.build(cls, level).spell_slots
	for i in range(slots.size() - 1, -1, -1):
		if slots[i] > 0:
			return i + 1
	return 0


## level에서 고를 수 있는 주문: 클래스 목록 중, 빌더가 언젠가 주는 것과 다른 레벨에서 이미 고른 것은 빼고, 쓸 수 있는 레벨까지
static func spell_pool(cls: String, level: int, choices: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if level < 2 or not SPELL_LISTS.has(cls):
		return out
	var fixed := Catalog.build(cls, HeroState.MAX_LEVEL).spells
	var taken := {}
	for l in choices:
		if int(l) != level:
			taken[(choices[l] as Dictionary).get("spell", "")] = true
	var top := max_spell_level(cls, level)
	for id in SPELL_LISTS[cls]:
		if not fixed.has(id) and not taken.has(id) and int(Spells.DATA[id].level) <= top:
			out.append(id)
	return out


## 아직 고르지 않은 것이 남은 레벨들 (2..level). 각 {"level", "asi": bool, "spell": bool}
static func pending(cls: String, level: int, choices: Dictionary) -> Array:
	var out := []
	for l in range(2, level + 1):
		var c: Dictionary = choices.get(l, {})
		var need_asi := l == ASI_LEVEL and not c.has("asi")
		var need_spell := not c.has("spell") and not spell_pool(cls, l, choices).is_empty()
		if need_asi or need_spell:
			out.append({"level": l, "asi": need_asi, "spell": need_spell})
	return out
