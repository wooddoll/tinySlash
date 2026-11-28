extends Node3D

const InputSetup = preload("res://scripts/input_setup.gd")
const Kenney = preload("res://scripts/kenney.gd")
const Outdoor = preload("res://scripts/outdoor_terrain.gd")
const DungeonView = preload("res://scripts/dungeon_view.gd")
const ActionLayer = preload("res://scripts/action_layer.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Monsters = preload("res://scripts/outdoor_monsters.gd")
const Game = preload("res://scripts/game.gd")
const Village = preload("res://rules/village.gd")
const TownBuilder = preload("res://scripts/town_builder.gd")
const TownDialog = preload("res://scripts/town_dialog.gd")
const Quests = preload("res://rules/quests.gd")
const Region = preload("res://rules/region.gd")
const RegionMap = preload("res://scripts/region_map.gd")
const Minimap = preload("res://scripts/minimap.gd")
const Loading = preload("res://scripts/loading.gd")
const Reputation = preload("res://rules/reputation.gd")
const Ambience = preload("res://scripts/ambience.gd")
const Music = preload("res://scripts/music.gd")
const PauseMenu = preload("res://scripts/pause_menu.gd")
const LevelUpDialog = preload("res://scripts/level_up_dialog.gd")
## 바깥에 있는 동안 이만큼(초)마다 저장
const AUTOSAVE_EVERY := 60.0

@export var tree_count := 40
@export var grass_count := 150
@export var decor_count := 40
@export var world_half_size := 18.0

@onready var decor: Node3D = $Decor
## 0이면 실행할 때마다 새 지형
@export var terrain_seed := 0

## 이번 판의 바깥 세상 시드 (던전에 다녀와도 같은 지형), 던전에서 돌아왔으면 입구 앞에서 시작
static var world_seed: int:
	get: return Game.world_seed
	set(v): Game.world_seed = v
static var back_from_dungeon := false
## 이 세상에서 물리친 바깥 몬스터 무리 번호
static var defeated: Dictionary:
	get: return Game.defeated
	set(v): Game.defeated = v
## 바깥 전투 격자 크기 (칸), 이만큼 멀어지면 도망친 것으로 봄
const FIGHT_SIZE := 40
const FLEE_DIST := 14.0
## 여관 하룻밤 값 (긴 휴식)
const INN_PRICE := 10
## 문·의뢰판 앞에서 이만큼 가까우면 Enter/F/Y로 들어감
const USE_DIST := 1.6
## 바깥에서 실제 1초에 흐르는 게임 분
const MINUTES_PER_SECOND := 1.0
## 마을 곡이 들리는 거리 (빈터 가운데에서, 칸)
const VILLAGE_MUSIC_RADIUS := 40.0

## 만든 지형 (Terrain3D가 없으면 null: 예전 평평한 풀밭 + Kenney 나무)
var outdoor: Node3D = null
var monsters: Node3D = null
## 바깥 전투 중이면 그 ActionLayer, 싸우는 무리 번호, 파티원 Actor들
var fight: Node3D = null
var fight_group := -1
var fight_members: Array = []
var _flee_time := 0.0
## 빈터의 마을 (rules/village.gd 배치, scripts/town_builder.gd가 세움)
var village = null
var town: Node3D = null
var dialog: CanvasLayer = null
var _use_hint: Label = null
## 지금 가까이 있는 마을 자리: {kind, name} 또는 빈 사전
var _near := {}
## 지방 (rules/region.gd), 지도 창
var region = null
var region_map: CanvasLayer = null
var minimap: CanvasLayer = null
var _minute_acc := 0.0
var _clock: Label = null
var _stream_in := 0.0
var _toast_label: Label
var _toast_left := 0.0
var _pending_toast := ""
var _autosave_in := AUTOSAVE_EVERY


var ambience: AudioStreamPlayer = null
var pause_menu: CanvasLayer
var level_dialog: LevelUpDialog
var _level_poll := 0.0


func _ready() -> void:
	InputSetup.register()
	get_tree().paused = false
	pause_menu = PauseMenu.new()
	pause_menu.save_fn = _autosave
	add_child(pause_menu)
	var top := CanvasLayer.new()
	top.layer = 10
	add_child(top)
	level_dialog = LevelUpDialog.new()
	level_dialog.visible = false
	top.add_child(level_dialog)
	level_dialog.finished.connect(func() -> void:
		($Player as Node3D).set_physics_process(true)
		monsters.set_process(true)
		_autosave())
	ambience = Ambience.new()
	ambience.name = "Ambience"
	add_child(ambience)
	if not _build_terrain():
		_scatter_decor()
	_add_hint()
	if _pending_toast != "":
		_toast(_pending_toast)
	_update_music()


## 마을 가까이는 마을 곡, 그 밖은 들판 곡 (1초마다 봄)
var _music_check := 0.0


func _update_music() -> void:
	var near_village := village != null and ($Player as Node3D).global_position.length() < VILLAGE_MUSIC_RADIUS
	Music.play(self, "village" if near_village else "field")


## Terrain3D가 설치돼 있으면 지방 전체(3x3 칸)를 한 지형으로 만들고 평평한 바닥·연습용 돌 블록을 치움 (M5 뒤 심리스).
## 마을은 가운데 칸 빈터에. 나무·풀·몬스터는 플레이어가 가까이 가는 칸부터 채움 (_stream_near).
## 세계 좌표: 마을 칸 가운데 = (0, 0). 지금 칸(Game.tile)은 플레이어 자리로 정해짐
func _build_terrain() -> bool:
	if not Outdoor.available():
		return false
	if world_seed == 0:
		world_seed = terrain_seed if terrain_seed != 0 else randi() % 100000 + 1
	region = Game.region()
	outdoor = Outdoor.new()
	outdoor.name = "Outdoor"
	add_child(outdoor)
	village = Village.generate(world_seed, Outdoor.entrance_dir(world_seed))
	if not outdoor.generate_region(region, world_seed, village.blocked):
		outdoor.queue_free()
		outdoor = null
		village = null
		return false
	$Ground.queue_free()
	$Props.queue_free()
	town = TownBuilder.new()
	town.name = "Town"
	add_child(town)
	town.build(village, outdoor.height_at, world_seed)
	town.focus = $Player
	dialog = TownDialog.new()
	add_child(dialog)
	dialog.closed.connect(_dialog_closed)
	region_map = RegionMap.new()
	add_child(region_map)
	region_map.travel.connect(_fast_travel)
	region_map.closed.connect(_dialog_closed)
	outdoor.entrance_entered.connect(_enter_dungeon)
	# 처음엔 마을 광장. 던전에서 나왔으면 그 던전 입구 앞, 빠른 이동이면 도착한 자리, 불러왔으면 저장한 자리
	var player := $Player as Node3D
	player.global_position = Vector3(0, outdoor.height_at(Vector3.ZERO) + 0.5, 0)
	var calm := 0.0
	if back_from_dungeon:
		back_from_dungeon = false
		player.global_position = outdoor.before_entrance(Game.tile)
	var arrive = Game.arrival
	Game.arrival = null
	if arrive is String and arrive == "entrance":
		player.global_position = outdoor.before_entrance(Game.tile)
		calm = 3.0
	elif arrive is Vector2:
		player.global_position = Vector3(arrive.x, outdoor.height_at(Vector3(arrive.x, 0, arrive.y)) + 0.5, arrive.y)
		calm = 3.0
	var loaded := Game.take_load_pos()
	if loaded != Vector3.INF:
		player.global_position = loaded + Vector3(0, 0.3, 0)
		calm = 4.0  # 불러온 자리 바로 옆에 몬스터가 있어도 잠깐은 덤비지 않음
	Game.tile = Outdoor.tile_of(player.global_position)
	if loaded != Vector3.INF:
		_pending_toast = "이어서 합니다 — " + region.tiles[Game.tile].name
	elif arrive != null:
		_pending_toast = _tile_title(Game.tile)
	# 무리 자리는 모든 칸에 미리 정하고, 모델은 가까운 것만
	monsters = Monsters.new()
	monsters.name = "Monsters"
	add_child(monsters)
	monsters.player = player
	for t in region.tiles:
		monsters.plan_tile(outdoor, t, Region.tile_seed(world_seed, t), defeated, Region.index(t) * 100,
			Region.offset(t, Outdoor.SIZE), t == Region.VILLAGE)
	monsters.calm = calm
	monsters.engaged.connect(_fight_outdoor)
	outdoor.map_image(village.buildings)  # 지도 그림을 일꾼 스레드에서 만들기 시작
	region_map.setup(outdoor, player, monsters, village.buildings)
	minimap = Minimap.new()
	minimap.setup(outdoor, player, $CameraRig, region, monsters, village.buildings)
	add_child(minimap)
	outdoor.fill_now(Game.tile)
	monsters.wake_near(player.global_position, 90.0)
	_stream_near()
	_autosave.call_deferred()
	($CameraRig as Node3D).global_position = player.global_position
	$CameraRig.zoom_pitch = Vector2(22.0, 36.0)  # 가까이 당기면 낮게 봐서 언덕이 보이게
	_apply_daylight()
	return true


## p가 칸 t 바깥으로 margin칸보다 더 나갔나 (경계에서 왔다 갔다 할 때 칸 이름이 계속 뜨지 않게)
func _beyond_tile(p: Vector3, t: Vector2i, margin: float) -> bool:
	var off := Region.offset(t, Outdoor.SIZE)
	var half := Outdoor.SIZE / 2.0 + margin
	return absf(p.x - off.x) > half or absf(p.z - off.y) > half


## 칸 이름 (던전이 있으면 "— ○○ 입구가 있는 곳")
func _tile_title(t: Vector2i) -> String:
	var dg: Dictionary = region.dungeon_at(t)
	return region.tiles[t].name + ("" if dg.is_empty() else " — %s 입구가 있는 곳" % dg.name)


## 플레이어 둘레 칸의 나무·풀을 채우고 가까운 몬스터 무리를 세움. 칸이 바뀌면 이름을 띄우고 저장
func _stream_near() -> void:
	if outdoor == null:
		return
	var p := ($Player as Node3D).global_position
	outdoor.ensure_near(p)
	monsters.wake_near(p, 150.0, 1)
	Game.explore(Vector2(p.x, p.z))
	var t := Outdoor.tile_of(p)
	if t != Game.tile and _beyond_tile(p, Game.tile, 4.0):
		Game.tile = t
		_toast(_tile_title(t))
		_apply_daylight()  # 오른쪽 위 칸 이름도 바뀜
		_autosave()


func _process(delta: float) -> void:
	_music_check -= delta
	if _music_check <= 0.0:
		_music_check = 1.0
		_update_music()
	if fight != null:
		_fight_process(delta)
	elif level_dialog.visible:
		pass
	elif dialog != null and not dialog.is_open() and not region_map.is_open():
		# 레벨업 고르기 (보상·바깥 싸움으로 레벨이 오르면 바로)
		_level_poll -= delta
		if _level_poll <= 0.0:
			_level_poll = 0.5
			if level_dialog.open(Game.party()):
				($Player as Node3D).set_physics_process(false)
				monsters.set_process(false)
				_show_use_hint("")
				return
		if village != null:
			_town_process()
		elif Input.is_action_just_pressed("journal"):
			_open_journal()
		if Input.is_action_just_pressed("help") and _hint:
			_toggle_help()
		if Input.is_action_just_pressed("map") and not region_map.just_closed():
			_open_map()
		_flow_time(delta)
		_stream_in -= delta
		if _stream_in <= 0.0:
			_stream_in = 0.25
			_stream_near()
	if outdoor:
		_autosave_in -= delta
		if _autosave_in <= 0.0:
			_autosave()
	_update_xray()
	if minimap:
		minimap.visible = fight == null and not level_dialog.visible and not (dialog.is_open() or region_map.is_open())
	if _toast_left > 0.0:
		_toast_left -= delta
		_toast_label.modulate.a = clampf(_toast_left, 0.0, 1.0)
	if dialog != null and (dialog.is_open() or region_map.is_open()) or level_dialog.visible:
		return
	# 시험용: B 단독 전투, G 던전 생성기, H 시나리오
	if Input.is_action_just_pressed("start_battle"):
		get_tree().change_scene_to_file("res://scenes/battle.tscn")
	elif Input.is_action_just_pressed("open_dungeon"):
		get_tree().change_scene_to_file("res://scenes/dungeon.tscn")
	elif Input.is_action_just_pressed("open_scenario"):
		get_tree().change_scene_to_file("res://scenes/scenario.tscn")


const HINT_SHORT := "WASD 이동 · F 문·의뢰판 · J 일지 · M 지도 · Esc 메뉴 · F1 도움말"
const HINT_FULL := "[조작]\nWASD / 왼쪽 스틱  이동\nSpace  점프 (싸울 땐 구르기)\nEnter / F  문·의뢰판·던전 입구\nJ  일지 (받은 의뢰, 등급·평판)\nM  지방 지도 (내 자리) · 빠른 이동 · 오른쪽 위는 미니맵\nQ / E  카메라 90° 회전 · 휠  줌\n\n[싸움]\nJ / X  공격 · Space  구르기 · K / L  기술 · 1  물약\n\n[시험용]\nB  단독 전투 · G  던전 생성기 · H  모험(시나리오)\n\nEsc  메뉴 (음량·저장)\nF1  도움말 닫기"
var _hint: Label


## F1: 짧은 안내 ↔ 조작 전부 (어두운 판 위에)
func _toggle_help() -> void:
	var full := _hint.text == HINT_SHORT
	_hint.text = HINT_FULL if full else HINT_SHORT
	if full:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.04, 0.03, 0.82)
		sb.set_content_margin_all(12)
		sb.set_corner_radius_all(4)
		_hint.add_theme_stylebox_override("normal", sb)
	else:
		_hint.remove_theme_stylebox_override("normal")


func _add_hint() -> void:
	var layer := CanvasLayer.new()
	var label := Label.new()
	_hint = label
	label.text = HINT_SHORT
	label.position = Vector2(16, 12)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	layer.add_child(label)
	add_child(layer)


## 나무, 풀, 꽃, 바위 같은 Nature Kit 모델을 흩뿌립니다. 나무에는 충돌체를 붙입니다.
func _scatter_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2025

	for i in tree_count:
		var pos := _random_pos(rng, 5.0)
		var tree := Kenney.instance(Kenney.TREES[rng.randi() % Kenney.TREES.size()], Kenney.NATURE)
		tree.scale = Vector3.ONE * rng.randf_range(2.0, 2.8)
		tree.rotation.y = rng.randf() * TAU
		tree.position = pos
		decor.add_child(tree)
		# 나무에 부딪히도록 충돌체 추가
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.25
		cyl.height = 2.0
		shape.shape = cyl
		body.position = pos + Vector3(0, 1.0, 0)
		body.add_child(shape)
		decor.add_child(body)

	for i in grass_count:
		var g := Kenney.instance(Kenney.GRASS[rng.randi() % Kenney.GRASS.size()], Kenney.NATURE)
		g.scale = Vector3.ONE * rng.randf_range(1.6, 2.4)
		g.rotation.y = rng.randf() * TAU
		g.position = _random_pos(rng, 1.5)
		decor.add_child(g)

	for i in decor_count:
		var dcr := Kenney.instance(Kenney.DECOR[rng.randi() % Kenney.DECOR.size()], Kenney.NATURE)
		dcr.scale = Vector3.ONE * rng.randf_range(1.8, 2.6)
		dcr.rotation.y = rng.randf() * TAU
		dcr.position = _random_pos(rng, 3.0)
		decor.add_child(dcr)


func _random_pos(rng: RandomNumberGenerator, keep_clear: float) -> Vector3:
	while true:
		var p := Vector3(rng.randf_range(-world_half_size, world_half_size), 0.0,
				rng.randf_range(-world_half_size, world_half_size))
		if p.length() > keep_clear:
			return p
	return Vector3.ZERO


## 입구 문턱을 넘으면 이 세상 시드로 정한 던전에서 바로 탐험 시작
func _enter_dungeon(_body: Node3D, t: Vector2i) -> void:
	if get_tree().paused or fight != null:
		return
	Game.tile = t
	_autosave()  # 입구 앞 (던전은 들어가서 다시 저장)
	var dg: Dictionary = region.dungeon_at(t)
	Game.dungeon_id = int(dg.id)
	DungeonView.enter_seed = int(dg.seed)
	DungeonView.enter_theme = str(dg.theme)
	DungeonView.enter_algorithm = int(dg.algorithm)
	DungeonView.enter_name = str(dg.name)
	back_from_dungeon = true
	Loading.go.call_deferred(self, "res://scenes/dungeon.tscn", "%s(으)로 들어가는 중…" % dg.name)


## 바깥 몬스터 무리와 마주침: 그 자리 지형 위에서 실시간 액션 전투 (장면을 넘기지 않음, 기획 M2).
## 둘레 FIGHT_SIZE칸을 지형에서 읽어 격자로 만들고(OutdoorTerrain.battle_grid) 던전과 같은 ActionLayer를 그 위에 얹음.
## 파티는 던전 탐험과 같은 HeroState(Game). 이기면 무리는 사라지고, 멀리 도망치면 무리는 제자리로, 지면 빈터에서 다시.
func _fight_outdoor(group: int) -> void:
	if fight != null:
		return
	Game.ensure_party()
	var player := $Player as Node3D
	var foes: Array = monsters.take_group(group)
	var center := player.global_position
	for f in foes:
		center += (f[1] as Vector3)
	center /= foes.size() + 1
	var origin := Vector2i(floori(center.x) - FIGHT_SIZE / 2, floori(center.z) - FIGHT_SIZE / 2)
	var d: Dungeon = outdoor.battle_grid(origin, Vector2i(FIGHT_SIZE, FIGHT_SIZE))
	fight = ActionLayer.new()
	fight.name = "Fight"
	fight.position = Vector3(origin.x, 0, origin.y)
	add_child(fight)
	fight.camera_rig = $CameraRig
	fight.setup(d, {})
	fight_group = group
	fight_members.clear()
	var taken := {}
	var pc := _free_cell(d, _to_cell(origin, player.global_position), taken)
	var heroes := Game.party()
	for i in heroes.size():
		var cell := pc if i == 0 else _free_cell(d, pc, taken)
		fight_members.append(fight.add_member((heroes[i] as HeroState).make_creature(), cell, "player" if i == 0 else "ally"))
	for f in foes:
		fight.add_foe(str(f[0]), _free_cell(d, _to_cell(origin, f[1]), taken), 0)
	fight.ac.wake_room(-1)
	fight.message.connect(_toast)
	fight.fight_over.connect(_fight_won)
	fight.defeated.connect(_fight_lost)
	player.visible = false
	player.set_physics_process(false)
	($CameraRig as Node3D).set("target", fight.views[fight.player].model)
	if town:
		town.focus = fight.views[fight.player].model
	monsters.set_process(false)
	_flee_time = 0.0
	_toast("몬스터 발견! — " + monsters.label(group))
	Sfx.play(self, "alert")


## 월드 자리 → 전투 격자 칸
func _to_cell(origin: Vector2i, p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x) - origin.x, floori(p.z) - origin.y)


## c에서 가장 가까운 서 있을 수 있는 빈 칸 (taken에 적어 둠)
func _free_cell(d: Dungeon, c: Vector2i, taken: Dictionary) -> Vector2i:
	for r in range(0, 8):
		for y in range(c.y - r, c.y + r + 1):
			for x in range(c.x - r, c.x + r + 1):
				var n := Vector2i(x, y)
				if maxi(absi(n.x - c.x), absi(n.y - c.y)) == r and d.is_walkable(n) and not taken.has(n):
					taken[n] = true
					return n
	return c


## 전투 중: 주인공 모델을 전투 위치에 붙이고(ActionLayer는 주인공 위치를 탐험자에게 맡김), 멀리 도망쳤는지 봄
func _fight_process(delta: float) -> void:
	var a = fight.player
	var m: Node3D = fight.views[a].model
	var h: float = fight.dungeon.get_height(Vector2i(floori(a.pos.x), floori(a.pos.y)))
	m.position = Vector3(a.pos.x, lerpf(m.position.y, h, 1.0 - exp(-14.0 * delta)), a.pos.y)
	var near := false
	for b in fight.ac.actors:
		if b.brain == "monster" and b.alive() and b.pos.distance_to(a.pos) < FLEE_DIST:
			near = true
			break
	_flee_time = 0.0 if near else _flee_time + delta
	if _flee_time > 1.5:
		_toast("도망쳤어요")
		_end_fight("flee")


func _fight_won(xp: int) -> void:
	var heroes := Game.party()
	var share := xp / maxi(heroes.size(), 1)
	var level_up := 0
	for i in mini(heroes.size(), fight_members.size()):
		var up: Dictionary = (heroes[i] as HeroState).absorb(fight_members[i].c, share)
		if up.has("level_up"):
			level_up = up.level_up
	defeated[fight_group] = true
	_toast("물리쳤어요! XP +%d씩%s" % [share, ("  — 레벨 업! %d레벨" % level_up) if level_up > 0 else ""])
	Sfx.play(self, "level_up" if level_up > 0 else "win")
	var done := Quests.on_group_defeated(Game.quests, fight_group)
	_end_fight("win")
	if not done.is_empty():
		_quest_news.call_deferred(done)


func _fight_lost() -> void:
	_toast("파티가 모두 쓰러졌어요…")
	Sfx.play(self, "lose")
	await get_tree().create_timer(2.0).timeout
	if fight != null:
		_end_fight("lose")


## 전투를 걷고 바깥 탐험으로 돌아감
func _end_fight(result: String) -> void:
	var heroes := Game.party()
	if result != "win":
		for i in mini(heroes.size(), fight_members.size()):
			(heroes[i] as HeroState).absorb(fight_members[i].c, 0)
	var player := $Player as Node3D
	var a = fight.player
	if result == "lose":
		for h in heroes:
			(h as HeroState).long_rest()
		player.global_position = Vector3(0, outdoor.height_at(Vector3.ZERO) + 0.5, 0)
		_toast("쓰러졌어요… 하루 뒤 광장에서 정신을 차렸어요 (기력 회복)")
		_quest_news.call_deferred([], Game.sleep_until(7))
	else:
		var p := Vector3(fight.position.x + a.pos.x, 0, fight.position.z + a.pos.y)
		p.y = outdoor.height_at(p) + 0.3
		player.global_position = p
	if result != "win":
		monsters.restore_group(fight_group)
	player.visible = true
	player.set_physics_process(true)
	var rig := $CameraRig as Node3D
	rig.set("target", player)
	if town:
		town.focus = player
	rig.set("look_offset", Vector3.ZERO)
	rig.set("zoom_bonus", 0.0)
	fight.queue_free()
	fight = null
	fight_group = -1
	fight_members.clear()
	monsters.calm = 1.0 if result == "win" else 4.0
	monsters.set_process(true)
	_autosave()


## 마을: 문·의뢰판 가까이 가면 안내, Enter/F/Y로 창
func _town_process() -> void:
	var p := ($Player as Node3D).global_position
	var at := Vector2(p.x, p.z)
	var near := {}
	for b in village.buildings:
		if b.kind != "house" and at.distance_to(b.door) < USE_DIST:
			near = {"kind": b.kind, "name": b.name}
	if at.distance_to(village.board + village.board_front * 0.8) < USE_DIST:
		near = {"kind": "board", "name": "의뢰판"}
	_near = near
	_show_use_hint("Enter / F / Y: %s" % near.name if not near.is_empty() else "")
	if not near.is_empty() and Input.is_action_just_pressed("interact"):
		_open_place(str(near.kind))
	elif Input.is_action_just_pressed("journal"):
		_open_journal()


func _show_use_hint(text: String) -> void:
	if _use_hint == null:
		var layer := CanvasLayer.new()
		_use_hint = Label.new()
		_use_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_use_hint.position.y -= 90
		_use_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_use_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_use_hint.add_theme_font_size_override("font_size", 22)
		_use_hint.add_theme_constant_override("outline_size", 8)
		_use_hint.add_theme_color_override("font_outline_color", Color.BLACK)
		layer.add_child(_use_hint)
		add_child(layer)
	_use_hint.text = text


func _open_place(kind: String) -> void:
	Game.ensure_party()
	($Player as Node3D).set_physics_process(false)
	monsters.set_process(false)
	_show_use_hint("")
	Sfx.play(self, "open")
	match kind:
		"inn":
			dialog.open(_inn_text(), [["하룻밤 묵기 (%d골드)" % _inn_price(), _inn_rest, Game.gold >= _inn_price()]])
		"shop":
			dialog.open(_shop_text(), [["회복 물약 사기 (%d골드)" % HeroState.POTION_PRICE, _buy_potion, Game.hero.can_buy_potion(Game.gold)]])
		"guild":
			_open_guild()
		"board":
			_open_board()


func _dialog_closed() -> void:
	($Player as Node3D).set_physics_process(true)
	monsters.set_process(true)
	Sfx.play(self, "close")


func _party_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	for h in Game.party():
		lines.append("%s %d레벨 · HP %d/%d · 히트 다이스 %d/%d" % [h.display_name(), h.level(), h.current_hp(), h.max_hp(), h.hit_dice_left(), h.level()])
	lines.append("물약 %d/%d · 금화 %d" % [Game.hero.potions(), HeroState.MAX_POTIONS, Game.gold])
	return lines


func _inn_text() -> String:
	var b: Dictionary = village.find("inn")
	var lines := PackedStringArray(["[font_size=22]%s[/font_size]" % b.get("name", "여관"),
		"따뜻한 방과 저녁 한 끼. 하룻밤 묵으면 파티 모두 HP·히트 다이스·기능·주문 슬롯을 회복하고 저장해요.", ""])
	lines.append_array(_party_lines())
	if _inn_price() < INN_PRICE:
		lines.append("[color=#9f9]마을 사람들이 반겨 줘서 %d골드에 묵어요 (마을 평판 %d)[/color]" % [_inn_price(), int(Game.rep.village)])
	if Game.gold < _inn_price():
		lines.append("[color=gray]금화가 모자라요 (던전 상자에서 모을 수 있어요)[/color]")
	return "\n".join(lines)


func _inn_rest() -> void:
	if Game.gold < _inn_price():
		return
	Game.gold -= _inn_price()
	for h in Game.party():
		h.long_rest()
	var failed := Game.sleep_until(7)
	_autosave()
	_quest_news([], failed)
	Sfx.play(self, "coins")
	dialog.refresh(_inn_text() + "\n[color=#9f9]푹 쉬었어요 (%d일째). 저장했어요." % Game.day + "[/color]", [Game.gold >= _inn_price()])


## 여관 값 (마을 평판으로 깎임, rules/reputation.gd)
func _inn_price() -> int:
	return Reputation.inn_price(INN_PRICE, int(Game.rep.village))


func _shop_text() -> String:
	var lines := PackedStringArray(["[font_size=22]잡화점[/font_size]", "회복 물약 (2d4+2 회복) %d골드. 무기·방어구는 아직 들어오지 않았어요." % HeroState.POTION_PRICE, ""])
	lines.append_array(_party_lines())
	if Game.hero.potions() >= HeroState.MAX_POTIONS:
		lines.append("[color=gray]물약이 가득 찼어요[/color]")
	elif Game.gold < HeroState.POTION_PRICE:
		lines.append("[color=gray]금화가 모자라요[/color]")
	return "\n".join(lines)


func _buy_potion() -> void:
	if not Game.hero.can_buy_potion(Game.gold):
		return
	Game.gold = Game.hero.buy_potion(Game.gold)
	_autosave()
	Sfx.play(self, "coins")
	dialog.refresh(_shop_text(), [Game.hero.can_buy_potion(Game.gold)])


## 조합 회관 (M6): 가입, 등급과 평판, 정회원부터 공짜 하룻밤, 베테랑에게 마지막 의뢰
func _open_guild(note := "") -> void:
	var lines := PackedStringArray(["[font_size=22]모험가 조합 회관[/font_size]  [color=gray]%s[/color]" % Reputation.rank_name(Game.rank)])
	var buttons := []
	if Game.rank <= 0:
		if Reputation.can_join(Game.rank, int(Game.rep.guild)):
			lines.append("\"%s에 온 걸 환영하네. 조합에 들면 던전 우두머리 일도 맡길 수 있지. 가입비는 없네.\"" % village.name)
			buttons.append(["조합 가입", _join_guild, true])
		else:
			lines.append("\"자네 이름이 좋지 않게 돌고 있어. 마을 일부터 해서 평판을 되찾고 오게.\" (조합 평판 %d)" % int(Game.rep.guild))
	else:
		lines.append("\"어서 오게, %s. 일거리는 광장 의뢰판에 붙여 두었네.\"" % Reputation.rank_name(Game.rank))
		var need := Reputation.next_need(Game.rank)
		lines.append("[color=gray]다음 등급 — %s[/color]" % need if need != "" else "[color=#fd8]조합 최고 등급이에요[/color]")
		if Reputation.free_rest(Game.rank):
			buttons.append(["회관에서 하룻밤 (무료)", _guild_rest, true])
	var fin := Game.final_offer(_quest_world())
	if not fin.is_empty():
		lines.append("")
		lines.append("[color=#fd8]마지막 의뢰: %s[/color]  [color=gray](%d일 · 금화 %d · 경험치 %d)[/color]" % [fin.title, fin.days, fin.gold, fin.xp])
		lines.append("    " + str(fin.text))
		buttons.append(["마지막 의뢰 받기", _take_final.bind(fin), Quests.busy(Game.quests) < Quests.MAX_ACTIVE])
	lines.append("")
	lines.append("평판: " + Reputation.line(Game.rep))
	if note != "":
		lines.append(note)
	lines.append("")
	lines.append_array(_party_lines())
	dialog.open("\n".join(lines), buttons)


func _join_guild() -> void:
	if Game.join_guild():
		Sfx.play(self, "confirm")
		_autosave()
		_open_guild("[color=#9f9]조합에 들었어요: %s[/color]" % Reputation.rank_name(Game.rank))


func _guild_rest() -> void:
	for h in Game.party():
		h.long_rest()
	var failed := Game.sleep_until(7)
	_autosave()
	_quest_news([], failed)
	Sfx.play(self, "confirm")
	_open_guild("[color=#9f9]회관 숙소에서 푹 쉬었어요 (%d일째). 저장했어요.[/color]" % Game.day)


func _take_final(q: Dictionary) -> void:
	if Game.take_final(q):
		Sfx.play(self, "confirm")
		_autosave()
		_open_guild("[color=#9f9]받았어요: %s (%d일째까지)[/color]" % [q.title, q.deadline])


## 의뢰판 (M4): 끝낸 의뢰 보상, 오늘 붙은 의뢰 받기, 아래에 소문 두 줄
func _open_board(note := "") -> void:
	var offers := Game.board_offers(_quest_world())
	var busy := Quests.busy(Game.quests)
	var done := Quests.ready_to_reward(Game.quests)
	var lines := PackedStringArray(["[font_size=22]%s 의뢰판[/font_size]  [color=gray]%d일째 · 받은 의뢰 %d/%d[/color]" % [
		village.name, Game.day, busy, Quests.MAX_ACTIVE]])
	if note != "":
		lines.append(note)
	var buttons := []
	if not done.is_empty():
		lines.append("")
		lines.append("[color=#9f9]끝낸 의뢰[/color]")
		for q in done:
			lines.append("• %s — 금화 %d, 경험치 %d" % [q.title, q.gold, q.xp])
		buttons.append(["보상 받기", _take_rewards, true])
	lines.append("")
	if offers.is_empty():
		lines.append("[color=gray]오늘 붙은 의뢰를 모두 가져갔어요. 하룻밤 자고 나면 새로 붙어요.[/color]")
	for k in offers.size():
		var q: Dictionary = offers[k]
		lines.append("[color=#fd8]%d. %s[/color]  [color=gray](%s · %d일 · 금화 %d · 경험치 %d)[/color]" % [
			k + 1, q.title, q.giver, q.days, q.gold, q.xp])
		lines.append("    " + str(q.text))
		buttons.append(["%d번 받기" % (k + 1), _take_offer.bind(q), busy < Quests.MAX_ACTIVE])
	if busy >= Quests.MAX_ACTIVE and not offers.is_empty():
		lines.append("[color=gray]더 받으려면 하던 의뢰를 끝내세요.[/color]")
	lines.append("")
	for n in _rumors().slice(0, 2):
		lines.append("[color=#bbb]%s[/color]" % n)
	lines.append("[color=gray]J: 일지[/color]")
	dialog.open("\n".join(lines), buttons)


func _quest_world() -> Dictionary:
	var groups := []
	for g in monsters.alive():
		var home: Vector3 = g.home
		groups.append({"id": g.id, "label": monsters.label(g.id), "home": Vector2(home.x, home.z)})
	var dgs := []
	for dg in region.dungeons:
		dgs.append({"id": dg.id, "name": dg.name, "tile": region.tiles[dg.tile].name,
			"dir": Region.direction(Region.VILLAGE, dg.tile), "hours": Region.travel_hours(Region.VILLAGE, dg.tile)})
	return {"groups": groups, "dungeons": dgs, "rank": Game.rank, "max_floor": Reputation.max_floor(Game.rank)}


func _take_offer(q: Dictionary) -> void:
	if Game.take_offer(q):
		Sfx.play(self, "confirm")
		_autosave()
		_open_board("[color=#9f9]받았어요: %s (%d일째까지)[/color]" % [q.title, q.deadline])


func _take_rewards() -> void:
	var total_gold := 0
	var up := 0
	var rank_before := Game.rank
	var rep_before: Dictionary = Game.rep.duplicate()
	var was_ended := Game.ended
	for q in Quests.ready_to_reward(Game.quests):
		total_gold += int(q.gold)
		up = maxi(up, Game.reward(q))
	Sfx.play(self, "level_up" if up > 0 or Game.rank > rank_before else "coins")
	_autosave()
	var note := "[color=#9f9]보상: 금화 %d · 평판 %s%s[/color]" % [total_gold, _rep_delta(rep_before),
		("  — 레벨 업! %d레벨 " % up) if up > 0 else ""]
	if Game.rank > rank_before:
		note += "\n[color=#fd8]조합 등급이 올랐어요: %s[/color]" % Reputation.rank_name(Game.rank)
		if Game.rank >= Reputation.TOP_RANK:
			note += "\n[color=#fd8]조합 회관에 가 보세요 — 마지막 의뢰가 기다려요[/color]"
	_open_board(note)
	if Game.ended and not was_ended:
		dialog.close()
		_show_ending()


## 평판이 얼마나 바뀌었나 ("모험가 조합 +6, 마을 사람들 +3")
func _rep_delta(before: Dictionary) -> String:
	var parts := PackedStringArray()
	for f in Reputation.FACTIONS:
		var d := int(Game.rep[f]) - int(before.get(f, 0))
		if d != 0:
			parts.append("%s %+d" % [Reputation.FACTIONS[f], d])
	return ", ".join(parts) if not parts.is_empty() else "그대로"


## 엔딩 (M6): 마지막 의뢰 보상을 받으면. 계속 돌아다니거나 시작 화면으로
func _show_ending() -> void:
	($Player as Node3D).set_physics_process(false)
	monsters.set_process(false)
	var layer := CanvasLayer.new()
	layer.layer = 25
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.025, 0.02, 0.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 18)
	box.modulate.a = 0.0
	layer.add_child(box)
	var title := Label.new()
	title.text = "재너머 골짜기에 이름을 남기다"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.5))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var done := Game.quests.filter(func(q) -> bool: return q.state == "rewarded").size()
	var body := Label.new()
	body.text = "\n".join(PackedStringArray([
		"%s 사람들을 괴롭히던 우두머리가 쓰러지고, 골짜기에 다시 나무꾼의 도끼 소리가 울립니다." % village.name,
		"조합은 당신의 이름을 회관 벽에 새겼습니다.",
		"",
		"%d일 동안 · 의뢰 %d개 · %s %d레벨 · 금화 %d" % [Game.day, done, Game.hero.display_name(), Game.hero.level(), Game.gold],
		"평판 — " + Reputation.line(Game.rep),
		"",
		"끝까지 해 주셔서 고맙습니다."]))
	body.add_theme_font_size_override("font_size", 20)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	var keep := Button.new()
	keep.text = "계속 돌아다니기"
	keep.pressed.connect(func() -> void:
		layer.queue_free()
		($Player as Node3D).set_physics_process(true)
		monsters.set_process(true))
	row.add_child(keep)
	var quit_btn := Button.new()
	quit_btn.text = "시작 화면으로"
	quit_btn.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/title.tscn"))
	row.add_child(quit_btn)
	var tw := create_tween()
	tw.tween_property(bg, "color:a", 0.88, 1.2)
	tw.tween_property(box, "modulate:a", 1.0, 0.8)
	keep.grab_focus.call_deferred()


## 소문: 가까운 몬스터 무리, 던전 입구
func _rumors() -> Array:
	var news := []
	for g in monsters.alive():
		var home: Vector3 = g.home
		news.append([Vector2(home.x, home.z).length(), "• %s 무리가 %s쪽 %d걸음쯤에서 어슬렁거린다고 한다." % [
			monsters.label(g.id), _compass(Vector2(home.x, home.z)), roundi(Vector2(home.x, home.z).length() / 5.0) * 5]])
	news.sort_custom(func(a, b) -> bool: return a[0] < b[0])
	var out := news.map(func(n): return n[1])
	var far: Array = region.dungeons.filter(func(dg) -> bool: return dg.tile != Region.VILLAGE)
	if not far.is_empty():
		var dg: Dictionary = far[Game.day % far.size()]
		out.insert(mini(1, out.size()), "• %s쪽 %s에 %s(이)라는 던전이 있다. (M: 지도)" % [Region.direction(Region.VILLAGE, dg.tile), region.tiles[dg.tile].name, dg.name])
	return out


## 일지 (J): 받은 의뢰와 지난 의뢰
func _open_journal() -> void:
	($Player as Node3D).set_physics_process(false)
	monsters.set_process(false)
	_show_use_hint("")
	var lines := PackedStringArray(["[font_size=22]일지[/font_size]  [color=gray]%d일째 · 금화 %d[/color]" % [Game.day, Game.gold],
		"[color=gray]조합 %s · 평판 %s[/color]" % [Reputation.rank_name(Game.rank), Reputation.line(Game.rep)], ""])
	var now := Game.quests.filter(func(q) -> bool: return q.state == "active" or q.state == "done")
	if now.is_empty():
		lines.append("[color=gray]받은 의뢰가 없어요. 광장 의뢰판을 보세요.[/color]")
	for q in now:
		lines.append(("[color=#9f9]" if q.state == "done" else "[color=#fd8]") + Quests.line(q, Game.day) + "[/color]")
		if q.state == "active":
			lines.append("    " + str(q.text))
	var past := Game.quests.filter(func(q) -> bool: return q.state == "rewarded" or q.state == "failed")
	if not past.is_empty():
		lines.append("")
		lines.append("[color=gray]지난 의뢰[/color]")
		for q in past.slice(maxi(0, past.size() - 5)):
			lines.append("[color=gray]%s[/color]" % Quests.line(q, Game.day))
	dialog.open("\n".join(lines))


## 의뢰 진행 알림 (목표를 이룸 / 실패)
func _quest_news(done: Array, failed: Array = []) -> void:
	var parts := PackedStringArray()
	for q in done:
		parts.append("의뢰 끝: %s — 의뢰판에서 보상 받기" % q.title)
	for q in failed:
		parts.append("의뢰 실패: %s (기한 지남)" % q.title)
	if not parts.is_empty():
		_toast("\n".join(parts))


## 방향 이름 (-Z가 북쪽)
static func _compass(v: Vector2) -> String:
	var names := ["동", "남동", "남", "남서", "서", "북서", "북", "북동"]
	var i := posmod(roundi(atan2(v.y, v.x) / (PI / 4.0)), 8)
	return names[i]


## 바깥 시간: 실제 1초에 1분. 날이 바뀌면 기한 넘긴 의뢰 알림. 해 높이·밝기도 시각에 맞춤
func _flow_time(delta: float) -> void:
	_minute_acc += delta * MINUTES_PER_SECOND
	if _minute_acc >= 1.0:
		var m := int(_minute_acc)
		_minute_acc -= m
		var failed := Game.advance_minutes(m)
		if not failed.is_empty():
			_quest_news([], failed)
		_apply_daylight()


## 시각에 따라 해의 높이·방향·밝기, 하늘·주변광 밝기 (6시 해 뜸, 18시 해 짐, 밤은 푸르고 어둑하게)
func _apply_daylight() -> void:
	var hour := Game.minute / 60.0
	var day_t := clampf((hour - 5.0) / 14.0, 0.0, 1.0)  # 5시 0 → 19시 1
	var up := sin(day_t * PI)  # 낮 높이 0~1
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		var elev := lerpf(8.0, 62.0, up) if day_t > 0.0 and day_t < 1.0 else 35.0  # 밤엔 달빛
		var az := lerpf(-70.0, 70.0, day_t)
		sun.rotation_degrees = Vector3(-elev, az, 0)
		var night := 1.0 - smoothstep(0.0, 0.25, up)
		sun.light_energy = lerpf(1.0, 0.18, night)
		sun.light_color = Color(1.0, 0.95, 0.88).lerp(Color(1.0, 0.7, 0.45), smoothstep(0.25, 0.0, up) * (1.0 - night * 0.9)).lerp(Color(0.55, 0.65, 1.0), night)
		sun.shadow_enabled = night < 0.8
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we and we.environment:
		var night2 := 1.0 - smoothstep(0.0, 0.25, up)
		we.environment.ambient_light_energy = lerpf(1.0, 0.35, night2)
		we.environment.background_energy_multiplier = lerpf(1.0, 0.15, night2)
	if ambience:
		ambience.strength = lerpf(1.0, 0.45, 1.0 - smoothstep(0.0, 0.25, up))
	if _clock == null:
		var layer := CanvasLayer.new()
		_clock = Label.new()
		_clock.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		_clock.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_clock.offset_right = -16
		_clock.offset_left = -16
		_clock.offset_top = 44
		_clock.add_theme_font_size_override("font_size", 18)
		_clock.add_theme_constant_override("outline_size", 6)
		_clock.add_theme_color_override("font_outline_color", Color.BLACK)
		layer.add_child(_clock)
		add_child(layer)
	_clock.text = "%s · %s · M: 지도" % [Game.time_text(), region.tiles[Game.tile].name if region else ""]


## 빠른 이동: 검은 화면 → 시간이 흐르고 → 도착한 칸(던전이 있으면 입구 앞, 아니면 가운데)으로 옮김. 장면은 그대로
func _go_to_tile(t: Vector2i, arrive, minutes: int) -> void:
	var failed := Game.advance_minutes(minutes)
	var names := PackedStringArray()
	for q in failed:
		names.append(q.title)
	_cover_black("%s(으)로…%s" % [region.tiles[t].name, ("\n의뢰 실패: " + ", ".join(names)) if not names.is_empty() else ""])
	await get_tree().process_frame
	var player := $Player as Node3D
	var p: Vector3
	if arrive is String and arrive == "entrance":
		p = outdoor.before_entrance(t)
	else:
		var a: Vector2 = arrive
		outdoor.fill_now(t)
		p = outdoor.free_spot(Vector3(a.x, 0, a.y))
	player.global_position = p
	($CameraRig as Node3D).global_position = p
	Game.tile = t
	outdoor.fill_now(t)
	monsters.wake_near(p)
	monsters.calm = 3.0
	_apply_daylight()
	_autosave()
	_fade_from_black()
	_toast(_tile_title(t))


## 칸을 옮길 때 가리는 검은 화면
var _fade: ColorRect = null


func _fade_rect() -> ColorRect:
	if _fade == null:
		var layer := CanvasLayer.new()
		layer.layer = 30
		_fade = ColorRect.new()
		_fade.color = Color.BLACK
		_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := Label.new()
		l.name = "Text"
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 28)
		_fade.add_child(l)
		layer.add_child(_fade)
		add_child(layer)
	return _fade


func _cover_black(text: String) -> void:
	var f := _fade_rect()
	(f.get_node("Text") as Label).text = text
	f.modulate.a = 1.0
	f.visible = true


func _fade_from_black() -> void:
	var f := _fade_rect()
	(f.get_node("Text") as Label).text = ""
	f.modulate.a = 1.0
	f.visible = true
	var tw := create_tween()
	tw.tween_interval(0.15)
	tw.tween_property(f, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func() -> void: f.visible = false)


## 지도 (M): 3x3 칸, 빠른 이동
func _open_map() -> void:
	($Player as Node3D).set_physics_process(false)
	monsters.set_process(false)
	_show_use_hint("")
	Sfx.play(self, "open")
	region_map.open(region, Game.tile, Game.time_text())


func _fast_travel(t: Vector2i) -> void:
	if t == Game.tile:
		return
	var hours := Region.travel_hours(Game.tile, t)
	var dg: Dictionary = region.dungeon_at(t)
	var arrive = Region.offset(t, Outdoor.SIZE) if t == Region.VILLAGE or dg.is_empty() else "entrance"
	_go_to_tile(t, arrive, roundi(hours * 60.0))


func _toast(text: String) -> void:
	if _toast_label == null:
		var layer := CanvasLayer.new()
		_toast_label = Label.new()
		_toast_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_toast_label.position.y = 120
		_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_toast_label.add_theme_font_size_override("font_size", 28)
		_toast_label.add_theme_constant_override("outline_size", 8)
		_toast_label.add_theme_color_override("font_outline_color", Color.BLACK)
		layer.add_child(_toast_label)
		add_child(layer)
	_toast_label.text = text
	_toast_left = 3.0
	_toast_label.modulate.a = 1.0


## 바깥 자리와 한 판 상태를 파일에 저장
func _autosave() -> void:
	_autosave_in = AUTOSAVE_EVERY
	if outdoor == null:
		return
	Game.ensure_party()
	Game.place = "outside"
	Game.outside_pos = ($Player as Node3D).global_position
	Game.save_game()


## Esc / Start: 게임 안 메뉴 (창이 열려 있으면 그 창이 먼저 닫힘)
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("back") or pause_menu.is_open() or pause_menu.just_closed():
		return
	if (dialog and dialog.is_open()) or (region_map and region_map.is_open()) or level_dialog.visible:
		return
	get_viewport().set_input_as_handled()
	pause_menu.open()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_autosave()


## 나무가 주인공(싸울 땐 전투 주인공)을 가리지 않게 셰이더에 자리를 알려 줌 (shaders/foliage_wind.gdshader)
func _update_xray() -> void:
	var t: Node3D = $CameraRig.target
	var p := t.global_position + Vector3(0, 1.0, 0) if is_instance_valid(t) else Vector3(0, -1000, 0)
	if fight != null and fight.player != null and outdoor:
		p = fight.position + Vector3(fight.player.pos.x, 0, fight.player.pos.y)
		p.y = outdoor.height_at(p) + 1.0
	RenderingServer.global_shader_parameter_set("xray_target", p)


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set("xray_target", Vector3(0, -1000, 0))
