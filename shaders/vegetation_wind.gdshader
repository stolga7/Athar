shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// ATHAR vegetation wind.
//
// Trees and grass sway in the shader, not on the CPU: the whole forest is a
// handful of MultiMesh batches, so moving 138 trunks from GDScript every frame
// would cost far more than a couple of sin() calls per vertex. The cost here is
// two sines and one cosine per vertex, no texture fetches, and the same vertex
// function is reused by the shadow pass, so shadows sway too.
//
// Only geometry above `sway_start` moves, squared so the base of a trunk stays
// planted. The phase comes from the instance's world position, so neighbouring
// trees never sway in lockstep and two runs of the same seed look identical.

uniform float wind_strength = 0.14;
uniform float wind_speed = 1.15;
uniform float sway_start = 3.0;
uniform float sway_span = 4.5;
uniform float base_roughness = 0.92;
uniform float specular_amount = 0.15;
uniform bool use_vertex_color = true;
uniform vec3 tint : source_color = vec3(0.35, 0.45, 0.30);

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = origin.x * 0.31 + origin.z * 0.23;
	float height = clamp((VERTEX.y - sway_start) / max(sway_span, 0.001), 0.0, 1.0);
	float weight = height * height;
	// A slow gust envelope so the forest breathes instead of vibrating.
	float gust = 0.72 + 0.28 * sin(TIME * 0.21 + phase * 0.15);
	float wave = sin(TIME * wind_speed + phase)
			+ 0.45 * sin(TIME * wind_speed * 1.9 + phase * 1.7);
	VERTEX.x += wave * wind_strength * weight * gust;
	VERTEX.z += cos(TIME * wind_speed * 0.8 + phase * 1.3) * wind_strength * 0.55 * weight * gust;
}

void fragment() {
	// Vertex colours are authored in sRGB, matching the old StandardMaterial3D
	// setting, so convert them the same way.
	vec3 base = use_vertex_color ? pow(COLOR.rgb, vec3(2.2)) : tint;
	ALBEDO = base;
	ROUGHNESS = base_roughness;
	SPECULAR = specular_amount;
}
