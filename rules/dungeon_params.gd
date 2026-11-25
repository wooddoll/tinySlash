## 던전 생성 파라미터. 에디터에서 .tres로 저장해 두고 쓸 수도 있습니다.
class_name DungeonParams
extends Resource

enum Algorithm {
	BSP,      ## 공간을 반씩 나눠 방을 하나씩: 고르게 퍼진 방
	SCATTER,  ## 무작위로 방을 흩뿌림: 불규칙한 배치
	CAVE,     ## 셀룰러 오토마타 동굴: 둥글고 자연스러운 공간
}
enum Difficulty { LOW, MODERATE, HIGH }

## 0이면 매번 다른 던전
@export var rng_seed := 0
@export var algorithm := Algorithm.BSP

@export_group("Size")
@export_range(20, 120) var width := 48
@export_range(16, 120) var height := 36

@export_group("Rooms")
@export_range(2, 40) var room_count := 10
@export_range(3, 20) var room_min := 4
@export_range(3, 30) var room_max := 9
## 1 또는 2칸
@export_range(1, 3) var corridor_width := 1
## 최소 신장 트리 외에 추가로 길을 이을 확률 (순환로)
@export_range(0.0, 1.0) var loop_chance := 0.2
## 동굴: 처음에 벽으로 채울 비율
@export_range(0.3, 0.6) var cave_fill := 0.45

@export_group("Features")
## 방 안 기둥(완전 엄폐) 밀도
@export_range(0.0, 0.2) var pillar_density := 0.04
## 잔해 = 험지 밀도
@export_range(0.0, 0.4) var rubble_density := 0.06
## 단상(높이 0.5/1.0)이 생길 확률 / 동굴 높낮이 세기
@export_range(0.0, 1.0) var height_variation := 0.35

@export_group("Encounters")
@export_range(1, 5) var party_level := 1
@export_range(1, 6) var party_size := 1
@export var difficulty := Difficulty.MODERATE
## 깊은 방일수록 난이도 한 단계 위
@export var difficulty_ramp := true
## "mixed", "goblin", "undead", "beast"
@export_enum("mixed", "goblin", "undead", "beast") var theme := "mixed"
## 시작 방을 뺀 방 중 몬스터가 있는 비율
@export_range(0.0, 1.0) var encounter_ratio := 0.6
@export_range(0.0, 1.0) var treasure_ratio := 0.3
## 출구 방에 높은 난이도 조우
@export var boss_room := true
## 모닥불(짧은 휴식) 수. 몬스터 없는 방에 놓음 [변경: rules 5.3]
@export_range(0, 4) var campfire_count := 1


func duplicate_params() -> DungeonParams:
	return duplicate() as DungeonParams
