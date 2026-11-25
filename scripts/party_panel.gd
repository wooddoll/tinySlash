## 화면 왼쪽 파티 창: 파티원마다 초상화, HP 바(숫자 포함), 버프·디버프 표시.
## 전투와 던전 탐험이 같이 씁니다. show_members()에 사전 배열을 넘기면 됩니다.
extends VBoxContainer

const CharacterModel = preload("res://scripts/character_model.gd")
const WIDTH := 250
const PORTRAIT := 64
const KIND_COLORS := {
	"buff": Color(0.2, 0.5, 0.25, 0.9),
	"debuff": Color(0.6, 0.18, 0.15, 0.9),
	"info": Color(0.3, 0.3, 0.38, 0.9),
}

## key -> {panel, style, portrait, name, bar, fill, hp, chips}
var _rows := {}


func _init() -> void:
	add_theme_constant_override("separation", 6)
	custom_minimum_size.x = WIDTH
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## members: [{key, name, model, weapon, hp, max_hp, temp_hp, active, down, dead,
##            effects: [[글자, "buff"/"debuff"/"info", 설명], ...]}]
func show_members(members: Array) -> void:
	var keep := {}
	for m in members:
		var key: String = m.key
		keep[key] = true
		if not _rows.has(key):
			_rows[key] = _make_row(m)
		_fill(_rows[key], m)
	for key in _rows.keys():
		if not keep.has(key):
			(_rows[key].panel as Control).queue_free()
			_rows.erase(key)


func _make_row(m: Dictionary) -> Dictionary:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.08, 0.78)
	style.set_corner_radius_all(6)
	style.set_border_width_all(2)
	style.border_color = Color(0, 0, 0, 0)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hb)

	var frame := PanelContainer.new()
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color(0.22, 0.24, 0.3)
	fs.set_corner_radius_all(PORTRAIT / 2)
	frame.add_theme_stylebox_override("panel", fs)
	frame.custom_minimum_size = Vector2(PORTRAIT, PORTRAIT)
	frame.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(frame)
	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(PORTRAIT, PORTRAIT)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.texture = _portrait_texture(panel, m.get("model", ""), m.get("weapon", ""))
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(portrait)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 3)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)
	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", 14)
	vb.add_child(name_label)

	# HP 바: 배경 위에 채움 막대, 그 위에 숫자
	var bar := Panel.new()
	bar.custom_minimum_size = Vector2(0, 18)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.05, 0.05)
	bg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("panel", bg)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(bar)
	var fill := Panel.new()
	var fstyle := StyleBoxFlat.new()
	fstyle.set_corner_radius_all(4)
	fill.add_theme_stylebox_override("panel", fstyle)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(fill)
	var hp := Label.new()
	hp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp.add_theme_font_size_override("font_size", 12)
	hp.add_theme_constant_override("outline_size", 4)
	hp.add_theme_color_override("font_outline_color", Color.BLACK)
	bar.add_child(hp)

	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 3)
	chips.add_theme_constant_override("v_separation", 3)
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(chips)
	return {"panel": panel, "style": style, "portrait": portrait, "name": name_label,
		"bar": bar, "fill": fill, "hp": hp, "chips": chips, "fill_style": fstyle}


func _fill(row: Dictionary, m: Dictionary) -> void:
	var max_hp: int = maxi(int(m.max_hp), 1)
	var hp: int = clampi(int(m.hp), 0, max_hp)
	var ratio := float(hp) / max_hp
	(row.name as Label).text = m.name
	var temp: int = m.get("temp_hp", 0)
	(row.hp as Label).text = "%d/%d%s" % [hp, max_hp, (" (+%d)" % temp) if temp > 0 else ""]
	var fill: Panel = row.fill
	fill.anchor_right = ratio
	fill.anchor_bottom = 1.0
	fill.offset_right = 0
	fill.offset_bottom = 0
	(row.fill_style as StyleBoxFlat).bg_color = Color(0.25, 0.75, 0.3) if ratio > 0.5 \
			else (Color(0.85, 0.7, 0.2) if ratio > 0.25 else Color(0.85, 0.25, 0.2))
	(row.style as StyleBoxFlat).border_color = Color(1.0, 0.85, 0.3) if m.get("active", false) else Color(0, 0, 0, 0)
	var portrait: TextureRect = row.portrait
	if m.get("dead", false):
		portrait.modulate = Color(0.25, 0.25, 0.25)
	elif m.get("down", false):
		portrait.modulate = Color(0.55, 0.45, 0.45)
	else:
		portrait.modulate = Color.WHITE
	var chips: HFlowContainer = row.chips
	for c in chips.get_children():
		c.queue_free()
	for e in m.get("effects", []):
		chips.add_child(_chip(e[0], e[1], e[2] if e.size() > 2 else ""))


func _chip(text: String, kind: String, tip: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	var s := StyleBoxFlat.new()
	s.bg_color = KIND_COLORS.get(kind, KIND_COLORS.info)
	s.set_corner_radius_all(3)
	s.content_margin_left = 4
	s.content_margin_right = 4
	l.add_theme_stylebox_override("normal", s)
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS if tip != "" else Control.MOUSE_FILTER_IGNORE
	return l


## 캐릭터 모델을 따로 그리는 작은 화면을 만들어 그 텍스처를 초상화로 씁니다
func _portrait_texture(owner_node: Node, model: String, weapon: String) -> Texture2D:
	if model == "":
		return null
	var vp := SubViewport.new()
	vp.size = Vector2i(128, 128)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	owner_node.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.environment.ambient_light_energy = 0.7
	vp.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(-35), deg_to_rad(25), 0)
	vp.add_child(light)
	var body := CharacterModel.new()
	vp.add_child(body)
	body.setup(model, 1.0, weapon)
	body.face(Vector3(0.35, 0, 1), true)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = body.height * 0.62
	var target := Vector3(0, body.height * 0.72, 0)
	var pos := Vector3(0, body.height * 0.8, 3.0)
	cam.transform = Transform3D(Basis.looking_at(target - pos), pos)
	vp.add_child(cam)
	return vp.get_texture()
