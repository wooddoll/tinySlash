## 키·게임패드 입력을 코드로 등록합니다 (프로젝트 설정 > 입력 맵에서 직접 만들어도 됩니다)
## 게임패드는 Xbox 배치 기준: A 아래, B 오른쪽, X 왼쪽, Y 위
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
	"open_scenario": [KEY_H],
	"explore": [KEY_TAB],
	"end_turn": [KEY_ENTER, KEY_KP_ENTER],
	"back": [KEY_ESCAPE],
	# 액션 전투 (rules 10장)
	"attack": [KEY_J],
	"dodge": [KEY_SPACE, KEY_SHIFT],
	"skill": [KEY_K],
	"skill2": [KEY_L],
	"potion": [KEY_1],
	"interact": [KEY_F, KEY_ENTER],
	# 시나리오: 방 수색, 일지
	"search": [KEY_R],
	"journal": [KEY_J],
	# 바깥: 지방 지도 (M5)
	"map": [KEY_M],
	# 도움말 (조작 전부 보기, M7)
	"help": [KEY_F1],
}

## 게임패드 버튼
const JOY := {
	"attack": [JOY_BUTTON_X],
	"dodge": [JOY_BUTTON_A],
	"skill": [JOY_BUTTON_B],
	"skill2": [JOY_BUTTON_DPAD_RIGHT],
	"interact": [JOY_BUTTON_Y],
	"end_turn": [JOY_BUTTON_Y],
	"potion": [JOY_BUTTON_DPAD_UP],
	"cam_left": [JOY_BUTTON_LEFT_SHOULDER],
	"cam_right": [JOY_BUTTON_RIGHT_SHOULDER],
	"explore": [JOY_BUTTON_BACK],
	"back": [JOY_BUTTON_START],
	"search": [JOY_BUTTON_DPAD_DOWN],
	"journal": [JOY_BUTTON_BACK],
	"map": [JOY_BUTTON_DPAD_LEFT],
}
## Godot 기본 창 조작에 패드 버튼을 더함: A 확인, B 취소 (프로젝트 입력 맵에는 키만 있음)
const UI_JOY := {"ui_accept": JOY_BUTTON_A, "ui_cancel": JOY_BUTTON_B}

## 왼쪽 스틱 (축, 방향)
const STICK := {
	"move_left": [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X, 1.0],
	"move_up": [JOY_AXIS_LEFT_Y, -1.0],
	"move_down": [JOY_AXIS_LEFT_Y, 1.0],
}
const DEADZONE := 0.2


static func register() -> void:
	for action in UI_JOY:
		var has := false
		for e in InputMap.action_get_events(action):
			if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == UI_JOY[action]:
				has = true
		if not has:
			var jb := InputEventJoypadButton.new()
			jb.button_index = UI_JOY[action]
			InputMap.action_add_event(action, jb)
	for action in MAP:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, DEADZONE)
		for key in MAP[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
		for b in JOY.get(action, []):
			var jb := InputEventJoypadButton.new()
			jb.button_index = b
			InputMap.action_add_event(action, jb)
		if STICK.has(action):
			var jm := InputEventJoypadMotion.new()
			jm.axis = STICK[action][0]
			jm.axis_value = STICK[action][1]
			InputMap.action_add_event(action, jm)
