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
## AI 성향: melee, ranged, skirmisher
@export var ai_style := "melee"
## 화면 표시용
@export var tint := Color.WHITE
@export var sprite_scale := 1.0
## 3D 모델 "팩/이름" (assets/kenney/). 크기는 sprite_scale을 씀
@export var model := "mini-characters/character-male-a"
## 손에 드는 무기 모델 (없으면 빈 문자열)
@export var weapon_model := ""


func ability_mod(a: int) -> int:
	return Rules.ability_mod(scores[a])


func proficiency_bonus() -> int:
	return Rules.proficiency_bonus(level if is_pc else cr)


func has_feature(f: String) -> bool:
	return features.has(f)
