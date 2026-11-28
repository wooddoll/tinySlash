## 장면을 바꿀 때 "불러오는 중…" 검은 화면 (새 장면의 _ready가 무거워 몇 초 멈추는 동안 가림).
## 화면 맨 위(root)에 붙여 두고 새 장면이 뜨면 서서히 걷힘.
## 다른 스크립트는 const Loading = preload("res://scripts/loading.gd") 로 Loading.go(self, "res://scenes/main.tscn")
extends RefCounted


static func go(from: Node, path: String, text := "불러오는 중…") -> void:
	var tree := from.get_tree()
	var layer := CanvasLayer.new()
	layer.layer = 100
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.025)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(bg)
	var label := Label.new()
	label.text = text
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.75))
	bg.add_child(label)
	tree.root.add_child(layer)
	# 검은 화면이 한 번 그려진 뒤에 바꿈
	await RenderingServer.frame_post_draw
	tree.change_scene_to_file(path)
	await tree.scene_changed
	await tree.process_frame
	await tree.process_frame
	if not is_instance_valid(layer):
		return
	var tw := layer.create_tween()
	tw.tween_property(bg, "modulate:a", 0.0, 0.5)
	tw.tween_callback(layer.queue_free)
