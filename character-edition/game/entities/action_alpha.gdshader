shader_type canvas_item;
uniform vec4 tone:source_color=vec4(1.0);
void fragment(){
	vec4 pixel=texture(TEXTURE,UV);
	if(pixel.a<0.72){discard;}
	COLOR=vec4(pixel.rgb,1.0)*tone;
}
