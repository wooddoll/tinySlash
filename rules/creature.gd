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
## Wild Shape 중이면 본래 스탯 (아니면 null)
var true_stats: CreatureStats = null
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
## 사용 횟수가 있는 자원: second_wind, action_surge, potion, slot1~slot3, channel, rage ... (ClassFeatures)
var resources := {}
## 집중 중인 주문 id (없으면 빈 문자열)
var concentration := ""
## 집중 중인 주문을 쓴 슬롯 레벨 (Spiritual Weapon, Spirit Guardians 피해에 씀)
var conc_slot := 0
## Spiritual Weapon이 떠 있는 칸 (없으면 -1, -1)
var spirit_cell := Vector2i(-1, -1)
## Aid로 늘어난 최대 HP (전투가 끝나면 사라짐)
var aid_bonus := 0
## Spirit Guardians 내성을 마지막으로 굴린 턴 (턴마다 한 번만)
var guardian_turn := -1
## Shadow의 근력 흡수로 줄어든 근력 (전투가 끝나면 돌아옴 [변경: SRD는 휴식까지])
var str_loss := 0
## 이 전투에서 줄어든 최대 HP (스펙터 Life Drain). stats.max_hp에 이미 반영됨
var max_hp_loss := 0

# 턴 자원
var movement_left := 0
var action_available := true
var bonus_available := true
var reaction_available := true
var attacks_left := 0
var disengaged := false
var action_surge_used := false
var once_per_turn := {}
## 보너스 행동으로 얻은 맨손 타격 횟수 (몽크 Martial Arts, Flurry of Blows)
var bonus_attacks := 0
## 켜 두는 선택 (몽크 열린 손 기술 종류, Flurry 중인지 ...)
var toggles := {}


func _init(s: CreatureStats, team_id: int, name_override := "") -> void:
	stats = s
	team = team_id
	display_name = name_override if name_override != "" else s.display_name
	hp = s.max_hp
	ClassFeatures.init_resources(self)


# --- 능력치 ---

func mod(a: int) -> int:
	if a == STR and str_loss > 0:
		return Rules.ability_mod(stats.scores[STR] - str_loss)
	return stats.ability_mod(a)


func pb() -> int:
	return stats.proficiency_bonus()


func ac() -> int:
	return stats.ac + (2 if has_effect("shield_of_faith") else 0) + (5 if has_effect("shield_spell") else 0)


## 주문 내성 DC와 주문 공격 보너스 (rules 7.5)
func spell_mod() -> int:
	return mod(stats.spell_ability) if stats.spell_ability >= 0 else 0


func spell_dc() -> int:
	return Rules.save_dc(spell_mod(), pb()) + (1 if has_effect("innate_sorcery") else 0)


func spell_attack_bonus() -> int:
	return spell_mod() + pb()


func speed() -> int:
	if has_condition("unconscious") or has_effect("paralyzed") or has_effect("stunned"):
		return 0
	var s := stats.speed
	if has_effect("slowed"):
		s -= 2
	if has_effect("staggered"):
		s = floori(s / 2.0)
	return maxi(0, s)


func save_bonus(a: int) -> int:
	return mod(a) + (pb() if stats.save_proficiencies.has(a) else 0)


## 기술 판정 보너스 (숙련이면 숙련 보너스를 더함). skill은 Rules.SKILLS 키 또는 능력치 이름(str, dex...)
func skill_bonus(skill: String) -> int:
	if Rules.SKILLS.has(skill):
		var prof := pb() if stats.skills.has(skill) else (pb() / 2 if stats.has_feature("jack_of_all_trades") else 0)
		return mod(Rules.SKILLS[skill]) + prof + (pb() if stats.expertise.has(skill) else 0)
	var i := Rules.ABILITY_NAMES.find(skill.to_upper())
	return mod(i) if i >= 0 else 0


## 수동 지각 = 10 + 지각 보너스
func passive_perception() -> int:
	return 10 + skill_bonus("perception")


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


## 맨손 타격 (몽크). 없으면 null
func unarmed_weapon() -> WeaponData:
	for w in stats.weapons:
		if w.id == "unarmed":
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
	return has_condition("incapacitated") or has_condition("unconscious") or has_effect("turned") or has_effect("paralyzed") or has_effect("stunned")


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
	bonus_attacks = 0
	toggles.erase("flurry")
	once_per_turn.clear()
