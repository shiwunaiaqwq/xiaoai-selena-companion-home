shader_type canvas_item;
uniform vec4 tone:source_color=vec4(1.0);
void fragment(){
 vec4 p=texture(TEXTURE,UV);
 vec2 q=UV*vec2(1254.0);
 if(p.a<0.72 || (q.x>250.0 && q.x<390.0 && q.y>150.0)){discard;}
 COLOR=vec4(p.rgb,1.0)*tone;
}
