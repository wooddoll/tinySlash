## 다른 뼈대로 동작 옮기기 (방향 맞추기 방식).
## 뼈마다 "이 뼈에서 자식 관절을 향하는 방향"을 원본과 같게 돌려서, 쉬는 자세(T자/A자)가 달라도 옮겨집니다.
## 비틀림(뼈 축 회전)은 옮기지 않습니다. 손·머리처럼 자식이 없는 뼈는 쉬는 자세 그대로 따라갑니다.
extends RefCounted

const FPS := 30.0

## map: [대상 뼈, 원본 뼈, 대상 자식, 원본 자식] 목록. 자식이 ""이면 방향 맞추기 없음
## hips: [대상 골반, 원본 골반, 대상 위쪽 뼈, 원본 위쪽 뼈, 대상 왼허벅지, 원본 왼허벅지, 대상 오른허벅지, 원본 오른허벅지]
## src_skel_path / tgt_track_prefix: 원본 동작의 트랙 앞부분, 새 동작의 트랙 앞부분("경로/Skeleton3D")
static func retarget(src_skel: Skeleton3D, src_anim: Animation, src_prefix: String,
		tgt_skel: Skeleton3D, tgt_prefix: String, map: Array, hips: Array, no_yaw := true) -> Animation:
	var src_root := _root_xf(src_skel)
	var tgt_root := _root_xf(tgt_skel)
	# 원본 트랙: 뼈 이름 → [회전 트랙, 위치 트랙]
	var rot_tr := {}
	var pos_tr := {}
	for i in src_anim.get_track_count():
		var p := String(src_anim.track_get_path(i))
		if not p.begins_with(src_prefix + ":"):
			continue
		var bone := p.get_slice(":", 1)
		match src_anim.track_get_type(i):
			Animation.TYPE_ROTATION_3D: rot_tr[bone] = i
			Animation.TYPE_POSITION_3D: pos_tr[bone] = i
	# 쉬는 자세 (모델 공간)
	_reset(src_skel)
	_reset(tgt_skel)
	var s_rest := _globals(src_skel, src_root)
	var t_rest := _globals(tgt_skel, tgt_root)
	var t_hip := tgt_skel.find_bone(hips[0])
	var s_hip := src_skel.find_bone(hips[1])
	var height_k: float = t_rest[t_hip].origin.y / maxf(s_rest[s_hip].origin.y, 0.01)
	# 두 모델이 모델 공간에서 바라보는 방향이 다를 수 있으므로, 원본 방향을 대상 공간으로 돌리는 회전
	var align := _frame(t_rest, tgt_skel, hips[0], hips[2], hips[4], hips[6]) * _frame(s_rest, src_skel, hips[1], hips[3], hips[5], hips[7]).inverse()
	var out := Animation.new()
	out.length = src_anim.length
	var tracks := {}
	for m in map:
		var b := tgt_skel.find_bone(m[0])
		if b < 0:
			continue
		var t := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(t, NodePath("%s:%s" % [tgt_prefix, m[0]]))
		tracks[b] = t
	var hip_rot := out.add_track(Animation.TYPE_ROTATION_3D)
	out.track_set_path(hip_rot, NodePath("%s:%s" % [tgt_prefix, hips[0]]))
	var hip_pos := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(hip_pos, NodePath("%s:%s" % [tgt_prefix, hips[0]]))
	var frames := maxi(1, int(round(src_anim.length * FPS)))
	for f in frames + 1:
		var time := minf(f / FPS, src_anim.length)
		# 원본 자세 세우기
		_reset(src_skel)
		for bone in rot_tr:
			var bi := src_skel.find_bone(bone)
			if bi >= 0:
				src_skel.set_bone_pose_rotation(bi, src_anim.rotation_track_interpolate(rot_tr[bone], time))
		for bone in pos_tr:
			var bi := src_skel.find_bone(bone)
			if bi >= 0:
				src_skel.set_bone_pose_position(bi, src_anim.position_track_interpolate(pos_tr[bone], time))
		var s_now := _globals(src_skel, src_root)
		# 대상: 쉬는 자세에서 시작해 부모부터 차례로 돌림
		_reset(tgt_skel)
		# 골반: 위쪽·옆쪽 두 방향으로 몸통 방향을 맞춤
		var q_hip := _frame(s_now, src_skel, hips[1], hips[3], hips[5], hips[7]) * _frame(s_rest, src_skel, hips[1], hips[3], hips[5], hips[7]).inverse()
		q_hip = align * q_hip * align.inverse()
		if no_yaw:
			# 좌우로 도는 성분은 뺌 (바라보는 방향은 게임이 정함)
			var f0 := Vector3(0, 0, 1)
			var f1 := Basis(q_hip) * f0
			var yaw := atan2(f1.x, f1.z)
			q_hip = Quaternion(Vector3.UP, -yaw) * q_hip
		var hip_g: Transform3D = t_rest[t_hip]
		var new_hip := Basis(q_hip) * hip_g.basis
		var s_off: Vector3 = Basis(align) * (s_now[s_hip].origin - s_rest[s_hip].origin)
		var hip_origin := hip_g.origin + s_off * height_k
		_set_global(tgt_skel, tgt_root, t_hip, Transform3D(new_hip, hip_origin))
		out.rotation_track_insert_key(hip_rot, time, tgt_skel.get_bone_pose_rotation(t_hip))
		out.position_track_insert_key(hip_pos, time, tgt_skel.get_bone_pose_position(t_hip))
		for m in map:
			var b := tgt_skel.find_bone(m[0])
			if b < 0 or not tracks.has(b):
				continue
			var cur := _globals(tgt_skel, tgt_root)
			if m[2] != "" and m[3] != "":
				var tc := tgt_skel.find_bone(m[2])
				var sb := src_skel.find_bone(m[1])
				var sc := src_skel.find_bone(m[3])
				if tc >= 0 and sb >= 0 and sc >= 0:
					var d_t: Vector3 = (cur[tc].origin - cur[b].origin).normalized()
					var d_s: Vector3 = Basis(align) * (s_now[sc].origin - s_now[sb].origin).normalized()
					if d_t.length() > 0.5 and d_s.length() > 0.5:
						var q := _arc(d_t, d_s)
						var g: Transform3D = cur[b]
						_set_global(tgt_skel, tgt_root, b, Transform3D(Basis(q) * g.basis, g.origin))
			out.rotation_track_insert_key(tracks[b], time, tgt_skel.get_bone_pose_rotation(b))
	_reset(src_skel)
	_reset(tgt_skel)
	return out


static func _root_xf(sk: Skeleton3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = sk
	while n != null and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


static func _reset(sk: Skeleton3D) -> void:
	sk.reset_bone_poses()


## 모든 뼈의 모델 공간 자리 (트리 밖 뼈대는 전역 자세가 갱신되지 않으므로 지역 자세로 직접 계산)
static func _raw_globals(sk: Skeleton3D, root: Transform3D) -> Array:
	var out := []
	out.resize(sk.get_bone_count())
	for b in sk.get_bone_count():
		var parent := sk.get_bone_parent(b)
		var local := sk.get_bone_pose(b)
		out[b] = (root if parent < 0 else out[parent]) * local
	return out


static func _globals(sk: Skeleton3D, root: Transform3D) -> Array:
	var raw := _raw_globals(sk, root)
	var out := []
	for g in raw:
		out.append(Transform3D((g as Transform3D).basis.orthonormalized(), (g as Transform3D).origin))
	return out


## 모델 공간 자리를 주면 그 뼈의 지역 회전(과 위치)을 정함
static func _set_global(sk: Skeleton3D, root: Transform3D, b: int, want: Transform3D) -> void:
	var parent := sk.get_bone_parent(b)
	var parent_g := root
	if parent >= 0:
		parent_g = _raw_globals(sk, root)[parent]
	# 부모의 크기(축척)는 빼고 회전만 비교, 위치는 그대로 역변환
	var pg := Transform3D(parent_g.basis.orthonormalized(), parent_g.origin)
	var local_rot := pg.basis.inverse() * want.basis
	sk.set_bone_pose_rotation(b, local_rot.get_rotation_quaternion())
	var local_pos := parent_g.affine_inverse() * want.origin
	sk.set_bone_pose_position(b, local_pos)


static func _frame(g: Array, sk: Skeleton3D, hip: String, up: String, l: String, r: String) -> Quaternion:
	var o: Vector3 = g[sk.find_bone(hip)].origin
	var u: Vector3 = (g[sk.find_bone(up)].origin - o).normalized()
	var side: Vector3 = (g[sk.find_bone(r)].origin - g[sk.find_bone(l)].origin).normalized()
	var fwd := side.cross(u).normalized()
	side = u.cross(fwd).normalized()
	return Basis(side, u, fwd).get_rotation_quaternion()


static func _arc(a: Vector3, b: Vector3) -> Quaternion:
	var d := clampf(a.dot(b), -1.0, 1.0)
	if d > 0.99999:
		return Quaternion.IDENTITY
	var axis := a.cross(b)
	if axis.length() < 1e-6:
		axis = a.cross(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT)
	return Quaternion(axis.normalized(), acos(d))
