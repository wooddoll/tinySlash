## 시나리오 팩 "꺼진 봉화"(scenarios/crowwatch) 진행 검사. 데이터 검사는 test_scenario.gd가 모든 팩에 돌림
extends RefCounted

const FILE := "res://scenarios/crowwatch"

var failures: Array[String] = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func eq(actual, expected, msg: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [msg, str(expected), str(actual)])


func fresh() -> Scenario:
	var s := Scenario.load_pack(FILE)
	s.dice = Dice.new(3)
	s.new_game()
	s.out.clear()
	return s


func types(s: Scenario) -> Array:
	return s.out.map(func(o: Dictionary) -> String: return str(o.type))


func last_end(s: Scenario) -> Dictionary:
	for i in range(s.out.size() - 1, -1, -1):
		if s.out[i].type == "end":
			return s.out[i]
	return {}


## 방 표시 칸으로 옮기고 도착 처리 (방 들어서기)
func walk_in(s: Scenario, lid: String, ch: String) -> void:
	s.out.clear()
	s.cell = s.mark_cell(lid, ch)
	s.on_arrived()


func test_pack_loads() -> void:
	var s := fresh()
	eq(s.errors.size(), 0, "no pack errors")
	eq(s.title, "꺼진 봉화", "title")
	eq(s.levels.size(), 4, "four levels")
	eq(s.level, "f1", "starts in the outer ward")
	eq(s.monster_stats("harval").display_name, "철투구 하르발", "boss defined by pack")
	check(s.monster_stats("harval").has_feature("undead_fortitude"), "boss keeps fortitude")


## 대화로 그락을 설득하고 맹세로 하르발을 흔드는 길
func test_full_playthrough_talk() -> void:
	var s := fresh()
	s.interact("f1:h")
	check(s.items.has("store_key"), "notice board key")
	s.interact("f1:f")
	check(s.is_open("f1:f"), "storehouse open")
	s.out.clear()
	s.interact("f1:T")
	check(types(s).has("dialogue"), "teo talks")
	s.choose(0)
	s.choose(1)
	check(s.flags.has("teo_free"), "teo freed")
	s.interact("f1:i")
	check(s.items.has("rope"), "rope")
	s.battle_result("barracks", "win", Vector2i.ZERO)
	s.interact("f1:y")
	check(s.items.has("tower_key"), "tower key from loot")
	s.interact("f1:c")
	check(s.is_open("f1:c"), "tower open")
	s.interact("f1:U")
	eq(s.level, "f2", "tower upstairs")
	s.on_arrived()
	walk_in(s, "f2", "R")
	check(types(s).has("dialogue"), "grak parley")
	s.dice.forced = [20]
	s.choose(0)
	s.choose(0)
	check(s.flags.has("grak_pact") and s.items.has("barrow_key"), "pact gives barrow key")
	eq((s.heroes[0] as HeroState).level(), 2, "level 2 after grak")
	eq(s.foes_of("roof").size(), 0, "goblins left the roof")
	s.interact("f2:D")
	s.on_arrived()
	s.interact("f1:z")
	eq(s.level, "b1", "down the trapdoor")
	s.on_arrived()
	s.interact("b1:x")
	check(s.is_open("b1:x"), "barrow door opened with key")
	s.out.clear()
	s.start_dialogue("ilse")
	s.choose(2)
	s.dice.forced = [20]
	s.choose(0)
	check(s.flags.has("ilse_rest"), "ilse lets us rest")
	s.choose(0)
	(s.heroes[0] as HeroState).hp = 2
	s.interact("b1:c")
	eq((s.heroes[0] as HeroState).current_hp(), (s.heroes[0] as HeroState).max_hp(), "long rest at the guard post")
	s.interact("b1:v")
	eq(s.level, "b2", "barrow")
	s.on_arrived()
	eq((s.heroes[0] as HeroState).level(), 3, "level 3 in the barrow")
	s.interact("b2:u")
	check(s.items.has("oath"), "oath rubbing")
	walk_in(s, "b2", "D")
	check(types(s).has("dialogue"), "harval speaks")
	s.dice.forced = [20]
	s.choose(0)
	check(s.flags.has("harval_moved") and s.flags.has("surprise:boss"), "oath shakes harval")
	s.out.clear()
	s.choose(0)
	check(types(s).has("battle"), "boss battle")
	eq(s.foes_of("boss").size(), 1, "honor guard fell")
	eq(s.battle_setup("boss").surprised, 1, "monsters surprised")
	s.battle_result("boss", "win", Vector2i.ZERO)
	check(s.items.has("lamp") and s.flags.has("escape"), "lamp and escape")
	s.interact("b2:v")
	s.on_arrived()
	walk_in(s, "b1", "F")
	check(types(s).has("battle"), "the dead rise in the corridor")
	s.battle_result("rising", "win", Vector2i.ZERO)
	s.interact("b1:z")
	s.out.clear()
	s.on_arrived()
	check(types(s).has("battle"), "dead pour out of the trapdoor")
	eq(s.foes_of("gate_dead").size(), 2, "pact means one fewer")
	s.battle_result("gate_dead", "win", Vector2i.ZERO)
	s.interact("f1:U")
	s.on_arrived()
	s.out.clear()
	s.interact("f2:X")
	check(types(s).has("dialogue"), "beacon")
	s.choose(0)
	s.choose(0)
	check(s.ended and s.flags.has("beacon_lit"), "beacon lit, game over")
	eq(last_end(s).get("result", ""), "win", "good ending")


## 그락과 싸우는 길: 도망쳤다 돌아오면 다시 전투
func test_grak_fight_and_return() -> void:
	var s := fresh()
	s.go_to("f2", "D")
	s.on_arrived()
	eq(s.foes_of("roof").size(), 2, "grak and archer visible before the talk")
	walk_in(s, "f2", "R")
	check(not types(s).has("battle"), "talk first, no fight yet")
	s.choose(3)  # 무기를 뽑는다
	s.out.clear()
	s.choose(0)
	check(types(s).has("battle"), "roof battle")
	s.battle_result("roof", "retreat", s.mark_cell("f2", "L"))
	walk_in(s, "f2", "R")
	check(types(s).has("battle"), "fight resumes on return")
	s.battle_result("roof", "win", Vector2i.ZERO)
	check(s.items.has("barrow_key"), "key from grak")
	check(not s.flags.has("grak_pact"), "no pact")
	s.flags["escape"] = true
	eq(s.foes_of("gate_dead").size(), 3, "without pact the zombie comes too")


func test_beacon_needs_lamp() -> void:
	var s := fresh()
	s.go_to("f2", "D")
	s.interact("f2:X")
	check(not types(s).has("dialogue"), "no lamp, no dialogue")
	check(not s.ended, "not over")


func test_leaving_early_is_bad_ending() -> void:
	var s := fresh()
	s.interact("f1:X")
	s.choose(0)
	check(not s.ended, "stay")
	s.interact("f1:X")
	s.choose(1)
	s.choose(0)
	check(s.ended, "left")
	eq(last_end(s).get("result", ""), "lose", "bad ending")


func test_well_needs_rope() -> void:
	var s := fresh()
	s.interact("f1:w")
	eq(s.level, "f1", "no rope, no descent")
	s.items["rope"] = {"name": "삼밧줄", "count": 1}
	s.interact("f1:w")
	eq(s.level, "b1", "rope down the well")
	s.on_arrived()
	eq((s.heroes[0] as HeroState).level(), 2, "undercroft milestone")
