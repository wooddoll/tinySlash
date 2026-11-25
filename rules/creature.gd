## 전투 중인 크리처의 현재 상태 (HP, 상태, 턴 자원)
class_name Creature
extends RefCounted

const STR := Rules.Ability.STR
const DEX := Rules.Ability.DEX

var stats: CreatureStats
var display_name := ""
## 0 = 플레이어 편, 1 = 적
var team := 0
var cell := Vector2i.ZERO
var facing := Vector2i(0, 1)
var hp := 0
var temp_hp := 0
var dead := false
var fled := false
var stable := false
var death_successes := 0
var death_failures := 0
var initiative := 0
## "prone", "unconscious", "incapacitated" ...
var conditions := {}
## 일시 효과: {"type", "owner", "phase", "skip", "target"}
## owner의 턴 시작/끝(phase)에 skip이 0이면 사라집니다.
var effects: Array[Dictionary] = []
## 사용 횟수가 있는 자원: second_wind, action_surge, potion, slot1~slot3, channel
var resources := {}
## 집중 중인 주문 id (없으면 빈 문자열)
var concentration := ""

# 턴 자원
var movement_left := 0
var action_available := true
var bonus_available := true
var reaction_available := true
var attacks_left := 0
var disengaged := false
var action_surge_used := false
var once_per_turn := {}


func _init(s: CreatureStats, team_id: int, name_override := "") -> void:
	stats = s
	team = team_id
	display_name = name_override if name_override != "" else s.display_name
	hp = s.max_hp
	if s.has_feature("second_wind"):
		resources["second_wind"] = second_wind_max()
	if s.has_feature("action_surge"):
		resources["action_surge"] = 1
	for i in s.spell_slots.size():
		if s.spell_slots[i] > 0:
			resources["slot%d" % (i + 1)] = s.spell_slots[i]
	if s.channel_divinity > 0:
		resources["channel"] = s.channel_divinity


# --- 능력치 ---

func mod(a: int) -> int:
	return stats.ability_mod(a)


func pb() -> int:
	return stats.proficiency_bonus()


func ac() -> int:
	return stats.ac + (2 if has_effect("shield_of_faith") else 0)


## 주문 내성 DC와 주문 공격 보너스 (rules 7.5)
func spell_mod() -> int:
	return mod(stats.spell_ability) if stats.spell_ability >= 0 else 0


func spell_dc() -> int:
	return Rules.save_dc(spell_mod(), pb())


func spell_attack_bonus() -> int:
	return spell_mod() + pb()


func speed() -> int:
	if has_condition("unconscious"):
		return 0
	var s := stats.speed
	if has_effect("slowed"):
		s -= 2
	return maxi(0, s)


func save_bonus(a: int) -> int:
	return mod(a) + (pb() if stats.save_proficiencies.has(a) else 0)


func crit_threshold() -> int:
	return 19 if stats.has_feature("improved_critical") else 20


func attacks_per_action() -> int:
	if stats.has_feature("extra_attack"):
		return 2
	return stats.multiattack


func second_wind_max() -> int:
	return 3 if stats.level >= 4 else 2


func can_use_mastery(w: WeaponData) -> bool:
	return w != null and w.mastery != "" and stats.weapon_masteries.has(w.id)


func melee_weapon() -> WeaponData:
	for w in stats.weapons:
		if not w.ranged:
			return w
	return null


func ranged_weapon() -> WeaponData:
	for w in stats.weapons:
		if w.ranged:
			return w
	for w in stats.weapons:
		if w.thrown:
			return w
	return null


func melee_reach() -> int:
	var w := melee_weapon()
	return w.melee_reach() if w else 1


# --- 상태 ---

func is_alive() -> bool:
	return not dead and not fled


func is_down() -> bool:
	return is_alive() and hp == 0


func is_bloodied() -> bool:
	return hp * 2 <= stats.max_hp


func is_incapacitated() -> bool:
	return has_condition("incapacitated") or has_condition("unconscious") or has_effect("turned")


func can_act() -> bool:
	return is_alive() and not is_incapacitated()


func is_hostile_to(other: Creature) -> bool:
	return team != other.team


func has_condition(c: String) -> bool:
	return conditions.has(c)


func add_condition(c: String) -> bool:
	if stats.condition_immunities.has(c):
		return false
	conditions[c] = true
	return true


func remove_condition(c: String) -> void:
	conditions.erase(c)


# --- 일시 효과 ---

func add_effect(type: String, owner: Creature, phase: String, skip := 0, target: Creature = null) -> void:
	effects.append({"type": type, "owner": owner, "phase": phase, "skip": skip, "target": target})


func has_effect(type: String) -> bool:
	for e in effects:
		if e.type == type:
			return true
	return false


## target을 지정하면 그 대상에 대한 효과만 찾습니다.
func find_effect(type: String, target: Creature = null) -> Dictionary:
	for e in effects:
		if e.type == type and (target == null or e.target == target):
			return e
	return {}


func remove_effects(type: String) -> void:
	for i in range(effects.size() - 1, -1, -1):
		if effects[i].type == type:
			effects.remove_at(i)


## owner가 건 types 효과를 지움. 지운 게 있으면 true
func remove_effects_from(owner: Creature, types: Array) -> bool:
	var removed := false
	for i in range(effects.size() - 1, -1, -1):
		if effects[i].owner == owner and types.has(effects[i].type):
			effects.remove_at(i)
			removed = true
	return removed


## owner의 턴 시작("start") 또는 끝("end")에 호출됩니다.
func process_phase(owner: Creature, phase: String) -> void:
	for i in range(effects.size() - 1, -1, -1):
		var e := effects[i]
		if e.owner != owner or e.phase != phase:
			continue
		if e.skip > 0:
			e.skip -= 1
		else:
			effects.remove_at(i)


func start_turn_reset() -> void:
	movement_left = speed()
	action_available = true
	bonus_available = true
	reaction_available = true
	attacks_left = 0
	disengaged = false
	action_surge_used = false
	once_per_turn.clear()
