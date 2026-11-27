## 레벨업 고르기 창 (rules 7.17): 능력치 향상(4레벨)과 새 주문 하나.
## open(heroes)로 띄우면 고를 것이 남은 파티원·레벨을 하나씩 보여 주고, 다 고르면 finished.
extends PanelContainer

signal finished

const ABILITY_KO := ["힘", "민첩", "건강", "지능", "지혜", "매력"]

var heroes: Array = []
var hero: HeroState
var level := 0
var need_asi := false
var need_spell := false

var title: RichTextLabel
var asi_box: VBoxContainer
var mode_two: CheckBox
var pick_a: OptionButton
var pick_b: OptionButton
var spell_box: VBoxContainer
var spell_list: VBoxContainer
var spell_pick := ""
var first_spell: Button = null
var preview: RichTextLabel
var ok_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.08, 0.11, 0.95)
	bg.border_color = Color(0.9, 0.78, 0.4)
	bg.set_border_width_all(2)
	bg.set_content_margin_all(16)
	bg.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", bg)
	visible = false

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size.x = 520
	add_child(box)
	title = _rich(box, 20)

	asi_box = VBoxContainer.new()
	box.add_child(asi_box)
	_rich(asi_box, 15).text = "[b]능력치 향상[/b]  [color=gray]한 능력치 +2, 또는 두 능력치 +1 (최대 20)[/color]"
	var row := HBoxContainer.new()
	asi_box.add_child(row)
	pick_a = _ability_option(row)
	mode_two = CheckBox.new()
	mode_two.text = "+1씩 나누기"
	mode_two.focus_mode = Control.FOCUS_ALL
	mode_two.toggled.connect(func(_on: bool) -> void: _refresh())
	row.add_child(mode_two)
	pick_b = _ability_option(row)

	spell_box = VBoxContainer.new()
	box.add_child(spell_box)
	_rich(spell_box, 15).text = "[b]새 주문 하나[/b]"
	spell_list = VBoxContainer.new()
	spell_box.add_child(spell_list)

	preview = _rich(box, 14)
	ok_button = Button.new()
	ok_button.text = "확인"
	ok_button.focus_mode = Control.FOCUS_ALL
	ok_button.custom_minimum_size = Vector2(140, 34)
	ok_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok_button.pressed.connect(_confirm)
	box.add_child(ok_button)


## 고를 것이 남은 파티원이 있으면 창을 띄우고 true
func open(list: Array) -> bool:
	heroes = list.filter(func(h: Variant) -> bool: return h != null)
	return _next()


func _next() -> bool:
	for h in heroes:
		var p: Array = (h as HeroState).pending_choices()
		if p.is_empty():
			continue
		hero = h
		level = p[0].level
		need_asi = p[0].asi
		need_spell = p[0].spell
		_fill()
		visible = true
		return true
	visible = false
	return false


func _fill() -> void:
	title.text = "[color=#e8d27a][b]레벨 업![/b][/color]  %s %d레벨에서 고르기" % [hero.display_name(), level]
	asi_box.visible = need_asi
	spell_box.visible = need_spell
	if need_asi:
		var s := Catalog.build(hero.cls, level)
		var def: Dictionary = LevelUp.DEFAULT_ASI.get(hero.cls, {})
		for o in [pick_a, pick_b]:
			(o as OptionButton).clear()
			for i in 6:
				(o as OptionButton).add_item("%s %d" % [ABILITY_KO[i], s.scores[i]], i)
		pick_a.select(int(def.keys()[0]) if not def.is_empty() else 0)
		pick_b.select(Rules.Ability.CON)
		mode_two.button_pressed = false
	if need_spell:
		for c in spell_list.get_children():
			c.queue_free()
		spell_pick = ""
		first_spell = null
		var group := ButtonGroup.new()
		for id in LevelUp.spell_pool(hero.cls, level, hero.choices):
			var b := Button.new()
			b.toggle_mode = true
			b.button_group = group
			b.focus_mode = Control.FOCUS_ALL
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var lv: int = Spells.DATA[id].level
			b.text = "%s (%s) — %s" % [Spells.spell_name(id), "소마법" if lv == 0 else "%d레벨" % lv, Spells.SUMMARY.get(id, "")]
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.custom_minimum_size.x = 500
			b.pressed.connect(func() -> void:
				spell_pick = id
				_refresh())
			spell_list.add_child(b)
			if first_spell == null:
				first_spell = b
	_refresh()
	# 게임패드: 첫 항목에 포커스 (십자 버튼으로 옮기고 A로 고름)
	if need_spell and first_spell != null:
		first_spell.call_deferred("grab_focus")
	elif need_asi:
		pick_a.call_deferred("grab_focus")


func _asi() -> Dictionary:
	var a := pick_a.get_selected_id()
	if not mode_two.button_pressed:
		return {a: 2}
	var b := pick_b.get_selected_id()
	return {a: 2} if a == b else {a: 1, b: 1}


func _refresh() -> void:
	pick_b.visible = mode_two.button_pressed
	var lines := []
	var ok := true
	if need_asi:
		var base := Catalog.build(hero.cls, level)
		var asi := _asi()
		if not LevelUp.valid_asi(base.scores, asi):
			ok = false
			lines.append("[color=#ff8080]20을 넘을 수 없어요[/color]")
		else:
			var trial := hero.choices.duplicate(true)
			var c: Dictionary = trial.get(level, {})
			c["asi"] = asi
			trial[level] = c
			var now := Catalog.pc(hero.cls, level, hero.choices)
			var after := Catalog.pc(hero.cls, level, trial)
			var parts := []
			for i in asi:
				parts.append("%s %d → %d" % [ABILITY_KO[i], base.scores[i], after.scores[i]])
			if after.ac != now.ac:
				parts.append("AC %d → %d" % [now.ac, after.ac])
			if after.max_hp != now.max_hp:
				parts.append("최대 HP %d → %d" % [now.max_hp, after.max_hp])
			lines.append(", ".join(parts))
	if need_spell and spell_pick == "":
		ok = false
		lines.append("[color=gray]주문을 하나 고르세요[/color]")
	preview.text = "\n".join(lines)
	ok_button.disabled = not ok


func _confirm() -> void:
	if need_asi:
		hero.choose(level, "asi", _asi())
	if need_spell and spell_pick != "":
		hero.choose(level, "spell", spell_pick)
	if not _next():
		finished.emit()


func _ability_option(parent: Control) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_ALL
	o.custom_minimum_size.x = 140
	o.item_selected.connect(func(_i: int) -> void: _refresh())
	parent.add_child(o)
	return o


func _rich(parent: Control, size: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	parent.add_child(r)
	return r
