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
var _seed := 0
var _toast_label: Label
var _toast_left := 0.0
var _pending_toast := ""
var _autosave_in := AUTOSAVE_EVERY


func _ready() -> void:
	InputSetup.register()
	if not _build_terrain():
		_scatter_decor()
	_add_hint()
	if _pending_toast != "":
		_toast(_pending_toast)


## Terrain3D가 설치돼 있으면 노이즈 언덕·숲 지형을 만들고 평평한 바닥·연습용 돌 블록을 치움
func _build_terrain() -> bool:
	if not Outdoor.available():
		return false
	if world_seed == 0:
		world_seed = terrain_seed if terrain_seed != 0 else randi() % 100000 + 1
	_seed = world_seed
	outdoor = Outdoor.new()
	outdoor.name = "Outdoor"
	add_child(outdoor)
	village = Village.generate(_seed, Outdoor.entrance_dir(_seed))
	outdoor.keep_out = village.blocked
	if not outdoor.generate(_seed):
		outdoor.queue_free()
		outdoor = null
		return false
	$Ground.queue_free()
	$Props.queue_free()
	town = TownBuilder.new()
	town.name = "Town"
	add_child(town)
	town.build(village, outdoor.height_at, _seed)
	town.focus = $Player
	dialog = TownDialog.new()
	add_child(dialog)
	dialog.closed.connect(_dialog_closed)
	# 빈터 가운데에 세움 (조금 위에서 떨어져 땅에 닿음). 던전에서 나왔으면 입구 앞
	var player := $Player as Node3D
	player.global_position = Vector3(0, outdoor.height_at(Vector3.ZERO) + 0.3, 0)
	if back_from_dungeon:
		back_from_dungeon = false
		player.global_position = outdoor.before_entrance()
	var loaded := Game.take_load_pos()
	if loaded != Vector3.INF:
		player.global_position = loaded + Vector3(0, 0.3, 0)
		_pending_toast = "이어서 합니다"
	outdoor.entrance_entered.connect(_enter_dungeon)
	var calm := 0.0
	if loaded != Vector3.INF:
		calm = 4.0  # 불러온 자리 바로 옆에 몬스터가 있어도 잠깐은 덤비지 않음
	monsters = Monsters.new()
	monsters.name = "Monsters"
	add_child(monsters)
	monsters.spawn(outdoor, world_seed, defeated, player)
	monsters.calm = calm
	monsters.engaged.connect(_fight_outdoor)
	_autosave.call_deferred()
	($CameraRig as Node3D).global_position = player.global_position
	return true


func _process(delta: float) -> void:
	if fight != null:
		_fight_process(delta)
	elif village != null and not dialog.is_open():
		_town_process()
	if outdoor:
		_autosave_in -= delta
		if _autosave_in <= 0.0:
			_autosave()
	if _toast_left > 0.0:
		_toast_left -= delta
		_toast_label.modulate.a = clampf(_toast_left, 0.0, 1.0)
	if dialog != null and dialog.is_open():
		return
	# 시험용: B 단독 전투, G 던전 생성기, H 시나리오
	if Input.is_action_just_pressed("start_battle"):
		get_tree().change_scene_to_file("res://scenes/battle.tscn")
	elif Input.is_action_just_pressed("open_dungeon"):
		get_tree().change_scene_to_file("res://scenes/dungeon.tscn")
	elif Input.is_action_just_pressed("open_scenario"):
		get_tree().change_scene_to_file("res://scenes/scenario.tscn")


func _add_hint() -> void:
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.text = ("지형 시드 %d · " % _seed if outdoor else "") + "WASD 이동 · Space 점프 · Enter/F 문·의뢰판 · Q/E 카메라 90° 회전 · 휠 줌 · B 전투 시작 · G 던전 생성기 · H 모험(시나리오)"
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
func _enter_dungeon(_body: Node3D) -> void:
	if get_tree().paused:
		return
	_autosave()  # 입구 앞 (던전은 들어가서 다시 저장)
	DungeonView.enter_seed = world_seed * 31 + 7
	back_from_dungeon = true
	get_tree().change_scene_to_file.call_deferred("res://scenes/dungeon.tscn")


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
	_end_fight("win")


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
		_toast("쓰러졌어요… 빈터에서 정신을 차렸어요 (기력 회복)")
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
			dialog.open(_inn_text(), [["하룻밤 묵기 (%d골드)" % INN_PRICE, _inn_rest, Game.gold >= INN_PRICE]])
		"shop":
			dialog.open(_shop_text(), [["회복 물약 사기 (%d골드)" % HeroState.POTION_PRICE, _buy_potion, Game.hero.can_buy_potion(Game.gold)]])
		"guild":
			dialog.open(_guild_text())
		"board":
			dialog.open(_board_text())


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
	if Game.gold < INN_PRICE:
		lines.append("[color=gray]금화가 모자라요 (던전 상자에서 모을 수 있어요)[/color]")
	return "
".join(lines)


func _inn_rest() -> void:
	if Game.gold < INN_PRICE:
		return
	Game.gold -= INN_PRICE
	for h in Game.party():
		h.long_rest()
	_autosave()
	Sfx.play(self, "coins")
	dialog.refresh(_inn_text() + "
[color=#9f9]푹 쉬었어요. 저장했어요.[/color]", [Game.gold >= INN_PRICE])


func _shop_text() -> String:
	var lines := PackedStringArray(["[font_size=22]잡화점[/font_size]", "회복 물약 (2d4+2 회복) %d골드. 무기·방어구는 아직 들어오지 않았어요." % HeroState.POTION_PRICE, ""])
	lines.append_array(_party_lines())
	if Game.hero.potions() >= HeroState.MAX_POTIONS:
		lines.append("[color=gray]물약이 가득 찼어요[/color]")
	elif Game.gold < HeroState.POTION_PRICE:
		lines.append("[color=gray]금화가 모자라요[/color]")
	return "
".join(lines)


func _buy_potion() -> void:
	if not Game.hero.can_buy_potion(Game.gold):
		return
	Game.gold = Game.hero.buy_potion(Game.gold)
	_autosave()
	Sfx.play(self, "coins")
	dialog.refresh(_shop_text(), [Game.hero.can_buy_potion(Game.gold)])


func _guild_text() -> String:
	var lines := PackedStringArray(["[font_size=22]모험가 조합 회관[/font_size]",
		"\"%s에 온 걸 환영하네. 일거리는 광장 의뢰판에 붙여 두지.\"" % village.name, "",
		"[color=gray]조합 가입과 등급은 아직 준비 중이에요 (평판, M6).[/color]", ""])
	lines.append_array(_party_lines())
	return "
".join(lines)


## 의뢰판: 아직 의뢰(M4)는 없고, 근처 몬스터 무리와 던전 입구 소식을 붙여 둠
func _board_text() -> String:
	var lines := PackedStringArray(["[font_size=22]%s 의뢰판[/font_size]" % village.name, ""])
	var news := []
	for g in monsters.groups:
		var home: Vector3 = g.home
		news.append([Vector2(home.x, home.z).length(), "• %s 무리가 %s쪽 %d걸음쯤에서 어슬렁거린다." % [
			monsters.label(g.id), _compass(Vector2(home.x, home.z)), roundi(Vector2(home.x, home.z).length() / 5.0) * 5]])
	news.sort_custom(func(a, b) -> bool: return a[0] < b[0])
	for n in news.slice(0, 4):
		lines.append(n[1])
	if news.is_empty():
		lines.append("• 근처 몬스터 무리는 모두 물리쳤다. 조용한 날들이다.")
	var e: Vector3 = (outdoor.entrance as Transform3D).origin
	lines.append("• %s쪽 언덕에 오래된 던전 입구가 있다. 들어간 사람들이 잘 안 돌아온다." % _compass(Vector2(e.x, e.z)))
	lines.append("")
	lines.append("[color=gray]정식 의뢰는 곧 붙어요 (M4).[/color]")
	return "
".join(lines)


## 방향 이름 (-Z가 북쪽)
static func _compass(v: Vector2) -> String:
	var names := ["동", "남동", "남", "남서", "서", "북서", "북", "북동"]
	var i := posmod(roundi(atan2(v.y, v.x) / (PI / 4.0)), 8)
	return names[i]


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


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_autosave()
