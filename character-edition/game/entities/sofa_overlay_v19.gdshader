shader_type canvas_item;
uniform vec4 tone:source_color=vec4(1.0);
uniform vec4 cell_uv=vec4(0.0,0.0,1.0,1.0);
uniform bool trim_cushion=false;
void fragment(){
	vec4 p=texture(TEXTURE,UV);
	vec2 local=(UV-cell_uv.xy)/cell_uv.zw;
	if(p.a<0.72){discard;}
	// The fixed sofa supplies the upholstery; independent poses supply the people and books.
	if(trim_cushion && local.y>0.60 && p.r>0.65 && p.g>0.60 && p.b>0.50 && max(max(p.r,p.g),p.b)-min(min(p.r,p.g),p.b)<0.28){discard;}
	COLOR=vec4(p.rgb,1.0)*tone;
}
