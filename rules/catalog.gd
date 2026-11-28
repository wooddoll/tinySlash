## SRD 5.2.1 기반 데이터: 무기, 파이터, 클레릭, 몬스터 (docs/rules.md 4.4, 7, 8장)
## 사거리와 속도는 칸 단위(5ft = 1칸)로 변환해 둡니다.
class_name Catalog
extends RefCounted

const STR := Rules.Ability.STR
const CON := Rules.Ability.CON
const WIS := Rules.Ability.WIS
const CHA := Rules.Ability.CHA
const DEX := Rules.Ability.DEX
## 고를 수 있는 PC 클래스 (만든 순서). 이름은 HeroState.NAMES
const CLASSES := ["fighter", "cleric", "barbarian", "rogue", "monk", "paladin", "ranger", "wizard", "sorcerer", "warlock", "bard", "druid"]


static func weapon(id: String) -> WeaponData:
	match id:
		"greataxe": return _w(id, "그레이트액스", 1, 12, "slashing", {"heavy": true, "two_handed": true, "mastery": "cleave"})
		"handaxe": return _w(id, "핸드액스", 1, 6, "slashing", {"light": true, "thrown": true, "range_normal": 4, "range_long": 12, "mastery": "vex"})
		"greatsword": return _w(id, "대검", 2, 6, "slashing", {"heavy": true, "two_handed": true, "mastery": "graze"})
		"longsword": return _w(id, "롱소드", 1, 8, "slashing", {"versatile_sides": 10, "mastery": "sap"})
		"quarterstaff": return _w(id, "쿼터스태프", 1, 6, "bludgeoning", {"versatile_sides": 8, "mastery": "topple"})
		"mace": return _w(id, "메이스", 1, 6, "bludgeoning", {"mastery": "sap"})
		"flail": return _w(id, "도리깨", 1, 8, "bludgeoning", {"mastery": "sap"})
		"warhammer": return _w(id, "워해머", 1, 8, "bludgeoning", {"versatile_sides": 10, "mastery": "push"})
		"javelin": return _w(id, "투창", 1, 6, "piercing", {"thrown": true, "range_normal": 6, "range_long": 24, "mastery": "slow"})
		"spear": return _w(id, "창", 1, 6, "piercing", {"thrown": true, "range_normal": 4, "range_long": 12, "versatile_sides": 8, "mastery": "sap"})
		"shortsword": return _w(id, "숏소드", 1, 6, "piercing", {"finesse": true, "light": true, "mastery": "vex"})
		"scimitar": return _w(id, "시미터", 1, 6, "slashing", {"finesse": true, "light": true, "mastery": "nick"})
		"dagger": return _w(id, "단검", 1, 4, "piercing", {"finesse": true, "light": true, "thrown": true, "range_normal": 4, "range_long": 12, "mastery": "nick"})
		"shortbow": return _w(id, "숏보우", 1, 6, "piercing", {"ranged": true, "two_handed": true, "range_normal": 16, "range_long": 64, "mastery": "vex"})
		"longbow": return _w(id, "롱보우", 1, 8, "piercing", {"ranged": true, "heavy": true, "two_handed": true, "range_normal": 30, "range_long": 120, "mastery": "slow"})
		"bite": return _w(id, "물기", 1, 6, "piercing", {"knocks_prone": true})
		# 시나리오 몬스터의 자연 무기 [SRD 5.2.1]
		"slam": return _w(id, "후려치기", 1, 6, "bludgeoning", {})
		"zombie_slam": return _w(id, "후려치기", 1, 8, "bludgeoning", {})
		"ghoul_claw": return _w(id, "발톱", 1, 4, "slashing", {"finesse": true, "on_hit_save": CON, "on_hit_dc": 10, "on_hit_effect": "paralyzed"})
		"ghast_claw": return _w(id, "발톱", 2, 6, "slashing", {"finesse": true, "on_hit_save": CON, "on_hit_dc": 10, "on_hit_effect": "paralyzed"})
		"shadow_swipe": return _w(id, "흡수하는 손길", 2, 6, "necrotic", {"finesse": true, "on_hit_always": "str_drain"})
		"life_drain": return _w(id, "생명 흡수", 3, 6, "necrotic", {"finesse": true, "add_mod": false, "on_hit_save": CON, "on_hit_dc": 10, "on_hit_effect": "drain_max"})
		"swarm_bites": return _w(id, "물어뜯기", 2, 4, "piercing", {"finesse": true, "add_mod": false})
		"insect_bites": return _w(id, "물어뜯기", 2, 4, "piercing", {"finesse": true})
		# 던전 보스 [변경: SRD에 없는 자작 몬스터]
		"bell_toll": return _w(id, "종 내려치기", 2, 6, "bludgeoning", {"heavy": true, "reach": true})
		"burr_spikes": return _w(id, "가시 바퀴살", 2, 6, "piercing", {})
		"heron_beak": return _w(id, "부리", 1, 10, "piercing", {"finesse": true, "reach": true})
		"silk_claws": return _w(id, "갈고리 발", 1, 8, "slashing", {"finesse": true})
		"scion_vine": return _w(id, "얼음 덩굴", 2, 8, "bludgeoning", {"reach": true})
		"aurochs_gore": return _w(id, "뿔 들이받기", 2, 10, "piercing", {"heavy": true, "reach": true})
		"cantor_tentacle": return _w(id, "큰 도끼", 1, 6, "slashing", {"finesse": true, "reach": true})
		"regent_sting": return _w(id, "독 칼날", 2, 6, "piercing", {"finesse": true, "reach": true, "on_hit_save": CON, "on_hit_dc": 12, "on_hit_effect": "poisoned"})
	push_error("알 수 없는 무기: " + id)
	return null


static func _w(id: String, display: String, count: int, sides: int, type: String, opts: Dictionary) -> WeaponData:
	var w := WeaponData.new()
	w.id = id
	w.display_name = display
	w.dice_count = count
	w.dice_sides = sides
	w.damage_type = type
	for k in opts:
		w.set(k, opts[k])
	return w


## 고정 파이터 (Soldier 배경, 표준 배열). docs/rules.md 7.1
static func fighter(level := 1) -> CreatureStats:
	var s := CreatureStats.new()
	s.id = "fighter"
	s.display_name = "파이터"
	s.is_pc = true
	s.level = level
	s.scores = PackedInt32Array([17, 13, 15, 8, 12, 10])
	s.ac = 17  # Chain Mail 16 + Defense 1
	s.max_hp = 10 + 2 + (level - 1) * (6 + 2)
	s.speed = 6
	s.initiative_bonus = 1
	s.save_proficiencies = [STR, CON]
	s.weapons = [weapon("greatsword"), weapon("javelin"), weapon("flail")]
	s.weapon_masteries = PackedStringArray(["greatsword", "javelin", "flail"])
	s.skills = PackedStringArray(["athletics", "intimidation", "perception", "survival"])
	s.model = "qhero/fighter"
	s.weapon_model = ""
	var f := ["second_wind", "weapon_mastery", "savage_attacker", "defense"]
	if level >= 2:
		f.append_array(["action_surge", "tactical_mind"])
	if level >= 3:
		f.append_array(["improved_critical", "remarkable_athlete"])
	if level >= 5:
		f.append_array(["extra_attack", "tactical_shift"])
	s.features = PackedStringArray(f)
	return s


## 동료 클레릭 (Acolyte 배경, Life Domain, Divine Order: Protector). docs/rules.md 7.4
static func cleric(level := 1) -> CreatureStats:
	var s := CreatureStats.new()
	s.id = "cleric"
	s.display_name = "클레릭"
	s.is_pc = true
	s.level = level
	s.scores = PackedInt32Array([14, 8, 13, 10, 17, 13])
	s.ac = 18  # Chain Mail 16 (Protector) + Shield 2
	s.max_hp = 8 + 1 + (level - 1) * (5 + 1)
	s.speed = 6
	s.initiative_bonus = -1
	s.save_proficiencies = [WIS, CHA]
	s.hit_die = 8
	s.skills = PackedStringArray(["insight", "religion", "medicine", "persuasion"])
	s.weapons = [weapon("mace")]
	s.model = "qhero/cleric"
	s.weapon_model = "2H_Staff"
	s.spell_ability = WIS
	const SLOTS := [[2], [3], [4, 2], [4, 3], [4, 3, 2]]
	s.spell_slots = PackedInt32Array(SLOTS[clampi(level, 1, 5) - 1])
	var sp := ["sacred_flame", "spare_the_dying", "guiding_bolt", "cure_wounds", "healing_word", "bless"]
	var f := ["spellcasting", "protector"]
	if level >= 2:
		sp.append_array(["shield_of_faith", "divine_spark", "turn_undead"])
		f.append("channel_divinity")
		s.channel_divinity = 2
	if level >= 3:
		sp.append_array(["aid", "spiritual_weapon", "preserve_life"])
		f.append_array(["disciple_of_life", "preserve_life"])
	if level >= 5:
		sp.append("spirit_guardians")
		f.append("sear_undead")
	s.spells = PackedStringArray(sp)
	s.features = PackedStringArray(f)
	return s


## 바바리안 (Soldier 배경, 표준 배열, Path of the Berserker). docs/rules.md 7.7
static func barbarian(level := 1) -> CreatureStats:
	var s := CreatureStats.new()
	s.id = "barbarian"
	s.display_name = "바바리안"
	s.is_pc = true
	s.level = level
	s.scores = PackedInt32Array([17, 13, 15, 10, 12, 8])
	# Unarmored Defense: 10 + DEX + CON
	s.ac = 10 + s.ability_mod(DEX) + s.ability_mod(CON)
	s.ac_abilities = [[DEX], [CON]]
	s.max_hp = 12 + 2 + (level - 1) * (7 + 2)
	s.hit_die = 12
	s.speed = 8 if level >= 5 else 6  # Fast Movement +10ft
	s.initiative_bonus = 1
	s.save_proficiencies = [STR, CON]
	s.weapons = [weapon("greataxe"), weapon("handaxe")]
	s.weapon_masteries = PackedStringArray(["greataxe", "handaxe"])
	s.skills = PackedStringArray(["athletics", "intimidation", "perception", "survival"])
	s.model = "qhero/barbarian"
	s.weapon_model = "2H_Axe"
	var f := ["rage", "unarmored_defense", "weapon_mastery", "savage_attacker"]
	if level >= 2:
		f.append_array(["danger_sense", "reckless_attack"])
	if level >= 3:
		f.append_array(["frenzy", "primal_knowledge"])
	if level >= 5:
		f.append_array(["extra_attack", "fast_movement"])
	s.features = PackedStringArray(f)
	return s


## 로그 (Criminal 배경, 표준 배열, Thief). docs/rules.md 7.8
static func rogue(level := 1) -> CreatureStats:
	var s := CreatureStats.new()
	s.id = "rogue"
	s.display_name = "로그"
	s.is_pc = true
	s.level = level
	s.scores = PackedInt32Array([8, 17, 15, 12, 13, 10])
	s.ac = 11 + s.ability_mod(DEX)  # Leather Armor
	s.ac_abilities = [[DEX]]
	s.max_hp = 8 + 2 + (level - 1) * (5 + 2)
	s.hit_die = 8
	s.speed = 6
	s.initiative_bonus = s.ability_mod(DEX) + Rules.proficiency_bonus(level)  # Alert: 이니셔티브 + PB
	s.save_proficiencies = [DEX, Rules.Ability.INT]
	s.weapons = [weapon("shortsword"), weapon("shortbow"), weapon("dagger")]
	s.weapon_masteries = PackedStringArray(["shortsword", "shortbow"])
	s.skills = PackedStringArray(["stealth", "sleight_of_hand", "acrobatics", "perception", "investigation", "deception"])
	s.expertise = PackedStringArray(["stealth", "perception"])
	s.model = "qhero/rogue"
	s.weapon_model = "Knife"
	var f := ["sneak_attack", "expertise", "weapon_mastery", "alert"]
	if level >= 2:
		f.append("cunning_action")
	if level >= 3:
		f.append_array(["steady_aim", "fast_hands", "second_story_work"])
	if level >= 5:
		f.append_array(["cunning_strike", "uncanny_dodge"])
	s.features = PackedStringArray(f)
	return s


## 몽크 (Soldier 배경, 표준 배열, Warrior of the Open Hand). docs/rules.md 7.9
static func monk(level := 1) -> CreatureStats:
	var s := CreatureStats.new()
	s.id = "monk"
	s.display_name = "몽크"
	s.is_pc = true
	s.level = level
	s.scores = PackedInt32Array([12, 17, 14, 10, 14, 8])
	# Unarmored Defense: 10 + DEX + WIS
	s.ac = 10 + s.ability_mod(DEX) + s.ability_mod(WIS)
	s.ac_abilities = [[DEX], [WIS]]
	s.max_hp = 8 + 2 + (level - 1) * (5 + 2)
	s.hit_die = 8
	s.speed = 8 if level >= 2 else 6  # Unarmored Movement +10ft
	s.initiative_bonus = s.ability_mod(DEX)
	s.save_proficiencies = [STR, DEX]
	# Martial Arts: 몽크 무기와 맨손 타격은 DEX를 쓸 수 있고 무술 주사위(d6, 5레벨 d8)를 씀
	var ma := martial_arts_die(level)
	var fist := _w("unarmed", "맨손 타격", 1, ma, "bludgeoning", {"finesse": true})
	var spear := weapon("spear")
	spear.finesse = true
	spear.dice_sides = maxi(spear.dice_sides, ma)
	spear.versatile_sides = 0
	s.weapons = [fist, spear]
	s.skills = PackedStringArray(["athletics", "intimidation", "acrobatics", "insight"])
	s.model = "qhero/monk"
	s.weapon_model = ""
	var f := ["martial_arts", "unarmored_defense", "savage_attacker"]
	if level >= 2:
		f.append_array(["monks_focus", "unarmored_movement", "uncanny_metabolism"])
	if level >= 3:
		f.append_array(["deflect_attacks", "open_hand_technique"])
	if level >= 4:
		f.append("slow_fall")
	if level >= 5:
		f.append_array(["extra_attack", "stunning_strike"])
	s.features = PackedStringArray(f)
	return s


## 몽크 무술 주사위 [SRD 표: 1~4레벨 d6, 5레벨 d8]
static func martial_arts_die(level: int) -> int:
	return 8 if level >= 5 else 6


## 팔라딘·레인저 같은 반쪽 시전자의 주문 슬롯 [SRD 표]
const HALF_CASTER_SLOTS := [[2], [2], [3], [3], [4, 2]]


## 팔라딘 (Soldier 배경, 표준 배열, Oath of Devotion). docs/rules.md 7.10
static func paladin(level := 1) -> CreatureStats:
	var s := CreatureStats.new()
	s.id = "paladin"
	s.display_name = "팔라딘"
	s.is_pc = true
	s.level = level
	s.scores = PackedInt32Array([17, 10, 14, 8, 12, 14])
	s.ac = 16 + 2 + (1 if level >= 2 else 0)  # Chain Mail + Shield, 2레벨 Defense
	s.max_hp = 10 + 2 + (level - 1) * (6 + 2)
	s.speed = 6
	s.initiative_bonus = 0
	s.save_proficiencies = [WIS, CHA]
	s.weapons = [weapon("longsword"), weapon("javelin")]
	s.weapon_masteries = PackedStringArray(["longsword", "javelin"])
	s.skills = PackedStringArray(["athletics", "intimidation", "insight", "persuasion"])
	s.model = "qhero/paladin"
	s.weapon_model = ""
	s.tint = Color(1.0, 0.92, 0.75)
	s.spell_ability = CHA
	s.spell_slots = PackedInt32Array(HALF_CASTER_SLOTS[clampi(level, 1, 5) - 1])
	var sp := ["lay_on_hands", "bless", "cure_wounds"]
	var f := ["lay_on_hands", "spellcasting", "weapon_mastery", "savage_attacker"]
	if level >= 2:
		sp.append_array(["divine_smite", "heroism"])
		f.append_array(["defense", "paladins_smite"])
	if level >= 3:
		sp.append_array(["protection_from_evil", "shield_of_faith", "sacred_weapon"])
		f.append_array(["channel_divinity", "sacred_weapon"])
		s.channel_divinity = 2
	if level >= 5:
		sp.append("aid")
		f.append_array(["extra_attack", "faithful_steed"])
	s.spells = PackedStringArray(sp)
	s.features = PackedStringArray(f)
	return s


## 레인저 (Soldier 배경, 표준 배열, Hunter). docs/rules.md 7.11
static func ranger(level := 1) -> CreatureStats:
	var s := CreatureStats.new()
	s.id = "ranger"
	s.display_name = "레인저"
	s.is_pc = true
	s.level = level
	s.scores = PackedInt32Array([12, 17, 14, 10, 14, 8])
	s.ac = 12 + s.ability_mod(DEX)  # Studded Leather
	s.ac_abilities = [[DEX]]
	s.max_hp = 10 + 2 + (level - 1) * (6 + 2)
	s.speed = 6
	s.initiative_bonus = s.ability_mod(DEX)
	s.save_proficiencies = [STR, DEX]
	s.weapons = [weapon("longbow"), weapon("shortsword"), weapon("scimitar")]
	s.weapon_masteries = PackedStringArray(["longbow", "shortsword"])
	s.skills = PackedStringArray(["athletics", "intimidation", "perception", "survival", "stealth"])
	if level >= 2:
		s.expertise = PackedStringArray(["perception"])  # Deft Explorer
	s.model = "qhero/ranger"
	s.weapon_model = "2H_Crossbow"
	s.tint = Color(0.8, 1.0, 0.8)
	s.spell_ability = WIS
	s.spell_slots = PackedInt32Array(HALF_CASTER_SLOTS[clampi(level, 1, 5) - 1])
	var sp := ["hunters_mark", "cure_wounds"]
	var f := ["spellcasting", "favored_enemy", "weapon_mastery", "savage_attacker"]
	if level >= 2:
		f.append_array(["archery", "deft_explorer"])
	if level >= 3:
		f.append_array(["colossus_slayer", "hunters_lore"])
	if level >= 5:
		sp.append("aid")
		f.append("extra_attack")
	s.spells = PackedStringArray(sp)
	s.features = PackedStringArray(f)
	return s


## 온전한 시전자(위저드, 소서러, 바드, 드루이드)의 주문 슬롯 [SRD 표]
const FULL_CASTER_SLOTS := [[2], [3], [4, 2], [4, 3], [4, 3, 2]]


## 위저드 (Sage 배경, 표준 배열, Evoker). docs/rules.md 7.12
static func wizard(level := 1) -> CreatureStats:
	var s := CreatureStats.new()
	s.id = "wizard"
	s.display_name = "위저드"
	s.is_pc = true
	s.level = level
	s.scores = PackedInt32Array([8, 13, 15, 17, 12, 10])
	s.ac = 13 + s.ability_mod(DEX)  # Mage Armor [변경: 하루를 시작할 때 써 둔 것으로 봄]
	s.ac_abilities = [[DEX]]
	s.max_hp = 6 + 2 + (level - 1) * (4 + 2)
	s.hit_die = 6
	s.speed = 6
	s.initiative_bonus = s.ability_mod(DEX)
	s.save_proficiencies = [Rules.Ability.INT, WIS]
	s.weapons = [weapon("quarterstaff"), weapon("dagger")]
	s.skills = PackedStringArray(["arcana", "history", "investigation", "insight"])
	if level >= 2:
		s.expertise = PackedStringArray(["arcana"])  # Scholar
	s.model = "qhero/wizard"
	s.weapon_model = ""
	s.tint = Color(0.8, 0.88, 1.0)
	s.spell_ability = Rules.Ability.INT
	s.spell_slots = PackedInt32Array(FULL_CASTER_SLOTS[clampi(level, 1, 5) - 1])
	var sp := ["fire_bolt", "ray_of_frost", "shocking_grasp", "magic_missile", "burning_hands", "thunderwave", "shield"]
	var f := ["spellcasting", "arcane_recovery", "ritual_adept"]
	if level >= 2:
		f.append("scholar")
	if level >= 3:
		sp.append_array(["scorching_ray", "shatter"])
		f.append_array(["evocation_savant", "potent_cantrip"])
	if level >= 5:
		sp.append("fireball")
		f.append("memorize_spell")
	s.spells = PackedStringArray(sp)
	s.features = PackedStringArray(f)
	return s


## 소서러 (Acolyte 배경, 표준 배열, Draconic Sorcery). docs/rules.md 7.13
static func sorcerer(level := 1) -> CreatureStats:
	var s := CreatureStats.new()
	s.id = "sorcerer"
	s.display_name = "소서러"
	s.is_pc = true
	s.level = level
	s.scores = PackedInt32Array([8, 13, 14, 10, 13, 17])
	if level >= 3:
		s.ac = 10 + s.ability_mod(DEX) + s.ability_mod(CHA)  # Draconic Resilience
		s.ac_abilities = [[DEX], [CHA]]
	else:
		s.ac = 13 + s.ability_mod(DEX)  # Mage Armor [변경: 하루를 시작할 때 써 둔 것으로 봄]
		s.ac_abilities = [[DEX]]
	s.max_hp = 6 + 2 + (level - 1) * (4 + 2) + (level if level >= 3 else 0)
	s.hit_die = 6
	s.speed = 6
	s.initiative_bonus = s.ability_mod(DEX)
	s.save_proficiencies = [CON, CHA]
	s.weapons = [weapon("dagger"), weapon("quarterstaff")]
	s.skills = PackedStringArray(["insight", "religion", "arcana", "intimidation"])
	s.model = "qhero/sorcerer"
	s.weapon_model = ""
	s.tint = Color(1.0, 0.8, 0.75)
	s.spell_ability = CHA
	s.spell_slots = PackedInt32Array(FULL_CASTER_SLOTS[clampi(level, 1, 5) - 1])
	var sp := ["fire_bolt", "ray_of_frost", "shocking_grasp", "magic_missile", "shield"]
	var f := ["spellcasting", "innate_sorcery"]
	if level >= 2:
		sp.append_array(["burning_hands", "thunderwave"])
		f.append_array(["font_of_magic", "metamagic"])
	if level >= 3:
		sp.append_array(["scorching_ray", "shatter", "chromatic_orb"])
		f.append_array(["draconic_resilience", "draconic_spells"])
	if level >= 5:
		sp.append("fireball")
		f.append("sorcerous_restoration")
	s.spells = PackedStringArray(sp)
	s.features = PackedStringArray(f)
	return s


## 워락 Pact Magic 슬롯 (레벨 1~5): 슬롯은 모두 같은 레벨 [SRD]
const PACT_SLOTS := [[1], [2], [0, 2], [0, 2], [0, 0, 2]]


## 워락 (Acolyte 배경, 표준 배열, Fiend Patron). docs/rules.md 7.14
static func warlock(level := 1) -> CreatureStats:
	var s := CreatureStats.new()
	s.id = "warlock"
	s.display_name = "워락"
	s.is_pc = true
	s.level = level
	s.scores = PackedInt32Array([8, 13, 14, 10, 13, 17])
	s.ac = 13 + s.ability_mod(DEX)  # Armor of Shadows (Mage Armor를 마음대로)
	s.ac_abilities = [[DEX]]
	s.max_hp = 8 + 2 + (level - 1) * (5 + 2)
	s.hit_die = 8
	s.speed = 6
	s.initiative_bonus = s.ability_mod(DEX)
	s.save_proficiencies = [WIS, CHA]
	s.weapons = [weapon("dagger"), weapon("quarterstaff")]
	s.skills = PackedStringArray(["insight", "religion", "arcana", "intimidation"])
	s.model = "qhero/warlock"
	s.weapon_model = ""
	s.tint = Color(0.8, 0.7, 1.0)
	s.spell_ability = CHA
	s.spell_slots = PackedInt32Array(PACT_SLOTS[clampi(level, 1, 5) - 1])
	var sp := ["eldritch_blast", "chill_touch", "hex", "hellish_rebuke"]
	var f := ["spellcasting", "pact_magic", "armor_of_shadows"]
	if level >= 2:
		f.append_array(["agonizing_blast", "repelling_blast"])
	if level >= 3:
		sp.append_array(["burning_hands", "scorching_ray"])
		f.append("dark_ones_blessing")
	if level >= 5:
		sp.append("fireball")
		f.append("eldritch_mind")
	s.spells = PackedStringArray(sp)
	s.features = PackedStringArray(f)
	return s


## 바드 (Entertainer 배경, 표준 배열, College of Lore). docs/rules.md 7.15
static func bard(level := 1) -> CreatureStats:
	var s := CreatureStats.new()
	s.id = "bard"
	s.display_name = "바드"
	s.is_pc = true
	s.level = level
	s.scores = PackedInt32Array([8, 15, 13, 10, 12, 17])
	s.ac = 11 + s.ability_mod(DEX)  # 가죽 갑옷
	s.ac_abilities = [[DEX]]
	s.max_hp = 8 + 1 + (level - 1) * (5 + 1)
	s.hit_die = 8
	s.speed = 6
	s.initiative_bonus = s.ability_mod(DEX)
	s.save_proficiencies = [DEX, CHA]
	s.weapons = [weapon("dagger"), weapon("shortbow")]
	var sk := ["acrobatics", "persuasion", "deception", "insight"]
	s.spell_ability = CHA
	s.spell_slots = PackedInt32Array(FULL_CASTER_SLOTS[clampi(level, 1, 5) - 1])
	var sp := ["vicious_mockery", "bardic_inspiration", "dissonant_whispers", "healing_word", "faerie_fire", "thunderwave"]
	var f := ["spellcasting", "bardic_inspiration"]
	if level >= 2:
		sp.append("cure_wounds")
		f.append("jack_of_all_trades")
		s.expertise = PackedStringArray(["persuasion", "deception"])
	if level >= 3:
		sp.append("shatter")
		f.append("cutting_words")
		sk.append_array(["perception", "stealth", "arcana"])  # Lore: Bonus Proficiencies
	if level >= 5:
		sp.append("mass_healing_word")
		f.append("font_of_inspiration")
	s.skills = PackedStringArray(sk)
	s.spells = PackedStringArray(sp)
	s.features = PackedStringArray(f)
	s.model = "qhero/bard"
	s.weapon_model = "Knife"
	s.tint = Color(1.0, 0.85, 0.6)
	return s


## 드루이드 (Sage 배경, 표준 배열, Warden, Circle of the Land: 메마른 땅). docs/rules.md 7.16
static func druid(level := 1) -> CreatureStats:
	var s := CreatureStats.new()
	s.id = "druid"
	s.display_name = "드루이드"
	s.is_pc = true
	s.level = level
	s.scores = PackedInt32Array([8, 13, 15, 12, 17, 10])
	s.ac = 12 + mini(s.ability_mod(DEX), 2) + 2  # 가죽 갑옷(Hide) + 방패 (Warden: 중갑 훈련)
	s.ac_abilities = [[DEX, 2]]
	s.max_hp = 8 + 2 + (level - 1) * (5 + 2)
	s.hit_die = 8
	s.speed = 6
	s.initiative_bonus = s.ability_mod(DEX)
	s.save_proficiencies = [Rules.Ability.INT, WIS]
	s.weapons = [weapon("scimitar"), weapon("javelin")]
	s.skills = PackedStringArray(["arcana", "history", "perception", "survival"])
	s.model = "qhero/druid"
	s.weapon_model = "2H_Staff"
	s.tint = Color(0.75, 1.0, 0.75)
	s.spell_ability = WIS
	s.spell_slots = PackedInt32Array(FULL_CASTER_SLOTS[clampi(level, 1, 5) - 1])
	var sp := ["starry_wisp", "cure_wounds", "healing_word", "faerie_fire", "thunderwave"]
	var f := ["spellcasting", "warden"]
	if level >= 2:
		f.append("wild_shape")
	if level >= 3:
		sp.append_array(["fire_bolt", "burning_hands", "lands_aid"])
		f.append("lands_aid")
	if level >= 5:
		sp.append("fireball")
	s.spells = PackedStringArray(sp)
	s.features = PackedStringArray(f)
	return s


## 클래스 id로 PC 스탯. choices: 레벨업 때 고른 것 (LevelUp, HeroState.choices). 비면 기본 구성
static func pc(cls: String, level := 1, choices := {}) -> CreatureStats:
	var s := build(cls, level)
	LevelUp.apply(s, cls, choices)
	return s


## 고르기를 반영하기 전의 클래스 빌더 결과 (4레벨 능력치 향상도 빠짐)
static func build(cls: String, level := 1) -> CreatureStats:
	match cls:
		"cleric": return cleric(level)
		"barbarian": return barbarian(level)
		"rogue": return rogue(level)
		"monk": return monk(level)
		"paladin": return paladin(level)
		"ranger": return ranger(level)
		"wizard": return wizard(level)
		"sorcerer": return sorcerer(level)
		"warlock": return warlock(level)
		"bard": return bard(level)
		"druid": return druid(level)
	return fighter(level)


## 시나리오가 정의한 몬스터: SRD 몬스터(base)를 바탕으로 값을 바꿈. defs에 없으면 monster(id)
##   {"base": "ghast", "name": "...", "hp": 40, "ac": 14, "speed": 6, "xp": 450, "cr": 2,
##    "scores": [6개], "tint": [r, g, b], "model": "팩/이름", "scale": 1.2, "weapon_model": "...",
##    "weapons": [무기 id], "multiattack": 2, "features": [...], "add_features": [...],
##    "resistances": [...], "immunities": [...], "vulnerabilities": [...], "ai_style": "melee"}
static func custom_monster(id: String, defs: Dictionary, depth := 0) -> CreatureStats:
	if not defs.has(id) or depth > 8:
		return monster(id)
	var d: Dictionary = defs[id]
	var s := custom_monster(str(d.get("base", "")), defs, depth + 1) if d.get("base", "") != id else monster(id)
	s.id = id
	if d.has("name"): s.display_name = str(d.name)
	if d.has("hp"): s.max_hp = int(d.hp)
	if d.has("ac"): s.ac = int(d.ac)
	if d.has("speed"): s.speed = int(d.speed)
	if d.has("xp"): s.xp = int(d.xp)
	if d.has("cr"): s.cr = float(d.cr)
	if d.has("initiative_bonus"): s.initiative_bonus = int(d.initiative_bonus)
	if d.has("multiattack"): s.multiattack = int(d.multiattack)
	if d.has("scores") and (d.scores as Array).size() == 6: s.scores = PackedInt32Array(d.scores)
	if d.has("tint"):
		var t: Array = d.tint
		s.tint = Color(float(t[0]), float(t[1]), float(t[2]))
	if d.has("model"): s.model = str(d.model)
	if d.has("scale"): s.sprite_scale = float(d.scale)
	if d.has("weapon_model"): s.weapon_model = str(d.weapon_model)
	if d.has("ai_style"): s.ai_style = str(d.ai_style)
	if d.has("weapons"):
		var ws: Array[WeaponData] = []
		for w in d.weapons:
			ws.append(weapon(str(w)))
		s.weapons = ws
	for k in ["features", "resistances", "immunities", "vulnerabilities", "condition_immunities"]:
		if d.has(k):
			s.set(k, PackedStringArray(d[k]))
	for f in d.get("add_features", []):
		s.features.append(str(f))
	return s


static func monster(id: String) -> CreatureStats:
	var s := CreatureStats.new()
	s.id = id
	match id:
		"goblin_minion":
			_m(s, "고블린 졸개", 0.125, 25, [8, 15, 10, 10, 8, 8], 12, 7, 6, Rules.Size.SMALL, 2)
			s.weapons = [weapon("dagger")]
			s.features = PackedStringArray(["nimble_escape", "cowardly"])
			s.ai_style = "skirmisher"
			s.sprite_scale = 0.75
			s.model = "qhero/puglin"
		"goblin_warrior":
			_m(s, "고블린 전사", 0.25, 50, [8, 15, 10, 10, 8, 8], 15, 10, 6, Rules.Size.SMALL, 2)
			s.weapons = [_goblin(weapon("scimitar")), _goblin(weapon("shortbow"))]
			s.features = PackedStringArray(["nimble_escape", "cowardly"])
			s.ai_style = "ranged"
			s.tint = Color.WHITE
			s.sprite_scale = 0.8
			s.model = "qhero/puglin_warrior"
		"goblin_boss":
			_m(s, "고블린 대장", 1.0, 200, [10, 15, 10, 10, 8, 10], 17, 21, 6, Rules.Size.SMALL, 2)
			s.weapons = [_goblin(weapon("scimitar")), _goblin(weapon("shortbow"))]
			s.multiattack = 2
			s.features = PackedStringArray(["nimble_escape", "redirect_attack"])
			s.ai_style = "melee"
			s.sprite_scale = 0.95
			s.model = "qhero/imp"
		"skeleton":
			_m(s, "스켈레톤", 0.25, 50, [10, 16, 15, 6, 8, 5], 14, 13, 6, Rules.Size.MEDIUM, 3)
			s.weapons = [weapon("shortsword"), weapon("shortbow")]
			s.creature_type = "undead"
			s.vulnerabilities = PackedStringArray(["bludgeoning"])
			s.immunities = PackedStringArray(["poison"])
			s.condition_immunities = PackedStringArray(["exhaustion", "poisoned"])
			s.ai_style = "melee"
			s.tint = Color(0.8, 0.8, 0.95)
			s.model = "dark/skeleton"
			s.weapon_model = ""
		"wolf":
			_m(s, "늑대", 0.25, 50, [14, 15, 12, 3, 12, 6], 12, 11, 8, Rules.Size.MEDIUM, 2)
			s.weapons = [weapon("bite")]
			s.features = PackedStringArray(["pack_tactics"])
			s.creature_type = "beast"
			s.ai_style = "melee"
			s.sprite_scale = 0.75
			s.model = "animals/wolf"
		"zombie":
			_m(s, "좀비", 0.25, 50, [13, 6, 16, 3, 6, 5], 8, 15, 4, Rules.Size.MEDIUM, -2)
			s.weapons = [weapon("zombie_slam")]
			s.features = PackedStringArray(["undead_fortitude"])
			_undead(s)
			s.save_proficiencies = [Rules.Ability.WIS]
			s.model = "qhero/zombie"
		"ghoul":
			_m(s, "구울", 1.0, 200, [13, 15, 10, 7, 10, 6], 12, 22, 6, Rules.Size.MEDIUM, 2)
			s.weapons = [weapon("ghoul_claw")]
			s.multiattack = 2
			_undead(s)
			s.condition_immunities.append("charmed")
			s.model = "qhero/ghoul"
		"ghast":
			_m(s, "가스트", 2.0, 450, [16, 17, 10, 11, 10, 8], 13, 36, 6, Rules.Size.MEDIUM, 3)
			s.weapons = [weapon("ghast_claw")]
			s.multiattack = 2
			_undead(s)
			s.resistances = PackedStringArray(["necrotic"])
			s.features = PackedStringArray(["stench"])
			s.sprite_scale = 1.1
			s.model = "qhero/ghast"
		"shadow":
			_m(s, "섀도", 0.5, 100, [6, 14, 13, 6, 10, 8], 12, 16, 8, Rules.Size.MEDIUM, 2)
			s.weapons = [weapon("shadow_swipe")]
			_undead(s)
			s.resistances = PackedStringArray(["acid", "cold", "fire", "lightning", "thunder", "bludgeoning", "piercing", "slashing"])
			s.immunities = PackedStringArray(["necrotic", "poison"])
			s.vulnerabilities = PackedStringArray(["radiant"])
			s.model = "qhero/shadow"
		"specter":
			_m(s, "스펙터", 1.0, 200, [1, 14, 11, 10, 10, 11], 12, 22, 10, Rules.Size.MEDIUM, 2)
			s.weapons = [weapon("life_drain")]
			_undead(s)
			s.features = PackedStringArray(["flying", "incorporeal"])
			s.resistances = PackedStringArray(["acid", "cold", "fire", "lightning", "thunder", "bludgeoning", "piercing", "slashing"])
			s.immunities = PackedStringArray(["necrotic", "poison"])
			s.model = "qhero/specter"
		"animated_armor":
			_m(s, "움직이는 갑옷", 1.0, 200, [14, 11, 13, 1, 3, 1], 18, 33, 5, Rules.Size.MEDIUM, 0)
			s.weapons = [weapon("slam")]
			s.multiattack = 2
			s.creature_type = "construct"
			s.immunities = PackedStringArray(["poison", "psychic"])
			s.condition_immunities = PackedStringArray(["charmed", "deafened", "exhaustion", "frightened", "paralyzed", "petrified", "poisoned"])
			s.model = "qhero/animated_armor"
			s.weapon_model = ""
		# 던전 보스 [변경: 자작]. 출구(보스) 방에만 나옴. 모델은 Bento "The Eightfold Archive" (tools/bake_boss.gd)
		"bellwarden":
			_m(s, "가라앉은 종지기", 2.0, 450, [18, 8, 16, 3, 10, 5], 16, 45, 6, Rules.Size.LARGE, -1)
			s.weapons = [weapon("bell_toll")]
			s.creature_type = "construct"
			s.immunities = PackedStringArray(["poison", "psychic"])
			s.condition_immunities = PackedStringArray(["charmed", "frightened", "paralyzed", "poisoned"])
			s.model = "dark/bellwarden"
			s.weapon_model = ""
		"cantor":
			_m(s, "포효하는 오크 족장", 3.0, 700, [16, 14, 14, 8, 12, 10], 13, 52, 8, Rules.Size.LARGE, 2)
			s.weapons = [weapon("cantor_tentacle")]
			s.multiattack = 3
			s.creature_type = "humanoid"
			s.resistances = PackedStringArray(["cold", "thunder"])
			s.sprite_scale = 1.6
			s.model = "qhero/orc_chief"
			s.weapon_model = ""
		"regent":
			_m(s, "납골 섭정", 4.0, 1100, [17, 15, 15, 6, 12, 8], 14, 68, 8, Rules.Size.LARGE, 2)
			s.weapons = [weapon("regent_sting")]
			s.multiattack = 2
			_undead(s)
			s.resistances = PackedStringArray(["necrotic"])
			s.features = PackedStringArray(["flying"])
			s.sprite_scale = 1.5
			s.model = "qhero/dark_regent"
			s.weapon_model = ""
		"burrwheel":
			_m(s, "가시 바퀴", 2.0, 450, [16, 14, 15, 3, 10, 4], 15, 42, 8, Rules.Size.LARGE, 2)
			s.weapons = [weapon("burr_spikes")]
			s.creature_type = "construct"
			s.immunities = PackedStringArray(["poison", "psychic"])
			s.condition_immunities = PackedStringArray(["charmed", "frightened", "paralyzed", "poisoned"])
			s.model = "dark/burrwheel"
			s.weapon_model = ""
		"heron":
			_m(s, "비 지킴이 왜가리", 3.0, 700, [14, 16, 13, 6, 14, 8], 14, 50, 8, Rules.Size.LARGE, 3)
			s.weapons = [weapon("heron_beak")]
			s.multiattack = 2
			s.creature_type = "monstrosity"
			s.resistances = PackedStringArray(["cold"])
			s.features = PackedStringArray(["flying"])
			s.model = "dark/heron"
			s.weapon_model = ""
		"silkgrafter":
			_m(s, "비단 접목자", 4.0, 1100, [16, 16, 14, 10, 12, 6], 15, 66, 8, Rules.Size.LARGE, 3)
			s.weapons = [weapon("silk_claws")]
			s.multiattack = 3
			s.creature_type = "monstrosity"
			s.model = "dark/silkgrafter"
			s.weapon_model = ""
		"winterscion":
			_m(s, "겨울 접순", 5.0, 1800, [18, 10, 18, 12, 14, 14], 15, 90, 6, Rules.Size.LARGE, 0)
			s.weapons = [weapon("scion_vine")]
			s.multiattack = 2
			s.creature_type = "plant"
			s.resistances = PackedStringArray(["cold"])
			s.vulnerabilities = PackedStringArray(["fire"])
			s.features = PackedStringArray(["flying"])
			s.model = "dark/winterscion"
			s.weapon_model = ""
		"aurochs":
			_m(s, "접붙인 들소", 5.0, 1800, [21, 10, 19, 3, 12, 6], 14, 95, 8, Rules.Size.HUGE, 0)
			s.weapons = [weapon("aurochs_gore")]
			s.creature_type = "beast"
			s.model = "dark/aurochs"
			s.weapon_model = ""
		"swarm_rats":
			_m(s, "쥐 떼", 0.25, 50, [9, 11, 9, 2, 10, 3], 10, 14, 6, Rules.Size.MEDIUM, 0)
			s.weapons = [weapon("swarm_bites")]
			_swarm(s)
			s.tint = Color(0.45, 0.38, 0.3)
		"swarm_bats":
			_m(s, "박쥐 떼", 0.25, 50, [5, 15, 10, 2, 12, 4], 12, 11, 6, Rules.Size.MEDIUM, 2)
			s.weapons = [weapon("swarm_bites")]
			_swarm(s)
			s.model = "quaternius/demon*3"
			s.sprite_scale = 0.22
			s.features.append("flying")
			s.tint = Color(0.3, 0.25, 0.35)
		"swarm_insects":
			_m(s, "벌레 떼", 0.5, 100, [3, 13, 14, 1, 7, 1], 11, 19, 4, Rules.Size.MEDIUM, 1)
			s.weapons = [weapon("insect_bites")]
			_swarm(s)
			s.model = "quaternius/armabee*3"
			s.tint = Color(0.4, 0.45, 0.2)
		_:
			push_error("알 수 없는 몬스터: " + id)
	return s


static func _undead(s: CreatureStats) -> void:
	s.creature_type = "undead"
	s.immunities = PackedStringArray(["poison"])
	s.condition_immunities = PackedStringArray(["exhaustion", "poisoned"])
	s.ai_style = "melee"


## 떼 [SRD]: 물리 피해 저항, HP 절반 이하면 피해 주사위 절반. 모델은 작은 몸을 여러 개 대신 작게 표시
static func _swarm(s: CreatureStats) -> void:
	s.creature_type = "beast"
	s.features = PackedStringArray(["swarm"])
	s.resistances = PackedStringArray(["bludgeoning", "piercing", "slashing"])
	s.condition_immunities = PackedStringArray(["charmed", "frightened", "grappled", "paralyzed", "petrified", "prone", "restrained", "stunned"])
	s.ai_style = "melee"
	s.sprite_scale = 0.3
	s.model = "animals/rat*3"


static func _m(s: CreatureStats, display: String, cr: float, xp: int, scores: Array, ac: int, hp: int, speed: int, size: Rules.Size, init: int) -> void:
	s.display_name = display
	s.cr = cr
	s.xp = xp
	s.scores = PackedInt32Array(scores)
	s.ac = ac
	s.max_hp = hp
	s.speed = speed
	s.size = size
	s.initiative_bonus = init


## 고블린 무기: 이점으로 명중하면 +1d4
static func _goblin(w: WeaponData) -> WeaponData:
	w.bonus_die_on_advantage = 4
	return w
