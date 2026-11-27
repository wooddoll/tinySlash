## 실시간 액션 전투 테스트 (docs/rules.md 10장)
extends RefCounted

var failures: Array[String] = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func eq(actual, expected, msg: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [msg, str(expected), str(actual)])


## 12x8 빈 방 (가장자리는 벽)
func arena() -> ActionCombat:
	var d := Dungeon.new(12, 8)
	for y in range(1, 7):
		for x in range(1, 11):
			d.set_tile(Vector2i(x, y), Dungeon.Tile.FLOOR)
	return ActionCombat.new(d, Dice.new(1))


func pc(cls: String, level := 1) -> Creature:
	return Creature.new(Catalog.pc(cls, level), 0)


func foe(id := "goblin_warrior") -> Creature:
	return Creature.new(Catalog.monster(id), 1)


func run(ac: ActionCombat, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		ac.tick(1.0 / 60.0)
		t += 1.0 / 60.0


func test_move_and_walls() -> void:
	var ac := arena()
	var p := ac.add(pc("fighter"), Vector2(2.5, 2.5), "player")
	p.move = Vector2(1, 0)
	run(ac, 1.0)
	check(p.pos.x > 6.0, "moves about 4.5 units per second (got %.2f)" % p.pos.x)
	p.move = Vector2(1, 0)
	run(ac, 3.0)
	check(p.pos.x <= 10.71, "stops at the wall (got %.2f)" % p.pos.x)


func test_melee_hit_uses_dnd_roll() -> void:
	var ac := arena()
	var p := ac.add(pc("fighter"), Vector2(3.0, 3.5), "player")
	var g := ac.add(foe(), Vector2(4.0, 3.5), "monster")
	g.c.stats.max_hp = 99
	g.c.hp = 99
	p.facing = Vector2(1, 0)
	ac.dice.forced = [15, 6]  # d20 15 + 5 = 20 vs AC 15 → 맞음, 1d8? greatsword 2d6 → 6 + ...
	var hits: Array = []
	ac.event.connect(func(ev: Dictionary) -> void:
		if ev.type == "hit":
			hits.append(ev))
	p.want_attack = true
	run(ac, 0.5)
	eq(hits.size(), 1, "one hit")
	check(not hits[0].blocked, "beat AC")
	check(g.c.hp < 99, "took damage")
	check(g.awake, "wakes when hit")


func test_blocked_hit_does_half() -> void:
	var ac := arena()
	var p := ac.add(pc("wizard"), Vector2(3.0, 3.5), "player")
	var g := ac.add(foe(), Vector2(4.0, 3.5), "monster")
	p.weapon = Catalog.weapon("dagger")
	g.c.stats.max_hp = 99
	g.c.hp = 99
	ac.dice.forced = [2, 4]  # 2 + 4 = 6 < AC 15 → 막힘: (4 + 1) / 2 = 2
	var ev := ac.strike(p, g, p.weapon)
	check(ev.blocked, "blocked")
	eq(ev.damage, 2, "half damage")


func test_dodge_iframes() -> void:
	var ac := arena()
	var p := ac.add(pc("fighter"), Vector2(3.0, 3.5), "player")
	var g := ac.add(foe(), Vector2(4.0, 3.5), "monster")
	p.move = Vector2(0, 1)
	p.want_dodge = true
	ac.tick(1.0 / 60.0)
	eq(p.state, "dodge", "rolling")
	var hp := p.c.hp
	var ev := ac.strike(g, p, g.weapon)
	check(ev.has("dodged"), "attack passes through the roll")
	eq(p.c.hp, hp, "no damage")
	run(ac, 0.5)
	check(p.pos.y > 4.5, "rolled away (y %.2f)" % p.pos.y)


func test_monster_telegraphs_then_hits() -> void:
	var ac := arena()
	var p := ac.add(pc("fighter"), Vector2(3.0, 3.5), "player")
	var g := ac.add(foe(), Vector2(6.0, 3.5), "monster")
	p.c.stats.max_hp = 200
	p.c.hp = 200
	var swings: Array = []
	var hits: Array = []
	ac.event.connect(func(ev: Dictionary) -> void:
		if ev.type == "swing" and ev.actor == g:
			swings.append(ev)
		elif ev.type == "hit" and ev.actor == g:
			hits.append(ev))
	run(ac, 0.2)
	check(g.awake, "wakes when the party is close")
	run(ac, 3.0)
	check(not swings.is_empty(), "monster swings")
	check(swings[0].windup >= 0.5, "slow, visible windup")
	check(not hits.is_empty(), "and hits a standing target")


func test_ranged_shot_travels() -> void:
	var ac := arena()
	var p := ac.add(pc("wizard"), Vector2(2.0, 3.5), "player")
	var g := ac.add(foe(), Vector2(8.0, 3.5), "monster")
	g.c.stats.max_hp = 99
	g.c.hp = 99
	eq(p.weapon.id, "fire_bolt", "wizard's basic attack is Fire Bolt")
	p.facing = Vector2(1, 0)
	ac.dice.forced = [18]
	p.want_attack = true
	run(ac, 0.25)
	eq(ac.shots.size(), 1, "bolt in the air")
	run(ac, 1.0)
	eq(ac.shots.size(), 0, "bolt landed")
	check(g.c.hp < 99, "goblin burned")


func test_kill_gives_xp_and_clears_room() -> void:
	var ac := arena()
	var p := ac.add(pc("fighter"), Vector2(3.0, 3.5), "player")
	var g := ac.add(foe(), Vector2(4.0, 3.5), "monster", 2)
	g.c.hp = 1
	ac.dice.forced = [15]
	ac.strike(p, g, p.weapon)
	eq(g.state, "dead", "dead")
	eq(ac.xp_pool, g.c.stats.xp, "xp pooled")
	check(ac.room_clear(2), "room clear")
	check(not ac.fighting(), "fight over")


func test_party_down_and_revive() -> void:
	var ac := arena()
	var p := ac.add(pc("fighter"), Vector2(3.0, 3.5), "player")
	var g := ac.add(foe(), Vector2(4.0, 3.5), "monster")
	p.c.hp = 1
	ac.dice.forced = [15, 5]
	ac.strike(g, p, g.weapon)
	eq(p.state, "down", "PC goes down, not dead")
	check(ac.party_down(), "whole party down")
	g.c.hp = 0
	ac.revive_party()
	eq(p.c.hp, 1, "back up at 1 HP")
	eq(p.state, "idle", "standing")


func test_ally_follows_and_fights() -> void:
	var ac := arena()
	var p := ac.add(pc("fighter"), Vector2(2.5, 2.5), "player")
	var a := ac.add(pc("cleric"), Vector2(8.5, 5.5), "ally")
	run(ac, 2.0)
	check(a.pos.distance_to(p.pos) < 2.2, "ally walks to the leader (%.2f)" % a.pos.distance_to(p.pos))
	var g := ac.add(foe(), Vector2(5.0, 2.5), "monster")
	g.awake = true
	g.c.stats.max_hp = 999
	g.c.hp = 999
	run(ac, 3.0)
	check(g.c.hp < 999, "ally (and goblin fight) deal damage")


func test_skills() -> void:
	var ac := arena()
	var f := ac.add(pc("fighter"), Vector2(2.5, 2.5), "player")
	f.c.hp = 3
	var sw: int = f.c.resources.second_wind
	eq(ac.use_skill(f), "", "second wind")
	check(f.c.hp > 3, "healed")
	eq(f.c.resources.second_wind, sw - 1, "spent")
	var b := ac.add(pc("barbarian"), Vector2(4.5, 2.5), "ally")
	eq(ac.use_skill(b), "", "rage")
	check(b.c.has_effect("raging"), "raging")
	run(ac, 31.0)
	check(not b.c.has_effect("raging"), "rage times out")
	var w := ac.add(pc("wizard"), Vector2(2.5, 5.5), "ally")
	var g := ac.add(foe(), Vector2(6.5, 5.5), "monster")
	g.c.stats.max_hp = 99
	g.c.hp = 99
	w.facing = Vector2(1, 0)
	eq(ac.use_skill(w), "", "magic missile")
	check(g.c.hp < 99, "darts hit")


func test_potion() -> void:
	var ac := arena()
	var c := pc("fighter")
	c.resources["potion"] = 1
	var p := ac.add(c, Vector2(2.5, 2.5), "player")
	eq(ac.use_potion(p), "HP가 가득 찼어요", "not when full")
	p.c.hp = 2
	eq(ac.use_potion(p), "", "drink")
	check(p.c.hp > 2, "healed")
	eq(ac.use_potion(p), "물약이 없어요", "none left")


func test_monster_miss_is_blocked() -> void:
	var ac := arena()
	var p := ac.add(pc("fighter"), Vector2(3.0, 3.5), "player")
	var g := ac.add(foe(), Vector2(4.0, 3.5), "monster")
	var hp := p.c.hp
	ac.dice.forced = [2, 6]
	var ev := ac.strike(g, p, g.weapon)
	check(ev.blocked, "blocked")
	eq(p.c.hp, hp, "no damage from a monster miss")


func test_monster_windup_not_interrupted() -> void:
	# 몬스터는 준비 중에 맞아도 공격이 끊기지 않음 (치명타 제외)
	var ac := arena()
	var p := ac.add(pc("fighter"), Vector2(3.0, 3.5), "player")
	var g := ac.add(foe(), Vector2(4.0, 3.5), "monster")
	g.c.stats.max_hp = 99
	g.c.hp = 99
	g.awake = true
	g.state = "windup"
	g.t = 0.5
	p.facing = Vector2(1, 0)
	ac.dice.forced = [15, 4, 4]
	ac.strike(p, g, p.weapon)
	eq(g.state, "windup", "still winding up after a normal hit")
	ac.dice.forced = [20, 4, 4, 4, 4]
	ac.strike(p, g, p.weapon)
	eq(g.state, "stun", "a crit interrupts")


func test_dodge_cancels_recover_and_buffers() -> void:
	var ac := arena()
	var p := ac.add(pc("fighter"), Vector2(3.0, 3.5), "player")
	p.want_attack = true
	ac.tick(1.0 / 60.0)
	eq(p.state, "windup", "swinging")
	# 준비 중에 누른 구르기는 기억했다가 회복 동작에 들어가면 바로 구름
	p.want_dodge = true
	var t := 0.0
	while p.state != "dodge" and t < 0.5:
		ac.tick(1.0 / 60.0)
		t += 1.0 / 60.0
	eq(p.state, "dodge", "buffered dodge fires")
	check(t < ActionCombat.PC_WINDUP + HEAVY_PAD + 0.05, "dodge cancels recovery (%.2f s)" % t)


const HEAVY_PAD := ActionCombat.HEAVY_EXTRA


func test_multiattack_rolls_each() -> void:
	var ac := arena()
	var p := ac.add(pc("fighter"), Vector2(3.0, 3.5), "player")
	var g := ac.add(foe("ghoul"), Vector2(4.0, 3.5), "monster")
	p.c.stats.max_hp = 99
	p.c.hp = 99
	g.facing = Vector2(-1, 0)
	var hits := [0]
	ac.event.connect(func(ev: Dictionary) -> void:
		if ev.type in ["hit", "text"] and ev.get("target", ev.actor) == p:
			hits[0] += 1)
	ac._release(g)
	eq(hits[0], 2, "ghoul swings two claws")


func test_monster_walks_around_pillar() -> void:
	var ac := arena()
	for y in range(2, 6):
		ac.dungeon.set_tile(Vector2i(5, y), Dungeon.Tile.WALL)
	var p := ac.add(pc("fighter"), Vector2(8.5, 3.5), "player")
	var g := ac.add(foe(), Vector2(2.5, 3.5), "monster")
	g.awake = true
	p.c.stats.max_hp = 999
	p.c.hp = 999
	run(ac, 6.0)
	check(g.pos.distance_to(p.pos) < 2.0, "reached the player around the wall (dist %.2f)" % g.pos.distance_to(p.pos))


func test_ally_cleric_heals() -> void:
	var ac := arena()
	var p := ac.add(pc("fighter"), Vector2(3.0, 3.5), "player")
	var cl := ac.add(pc("cleric"), Vector2(3.0, 4.5), "ally")
	var g := ac.add(foe(), Vector2(9.0, 6.0), "monster")
	g.awake = true
	p.c.hp = 2
	ac.tick(1.0 / 60.0)
	check(p.c.hp > 2, "ally cleric used Healing Word")


func test_max_two_melee_attackers() -> void:
	# 한 대상을 동시에 공격 준비하는 근접 몬스터는 최대 2마리
	var ac := arena()
	var p := ac.add(pc("fighter"), Vector2(5.5, 4.0), "player")
	p.c.stats.max_hp = 999
	p.c.hp = 999
	for i in 4:
		var g := ac.add(foe(), p.pos + Vector2.from_angle(i * PI / 2) * 1.0, "monster")
		g.awake = true
	var most := 0
	for f in 300:
		ac.tick(1.0 / 60.0)
		most = maxi(most, ac.actors.filter(func(b: ActionCombat.Actor) -> bool: return b.state == "windup").size())
	check(most <= ActionCombat.MAX_MELEE_ATTACKERS, "at most 2 wind up together (got %d)" % most)
	check(most >= 1, "they still attack")


func test_target_score_prefers_hurt_caster() -> void:
	var ac := arena()
	var g := ac.add(foe(), Vector2(5.0, 4.0), "monster")
	var f := ac.add(pc("fighter"), Vector2(6.0, 4.0), "player")
	var w := ac.add(pc("wizard"), Vector2(5.0, 5.3), "ally")
	w.c.hp = 1
	check(ac.monster_target_score(g, w) > ac.monster_target_score(g, f), "a hurt caster a bit farther away is preferred")


func test_cowardly_flees() -> void:
	var ac := arena()
	var p := ac.add(pc("fighter"), Vector2(3.0, 4.0), "player")
	var g := ac.add(foe("goblin_minion"), Vector2(4.0, 4.0), "monster")
	g.awake = true
	g.c.stats.features.append("cowardly")
	g.c.hp = 1
	seed(3)
	var fled := false
	for i in 40:
		g.flee_checked = false
		g.flee = 0.0
		ac._think_monster(g, 0.016)
		if g.flee > 0.0:
			fled = true
			check(g.move.dot(g.pos - p.pos) > 0.0, "runs away from the player")
			break
	check(fled, "a bloodied cowardly goblin sometimes flees")


func test_ally_dodges_telegraph() -> void:
	var ac := arena()
	ac.add(pc("fighter"), Vector2(2.0, 2.0), "player")
	var cl := ac.add(pc("cleric"), Vector2(5.0, 4.0), "ally")
	var g := ac.add(foe(), Vector2(6.0, 4.0), "monster")
	g.awake = true
	g.target = cl
	g.state = "windup"
	g.t = ActionCombat.MONSTER_WINDUP - 0.3
	seed(1)
	var dodged := 0
	for i in 20:
		cl.reacted.clear()
		cl.want_dodge = false
		ac._think_ally(cl)
		if cl.want_dodge:
			dodged += 1
	check(dodged >= 8 and dodged <= 19, "ally dodges about 70%% of the time (%d/20)" % dodged)


func test_ghoul_paralyzes_then_wears_off() -> void:
	var ac := arena()
	var p := ac.add(pc("fighter"), Vector2(3.0, 3.5), "player")
	var g := ac.add(foe("ghoul"), Vector2(4.0, 3.5), "monster")
	p.c.stats.max_hp = 99
	p.c.hp = 99
	ac.dice.forced = [20, 3, 3, 1]  # 맞힘(치명타), 피해, 내성 1 → 실패
	ac.strike(g, p, g.weapon)
	check(p.c.has_effect("paralyzed"), "fighter paralyzed")
	p.want_attack = true
	ac.tick(1.0 / 60.0)
	eq(p.state, "stun", "can't act while paralyzed")
	run(ac, ActionCombat.PARALYZE_TIME + 0.2)
	check(not p.c.has_effect("paralyzed"), "paralysis wears off")


func test_zombie_undead_fortitude() -> void:
	var ac := arena()
	var p := ac.add(pc("fighter"), Vector2(3.0, 3.5), "player")
	var z := ac.add(foe("zombie"), Vector2(4.0, 3.5), "monster")
	z.c.hp = 3
	ac.dice.forced = [15, 2, 2, 20]  # 맞힘, 피해 2+2+3=7 (치명타 아님), CON 내성 20 → 버팀
	ac.strike(p, z, p.weapon)
	eq(z.c.hp, 1, "zombie stays at 1 HP")
	check(z.alive(), "still up")


func test_ghast_stench_poisons() -> void:
	var ac := arena()
	var p := ac.add(pc("fighter"), Vector2(3.0, 3.5), "player")
	ac.add(foe("ghast"), Vector2(4.0, 3.5), "monster")
	ac.dice.forced = [1]
	ac._stench(0.0)
	check(p.c.has_effect("poisoned"), "failed CON save → poisoned")


func test_shadow_drains_strength() -> void:
	var ac := arena()
	var p := ac.add(pc("fighter"), Vector2(3.0, 3.5), "player")
	var s := ac.add(foe("shadow"), Vector2(4.0, 3.5), "monster")
	p.c.stats.max_hp = 99
	p.c.hp = 99
	ac.dice.forced = [19, 3, 1, 2]
	ac.strike(s, p, s.weapon)
	check(p.c.str_loss > 0, "strength drained (%d)" % p.c.str_loss)


func test_flyer_crosses_low_obstacle() -> void:
	# 날면 높이 1 이하 장애물 위로 지나가고, 걷는 몬스터는 못 지남. 높은 장애물은 둘 다 못 지남
	var ac := arena()
	ac.dungeon.obstacles[Vector2i(5, 3)] = 1.0
	ac.dungeon.obstacles[Vector2i(6, 3)] = 3.0
	var bat := ac.add(foe("swarm_bats"), Vector2(2.5, 3.5), "monster")
	var g := ac.add(foe(), Vector2(2.5, 5.5), "monster")
	check(bat.fly and not g.fly, "flying feature read")
	check(ac.passable(Vector2i(5, 3), bat), "bat over the low obstacle")
	check(not ac.passable(Vector2i(5, 3), g), "walker blocked by the low obstacle")
	check(not ac.passable(Vector2i(6, 3), bat), "tall obstacle blocks the bat")
	check(not ac.passable(Vector2i(0, 3), bat), "wall blocks the bat")


func test_ghost_walks_through_wall() -> void:
	# 비실체는 끝까지 막힌 벽을 지나 곧장 다가옴 (벽 속에서는 절반 속도), 걷는 몬스터는 못 지남
	var ac := arena()
	for y in range(1, 7):
		ac.dungeon.set_tile(Vector2i(5, y), Dungeon.Tile.WALL)
	var p := ac.add(pc("fighter"), Vector2(8.5, 3.5), "player")
	p.c.stats.max_hp = 999
	p.c.hp = 999
	var sp := ac.add(foe("specter"), Vector2(2.5, 3.5), "monster")
	var g := ac.add(foe(), Vector2(2.5, 5.5), "monster")
	sp.awake = true
	g.awake = true
	check(sp.ghost and sp.fly, "specter is incorporeal and flies")
	run(ac, 6.0)
	check(sp.pos.distance_to(p.pos) < 2.0, "specter came through the wall (dist %.2f)" % sp.pos.distance_to(p.pos))
	check(g.pos.x < 5.0, "walker stays behind the wall")


func test_monster_hp_scaled_in_action() -> void:
	# 실시간 전투의 몬스터 HP는 1.5배, 파티와 원래 능력치는 그대로
	var ac := arena()
	var st := Catalog.monster("goblin_warrior")
	var base := st.max_hp
	var g := ac.add(Creature.new(st, 1), Vector2(3.5, 3.5), "monster")
	var p := ac.add(pc("fighter"), Vector2(6.5, 3.5), "player")
	eq(g.c.stats.max_hp, ceili(base * ActionCombat.MONSTER_HP_K), "monster max hp scaled")
	eq(g.c.hp, g.c.stats.max_hp, "monster starts full")
	eq(st.max_hp, base, "shared stats untouched")
	eq(p.c.hp, Catalog.pc("fighter", 1).max_hp, "party hp unchanged")


func test_large_boss_body_and_reach() -> void:
	# 대형 보스는 몸이 커서 더 멀리서 맞고 더 멀리 닿음. 섭정 꼬리 침은 중독
	var ac := arena()
	var r := ac.add(foe("regent"), Vector2(3.5, 3.5), "monster")
	eq(r.radius, 0.45, "large radius")
	check(r.fly and r.c.stats.multiattack == 2, "regent flies, two stings")
	var p := ac.add(pc("fighter"), Vector2(3.5 + ActionCombat.melee_dist(p_dummy(ac), r) - 0.05, 3.5), "player")
	p.facing = Vector2.LEFT
	check(ac.aim_target(p) == r, "fighter can reach the big body from farther away")
	var hit := false
	for i in 30:
		var res := ac.strike(r, p, r.weapon)
		if res.get("damage", 0) > 0 and p.c.has_effect("poisoned"):
			hit = true
			break
		p.c.hp = p.c.stats.max_hp
	check(hit, "sting can poison")


func p_dummy(ac: ActionCombat) -> ActionCombat.Actor:
	var a := ActionCombat.Actor.new(pc("fighter"), Vector2.ZERO)
	a.weapon = ActionCombat.primary_weapon(a.c)
	return a


func test_bosses_exist() -> void:
	for id in DungeonGenerator.BOSSES:
		var s := Catalog.monster(id)
		check(s.size == Rules.Size.LARGE and s.model.begins_with("dark/"), "%s is large with a model" % id)
