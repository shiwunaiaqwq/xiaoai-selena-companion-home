class_name WanderingNpc
extends Node2D
## Local decorative patrols; independent of resident identity, life, host and services.
static var definition: Dictionary={}
var scene_id: String
var skin: String
var special := false
var sprite := Sprite2D.new()
var spec: Dictionary
var nav: RoomNav
var route: Array[Vector2]=[]
var clock := 0.0
var pause := 1.0
var row := 0
var moving := false
var speed := 35.0
var rng := RandomNumberGenerator.new()
var patrol: Array[Vector2]=[]
var serial := 0

static func data() -> Dictionary:
	if definition.is_empty():definition=JSON.parse_string(FileAccess.get_file_as_string("res://assets/wandering-npcs-v15.json"))
	return definition

static func mount(room: Node2D, id: String) -> void:
	if not data().scenes.has(id):return
	var entries: Array=data().scenes[id]
	for i in entries.size():
		var npc:=WanderingNpc.new()
		npc.scene_id=id;npc.skin=str(entries[i].skin);npc.special=bool(entries[i].get("special",false));npc.serial=i
		npc.spec=data().skins[str(entries[i].skin)+( "_hop" if npc.special else "_walk")]
		room.add_child(npc)
		npc.configure(entries[i])

func configure(entry: Dictionary) -> void:
	add_to_group("ambient_npcs")
	rng.seed=hash(scene_id+skin+str(serial))
	nav=WorldData.nav(scene_id)
	speed=30.0 if special else 36.0+rng.randf_range(0,10)
	# Foot positions are sampled from the existing navigation grid, never inside furniture.
	for y in range(0,nav.grid.region.size.y,4):
		for x in range(0,nav.grid.region.size.x,4):
			var p: Vector2=nav.walk.position+Vector2(x,y)*nav.step
			if not nav.walkable(p):continue
			var near_door:=false
			for door in WorldData.scenes[scene_id].exits:
				var at: Dictionary=door.get("at",{})
				if at.has("x") and p.distance_to(WorldData.point(at))<45:near_door=true
			if not near_door:patrol.append(p)
	var preferred:=Vector2(entry.feet[0],entry.feet[1])
	position=preferred
	if not nav.walkable(position):
		var best:=INF
		for p in patrol:
			if p.distance_squared_to(preferred)<best:best=p.distance_squared_to(preferred);position=p
	sprite.centered=false;sprite.region_enabled=true;sprite.texture=load(str(spec.texture))
	sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	if skin!="xiaojingyu":
		var pixel:=ShaderMaterial.new()
		pixel.shader=load("res://entities/npc_pixel_finish.gdshader")
		pixel.set_shader_parameter("source_pixel_step",float(spec.pixel_step))
		sprite.material=pixel
	add_child(sprite)
	pause=.5+serial*.7
	_draw_frame()
	queue_redraw()

func choose_route() -> void:
	for attempt in 20:
		var target: Vector2=patrol[rng.randi_range(0,patrol.size()-1)]
		var distance:=position.distance_to(target)
		if distance<70 or distance>260:continue
		var candidate: Array[Vector2]=nav.route(position,target)
		if not candidate.is_empty():route=candidate;return
	pause=2.0

func advance(delta: float) -> void:
	clock+=delta
	moving=false
	if pause>0:pause-=delta
	elif route.is_empty():choose_route()
	else:
		var offset:=route[0]-position
		var next:=position+offset.normalized()*minf(speed*delta,offset.length())
		var blocked:=false
		for other in get_tree().get_nodes_in_group("ambient_npcs"):
			if other!=self and other.scene_id==scene_id and other.position.distance_to(next)<42 and other.position.distance_to(next)<other.position.distance_to(position):blocked=true
		for resident in get_tree().get_nodes_in_group("world_residents"):
			if resident.scene_id==scene_id and resident.feet.distance_to(next)<27 and resident.feet.distance_to(next)<resident.feet.distance_to(position):blocked=true
		if blocked:route.clear();pause=rng.randf_range(.8,1.8)
		elif nav.walkable(next):
			position=next;moving=true
			if absf(offset.x)>absf(offset.y):row=2 if offset.x>0 else 1
			else:row=0 if offset.y>0 else 3
			if position.distance_to(route[0])<.1:
				route.pop_front()
				if route.is_empty():pause=rng.randf_range(1.5,4.0)
		else:route.clear();pause=1.0
	_draw_frame()

func _process(delta: float) -> void:
	if get_parent().visible:advance(delta)

func _draw_frame() -> void:
	var frame:=int(clock*(4.0 if special else 6.0))%4 if moving or special else 0
	var index:=frame if special else row*4+frame
	var rect: Array=spec.rects[index]
	var anchor: Array=spec.anchors[index]
	var factor: float=float(spec.frame_scales[index] if spec.has("frame_scales") else spec.scale)*float(WorldData.scenes[scene_id].get("actorScale",1))
	sprite.region_rect=Rect2(rect[0],rect[1],rect[2],rect[3])
	sprite.scale=Vector2.ONE*factor
	sprite.offset=-Vector2(anchor[0],anchor[1])
	sprite.position=Vector2.ZERO
	if special:
		sprite.rotation=sin(clock*TAU*1.0)*.025
		sprite.position.y-=maxf(0,sin(clock*TAU*2.0))*1.5

func _draw() -> void:
	draw_set_transform(Vector2(0,-1),0,Vector2(1,.23))
	draw_circle(Vector2.ZERO,13,Color(.07,.09,.14,.20))
