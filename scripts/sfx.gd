## 효과음 도우미. Kenney 오디오(CC0)에서 그룹마다 하나를 골라 조금씩 음높이를 바꿔 틉니다.
## 재생기는 트리 루트에 붙여서 장면이 바뀌어도 끝까지 들립니다.
extends RefCounted

const BASE := "res://assets/kenney/audio/"

## 그룹 -> [파일들], 기본 볼륨(dB)
const GROUPS := {
	"swing": [["rpg-audio/drawKnife1", "rpg-audio/drawKnife2", "rpg-audio/drawKnife3"], -4.0],
	"shoot": [["rpg-audio/cloth1", "rpg-audio/cloth2", "rpg-audio/cloth3"], -2.0],
	"hit": [["rpg-audio/knifeSlice", "rpg-audio/knifeSlice2", "rpg-audio/chop",
			"impact-sounds/impactPunch_medium_000", "impact-sounds/impactPunch_medium_001",
			"impact-sounds/impactPunch_medium_002"], 0.0],
	"crit": [["impact-sounds/impactPunch_heavy_000", "impact-sounds/impactPunch_heavy_001",
			"impact-sounds/impactPunch_heavy_002"], 2.0],
	"miss": [["impact-sounds/impactSoft_medium_000", "impact-sounds/impactSoft_medium_001",
			"impact-sounds/impactSoft_medium_002"], -6.0],
	"death": [["impact-sounds/impactSoft_heavy_000", "impact-sounds/impactSoft_heavy_001",
			"impact-sounds/impactSoft_heavy_002"], 0.0],
	"heal": [["interface-sounds/maximize_006", "interface-sounds/maximize_008"], -4.0],
	"step": [["impact-sounds/footstep_concrete_000", "impact-sounds/footstep_concrete_001",
			"impact-sounds/footstep_concrete_002", "impact-sounds/footstep_concrete_003",
			"impact-sounds/footstep_concrete_004"], -16.0],
	"chest": [["rpg-audio/doorOpen_1", "rpg-audio/doorOpen_2"], -4.0],
	"coins": [["rpg-audio/handleCoins", "rpg-audio/handleCoins2"], -2.0],
	"alert": [["interface-sounds/bong_001"], -2.0],
	"stairs": [["rpg-audio/doorClose_1", "rpg-audio/doorClose_2"], -4.0],
	"click": [["ui-audio/click1", "ui-audio/click2", "ui-audio/click3"], -8.0],
	"open": [["interface-sounds/open_001", "interface-sounds/open_002"], -6.0],
	"close": [["interface-sounds/close_001", "interface-sounds/close_002"], -6.0],
	"dice": [["interface-sounds/drop_001", "interface-sounds/drop_002", "interface-sounds/drop_003"], -4.0],
	"confirm": [["interface-sounds/confirmation_001"], -4.0],
	"cast": [["interface-sounds/glass_002", "interface-sounds/glass_004"], -6.0],
	"switch": [["ui-audio/switch2", "ui-audio/switch3"], -8.0],
	# 전투 시작·끝 (예전 음성 "FIGHT", "YOU WIN"은 어색해서 효과음으로 바꿈, 2026-11-28)
	"fight": [["rpg-audio/drawKnife2"], -2.0],
	"win": [["interface-sounds/confirmation_002"], -2.0],
	"lose": [["interface-sounds/error_006"], -4.0],
	"level_up": [["interface-sounds/maximize_008"], -2.0],
}

static var _streams := {}
## 끄기 (테스트, 녹화용)
static var muted := false


static func path_of(file: String) -> String:
	return BASE + file + ".ogg"


static func play(node: Node, group: String, volume_db := 0.0, pitch_jitter := 0.08) -> void:
	if muted or node == null or not node.is_inside_tree():
		return
	if not GROUPS.has(group):
		push_error("효과음 그룹 없음: " + group)
		return
	var files: Array = GROUPS[group][0]
	var file: String = files[randi() % files.size()]
	if not _streams.has(file):
		_streams[file] = load(path_of(file))
	var p := AudioStreamPlayer.new()
	p.stream = _streams[file]
	p.volume_db = float(GROUPS[group][1]) + volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.autoplay = true  # 트리에 들어가면 재생
	p.finished.connect(p.queue_free)
	# 장면 _ready 중에는 루트에 바로 붙일 수 없어서 미룸
	node.get_tree().root.add_child.call_deferred(p)


## 노드 아래 모든 버튼에 클릭 소리
static func wire_buttons(root: Node) -> void:
	for n in root.find_children("*", "BaseButton", true, false):
		var b := n as BaseButton
		b.pressed.connect(func() -> void: play(b, "click"))
