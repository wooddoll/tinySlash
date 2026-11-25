## 임시(placeholder) 픽셀아트 텍스처를 코드로 생성합니다.
## 나중에 직접 그린 PNG로 교체하면 됩니다.
extends RefCounted

const FRAME_W := 16
const FRAME_H := 24
const FRAMES := 4
## 시트의 행(방향) 수. 왼쪽 계열 3방향은 오른쪽을 좌우반전해서 씁니다.
## 0 앞, 1 앞-오른쪽, 2 오른쪽, 3 뒤-오른쪽, 4 뒤
const DIRECTIONS := 5
enum Dir { FRONT, FRONT_SIDE, SIDE, BACK_SIDE, BACK }

const OUTLINE := Color(0.08, 0.06, 0.1)
const SKIN := Color(0.98, 0.8, 0.65)
const HAIR := Color(0.45, 0.25, 0.15)
const SHIRT := Color(0.25, 0.45, 0.85)
const PANTS := Color(0.2, 0.2, 0.3)
const EYE := Color(0.1, 0.1, 0.15)


## 캐릭터 스프라이트시트를 만듭니다.
## 가로: 걷기 4프레임 (0번 = 서 있기), 세로: 방향 5행 (Dir 순서).
static func make_character_image() -> Image:
	var img := Image.create_empty(FRAME_W * FRAMES, FRAME_H * DIRECTIONS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for row in DIRECTIONS:
		for f in FRAMES:
			_draw_character(img, f * FRAME_W, row * FRAME_H, row, f)
	_add_outline(img)
	return img


static func make_character_sheet() -> ImageTexture:
	return ImageTexture.create_from_image(make_character_image())


static func _draw_character(img: Image, ox: int, oy: int, dir: int, f: int) -> void:
	var b: int = [0, -1, 0, -1][f]          # 몸 위아래 흔들림
	var stride: int = [0, 1, 0, -1][f]      # 다리 앞뒤 (옆모습에서 좌우로 보임)
	var lift_l := 1 if f == 1 else 0        # 정면/뒷면에서 발 들기
	var lift_r := 1 if f == 3 else 0

	# 다리
	match dir:
		Dir.SIDE:
			# 먼 쪽 다리는 어둡게 칠해서 앞뒤 다리를 구분
			img.fill_rect(Rect2i(ox + 6 - stride * 2, oy + 17, 2, 6), PANTS.darkened(0.35))
			img.fill_rect(Rect2i(ox + 8 + stride * 2, oy + 17, 2, 6), PANTS)
		Dir.FRONT, Dir.BACK:
			img.fill_rect(Rect2i(ox + 5, oy + 17, 2, 6 - lift_l), PANTS)
			img.fill_rect(Rect2i(ox + 9, oy + 17, 2, 6 - lift_r), PANTS)
		_:  # 대각선: 좌우 이동 + 발 들기를 섞음
			img.fill_rect(Rect2i(ox + 5 + stride, oy + 17, 2, 6 - lift_l), PANTS)
			img.fill_rect(Rect2i(ox + 9 - stride, oy + 17, 2, 6 - lift_r), PANTS)

	# 몸통
	var body_x := 5 if dir == Dir.SIDE else 4
	var body_w := 6 if dir == Dir.SIDE else 8
	img.fill_rect(Rect2i(ox + body_x, oy + 11 + b, body_w, 7), SHIRT)

	# 팔
	if dir == Dir.SIDE:
		img.fill_rect(Rect2i(ox + 7 + stride, oy + 12 + b, 2, 4), SKIN)
	else:
		img.fill_rect(Rect2i(ox + 3, oy + 12 + b + stride, 1, 4), SKIN)
		img.fill_rect(Rect2i(ox + 12, oy + 12 + b - stride, 1, 4), SKIN)

	# 머리
	var hy := oy + b
	img.fill_rect(Rect2i(ox + 4, hy + 3, 8, 8), SKIN)
	match dir:
		Dir.FRONT:
			img.fill_rect(Rect2i(ox + 4, hy + 2, 8, 3), HAIR)
			img.fill_rect(Rect2i(ox + 4, hy + 2, 1, 6), HAIR)
			img.fill_rect(Rect2i(ox + 11, hy + 2, 1, 6), HAIR)
			img.set_pixel(ox + 6, hy + 6, EYE)
			img.set_pixel(ox + 9, hy + 6, EYE)
		Dir.FRONT_SIDE:
			img.fill_rect(Rect2i(ox + 4, hy + 2, 8, 3), HAIR)
			img.fill_rect(Rect2i(ox + 4, hy + 2, 2, 7), HAIR)
			img.set_pixel(ox + 8, hy + 6, EYE)
			img.set_pixel(ox + 10, hy + 6, EYE)
		Dir.SIDE:
			img.fill_rect(Rect2i(ox + 4, hy + 2, 8, 3), HAIR)
			img.fill_rect(Rect2i(ox + 4, hy + 2, 4, 8), HAIR)
			img.set_pixel(ox + 10, hy + 6, EYE)
		Dir.BACK_SIDE:
			img.fill_rect(Rect2i(ox + 4, hy + 2, 8, 9), HAIR)
			img.fill_rect(Rect2i(ox + 11, hy + 5, 1, 4), SKIN)  # 귀/뺨이 살짝 보임
		Dir.BACK:
			img.fill_rect(Rect2i(ox + 4, hy + 2, 8, 9), HAIR)


static func make_tree() -> ImageTexture:
	var img := Image.create_empty(32, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(14, 30, 4, 17), Color(0.45, 0.3, 0.18))
	_fill_circle(img, Vector2(16, 18), 13.0, Color(0.18, 0.45, 0.2))
	_fill_circle(img, Vector2(13, 14), 7.0, Color(0.28, 0.58, 0.28))
	_add_outline(img)
	return ImageTexture.create_from_image(img)


static func make_grass() -> ImageTexture:
	var img := Image.create_empty(8, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Color(0.3, 0.65, 0.3)
	for x in [1, 3, 4, 6]:
		var h: int = 3 + (x % 3)
		img.fill_rect(Rect2i(x, 6 - h, 1, h), c)
	return ImageTexture.create_from_image(img)


static func _fill_circle(img: Image, center: Vector2, r: float, color: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			if Vector2(x + 0.5, y + 0.5).distance_to(center) <= r:
				img.set_pixel(x, y, color)


## 불투명 픽셀 둘레에 1px 외곽선을 그립니다.
static func _add_outline(img: Image) -> void:
	var src := img.duplicate() as Image
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			if src.get_pixel(x, y).a > 0.0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var p: Vector2i = Vector2i(x, y) + d
				if p.x >= 0 and p.y >= 0 and p.x < w and p.y < h and src.get_pixel(p.x, p.y).a > 0.0:
					img.set_pixel(x, y, OUTLINE)
					break
