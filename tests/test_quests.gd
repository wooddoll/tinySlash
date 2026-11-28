## 의뢰 테스트 (rules/quests.gd, scripts/game.gd, docs/design.md M4·12.1)
extends RefCounted

const Quests = preload("res://rules/quests.gd")
const Game = preload("res://scripts/game.gd")

var failures: Array[String] = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func _world(day := 1) -> Dictionary:
	return {"groups": [{"id": 0, "label": "늑대", "home": Vector2(30, 10)}, {"id": 3, "label": "고블린 졸개", "home": Vector2(-40, -50)}],
		"dungeons": [{"id": 0, "name": "버려진 동굴", "tile": "바람 등성이", "dir": "이곳", "hours": 0.0},
			{"id": 2, "name": "무너진 광산", "tile": "까마귀 언덕", "dir": "남동", "hours": 8.5}],
		"max_floor": 2, "day": day}


func test_offers_fill_slots() -> void:
	for s in range(1, 40):
		var offers := Quests.offers(s, _world(), [], 1)
		check(offers.size() > 0 and offers.size() <= Quests.BOARD_SIZE, "시드 %d: 의뢰 수" % s)
		var uids := {}
		for q in offers:
			check(not str(q.title).contains("{") and not str(q.text).contains("{"), "빈칸이 다 채워짐: " + str(q.text))
			check(int(q.gold) > 0 and int(q.xp) > 0 and int(q.days) >= 2, "보상·기한")
			check(not uids.has(q.uid), "uid 겹치지 않음")
			uids[q.uid] = true
			if q.kind == "group":
				check(int(q.target) in [0, 3], "있는 무리를 겨냥")
			else:
				check(int(q.floor) >= 1 and int(q.floor) <= 2, "층 범위")
			if q.kind == "fetch":
				check(str(q.item) != "", "물건 이름")
			if q.kind != "group":
				check(int(q.dungeon) in [0, 2], "있는 던전을 겨냥")
				if int(q.dungeon) == 2:
					# 8.5시간 거리: 왕복 17시간 × 2.5 → 1 + 2 = 적어도 3일
					check(int(q.days) >= 3, "먼 던전은 기한이 넉넉함")
					check(str(q.text).contains("남동쪽 까마귀 언덕의"), "던전 위치가 글에 들어감: " + str(q.text))
	check(Quests.offers(5, _world(1), [], 1) == Quests.offers(5, _world(1), [], 1), "같은 날 같은 의뢰판")


func test_progress_and_deadline() -> void:
	var qs := []
	var g := {"uid": 1, "kind": "group", "target": 3, "floor": 0, "state": "offered", "days": 2, "title": "a"}
	var b := {"uid": 2, "kind": "boss", "target": -1, "floor": 2, "state": "offered", "days": 3, "title": "b"}
	var f := {"uid": 3, "kind": "fetch", "target": -1, "floor": 1, "state": "offered", "days": 3, "title": "c", "item": "반지"}
	for q in [g, b, f]:
		Quests.accept(q, 1)
		qs.append(q)
	check(g.deadline == 3, "기한 = 받은 날 + 일수")
	check(Quests.on_group_defeated(qs, 0).is_empty(), "다른 무리는 무관")
	check(Quests.on_group_defeated(qs, 3).size() == 1 and g.state == "done", "무리 처치")
	check(Quests.on_boss(qs, 2, 2).is_empty() and Quests.on_boss(qs, 0, 1).is_empty() and Quests.on_boss(qs, 0, 2).size() == 1, "보스 층")
	check(Quests.item_on_floor(qs, 0, 1) == f and Quests.item_on_floor(qs, 2, 1).is_empty(), "1층에 물건")
	check(Quests.item_on_floor(qs, 0, 2).is_empty(), "2층엔 없음")
	# 같은 무리를 겨냥한 의뢰는 다시 안 붙음
	var g2 := g.duplicate()
	g2.state = "active"
	for s in range(1, 20):
		for o in Quests.offers(s, _world(), [g2], 10):
			check(not (o.kind == "group" and int(o.target) == 3), "받은 무리는 의뢰판에 안 붙음")
	# 기한
	check(Quests.tick(qs, 4).is_empty(), "기한 날(4일째)까지는 괜찮음")
	check(Quests.tick(qs, 5).size() == 1 and f.state == "failed", "물건 찾기는 5일째에 실패")
	check(g.state == "done", "끝낸 의뢰는 기한과 무관")


func test_game_board_reward_and_save() -> void:
	var old := Game.save_path
	Game.save_path = "user://test_quest_save.dat"
	Game.new_game()
	Game.world_seed = 42
	Game.ensure_party()
	var offers := Game.board_offers(_world())
	check(offers.size() > 0, "의뢰판")
	check(Game.board_offers(_world()) == offers, "같은 날엔 같은 의뢰판")
	var q: Dictionary = offers[0]
	check(Game.take_offer(q), "받기")
	check(q.state == "active" and Game.quests.size() == 1, "받은 의뢰")
	q.state = "done"
	var gold := Game.gold
	var xp: int = Game.hero.xp
	Game.reward(q)
	check(Game.gold == gold + int(q.gold), "금화 보상")
	check(Game.hero.xp > xp, "경험치 보상")
	check(q.state == "rewarded", "보상 받음")
	Game.advance_day()
	check(Game.day == 2, "하루 지남")
	check(Game.save_game(), "저장")
	Game.new_game()
	Game.load_game()
	check(Game.day == 2 and Game.quests.size() == 1 and Game.quests[0].state == "rewarded", "불러오면 의뢰·날짜 그대로")
	Game.delete_save()
	Game.save_path = old
	Game.new_game()
