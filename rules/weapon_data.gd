## 무기 데이터 (docs/rules.md 4.4). 몬스터의 자연 무기(물기 등)도 여기에 담습니다.
class_name WeaponData
extends Resource

@export var id := ""
@export var display_name := ""
@export var dice_count := 1
@export var dice_sides := 6
@export var versatile_sides := 0
@export var damage_type := "slashing"
## 원거리 무기 (활, 석궁). 투척 무기는 ranged = false, thrown = true
@export var ranged := false
@export var finesse := false
@export var light := false
@export var heavy := false
@export var two_handed := false
@export var reach := false
@export var thrown := false
## 사거리 (칸). 원거리/투척 무기만
@export var range_normal := 0
@export var range_long := 0
## 무기 숙달: graze, sap, slow, vex, topple, push, cleave, nick
@export var mastery := ""
## 몬스터 전용: 이점으로 명중하면 추가 피해 주사위 (고블린 1d4 → 4)
@export var bonus_die_on_advantage := 0
## 몬스터 전용: 명중하면 중형 이하 대상을 넘어뜨림 (늑대 물기)
@export var knocks_prone := false
## 주문 공격용: 공격 능력치 (Rules.Ability, -1이면 무기 기본값)과 피해에 수정치를 더할지
@export var ability := -1
@export var add_mod := true


func melee_reach() -> int:
	return 2 if reach else 1


func damage_text() -> String:
	return "%dd%d %s" % [dice_count, dice_sides, damage_type]
