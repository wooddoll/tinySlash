## 한 판 상태 저장·불러오기 테스트 (scripts/game.gd, docs/design.md M1)
extends RefCounted

const Game = preload("res://scripts/game.gd")
const DV = preload("res://scripts/dungeon_view.gd")

var failures: Array[String] = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func eq(actual, expected, msg: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [msg, str(expected), str(actual)])


func test_hero_state_round_trip() -> void:
	var h := HeroState.fresh("cleric", 0)
	h.xp = 900
	h.hp = 7
	h.resources = {"potion": 2, "slot1": 1}
	h.hit_dice_spent = 1
	h.choices = {4: {"asi": {"wis": 2}}}
	var b := HeroState.from_dict(h.to_dict())
	eq(b.cls, "cleric", "class")
	eq(b.xp, 900, "xp")
	eq(b.hp, 7, "hp")
	eq(b.resources, h.resources, "resources")
	eq(b.choices, h.choices, "choices")
	eq(b.level(), h.level(), "level")


func test_params_round_trip() -> void:
	var p := DungeonParams.new()
	p.rng_seed = 1234
	p.floor_depth = 3
	p.algorithm = DungeonParams.Algorithm.CAVE
	p.theme = "undead"
	var q := DungeonParams.from_dict(p.to_dict())
	eq(q.rng_seed, 1234, "seed")
	eq(q.floor_depth, 3, "depth")
	eq(q.algorithm, DungeonParams.Algorithm.CAVE, "algorithm")
	eq(q.theme, "undead", "theme")


func test_save_outside_and_dungeon_to_file() -> void:
	var real := Game.save_path
	Game.save_path = "user://test_save.dat"
	# 바깥
	Game.new_game()
	Game.world_seed = 77
	Game.defeated = {2: true}
	Game.ensure_party()
	Game.hero.xp = 300
	Game.gold = 45
	Game.place = "outside"
	Game.outside_pos = Vector3(3, 4, 5)
	check(Game.save_game(), "saved")
	Game.new_game()
	eq(Game.world_seed, 0, "new game clears seed")
	var scene := Game.load_game()
	eq(scene, "res://scenes/main.tscn", "outside -> main scene")
	eq(Game.world_seed, 77, "seed back")
	eq(Game.defeated, {2: true}, "defeated back")
	eq(Game.hero.xp, 300, "hero xp back")
	eq(Game.gold, 45, "gold back")
	eq(Game.take_load_pos(), Vector3(3, 4, 5), "outside pos once")
	eq(Game.take_load_pos(), Vector3.INF, "pos taken")
	# 던전 탐험 중 (층 기억, 연 상자, 쉼터 저장 포함)
	var p := DungeonParams.new()
	p.rng_seed = 99
	p.floor_depth = 2
	DV.saved = p
	DV.exploring = true
	DV.from_outside = true
	DV.entry_floor = 1
	DV.floor_no = 2
	DV.opened = {Vector2i(3, 4): true}
	DV.cleared = {5: true}
	DV.explore_cell = Vector2i(7, 8)
	var p1 := DungeonParams.new()
	p1.rng_seed = 11
	DV.floor_memory = {1: {"params": p1, "cleared": {1: true}, "opened": {}, "used_fires": {}, "seen": {Vector2i(1, 1): true}}}
	DV.save = {"params": p1, "floor": 1, "hero": Game.hero.duplicate_state(), "ally": Game.ally.duplicate_state(), "gold": 10, "rested": false}
	Game.place = "dungeon"
	check(Game.save_game(), "saved in dungeon")
	Game.new_game()
	eq(DV.floor_no, 1, "reset run")
	scene = Game.load_game()
	eq(scene, "res://scenes/dungeon.tscn", "dungeon -> dungeon scene")
	eq(DV.saved.rng_seed, 99, "dungeon params back")
	check(DV.exploring and DV.from_outside, "exploring from outside")
	eq(DV.floor_no, 2, "floor back")
	eq(DV.opened, {Vector2i(3, 4): true}, "opened back")
	eq(DV.cleared, {5: true}, "cleared back")
	eq(DV.explore_cell, Vector2i(7, 8), "cell back")
	eq((DV.floor_memory[1].params as DungeonParams).rng_seed, 11, "floor memory params")
	eq(DV.floor_memory[1].seen, {Vector2i(1, 1): true}, "floor memory seen")
	eq((DV.save.hero as HeroState).xp, 300, "shelter save hero")
	eq(DV.hero.xp, 300, "DungeonView.hero is Game.hero")
	# 정리
	Game.delete_save()
	check(not Game.has_save(), "deleted")
	Game.new_game()
	Game.save_path = real

## 심리스 전 저장은 바깥 자리가 칸 안 좌표 → 불러오면 칸 가운데를 더해 세계 좌표로. 새 저장은 그대로
func test_old_outside_pos_becomes_world() -> void:
	Game.new_game()
	Game.world_seed = 5
	Game.tile = Vector2i(2, 0)
	Game.outside_pos = Vector3(300, 4, -250)
	var d := Game.snapshot()
	check(d.get("world_pos", false), "new saves are marked world_pos")
	Game.restore(d)
	eq(Game.take_load_pos(), Vector3(300, 4, -250), "world save kept")
	d.erase("world_pos")
	d.outside_pos = Vector3(10, 4, -5)
	Game.restore(d)
	eq(Game.take_load_pos(), Vector3(266, 4, -261), "old save + tile (2,0) offset (256,-256)")
	Game.new_game()
