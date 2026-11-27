## 크리처의 고정 데이터 (스탯 블록 / 캐릭터 시트)
class_name CreatureStats
extends Resource

@export var id := ""
@export var display_name := ""
@export var is_pc := false
@export var level := 1
@export var cr := 0.0
@export var xp := 0
## STR, DEX, CON, INT, WIS, CHA
@export var scores := PackedInt32Array([10, 10, 10, 10, 10, 10])
@export var ac := 10
## AC에 더하는 능력치 [[능력치, 최대치]] (레벨업 능력치 향상 때 AC를 맞추는 데 씀)
@export var ac_abilities: Array = []
@export var max_hp := 1
## 속도 (칸)
@export var speed := 6
@export var size: Rules.Size = Rules.Size.MEDIUM
@export var initiative_bonus := 0
@export var save_proficiencies: Array[int] = []
@export var resistances := PackedStringArray()
@export var vulnerabilities := PackedStringArray()
@export var immunities := PackedStringArray()
@export var condition_immunities := PackedStringArray()
@export var weapons: Array[WeaponData] = []
## 공격 행동 한 번에 하는 공격 횟수 (몬스터 Multiattack)
@export var multiattack := 1
## 기능/특성 id: second_wind, action_surge, extra_attack, improved_critical,
## savage_attacker, pack_tactics, nimble_escape, redirect_attack, cowardly ...
@export var features := PackedStringArray()
## 숙달을 쓸 수 있는 무기 id
@export var weapon_masteries := PackedStringArray()
@export var hit_die := 10
## 크리처 종류: humanoid, undead, beast (Turn Undead 대상 판정)
@export var creature_type := "humanoid"
## 주문 (클레릭): 쓸 수 있는 주문·Channel Divinity id (rules/spells.gd)
@export var spells := PackedStringArray()
## 레벨별 주문 슬롯 수 (인덱스 0 = 1레벨 슬롯)
@export var spell_slots := PackedInt32Array()
## Channel Divinity 사용 횟수
@export var channel_divinity := 0
## 주문 시전 능력치 (Rules.Ability). -1이면 주문 없음
@export var spell_ability := -1
## AI 성향: melee, ranged, skirmisher
@export var ai_style := "melee"
## 화면 표시용
@export var tint := Color.WHITE
@export var sprite_scale := 1.0
## 3D 모델 "팩/이름" (assets/kenney/). 크기는 sprite_scale을 씀
@export var model := "mini-characters/character-male-a"
## 손에 드는 무기 모델 (없으면 빈 문자열)
@export var weapon_model := ""
## 숙련된 기술 (Rules.SKILLS의 키): athletics, perception ...
@export var skills := PackedStringArray()
## 전문 기술 (숙련 보너스를 두 번 더함): 로그 Expertise
@export var expertise := PackedStringArray()


func ability_mod(a: int) -> int:
	return Rules.ability_mod(scores[a])


func proficiency_bonus() -> int:
	return Rules.proficiency_bonus(level if is_pc else cr)


func has_feature(f: String) -> bool:
	return features.has(f)
