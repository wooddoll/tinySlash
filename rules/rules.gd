## 공통 규칙 상수와 계산식 (docs/rules.md 1장)
class_name Rules
extends RefCounted

enum Ability { STR, DEX, CON, INT, WIS, CHA }
enum Size { TINY, SMALL, MEDIUM, LARGE, HUGE, GARGANTUAN }

const ABILITY_NAMES := ["STR", "DEX", "CON", "INT", "WIS", "CHA"]
## 기술 → 능력치 (rules 시나리오 판정)
const SKILLS := {
	"athletics": Ability.STR, "acrobatics": Ability.DEX, "sleight_of_hand": Ability.DEX, "stealth": Ability.DEX,
	"arcana": Ability.INT, "history": Ability.INT, "investigation": Ability.INT, "religion": Ability.INT,
	"insight": Ability.WIS, "medicine": Ability.WIS, "perception": Ability.WIS, "survival": Ability.WIS,
	"intimidation": Ability.CHA, "persuasion": Ability.CHA, "deception": Ability.CHA,
}
const SKILL_NAMES := {
	"athletics": "운동", "acrobatics": "곡예", "sleight_of_hand": "손재주", "stealth": "은신",
	"arcana": "비전", "history": "역사", "investigation": "조사", "religion": "종교",
	"insight": "통찰", "medicine": "의학", "perception": "지각", "survival": "생존",
	"intimidation": "위협", "persuasion": "설득", "deception": "기만",
	"str": "근력", "dex": "민첩", "con": "건강", "int": "지능", "wis": "지혜", "cha": "매력",
}
## 레벨별 필요 XP (인덱스 = 레벨 - 1)
const XP_THRESHOLDS := [0, 300, 900, 2700, 6500, 14000]


## 수정치 = (능력치 - 10) / 2, 내림
static func ability_mod(score: int) -> int:
	return floori((score - 10) / 2.0)


## 숙련 보너스. 몬스터는 CR을 넣습니다 (CR 1/8 등은 1로 취급).
static func proficiency_bonus(level_or_cr: float) -> int:
	var l := maxi(1, ceili(level_or_cr))
	return 2 + floori((l - 1) / 4.0)


## 이점(1) / 불리점(-1) / 없음(0). 둘 다 있으면 상쇄됩니다.
static func combine_advantage(adv: Array, dis: Array) -> int:
	if not adv.is_empty() and not dis.is_empty():
		return 0
	if not adv.is_empty():
		return 1
	if not dis.is_empty():
		return -1
	return 0


static func save_dc(ability_modifier: int, pb: int) -> int:
	return 8 + ability_modifier + pb


static func level_for_xp(xp: int) -> int:
	var level := 1
	for i in XP_THRESHOLDS.size():
		if xp >= XP_THRESHOLDS[i]:
			level = i + 1
	return level
