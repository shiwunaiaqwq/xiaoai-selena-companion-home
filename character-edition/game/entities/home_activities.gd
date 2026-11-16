extends Node2D
## Furniture-aware domestic visuals. Original AstrBot remains the life authority.
static var definition:Dictionary={}
var scene_id:String=""
var clock:float=0.0
var textures:Dictionary={}
var people:Array=[]
var state:String="empty"
var meal_sprite:=Sprite2D.new()
var poses:Dictionary={}
var desk_clear:Node2D
static var extra:Dictionary={}
static func extension() -> Dictionary:
	if extra.is_empty():extra=JSON.parse_string(FileAccess.get_file_as_string("res://assets/home-v17.json"))
	return extra

static func data() -> Dictionary:
	if definition.is_empty():definition=JSON.parse_string(FileAccess.get_file_as_string("res://assets/home-activities-v16.json"))
	return definition

static func stage_for(c:Node) -> Dictionary:
	if c.sleeping:return {}
	var kind:String=str(c.action).trim_prefix("home_")
	if not str(c.action).begins_with("home_"):return {}
	if kind in ["eat","eat_phone","cook","wash_food","wash_dishes"] and c.scene_id!="xiaojingyu-home":return {}
	if kind in ["view","wardrobe","mirror"] and c.scene_id!="shared-home-upstairs":return {}
	if kind in ["diary","desk_read","old_letters"] and (c.key!="selena" or c.scene_id!="shared-home-upstairs"):return {}
	if kind in ["shower","soak"] and c.scene_id!="shared-home-bathroom":return {}
	if kind not in ["eat","eat_phone","cook","wash_food","wash_dishes","view","wardrobe","mirror","diary","desk_read","old_letters","shower","soak"]:return {}
	if c.key=="selena" and kind in ["cook","wash_food","wash_dishes","shower","soak"]:
		for other:Node in c.get_tree().get_nodes_in_group("world_residents"):
			if other==c or other.scene_id!=c.scene_id or other.sleeping or other.is_walking():continue
			var same_sink:bool=kind in ["wash_food","wash_dishes"] and str(other.action) in ["home_wash_food","home_wash_dishes"]
			var same_bath:bool=kind in ["shower","soak"] and str(other.action) in ["home_shower","home_soak"]
			if str(other.action)==str(c.action) or same_sink or same_bath:
				var wait_at:Vector2=Vector2(440,330) if same_bath else Vector2(255,275)
				return {"feet":wait_at,"sort":wait_at.y,"waiting_station":true}
	return {"home_activity":kind,"feet":c.feet,"sort":c.feet.y,"seat":kind in ["eat","eat_phone","diary","desk_read","old_letters","soak"]}

func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	meal_sprite.centered=false;meal_sprite.region_enabled=true;meal_sprite.visible=false;add_child(meal_sprite)
	var meal_material:=ShaderMaterial.new();meal_material.shader=load("res://entities/meal_motion.gdshader");meal_sprite.material=meal_material
	for kind:String in ["dining","cook","diary"]:textures[kind]=load(str(data()[kind].texture))
	textures.wood_day=load("res://assets/renovation/first-floor-day.png")
	textures.wood_night=load("res://assets/renovation/first-floor-night.png")
	textures.up_day=load("res://assets/renovation/rear-balconies-heart-day-v13.png")
	textures.up_night=load("res://assets/renovation/rear-balconies-heart-night-v13.png") if ResourceLoader.exists("res://assets/renovation/rear-balconies-heart-night-v13.png") else textures.up_day
	textures.clear_day=load("res://assets/renovation/personal-clear-day-v17.png")
	textures.clear_night=load("res://assets/renovation/personal-clear-night-v17.png")
	if scene_id=="shared-home-upstairs":z_index=85
	position.y=245 if scene_id=="xiaojingyu-home" else 290
	if scene_id=="shared-home-upstairs":
		desk_clear=load("res://entities/registered_ground.gd").new()
		desk_clear.xs=[[804,502.5],[984,615.0]];desk_clear.ys=[[184,167.361111],[240,206.25],[354,271.5625]]
		desk_clear.position=-position;desk_clear.visible=false;add_child(desk_clear)
		var blend:=ShaderMaterial.new();blend.shader=load("res://entities/registered_patch_blend.gdshader")
		blend.set_shader_parameter("source_bounds",Vector4(804.0/1536.0,184.0/1024.0,984.0/1536.0,354.0/1024.0));blend.set_shader_parameter("feather_pixels",3.0);desk_clear.material=blend
	queue_redraw()

func _process(delta:float) -> void:
	if not get_parent().visible:return
	clock+=delta;people=[]
	if is_instance_valid(desk_clear):desk_clear.visible=false
	for sprite:Sprite2D in poses.values():sprite.visible=false
	for c:Node in get_tree().get_nodes_in_group("world_residents"):
		if c.scene_id==scene_id and not c.is_walking() and c.stage.has("home_activity"):people.append(c)
	if scene_id=="shared-home-upstairs":
		z_index=85 if people.any(func(c):return c.stage.get("home_activity","") in ["wardrobe","mirror"]) else 0
	queue_redraw()

func _point(p:Vector2) -> Vector2:return p-position

func _night() -> bool:return BedroomPreview.night(Daylight.reading(SharedFeed.now_ms()).phase=="night")

func _color() -> Color:return Color(.86,.82,.80) if _night() and scene_id!="shared-home-bathroom" else Color.WHITE

func _patch(rect:Rect2,upstairs:bool=false) -> void:
	if upstairs:
		var key:String="floor_image_night" if _night() else "floor_image_day"
		if not textures.has(key):textures[key]=textures["up_night" if _night() else "up_day"].get_image()
		var image:Image=textures[key]
		for y:int in range(int(rect.position.y),int(rect.end.y)):
			var source_y:int=roundi(240+(float(y)-206.25)*300.0/171.875)
			var left:Color=image.get_pixel(1070,source_y)
			var right:Color=image.get_pixel(1140,source_y)
			for band:int in 8:
				var x:float=rect.position.x+float(band)*rect.size.x/8
				draw_line(_point(Vector2(x,y)),_point(Vector2(x+rect.size.x/8+.2,y)),left.lerp(right,(float(band)+.5)/8),1.1)
		return
	var source:Vector2=Vector2(1000,400) if upstairs else Vector2(760,280)
	var texture:Texture2D=textures["up_night" if _night() else "up_day"] if upstairs else textures["wood_night" if _night() else "wood_day"]
	for y:float in range(int(rect.position.y),int(rect.end.y),20):
		for x:float in range(int(rect.position.x),int(rect.end.x),100):
			var size:Vector2=Vector2(minf(100,rect.end.x-x),minf(20,rect.end.y-y))
			draw_texture_rect_region(texture,Rect2(_point(Vector2(x,y)),size),Rect2(source,size/0.625))

func _draw() -> void:
	if not is_inside_tree():return
	if scene_id=="xiaojingyu-home":
		_draw_dining()
		for c:Node in people:
			if c.stage.get("home_activity","") in ["cook","wash_food","wash_dishes"]:_draw_kitchen(c)
	elif scene_id=="shared-home-upstairs":
		for c:Node in people:
			if c.stage.get("home_activity","") in ["diary","desk_read","old_letters"]:_draw_diary(str(c.stage.home_activity))
			elif c.stage.get("home_activity","")=="view":_draw_view(c)
			elif c.stage.get("home_activity","") in ["wardrobe","mirror"]:_draw_personal(c)
	elif scene_id=="shared-home-bathroom":
		for c:Node in people:
			if c.stage.get("home_activity","") in ["shower","soak"]:_draw_bath(c);break

func _draw_dining() -> void:
	var occupied:Array=[]
	for c:Node in people:
		if c.stage.get("home_activity","") in ["eat","eat_phone"]:occupied.append(c.key)
	state="both" if occupied.has("xiaoai") and occupied.has("selena") else "xiaoai" if occupied.has("xiaoai") else "selena" if occupied.has("selena") else "empty"
	# Empty state retains the original table; composites replace it only while occupied.
	meal_sprite.visible=state!="empty"
	if state=="empty":return
	if people.any(func(c):return c.stage.get("home_activity","")=="eat_phone"):
		meal_sprite.visible=false;_draw_phone_dining(occupied);return
	var index:int={"both":0,"xiaoai":1,"selena":2}[state]
	var spec:Dictionary=data().dining;var cell:Dictionary=spec.cells[index]
	var scale_of:float=float(spec.table[2])/float(cell.table[1]-cell.table[0]+1)

	var top:Vector2=Vector2(float(spec.table[0])-float(cell.table[0])*scale_of,float(spec.table[1])-float(cell.table_y)*scale_of)
	var r:Array=cell.rect
	meal_sprite.texture=textures.dining;meal_sprite.region_rect=Rect2(r[0],r[1],r[2],r[3]);meal_sprite.position=_point(top);meal_sprite.scale=Vector2.ONE*scale_of;meal_sprite.modulate=_color()
	meal_sprite.material.set_shader_parameter("atlas_cell",Vector2(index%2,index/2))
	meal_sprite.material.set_shader_parameter("meal_tint",_color())
	# Warm food breathes gently; the table and its feet remain fixed.
	for x:float in [650.0,716.0]:
		if (x<680 and not occupied.has("xiaoai")) or (x>680 and not occupied.has("selena")):continue
		for i:int in 2:
			var t:float=fposmod(clock*.45+float(i)*.5,1.0)
			draw_arc(_point(Vector2(x+sin(t*TAU)*1.2,151-t*6)),1.4,0.0,PI,7,Color(1,1,.92,(1-t)*.32),.7)

func _pose_sprite(key:String,texture:Texture2D,source:Rect2,top:Vector2,factor:float) -> void:
	if not poses.has(key):
		var sprite:=Sprite2D.new();sprite.centered=false;sprite.region_enabled=true;sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		var material:=ShaderMaterial.new();material.shader=load("res://entities/action_alpha.gdshader");sprite.material=material
		add_child(sprite);poses[key]=sprite
	var sprite:Sprite2D=poses[key];sprite.visible=true;sprite.texture=texture;sprite.region_rect=source;sprite.position=_point(top);sprite.scale=Vector2.ONE*factor;sprite.material.set_shader_parameter("tone",_color())

func _draw_kitchen(c:Node) -> void:
	var kind:String=c.stage.home_activity
	var group:String="cook" if kind=="cook" else "wash"
	var phase:int=int(clock*2.0)%2
	var frame:int=phase+(0 if c.key=="xiaoai" else 2) if group=="cook" else phase+(0 if kind=="wash_food" else 2)+(0 if c.key=="xiaoai" else 4)
	var spec:Dictionary=extension()[group];var cell:Dictionary=spec.cells[frame]
	var fraction:float=.775 if group=="cook" else .745
	var reference:Dictionary=spec.cells[frame-frame%2]
	var factor:float=86.9338235294/(float(reference.bounds[3])*fraction)
	var at:Vector2=WorldData.point(WorldData.scenes[scene_id].zones[c.want_zone]);var r:Array=cell.rect
	var stable_x:float=float(cell.bounds[0])+float(cell.bounds[2])*.5 if group=="cook" else 210.0
	var top:Vector2=at-Vector2(stable_x,cell.floor[1])*factor
	draw_set_transform(_point(at-Vector2(0,.5)),0,Vector2(1,.22));draw_circle(Vector2.ZERO,15,Color(0,0,0,.16));draw_set_transform(Vector2.ZERO)
	_pose_sprite(c.key,load(str(spec.texture)),Rect2(r[0],r[1],r[2],r[3]),top,factor)
	if group=="wash":
		for i:int in 5:
			var t:float=fposmod(clock*1.2+float(i)*.2,1.0)
			draw_circle(_point(at+Vector2(20+float(i%3)*2,-66+t*8)),.6,Color(.85,.97,1,(1-t)*.7))

func _draw_view(c:Node) -> void:
	var walk:Dictionary=WorldData.actors[c.art].walk;var r:Array=walk.rects[12];var anchor:Array=walk.anchors[12]
	var factor:float=86.9338235294/float(r[3])
	_pose_sprite(c.key,load("res://assets/actors/"+str(walk.file)),Rect2(r[0],r[1],r[2],r[3]),c.feet-Vector2(anchor[0],anchor[1])*factor,factor)
	draw_set_transform(_point(c.feet),0,Vector2(1,.22));draw_circle(Vector2.ZERO,11,Color(0,0,0,.15));draw_set_transform(Vector2.ZERO)

func _draw_personal(c:Node) -> void:
	var kind:String=c.stage.home_activity
	var frame:int=(0 if c.key=="xiaoai" else 4)+(0 if kind=="wardrobe" else 2)+int(clock*1.5)%2
	var spec:Dictionary=extension().personal;var cell:Dictionary=spec.cells[frame];var r:Array=cell.rect
	var id:String=c.key+"-"+kind;var module:Dictionary=WorldData.scenes[scene_id].modules[id]
	var layer:Dictionary=WorldData.layers[scene_id].layers.filter(func(item):return item.get("id","")==id)[0]
	var clear:Texture2D=textures.clear_night if _night() else textures.clear_day;var region:Array=layer.region
	draw_texture_rect_region(clear,Rect2(_point(Vector2(layer.x,layer.y)),Vector2(layer.w,layer.h)),Rect2(region[0],region[1],region[2],region[3]))
	var factor:float=86.9338235294/float(cell.char_height)
	var furniture_left:float=float(r[2])*(.47 if kind=="wardrobe" else .52)
	var top:Vector2=Vector2(float(module.x)-furniture_left*factor,float(module.y)+float(module.h)-float(cell.floor[1])*factor)
	if kind=="mirror":top.y+=c.feet.y-(top.y+float(cell.actor_floor[1])*factor)
	_pose_sprite(c.key,load(str(spec.texture)),Rect2(r[0],r[1],r[2],r[3]),top,factor)

func _draw_diary(kind:String="diary") -> void:
	# The damaged page-turn frame is deliberately excluded; three writing frames remain.
	desk_clear.texture=load("res://assets/renovation/desk-clear-night-v19.png" if _night() else "res://assets/renovation/desk-clear-day-v19.png")
	desk_clear.visible=true;desk_clear.queue_redraw()
	var frame:int=[0,1,3,1][int(clock*2.2)%4]
	var cell:Dictionary=data().diary.cells[frame];var r:Array=cell.rect
	var factor:float=100.625/float(cell.table[1]-cell.table[0]+1)

	var top:Vector2=Vector2(507.5-float(cell.table[0])*factor,267.55-float(cell.foot[1])*factor)
	if kind=="diary":_pose_sprite("desk",textures.diary,Rect2(r[0],r[1],r[2],r[3]),top,factor)
	else:
		var texture:Texture2D=load("res://assets/renovation/selena-reading-v18.png")
		var frame_read:int=int(clock*.65)%2+(2 if kind=="old_letters" else 0)
		var size:Vector2=texture.get_size()/2.0
		# Same desk, stool and registration as the original writing composite.
		_pose_sprite("desk",texture,Rect2(Vector2(frame_read%2,frame_read/2)*size,size),Vector2(507.5-67.0*(100.625/512.0),267.55-597.0*(100.625/512.0)),100.625/512.0)

func _draw_head(c:Node,center:Vector2,alpha:float=1.0) -> void:
	var walk:Dictionary=WorldData.actors[c.art].walk
	var texture:Texture2D=load("res://assets/actors/"+str(walk.file))
	var r:Array=walk.rects[0]
	var height:float=float(r[3])*.58
	var factor:float=42.0/height
	var key:String="bath-head-"+c.key
	_pose_sprite(key,texture,Rect2(r[0],r[1],r[2],height),center-Vector2(float(r[2])*factor*.5,0),factor)
	var mat:ShaderMaterial=poses[key].material
	mat.shader=load("res://entities/bath_head_v19.gdshader")
	var pixels:Vector2=texture.get_size()
	mat.set_shader_parameter("head_uv",Vector4(float(r[0])/pixels.x,float(r[1])/pixels.y,float(r[2])/pixels.x,height/pixels.y))
	mat.set_shader_parameter("tone",Color(1,1,1,alpha))

func _draw_bath(c:Node) -> void:
	var shower:bool=c.stage.get("home_activity","")=="shower"
	var texture:Texture2D=load("res://assets/renovation/bath-towels-v19.png")
	var cell:Vector2=texture.get_size()/2.0
	var row:int=0 if c.key=="xiaoai" else 1
	var col:int=0 if shower else 1
	var source:=Rect2(Vector2(col,row)*cell,cell)
	var factor:float=90.0/590.0
	var at:=Vector2(347,247) if shower else Vector2(520,228)
	_pose_sprite("bath-towel-"+c.key,texture,source,at-Vector2(330 if shower else 296,610)*factor,factor)
	if not shower:
		# Preserve the original bath front as a foreground occluder over the seated lap.
		var bath:Texture2D=load("res://assets/renovation/bathroom-modern-v16.png")
		_pose_sprite("bath-front",bath,Rect2(830,401,520,141),Vector2(415,200.5),.5)
		poses["bath-front"].z_index=1
	for i:int in 18 if shower else 4:
		if shower:
			var x:float=320+float(i%7)*7
			var y:float=113+fposmod(clock*60+float(i)*13,132)
			draw_line(_point(Vector2(x,y)),_point(Vector2(x-1,y+6)),Color(.94,.99,1,.30),.7)
		else:
			var t:float=fposmod(clock*.19+float(i)*.25,1.0)
			draw_arc(_point(Vector2(491+float(i)*17,194-t*14)),3.5,0,PI,8,Color(.94,1,1,(1-t)*.22),.7)

func _draw_phone_dining(occupied:Array) -> void:
	var phone_count:int=people.filter(func(c):return c.stage.get("home_activity","")=="eat_phone").size()
	if occupied.size()==2 and phone_count==1:
		_draw_mixed_phone_dining();return
	var texture:Texture2D=load("res://assets/renovation/dining-phone-v21.png")
	var factor:float=143.75/529.0
	# One fixed table body; upper chair/person halves change without moving furniture.
	var base_top:=Vector2(608.125-60.0*factor,145.625-238.0*factor)
	var base_index:int=0 if occupied.size()==2 else 1 if occupied.has("xiaoai") else 2
	var base_shift:float=26 if base_index==1 else 0
	_pose_sprite("phone-table",texture,Rect2((base_index%2)*627,(base_index/2)*627+280,627,347),base_top+Vector2(base_shift,280)*factor,factor)
	for actor:String in ["xiaoai","selena"]:
		var is_left:bool=actor=="xiaoai"
		var present:bool=occupied.has(actor)
		var phone:bool=people.any(func(c):return c.key==actor and c.stage.get("home_activity","")=="eat_phone")
		var phase:int=1 if fposmod(clock,3.2)>1.5 else 0
		var index:int=(3 if phase==1 else 0) if present else (2 if is_left else 1)
		var image:Texture2D=texture
		var x:float=0 if is_left else 324
		var width:float=324 if is_left else 303
		var shift:float=-26 if index in [1,3] else 0
		var src:=Rect2((index%2)*627+x+shift,(index/2)*627,width,280)
		var top:Vector2=base_top+Vector2(x,0)*factor
		var scale_of:float=factor
		_pose_sprite("phone-diner-"+actor,image,src,top,scale_of)
		poses["phone-diner-"+actor].material.shader=load("res://entities/action_alpha.gdshader")
	_pose_sprite("phone-flowers",texture,Rect2(250,170,145,110),base_top+Vector2(250,170)*factor,factor)
	poses["phone-flowers"].z_index=1

func _draw_mixed_phone_dining() -> void:
	var texture:Texture2D=load("res://assets/renovation/dining-phone-mixed-v21.png")
	var row:int=0 if people.any(func(c):return c.key=="xiaoai" and c.stage.get("home_activity","")=="eat_phone") else 1
	var phase:int=1 if fposmod(clock,3.2)>1.5 else 0
	var factor:float=143.75/529.0
	var top:=Vector2(608.125-60.0*factor,145.625-238.0*factor)
	_pose_sprite("mixed-phone-table",texture,Rect2(0,row*627+280,627,347),top+Vector2(0,280)*factor,factor)
	_pose_sprite("mixed-phone-upper",texture,Rect2(601 if phase==1 else 0,row*627,627,280),top,factor)
