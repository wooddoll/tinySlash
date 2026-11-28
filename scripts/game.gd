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
## 날짜 (하루 단위, 여관·쉼터에서 자면 하루가 감)
static var day := 1
## 받은 의뢰들 (rules/quests.gd 사전), 의뢰판에 붙은 의뢰와 그 날짜, 다음 의뢰 번호
static var quests: Array = []
static var board: Array = []
static var board_day := 0
static var next_uid := 1
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
	quests = []
	board = []
	board_day = 0
	next_uid = 1
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
		"quests": quests.duplicate(true),
		"board": board.duplicate(true),
		"board_day": board_day,
		"next_uid": next_uid,
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
	quests = (d.get("quests", []) as Array).duplicate(true)
	board = (d.get("board", []) as Array).duplicate(true)
	board_day = int(d.get("board_day", 0))
	next_uid = int(d.get("next_uid", 1))
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


## 하루가 지남. 기한을 넘긴 의뢰들을 돌려줌
static func advance_day() -> Array:
	day += 1
	return Quests.tick(quests, day)


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
	var heroes := party()
	var share := int(q.xp) / maxi(heroes.size(), 1)
	var up := 0
	for h in heroes:
		var r: Dictionary = (h as HeroState).absorb((h as HeroState).make_creature(), share)
		up = maxi(up, int(r.get("level_up", 0)))
	return up
