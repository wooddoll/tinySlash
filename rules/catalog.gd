## SRD 5.2.1 기반 데이터: 무기, 파이터, 클레릭, 몬스터 (docs/rules.md 4.4, 7, 8장)
## 사거리와 속도는 칸 단위(5ft = 1칸)로 변환해 둡니다.
class_name Catalog
extends RefCounted

const STR := Rules.Ability.STR
const CON := Rules.Ability.CON
const WIS := Rules.Ability.WIS
const CHA := Rules.Ability.CHA


static func weapon(id: String) -> WeaponData:
	match id:
		"greatsword": return _w(id, "대검", 2, 6, "slashing", {"heavy": true, "two_handed": true, "mastery": "graze"})
		"longsword": return _w(id, "롱소드", 1, 8, "slashing", {"versatile_sides": 10, "mastery": "sap"})
		"mace": return _w(id, "메이스", 1, 6, "bludgeoning", {"mastery": "sap"})
		"flail": return _w(id, "도리깨", 1, 8, "bludgeoning", {"mastery": "sap"})
		"warhammer": return _w(id, "워해머", 1, 8, "bludgeoning", {"versatile_sides": 10, "mastery": "push"})
		"javelin": return _w(id, "투창", 1, 6, "piercing", {"thrown": true, "range_normal": 6, "range_long": 24, "mastery": "slow"})
		"shortsword": return _w(id, "숏소드", 1, 6, "piercing", {"finesse": true, "light": true, "mastery": "vex"})
		"scimitar": return _w(id, "시미터", 1, 6, "slashing", {"finesse": true, "light": true, "mastery": "nick"})
		"dagger": return _w(id, "단검", 1, 4, "piercing", {"finesse": true, "light": true, "thrown": true, "range_normal": 4, "range_long": 12, "mastery": "nick"})
		"shortbow": return _w(id, "숏보우", 1, 6, "piercing", {"ranged": true, "two_handed": true, "range_normal": 16, "range_long": 64, "mastery": "vex"})
		"longbow": return _w(id, "롱보우", 1, 8, "piercing", {"ranged": true, "heavy": true, "two_handed": true, "range_normal": 30, "range_long": 120, "mastery": "slow"})
		"bite": return _w(id, "물기", 1, 6, "piercing", {"knocks_prone": true})
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
	if level >= 4:
		s.scores[STR] = 19
	s.ac = 17  # Chain Mail 16 + Defense 1
	s.max_hp = 10 + 2 + (level - 1) * (6 + 2)
	s.speed = 6
	s.initiative_bonus = 1
	s.save_proficiencies = [STR, CON]
	s.weapons = [weapon("greatsword"), weapon("javelin"), weapon("flail")]
	s.weapon_masteries = PackedStringArray(["greatsword", "javelin", "flail"])
	s.model = "mini-characters/character-knight"
	s.weapon_model = "mini-characters/weapon-sword"
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
	if level >= 4:
		s.scores[WIS] = 19
	s.ac = 18  # Chain Mail 16 (Protector) + Shield 2
	s.max_hp = 8 + 1 + (level - 1) * (5 + 1)
	s.speed = 6
	s.initiative_bonus = -1
	s.save_proficiencies = [WIS, CHA]
	s.hit_die = 8
	s.weapons = [weapon("mace")]
	s.model = "mini-characters/character-female-b"
	s.weapon_model = "survival-kit/tool-hammer"
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


## 클래스 id로 PC 스탯
static func pc(cls: String, level := 1) -> CreatureStats:
	return cleric(level) if cls == "cleric" else fighter(level)


static func monster(id: String) -> CreatureStats:
	var s := CreatureStats.new()
	s.id = id
	match id:
		"goblin_minion":
			_m(s, "고블린 졸개", 0.125, 25, [8, 15, 10, 10, 8, 8], 12, 7, 6, Rules.Size.SMALL, 2)
			s.weapons = [weapon("dagger")]
			s.features = PackedStringArray(["nimble_escape", "cowardly"])
			s.ai_style = "skirmisher"
			s.tint = Color(0.55, 0.95, 0.45)
			s.sprite_scale = 0.75
			s.model = "mini-dungeon/character-orc"
			s.weapon_model = "mini-dungeon/weapon-sword"
		"goblin_warrior":
			_m(s, "고블린 전사", 0.25, 50, [8, 15, 10, 10, 8, 8], 15, 10, 6, Rules.Size.SMALL, 2)
			s.weapons = [_goblin(weapon("scimitar")), _goblin(weapon("shortbow"))]
			s.features = PackedStringArray(["nimble_escape", "cowardly"])
			s.ai_style = "ranged"
			s.tint = Color(0.4, 0.8, 0.35)
			s.sprite_scale = 0.8
			s.model = "mini-dungeon/character-orc"
			s.weapon_model = "mini-characters/weapon-bow"
		"goblin_boss":
			_m(s, "고블린 대장", 1.0, 200, [10, 15, 10, 10, 8, 10], 17, 21, 6, Rules.Size.SMALL, 2)
			s.weapons = [_goblin(weapon("scimitar")), _goblin(weapon("shortbow"))]
			s.multiattack = 2
			s.features = PackedStringArray(["nimble_escape", "redirect_attack"])
			s.ai_style = "melee"
			s.tint = Color(0.85, 0.75, 0.35)
			s.sprite_scale = 0.95
			s.model = "mini-dungeon/character-orc"
			s.weapon_model = "mini-dungeon/weapon-spear"
		"skeleton":
			_m(s, "스켈레톤", 0.25, 50, [10, 16, 15, 6, 8, 5], 14, 13, 6, Rules.Size.MEDIUM, 3)
			s.weapons = [weapon("shortsword"), weapon("shortbow")]
			s.creature_type = "undead"
			s.vulnerabilities = PackedStringArray(["bludgeoning"])
			s.immunities = PackedStringArray(["poison"])
			s.condition_immunities = PackedStringArray(["exhaustion", "poisoned"])
			s.ai_style = "melee"
			s.tint = Color(0.8, 0.8, 0.95)
			s.model = "mini-characters/character-zombie"
			s.weapon_model = "mini-dungeon/weapon-sword"
		"wolf":
			_m(s, "늑대", 0.25, 50, [14, 15, 12, 3, 12, 6], 12, 11, 8, Rules.Size.MEDIUM, 2)
			s.weapons = [weapon("bite")]
			s.features = PackedStringArray(["pack_tactics"])
			s.creature_type = "beast"
			s.ai_style = "melee"
			s.tint = Color(0.55, 0.55, 0.6)
			s.sprite_scale = 0.85
			s.model = "mini-characters/character-raider"  # 임시: 팩에 동물 모델이 없음
		_:
			push_error("알 수 없는 몬스터: " + id)
	return s


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
