## 한 판(게임 하나)의 상태를 한곳에 모으고 파일로 저장·불러오기 (docs/design.md M1).
## 여러 장면이 같이 쓰는 것(세계 시드, 물리친 무리, 파티, 금화, 지금 있는 곳)은 여기에 두고,
## 던전 탐험 중 상태(층, 연 상자, 본 칸 등)는 던전 화면(dungeon_view.gd)에 두되 저장할 때 같이 담습니다.
## 다른 스크립트는 const Game = preload("res://scripts/game.gd") 로 씁니다.
## 저장 파일은 객체 없이 값만 (FileAccess.store_var / get_var(false)) 이라 열어도 코드가 돌지 않습니다.
extends RefCounted

## 저장 파일 (테스트는 다른 파일로 바꿔 씀)
static var save_path := "user://save1.dat"
const VERSION := 1
## 새 게임 금화 (여관 하룻밤 몇 번)
const START_GOLD := 30
const DUNGEON_VIEW := "res://scripts/dungeon_view.gd"
const Quests = preload("res://rules/quests.gd")
const Region = preload("res://rules/region.gd")
const Reputation = preload("res://rules/reputation.gd")

## 바깥 세상 시드 (0이면 다음에 바깥으로 나갈 때 새로 정함)
static var world_seed := 0
## 이 세상에서 물리친 바깥 몬스터 무리 번호
static var defeated := {}
## 파티 (던전·바깥이 같이 씀)
static var hero: HeroState = null
static var ally: HeroState = null
static var gold := 0
## 지금 있는 곳: "outside" (바깥 지형) 또는 "dungeon" (던전 탐험 중)
static var place := "outside"
## 바깥에서 서 있던 자리 (불러오면 여기서 시작, INF면 빈터)
static var outside_pos := Vector3.INF
## 이번에 불러온 바깥 자리를 main.gd가 한 번 쓰고 비움
static var _load_pos := Vector3.INF
## 날짜와 시각 (M5): day일째 minute분 (0~1439). 바깥에서는 실제 1초에 1분씩 흐르고, 자거나 빠른 이동하면 훌쩍 지남
static var day := 1
static var minute := 8 * 60
## 지금 있는 지방 칸 (rules/region.gd, 마을 칸이 (1, 1)), 들어가 있는 던전 번호
static var tile := Vector2i(1, 1)
static var dungeon_id := 0
## 칸을 넘거나 빠른 이동해서 도착할 자리 (x, z). "entrance"면 그 칸 던전 입구 앞. main.gd가 한 번 쓰고 비움
static var arrival = null
static var _region = null
static var _region_seed := -1
## 받은 의뢰들 (rules/quests.gd 사전), 의뢰판에 붙은 의뢰와 그 날짜, 다음 의뢰 번호
static var quests: Array = []
static var board: Array = []
static var board_day := 0
static var next_uid := 1
## 던전마다 기억 (던전 번호 → {day: 마지막으로 나온 날, floors: {층: {params(사전), cleared, opened, used_fires, seen}}})
## 같은 던전은 언제 가도 같은 구조. 비운 방은 RESPAWN_DAYS 지나면 다시 몬스터가 참 (상자는 그대로 열림)
static var dungeon_memory := {}
## 평판 {guild, village} (rules/reputation.gd), 조합 등급 0~3, 마지막 의뢰를 끝냈나 (엔딩을 봄)
static var rep := {"guild": 0, "village": 0}
static var rank := 0
static var ended := false
const RESPAWN_DAYS := 3
## 마지막으로 저장한 시각 (Time.get_unix_time_from_system)
static var saved_at := 0


static func has_save() -> bool:
	return FileAccess.file_exists(save_path)


## 새 게임: 모든 상태를 처음으로 (세계 시드는 바깥에 나갈 때 새로 정함)
static func new_game() -> void:
	world_seed = 0
	defeated.clear()
	hero = null
	ally = null
	gold = START_GOLD
	place = "outside"
	outside_pos = Vector3.INF
	_load_pos = Vector3.INF
	day = 1
	minute = 8 * 60
	tile = Region.VILLAGE
	dungeon_id = 0
	arrival = null
	_region = null
	quests = []
	board = []
	board_day = 0
	next_uid = 1
	dungeon_memory = {}
	rep = Reputation.fresh()
	rank = 0
	ended = false
	load(DUNGEON_VIEW).reset_run()


## 파티가 없으면 새로 (주인공, 동료)
static func ensure_party() -> void:
	if hero == null:
		hero = HeroState.fresh(str(HeroState.party_classes[0]), 1)
	if ally == null and HeroState.party_classes.size() > 1:
		ally = HeroState.fresh(str(HeroState.party_classes[1]), 0)


static func party() -> Array:
	return [hero, ally].filter(func(h: HeroState) -> bool: return h != null)


## 지금 상태를 사전으로 (저장 파일 내용)
static func snapshot() -> Dictionary:
	var dv = load(DUNGEON_VIEW)
	return {
		"version": VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"world_seed": world_seed,
		"defeated": defeated.duplicate(),
		"hero": hero.to_dict() if hero else {},
		"ally": ally.to_dict() if ally else {},
		"gold": gold,
		"place": place,
		"outside_pos": outside_pos,
		"party_classes": HeroState.party_classes.duplicate(),
		"day": day,
		"minute": minute,
		"tile": [tile.x, tile.y],
		"dungeon_id": dungeon_id,
		"quests": quests.duplicate(true),
		"board": board.duplicate(true),
		"board_day": board_day,
		"next_uid": next_uid,
		"dungeon_memory": dungeon_memory.duplicate(true),
		"rep": rep.duplicate(),
		"rank": rank,
		"ended": ended,
		"dungeon": dv.run_state() if place == "dungeon" else {},
	}


## 사전에서 상태를 되돌림. 돌아갈 장면 경로를 돌려줌
static func restore(d: Dictionary) -> String:
	world_seed = int(d.get("world_seed", 0))
	defeated = (d.get("defeated", {}) as Dictionary).duplicate()
	hero = HeroState.from_dict(d.hero) if not (d.get("hero", {}) as Dictionary).is_empty() else null
	ally = HeroState.from_dict(d.ally) if not (d.get("ally", {}) as Dictionary).is_empty() else null
	gold = int(d.get("gold", 0))
	place = str(d.get("place", "outside"))
	outside_pos = d.get("outside_pos", Vector3.INF)
	saved_at = int(d.get("saved_at", 0))
	day = int(d.get("day", 1))
	minute = int(d.get("minute", 8 * 60))
	var tl: Array = d.get("tile", [])
	dungeon_id = int(d.get("dungeon_id", 0))
	_region = null
	arrival = null
	quests = (d.get("quests", []) as Array).duplicate(true)
	board = (d.get("board", []) as Array).duplicate(true)
	board_day = int(d.get("board_day", 0))
	next_uid = int(d.get("next_uid", 1))
	dungeon_memory = (d.get("dungeon_memory", {}) as Dictionary).duplicate(true)
	rep = Reputation.fresh()
	rep.merge(d.get("rep", {}), true)
	rank = int(d.get("rank", 0))
	ended = bool(d.get("ended", false))
	if tl.size() == 2:
		tile = Vector2i(int(tl[0]), int(tl[1]))
	else:
		# 지방 지도(M5) 전 저장: 모두 마을 칸에서 있던 일. 무리 번호에 칸 앞자리를 붙임
		tile = Region.VILLAGE
		var base := Region.index(Region.VILLAGE) * 100
		var nd := {}
		for k in defeated:
			nd[int(k) + base if int(k) < 100 else int(k)] = true
		defeated = nd
		for q in quests + board:
			if q.get("kind", "") == "group" and int(q.target) < 100:
				q.target = int(q.target) + base
	if d.has("party_classes"):
		HeroState.party_classes = (d.party_classes as Array).duplicate()
	var dv = load(DUNGEON_VIEW)
	dv.reset_run()
	if place == "dungeon" and not (d.get("dungeon", {}) as Dictionary).is_empty():
		dv.restore_run(d.dungeon)
		return "res://scenes/dungeon.tscn"
	place = "outside"
	_load_pos = outside_pos
	return "res://scenes/main.tscn"


static func save_game() -> bool:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_error("저장 실패: %s" % FileAccess.get_open_error())
		return false
	var d := snapshot()
	f.store_var(d, false)
	saved_at = int(d.saved_at)
	return true


## 저장 파일을 읽어 상태를 되돌리고 돌아갈 장면 경로를 돌려줌 (없거나 깨졌으면 "")
static func load_game() -> String:
	if not has_save():
		return ""
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		return ""
	var d = f.get_var(false)
	if not (d is Dictionary) or int(d.get("version", 0)) != VERSION:
		push_warning("저장 파일을 읽지 못했어요")
		return ""
	return restore(d)


static func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


## 불러온 바깥 자리를 한 번만 꺼냄 (main.gd)
static func take_load_pos() -> Vector3:
	var p := _load_pos
	_load_pos = Vector3.INF
	return p


## 시간이 흐름 (분). 날이 바뀌면 기한을 넘긴 의뢰들을 돌려줌
static func advance_minutes(m: int) -> Array:
	var failed := []
	minute += maxi(m, 0)
	while minute >= 1440:
		minute -= 1440
		day += 1
		var f := Quests.tick(quests, day)
		for q in f:
			Reputation.on_quest(rep, q, false)
		failed.append_array(f)
	if not failed.is_empty():
		rank = Reputation.rank_for(rank, int(rep.guild), hero.level() if hero else 1)
	return failed


## 다음 hour시까지 잠 (여관, 바깥에서 쓰러짐)
static func sleep_until(hour: int) -> Array:
	var target := hour * 60
	return advance_minutes(target - minute if minute < target else 1440 - minute + target)


## 하루가 지남 (24시간)
static func advance_day() -> Array:
	return advance_minutes(1440)


## "3일째 14:05"
static func time_text() -> String:
	return "%d일째 %02d:%02d" % [day, minute / 60, minute % 60]


## 이 세계의 지방 (세계 시드로 정해짐)
static func region():
	if _region == null or _region_seed != world_seed:
		_region = Region.generate(world_seed)
		_region_seed = world_seed
	return _region


## 의뢰판: 날이 바뀌었으면 새로 붙임 (받은 것과 겹치지 않게)
static func board_offers(world: Dictionary) -> Array:
	if board_day != day:
		world["day"] = day
		board = Quests.offers(world_seed, world, quests, next_uid)
		next_uid += board.size()
		board_day = day
	return board


## 의뢰판의 의뢰를 받음
static func take_offer(q: Dictionary) -> bool:
	if Quests.busy(quests) >= Quests.MAX_ACTIVE or not board.has(q):
		return false
	board.erase(q)
	Quests.accept(q, day)
	quests.append(q)
	return true


## 끝낸 의뢰의 보상: 금화 + 경험치(파티가 나눔). 레벨업한 레벨(없으면 0)을 돌려줌
static func reward(q: Dictionary) -> int:
	if q.state != "done":
		return 0
	q.state = "rewarded"
	gold += int(q.gold)
	Reputation.on_quest(rep, q, true)
	if q.get("final", false):
		ended = true
	var heroes := party()
	var share := int(q.xp) / maxi(heroes.size(), 1)
	var up := 0
	for h in heroes:
		var r: Dictionary = (h as HeroState).absorb((h as HeroState).make_creature(), share)
		up = maxi(up, int(r.get("level_up", 0)))
	rank = Reputation.rank_for(rank, int(rep.guild), hero.level() if hero else 1)
	return up


## 조합 가입 (회관)
static func join_guild() -> bool:
	if not Reputation.can_join(rank, int(rep.guild)):
		return false
	rank = 1
	rank = Reputation.rank_for(rank, int(rep.guild), hero.level() if hero else 1)
	return true


## 마지막 의뢰: 베테랑이 되면 회관에서 받을 수 있음 (받은 적 없을 때만, 실패했으면 다시 줌). world는 의뢰판과 같은 꼴
static func final_offer(world: Dictionary) -> Dictionary:
	if rank < Reputation.TOP_RANK or ended:
		return {}
	for q in quests:
		if q.get("final", false) and q.state != "failed":
			return {}
	return Quests.final_quest(world.get("dungeons", []), Reputation.FINAL_FLOOR, next_uid)


static func take_final(q: Dictionary) -> bool:
	if q.is_empty() or not q.get("final", false) or Quests.busy(quests) >= Quests.MAX_ACTIVE:
		return false
	next_uid += 1
	Quests.accept(q, day)
	quests.append(q)
	return true
