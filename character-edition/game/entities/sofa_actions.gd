class_name SofaActions
extends Node2D
## One sofa composite for the two independent residents' current seated states.
static var _definition: Dictionary={}
var scene_id: String="xiaojingyu-home"
var current_state: String="empty"
var current_frame: int=0
var _clock: float=0.0
var _sprite:=Sprite2D.new()
var _front:=Sprite2D.new()
var _textures: Dictionary={}
var _tv: Node2D
var _left:=Sprite2D.new()
var _right:=Sprite2D.new()
var _new_texture:Texture2D

static func data() -> Dictionary:
	if _definition.is_empty():
		_definition=JSON.parse_string(FileAccess.get_file_as_string("res://assets/renovation/sofa-actions-v13.json"))
	return _definition

func setup(id: String, layer: Dictionary) -> void:
	scene_id=id
	position=Vector2(0,float(layer.depth))
	_sprite.centered=false
	_sprite.region_enabled=true
	add_child(_sprite)
	for sprite:Sprite2D in [_left,_right]:
		sprite.centered=false;sprite.region_enabled=true;sprite.visible=false
		var mat:=ShaderMaterial.new();mat.shader=load("res://entities/sofa_overlay_v19.gdshader");sprite.material=mat;add_child(sprite)
	_new_texture=load(str(load("res://entities/home_activities.gd").extension().sofa.texture))
	_front.centered=false
	_front.region_enabled=true
	_front.z_index=0
	add_child(_front)
	for state in data().states:
		_textures[state]=load(str(data().states[state].atlas))
	queue_redraw()

func _ready() -> void:
	_tv=Node2D.new()
	_tv.position=Vector2(0,float(data().tv_sort))
	_tv.draw.connect(_draw_tv)
	get_parent().call_deferred("add_child",_tv)
	refresh()

func refresh() -> String:
	var occupants: Array[String]=[]
	var residents:Dictionary={}
	var custom:bool=false
	for resident in get_tree().get_nodes_in_group("world_residents"):
		if resident.scene_id==scene_id and not resident.is_walking() and resident.stage.has("sofa_action"):
			occupants.append(resident.key);residents[resident.key]=resident
			if resident.action in ["sofa_rest","sofa_read","sofa_music","sofa_album","sofa_phone"]:custom=true
	current_state="both" if "xiaoai" in occupants and "selena" in occupants else "xiaoai" if "xiaoai" in occupants else "selena" if "selena" in occupants else "empty"
	var render_state:String="empty" if custom else current_state
	var spec: Dictionary=data().states[render_state]
	current_frame=0 if render_state=="empty" else int(floorf(_clock*float(data().fps)))%4
	var texture: Texture2D=_textures[render_state]
	var cell:=texture.get_size()/2.0
	var pin: Array=spec.registration[current_frame]
	var body: Array=data().body
	var factor: float=float(body[2])/float(pin[1])
	_sprite.texture=texture
	_sprite.region_rect=Rect2(Vector2(current_frame%2,int(current_frame/2))*cell,cell)
	_sprite.scale=Vector2.ONE*factor
	_sprite.position=Vector2(float(body[0])-float(pin[0])*factor,float(body[1])+float(body[3])-float(pin[2])*factor)-position
	_sprite.modulate=Color(.86,.80,.78) if BedroomPreview.night(Daylight.reading(SharedFeed.now_ms()).phase=="night") else Color.WHITE
	# Keep the cushion seams, broad back panel and sofa feet fixed across action frames.
	var fixed: Texture2D=_textures.empty
	var fixed_cell:=fixed.get_size()/2.0
	var fixed_pin: Array=data().states.empty.registration[0]
	var fixed_scale: float=float(body[2])/float(fixed_pin[1])
	_front.texture=fixed
	_front.region_rect=Rect2(0,365,fixed_cell.x,fixed_cell.y-365)
	_front.scale=Vector2.ONE*fixed_scale
	_front.position=Vector2(float(body[0])-float(fixed_pin[0])*fixed_scale,float(body[1])+float(body[3])-(float(fixed_pin[2])-365.0)*fixed_scale)-position
	_front.modulate=_sprite.modulate
	_left.visible=false;_right.visible=false
	if custom:
		for actor:String in residents:_show_independent(actor,str(residents[actor].action),_left if actor=="xiaoai" else _right)
		if residents.values().any(func(c):return c.action=="sofa_phone"):
			for actor:String in residents:
				if str(residents[actor].action)=="sofa_phone":continue
				var other:Sprite2D=_left if actor=="xiaoai" else _right
				var pivot:=Vector2(418.5 if actor=="xiaoai" else 500.5,458)-position
				other.position=pivot+(other.position-pivot)*.82;other.scale*=.82
	if is_instance_valid(_tv):
		_tv.visible=residents.has("xiaoai") and str(residents.xiaoai.action) in ["sofa_game","play_game","game"]
		_tv.queue_redraw()
	return current_state

func _process(delta: float) -> void:
	if not get_parent().visible:return
	_clock+=delta
	refresh()

func _draw() -> void:
	var body: Array=data().body
	for x in [float(body[0])+14.0,float(body[0])+float(body[2])-14.0]:
		draw_set_transform(Vector2(x,float(body[1])+float(body[3])-.6)-position,0,Vector2(1,.25))
		draw_circle(Vector2.ZERO,8,Color(.08,.10,.14,.18))
	draw_set_transform(Vector2.ZERO)

func _draw_tv() -> void:
	if not current_state in ["xiaoai","both"]:return
	var r: Array=data().tv_screen
	var at:=Vector2(r[0],r[1])-_tv.position
	var size:=Vector2(r[2],r[3])
	_tv.draw_rect(Rect2(at,size),Color("182b48"))
	_tv.draw_rect(Rect2(at+Vector2(0,size.y*.77),Vector2(size.x,size.y*.23)),Color("4f8062"))
	for i in 6:
		var x: float=fposmod(float(i)*17.0-_clock*9.0,size.x-3)
		_tv.draw_rect(Rect2(at+Vector2(x,6+int(i%2)*5),Vector2(2,2)),Color("e6d797"))
	var hero:=at+Vector2(size.x*.33,size.y*.63-sin(_clock*2.0)*2)
	_tv.draw_rect(Rect2(hero,Vector2(5,6)),Color("e8a5b6"))
	_tv.draw_rect(Rect2(hero+Vector2(1,-3),Vector2(4,3)),Color("f4dbb0"))
	_tv.draw_rect(Rect2(at+Vector2(4,3),Vector2(16,2)),Color("badbe2"))

func _show_independent(actor:String,action:String,sprite:Sprite2D) -> void:
	var texture:Texture2D
	var source:Rect2
	var pin:Array
	if action=="sofa_phone":
		texture=load("res://assets/renovation/sofa-phone-v21.png")
		var row:int=0 if actor=="xiaoai" else 1
		var frame:int=1 if fposmod(_clock,4.2)>3.9 else 0
		source=Rect2(frame*768,row*512,768,512)
		pin=[57,651,505 if row==0 else 473]
	elif action in ["sofa_rest","sofa_read","sofa_music","sofa_album"]:
		var group:Dictionary=load("res://entities/life_activities_v18.gd").data().sofa if actor=="xiaoai" and action!="sofa_album" else load("res://entities/home_activities.gd").extension().sofa
		var index:int={"sofa_rest":0,"sofa_read":2,"sofa_music":4,"sofa_album":6}[action]
		var fps:float=.4 if action=="sofa_rest" else 1.2
		var cell:Dictionary=group.cells[index+int(_clock*fps)%2];var r:Array=cell.rect
		texture=load(str(group.texture));source=Rect2(r[0],r[1],r[2],r[3]);pin=cell.sofa
	else:
		texture=_textures[actor];var size:Vector2=texture.get_size()/2.0;var frame:int=int(_clock*float(data().fps))%4
		source=Rect2(Vector2(frame%2,frame/2)*size,size);pin=data().states[actor].registration[frame]
	var body:Array=data().body;var scale_of:float=float(body[2])/float(pin[1])
	var pixels:Vector2=texture.get_size()
	sprite.material.set_shader_parameter("cell_uv",Vector4(source.position.x/pixels.x,source.position.y/pixels.y,source.size.x/pixels.x,source.size.y/pixels.y))
	sprite.material.set_shader_parameter("trim_cushion",action in ["sofa_rest","sofa_read","sofa_music","sofa_album","sofa_phone"])
	var top:Vector2=Vector2(float(body[0])-float(pin[0])*scale_of,float(body[1])+float(body[3])-float(pin[2])*scale_of)
	var min_x:float=float(body[0])+(0.0 if actor=="xiaoai" else float(body[2])*.48)
	var max_x:float=float(body[0])+float(body[2])*(.68 if actor=="xiaoai" else 1.0)
	var cut_left:float=maxf(0,(min_x-top.x)/scale_of)
	var cut_right:float=minf(source.size.x,(max_x-top.x)/scale_of)
	var cut_bottom:float=clampf((_front.position.y+position.y-top.y)/scale_of,0,source.size.y)
	if action in ["sofa_rest","sofa_read","sofa_music","sofa_album"]:cut_bottom=minf(cut_bottom,source.size.y*.66)
	if action=="sofa_phone":cut_bottom=minf(cut_bottom,286.0 if actor=="xiaoai" else 254.0)
	if cut_right<=cut_left or cut_bottom<=0:return
	sprite.texture=texture;sprite.region_rect=Rect2(source.position+Vector2(cut_left,0),Vector2(cut_right-cut_left,cut_bottom));sprite.scale=Vector2.ONE*scale_of;sprite.position=top-position+Vector2(cut_left*scale_of,0);sprite.visible=true;sprite.material.set_shader_parameter("tone",_sprite.modulate)
