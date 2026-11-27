## 새 클래스 테스트 (docs/rules.md 7.7~)
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


func setup() -> Combat:
	return Combat.new(CombatGrid.new(8, 6), Dice.new(1))


func spawn(cb: Combat, stats: CreatureStats, team: int, cell: Vector2i) -> Creature:
	var c := Creature.new(stats, team)
	cb.add(c, cell)
	c.start_turn_reset()
	return c


## 전투를 시작하고 c의 턴이 되게 맞춤 (이니셔티브 순서를 c가 맨 앞으로)
func begin(cb: Combat, c: Creature) -> void:
	cb.order = cb.creatures.duplicate()
	cb.order.erase(c)
	cb.order.push_front(c)
	cb.round_num = 1
	cb.turn_index = 0
	c.start_turn_reset()


# --- 공통 ---

func test_every_class_builds() -> void:
	for cls in Catalog.CLASSES:
		for lv in range(1, 6):
			var s := Catalog.pc(cls, lv)
			eq(s.id, cls, "%s id" % cls)
			eq(s.level, lv, "%s level" % cls)
			check(s.max_hp > 0 and s.ac >= 10, "%s %d stats" % [cls, lv])
			check(HeroState.NAMES.has(cls), "%s has a name" % cls)
			check(not s.weapons.is_empty(), "%s has a weapon" % cls)


func test_lead_holds_potion() -> void:
	eq(HeroState.fresh("barbarian", 1).potions(), 1, "lead barbarian holds potion")
	eq(HeroState.fresh("fighter", 0).potions(), 0, "companion fighter has none")
	eq(HeroState.fresh().potions(), 1, "default fighter still holds potion")


# --- 바바리안 (rules 7.7) ---

func test_barbarian_sheet() -> void:
	var s := Catalog.barbarian(1)
	eq(s.ac, 13, "unarmored defense 10 + DEX 1 + CON 2")
	eq(s.max_hp, 14, "lv1 HP 12 + CON")
	eq(Catalog.pc("barbarian", 5).max_hp, 14 + 4 * 9, "lv5 HP")
	eq(Catalog.pc("barbarian", 5).speed, 8, "fast movement")
	eq(Creature.new(s, 0).resources.rage, 2, "2 rages")
	eq(Creature.new(Catalog.barbarian(3), 0).resources.rage, 3, "3 rages at lv3")


func test_rage() -> void:
	var cb := setup()
	var b := spawn(cb, Catalog.barbarian(1), 0, Vector2i(1, 1))
	var g := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(2, 1))
	begin(cb, b)
	check(ClassFeatures.rage(cb, b), "rage")
	check(b.has_effect("raging"), "raging")
	eq(b.resources.rage, 1, "rage spent")
	check(not b.bonus_available, "bonus action used")
	eq(Damage.modify(b, 9, "slashing"), 4, "half slashing")
	eq(Damage.modify(b, 9, "fire"), 9, "fire not resisted")
	eq(ClassFeatures.save_adv(b, STR), 1, "STR save advantage")
	# 근력 공격 피해 +2
	var w := b.melee_weapon()
	var info := cb.attack_info(b, g, w)
	var bd := ClassFeatures.bonus_damage(cb, b, g, w, info, false)
	eq(bd.amount, 2, "rage damage")
	var thrown := cb.attack_info(b, g, b.stats.weapons[1])
	eq(ClassFeatures.bonus_damage(cb, b, g, b.stats.weapons[1], thrown, false).amount, 2, "thrown handaxe uses STR")


func test_rage_ends_without_attack() -> void:
	var cb := setup()
	var b := spawn(cb, Catalog.barbarian(1), 0, Vector2i(1, 1))
	spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(5, 1))
	begin(cb, b)
	ClassFeatures.rage(cb, b)
	ClassFeatures.on_turn_end(cb, b)
	check(b.has_effect("raging"), "lasts through the turn it started")
	b.start_turn_reset()
	ClassFeatures.on_turn_end(cb, b)
	check(not b.has_effect("raging"), "ends after a turn without attacking")


func test_rage_kept_by_attacking() -> void:
	var cb := setup()
	var b := spawn(cb, Catalog.barbarian(1), 0, Vector2i(1, 1))
	var g := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(2, 1))
	g.stats.max_hp = 999
	g.hp = 999
	begin(cb, b)
	ClassFeatures.rage(cb, b)
	b.start_turn_reset()
	check(cb.attack(b, g, b.melee_weapon()), "attack")
	ClassFeatures.on_turn_end(cb, b)
	check(b.has_effect("raging"), "attack roll keeps rage")


func test_rage_ends_when_downed() -> void:
	var cb := setup()
	var b := spawn(cb, Catalog.barbarian(1), 0, Vector2i(1, 1))
	begin(cb, b)
	ClassFeatures.rage(cb, b)
	cb._deal(b, 100, "fire", false, "")
	check(not b.has_effect("raging"), "downed ends rage")


func test_reckless_attack() -> void:
	var cb := setup()
	var b := spawn(cb, Catalog.barbarian(2), 0, Vector2i(1, 1))
	var g := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(2, 1))
	begin(cb, b)
	eq(cb.attack_info(b, g, b.melee_weapon()).adv, 0, "no advantage before")
	check(ClassFeatures.reckless(cb, b), "go reckless")
	eq(cb.attack_info(b, g, b.melee_weapon()).adv, 1, "advantage on STR attack")
	eq(cb.attack_info(g, b, g.melee_weapon()).adv, 1, "enemies get advantage too")
	b.effects.clear()
	b.once_per_turn["attacked"] = true
	check(not ClassFeatures.reckless(cb, b), "only before the first attack")


func test_danger_sense() -> void:
	var b := Creature.new(Catalog.barbarian(2), 0)
	eq(ClassFeatures.save_adv(b, DEX), 1, "DEX save advantage")
	eq(ClassFeatures.save_adv(Creature.new(Catalog.barbarian(1), 0), DEX), 0, "not at lv1")


func test_frenzy() -> void:
	var cb := setup()
	var b := spawn(cb, Catalog.barbarian(3), 0, Vector2i(1, 1))
	var g := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(2, 1))
	begin(cb, b)
	ClassFeatures.rage(cb, b)
	ClassFeatures.reckless(cb, b)
	var w := b.melee_weapon()
	var info := cb.attack_info(b, g, w)
	var first := ClassFeatures.bonus_damage(cb, b, g, w, info, false)
	check(first.amount >= 2 + 2 and first.amount <= 2 + 12, "rage + 2d6 frenzy")
	eq(ClassFeatures.bonus_damage(cb, b, g, w, info, false).amount, 2, "frenzy once per turn")


func test_rage_short_rest() -> void:
	var h := HeroState.fresh("barbarian", 1)
	h.xp = 900
	h.resources["rage"] = 0
	h.finish_short_rest()
	eq(h.resources.rage, 1, "short rest returns one rage")
	h.long_rest()
	eq(h.make_creature().resources.rage, 3, "long rest returns all")


# --- 로그 (rules 7.8) ---

func test_rogue_sheet() -> void:
	var s := Catalog.rogue(1)
	eq(s.ac, 14, "leather 11 + DEX 3")
	eq(s.max_hp, 10, "lv1 HP 8 + CON")
	eq(s.initiative_bonus, 5, "Alert: DEX 3 + PB 2")
	var c := Creature.new(s, 0)
	eq(c.skill_bonus("stealth"), 3 + 4, "expertise doubles PB")
	eq(c.skill_bonus("acrobatics"), 3 + 2, "plain proficiency")
	eq(ClassFeatures.sneak_dice(1), 1, "1d6")
	eq(ClassFeatures.sneak_dice(3), 2, "2d6")
	eq(ClassFeatures.sneak_dice(5), 3, "3d6")


func test_sneak_attack_needs_ally_or_advantage() -> void:
	var cb := setup()
	var r := spawn(cb, Catalog.rogue(1), 0, Vector2i(1, 1))
	var g := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(2, 1))
	begin(cb, r)
	var w := r.melee_weapon()
	check(not ClassFeatures.can_sneak(cb, r, g, w, 0), "alone, no advantage: no sneak attack")
	check(ClassFeatures.can_sneak(cb, r, g, w, 1), "advantage: sneak attack")
	check(not ClassFeatures.can_sneak(cb, r, g, w, -1), "disadvantage: none")
	spawn(cb, Catalog.fighter(1), 0, Vector2i(3, 1))
	check(ClassFeatures.can_sneak(cb, r, g, w, 0), "ally next to target")
	check(not ClassFeatures.can_sneak(cb, r, g, Catalog.weapon("greatsword"), 1), "not with a heavy weapon")
	var info := cb.attack_info(r, g, w)
	var bd := ClassFeatures.bonus_damage(cb, r, g, w, info, false)
	check(bd.amount >= 1 and bd.amount <= 6, "1d6 extra")
	eq(ClassFeatures.bonus_damage(cb, r, g, w, info, false).amount, 0, "once per turn")


func test_cunning_action_and_steady_aim() -> void:
	var cb := setup()
	var r := spawn(cb, Catalog.rogue(3), 0, Vector2i(1, 1))
	var g := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(6, 1))
	begin(cb, r)
	check(ClassFeatures.use(cb, r, "steady_aim"), "steady aim")
	eq(r.movement_left, 0, "can't move after aiming")
	eq(cb.attack_info(r, g, r.stats.weapons[1]).adv, 1, "advantage on the shot")
	r.start_turn_reset()
	r.effects.clear()
	ClassFeatures.use(cb, r, "cunning_dash")
	eq(r.movement_left, 12, "bonus dash doubles movement")
	check(cb.move(r, Vector2i(2, 1)), "moves")
	check(not ClassFeatures.steady_aim(cb, r), "no steady aim after moving")


func test_uncanny_dodge_and_trip() -> void:
	var cb := setup()
	var r := spawn(cb, Catalog.pc("rogue", 5), 0, Vector2i(1, 1))
	var g := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(2, 1))
	begin(cb, r)
	var gw := g.melee_weapon()
	var gi := cb.attack_info(g, r, gw)
	eq(ClassFeatures.on_hit_taken(cb, g, r, gw, gi, 9), 4, "uncanny dodge halves")
	eq(ClassFeatures.on_hit_taken(cb, g, r, gw, gi, 9), 9, "only one reaction")
	ClassFeatures.use(cb, r, "cs_trip")
	var w := r.stats.weapons[1]
	var info := cb.attack_info(r, g, w)
	info.adv = 1
	var bd := ClassFeatures.bonus_damage(cb, r, g, w, info, false)
	check(bd.trip, "trip spends a die")
	check(bd.amount >= 2 and bd.amount <= 12, "2d6 left of 3d6")
	check(not r.has_effect("cs_trip"), "trip used up")


# --- 몽크 (rules 7.9) ---

func test_monk_sheet() -> void:
	var s := Catalog.monk(1)
	eq(s.ac, 15, "10 + DEX 3 + WIS 2")
	eq(s.speed, 6, "lv1 speed")
	eq(Catalog.monk(2).speed, 8, "unarmored movement")
	var fist := s.weapons[0]
	eq(fist.dice_sides, 6, "martial arts d6")
	eq(Catalog.pc("monk", 5).weapons[0].dice_sides, 8, "d8 at lv5")
	check(fist.finesse, "dexterous attacks")
	eq(Creature.new(Catalog.monk(3), 0).resources.focus, 3, "focus = level")
	check(not Creature.new(s, 0).resources.has("focus"), "no focus at lv1")


func test_flurry_of_blows() -> void:
	var cb := setup()
	var m := spawn(cb, Catalog.monk(3), 0, Vector2i(1, 1))
	var g := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(2, 1))
	g.stats.max_hp = 999
	g.hp = 999
	begin(cb, m)
	check(cb.attack(m, g, m.stats.weapons[1]), "attack action with spear")
	check(ClassFeatures.use(cb, m, "flurry"), "flurry")
	eq(m.resources.focus, 2, "1 focus spent")
	eq(m.bonus_attacks, 2, "two strikes")
	check(cb.can_attack(m), "can still attack")
	check(cb.attack(m, g, m.stats.weapons[1]), "strike 1 (uses fist)")
	check(cb.attack(m, g, m.stats.weapons[1]), "strike 2")
	check(not cb.can_attack(m), "no attacks left")
	check(not m.bonus_available, "bonus action used")


func test_martial_arts_bonus_strike() -> void:
	var cb := setup()
	var m := spawn(cb, Catalog.monk(1), 0, Vector2i(1, 1))
	var g := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(2, 1))
	begin(cb, m)
	check(ClassFeatures.use(cb, m, "martial_bonus"), "bonus strike")
	eq(m.bonus_attacks, 1, "one strike")
	check(cb.attack(m, g, m.stats.weapons[0]), "strike")
	check(m.action_available, "action still free")


func test_deflect_attacks() -> void:
	var cb := setup()
	var m := spawn(cb, Catalog.monk(3), 0, Vector2i(1, 1))
	var g := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(2, 1))
	begin(cb, m)
	var gw := g.melee_weapon()
	var left := ClassFeatures.on_hit_taken(cb, g, m, gw, cb.attack_info(g, m, gw), 30)
	check(left >= 30 - 10 - 6 and left <= 30 - 1 - 6, "reduced by 1d10 + DEX 3 + level 3")
	check(not m.reaction_available, "reaction used")


func test_stunning_strike() -> void:
	var cb := setup()
	var m := spawn(cb, Catalog.pc("monk", 5), 0, Vector2i(1, 1))
	var g := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(2, 1))
	g.stats.max_hp = 999
	g.hp = 999
	begin(cb, m)
	ClassFeatures.use(cb, m, "stun")
	var fp: int = m.resources.focus
	ClassFeatures.after_hit(cb, m, g, m.stats.weapons[0], {}, {})
	eq(m.resources.focus, fp - 1, "focus spent")
	check(g.has_effect("stunned") or g.has_effect("staggered"), "stunned or staggered")
	if g.has_effect("stunned"):
		check(not g.can_act(), "stunned can't act")
		eq(g.speed(), 0, "speed 0")
	ClassFeatures.after_hit(cb, m, g, m.stats.weapons[0], {}, {})
	eq(m.resources.focus, fp - 1, "once per turn")


func test_open_hand_topple() -> void:
	var cb := setup()
	var m := spawn(cb, Catalog.monk(3), 0, Vector2i(1, 1))
	var g := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(2, 1))
	begin(cb, m)
	cb.dice.forced = [1]
	ClassFeatures.after_hit(cb, m, g, m.stats.weapons[0], {"flurry": true}, {})
	check(g.has_condition("prone"), "topple on failed save")
	ClassFeatures.use(cb, m, "open_hand")
	eq(ClassFeatures.open_hand(m), "push", "cycle to push")


func test_uncanny_metabolism() -> void:
	var cb := setup()
	var m := spawn(cb, Catalog.monk(2), 0, Vector2i(1, 1))
	spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(5, 1))
	m.resources["focus"] = 0
	m.hp = 5
	ClassFeatures.on_initiative(cb, m)
	eq(m.resources.focus, 2, "focus back")
	check(m.hp > 5, "healed")
	eq(m.resources.metabolism, 0, "once per long rest")


# --- 팔라딘 (rules 7.10) ---

func test_paladin_sheet() -> void:
	var s := Catalog.paladin(1)
	eq(s.ac, 18, "chain mail + shield")
	eq(Catalog.paladin(2).ac, 19, "defense style")
	eq(s.max_hp, 12, "lv1 HP")
	var c := Creature.new(s, 0)
	eq(c.resources.lay_on_hands, 5, "pool 5 x level")
	eq(c.resources.slot1, 2, "2 first-level slots")
	eq(Creature.new(Catalog.pc("paladin", 5), 0).resources.slot2, 2, "lv5 second-level slots")
	eq(c.spell_dc(), 8 + 2 + 2, "CHA spell DC")


func test_lay_on_hands() -> void:
	var cb := setup()
	var p := spawn(cb, Catalog.paladin(3), 0, Vector2i(1, 1))
	var f := spawn(cb, Catalog.fighter(1), 0, Vector2i(2, 1))
	begin(cb, p)
	f.hp = 4
	check(Spells.cast(cb, p, "lay_on_hands", f), "lay on hands")
	eq(f.hp, 12, "healed to full")
	eq(p.resources.lay_on_hands, 15 - 8, "pool spent by the amount healed")
	check(not p.bonus_available, "bonus action")


func test_divine_smite() -> void:
	var cb := setup()
	var p := spawn(cb, Catalog.paladin(2), 0, Vector2i(1, 1))
	var z := spawn(cb, Catalog.monster("zombie"), 1, Vector2i(2, 1))
	z.stats.max_hp = 999
	z.hp = 999
	begin(cb, p)
	check(Spells.cast(cb, p, "divine_smite"), "toggle on")
	check(p.toggles.divine_smite, "smite armed")
	var info := cb.attack_info(p, z, p.melee_weapon())
	ClassFeatures.after_hit(cb, p, z, p.melee_weapon(), info, {"crit": false})
	eq(p.resources.free_smite, 0, "free smite used first")
	check(z.hp <= 999 - 3 and z.hp >= 999 - 24, "3d8 radiant vs undead")
	check(not p.bonus_available, "uses the bonus action")
	var before := z.hp
	ClassFeatures.after_hit(cb, p, z, p.melee_weapon(), info, {"crit": false})
	eq(z.hp, before, "no second smite this turn")


func test_sacred_weapon() -> void:
	var cb := setup()
	var p := spawn(cb, Catalog.paladin(3), 0, Vector2i(1, 1))
	var g := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(2, 1))
	begin(cb, p)
	var before: int = cb.attack_info(p, g, p.melee_weapon()).bonus
	check(Spells.cast(cb, p, "sacred_weapon"), "sacred weapon")
	eq(cb.attack_info(p, g, p.melee_weapon()).bonus, before + 2, "adds CHA")
	check(p.action_available, "doesn't use the action")
	eq(p.resources.channel, 1, "channel spent")


func test_heroism_and_protection() -> void:
	var cb := setup()
	var p := spawn(cb, Catalog.paladin(3), 0, Vector2i(1, 1))
	var sk := spawn(cb, Catalog.monster("skeleton"), 1, Vector2i(2, 1))
	begin(cb, p)
	check(Spells.cast(cb, p, "protection_from_evil", p), "protection")
	eq(cb.attack_info(sk, p, sk.melee_weapon()).adv, -1, "undead attack at disadvantage")
	p.start_turn_reset()
	check(Spells.cast(cb, p, "heroism", p), "heroism replaces protection")
	eq(cb.attack_info(sk, p, sk.melee_weapon()).adv, 0, "protection ended with concentration")
	ClassFeatures.on_turn_start(cb, p)
	eq(p.temp_hp, 2, "temp HP = CHA")


# --- 레인저 (rules 7.11) ---

func test_ranger_sheet() -> void:
	var s := Catalog.ranger(1)
	eq(s.ac, 15, "studded leather 12 + DEX 3")
	var c := Creature.new(s, 0)
	eq(c.resources.free_mark, 2, "2 free hunter's marks")
	var cb := setup()
	var r := spawn(cb, Catalog.ranger(2), 0, Vector2i(1, 1))
	var g := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(6, 1))
	eq(cb.attack_info(r, g, r.stats.weapons[0]).bonus, 3 + 2 + 2, "archery +2")


func test_hunters_mark() -> void:
	var cb := setup()
	var r := spawn(cb, Catalog.ranger(1), 0, Vector2i(1, 1))
	var g := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(6, 1))
	var g2 := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(6, 3))
	g.stats.max_hp = 999
	g.hp = 999
	begin(cb, r)
	check(Spells.cast(cb, r, "hunters_mark", g), "mark")
	eq(r.resources.free_mark, 1, "free cast used")
	eq(r.resources.slot1, 2, "no slot spent")
	eq(r.concentration, "hunters_mark", "concentrating")
	var info := cb.attack_info(r, g, r.stats.weapons[0])
	ClassFeatures.after_hit(cb, r, g, r.stats.weapons[0], info, {"crit": false})
	check(g.hp < 999 and g.hp >= 999 - 6, "1d6 force")
	# 표식한 적이 쓰러지면 옮길 수 있음
	cb._deal(g, 9999, "force", false, "")
	check(Spells.knows(r, "mark_move"), "can move the mark")
	r.start_turn_reset()
	check(Spells.cast(cb, r, "mark_move", g2), "moved")
	check(not g2.find_effect("marked").is_empty(), "new target marked")
	check(not Spells.knows(r, "mark_move"), "moving used up")


func test_colossus_slayer() -> void:
	var cb := setup()
	var r := spawn(cb, Catalog.ranger(3), 0, Vector2i(1, 1))
	var g := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(6, 1))
	begin(cb, r)
	var w := r.stats.weapons[0]
	var info := cb.attack_info(r, g, w)
	eq(ClassFeatures.bonus_damage(cb, r, g, w, info, false).amount, 0, "unhurt target: none")
	g.hp -= 1
	var bd := ClassFeatures.bonus_damage(cb, r, g, w, info, false)
	check(bd.amount >= 1 and bd.amount <= 8, "1d8 on a hurt target")
	eq(ClassFeatures.bonus_damage(cb, r, g, w, info, false).amount, 0, "once per turn")


# --- 위저드 (rules 7.12) ---

func test_wizard_sheet() -> void:
	var s := Catalog.wizard(1)
	eq(s.ac, 14, "mage armor 13 + DEX 1")
	eq(s.max_hp, 8, "lv1 HP 6 + CON")
	var c := Creature.new(s, 0)
	eq(c.spell_dc(), 8 + 2 + 3, "INT spell DC")
	eq(c.resources.slot1, 2, "2 slots")
	eq(Creature.new(Catalog.pc("wizard", 5), 0).resources.slot3, 2, "lv5 3rd-level slots")


func test_fire_bolt_and_cantrip_scaling() -> void:
	var cb := setup()
	var w := spawn(cb, Catalog.wizard(1), 0, Vector2i(1, 1))
	var g := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(6, 1))
	begin(cb, w)
	var sw := Spells.spell_weapon(w, "fire_bolt", 0)
	eq(sw.dice_count, 1, "1d10")
	eq(Spells.spell_weapon(Creature.new(Catalog.pc("wizard", 5), 0), "fire_bolt", 0).dice_count, 2, "2d10 at lv5")
	eq(cb.attack_info(w, g, sw).bonus, 3 + 2, "spell attack = INT + PB")
	check(Spells.cast(cb, w, "fire_bolt", g), "cast fire bolt")
	check(not w.action_available, "uses the action")


func test_magic_missile_never_misses() -> void:
	var cb := setup()
	var w := spawn(cb, Catalog.wizard(1), 0, Vector2i(1, 1))
	var g := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(6, 1))
	g.stats.max_hp = 999
	g.hp = 999
	begin(cb, w)
	check(Spells.cast(cb, w, "magic_missile", g), "cast")
	check(g.hp <= 999 - 6 and g.hp >= 999 - 15, "3 darts of 1d4+1")
	eq(w.resources.slot1, 1, "slot spent")


func test_fireball_hits_area_and_allies() -> void:
	var cb := Combat.new(CombatGrid.new(14, 8), Dice.new(1))
	var w := spawn(cb, Catalog.pc("wizard", 5), 0, Vector2i(1, 1))
	var ally := spawn(cb, Catalog.fighter(1), 0, Vector2i(9, 2))
	var g1 := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(10, 2))
	var g2 := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(11, 4))
	var far := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(10, 7))
	begin(cb, w)
	var hit := Spells.area_targets(cb, w, "fireball", g1)
	check(hit.has(g1) and hit.has(g2), "both goblins inside")
	check(hit.has(ally), "ally caught too")
	check(not hit.has(far), "5 away is outside")
	check(not hit.has(w), "caster far away is safe")
	check(Spells.describe(cb, w, "fireball", g1).contains("아군"), "warns about allies")
	check(Spells.cast(cb, w, "fireball", g1), "cast")
	eq(w.resources.slot3, 1, "3rd-level slot")


func test_burning_hands_cone() -> void:
	var cb := setup()
	var w := spawn(cb, Catalog.wizard(1), 0, Vector2i(1, 2))
	var front := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(2, 2))
	var behind := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(0, 2))
	var diag := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(3, 3))
	var hit := Spells.area_targets(cb, w, "burning_hands", front)
	check(hit.has(front), "target in cone")
	check(hit.has(diag), "slightly off-axis in cone")
	check(not hit.has(behind), "behind is outside")


func test_thunderwave_pushes() -> void:
	var cb := setup()
	var w := spawn(cb, Catalog.wizard(1), 0, Vector2i(2, 2))
	var g := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(3, 2))
	g.stats.max_hp = 999
	g.hp = 999
	begin(cb, w)
	cb.dice.forced = [1]
	check(Spells.cast(cb, w, "thunderwave"), "cast")
	eq(g.cell, Vector2i(5, 2), "pushed 2")


func test_shield_reaction() -> void:
	var cb := setup()
	var w := spawn(cb, Catalog.wizard(1), 0, Vector2i(1, 1))
	check(ClassFeatures.try_shield(cb, w, 16, 14), "blocks a hit that +5 would stop")
	eq(w.ac(), 19, "AC +5")
	eq(w.resources.slot1, 1, "slot spent")
	check(not ClassFeatures.try_shield(cb, w, 16, 14), "one reaction")
	var w2 := spawn(cb, Catalog.wizard(1), 0, Vector2i(3, 3))
	check(not ClassFeatures.try_shield(cb, w2, 25, 14), "doesn't waste a slot on a sure hit")


func test_arcane_recovery() -> void:
	var h := HeroState.fresh("wizard", 1)
	h.xp = 6500
	var full := h.make_creature().resources
	h.resources = {"slot1": 4, "slot2": 3, "slot3": 0}
	h.finish_short_rest()
	eq(h.resources.slot3, 1, "recovers a 3rd-level slot (budget 3)")
	eq(h.resources.arcane_recovery, 0, "once per long rest")
	h.resources["slot3"] = 0
	h.finish_short_rest()
	eq(h.resources.slot3, 0, "not again")
	check(full.has("arcane_recovery"), "starts with it")


# --- 소서러 (rules 7.13) ---

func test_sorcerer_sheet() -> void:
	var s1 := Catalog.sorcerer(1)
	eq(s1.ac, 14, "L1 Mage Armor 13+1")
	eq(s1.max_hp, 8, "L1 HP")
	var s3 := Catalog.sorcerer(3)
	eq(s3.ac, 14, "L3 Draconic Resilience 10+1+3")
	eq(s3.max_hp, 8 + 12 + 3, "L3 HP with resilience")
	check(s3.spells.has("chromatic_orb"), "draconic spell")
	var c := Creature.new(Catalog.pc("sorcerer", 5), 0)
	eq(c.resources.sp, 5, "sorcery points = level")
	eq(c.resources.innate, 2, "innate sorcery twice")


func test_innate_sorcery() -> void:
	var cb := setup()
	var s := spawn(cb, Catalog.sorcerer(1), 0, Vector2i(1, 1))
	var g := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(4, 1))
	begin(cb, s)
	var dc := s.spell_dc()
	ClassFeatures.use(cb, s, "innate_sorcery")
	check(s.has_effect("innate_sorcery"), "active")
	eq(s.spell_dc(), dc + 1, "DC +1")
	eq(s.resources.innate, 1, "one use spent")
	check(not s.bonus_available, "bonus action used")
	var info := cb.attack_info_from(s, s.cell, g, Spells.spell_weapon(s, "fire_bolt", 0))
	check(info.adv > 0, "spell attack has advantage")


func test_font_of_magic() -> void:
	var cb := setup()
	var s := spawn(cb, Catalog.sorcerer(3), 0, Vector2i(1, 1))
	begin(cb, s)
	var l2: int = s.resources.slot2
	ClassFeatures.use(cb, s, "make_slot:2")
	eq(s.resources.slot2, l2 + 1, "made a 2nd-level slot")
	eq(s.resources.sp, 0, "3 points spent")
	ClassFeatures.use(cb, s, "burn_slot:1")
	eq(s.resources.sp, 1, "slot back to a point")


func test_quickened_spell() -> void:
	var cb := setup()
	var s := spawn(cb, Catalog.sorcerer(2), 0, Vector2i(1, 1))
	var g := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(4, 1))
	begin(cb, s)
	ClassFeatures.use(cb, s, "quicken")
	check(Spells.cast(cb, s, "fire_bolt", g), "cast quickened")
	check(s.action_available, "action still free")
	check(not s.bonus_available, "bonus used instead")
	eq(s.resources.sp, 0, "2 points spent")
	check(not s.toggles.get("quicken", false), "toggle consumed")


func test_careful_spell() -> void:
	var cb := setup()
	var s := spawn(cb, Catalog.sorcerer(2), 0, Vector2i(1, 2))
	var ally := spawn(cb, Catalog.fighter(1), 0, Vector2i(2, 1))
	var g := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(2, 2))
	begin(cb, s)
	var hp := ally.hp
	ClassFeatures.use(cb, s, "careful")
	check(Spells.cast(cb, s, "thunderwave"), "cast")
	eq(ally.hp, hp, "ally untouched")
	eq(s.resources.sp, 1, "1 point spent")


func test_sorcerous_restoration() -> void:
	var h := HeroState.fresh("sorcerer", 1)
	h.xp = 6500
	h.resources = h.make_creature().resources.duplicate()
	h.resources["sp"] = 0
	h.finish_short_rest()
	eq(h.resources.sp, 2, "regains half level")
	h.resources["sp"] = 0
	h.finish_short_rest()
	eq(h.resources.sp, 0, "once per long rest")


# --- 워락 (rules 7.14) ---

func test_warlock_sheet() -> void:
	eq(Catalog.warlock(1).ac, 14, "Armor of Shadows 13+1")
	eq(Catalog.pc("warlock", 5).max_hp, 38, "L5 HP")
	var c := Creature.new(Catalog.warlock(3), 0)
	eq(c.resources.get("slot1", 0), 0, "no 1st-level pact slots at L3")
	eq(c.resources.slot2, 2, "two 2nd-level pact slots")


func test_eldritch_blast() -> void:
	var cb := setup()
	var w := spawn(cb, Catalog.pc("warlock", 5), 0, Vector2i(1, 1))
	eq(Spells.dmg_beams(w, "eldritch_blast", 0), 2, "two beams at L5")
	eq(Spells.dmg_dice(w, "eldritch_blast", 0), 1, "1d10 each")
	check(Spells.spell_weapon(w, "eldritch_blast", 0).add_mod, "Agonizing Blast adds CHA")
	check(not Spells.spell_weapon(Creature.new(Catalog.warlock(1), 0), "eldritch_blast", 0).add_mod, "not at L1")


func test_hex() -> void:
	var cb := setup()
	var w := spawn(cb, Catalog.warlock(1), 0, Vector2i(1, 1))
	var g := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(4, 1))
	g.stats.max_hp = 999
	g.hp = 999
	begin(cb, w)
	check(Spells.cast(cb, w, "hex", g), "cast hex")
	eq(w.concentration, "hex", "concentrating")
	check(g.has_effect("marked"), "cursed")
	var hp := g.hp
	cb.dice.forced = [4]
	ClassFeatures.after_hit(cb, w, g, Spells.spell_weapon(w, "eldritch_blast", 0), {"mode": "ranged"}, {})
	eq(g.hp, hp - 4, "1d6 necrotic")
	g.hp = 0
	ClassFeatures.on_creature_down(cb, g)
	check(Spells.knows(w, "mark_move"), "can move the curse")


func test_pact_magic_short_rest() -> void:
	var h := HeroState.fresh("warlock", 1)
	h.resources = h.make_creature().resources.duplicate()
	h.resources["slot1"] = 0
	h.finish_short_rest()
	eq(h.resources.slot1, 1, "pact slot back on short rest")


func test_hellish_rebuke() -> void:
	var cb := setup()
	var w := spawn(cb, Catalog.warlock(1), 0, Vector2i(1, 1))
	var g := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(2, 1))
	g.stats.max_hp = 999
	g.hp = 999
	ClassFeatures.on_damaged(cb, g, w)
	check(g.hp < 999, "rebuke burns the attacker")
	check(not w.reaction_available, "reaction spent")
	eq(w.resources.slot1, 0, "slot spent")


func test_dark_ones_blessing() -> void:
	var cb := setup()
	var w := spawn(cb, Catalog.warlock(3), 0, Vector2i(1, 1))
	var g := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(2, 1))
	g.hp = 0
	ClassFeatures.on_kill(cb, w, g)
	eq(w.temp_hp, 6, "CHA 3 + level 3")


func test_chill_touch_blocks_healing() -> void:
	var cb := setup()
	var w := spawn(cb, Catalog.warlock(1), 0, Vector2i(1, 1))
	var g := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(2, 1))
	g.hp = 1
	Spells._rider(cb, w, g, "no_heal")
	eq(Damage.heal(g, 5), 0, "no healing")


# --- 바드 (rules 7.15) ---

func test_bard_sheet() -> void:
	var s := Catalog.bard(1)
	eq(s.ac, 13, "leather 11+2")
	eq(s.max_hp, 9, "L1 HP")
	var c := Creature.new(Catalog.bard(2), 0)
	eq(c.resources.bardic_inspiration, 3, "CHA mod uses")
	eq(c.skill_bonus("athletics"), -1 + 1, "Jack of All Trades half PB")
	eq(c.skill_bonus("persuasion"), 3 + 4, "expertise")


func test_bardic_inspiration_rescues_attack() -> void:
	var cb := setup()
	var b := spawn(cb, Catalog.bard(1), 0, Vector2i(1, 1))
	var f := spawn(cb, Catalog.fighter(1), 0, Vector2i(2, 1))
	var g := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(3, 1))
	begin(cb, b)
	check(Spells.target_error(cb, b, "bardic_inspiration", b) != "", "not on self")
	check(Spells.cast(cb, b, "bardic_inspiration", f), "inspire")
	check(f.has_effect("inspired"), "has the die")
	eq(b.resources.bardic_inspiration, 2, "use spent")
	eq(ClassFeatures.use_inspiration(cb, f, 5, 15), 0, "hopeless roll keeps the die")
	cb.dice.forced = [4]
	eq(ClassFeatures.use_inspiration(cb, f, 12, 15), 4, "adds the die")
	check(not f.has_effect("inspired"), "spent")
	check(g != null, "")


func test_cutting_words() -> void:
	var cb := setup()
	var b := spawn(cb, Catalog.bard(3), 0, Vector2i(1, 1))
	var f := spawn(cb, Catalog.fighter(1), 0, Vector2i(2, 1))
	var g := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(3, 1))
	eq(ClassFeatures.cutting_words(cb, g, f, 25, 16), 0, "sure hit: don't waste it")
	cb.dice.forced = [5]
	eq(ClassFeatures.cutting_words(cb, g, f, 17, 16), 5, "cuts the roll")
	check(not b.reaction_available, "reaction spent")


func test_faerie_fire() -> void:
	var cb := setup()
	var b := spawn(cb, Catalog.bard(1), 0, Vector2i(1, 1))
	var f := spawn(cb, Catalog.fighter(1), 0, Vector2i(3, 2))
	var g := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(4, 1))
	begin(cb, b)
	cb.dice.forced = [1]
	check(Spells.cast(cb, b, "faerie_fire", g), "cast")
	check(g.has_effect("outlined"), "outlined")
	eq(b.concentration, "faerie_fire", "concentrating")
	var info := cb.attack_info(f, g, f.stats.weapons[0])
	check(info.adv_src.has("요정불"), "attacks have advantage")


func test_mass_healing_word() -> void:
	var cb := setup()
	var b := spawn(cb, Catalog.pc("bard", 5), 0, Vector2i(1, 1))
	var f := spawn(cb, Catalog.fighter(1), 0, Vector2i(2, 1))
	var c := spawn(cb, Catalog.cleric(1), 0, Vector2i(3, 1))
	begin(cb, b)
	f.hp = 3
	c.hp = 1
	check(Spells.cast(cb, b, "mass_healing_word"), "cast")
	check(f.hp > 3 and c.hp > 1, "both healed")
	eq(b.resources.slot3, 1, "3rd-level slot")


func test_font_of_inspiration() -> void:
	var h := HeroState.fresh("bard", 1)
	h.xp = 6500
	h.resources = h.make_creature().resources.duplicate()
	h.resources["bardic_inspiration"] = 0
	h.finish_short_rest()
	eq(h.resources.bardic_inspiration, 4, "back on short rest at L5 (CHA 19)")


# --- 드루이드 (rules 7.16) ---

func test_druid_sheet() -> void:
	var s := Catalog.druid(1)
	eq(s.ac, 15, "hide 12+1 + shield 2")
	eq(s.max_hp, 10, "L1 HP")
	check(not s.has_feature("wild_shape"), "no wild shape at L1")
	var c := Creature.new(Catalog.druid(2), 0)
	eq(c.resources.wild_shape, 2, "two uses")


func test_wild_shape() -> void:
	var cb := setup()
	var d := spawn(cb, Catalog.druid(2), 0, Vector2i(1, 1))
	begin(cb, d)
	var hp := d.hp
	ClassFeatures.use(cb, d, "wild_shape")
	check(d.true_stats != null, "shaped")
	eq(d.stats.model, "animals/wolf", "wolf model")
	eq(d.stats.weapons[0].id, "bite", "bites")
	eq(d.stats.scores[Rules.Ability.WIS], 17, "keeps WIS")
	eq(d.hp, hp, "keeps HP")
	eq(d.temp_hp, 2, "temp HP = level")
	eq(d.resources.wild_shape, 1, "use spent")
	eq(d.movement_left, 8, "wolf speed this turn")
	check(d.stats.has_feature("pack_tactics"), "pack tactics")
	check(Spells.why_not(cb, d, "cure_wounds") != "", "no spells while shaped")
	check(not Catalog.druid(2).spells.is_empty(), "base sheet untouched")
	ClassFeatures.on_incapacitated(cb, d)
	check(d.true_stats == null, "reverts when incapacitated")
	eq(d.stats.model, "kaykit/Mage", "back to druid")


func test_wild_shape_short_rest() -> void:
	var h := HeroState.fresh("druid", 1)
	h.xp = 300
	h.resources = h.make_creature().resources.duplicate()
	h.resources["wild_shape"] = 0
	h.finish_short_rest()
	eq(h.resources.wild_shape, 1, "regains one")


func test_lands_aid() -> void:
	var cb := setup()
	var d := spawn(cb, Catalog.druid(3), 0, Vector2i(1, 1))
	var f := spawn(cb, Catalog.fighter(1), 0, Vector2i(3, 2))
	var g := spawn(cb, Catalog.monster("goblin_warrior"), 1, Vector2i(4, 1))
	g.stats.max_hp = 999
	g.hp = 999
	f.hp = 2
	begin(cb, d)
	check(Spells.cast(cb, d, "lands_aid", g), "cast")
	check(g.hp < 999, "thorns hurt the goblin")
	check(f.hp > 2, "flowers heal the fighter")
	eq(d.resources.wild_shape, 1, "uses wild shape")


# --- 레벨업 고르기 (rules 7.17) ---

func test_default_asi_matches_old_build() -> void:
	eq(Catalog.pc("rogue", 4).scores[DEX], 19, "rogue default DEX +2")
	eq(Catalog.pc("rogue", 4).ac, 15, "AC follows DEX")
	eq(Catalog.pc("paladin", 4).scores[Rules.Ability.CHA], 16, "paladin default CHA +2")
	eq(Catalog.pc("druid", 4).ac, 15, "druid hide caps DEX")


func test_asi_choice_changes_stats() -> void:
	var con := {4: {"asi": {Rules.Ability.CON: 2}}}
	var b := Catalog.pc("barbarian", 4, con)
	eq(b.scores[STR], 17, "STR untouched")
	eq(b.max_hp, Catalog.build("barbarian", 4).max_hp + 4, "CON +1 mod → +level HP")
	eq(b.ac, Catalog.build("barbarian", 4).ac + 1, "unarmored defense uses CON")
	var dex := Catalog.pc("monk", 4, {4: {"asi": {DEX: 1, Rules.Ability.WIS: 1}}})
	eq(dex.scores[DEX], 18, "+1 DEX")
	check(LevelUp.valid_asi(PackedInt32Array([8, 13, 14, 10, 12, 19]), {Rules.Ability.CHA: 1, DEX: 1}), "+1/+1 ok")
	check(not LevelUp.valid_asi(PackedInt32Array([8, 13, 14, 10, 12, 19]), {Rules.Ability.CHA: 2}), "can't pass 20")
	check(not LevelUp.valid_asi(PackedInt32Array([8, 13, 14, 10, 12, 15]), {Rules.Ability.CHA: 1}), "must spend 2")


func test_spell_pool() -> void:
	var pool := LevelUp.spell_pool("wizard", 2, {})
	check(pool.has("chill_touch"), "wizard can learn chill touch")
	check(not pool.has("fire_bolt"), "already known")
	check(not pool.has("scorching_ray"), "builder grants it later")
	check(LevelUp.spell_pool("fighter", 3, {}).is_empty(), "fighter has none")
	var s := Catalog.pc("wizard", 2, {2: {"spell": "chill_touch"}})
	check(s.spells.has("chill_touch"), "chosen spell known")
	check(not LevelUp.spell_pool("wizard", 3, {2: {"spell": "chill_touch"}}).has("chill_touch"), "not twice")
	check(not Catalog.pc("wizard", 1, {2: {"spell": "chill_touch"}}).spells.has("chill_touch"), "not before that level")


func test_pending_choices() -> void:
	var h := HeroState.fresh("sorcerer", 1)
	eq(h.pending_choices().size(), 0, "nothing at L1")
	h.xp = 2700  # 4레벨
	var p := h.pending_choices()
	check(p.size() >= 1, "spell picks pending")
	check(p.any(func(x: Dictionary) -> bool: return x.asi), "ASI pending at 4")
	h.choose(4, "asi", {Rules.Ability.CON: 2})
	var guard := 0
	while not h.pending_choices().is_empty() and guard < 10:
		var x: Dictionary = h.pending_choices()[0]
		h.choose(x.level, "spell", LevelUp.spell_pool("sorcerer", x.level, h.choices)[0])
		guard += 1
	eq(h.pending_choices().size(), 0, "all chosen (pool may run dry)")
	var f := HeroState.fresh("fighter", 1)
	f.xp = 2700
	eq(f.pending_choices().size(), 1, "fighter only ASI")


func test_choose_con_raises_current_hp() -> void:
	var h := HeroState.fresh("fighter", 1)
	h.xp = 2700
	h.hp = 10
	h.choose(4, "asi", {Rules.Ability.CON: 2})
	eq(h.hp, 14, "+1 CON mod × 4 levels")
	var c := h.duplicate_state()
	eq(c.choices[4].asi[Rules.Ability.CON], 2, "copied")
