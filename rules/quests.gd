## 의뢰 (기획 12.1, M4): 템플릿 + 빈칸 채우기.
## 템플릿에는 목표 종류와 글(빈칸 {foe} {dir} {floor} {item} {days})만 있고, 의뢰판을 볼 때 그 세상의 것으로 빈칸을 채웁니다:
##   group  바깥 몬스터 무리 하나 (아직 안 물리친 것) 물리치기
##   boss   던전 N층 출구 방 우두머리 물리치기
##   fetch  던전 N층 어딘가에 떨어진 물건 찾아오기 (그 층을 만들 때 방 하나에 놓임)
## 의뢰 하나는 값만 든 사전이라 그대로 저장됩니다 (scripts/game.gd).
##   {uid, tid, kind, title, text, giver, target, item, floor, gold, xp, taken, deadline, state}
##   state: "offered" 의뢰판에 붙음 → "active" 받음 → "done" 목표 이룸(보상 받으러 감) → "rewarded" / "failed"
## 날짜는 하루 단위 (Game.day). 여관·쉼터에서 하룻밤 자면 하루가 갑니다. 기한을 넘기면 실패.
## 다른 스크립트는 const Quests = preload("res://rules/quests.gd") 로 씁니다.
extends RefCounted

## 한꺼번에 받을 수 있는 의뢰 수, 의뢰판에 붙는 수
const MAX_ACTIVE := 3
const BOARD_SIZE := 3

const TEMPLATES := [
	{"id": "hunt", "kind": "group", "title": "{foe} 무리 처치",
		"text": "{dir}쪽 {dist}걸음쯤에 {foe} 무리가 자리를 잡아 나무꾼들이 숲에 못 들어갑니다. 물리쳐 주세요.",
		"giver": "나무꾼 조합", "gold": [30, 50], "xp": [40, 70], "days": [2, 3]},
	{"id": "escort_road", "kind": "group", "title": "길목의 {foe}",
		"text": "장사꾼 수레가 {dir}쪽 길목에서 {foe} 무리에게 쫓겨 돌아왔습니다. 길을 다시 열어 주세요.",
		"giver": "잡화점 주인", "gold": [35, 55], "xp": [40, 70], "days": [2, 4]},
	{"id": "boss", "kind": "boss", "title": "던전 {floor}층의 우두머리",
		"text": "{dir}쪽 언덕 던전의 {floor}층 출구를 무언가 강한 것이 지키고 있다는 소문입니다. 그것을 쓰러뜨리면 조합이 사례합니다.",
		"giver": "모험가 조합", "gold": [70, 110], "xp": [90, 150], "days": [3, 5]},
	{"id": "fetch", "kind": "fetch", "title": "잃어버린 {item}",
		"text": "던전에 들어갔다 돌아오지 못한 동료가 {item}을(를) 지니고 있었습니다. {floor}층 어딘가에 떨어져 있을 겁니다. 찾아 주세요.",
		"giver": "여관 주인", "gold": [50, 80], "xp": [60, 100], "days": [3, 5],
		"items": ["은 목걸이", "가문 인장 반지", "낡은 기도서", "약초상의 장부", "청동 열쇠"]},
]


## 의뢰판에 붙일 의뢰들. world: {groups: [{id, label, home: Vector2}], entrance: Vector2, max_floor, day}
## taken: 이미 받은(진행 중) 의뢰들 — 같은 무리를 두 번 겨냥하지 않음
static func offers(seed_value: int, world: Dictionary, taken: Array, next_uid: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 104729 + int(world.get("day", 1)) * 7
	var busy_groups := {}
	var busy_floor := {}
	for q in taken:
		if q.state == "active" or q.state == "done":
			if q.kind == "group":
				busy_groups[int(q.target)] = true
			else:
				busy_floor["%s%d" % [q.kind, int(q.floor)]] = true
	var groups: Array = (world.get("groups", []) as Array).filter(func(g) -> bool: return not busy_groups.has(int(g.id)))
	var out := []
	var tries := 0
	while out.size() < BOARD_SIZE and tries < 30:
		tries += 1
		var t: Dictionary = TEMPLATES[rng.randi() % TEMPLATES.size()]
		var q := {"uid": next_uid + out.size(), "tid": t.id, "kind": t.kind, "giver": t.giver,
			"target": -1, "item": "", "floor": 0, "state": "offered", "taken": 0, "deadline": 0}
		var fill := {}
		match String(t.kind):
			"group":
				var free := groups.filter(func(g) -> bool: return not out.any(func(o) -> bool: return o.kind == "group" and int(o.target) == int(g.id)))
				if free.is_empty():
					continue
				var g: Dictionary = free[rng.randi() % free.size()]
				q.target = int(g.id)
				var home: Vector2 = g.home
				fill = {"foe": g.label, "dir": compass(home), "dist": roundi(home.length() / 5.0) * 5}
			"boss", "fetch":
				var f := rng.randi_range(1, maxi(1, int(world.get("max_floor", 2))))
				var key := "%s%d" % [t.kind, f]
				if busy_floor.has(key) or out.any(func(o) -> bool: return o.kind == t.kind and int(o.floor) == f):
					continue
				q.floor = f
				var e: Vector2 = world.get("entrance", Vector2(-1, -1))
				fill = {"floor": f, "dir": compass(e)}
				if t.has("items"):
					q.item = str(t.items[rng.randi() % t.items.size()])
					fill["item"] = q.item
		var days := rng.randi_range(int(t.days[0]), int(t.days[1]))
		fill["days"] = days
		q["days"] = days
		q.title = _fill(str(t.title), fill)
		q.text = _fill(str(t.text), fill)
		q.gold = rng.randi_range(int(t.gold[0]), int(t.gold[1]))
		q.xp = rng.randi_range(int(t.xp[0]), int(t.xp[1]))
		out.append(q)
	return out


## 의뢰 받기: 기한은 받은 날 + 일수
static func accept(q: Dictionary, day: int) -> void:
	q.state = "active"
	q.taken = day
	q.deadline = day + int(q.get("days", 3))


## 진행 중인 의뢰 수 (보상 받기 전까지 자리를 차지)
static func busy(quests: Array) -> int:
	return quests.filter(func(q) -> bool: return q.state == "active" or q.state == "done").size()


## 사건 → 목표를 이룬 의뢰들 (state가 "done"으로 바뀜)
static func on_group_defeated(quests: Array, group: int) -> Array:
	return _complete(quests, func(q) -> bool: return q.kind == "group" and int(q.target) == group)


static func on_boss(quests: Array, floor_no: int) -> Array:
	return _complete(quests, func(q) -> bool: return q.kind == "boss" and int(q.floor) == floor_no)


static func on_item(quests: Array, floor_no: int) -> Array:
	return _complete(quests, func(q) -> bool: return q.kind == "fetch" and int(q.floor) == floor_no)


## 이 층에 놓아야 할 의뢰 물건 (찾을 것이 없으면 빈 사전)
static func item_on_floor(quests: Array, floor_no: int) -> Dictionary:
	for q in quests:
		if q.state == "active" and q.kind == "fetch" and int(q.floor) == floor_no:
			return q
	return {}


## 하루가 지남 → 기한을 넘긴 의뢰들 (state가 "failed"로 바뀜)
static func tick(quests: Array, day: int) -> Array:
	var failed := []
	for q in quests:
		if q.state == "active" and day > int(q.deadline):
			q.state = "failed"
			failed.append(q)
	return failed


## 보상 받을 의뢰들
static func ready_to_reward(quests: Array) -> Array:
	return quests.filter(func(q) -> bool: return q.state == "done")


## 일지 한 줄
static func line(q: Dictionary, day: int) -> String:
	match String(q.state):
		"active":
			var left := int(q.deadline) - day
			return "%s — %s" % [q.title, "오늘까지" if left <= 0 else "%d일 남음" % left]
		"done":
			return "%s — 끝냄, 의뢰판에서 보상 받기" % q.title
		"rewarded":
			return "%s — 보상 받음" % q.title
		"failed":
			return "%s — 기한을 넘겨 실패" % q.title
	return str(q.title)


## 방향 이름 (-Z가 북쪽)
static func compass(v: Vector2) -> String:
	var names := ["동", "남동", "남", "남서", "서", "북서", "북", "북동"]
	return names[posmod(roundi(atan2(v.y, v.x) / (PI / 4.0)), 8)]


static func _complete(quests: Array, pred: Callable) -> Array:
	var out := []
	for q in quests:
		if q.state == "active" and pred.call(q):
			q.state = "done"
			out.append(q)
	return out


static func _fill(s: String, fill: Dictionary) -> String:
	for k in fill:
		s = s.replace("{%s}" % k, str(fill[k]))
	return s
