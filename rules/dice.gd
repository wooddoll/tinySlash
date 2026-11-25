## 모든 주사위 굴림은 여기를 거칩니다.
## 시드를 고정하거나 forced에 값을 넣으면 결과를 재현할 수 있습니다 (테스트용).
class_name Dice
extends RefCounted

var rng := RandomNumberGenerator.new()
## 값이 있으면 무작위 대신 앞에서부터 꺼내 씁니다.
var forced: Array[int] = []


func _init(seed_value: int = -1) -> void:
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()


func roll_die(sides: int) -> int:
	if not forced.is_empty():
		return forced.pop_front()
	return rng.randi_range(1, sides)


func roll(count: int, sides: int) -> Array[int]:
	var out: Array[int] = []
	for i in count:
		out.append(roll_die(sides))
	return out


## advantage: 1 = 이점, -1 = 불리점, 0 = 없음
## 반환: {"value": 사용한 값, "rolls": 굴린 값들}
func d20(advantage: int = 0) -> Dictionary:
	var a := roll_die(20)
	if advantage == 0:
		return {"value": a, "rolls": [a]}
	var b := roll_die(20)
	var v := maxi(a, b) if advantage > 0 else mini(a, b)
	return {"value": v, "rolls": [a, b]}


static func sum(values: Array) -> int:
	var t := 0
	for v in values:
		t += v
	return t
