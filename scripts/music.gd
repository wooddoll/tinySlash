## 배경 음악 (M7): 곡 하나를 트리 루트의 재생기로 돌려서 장면이 바뀌어도 이어지고, 다른 곡으로 바꿀 때는 천천히 겹쳐 넘김.
## 곡 파일은 tools/install_music.sh로 받음 (assets/music, 저장소에 없음). 없으면 조용히 건너뜀.
## Music.play(node, "village" / "field" / "dungeon"), Music 버스 (scripts/audio_settings.gd)
extends RefCounted

const AudioSettings = preload("res://scripts/audio_settings.gd")
const TRACKS := {
	"village": ["res://assets/music/village.mp3", -8.0],
	"field": ["res://assets/music/field.mp3", -10.0],
	"dungeon": ["res://assets/music/dungeon.ogg", -4.0],
}
const FADE := 2.0

static var current := ""
static var _player: AudioStreamPlayer = null


static func play(node: Node, track: String) -> void:
	if track == current or node == null or not node.is_inside_tree():
		return
	AudioSettings.ensure()
	var info: Array = TRACKS.get(track, [])
	if info.is_empty() or not ResourceLoader.exists(info[0]):
		return
	current = track
	var stream = load(info[0])
	if stream == null:
		return
	stream = stream.duplicate()
	if "loop" in stream:
		stream.loop = true
	var root := node.get_tree().root
	var old := _player
	if old and is_instance_valid(old):
		var tw := old.create_tween()
		tw.tween_property(old, "volume_db", -60.0, FADE)
		tw.tween_callback(old.queue_free)
	var p := AudioStreamPlayer.new()
	p.name = "Music_" + track
	p.bus = "Music"
	p.stream = stream
	p.volume_db = -60.0
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child.call_deferred(p)
	_player = p
	p.ready.connect(func() -> void:
		p.play()
		var tw := p.create_tween()
		tw.tween_property(p, "volume_db", float(info[1]), FADE), CONNECT_ONE_SHOT)


static func stop() -> void:
	current = ""
	if _player and is_instance_valid(_player):
		var p := _player
		var tw := p.create_tween()
		tw.tween_property(p, "volume_db", -60.0, FADE)
		tw.tween_callback(p.queue_free)
	_player = null
