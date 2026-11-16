extends Node2D
## Continuous joint animation: one fixed model, no whole-character frame changes.
var spec: Dictionary
var body:=Node2D.new()
var limbs: Array[Sprite2D]=[]
var factor:=1.0
var leg_height:=0.0

func setup(data: Dictionary) -> void:
	spec=data;factor=float(data.factor)
	var texture: Texture2D=load(str(data.texture))
	add_child(body)
	for i in 5:
		var r: Array=data.parts[i]
		var s:=Sprite2D.new()
		s.texture=texture;s.centered=false;s.region_enabled=true
		s.region_rect=Rect2(r[0],r[1],r[2],r[3]);s.scale=Vector2.ONE*factor
		s.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		var material:=ShaderMaterial.new()
		material.shader=load("res://entities/npc_pixel_finish.gdshader")
		material.set_shader_parameter("source_pixel_step",3.0)
		material.set_shader_parameter("alpha_cutoff",.985)
		s.material=material
		body.add_child(s);limbs.append(s)
		if i==0:s.offset=Vector2(-float(r[2])*.5,-float(r[3]));s.z_index=1
		elif i in [1,2]:
			s.offset=Vector2(-float(r[2])*.90 if i==1 else -float(r[2])*.10,-float(r[3])*.52);s.z_index=2
		else:s.offset=Vector2(-float(r[2])*.5,-3);s.z_index=0
	leg_height=float(data.parts[3][3])*factor*.90
	pose(0)

func pose(seconds: float) -> void:
	var phase:=seconds*TAU/float(spec.cycle)
	var swing:=sin(phase)
	body.position=Vector2(swing*1.7,-leg_height)
	body.rotation=swing*.035
	limbs[1].position=Vector2(-7,-leg_height*.82)
	limbs[2].position=Vector2(7,-leg_height*.82)
	limbs[1].rotation=1.0+swing*.98
	limbs[2].rotation=-1.0+swing*.98
	limbs[3].position=Vector2(-5,0)
	limbs[4].position=Vector2(5,0)
	limbs[3].rotation=maxf(0,swing)*.85
	limbs[4].rotation=-maxf(0,-swing)*.85
