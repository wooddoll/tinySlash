## 보스 몬스터(Fab, Bento Models "The Eightfold Archive" Hadal)를 게임용으로 굽습니다.
## 원본(glTF, LOD0~2, 동작 12~15개)은 프로젝트 밖 F:/workspace/fab_downloads/bosses 에 두고,
## LOD2 메시 + 줄인 텍스처 + 엔진 이름으로 바꾼 동작만 res://assets/dark/<이름>/<이름>.scn 에 씁니다 (공개 저장소에 올리지 않음).
##   godot --headless --path . -s tools/bake_boss.gd [-- 이름]
extends SceneTree

const SRC := "F:/workspace/fab_downloads/bosses/x/The_Eightfold_Archive/Hadal/Models/"
const OUT := "res://assets/dark/%s/"
const TEX_SIZE := 512
## 이름 → 원본 glTF, 동작 (엔진 이름: [원본 동작, 길이 초(0이면 그대로)])
const BOSSES := {
	"bellwarden": {
		"file": "drowned_bellwarden/01_Foundry_Warden/01_Tarnished_Iron_LOD2.gltf",
		"anims": {
			"idle": ["Watch", 0.0],
			"walk": ["Tripod_March", 1.6],
			"sprint": ["Tripod_March", 1.1],
			"crouch": ["Seabed_Listen", 0.0],
			"die": ["Pilgrim_Kneel", 1.8],
			"hit": ["Brace", 0.6],
			"attack-melee-right": ["Great_Toll", 1.3],
			"holding-right-shoot": ["Sounding_Sweep", 1.4],
			"dodge": ["Counterweight_Shift", 0.6],
			"cast": ["Alarm_Peal", 1.4],
			"wake": ["Wake", 1.5],
		},
	},
	"cantor": {
		"file": "hadal_cantor/01_Survey_Brass/03_Midnight_Survey_LOD2.gltf",
		"anims": {
			"idle": ["Suspended", 0.0],
			"walk": ["Jet_Swim", 0.0],
			"sprint": ["Jet_Swim", 1.8],
			"crouch": ["Echo_Scan", 0.0],
			"die": ["Power_Down", 1.8],
			"hit": ["Startle", 0.6],
			"attack-melee-right": ["Probe_Touch", 1.3],
			"holding-right-shoot": ["Sonar_Call", 1.3],
			"dodge": ["Crosscurrent_Slip", 0.6],
			"cast": ["Crown_Bloom", 1.5],
			"wake": ["Wake", 1.5],
		},
	},
	"regent": {
		"file": "ossuary_regent/01_Ossuary_Sovereign/01_Ivory_and_Oxblood_LOD2.gltf",
		"anims": {
			"idle": ["Glide", 0.0],
			"walk": ["Glide", 2.4],
			"sprint": ["Glide", 1.6],
			"crouch": ["Glide", 0.0],
			"die": ["Reseal", 1.8],
			"hit": ["Caudal_Feint", 0.6],
			"attack-melee-right": ["Spiral_Flare", 1.3],
			"holding-right-shoot": ["Pressure_Pulse", 1.3],
			"dodge": ["Caudal_Feint", 0.6],
			"cast": ["Eclipse_Mantle", 1.5],
			"wake": ["Unseal", 1.5],
		},
	},
}
const LOOPING := ["idle", "walk", "sprint", "crouch"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var only := args[0] if args.size() > 0 else ""
	for name in BOSSES:
		if only == "" or only == name:
			_bake(name)
	quit()


func _bake(name: String) -> void:
	var def: Dictionary = BOSSES[name]
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(SRC + def.file, st) != OK:
		push_error("glTF 못 읽음: " + def.file)
		return
	var root := doc.generate_scene(st) as Node3D
	root.name = name.capitalize()
	# 텍스처 줄이기 (같은 텍스처는 한 번만)
	var done := {}
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s) as BaseMaterial3D
			if mat == null:
				continue
			for p in ["albedo_texture", "normal_texture", "orm_texture", "roughness_texture", "metallic_texture", "emission_texture", "ao_texture"]:
				var t = mat.get(p)
				if t is Texture2D and not done.has(t):
					done[t] = _shrink(t)
				if t is Texture2D:
					mat.set(p, done[t])
	# 동작: 엔진 이름으로 새 묶음
	var src_ap := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var lib := AnimationLibrary.new()
	var anims: Dictionary = def.anims
	for key in anims:
		var orig: Animation = src_ap.get_animation(anims[key][0])
		if orig == null:
			push_error("동작 없음: %s %s" % [name, anims[key][0]])
			continue
		var a := orig.duplicate(true) as Animation
		var dur: float = anims[key][1]
		if dur > 0.0:
			_retime(a, dur / a.length)
		a.loop_mode = Animation.LOOP_LINEAR if key in LOOPING else Animation.LOOP_NONE
		lib.add_animation(key, a)
	for l in src_ap.get_animation_library_list():
		src_ap.remove_animation_library(l)
	src_ap.add_animation_library("", lib)
	_own(root, root)
	var out := OUT % name
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, out + name + ".scn", ResourceSaver.FLAG_COMPRESS)
	print("%s 저장: %s (텍스처 %d장)" % [name, error_string(err), done.size()])
	root.free()


func _shrink(t: Texture2D) -> Texture2D:
	var img := t.get_image()
	if img == null:
		return t
	if img.is_compressed():
		img.decompress()
	if img.get_width() > TEX_SIZE:
		img.resize(TEX_SIZE, TEX_SIZE * img.get_height() / img.get_width(), Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## 동작 길이를 k배로 (키 시간을 늘이거나 줄임)
func _retime(a: Animation, k: float) -> void:
	for t in a.get_track_count():
		var keys := []
		for i in a.track_get_key_count(t):
			keys.append([a.track_get_key_time(t, i) * k, a.track_get_key_value(t, i), a.track_get_key_transition(t, i)])
		while a.track_get_key_count(t) > 0:
			a.track_remove_key(t, 0)
		for kv in keys:
			a.track_insert_key(t, kv[0], kv[1], kv[2])
	a.length *= k


func _own(n: Node, root: Node) -> void:
	for c in n.get_children():
		c.owner = root
		_own(c, root)
