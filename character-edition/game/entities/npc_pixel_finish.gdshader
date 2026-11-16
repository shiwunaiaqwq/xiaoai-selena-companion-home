shader_type canvas_item;
render_mode unshaded;
uniform float source_pixel_step = 2.0;
uniform float alpha_cutoff = 0.0;
void fragment() {
	vec2 texel = TEXTURE_PIXEL_SIZE * source_pixel_step;
	vec2 sample_uv = (floor(UV / texel) + 0.5) * texel;
	vec4 source = texture(TEXTURE, sample_uv);
	if (source.a < alpha_cutoff) discard;
	if (alpha_cutoff > 0.0) source.a = 1.0;
	source.rgb = mix(source.rgb, floor(source.rgb * 31.0 + 0.5) / 31.0, 0.35);
	COLOR *= source;
}
