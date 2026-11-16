extends Node2D
## Presentation only: all decisions and remembered progress remain in AstrBot.
static var definition:Dictionary={}
const KINDS=["read","write","listen","select","washface","prep","tea","water","tidy","bench","onsen_rest","chess","arcade","outside_eat"]
var scene_id:String=""
var poses:Dictionary={}
var clock:float=0
var hidden_furniture:Array=[]
var shadows:Array[Vector2]=[]
var shadow_nodes:Dictionary={}

static func data() -> Dictionary:
	if definition.is_empty():definition=JSON.parse_string(FileAccess.get_file_as_string("res://assets/life-v18.json"))
	return definition

static func stage_for(c:Node) -> Dictionary:
	var kind:String=str(c.action).trim_prefix("life_")
	if c.sleeping or not str(c.action).begins_with("life_") or kind not in KINDS:return {}
	if kind in ["bench","arcade","washface","prep","tea"] and c.key=="selena":
		for other:Node in c.get_tree().get_nodes_in_group("world_residents"):
			if other!=c and other.scene_id==c.scene_id and other.action==c.action and not other.sleeping and not other.is_walking():
				var wait_at:Vector2=Vector2(190,275) if kind in ["prep","tea"] else Vector2(440,330) if kind=="washface" else c.feet+Vector2(65,10)
				return {"feet":wait_at,"sort":wait_at.y,"waiting_station":true}
	return {"home_activity":kind,"life_activity":kind,"feet":c.feet,"sort":c.feet.y,"seat":kind in ["bench","onsen_rest","chess","outside_eat"]}

static func destination(kind:String,actor:String) -> Array:
	match kind:
		"washface":return ["shared-home-bathroom","bath_sink"]
		"prep":return ["xiaojingyu-home","cook_prep"]
		"tea":return ["xiaojingyu-home","cook_tea"]
		"water":return ["shared-home-upstairs",actor+"_balcony"]
		"tidy":return ["shared-home-upstairs",actor+"_room_tidy"]
		"bench":return ["qianxia-park","bench"]
		"onsen_rest":return ["world-onsen","onsen_rest_a" if actor=="xiaoai" else "onsen_rest_b"]
		"chess":return ["world-arcade","arcade_xiangqi_far" if actor=="xiaoai" else "arcade_xiangqi_near"]
		"arcade":return ["world-arcade","arcade_mines"]
		"outside_eat":return ["world-restaurant","seat-c3_use" if actor=="xiaoai" else "seat-c4_use"]
		"select":return ["qianxia-shop","magazines"]
	return ["shared-home-upstairs","xiaoai_lyrics" if actor=="xiaoai" else "selena_score_work"]

func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	y_sort_enabled=true

func _process(delta:float) -> void:
	for node:Node2D in hidden_furniture:
		if is_instance_valid(node):node.visible=true
	hidden_furniture.clear()
	shadows.clear();queue_redraw()
	for sprite:Sprite2D in poses.values():sprite.visible=false
	for shadow:Polygon2D in shadow_nodes.values():shadow.visible=false
	if not get_parent().visible:return
	clock+=delta
	var reserved:Dictionary={}
	for c:Node in get_tree().get_nodes_in_group("world_residents"):
		if c.scene_id!=scene_id or c.is_walking() or not c.stage.has("life_activity"):continue
		var kind:String=c.stage.life_activity
		var slot:String=c.want_zone if kind in ["bench","arcade","chess","outside_eat","onsen_rest"] else c.key
		# A single physical seat is never occupied by two overlapping bodies.
		if reserved.has(slot):continue
		reserved[slot]=true
		_show(c,kind)

func _hide(ids:Array) -> void:
	for id:String in ids:
		var node:Node2D=get_parent().furniture.get(id)
		if is_instance_valid(node):node.visible=false;hidden_furniture.append(node)

func _show(c:Node,kind:String) -> void:
	var phase:int=int(clock*(.65 if kind in ["read","listen","bench","onsen_rest"] else 1.2))%2
	var group:String="universal"
	var index:int={"read":0,"write":2,"listen":4,"select":6}.get(kind,0)+(0 if c.key=="xiaoai" else 8)+phase
	var fraction:float=1.0
	var at:Vector2=c.feet
	if kind in ["washface","prep","tea","water"]:
		group="house";index={"washface":0,"prep":2,"tea":4,"water":6}[kind]+(0 if c.key=="xiaoai" else 8)+phase
		fraction=.79 if kind!="water" else 1.0
	elif kind in ["tidy","arcade"]:
		group="work";index=(0 if kind=="tidy" else 2)+(0 if c.key=="xiaoai" else 4)+phase
	elif kind in ["bench","onsen_rest","chess","outside_eat"]:
		group="seats";index={"bench":0,"onsen_rest":4,"chess":8,"outside_eat":12}[kind]+(0 if c.key=="xiaoai" else 2)+phase
		fraction=.94 if kind in ["bench","onsen_rest"] else .97
	var spec:Dictionary=data()[group];var cell:Dictionary=spec.cells[index];var r:Array=cell.rect
	var factor:float=86.9338235294*float(WorldData.scenes[scene_id].get("actorScale",1.0))/(float(cell.bounds[3])*fraction)
	var pin:Vector2=Vector2(cell.floor[0],cell.floor[1])
	# Register the stool's centre, rather than whichever one of its feet is a pixel lower.
	if kind=="washface":pin.x=164;at=Vector2(184,240)
	if kind in ["prep","tea"]:pin.x=147
	if kind=="water":pin.x=float(r[2])*.66;at.x-=30
	if kind=="tidy":pin.x=float(r[2])*.47
	if kind=="select" and scene_id=="qianxia-shop":
		var shelf:Dictionary=WorldData.scenes[scene_id].modules.magazines
		at=Vector2(float(shelf.x)-12,float(shelf.y)+float(shelf.h)+15)
	if kind in ["prep","tea"]:at+=Vector2(0,-18)
	if kind=="bench":
		_hide(["bench"]);at=Vector2(223.75,118);pin.x=float(cell.bounds[0])+float(cell.bounds[2])*.5
	elif kind=="onsen_rest":
		_hide(["bench_w" if c.key=="xiaoai" else "bench_e"]);at.y-=10;factor=103.0/float(cell.bounds[2])
	elif kind=="arcade":
		_hide(["arcade_mines"]);factor=96.0/float(cell.bounds[2]);pin.x=float(cell.bounds[0])+float(cell.bounds[2])*.5;at=Vector2(304,352)
	elif kind=="chess":
		_hide(["arcade_xiangqi","chess-far-seat","chess-near-seat"]);at=Vector2(880,224);pin.x=float(cell.bounds[0])+float(cell.bounds[2])*.5
	elif kind=="outside_eat":
		_hide(["table-c","seat-c1","seat-c2","seat-c3","seat-c4"]);at=Vector2(480,480);pin.x=float(cell.bounds[0])+float(cell.bounds[2])*.5
	if kind not in ["bench","onsen_rest","chess","outside_eat","arcade"]:
		if not shadow_nodes.has(c.key):
			var shadow:=Polygon2D.new();var points:=PackedVector2Array()
			for i:int in 24:points.append(Vector2(cos(TAU*i/24.0)*10,sin(TAU*i/24.0)*2.2))
			shadow.polygon=points;shadow.color=Color(0,0,0,.16);add_child(shadow);shadow_nodes[c.key]=shadow
		shadow_nodes[c.key].position=at-Vector2(0,.1);shadow_nodes[c.key].visible=true
	if not poses.has(c.key):
		var sprite:=Sprite2D.new();sprite.centered=false;sprite.region_enabled=true
		var mat:=ShaderMaterial.new();mat.shader=load("res://entities/life_alpha_v18.gdshader");sprite.material=mat
		add_child(sprite);poses[c.key]=sprite
	var sprite:Sprite2D=poses[c.key];sprite.texture=load(str(spec.texture));sprite.region_rect=Rect2(r[0],r[1],r[2],r[3]);sprite.position=at;sprite.offset=-pin;sprite.scale=Vector2.ONE*factor;sprite.visible=true
	var pixels:Vector2=sprite.texture.get_size()
	var live_game:Dictionary=VadsLink.arcade_view.get("sessions",{}).get("mines",{})
	sprite.material.set_shader_parameter("arcade_window",kind=="arcade" and live_game.get("game") is Dictionary and ArcadePanel.recent(live_game))
	sprite.material.set_shader_parameter("watering",kind=="water")
	sprite.material.set_shader_parameter("cell_uv",Vector4(float(r[0])/pixels.x,float(r[1])/pixels.y,float(r[2])/pixels.x,float(r[3])/pixels.y))
	if kind in ["outside_eat","chess"]:
		var paired:bool=false
		for other:Node in get_tree().get_nodes_in_group("world_residents"):
			if other!=c and other.scene_id==scene_id and other.action==c.action and not other.is_walking():paired=true
		if paired:
			var cut:float=pin.x
			if c.key=="xiaoai":sprite.region_rect.size.x=cut
			else:sprite.region_rect.position.x+=cut;sprite.region_rect.size.x-=cut;sprite.offset.x+=cut
	sprite.material.set_shader_parameter("tone",Color(.86,.82,.80) if BedroomPreview.night(Daylight.reading(SharedFeed.now_ms()).phase=="night") and scene_id!="shared-home-bathroom" else Color.WHITE)
	position.y=0

func _draw() -> void:
	for at:Vector2 in shadows:
		draw_set_transform(at-Vector2(0,.4),0,Vector2(1,.22));draw_circle(Vector2.ZERO,10,Color(0,0,0,.16))
	draw_set_transform(Vector2.ZERO)

