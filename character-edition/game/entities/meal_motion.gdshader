shader_type canvas_item;
uniform vec2 atlas_cell=vec2(0.0);
uniform vec4 meal_tint:source_color=vec4(1.0);
void fragment(){
	vec2 local=UV*2.0-atlas_cell;
	float hands=(smoothstep(.18,.23,local.x)*(1.0-smoothstep(.39,.44,local.x))+smoothstep(.61,.65,local.x)*(1.0-smoothstep(.80,.85,local.x)));
	hands*=smoothstep(.22,.25,local.y)*(1.0-smoothstep(.34,.37,local.y));
	vec2 sample_uv=UV+vec2(sin(TIME*2.4)*.0008,cos(TIME*2.4)*.0007)*hands;
	COLOR=texture(TEXTURE,sample_uv)*meal_tint;
}
