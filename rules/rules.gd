## 공통 규칙 상수와 계산식 (docs/rules.md 1장)
class_name Rules
extends RefCounted

enum Ability { STR, DEX, CON, INT, WIS, CHA }
enum Size { TINY, SMALL, MEDIUM, LARGE, HUGE, GARGANTUAN }

const ABILITY_NAMES := ["STR", "DEX", "CON", "INT", "WIS", "CHA"]
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
