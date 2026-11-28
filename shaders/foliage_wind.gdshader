// 나무·덤불·꽃이 바람에 흔들리는 셰이더 (scripts/wind_foliage.gd가 Quaternius 재질을 이걸로 바꿈).
// 높이가 높을수록 더 휘고(밑동은 그대로), 바람 방향으로 기울었다 돌아오기를 되풀이. 잎은 잘게 떨림.
// 같은 나무는 한 덩어리로 움직이고(나무 자리로 위상), 이웃 나무끼리는 조금씩 어긋남.
// 바람 방향은 EmacEArt 풀(+X)과 맞춤.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_normal = false;
uniform bool use_vertex_color = false;
uniform float cutoff = 0.2;
// 휘는 정도: 끝이 sway * h²/(1+h) 만큼 (나무 5칸이면 약 4배, 꽃 1칸이면 0.5배)
uniform float sway = 0.035;
// 잎 떨림
uniform float flutter = 0.0;
uniform float wind_speed = 1.1;
uniform vec2 wind_dir = vec2(1.0, 0.25);
// 주인공 가슴 자리 (main.gd가 매 프레임 넣음). 카메라와 주인공 사이에 있는 잎·줄기는 점점이 비워서 주인공이 보이게
global uniform vec3 xray_target;
const float BAYER[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float h = max(VERTEX.y, 0.0);
	float bend = sway * h * h / (1.0 + h);
	float t = TIME * wind_speed;
	float phase = origin.x * 0.13 + origin.z * 0.09;
	float w = sin(t + phase) * 0.65 + sin(t * 2.3 + phase * 1.7) * 0.35;
	vec3 local_dir = inverse(mat3(MODEL_MATRIX)) * vec3(wind_dir.x, 0.0, wind_dir.y);
	vec2 d = normalize(local_dir.xz + vec2(1e-5));
	VERTEX.xz += d * bend * (0.45 + 0.55 * w);
	if (flutter > 0.0) {
		float f = sin(t * 7.0 + VERTEX.x * 4.0 + VERTEX.z * 3.0 + phase * 5.0);
		VERTEX += NORMAL * flutter * f * h / (1.0 + h);
	}
}

void fragment() {
	vec4 a = texture(albedo_texture, UV);
	if (use_vertex_color) {
		a.rgb *= COLOR.rgb;
	}
	ALBEDO = a.rgb;
	ALPHA = a.a;
	vec3 tv = (VIEW_MATRIX * vec4(xray_target, 1.0)).xyz;
	vec2 dd = VERTEX.xy - tv.xy;
	float dist = length(vec2(dd.x, dd.y * 0.75));
	if (VERTEX.z > tv.z + 0.6 && dist < 2.4) {
		float fade = 0.85 * (1.0 - smoothstep(1.2, 2.4, dist));
		ivec2 p = ivec2(FRAGCOORD.xy) % 4;
		if ((BAYER[p.y * 4 + p.x] + 0.5) / 16.0 < fade) {
			ALPHA = 0.0;
		}
	}
	ALPHA_SCISSOR_THRESHOLD = cutoff;
	if (use_normal) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
	}
	ROUGHNESS = 1.0;
}
