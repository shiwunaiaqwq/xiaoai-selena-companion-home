shader_type canvas_item;
uniform vec4 tone:source_color=vec4(1.0);
uniform bool arcade_window=false;
uniform bool watering=false;
uniform vec4 cell_uv=vec4(0.0,0.0,1.0,1.0);
void fragment(){
	vec4 pixel=texture(TEXTURE,UV);
	vec2 local=(UV-cell_uv.xy)/cell_uv.zw;
	if(pixel.a<0.72){discard;}
	if(watering && ((local.x<0.43 && local.y>0.60) || (local.x<0.28 && local.y>0.47))){discard;}
	// Preserve the real game's screen below the composite, including live scores.
	if(arcade_window && local.x>0.2 && local.x<0.8 && local.y>0.2 && local.y<0.52 && max(max(pixel.r,pixel.g),pixel.b)<0.055){discard;}
	COLOR=vec4(pixel.rgb,1.0)*tone;
}
