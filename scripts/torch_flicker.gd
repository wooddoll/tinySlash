## 횃불 불빛 흔들림. 한 노드가 모든 횃불 불빛의 밝기와 불꽃 빛무리 크기를 매 프레임 조금씩 바꿉니다.
## Kenney.decorate가 장식을 놓을 때 하나 붙입니다.
extends Node

var lights: Array[OmniLight3D] = []
var _base: Array[float] = []
var _phase: Array[float] = []
var _t := 0.0


func add(l: OmniLight3D) -> void:
	lights.append(l)
	_base.append(l.light_energy)
	_phase.append(randf() * 100.0)


func _process(delta: float) -> void:
	_t += delta
	for i in lights.size():
		var l := lights[i]
		if not is_instance_valid(l) or not l.is_visible_in_tree():
			continue
		var p := _phase[i] + _t
		# 느린 출렁임과 빠른 떨림을 섞음
		var k := 0.82 + 0.1 * sin(p * 2.3) + 0.06 * sin(p * 7.9 + 1.3) + 0.04 * sin(p * 17.0)
		l.light_energy = _base[i] * k
		var glow := l.get_child(0) as Node3D if l.get_child_count() > 0 else null
		if glow:
			glow.scale = Vector3.ONE * (0.85 + 0.25 * (k - 0.82) / 0.2)
