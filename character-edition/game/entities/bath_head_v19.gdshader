shader_type canvas_item;
uniform vec4 head_uv=vec4(0.0,0.0,1.0,1.0);
uniform vec4 tone:source_color=vec4(1.0);
void fragment(){
	vec4 p=texture(TEXTURE,UV);
	vec2 local=(UV-head_uv.xy)/head_uv.zw;
	float submerged=1.0-smoothstep(0.88,1.0,local.y);
	COLOR=vec4(p.rgb,p.a*submerged)*tone;
}
