## 액션 전투 난이도 시뮬레이션 (수치 맞추기용).
## 실제 던전 생성기로 만든 방의 조우를 파티(플레이어 봇 + 동료 AI)가 싸워 보고 통계를 냅니다.
## 플레이어 봇은 몬스터 공격 예고를 보고 정해진 확률(skill)로 구릅니다 (반응 0.3초).
## 실행: Godot --headless --path . -s tools/sim_action.gd -- [던전 수] [파티 클래스들] [boss] (예: 20 fighter,cleric)
## boss를 붙이면 출구 보스 방만 싸우고, 레벨 2~5로 봅니다
extends SceneTree

const DT := 1.0 / 60.0
const REACTION := 0.3
const MAX_TIME := 90.0
var LEVELS := [1, 2, 3]
var SKILLS := [0.0, 0.5, 0.9]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 20
	var classes := (args[1] if args.size() > 1 else "fighter,cleric").split(",")
	var boss_only := args.size() > 2 and args[2] == "boss"
	if boss_only:
		LEVELS = [2, 3, 4, 5]
	for lvl in LEVELS:
		for skill in SKILLS:
			var st := {"fights": 0, "wins": 0, "time": 0.0, "lost": 0.0, "downs": 0, "worst": 0.0, "dealt": 0, "taken": 0,
				"swings": 0}
			for i in n:
				var p := DungeonParams.new()
				p.rng_seed = 1000 + i
				p.party_level = lvl
				p.party_size = classes.size()
				var d := DungeonGenerator.generate(p)
				for r in d.rooms:
					if r.encounter.is_empty() or (boss_only and not r.encounter.get("boss", false)):
						continue
					if boss_only and i < 2 and skill == SKILLS[0]:
						print("  Lv%d 보스 방: %s" % [lvl, r.encounter.label])
					_fight(d, r, classes, lvl, skill, st, 7 * i + r.id)
			var f: float = maxf(1, st.fights)
			print("Lv%d skill %.2f | 싸움 %d, 이김 %.0f%%, 평균 %.1f초, 잃은 HP %.0f%% (최악 %.0f%%), 쓰러짐 %.2f번, 플레이어 휘두르기 %.1f번" % [
				lvl, skill, st.fights, 100.0 * st.wins / f, st.time / f, 100.0 * st.lost / f, 100.0 * st.worst,
				float(st.downs) / f, float(st.swings) / f])
			print("   몬스터 휘두름 %d, 맞힘 %d (피해 %d), 막힘·회피 %d" % [st.get("mswing",0), st.get("mhit",0), st.get("mdmg",0), st.get("blk",0)])
	quit()


func _fight(d: Dungeon, r: Dictionary, classes: PackedStringArray, lvl: int, skill: float, st: Dictionary, seed_v: int) -> void:
	var ac := ActionCombat.new(d, Dice.new(seed_v))
	seed(seed_v)
	# 몬스터
	var centroid := Vector2.ZERO
	for f in r.encounter.foes:
		var cell: Vector2i = f[1]
		var m := ac.add(Creature.new(Catalog.monster(f[0]), 1), Vector2(cell) + Vector2(0.5, 0.5), "monster", r.id)
		centroid += m.pos
	centroid /= r.encounter.foes.size()
	# 파티: 방 안에서 몬스터 무리와 가장 먼 칸
	var best := Vector2.ZERO
	var bd := -1.0
	for cell in r.cells:
		var p := Vector2(cell) + Vector2(0.5, 0.5)
		if ac.can_stand(p) and p.distance_to(centroid) > bd:
			bd = p.distance_to(centroid)
			best = p
	var party: Array = []
	for i in classes.size():
		var c := Creature.new(Catalog.pc(classes[i], lvl), 0)
		c.resources["potion"] = 1
		var a := ac.add(c, best + Vector2(0.4 * i, 0.4 * i), "player" if i == 0 else "ally")
		party.append(a)
	var total_hp := 0
	for a in party:
		total_hp += a.c.stats.max_hp
	ac.wake_room(r.id)
	var downs := [0]
	ac.event.connect(func(ev: Dictionary) -> void:
		if ev.type == "down":
			downs[0] += 1
		elif ev.type == "swing" and ev.actor == party[0]:
			st.swings += 1
		elif ev.type == "swing" and ev.actor.c.team == 1:
			st["mswing"] = st.get("mswing", 0) + 1
		elif ev.type == "hit" and ev.actor.c.team == 1:
			st["mhit"] = st.get("mhit", 0) + 1
			st["mdmg"] = st.get("mdmg", 0) + ev.damage
			if ev.target == party[0]:
				st["pdmg"] = st.get("pdmg", 0) + ev.damage
		elif ev.type == "text" and ev.actor.c.team == 0:
			st["blk"] = st.get("blk", 0) + 1)
	var me: ActionCombat.Actor = party[0]
	var reacted := {}
	var t := 0.0
	while t < MAX_TIME and ac.fighting() and not ac.party_down():
		_bot(ac, me, skill, reacted)
		ac.tick(DT)
		t += DT
	var left := 0
	for a in party:
		left += maxi(0, a.c.hp)
	var lost := 1.0 - float(left) / total_hp
	st.fights += 1
	st.time += t
	st.lost += lost
	st.worst = maxf(st.worst, lost)
	st.downs += downs[0]
	if not ac.fighting() and not ac.party_down():
		st.wins += 1
	elif OS.get_cmdline_user_args().size() > 3:
		var desc := []
		for a in ac.actors:
			if a.alive():
				desc.append("%s@%s %s" % [a.c.stats.id, a.pos, a.state])
		print("  안 끝남: ", r.encounter.label, " | ", desc)


## 사람처럼: 다가가 때리고, 공격 예고를 보면 skill 확률로 구름. HP가 낮으면 물약·기술
func _bot(ac: ActionCombat, me: ActionCombat.Actor, skill: float, reacted: Dictionary) -> void:
	me.move = Vector2.ZERO
	if not me.alive():
		return
	if me.c.hp < me.c.stats.max_hp * 0.35:
		if ac.use_potion(me) == "" or ac.use_skill(me) == "":
			return
	var foes := ac.foes_of(me)
	if foes.is_empty():
		return
	# 보스 기술: 범위 안이면 (반응 뒤) skill 확률로 굴러 빠져나가고, 끝날 때까지 밖으로 걸음
	for f in foes:
		var key := -f.get_instance_id()
		if f.state != "ability":
			reacted.erase(key)
			continue
		if f.ab.sk.windup - f.t < REACTION or not ac.skill_area_has(f, me.pos, me.radius + 0.3):
			continue
		if not reacted.has(key):
			reacted[key] = randf() < skill
			me.want_dodge = reacted[key]
		if reacted[key]:
			me.move = ac.skill_escape(f, me.pos)
			return
	# 위협: 나를 노리는 몬스터가 준비 중이고, 반응 시간이 지났음
	for f in foes:
		if f.state != "windup":
			reacted.erase(f)
			continue
		var elapsed := ActionCombat.MONSTER_WINDUP - f.t
		if elapsed < REACTION or reacted.has(f):
			continue
		reacted[f] = true
		var ranged := ActionCombat.is_ranged(f.weapon)
		var in_reach := me.pos.distance_to(f.pos) <= ActionCombat.melee_dist(f, me) + 0.5
		if (ranged or in_reach) and randf() < skill:
			var away := (me.pos - f.pos).normalized()
			me.move = away.orthogonal() if ranged else away
			me.want_dodge = true
			return
	if me.skill_cd <= 0.0 and not me.busy() and ac.auto_skill2(me):
		return
	var target: ActionCombat.Actor = null
	var bd := INF
	for f in foes:
		var dd := me.pos.distance_to(f.pos)
		if dd < bd:
			bd = dd
			target = f
	var to := target.pos - me.pos
	if ActionCombat.is_ranged(me.weapon):
		if bd < 3.0:
			me.move = -to.normalized()
		elif bd > 7.0 or not ac.clear_line(me.pos, target.pos):
			me.move = to.normalized()
		else:
			me.facing = to.normalized()
			me.want_attack = true
		return
	if bd > (ActionCombat.melee_dist(me, target) - ActionCombat.RADIUS) * 0.85:
		me.move = to.normalized()
	else:
		me.facing = to.normalized()
		me.want_attack = true
