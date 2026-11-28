## 마을 배치 테스트 (rules/village.gd, docs/design.md M3·12.5)
extends RefCounted

const Village = preload("res://rules/village.gd")

var failures: Array[String] = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func test_same_seed_same_village() -> void:
	var a = Village.generate(42, Vector2(-1, -1).normalized())
	var b = Village.generate(42, Vector2(-1, -1).normalized())
	check(a.name == b.name, "같은 시드면 같은 이름")
	check(a.buildings.size() == b.buildings.size(), "같은 건물 수")
	for i in a.buildings.size():
		check(a.buildings[i].pos == b.buildings[i].pos and a.buildings[i].kind == b.buildings[i].kind, "건물 %d 같음" % i)


func test_required_buildings_and_layout() -> void:
	for s in range(1, 60):
		var road := Vector2.from_angle(deg_to_rad(190.0 + s * 1.2))
		var v = Village.generate(s, road)
		for k in ["inn", "shop", "guild"]:
			check(not v.find(k).is_empty(), "시드 %d: %s 있음" % [s, k])
		# 길 쪽 블록은 비어 있고, 길 방향에 건물이 없음
		check(v.yards.any(func(y) -> bool: return y.kind == "road"), "시드 %d: 길 블록" % s)
		for t in range(6, 16):
			check(not v.blocked(road * t), "시드 %d: 길 위 %d칸에 건물 없음" % [s, t])
		# 광장 가운데는 비어 있고, 문 앞도 비어 있음
		check(not v.blocked(Vector2.ZERO, 1.0), "시드 %d: 광장 가운데 빔" % s)
		for b in v.buildings:
			check(not v.blocked(b.door), "시드 %d: %s 문 앞 빔" % [s, b.name])
			check((b.pos as Vector2).length() < 16.0, "시드 %d: 빈터 안 (%s)" % [s, b.pos])
		# 건물끼리 겹치지 않음 (서로의 귀퉁이가 상대 바닥 안에 없음)
		for i in v.buildings.size():
			for j in v.buildings.size():
				if i == j:
					continue
				var bi: Dictionary = v.buildings[i]
				var f := Village.footprint(bi) / 2.0
				var fr: Vector2 = bi.front
				for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
					var p: Vector2 = (bi.pos as Vector2) + Vector2(fr.y, -fr.x) * f.x * c.x + fr * f.y * c.y
					check(not Village.blocked_by(v.buildings[j], p), "시드 %d: 건물 %d·%d 겹침" % [s, i, j])
