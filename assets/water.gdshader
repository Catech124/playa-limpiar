shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_schlick_ggx;

// Agua de la playa: una lámina que ondula, cambia de color según la
// profundidad (cerca de la orilla turquesa, mar adentro azul oscuro) y deja ver
// el fondo. Se anima con TIME: no hay texturas ni assets.

uniform vec4 shallow_color : source_color = vec4(0.16, 0.68, 0.76, 1.0);
uniform vec4 deep_color : source_color = vec4(0.03, 0.28, 0.52, 1.0);
uniform float shore_z = 11.0;
uniform float deep_z = 12.6;
uniform float wave_height = 0.028;

varying vec3 wpos;

void vertex() {
	vec3 v = VERTEX;
	// dos oleadas cruzadas: la superficie nunca queda quieta
	v.y += sin(v.x * 1.9 + TIME * 1.5) * wave_height;
	v.y += sin(v.z * 2.6 - TIME * 1.2) * wave_height * 0.8;
	VERTEX = v;
	wpos = (MODEL_MATRIX * vec4(v, 1.0)).xyz;
}

void fragment() {
	float depth = clamp((wpos.z - shore_z) / (deep_z - shore_z), 0.0, 1.0);
	depth = smoothstep(0.0, 1.0, depth);

	// brillo que corre sobre la superficie
	float w1 = sin(wpos.x * 1.7 + wpos.z * 2.3 + TIME * 1.5);
	float w2 = sin(wpos.x * 3.1 - wpos.z * 1.7 - TIME * 1.1);
	float surf = (w1 + w2) * 0.5;

	vec3 col = mix(shallow_color.rgb, deep_color.rgb, depth);
	col += surf * 0.045;
	col += smoothstep(0.72, 1.0, surf) * 0.09;      // destellos

	ALBEDO = col;
	ALPHA = mix(0.72, 0.95, depth);
	ROUGHNESS = 0.18;
	SPECULAR = 0.55;
	METALLIC = 0.05;
}
