shader_type canvas_item;
uniform vec4 source_bounds;
uniform float feather_pixels = 16.0;

void fragment() {
	vec4 sample_color = texture(TEXTURE, UV);
	vec2 edge_pixels = min(UV-source_bounds.xy, source_bounds.zw-UV) / TEXTURE_PIXEL_SIZE;
	float opacity = smoothstep(0.0, feather_pixels, min(edge_pixels.x, edge_pixels.y));
	COLOR = vec4(sample_color.rgb, sample_color.a * opacity);
}
