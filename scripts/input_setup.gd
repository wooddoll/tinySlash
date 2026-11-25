## 키 입력을 코드로 등록합니다 (프로젝트 설정 > 입력 맵에서 직접 만들어도 됩니다)
extends RefCounted

const MAP := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"jump": [KEY_SPACE],
	"cam_left": [KEY_Q],
	"cam_right": [KEY_E],
	"start_battle": [KEY_B],
	"open_dungeon": [KEY_G],
	"end_turn": [KEY_ENTER, KEY_KP_ENTER],
	"back": [KEY_ESCAPE],
}


static func register() -> void:
	for action in MAP:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in MAP[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
