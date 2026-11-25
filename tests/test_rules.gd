extends RefCounted

const STR := Rules.Ability.STR
const DEX := Rules.Ability.DEX

var failures: Array[String] = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func eq(actual, expected, msg: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [msg, str(expected), str(actual)])


## 빈 8x6 격자 + 시드 고정 주사위
func setup() -> Combat:
	return Combat.new(CombatGrid.new(8, 6), Dice.new(1))


func spawn(cb: Combat, stats: CreatureStats, team: int, cell: Vector2i) -> Creature:
	var c := Creature.new(stats, team)
	cb.add(c, cell)
	c.start_turn_reset()
	return c


# --- 1장: 핵심 판정 ---

func test_ability_mod() -> void:
	eq(Rules.ability_mod(1), -5, "1")
	eq(Rules.ability_mod(9), -1, "9")
	eq(Rules.ability_mod(10), 0, "10")
	eq(Rules.ability_mod(11), 0, "11")
	eq(Rules.ability_mod(17), 3, "17")
	eq(Rules.ability_mod(30), 10, "30")


func test_proficiency_bonus() -> void:
	eq(Rules.proficiency_bonus(1), 2, "lv1")
	eq(Rules.proficiency_bonus(4), 2, "lv4")
	eq(Rules.proficiency_bonus(5), 3, "lv5")
	eq(Rules.proficiency_bonus(9), 4, "lv9")
	eq(Rules.proficiency_bonus(0.125), 2, "CR 1/8")


func test_advantage_combine() -> void:
	eq(Rules.combine_advantage(["a"], []), 1, "adv")
	eq(Rules.combine_advantage([], ["d", "d2"]), -1, "dis")
	eq(Rules.combine_advantage(["a"], ["d", "d2"]), 0, "cancel")


func test_d20_advantage() -> void:
	var d := Dice.new(1)
	d.forced = [5, 17]
	eq(d.d20(1).value, 17, "adv takes higher")
	d.forced = [5, 17]
	eq(d.d20(-1).value, 5, "dis takes lower")


func test_level_for_xp() -> void:
	eq(Rules.level_for_xp(0), 1, "0")
	eq(Rules.level_for_xp(299), 1, "299")
	eq(Rules.level_for_xp(300), 2, "300")
	eq(Rules.level_for_xp(6500), 5, "6500")


# --- 4장: 공격과 피해 ---

func test_attack_bonus_matches_stat_blocks() -> void:
	var cb := setup()
	var f := spawn(cb, Catalog.fighter(1), 0, Vector2i(1, 1))
	var w := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(2, 1))
	var s := spawn(cb, Catalog.monster("skeleton"), 1, Vector2i(1, 2))
	var wolf := spawn(cb, Catalog.monster("wolf"), 1, Vector2i(2, 2))
	eq(cb.attack_info(w, f, w.melee_weapon()).bonus, 4, "goblin scimitar +4")
	eq(cb.attack_info(s, f, s.melee_weapon()).bonus, 5, "skeleton shortsword +5")
	eq(cb.attack_info(wolf, f, wolf.melee_weapon()).bonus, 4, "wolf bite +4")
	eq(cb.attack_info(f, w, f.melee_weapon()).bonus, 5, "fighter greatsword +5")


func test_nat20_crit_doubles_dice() -> void:
	var cb := setup()
	var f := spawn(cb, Catalog.fighter(1), 0, Vector2i(1, 1))
	var boss := spawn(cb, Catalog.monster("goblin_boss"), 1, Vector2i(2, 1))
	# d20=20, 4d6 = 1,1,1,1 / Savage Attacker 재굴림 4d6 = 2,2,2,2 → 8 + STR 3 = 11
	cb.dice.forced = [20, 1, 1, 1, 1, 2, 2, 2, 2]
	cb.attack(f, boss, f.melee_weapon())
	eq(boss.hp, 21 - 11, "boss hp after crit")


func test_nat1_misses_but_graze_hits() -> void:
	var cb := setup()
	var f := spawn(cb, Catalog.fighter(1), 0, Vector2i(1, 1))
	var g := spawn(cb, Catalog.monster("goblin_minion"), 1, Vector2i(2, 1))
	cb.dice.forced = [1]
	cb.attack(f, g, f.melee_weapon())
	eq(g.hp, 7 - 3, "graze deals STR mod on miss")


func test_damage_modifiers_order() -> void:
	var s := Catalog.monster("skeleton")
	var sk := Creature.new(s, 1)
	eq(Damage.modify(sk, 7, "bludgeoning"), 14, "vulnerable doubles")
	eq(Damage.modify(sk, 7, "poison"), 0, "immune")
	s.resistances = PackedStringArray(["bludgeoning"])
	eq(Damage.modify(sk, 7, "bludgeoning"), 6, "resist(3) then vuln(6)")


func test_temp_hp_absorbs_first() -> void:
	var f := Creature.new(Catalog.fighter(1), 0)
	f.temp_hp = 5
	Damage.apply(f, 7, "slashing")
	eq(f.temp_hp, 0, "temp hp used")
	eq(f.hp, 12 - 2, "remaining damage")


# --- 5장: HP 0 ---

func test_monster_dies_at_zero() -> void:
	var g := Creature.new(Catalog.monster("goblin_minion"), 1)
	var r := Damage.apply(g, 7, "slashing")
	check(r.killed and g.dead, "monster dies at 0 HP")


func test_pc_falls_unconscious_and_death_saves() -> void:
	var f := Creature.new(Catalog.fighter(1), 0)
	f.hp = 5
	Damage.apply(f, 8, "slashing")
	check(not f.dead, "not dead")
	check(f.has_condition("unconscious") and f.has_condition("prone"), "unconscious + prone")
	var d := Dice.new(1)
	d.forced = [10, 1]
	Damage.death_save(f, d)
	Damage.death_save(f, d)
	eq(f.death_successes, 1, "one success")
	eq(f.death_failures, 2, "nat 1 = two failures")
	Damage.apply(f, 1, "slashing")
	check(f.dead, "damage at 0 HP → third failure → dead")


func test_massive_damage_kills() -> void:
	var f := Creature.new(Catalog.fighter(1), 0)
	Damage.apply(f, 12 + 12, "slashing")
	check(f.dead, "overflow >= max HP is instant death")


func test_death_save_20_revives() -> void:
	var f := Creature.new(Catalog.fighter(1), 0)
	Damage.apply(f, 12, "slashing")
	var d := Dice.new(1)
	d.forced = [20]
	Damage.death_save(f, d)
	eq(f.hp, 1, "revived with 1 HP")
	check(not f.has_condition("unconscious"), "conscious again")


# --- 2장: 격자 ---

func test_step_costs() -> void:
	var cb := setup()
	var g := cb.grid
	var f := spawn(cb, Catalog.fighter(1), 0, Vector2i(1, 1))
	g.difficult[Vector2i(2, 1)] = true
	eq(g.step_cost(Vector2i(1, 1), Vector2i(2, 1), f), 2, "difficult terrain")
	g.heights[Vector2i(1, 2)] = 1.0
	eq(g.step_cost(Vector2i(1, 1), Vector2i(1, 2), f), 2, "climb 1.0")
	g.heights[Vector2i(0, 1)] = 1.5
	eq(g.step_cost(Vector2i(1, 1), Vector2i(0, 1), f), CombatGrid.INF, "1.5 too high")
	g.walls[Vector2i(2, 0)] = 3.0
	eq(g.step_cost(Vector2i(1, 1), Vector2i(2, 0), f), CombatGrid.INF, "wall")
	g.walls[Vector2i(1, 0)] = 3.0
	eq(g.step_cost(Vector2i(2, 1), Vector2i(1, 0), f), CombatGrid.INF, "wall cell")
	eq(g.step_cost(Vector2i(0, 0), Vector2i(1, 1), f), CombatGrid.INF, "no diagonal past wall corner")


func test_hostile_space_blocks_but_ally_passes() -> void:
	var cb := setup()
	var f := spawn(cb, Catalog.fighter(1), 0, Vector2i(1, 1))
	spawn(cb, Catalog.monster("skeleton"), 1, Vector2i(2, 1))
	var ally := spawn(cb, Catalog.fighter(1), 0, Vector2i(1, 2))
	eq(cb.grid.step_cost(f.cell, Vector2i(2, 1), f), CombatGrid.INF, "same-size hostile blocks")
	eq(cb.grid.step_cost(f.cell, ally.cell, f), 1, "ally passable")
	check(not cb.move_options(f).has(ally.cell), "can't end on ally")


func test_cover() -> void:
	var cb := setup()
	var g := cb.grid
	eq(g.cover(Vector2i(0, 2), Vector2i(4, 2)), 0, "open field")
	g.walls[Vector2i(2, 2)] = 3.0
	eq(g.cover(Vector2i(0, 2), Vector2i(4, 2)), CombatGrid.TOTAL_COVER, "tree = total")
	g.walls[Vector2i(2, 2)] = 1.0
	eq(g.cover(Vector2i(1, 2), Vector2i(3, 2)), 2, "low wall = half")


# --- 3장: 기회 공격 ---

func test_opportunity_attack_on_leaving_reach() -> void:
	var cb := setup()
	var f := spawn(cb, Catalog.fighter(1), 0, Vector2i(2, 2))
	var g := spawn(cb, Catalog.monster("goblin_minion"), 1, Vector2i(3, 2))
	cb.dice.forced = [2]  # 빗나감 → Graze 3
	cb.move_along(g, [Vector2i(4, 2), Vector2i(5, 2)])
	check(not f.reaction_available, "reaction used")
	eq(g.hp, 4, "graze from opportunity attack")
	eq(g.cell, Vector2i(5, 2), "kept moving")


func test_disengage_prevents_opportunity_attack() -> void:
	var cb := setup()
	var f := spawn(cb, Catalog.fighter(1), 0, Vector2i(2, 2))
	var g := spawn(cb, Catalog.monster("goblin_minion"), 1, Vector2i(3, 2))
	cb.nimble_escape(g)
	cb.move_along(g, [Vector2i(4, 2), Vector2i(5, 2)])
	check(f.reaction_available, "no reaction used")
	eq(g.hp, 7, "no damage")


# --- 4.3: 이점 / 불리점 ---

func test_sap_imposes_disadvantage() -> void:
	var cb := setup()
	var f := spawn(cb, Catalog.fighter(1), 0, Vector2i(1, 1))
	var g := spawn(cb, Catalog.monster("goblin_minion"), 1, Vector2i(2, 1))
	cb.dice.forced = [15, 1, 1]  # 명중, 1d8=1, Savage 1 → 4 피해
	cb.attack(f, g, f.stats.weapons[2])  # 도리깨 (Sap)
	eq(g.hp, 3, "flail damage")
	var info := cb.attack_info(g, f, g.melee_weapon())
	eq(info.adv, -1, "sapped goblin attacks with disadvantage")


func test_pack_tactics() -> void:
	var cb := setup()
	var f := spawn(cb, Catalog.fighter(1), 0, Vector2i(2, 2))
	var w1 := spawn(cb, Catalog.monster("wolf"), 1, Vector2i(3, 2))
	var info := cb.attack_info(w1, f, w1.melee_weapon())
	eq(info.adv, 0, "alone: no advantage")
	spawn(cb, Catalog.monster("wolf"), 1, Vector2i(1, 2))
	info = cb.attack_info(w1, f, w1.melee_weapon())
	eq(info.adv, 1, "ally adjacent to target: advantage")


func test_prone_target() -> void:
	var cb := setup()
	var f := spawn(cb, Catalog.fighter(1), 0, Vector2i(1, 1))
	var g := spawn(cb, Catalog.monster("goblin_minion"), 1, Vector2i(2, 1))
	g.add_condition("prone")
	eq(cb.attack_info(f, g, f.stats.weapons[0]).adv, 1, "melee vs prone: advantage")
	cb.grid.place(f, Vector2i(5, 1))
	eq(cb.attack_info(f, g, f.stats.weapons[1]).adv, -1, "ranged vs prone: disadvantage")


func test_wolf_bite_knocks_prone() -> void:
	var cb := setup()
	var f := spawn(cb, Catalog.fighter(1), 0, Vector2i(1, 1))
	var w := spawn(cb, Catalog.monster("wolf"), 1, Vector2i(2, 1))
	cb.dice.forced = [18, 1]
	cb.attack(w, f, w.melee_weapon())
	check(f.has_condition("prone"), "fighter prone")


func test_dodge_and_expiry() -> void:
	var cb := setup()
	var f := spawn(cb, Catalog.fighter(1), 0, Vector2i(1, 1))
	var w := spawn(cb, Catalog.monster("wolf"), 1, Vector2i(2, 1))
	cb.dodge(f)
	eq(cb.attack_info(w, f, w.melee_weapon()).adv, -1, "dodging: disadvantage")
	f.process_phase(f, "start")
	eq(cb.attack_info(w, f, w.melee_weapon()).adv, 0, "dodge ends at next turn start")


func test_ranged_with_adjacent_enemy() -> void:
	var cb := setup()
	var f := spawn(cb, Catalog.fighter(1), 0, Vector2i(1, 1))
	var w := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(2, 1))
	var bow := w.stats.weapons[1]
	eq(cb.attack_info(w, f, bow).adv, -1, "shooting next to an enemy")


# --- 7장: 파이터 ---

func test_extra_attack() -> void:
	var cb := setup()
	var f := spawn(cb, Catalog.fighter(5), 0, Vector2i(1, 1))
	var s := spawn(cb, Catalog.monster("skeleton"), 1, Vector2i(2, 1))
	s.stats.max_hp = 999
	s.hp = 999
	cb.dice.forced = [2, 2]
	check(cb.attack(f, s, f.melee_weapon()), "first attack")
	eq(f.attacks_left, 1, "one attack left")
	check(cb.attack(f, s, f.melee_weapon()), "second attack")
	check(not cb.can_attack(f), "action spent")


func test_improved_critical() -> void:
	var cb := setup()
	var f := spawn(cb, Catalog.fighter(3), 0, Vector2i(1, 1))
	var s := spawn(cb, Catalog.monster("skeleton"), 1, Vector2i(2, 1))
	s.stats.max_hp = 999
	s.hp = 999
	cb.dice.forced = [19, 1, 1, 1, 1, 1, 1, 1, 1]
	var info := cb.attack_info(f, s, f.melee_weapon())
	var r := cb.resolve_attack(f, s, f.melee_weapon(), info)
	check(r.crit, "19 crits at level 3")


func test_second_wind() -> void:
	var cb := setup()
	var f := spawn(cb, Catalog.fighter(1), 0, Vector2i(1, 1))
	f.hp = 3
	cb.dice.forced = [6]
	check(cb.second_wind(f), "used")
	eq(f.hp, 3 + 6 + 1, "1d10 + level")
	eq(f.resources["second_wind"], 1, "one use left")
	check(not cb.second_wind(f), "bonus action already used")


# --- 3.2: 이니셔티브 ---

func test_initiative_tie_breaks_by_dex() -> void:
	var cb := setup()
	var f := spawn(cb, Catalog.fighter(1), 0, Vector2i(1, 1))
	var g := spawn(cb, Catalog.monster("goblin_minion"), 1, Vector2i(5, 1))
	cb.dice.forced = [11, 10]  # 파이터 11+1 = 12, 고블린 10+2 = 12
	cb.roll_initiative()
	eq(cb.order[0], g, "higher DEX goes first on tie")
	eq(f.initiative, 12, "fighter initiative")


func test_redirect_attack() -> void:
	var cb := setup()
	var f := spawn(cb, Catalog.fighter(1), 0, Vector2i(2, 2))
	var boss := spawn(cb, Catalog.monster("goblin_boss"), 1, Vector2i(3, 2))
	var minion := spawn(cb, Catalog.monster("goblin_minion"), 1, Vector2i(4, 2))
	cb.dice.forced = [1]  # 빗나감 → Graze 3이 졸개에게
	cb.attack(f, boss, f.melee_weapon())
	eq(boss.cell, Vector2i(4, 2), "boss swapped")
	eq(minion.cell, Vector2i(3, 2), "minion swapped in")
	eq(minion.hp, 4, "minion took the hit")
	eq(boss.hp, 21, "boss untouched")


func test_monster_ai_runs_full_combat() -> void:
	var cb := Combat.new(CombatGrid.new(10, 8), Dice.new(42))
	var f := Creature.new(Catalog.fighter(1), 0)
	cb.add(f, Vector2i(1, 3))
	for id in ["goblin_warrior", "goblin_minion", "wolf"]:
		cb.add(Creature.new(Catalog.monster(id), 1), Vector2i(8, cb.creatures.size()))
	cb.start()
	var guard := 0
	while not cb.over and guard < 200:
		guard += 1
		var c := cb.current()
		if c.team == 1:
			cb.run_monster_turn()
		else:
			# 간단한 플레이어 봇: 가장 가까운 적에게 붙어서 공격
			var target: Creature = null
			for x in cb.creatures:
				if x.team == 1 and x.is_alive():
					target = x
					break
			var info := cb.attack_info(c, target, c.melee_weapon())
			if not info.valid:
				var opts := cb.move_options(c)
				var best := c.cell
				for cell in opts:
					if cb.grid.distance(cell, target.cell) < cb.grid.distance(best, target.cell):
						best = cell
				cb.move(c, best)
			if not cb.over and target.is_alive():
				cb.attack(c, target, c.melee_weapon())
			cb.end_turn(c)
	check(cb.over, "combat finished within 200 turns (guard=%d)" % guard)


# --- 7.4~7.6: 동료 클레릭과 주문 ---

func _cleric_party(level := 1) -> Array:
	var cb := setup()
	var c := spawn(cb, Catalog.cleric(level), 0, Vector2i(1, 1))
	var f := spawn(cb, Catalog.fighter(1), 0, Vector2i(2, 1))
	spawn(cb, Catalog.monster("wolf"), 1, Vector2i(7, 5))  # 적이 없으면 전투가 끝난 것으로 봄
	return [cb, c, f]


func test_cleric_stats() -> void:
	var c1 := Creature.new(Catalog.cleric(1), 0)
	eq(c1.stats.max_hp, 9, "lv1 hp")
	eq(c1.ac(), 18, "chain mail + shield")
	eq(c1.spell_dc(), 13, "dc 8+2+3")
	eq(c1.spell_attack_bonus(), 5, "spell attack")
	eq(c1.resources.get("slot1", 0), 2, "lv1 slots")
	check(not c1.resources.has("channel"), "no channel at 1")
	var c5 := Creature.new(Catalog.cleric(5), 0)
	eq(c5.stats.max_hp, 33, "lv5 hp")
	eq(c5.resources.get("slot3", 0), 2, "lv5 3rd slots")
	eq(c5.resources.get("channel", 0), 2, "channel")
	eq(c5.spell_dc(), 15, "lv5 dc (WIS 19, PB 3)")


func test_cure_wounds_heals_and_spends_slot() -> void:
	var p := _cleric_party()
	var cb: Combat = p[0]
	var c: Creature = p[1]
	var f: Creature = p[2]
	f.hp = 3
	cb.dice.forced = [4, 5]
	check(Spells.cast(cb, c, "cure_wounds", f), "cast")
	eq(f.hp, 12, "2d8(9)+3 capped at max")
	eq(c.resources.slot1, 1, "slot spent")
	check(not c.action_available, "action used")


func test_healing_word_revives_downed_ally() -> void:
	var p := _cleric_party()
	var cb: Combat = p[0]
	var c: Creature = p[1]
	var f: Creature = p[2]
	cb.grid.remove(f)
	cb.grid.place(f, Vector2i(6, 1))
	f.hp = 0
	f.add_condition("unconscious")
	cb.dice.forced = [2, 3]
	check(Spells.cast(cb, c, "healing_word", f), "cast at range")
	eq(f.hp, 8, "2d4(5)+3")
	check(not f.has_condition("unconscious"), "conscious again")
	check(c.action_available and not c.bonus_available, "bonus action")


func test_one_spell_slot_per_turn() -> void:
	var p := _cleric_party()
	var cb: Combat = p[0]
	var c: Creature = p[1]
	var f: Creature = p[2]
	f.hp = 1
	cb.dice.forced = [1, 1]
	Spells.cast(cb, c, "healing_word", f)
	eq(Spells.why_not(cb, c, "cure_wounds"), "슬롯 주문은 턴에 하나만", "second slot spell blocked")
	eq(Spells.why_not(cb, c, "sacred_flame"), "", "cantrip still fine")


func test_sacred_flame_dex_save() -> void:
	var p := _cleric_party()
	var cb: Combat = p[0]
	var c: Creature = p[1]
	var g := spawn(cb, Catalog.monster("goblin_minion"), 1, Vector2i(6, 3))
	cb.dice.forced = [1, 6]
	Spells.cast(cb, c, "sacred_flame", g)
	eq(g.hp, 1, "failed save takes 1d8")
	c.start_turn_reset()
	cb.dice.forced = [20]
	Spells.cast(cb, c, "sacred_flame", g)
	eq(g.hp, 1, "saved: no damage")


func test_guiding_bolt_grants_advantage() -> void:
	var p := _cleric_party()
	var cb: Combat = p[0]
	var c: Creature = p[1]
	var f: Creature = p[2]
	var g := spawn(cb, Catalog.monster("goblin_minion"), 1, Vector2i(3, 1))
	g.stats.max_hp = 30
	g.hp = 30
	cb.dice.forced = [15, 1, 1, 1, 1]
	Spells.cast(cb, c, "guiding_bolt", g)
	eq(g.hp, 26, "4d6 radiant without modifier")
	check(g.has_effect("guided"), "marked")
	check(cb.attack_info(f, g, f.melee_weapon()).adv_src.has("Guiding Bolt"), "next attack has advantage")
	cb.dice.forced = [2, 3, 1, 1, 1, 1]
	cb.attack(f, g, f.melee_weapon())
	check(not g.has_effect("guided"), "used up by the next attack")


func test_bless_and_concentration() -> void:
	var p := _cleric_party()
	var cb: Combat = p[0]
	var c: Creature = p[1]
	var f: Creature = p[2]
	Spells.cast(cb, c, "bless")
	check(c.has_effect("blessed") and f.has_effect("blessed"), "both blessed")
	eq(c.concentration, "bless", "concentrating")
	cb.dice.forced = [10, 3]
	eq(cb.saving_throw(f, STR, 30).total, 10 + f.save_bonus(STR) + 3, "save adds 1d4")
	cb.dice.forced = [1, 1]
	cb._deal(c, 5, "slashing", false, "")
	eq(c.concentration, "", "failed CON save drops it")
	check(not f.has_effect("blessed"), "bless ends for everyone")


func test_shield_of_faith_and_new_concentration() -> void:
	var p := _cleric_party(2)
	var cb: Combat = p[0]
	var c: Creature = p[1]
	var f: Creature = p[2]
	Spells.cast(cb, c, "shield_of_faith", f)
	eq(f.ac(), 19, "+2 AC")
	c.start_turn_reset()
	Spells.cast(cb, c, "bless")
	eq(f.ac(), 17, "new concentration ends the old one")


func test_turn_undead() -> void:
	var p := _cleric_party(2)
	var cb: Combat = p[0]
	var c: Creature = p[1]
	eq(Spells.why_not(cb, c, "turn_undead"), "6칸 안에 언데드가 없음", "needs undead")
	var s := spawn(cb, Catalog.monster("skeleton"), 1, Vector2i(4, 1))
	cb.dice.forced = [1]
	Spells.cast(cb, c, "turn_undead")
	check(not s.can_act(), "turned skeleton can't act")
	eq(c.resources.channel, 1, "channel spent")
	cb.dice.forced = []
	cb._deal(s, 1, "bludgeoning", false, "")
	check(s.can_act(), "damage ends it")


func test_divine_spark_heals_ally() -> void:
	var p := _cleric_party(2)
	var cb: Combat = p[0]
	var c: Creature = p[1]
	var f: Creature = p[2]
	f.hp = 2
	cb.dice.forced = [5]
	Spells.cast(cb, c, "divine_spark", f)
	eq(f.hp, 10, "1d8(5)+3")


func test_preserve_life_caps_at_half() -> void:
	var p := _cleric_party(3)
	var cb: Combat = p[0]
	var c: Creature = p[1]
	var f: Creature = p[2]
	f.hp = 2
	c.hp = 3
	Spells.cast(cb, c, "preserve_life")
	eq(f.hp, 6, "fighter to half (12/2)")
	eq(c.hp, 10, "cleric to half (21/2)")


func test_spare_the_dying() -> void:
	var p := _cleric_party()
	var cb: Combat = p[0]
	var c: Creature = p[1]
	var f: Creature = p[2]
	f.hp = 0
	f.add_condition("unconscious")
	f.death_failures = 2
	Spells.cast(cb, c, "spare_the_dying", f)
	check(f.stable and f.death_failures == 0, "stable")


func test_death_save_bless_bonus() -> void:
	var f := Creature.new(Catalog.fighter(1), 0)
	f.hp = 0
	var d := Dice.new(1)
	d.forced = [8]
	eq(Damage.death_save(f, d, 2).result, "success", "8 + 2 succeeds")
