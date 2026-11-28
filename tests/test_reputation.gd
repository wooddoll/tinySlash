## 평판·조합 등급·마지막 의뢰 테스트 (rules/reputation.gd, scripts/game.gd, docs/design.md M6·12.3)
extends RefCounted

const Reputation = preload("res://rules/reputation.gd")
const Quests = preload("res://rules/quests.gd")
const Game = preload("res://scripts/game.gd")

var failures: Array[String] = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func _dungeons() -> Array:
	return [{"id": 0, "name": "버려진 동굴", "tile": "바람 등성이", "dir": "이곳", "hours": 0.0},
		{"id": 2, "name": "무너진 광산", "tile": "까마귀 언덕", "dir": "남동", "hours": 8.5},
		{"id": 1, "name": "젖은 지하 사원", "tile": "서리 언덕", "dir": "서", "hours": 6.0}]


func test_change_and_spread() -> void:
	var rep := Reputation.fresh()
	var d := Reputation.on_quest(rep, {"giver": "모험가 조합"}, true)
	check(rep.guild == 6 and rep.village == 3, "조합 의뢰 성공: 조합 +6, 마을 +3")
	check(d == {"guild": 6, "village": 3}, "바뀐 양")
	Reputation.on_quest(rep, {"giver": "나무꾼 조합"}, false)
	check(rep.village == -1 and rep.guild == 4, "마을 의뢰 실패: 마을 −4, 조합 −2")
	for i in 40:
		Reputation.change(rep, "guild", 6)
	check(rep.guild == 100, "100을 넘지 않음")


func test_ranks() -> void:
	check(Reputation.rank_for(0, 50, 5) == 0, "가입 안 하면 그대로")
	check(Reputation.rank_for(1, 14, 5) == 1, "평판 모자람")
	check(Reputation.rank_for(1, 15, 1) == 1, "레벨 모자람")
	check(Reputation.rank_for(1, 15, 2) == 2, "정회원")
	check(Reputation.rank_for(1, 40, 3) == 3, "두 단계 한꺼번에")
	check(Reputation.rank_for(1, 40, 2) == 2, "베테랑은 3레벨부터")
	check(Reputation.rank_for(3, 10, 4) == 3, "평판이 떨어져도 등급은 안 내려감")
	check(Reputation.rank_for(2, -1, 4) == 0, "조합 평판이 음수면 쫓겨남")
	check(Reputation.can_join(0, 0) and not Reputation.can_join(0, -3) and not Reputation.can_join(1, 5), "가입 조건")
	check(Reputation.max_floor(0) == 1 and Reputation.max_floor(1) == 2 and Reputation.max_floor(3) == Reputation.FINAL_FLOOR, "등급별 층")
	check(Reputation.inn_price(10, 0) == 10 and Reputation.inn_price(10, 15) == 7 and Reputation.inn_price(10, 40) == 5, "여관 할인")
	check(not Reputation.free_rest(1) and Reputation.free_rest(2), "회관 무료 휴식")
	check(Reputation.next_need(3) == "" and Reputation.next_need(1).contains("정회원"), "다음 등급 글")


func test_board_respects_rank() -> void:
	var world := {"groups": [{"id": 400, "label": "늑대", "home": Vector2(30, 10)}], "dungeons": _dungeons(), "day": 1}
	for s in range(1, 40):
		world["rank"] = 0
		world["max_floor"] = Reputation.max_floor(0)
		for q in Quests.offers(s, world, [], 1):
			check(q.kind != "boss", "비회원에게는 우두머리 의뢰가 안 붙음")
			if q.kind == "fetch":
				check(int(q.floor) == 1, "비회원은 1층만")
	var seen_boss := false
	for s in range(1, 40):
		world["rank"] = 2
		world["max_floor"] = Reputation.max_floor(2)
		for q in Quests.offers(s, world, [], 1):
			seen_boss = seen_boss or q.kind == "boss"
	check(seen_boss, "회원에게는 우두머리 의뢰가 붙음")


func test_final_quest() -> void:
	var q := Quests.final_quest(_dungeons(), Reputation.FINAL_FLOOR, 77)
	check(q.final and q.kind == "boss" and int(q.dungeon) == 2, "가장 먼 던전")
	check(int(q.floor) == Reputation.FINAL_FLOOR and int(q.uid) == 77, "층·번호")
	check(int(q.days) >= 5 and str(q.text).contains("남동쪽 까마귀 언덕의"), "기한과 위치 글")


func test_game_flow_to_ending() -> void:
	var old := Game.save_path
	Game.save_path = "user://test_rep_save.dat"
	Game.new_game()
	Game.world_seed = 42
	Game.ensure_party()
	var world := {"dungeons": _dungeons()}
	check(Game.rank == 0 and Game.rep.guild == 0, "처음엔 비회원")
	check(Game.final_offer(world).is_empty(), "비회원에겐 마지막 의뢰 없음")
	check(Game.join_guild() and Game.rank == 1, "가입")
	check(not Game.join_guild(), "두 번 가입 안 됨")
	# 조합 의뢰 여러 번 성공 → 평판 오름
	for i in 6:
		var q := {"uid": 100 + i, "kind": "group", "giver": "모험가 조합", "state": "done", "gold": 1, "xp": 0, "title": "t"}
		Game.quests.append(q)
		Game.reward(q)
	check(Game.rep.guild == 36, "조합 평판 36")
	check(Game.rank == 1, "레벨이 모자라 등급은 그대로")
	Game.hero.xp = 2700
	Game.ally.xp = 2700
	var q2 := {"uid": 200, "kind": "group", "giver": "나무꾼 조합", "state": "done", "gold": 1, "xp": 1, "title": "t"}
	Game.quests.append(q2)
	Game.reward(q2)
	check(Game.hero.level() >= 4, "4레벨")
	check(Game.rank == 3, "베테랑이 됨: %d" % Game.rank)
	var fin := Game.final_offer(world)
	check(not fin.is_empty() and fin.final, "마지막 의뢰가 나옴")
	check(Game.take_final(fin) and fin.state == "active", "마지막 의뢰 받기")
	check(Game.final_offer(world).is_empty(), "받은 뒤엔 다시 안 나옴")
	check(Quests.on_boss(Game.quests, 2, Reputation.FINAL_FLOOR).size() == 1, "우두머리를 쓰러뜨림")
	Game.reward(fin)
	check(Game.ended, "엔딩")
	# 저장·불러오기
	Game.save_game()
	var r: Dictionary = Game.rep.duplicate()
	Game.new_game()
	check(Game.rank == 0 and not Game.ended, "새 게임은 처음부터")
	Game.load_game()
	check(Game.rank == 3 and Game.ended and Game.rep == r, "평판·등급·엔딩 되돌림")
	# 실패 벌칙
	Game.quests = [{"uid": 1, "kind": "group", "giver": "모험가 조합", "state": "active", "deadline": Game.day, "floor": 0, "title": "x"}]
	var before: int = Game.rep.guild
	Game.advance_day()
	check(Game.rep.guild == before - 4, "기한을 넘기면 평판 −4")
	Game.delete_save()
	Game.save_path = old
	Game.new_game()
