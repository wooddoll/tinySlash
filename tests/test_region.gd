## 지방·시간 테스트 (rules/region.gd, scripts/game.gd, docs/design.md M5)
extends RefCounted

const Region = preload("res://rules/region.gd")
const Game = preload("res://scripts/game.gd")

var failures: Array[String] = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func test_region_shape() -> void:
	for s in range(1, 30):
		var r = Region.generate(s)
		check(r.tiles.size() == Region.W * Region.H, "시드 %d: 칸 수" % s)
		check(r.tiles[Region.VILLAGE].kind == "village", "가운데 칸이 마을")
		check(r.dungeons.size() == 4, "던전 넷")
		check(r.dungeons[0].tile == Region.VILLAGE, "0번 던전은 마을 칸")
		var at := {}
		var names := {}
		for d in r.dungeons:
			check(not at.has(d.tile), "한 칸에 던전 하나")
			at[d.tile] = true
			names[d.name] = true
			check(r.dungeon_at(d.tile) == d, "dungeon_at")
			check(d.theme in ["beast", "goblin", "undead"] and int(d.algorithm) in [0, 1, 2], "던전 종류")
		check(names.size() == 4, "던전 이름 겹치지 않음")
		var tn := {}
		for t in r.tiles:
			tn[r.tiles[t].name] = true
		check(tn.size() == r.tiles.size(), "칸 이름 겹치지 않음")
	var a = Region.generate(7)
	var b = Region.generate(7)
	check(a.tiles == b.tiles and a.dungeons == b.dungeons, "같은 시드면 같은 지방")


func test_region_helpers() -> void:
	check(Region.travel_hours(Vector2i(1, 1), Vector2i(2, 1)) == 6.0, "이웃 칸 6시간")
	check(Region.travel_hours(Vector2i(1, 1), Vector2i(2, 2)) == 8.5, "대각선 8.5시간")
	check(Region.travel_hours(Vector2i(0, 0), Vector2i(2, 2)) == 17.0, "끝에서 끝")
	check(Region.direction(Vector2i(1, 1), Vector2i(2, 1)) == "동", "동쪽")
	check(Region.direction(Vector2i(1, 1), Vector2i(1, 0)) == "북", "북쪽 (-Y)")
	check(Region.direction(Vector2i(1, 1), Vector2i(0, 2)) == "남서", "남서쪽")
	check(Region.direction(Vector2i(1, 1), Vector2i(1, 1)) == "이곳", "같은 칸")
	check(Region.inside(Vector2i(0, 2)) and not Region.inside(Vector2i(3, 1)) and not Region.inside(Vector2i(-1, 0)), "안쪽")
	check(Region.offset(Vector2i(2, 1), 256) == Vector2(256, 0), "칸 위치")
	check(Region.tile_seed(42, Region.VILLAGE) == 42, "마을 칸 시드 = 세계 시드 (M5 전과 같은 마을)")
	check(Region.tile_seed(42, Vector2i(0, 0)) != Region.tile_seed(42, Vector2i(2, 0)), "칸마다 다른 시드")


func test_time_flow() -> void:
	Game.new_game()
	check(Game.day == 1 and Game.minute == 8 * 60, "1일째 08:00에 시작")
	check(Game.time_text() == "1일째 08:00", "시각 글")
	Game.advance_minutes(16 * 60 + 5)
	check(Game.day == 2 and Game.minute == 5, "자정을 넘김")
	Game.sleep_until(7)
	check(Game.day == 2 and Game.minute == 7 * 60, "새벽에 자면 같은 날 7시")
	Game.sleep_until(7)
	check(Game.day == 3 and Game.minute == 7 * 60, "7시에 자면 다음 날 7시")
	Game.quests = [{"uid": 1, "kind": "boss", "state": "active", "deadline": 3, "floor": 1, "title": "x"}]
	check(Game.advance_minutes(16 * 60).is_empty(), "기한 날 안은 괜찮음")
	var failed := Game.advance_minutes(9 * 60)
	check(failed.size() == 1 and Game.quests[0].state == "failed", "날이 바뀌면 기한 넘긴 의뢰 실패")
	Game.new_game()


func test_save_tile_and_migration() -> void:
	var old := Game.save_path
	Game.save_path = "user://test_region_save.dat"
	Game.new_game()
	Game.world_seed = 42
	Game.ensure_party()
	Game.tile = Vector2i(2, 0)
	Game.dungeon_id = 3
	Game.minute = 21 * 60 + 30
	Game.defeated = {200: true}
	check(Game.save_game(), "저장")
	Game.new_game()
	Game.load_game()
	check(Game.tile == Vector2i(2, 0) and Game.dungeon_id == 3 and Game.minute == 21 * 60 + 30, "칸·던전·시각 되돌림")
	check(Game.region().dungeon_at(Vector2i(2, 0)).is_empty() or Game.region().tiles.size() == 9, "지방 다시 만듦")
	# 지방 지도 전 저장: 칸이 없고 무리 번호가 0~99
	var d := Game.snapshot()
	d.erase("tile")
	d.defeated = {2: true}
	d.quests = [{"uid": 1, "kind": "group", "target": 3, "state": "active", "floor": 0, "title": "a"},
		{"uid": 2, "kind": "boss", "target": -1, "state": "active", "floor": 1, "title": "b"}]
	Game.restore(d)
	var base := Region.index(Region.VILLAGE) * 100
	check(Game.tile == Region.VILLAGE, "옛 저장은 마을 칸")
	check(Game.defeated.has(base + 2) and not Game.defeated.has(2), "옛 무리 번호에 칸 앞자리")
	check(int(Game.quests[0].target) == base + 3, "옛 무리 의뢰 번호도")
	check(int(Game.quests[1].target) == -1, "던전 의뢰는 그대로")
	Game.delete_save()
	Game.save_path = old
	Game.new_game()
