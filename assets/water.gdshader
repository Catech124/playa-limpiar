shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

// Agua de playa, OPACA y de dibujos animados: tres franjas duras de profundidad
// (turquesa → azul), rayas de luz que corren y un poco de espuma que late cerca
// de la orilla. No es transparente a propósito: el cuerpo del nadador queda
// cortado por la superficie, que es lo que hace que se lea "está en el agua".

uniform vec4 shallow_color : source_color = vec4(0.22, 0.80, 0.86, 1.0);
uniform vec4 deep_color : source_color = vec4(0.04, 0.34, 0.62, 1.0);
uniform float shore_z = 11.0;
uniform float deep_z = 13.2;
uniform float wave_height = 0.035;

varying vec3 wpos;

void vertex() {
	vec3 v = VERTEX;
	v.y += sin(v.x * 1.8 + TIME * 1.4) * wave_height;
	v.y += sin(v.z * 2.4 - TIME * 1.1) * wave_height * 0.8;
	VERTEX = v;
	wpos = (MODEL_MATRIX * vec4(v, 1.0)).xyz;
}

void fragment() {
	float depth = clamp((wpos.z - shore_z) / (deep_z - shore_z), 0.0, 1.0);
	// tres escalones de color: el borde duro es lo que le da el aire de dibujo
	float band = floor(depth * 3.0 + 0.001) / 3.0;

	vec3 col = mix(shallow_color.rgb, deep_color.rgb, band);

	// rayas de luz que se desplazan sobre la superficie
	float stripe = sin(wpos.x * 0.85 + wpos.z * 1.20 + TIME * 1.1);
	col += smoothstep(0.70, 1.0, stripe) * 0.09;

	// espuma que late en la primera franja
	float shore = smoothstep(0.55, 0.05, depth);
	float foam = shore * (0.5 + 0.5 * sin(wpos.x * 2.2 + TIME * 1.7));
	col = mix(col, vec3(0.93, 0.99, 1.0), foam * 0.35);

	ALBEDO = col;
	ROUGHNESS = 0.30;
	SPECULAR = 0.35;
}
