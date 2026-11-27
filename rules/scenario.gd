## 데이터로 만든 모험(시나리오)을 진행하는 엔진. 화면과 무관한 순수 로직입니다.
## 시나리오는 폴더 하나(팩)입니다. 폴더 안의 scenario.json(목록 파일)이 나머지 파일을 가리킵니다.
## 형식은 docs/scenario.md에 있습니다.
##
## 화면(scripts/scenario_view.gd)은 이렇게 씁니다.
##   1. enter_cell / interact / search / choose 를 부르면
##   2. 결과가 out 배열에 쌓이고 ({"type": "text" | "doc" | "dialogue" | "battle" | "level" | "refresh" | "toast" | "end"})
##   3. 화면이 out을 앞에서부터 꺼내 보여 줍니다.
class_name Scenario
extends RefCounted

const DOOR_TYPES := ["door"]
## 지도 기호: # 벽  . 바닥  , 험지(거미줄, 잔해)  ~ 얕은 물(험지)  o 낮은 가구(높이 1, 반 엄폐)
##           O 기둥(완전 엄폐)  - 계단참(높이 0.5)  ^ 단상(높이 1.0)  나머지 글자는 marks에 정의
const BASE_CHARS := "#.,~oO-^"
## 팩 폴더 안의 목록 파일 이름
const MANIFEST := "scenario.json"
## 팩을 찾는 곳. 각 폴더의 하위 폴더 중 scenario.json이 있는 것이 팩
const PACK_ROOTS := ["res://scenarios", "user://scenarios"]
## 목록 파일에서 여러 파일을 합치는 항목 (값: 파일 이름 배열 또는 바로 쓴 사전)
const MERGED_SECTIONS := ["encounters", "dialogues", "monsters"]

var data := {}
## 팩 폴더 (파일 이름은 여기 기준)
var pack_dir := ""
## 팩을 읽다 생긴 문제 (파일 없음, JSON 오류, 중복 id)
var errors := PackedStringArray()
var id := ""
var title := ""
## 층 id -> Dungeon (지도 모양)
var levels := {}
## "층:글자" -> 정의 사전 (+ level, ch, cell, type)
var marks := {}
## 층 -> {칸: 표식 key}
var mark_at := {}
## 방 key("층:글자") -> {key, level, name, cells, def}
var rooms := {}
## 층 -> {칸: 방 key}
var room_at := {}
## 층 -> {칸: true} 물 칸 (~)
var water := {}
var dice := Dice.new()
## 화면이 처리할 결과
var out: Array[Dictionary] = []

# --- 진행 상태 (체크포인트로 저장되는 것) ---
var level := ""
var cell := Vector2i.ZERO
var flags := {}
## 아이템 id -> {name, count}
var items := {}
var gold := 0
var heroes: Array = []
## 시나리오 고르기 창에서 고른 파티 (비어 있으면 시나리오 파일의 party)
static var party_override: Array = []
## 찾은 비밀(문, 함정, 숨은 물건): key -> true
var revealed := {}
## 연 문: key -> true
var opened := {}
## 이긴 조우: 그룹 id -> true
var cleared := {}
## 들어가 본 방, 수색한 방, 한 번만 되는 물건을 쓴 것
var visited := {}
var searched := {}
var used := {}
## 탐험 중 본 칸: "층" -> {칸: true}
var seen := {}
## 읽은 문서: [{title, text}]
var journal: Array = []
## 진행 중인 대화 {id, node}
var dialogue := {}
var checkpoint := {}
## 지금 있는 방 (들어설 때 바뀌면 방 이벤트)
var room_key := ""
var ended := false


# =====================================================================
# 불러오기
# =====================================================================

## 시나리오 팩을 읽음. path는 팩 폴더 또는 그 안의 scenario.json (res://, user://, 절대 경로 모두 됨)
static func load_pack(path: String) -> Scenario:
	var manifest_path := path if path.ends_with(".json") else path.path_join(MANIFEST)
	var s := Scenario.new()
	s.pack_dir = manifest_path.get_base_dir()
	var m: Variant = s._read_json(manifest_path)
	if not m is Dictionary:
		for e in s.errors:
			push_error(e)
		return null
	s.setup(s.assemble(m))
	return s  # 일부 파일 문제는 errors에 남김 (화면이 보여 줌)


## 목록 파일과 그것이 가리키는 파일들을 엔진이 쓰는 사전 하나로 합침
##   levels: ["levels/f1.json", ...] (각 파일에 "id") 또는 {층 id: 파일 이름 | 층 정의}
##   encounters / dialogues / monsters: [파일 이름, ...] (각 파일은 {id: 정의}) 또는 바로 쓴 사전
##   그 밖의 값이 ".json"으로 끝나는 문자열이면 그 파일 내용으로 바꿈 (intro 등)
func assemble(m: Dictionary) -> Dictionary:
	var d := {}
	for k in m:
		if k == "levels" or MERGED_SECTIONS.has(k):
			continue
		var v: Variant = m[k]
		d[k] = _read_rel(v) if v is String and (v as String).ends_with(".json") else v
	var lv := {}
	var src: Variant = m.get("levels", [])
	if src is Dictionary:
		for lid in src:
			var def: Variant = _read_rel(src[lid]) if src[lid] is String else src[lid]
			if def is Dictionary:
				lv[str(lid)] = def
	else:
		for f in src:
			var def: Variant = _read_rel(f) if f is String else f
			if not def is Dictionary:
				continue
			var lid := str(def.get("id", str(f).get_file().get_basename()))
			if lv.has(lid):
				errors.append("층 id 중복: %s" % lid)
			lv[lid] = def
	d["levels"] = lv
	for sec in MERGED_SECTIONS:
		var merged := {}
		var v: Variant = m.get(sec, [])
		var parts: Array = [v] if v is Dictionary else v
		for p in parts:
			var part: Variant = _read_rel(p) if p is String else p
			if not part is Dictionary:
				continue
			for k in part:
				if merged.has(k):
					errors.append("%s id 중복: %s" % [sec, k])
				merged[k] = part[k]
		d[sec] = merged
	return d


func _read_rel(rel: String) -> Variant:
	var p := rel if rel.is_absolute_path() else pack_dir.path_join(rel)
	return _read_json(p)


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("파일 없음: " + path)
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		errors.append("JSON 오류: %s %d줄: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


## 설치된 팩 목록: [{path, id, title, description, version, author}]
static func list_packs(roots: Array = PACK_ROOTS) -> Array:
	var out: Array = []
	for root in roots:
		var dir := DirAccess.open(str(root))
		if dir == null:
			continue
		var subs := dir.get_directories()
		subs.sort()
		for sub in subs:
			var p := str(root).path_join(sub).path_join(MANIFEST)
			if not FileAccess.file_exists(p):
				continue
			var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
			if not m is Dictionary:
				continue
			out.append({"path": p, "id": str(m.get("id", sub)), "title": str(m.get("title", sub)),
				"description": str(m.get("description", "")), "version": str(m.get("version", "")),
				"author": str(m.get("author", ""))})
	return out


## 이 시나리오의 몬스터 스탯. monsters에 정의가 있으면 그것(SRD 몬스터 바탕), 없으면 SRD 몬스터
func monster_stats(mid: String) -> CreatureStats:
	return Catalog.custom_monster(mid, data.get("monsters", {}))


func setup(d: Dictionary) -> void:
	data = d
	id = str(d.get("id", ""))
	title = str(d.get("title", id))
	var lv: Dictionary = d.get("levels", {})
	for lid in lv:
		_build_level(str(lid), lv[lid])


func _build_level(lid: String, def: Dictionary) -> void:
	var rows: Array = def.map
	var h := rows.size()
	var w := 0
	for r in rows:
		w = maxi(w, (r as String).length())
	var dg := Dungeon.new(w, h)
	var mdefs: Dictionary = def.get("marks", {})
	mark_at[lid] = {}
	water[lid] = {}
	for y in h:
		var row: String = rows[y]
		for x in row.length():
			var ch := row[x]
			var c := Vector2i(x, y)
			if ch == "#" or ch == " ":
				continue
			dg.set_tile(c, Dungeon.Tile.FLOOR)
			match ch:
				".": pass
				",": dg.difficult[c] = true
				"~":
					dg.difficult[c] = true
					water[lid][c] = true
				"o": dg.obstacles[c] = 1.0
				"O": dg.obstacles[c] = 3.0
				"-": dg.heights[c] = 0.5
				"^": dg.heights[c] = 1.0
				_:
					if not mdefs.has(ch):
						push_error("%s 층 (%d, %d): 정의 없는 기호 '%s'" % [lid, x, y, ch])
						continue
					var m: Dictionary = (mdefs[ch] as Dictionary).duplicate(true)
					var key := lid + ":" + ch
					if marks.has(key):
						push_error("%s 층: 기호 '%s'가 두 번 나옴" % [lid, ch])
					m["level"] = lid
					m["ch"] = ch
					m["cell"] = c
					m["mkey"] = key
					m["type"] = str(m.get("type", "feature"))
					marks[key] = m
					mark_at[lid][c] = key
					if m.type == "door":
						dg.set_tile(c, Dungeon.Tile.DOOR)
					if m.has("height"):
						dg.heights[c] = float(m.height)
					var fl: String = str(m.get("floor", ""))
					if fl == "~" or fl == ",":
						dg.difficult[c] = true
					if fl == "~":
						water[lid][c] = true
	levels[lid] = dg
	_build_rooms(lid)


## 방 표식(type "room")에서 벽과 문에 막힐 때까지 퍼져 나가 방 칸을 정함
func _build_rooms(lid: String) -> void:
	var dg: Dungeon = levels[lid]
	room_at[lid] = {}
	for key in marks:
		var m: Dictionary = marks[key]
		if m.level != lid or m.type != "room":
			continue
		var start: Vector2i = m.cell
		if room_at[lid].has(start):
			continue
		var cells: Array[Vector2i] = [start]
		var seen_c := {start: true}
		var i := 0
		while i < cells.size():
			var c := cells[i]
			i += 1
			for d in Dungeon.DIRS4:
				var n: Vector2i = c + d
				if seen_c.has(n) or not dg.is_floor(n) or _is_boundary(lid, n):
					continue
				seen_c[n] = true
				cells.append(n)
		for c in cells:
			room_at[lid][c] = key
		rooms[key] = {"key": key, "level": lid, "name": str(m.get("name", "")), "cells": cells, "def": m}


func _is_boundary(lid: String, c: Vector2i) -> bool:
	var key: String = mark_at[lid].get(c, "")
	if key == "":
		return false
	var t: String = marks[key].type
	return t == "door" or (t == "secret")


# =====================================================================
# 새 게임과 체크포인트
# =====================================================================

func new_game() -> void:
	flags = {}
	items = {}
	gold = int(data.get("start_gold", 0))
	revealed = {}
	opened = {}
	cleared = {}
	visited = {}
	searched = {}
	used = {}
	seen = {}
	journal = []
	dialogue = {}
	ended = false
	room_key = ""
	heroes = []
	var lv := int(data.get("start_level", 1))
	var classes: Array = party_override if not party_override.is_empty() else data.get("party", ["fighter", "cleric"])
	for i in classes.size():
		var h := HeroState.fresh(str(classes[i]), 1 if i == 0 else 0)
		h.xp = Rules.XP_THRESHOLDS[clampi(lv, 1, 6) - 1]
		heroes.append(h)
	var st: Dictionary = data.get("start", {})
	level = str(st.get("level", levels.keys()[0]))
	cell = mark_cell(level, str(st.get("mark", "")))
	out.clear()
	run(data.get("intro", []))
	save_checkpoint()


func save_checkpoint() -> void:
	checkpoint = snapshot()


func snapshot() -> Dictionary:
	var hs: Array = []
	for h in heroes:
		hs.append((h as HeroState).duplicate_state())
	return {
		"level": level, "cell": cell, "flags": flags.duplicate(true), "items": items.duplicate(true),
		"gold": gold, "heroes": hs, "revealed": revealed.duplicate(), "opened": opened.duplicate(),
		"cleared": cleared.duplicate(), "visited": visited.duplicate(), "searched": searched.duplicate(),
		"used": used.duplicate(), "seen": seen.duplicate(true), "journal": journal.duplicate(true),
	}


func load_checkpoint() -> void:
	var s := checkpoint
	if s.is_empty():
		return
	level = s.level
	cell = s.cell
	flags = s.flags.duplicate(true)
	items = s.items.duplicate(true)
	gold = s.gold
	heroes = []
	for h in s.heroes:
		heroes.append((h as HeroState).duplicate_state())
	revealed = s.revealed.duplicate()
	opened = s.opened.duplicate()
	cleared = s.cleared.duplicate()
	visited = s.visited.duplicate()
	searched = s.searched.duplicate()
	used = s.used.duplicate()
	seen = s.seen.duplicate(true)
	journal = s.journal.duplicate(true)
	dialogue = {}
	ended = false
	room_key = room_of(level, cell)


# =====================================================================
# 지도 질의
# =====================================================================

func dungeon() -> Dungeon:
	return levels[level]


func level_name(lid := "") -> String:
	var l := lid if lid != "" else level
	return str((data.levels[l] as Dictionary).get("name", l))


func level_style(lid := "") -> String:
	var l := lid if lid != "" else level
	return str((data.levels[l] as Dictionary).get("style", "rooms"))


func mark_cell(lid: String, ch: String) -> Vector2i:
	var key := lid + ":" + ch
	if marks.has(key):
		return marks[key].cell
	push_error("표식 없음: " + key)
	return Vector2i.ZERO


func room_of(lid: String, c: Vector2i) -> String:
	return room_at.get(lid, {}).get(c, "")


func room_name(key: String) -> String:
	return str(rooms[key].name) if rooms.has(key) else ""


## 조건: "flag", "!flag", "item:열쇠", "!item:열쇠", "cleared:그룹" 또는 그 배열(모두 참)
func cond(c: Variant) -> bool:
	if c == null:
		return true
	if c is Array:
		for x in c:
			if not cond(x):
				return false
		return true
	var s := str(c)
	if s == "":
		return true
	var neg := s.begins_with("!")
	if neg:
		s = s.substr(1)
	var v := false
	if s.begins_with("item:"):
		v = items.has(s.substr(5))
	elif s.begins_with("cleared:"):
		v = cleared.has(s.substr(8))
	elif s.begins_with("used:"):
		v = used.has(s.substr(5))
	else:
		v = flags.has(s)
	return v != neg


## 지금 존재하는 표식인가 ("if" 조건)
func active(key: String) -> bool:
	return marks.has(key) and cond(marks[key].get("if", null))


func hidden(key: String) -> bool:
	var m: Dictionary = marks[key]
	if m.type == "secret":
		return not revealed.has(key)
	return m.has("hidden_dc") and not revealed.has(key)


func is_open(key: String) -> bool:
	var m: Dictionary = marks[key]
	if m.type == "secret":
		return revealed.has(key)
	if m.type != "door":
		return true
	if not active(key):
		return true  # 조건에 따라 없어지는 문
	if m.has("open_if") and cond(m.open_if):
		return true
	return opened.has(key) and not (m.has("closed_if") and cond(m.closed_if))


## 이 층에서 지나갈 수 없는 칸: 닫힌 문, 찾지 못한 비밀문, 단단한 물건
func blocked(lid := "") -> Dictionary:
	var l := lid if lid != "" else level
	var b := {}
	for c in mark_at[l]:
		var key: String = mark_at[l][c]
		var m: Dictionary = marks[key]
		if m.type == "door" and not is_open(key):
			b[c] = true
		elif m.type == "secret" and not revealed.has(key):
			b[c] = true
		elif bool(m.get("solid", false)) and active(key) and not hidden(key):
			b[c] = true
	# 아직 싸우지 않은 몬스터 칸
	for g in groups_here(l):
		for f in foes_of(g):
			if not bool(f.get("hidden", false)):
				b[f.cell] = true
	return b


func walkable(c: Vector2i) -> bool:
	return dungeon().is_walkable(c) and not blocked().has(c)


## 이 층에 있는, 아직 이기지 못한 조우 그룹
func groups_here(lid: String) -> Array:
	var out_g: Array = []
	for key in marks:
		var m: Dictionary = marks[key]
		if m.level == lid and m.type == "foe":
			var g := str(m.get("group", ""))
			if not cleared.has(g) and not out_g.has(g) and group_active(g):
				out_g.append(g)
	return out_g


func group_def(g: String) -> Dictionary:
	return data.get("encounters", {}).get(g, {})


func group_active(g: String) -> bool:
	return cond(group_def(g).get("if", null))


func foes_of(g: String) -> Array:
	var fs: Array = []
	for key in marks:
		var m: Dictionary = marks[key]
		if m.type == "foe" and str(m.get("group", "")) == g and cond(m.get("if", null)):
			fs.append(m)
	return fs


## cell 옆(대각선 포함)이나 그 칸에서 상호작용할 수 있는 표식 (가장 가까운 것)
func interactable_near(c: Vector2i) -> String:
	var best := ""
	var best_d := 99
	for key in marks:
		var m: Dictionary = marks[key]
		if m.level != level or not active(key) or hidden(key):
			continue
		if not ["door", "secret", "feature", "npc", "stairs", "exit"].has(m.type):
			continue
		if m.type == "door" and is_open(key) and not m.has("open_text"):
			continue
		if m.type == "secret" and opened.has(key):
			continue
		if m.type == "feature" and bool(m.get("once", false)) and used.has(key) and not m.has("after_text"):
			continue
		var mc: Vector2i = m.cell
		var d := maxi(absi(mc.x - c.x), absi(mc.y - c.y))
		if d <= 1 and d < best_d:
			best_d = d
			best = key
	return best


## 상호작용 안내 문구 ("F: 문 열기 — 서재 문")
func prompt(key: String) -> String:
	var m: Dictionary = marks[key]
	var nm := str(m.get("name", ""))
	match m.type:
		"door", "secret":
			if m.type == "door" and is_open(key):
				return "살펴보기 — " + nm
			return ("문 열기" if not is_locked(key) else "문 열기 (잠김)") + (" — " + nm if nm != "" else "")
		"npc":
			return "말 걸기 — " + nm
		"stairs":
			return str(m.get("verb", "계단 이용")) + " — " + nm
		"exit":
			return str(m.get("verb", "나가기")) + " — " + nm
	return str(m.get("verb", "조사하기")) + " — " + nm


func is_locked(key: String) -> bool:
	var m: Dictionary = marks[key]
	if not bool(m.get("locked", false)) or used.has(key + "#unlocked"):
		return false
	return cond(m.get("locked_if", null))


# =====================================================================
# 파티
# =====================================================================

func party_creatures() -> Array[Creature]:
	var cs: Array[Creature] = []
	for h in heroes:
		cs.append((h as HeroState).make_creature())
	return cs


func passive_perception() -> int:
	var best := 0
	for c in party_creatures():
		best = maxi(best, c.passive_perception())
	return best


## 기술 판정. who: "best"(가장 잘하는 파티원), "fighter"/"cleric". 반환 {success, total, text, hero}
func check(skill: String, dc: int, who := "best") -> Dictionary:
	var cs := party_creatures()
	var pick: Creature = null
	var pi := 0
	for i in cs.size():
		var c := cs[i]
		if who != "best" and (heroes[i] as HeroState).cls != who:
			continue
		if pick == null or c.skill_bonus(skill) > pick.skill_bonus(skill):
			pick = c
			pi = i
	if pick == null:
		pick = cs[0]
	var r := dice.roll_die(20)
	var b := pick.skill_bonus(skill)
	var total := r + b
	var ok := total >= dc
	var txt := "%s %s 판정: d20 %d %+d = %d vs DC %d → %s" % [pick.display_name, Rules.SKILL_NAMES.get(skill, skill),
		r, b, total, dc, "[color=lime]성공[/color]" if ok else "[color=#f88]실패[/color]"]
	return {"success": ok, "total": total, "text": txt, "hero": pi}


func save(ability: String, dc: int, hero: int) -> Dictionary:
	var c := (heroes[hero] as HeroState).make_creature()
	var a := Rules.ABILITY_NAMES.find(ability.to_upper())
	var r := dice.roll_die(20)
	var b := c.save_bonus(a)
	var ok := r + b >= dc
	return {"success": ok, "text": "%s %s 내성: d20 %d %+d = %d vs DC %d → %s" % [c.display_name, ability.to_upper(),
		r, b, r + b, dc, "[color=lime]성공[/color]" if ok else "[color=#f88]실패[/color]"]}


static func roll_expr(d: Dice, expr: String) -> int:
	# "2d10+3", "1d6", "5"
	var total := 0
	var s := expr.replace(" ", "").replace("-", "+-")
	for part in s.split("+", false):
		if part.contains("d"):
			var p := part.split("d")
			var n := int(p[0]) if p[0] != "" else 1
			var neg := n < 0
			var sum := Dice.sum(d.roll(absi(n), int(p[1])))
			total += -sum if neg else sum
		else:
			total += int(part)
	return total


## 전투 밖 피해. 0이 되면 쓰러졌다가 동료가 돌봐 1로 일어남 [변경]. 모두 0이면 패배
func hurt(hero: int, amount: int) -> String:
	var h: HeroState = heroes[hero]
	var hp := h.current_hp() - amount
	if hp <= 0:
		h.hp = 0
		var all_down := heroes.all(func(x: HeroState) -> bool: return x.hp == 0)
		if all_down:
			return "%s 쓰러짐!" % h.display_name()
		h.hp = 1
		return "%s 쓰러졌다가 동료의 도움으로 겨우 일어남 (HP 1)" % h.display_name()
	h.hp = hp
	return "%s HP %d/%d" % [h.display_name(), hp, h.max_hp()]


func party_down() -> bool:
	return heroes.all(func(x: HeroState) -> bool: return x.hp == 0)


# =====================================================================
# 탐험 이벤트
# =====================================================================

## 플레이어가 새 칸에 들어섬
func enter_cell(from: Vector2i, to: Vector2i) -> void:
	cell = to
	_see_around(to)
	# 함정
	var tk: String = mark_at[level].get(to, "")
	if tk != "" and marks[tk].type == "trap" and active(tk) and not used.has(tk):
		if revealed.has(tk):
			if not used.has(tk + "#warned"):
				used[tk + "#warned"] = true
				out.append({"type": "toast", "text": "찾아 둔 함정을 조심해서 지나감"})
		else:
			_spring_trap(tk)
	# 근처 함정·비밀을 수동 지각으로 알아챔 (2칸 안)
	_passive_notice(to, 2)
	var rk := room_of(level, to)
	if rk != room_key:
		room_key = rk
		if rk != "":
			_enter_room(rk)


func _enter_room(rk: String) -> void:
	var def: Dictionary = rooms[rk].def
	var first := not visited.has(rk)
	visited[rk] = true
	for c in rooms[rk].cells:
		_mark_seen(c)
		for d in Dungeon.DIRS8:
			_mark_seen(c + d)
	if first and def.has("text"):
		out.append({"type": "text", "title": room_name(rk), "text": str(def.text)})
	if first and def.has("on_enter"):
		run(def.on_enter)
	if def.has("hazard"):
		var hz: Dictionary = def.hazard
		if cond(hz.get("if", null)):
			_hazard(hz, room_name(rk))
	# 들어서면 시작되는 조우
	for g in groups_here(level):
		var gd := group_def(g)
		if str(gd.get("trigger", "enter")) != "enter":
			continue
		if gd.has("trigger_if") and not cond(gd.trigger_if):
			continue  # 적은 보이지만 조건이 맞을 때만 들어서면 전투 (대화로 적대한 뒤 등)
		for f in foes_of(g):
			if room_of(level, f.cell) == rk:
				out.append({"type": "battle", "group": g})
				return


func _hazard(hz: Dictionary, where: String) -> void:
	var lines := PackedStringArray([str(hz.get("text", ""))])
	for i in heroes.size():
		var dmg := roll_expr(dice, str(hz.get("damage", "1d6")))
		if hz.has("save"):
			var sv := save(str(hz.save), int(hz.get("dc", 10)), i)
			lines.append(sv.text)
			if sv.success:
				if bool(hz.get("half", false)):
					dmg = dmg / 2
				else:
					continue
		lines.append("  %d %s 피해 → %s" % [dmg, _dtype(str(hz.get("type", ""))), hurt(i, dmg)])
	out.append({"type": "text", "title": where, "text": "\n".join(lines)})
	_check_party_down()


func _spring_trap(tk: String) -> void:
	var m: Dictionary = marks[tk]
	used[tk] = true
	revealed[tk] = true
	var lines := PackedStringArray([str(m.get("text", "함정이다!"))])
	var hero := 0
	var dmg := roll_expr(dice, str(m.get("damage", "1d6")))
	if m.has("save"):
		var sv := save(str(m.save), int(m.get("dc", 12)), hero)
		lines.append(sv.text)
		if sv.success:
			dmg = 0
			lines.append("  " + str(m.get("save_text", "아슬아슬하게 피했다.")))
	if dmg > 0:
		lines.append("  %d %s 피해 → %s" % [dmg, _dtype(str(m.get("dtype", ""))), hurt(hero, dmg)])
	out.append({"type": "text", "title": str(m.get("name", "함정")), "text": "\n".join(lines)})
	out.append({"type": "refresh"})
	_check_party_down()


func _check_party_down() -> void:
	if party_down():
		out.append({"type": "end", "result": "lose", "title": "쓰러졌다", "text": "파티가 모두 쓰러졌습니다. 마지막 체크포인트에서 다시 시작합니다."})


func _dtype(t: String) -> String:
	const N := {"piercing": "관통", "slashing": "참격", "bludgeoning": "타격", "fire": "화염", "cold": "냉기",
		"poison": "독", "necrotic": "사령", "radiant": "광휘", "psychic": "정신", "acid": "산성"}
	return N.get(t, t)


## 수동 지각으로 근처 비밀을 알아챔 (탐색하지 않아도)
func _passive_notice(c: Vector2i, radius: int) -> void:
	var pp := passive_perception()
	for key in marks:
		var m: Dictionary = marks[key]
		if m.level != level or revealed.has(key) or not active(key):
			continue
		var dc := _hidden_dc(m)
		if dc < 0 or not bool(m.get("passive", true)):
			continue
		var mc: Vector2i = m.cell
		if maxi(absi(mc.x - c.x), absi(mc.y - c.y)) > radius or pp < dc:
			continue
		_reveal(key, "수동 지각 %d" % pp)


func _hidden_dc(m: Dictionary) -> int:
	if m.type == "secret" or m.type == "trap":
		return int(m.get("dc_find", m.get("hidden_dc", 15)))
	if m.has("hidden_dc"):
		return int(m.hidden_dc)
	return -1


func _reveal(key: String, why := "") -> void:
	if revealed.has(key):
		return
	revealed[key] = true
	var m: Dictionary = marks[key]
	var txt := str(m.get("found_text", ""))
	if txt == "":
		match m.type:
			"secret": txt = "숨겨진 문을 찾았다!"
			"trap": txt = "함정을 찾았다!"
			_: txt = "숨겨진 것을 찾았다: " + str(m.get("name", ""))
	out.append({"type": "text", "title": "발견" + ((" (%s)" % why) if why != "" else ""), "text": txt})
	out.append({"type": "refresh"})


## 지금 방을 꼼꼼히 수색 (방마다 한 번): 파티에서 지각이 가장 좋은 사람이 굴림
func search() -> void:
	var rk := room_key
	var key := rk if rk != "" else "%s:%d,%d" % [level, cell.x, cell.y]
	if searched.has(key):
		out.append({"type": "toast", "text": "이미 꼼꼼히 살펴본 곳이다"})
		return
	searched[key] = true
	var r := check("perception", 0)
	var total: int = r.total
	var found := 0
	var area: Array = rooms[rk].cells if rk != "" else _cells_within(cell, 3)
	var area_set := {}
	for c in area:
		area_set[c] = true
		for d in Dungeon.DIRS8:
			area_set[c + d] = true  # 방 벽에 붙은 비밀문
	for k in marks:
		var m: Dictionary = marks[k]
		if m.level != level or revealed.has(k) or not active(k) or not area_set.has(m.cell):
			continue
		var dc := _hidden_dc(m)
		if dc >= 0 and total >= dc:
			found += 1
			_reveal(k)
	var txt := "%s\n%s" % [str(r.text).replace(" vs DC 0 → [color=lime]성공[/color]", ""),
		"새로 찾은 것은 없다." if found == 0 else "무언가를 찾았다!"]
	if rk != "" and rooms[rk].def.has("search_text") and found == 0:
		txt += "\n" + str(rooms[rk].def.search_text)
	out.insert(out.size() - found * 2, {"type": "text", "title": "수색", "text": txt})


func _cells_within(c: Vector2i, r: int) -> Array:
	var a: Array = []
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			a.append(c + Vector2i(x, y))
	return a


## 상호작용 (F 키)
func interact(key: String) -> void:
	var m: Dictionary = marks[key]
	match m.type:
		"door", "secret":
			_try_door(key)
		"npc":
			if m.has("dialogue"):
				start_dialogue(str(m.dialogue))
			else:
				out.append({"type": "text", "title": str(m.get("name", "")), "text": str(m.get("text", ""))})
		"stairs":
			if m.has("if_not_text") and not cond(m.get("use_if", null)):
				out.append({"type": "text", "title": str(m.get("name", "")), "text": str(m.if_not_text)})
				return
			run(m.get("do", []))
			go_to(str(m.to_level), str(m.to_mark))
		"exit":
			if not cond(m.get("use_if", null)):
				out.append({"type": "text", "title": str(m.get("name", "")), "text": str(m.get("if_not_text", "아직 떠날 수 없다."))})
				return
			run(m.get("do", []))
		_:
			_use_feature(key)


func _use_feature(key: String) -> void:
	var m: Dictionary = marks[key]
	var first := not used.has(key)
	if not first and bool(m.get("once", false)):
		if m.has("after_text"):
			out.append({"type": "text", "title": str(m.get("name", "")), "text": str(m.after_text)})
		return
	used[key] = true
	if bool(m.get("once", false)):
		out.append({"type": "refresh"})
	if m.has("text") and (first or not m.has("after_text")):
		out.append({"type": "text", "title": str(m.get("name", "")), "text": str(m.text)})
	elif m.has("after_text"):
		out.append({"type": "text", "title": str(m.get("name", "")), "text": str(m.after_text)})
	if first or not bool(m.get("once", false)):
		run(m.get("do", []))


func _try_door(key: String) -> void:
	var m: Dictionary = marks[key]
	var nm := str(m.get("name", "문"))
	if m.type == "door" and is_open(key):
		out.append({"type": "text", "title": nm, "text": str(m.get("open_text", "열려 있다."))})
		return
	if m.type == "secret":
		opened[key] = true
		out.append({"type": "text", "title": nm, "text": str(m.get("text", "숨겨진 문이 삐걱이며 열린다."))})
		run(m.get("do", []))
		out.append({"type": "refresh"})
		return
	if is_locked(key):
		var k := str(m.get("key", ""))
		if k != "" and items.has(k):
			used[key + "#unlocked"] = true
			out.append({"type": "text", "title": nm, "text": "%s(으)로 자물쇠를 열었다." % items[k].name})
		elif used.has(key + "#tried"):
			out.append({"type": "text", "title": nm, "text": str(m.get("locked_text", "잠겨 있다.")) + "\n(한 번 실패했다. 열쇠를 찾아야 한다.)"})
			return
		elif m.has("force_dc"):
			used[key + "#tried"] = true
			var r := check(str(m.get("force_skill", "athletics")), int(m.force_dc))
			if r.success:
				used[key + "#unlocked"] = true
				out.append({"type": "text", "title": nm, "text": str(m.get("locked_text", "잠겨 있다.")) + "\n" + str(r.text) + "\n문을 억지로 열었다!"})
			else:
				out.append({"type": "text", "title": nm, "text": str(m.get("locked_text", "잠겨 있다.")) + "\n" + str(r.text) + "\n꿈쩍도 하지 않는다."})
				return
		else:
			out.append({"type": "text", "title": nm, "text": str(m.get("locked_text", "잠겨 있다."))})
			return
	opened[key] = true
	if m.has("text"):
		out.append({"type": "text", "title": nm, "text": str(m.text)})
	run(m.get("do", []))
	out.append({"type": "refresh"})


func go_to(lid: String, ch: String) -> void:
	var to := mark_cell(lid, ch)
	var changed := lid != level
	level = lid
	cell = to
	room_key = ""
	out.append({"type": "level", "level": lid, "cell": to, "changed": changed})
	if changed and bool((data.levels[lid] as Dictionary).get("checkpoint", true)):
		out.append({"type": "toast", "text": "체크포인트 — " + level_name()})


## 화면이 새 위치에 플레이어를 놓은 뒤 부름. 방이 바뀌었으면 방 이벤트
func on_arrived() -> void:
	_see_around(cell)
	var rk := room_of(level, cell)
	if rk != room_key:
		room_key = rk
		if rk != "":
			_enter_room(rk)


## 둘레 1칸, 방 밖(복도)이면 바닥을 따라 3걸음까지 보임
func _see_around(c: Vector2i) -> void:
	_mark_seen(c)
	for d in Dungeon.DIRS8:
		_mark_seen(c + d)
	var rk := room_of(level, c)
	if rk != "":
		for rc in rooms[rk].cells:
			_mark_seen(rc)
			for d in Dungeon.DIRS8:
				_mark_seen(rc + d)  # 방 벽과 문
		return
	var dg := dungeon()
	var dist := {c: 0}
	var q: Array[Vector2i] = [c]
	while not q.is_empty():
		var cur: Vector2i = q.pop_front()
		if dist[cur] >= 3:
			continue
		for d in Dungeon.DIRS4:
			var n: Vector2i = cur + d
			if dist.has(n) or not dg.is_floor(n):
				continue
			dist[n] = dist[cur] + 1
			_mark_seen(n)
			for d2 in Dungeon.DIRS8:
				_mark_seen(n + d2)
			if not _is_boundary(level, n) and room_of(level, n) == "":
				q.append(n)


func _mark_seen(c: Vector2i) -> void:
	if not seen.has(level):
		seen[level] = {}
	seen[level][c] = true


func is_seen(c: Vector2i) -> bool:
	return seen.get(level, {}).has(c)


# =====================================================================
# 대화
# =====================================================================

func start_dialogue(did: String, node := "") -> void:
	var dd: Dictionary = data.get("dialogues", {}).get(did, {})
	if dd.is_empty():
		push_error("대화 없음: " + did)
		return
	var n := node if node != "" else str(dd.get("start", "start"))
	dialogue = {"id": did, "node": n}
	_show_node()


func _node() -> Dictionary:
	return data.dialogues[dialogue.id].nodes.get(dialogue.node, {})


func _show_node() -> void:
	var nd := _node()
	run(nd.get("do", []))
	var choices: Array = []
	var all_c: Array = nd.get("choices", [])
	for i in all_c.size():
		var ch: Dictionary = all_c[i]
		if not cond(ch.get("if", null)):
			continue
		if bool(ch.get("once", false)) and used.has("%s/%s/%d" % [dialogue.id, dialogue.node, i]):
			continue
		var label := str(ch.text)
		if ch.has("check"):
			label += " [%s DC %d]" % [Rules.SKILL_NAMES.get(str(ch.check.skill), str(ch.check.skill)), int(ch.check.dc)]
		choices.append({"text": label, "index": i})
	if choices.is_empty():
		choices.append({"text": "(대화를 마친다)", "index": -1})
	var speaker := str(nd.get("speaker", data.dialogues[dialogue.id].get("speaker", "")))
	out.append({"type": "dialogue", "speaker": speaker, "text": str(nd.get("text", "")), "choices": choices})


## 대화 선택지 고르기 (index는 노드의 choices 안 번호, -1은 끝내기)
func choose(index: int) -> void:
	if dialogue.is_empty():
		return
	if index < 0:
		dialogue = {}
		out.append({"type": "dialogue_end"})
		return
	var ch: Dictionary = _node().choices[index]
	used["%s/%s/%d" % [dialogue.id, dialogue.node, index]] = true
	var nxt := str(ch.get("next", ""))
	var pre := PackedStringArray()
	if ch.has("check"):
		var r := check(str(ch.check.skill), int(ch.check.dc), str(ch.check.get("who", "best")))
		pre.append(str(r.text))
		nxt = str(ch.check.get("success" if r.success else "fail", nxt))
		run(ch.check.get("do_success" if r.success else "do_fail", []))
	if not pre.is_empty():
		out.append({"type": "toast", "text": "\n".join(pre), "long": true})
	run(ch.get("do", []))
	if nxt == "" or nxt == "end" or dialogue.is_empty():
		dialogue = {}
		out.append({"type": "dialogue_end"})
		return
	dialogue.node = nxt
	_show_node()


# =====================================================================
# 행동 (actions)
# =====================================================================

## 행동 목록 실행. 각 행동은 {"do": 종류, ...}이고 "if"가 있으면 참일 때만
func run(actions: Variant) -> void:
	if not actions is Array:
		return
	for a in actions:
		if not a is Dictionary:
			continue
		var act: Dictionary = a
		if not cond(act.get("if", null)):
			if act.has("else"):
				run(act["else"])
			continue
		_do(act)


func _do(a: Dictionary) -> void:
	match str(a.get("do", "")):
		"text":
			out.append({"type": "text", "title": str(a.get("title", "")), "text": str(a.text)})
		"doc":
			var doc := {"title": str(a.title), "text": str(a.text)}
			if not journal.any(func(j: Dictionary) -> bool: return j.title == doc.title):
				journal.append(doc)
			out.append({"type": "doc", "title": doc.title, "text": doc.text})
		"give":
			var iid := str(a.item)
			var it: Dictionary = items.get(iid, {"name": str(a.get("name", iid)), "count": 0})
			it.count = int(it.count) + int(a.get("count", 1))
			items[iid] = it
			out.append({"type": "toast", "text": "얻음: " + str(it.name)})
		"take":
			items.erase(str(a.item))
		"gold":
			gold += int(a.amount)
			out.append({"type": "toast", "text": "금화 %+d (모두 %d)" % [int(a.amount), gold]})
		"potion":
			var h: HeroState = heroes[0]
			h.resources["potion"] = h.potions() + int(a.get("count", 1))
			out.append({"type": "toast", "text": "회복 물약 +%d" % int(a.get("count", 1))})
		"flag":
			if a.has("set"):
				flags[str(a.set)] = true
			if a.has("clear"):
				flags.erase(str(a.clear))
		"reveal":
			_reveal(str(a.get("level", level)) + ":" + str(a.mark))
		"open":
			opened[str(a.get("level", level)) + ":" + str(a.mark)] = true
			out.append({"type": "refresh"})
		"battle":
			out.append({"type": "battle", "group": str(a.group)})
		"dialogue":
			start_dialogue(str(a.id), str(a.get("node", "")))
		"check":
			var r := check(str(a.skill), int(a.dc), str(a.get("who", "best")))
			out.append({"type": "toast", "text": str(r.text), "long": true})
			run(a.get("success" if r.success else "fail", []))
		"damage":
			_hazard(a, str(a.get("title", "")))
		"heal":
			for h in heroes:
				if str(a.get("amount", "full")) == "full":
					(h as HeroState).hp = -1
				else:
					(h as HeroState).hp = mini((h as HeroState).current_hp() + int(a.amount), (h as HeroState).max_hp())
			out.append({"type": "toast", "text": "파티가 회복했다"})
		"short_rest":
			var lines := PackedStringArray()
			for h in heroes:
				var hs: HeroState = h
				while hs.current_hp() < hs.max_hp() and hs.hit_dice_left() > 0:
					var r2 := hs.spend_hit_die(dice)
					if r2.is_empty():
						break
					lines.append("%s 히트 다이스 d%d %d → +%d" % [hs.display_name(), hs.hit_die(), r2.roll, r2.heal])
				hs.finish_short_rest()
			out.append({"type": "text", "title": "짧은 휴식", "text": "\n".join(lines) if not lines.is_empty() else "숨을 고르며 장비를 정비했다."})
		"long_rest":
			for h in heroes:
				(h as HeroState).long_rest()
			out.append({"type": "toast", "text": "긴 휴식 — HP와 주문 슬롯이 모두 돌아왔다"})
		"xp":
			_add_xp(int(a.amount), str(a.get("why", "")))
		"level_to":
			var need: int = Rules.XP_THRESHOLDS[clampi(int(a.level), 1, 6) - 1]
			for h in heroes:
				if (h as HeroState).xp < need:
					_add_xp_to(h, need - (h as HeroState).xp)
		"teleport":
			go_to(str(a.get("level", level)), str(a.mark))
		"checkpoint":
			save_checkpoint()
			out.append({"type": "toast", "text": "체크포인트 저장"})
		"end":
			ended = true
			out.append({"type": "end", "result": str(a.get("result", "win")), "title": str(a.get("title", "끝")), "text": str(a.get("text", ""))})
		"toast":
			out.append({"type": "toast", "text": str(a.text)})
		_:
			push_error("알 수 없는 행동: " + str(a))


func _add_xp(amount: int, why: String) -> void:
	var lines := PackedStringArray()
	for h in heroes:
		var up := _add_xp_to(h, amount)
		if up > 0:
			lines.append("%s %d레벨!" % [(h as HeroState).display_name(), up])
	var msg := "경험치 +%d%s" % [amount, (" (%s)" % why) if why != "" else ""]
	if not lines.is_empty():
		msg += " — 레벨 업! " + ", ".join(lines)
	out.append({"type": "toast", "text": msg})


## XP를 더하고 레벨이 오르면 새 레벨 (HeroState.absorb와 같은 규칙)
func _add_xp_to(h: HeroState, amount: int) -> int:
	var c := h.make_creature()
	c.hp = h.current_hp()
	var up: Dictionary = h.absorb(c, amount)
	if h.hp >= 0 and h.hp < 1:
		h.hp = 1
	return int(up.get("level_up", 0))


# =====================================================================
# 전투 연결
# =====================================================================

## 조우 그룹을 전투 장면용 지도로 잘라냄 (Battle.custom 형식)
func battle_setup(g: String) -> Dictionary:
	var dg := dungeon()
	var fs := foes_of(g)
	var rect := Rect2i(cell, Vector2i.ONE)
	var rk := room_key
	if rk != "":
		for c in rooms[rk].cells:
			rect = rect.expand(c)
	for f in fs:
		rect = rect.expand(f.cell)
	rect = Rect2i(rect.position, rect.size + Vector2i.ONE).grow(1).intersection(Rect2i(0, 0, dg.width, dg.height))
	var blk := blocked()
	var map: Array[String] = []
	for y in rect.size.y:
		var row := ""
		for x in rect.size.x:
			var c := rect.position + Vector2i(x, y)
			var mk: String = mark_at[level].get(c, "")
			var solid := blk.has(c) and not _is_foe_cell(c, fs)
			if not dg.is_floor(c) or solid:
				row += "X"
			elif mk != "" and marks[mk].type == "door" and not is_open(mk):
				row += "X"
			elif dg.obstacles.has(c):
				row += "P" if dg.obstacles[c] >= 2.0 else "#"
			elif dg.difficult.has(c):
				row += ","
			elif dg.get_height(c) >= 1.0:
				row += "2"
			elif dg.get_height(c) > 0.0:
				row += "1"
			else:
				row += "."
		map.append(row)
	var foes: Array = []
	for f in fs:
		foes.append([str(f.monster), (f.cell as Vector2i) - rect.position])
	var gd := group_def(g)
	return {"map": map, "pc_start": cell - rect.position, "foes": foes, "label": str(gd.get("label", g)),
		"theme": "dungeon", "style": level_style(), "group": g, "monster_defs": data.get("monsters", {}),
		"surprised": int(gd.get("surprised", -1)) if not flags.has("surprise:" + g) else 1}


func _is_foe_cell(c: Vector2i, fs: Array) -> bool:
	for f in fs:
		if f.cell == c:
			return true
	return false


## 전투 결과를 받음. result: "win" / "lose" / 그 밖(도망)
func battle_result(g: String, result: String, retreat: Vector2i) -> void:
	if party_down() and result != "win":
		result = "lose"
	match result:
		"win":
			cleared[g] = true
			out.append({"type": "refresh"})
			run(group_def(g).get("after", []))
		"lose":
			out.append({"type": "end", "result": "lose", "title": "쓰러졌다", "text": "파티가 쓰러졌습니다. 마지막 체크포인트에서 다시 시작합니다."})
		_:
			cell = retreat
			room_key = room_of(level, cell)
			out.append({"type": "toast", "text": "물러났다"})
