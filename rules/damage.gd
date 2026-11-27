## 피해, 회복, 사망 내성 (docs/rules.md 4.2, 5장)
class_name Damage
extends RefCounted


## 피해 종류 이름
const TYPE_NAMES := {"slashing": "참격", "piercing": "관통", "bludgeoning": "타격", "fire": "화염", "cold": "냉기",
	"lightning": "번개", "thunder": "천둥", "force": "역장", "radiant": "광휘", "necrotic": "사령", "psychic": "정신",
	"poison": "독", "acid": "산"}


## 면역 → 저항(절반, 내림) → 취약(2배) 순서로 적용
static func modify(target: Creature, amount: int, type: String) -> int:
	if target.stats.immunities.has(type):
		return 0
	var a := maxi(0, amount)
	if target.stats.resistances.has(type) or ClassFeatures.resists(target, type):
		a = floori(a / 2.0)
	if target.stats.vulnerabilities.has(type):
		a *= 2
	return a


## 반환: {"dealt": 실제 피해, "killed": bool, "downed": bool, "death_fail": int}
static func apply(target: Creature, amount: int, type: String, is_crit := false) -> Dictionary:
	var res := {"dealt": 0, "killed": false, "downed": false, "death_fail": 0}
	if not target.is_alive():
		return res
	var dmg := modify(target, amount, type)
	res.dealt = dmg
	if dmg <= 0:
		return res

	# 임시 HP가 먼저 흡수
	if target.temp_hp > 0:
		var absorbed := mini(target.temp_hp, dmg)
		target.temp_hp -= absorbed
		dmg -= absorbed
		if dmg == 0:
			return res

	# 이미 HP 0인 PC
	if target.hp == 0:
		if dmg >= target.stats.max_hp:
			_kill(target)
			res.killed = true
			return res
		target.stable = false
		var fails := 2 if is_crit else 1
		target.death_failures += fails
		res.death_fail = fails
		if target.death_failures >= 3:
			_kill(target)
			res.killed = true
		return res

	target.hp -= dmg
	if target.hp <= 0:
		var overflow := -target.hp
		target.hp = 0
		if not target.stats.is_pc or overflow >= target.stats.max_hp:
			_kill(target)
			res.killed = true
		else:
			target.add_condition("unconscious")
			target.add_condition("prone")
			target.stable = false
			target.death_successes = 0
			target.death_failures = 0
			res.downed = true
	return res


static func heal(target: Creature, amount: int) -> int:
	if not target.is_alive() or amount <= 0 or target.has_effect("no_heal"):
		return 0
	var before := target.hp
	target.hp = mini(target.stats.max_hp, target.hp + amount)
	if before == 0 and target.hp > 0:
		target.remove_condition("unconscious")  # 넘어짐은 남습니다
		target.stable = false
		target.death_successes = 0
		target.death_failures = 0
	return target.hp - before


## 반환: {"roll": int, "result": "success"/"fail"/"stable"/"dead"/"revived"}
## bonus: Bless 같은 내성 보너스 (1과 20 판정에는 영향 없음)
static func death_save(target: Creature, dice: Dice, bonus := 0) -> Dictionary:
	var r := dice.roll_die(20)
	var result := ""
	if r == 20:
		heal(target, 1)
		return {"roll": r, "result": "revived"}
	elif r == 1:
		target.death_failures += 2
		result = "fail"
	elif r + bonus >= 10:
		target.death_successes += 1
		result = "success"
	else:
		target.death_failures += 1
		result = "fail"
	if target.death_failures >= 3:
		_kill(target)
		result = "dead"
	elif target.death_successes >= 3:
		target.stable = true
		target.death_successes = 0
		target.death_failures = 0
		result = "stable"
	return {"roll": r, "result": result}


static func _kill(target: Creature) -> void:
	target.dead = true
	target.hp = 0
