extends Node

func _ready() -> void:
	call_deferred("check")

func check() -> void:
	var issues: Array[String]=[]
	var lower: String="xiaojingyu-home"
	var upper: String="shared-home-upstairs"
	var lower_start:=WorldData.point(WorldData.scenes[lower].zones.shared_left)
	if WorldData.scene_path(lower,upper)!=[lower,upper] or WorldData.scene_path(upper,lower)!=[upper,lower]:issues.append("Floor route missing")
	HomeGrid.choose(lower)
	if HomeGrid.defaults().stored.size()!=28:issues.append("Old furniture not stored")
	var ports: Dictionary={lower:[Vector2(174,350),Vector2(116,350),Vector2(116,365),Vector2(116,474),Vector2(210,490),Vector2(230,490)],upper:[Vector2(230,525),Vector2(200,525),Vector2(116,525),Vector2(116,510),Vector2(116,401)]}
	var stair_offset: float=WorldData.scenes[upper].get("stairOffsetY",0)
	for i in ports[upper].size():ports[upper][i]+=Vector2(0,stair_offset)
	for scene in [lower,upper]:
		var nav: RoomNav=WorldData.nav(scene)
		var previous:=WorldData.point(WorldData.scenes[upper].zones.upstairs_center) if scene==upper else lower_start
		for point: Vector2 in ports[scene]:
			if not nav.walkable(point) or nav.route(previous,point).is_empty():issues.append("Blocked stair port: "+scene+str(point))
			previous=point
		for item in ["xj-bed","xj-sofa","xj-desk","xj-tank"]:
			if WorldData.scenes[scene].modules.has(item):issues.append("Ghost furniture: "+item)
	var upper_nav: RoomNav=WorldData.nav(upper)
	var lower_nav: RoomNav=WorldData.nav(lower)
	for zone in ["kitchen_sink","kitchen_stove","kitchen_fridge","dining","dining_seat","living_sofa","living_tv","living_armchair","living_reading","living_center","sofa_xiaoai","sofa_selena"]:
		if not WorldData.scenes[lower].zones.has(zone):continue
		var target:=WorldData.point(WorldData.scenes[lower].zones[zone])
		if not lower_nav.walkable(target) or lower_nav.route(lower_start,target).is_empty():issues.append("First-floor furniture unreachable: "+zone)
	for zone in WorldData.scenes[upper].zones:
		var target:=WorldData.point(WorldData.scenes[upper].zones[zone])
		if not upper_nav.walkable(target) or upper_nav.route(WorldData.point(WorldData.scenes[upper].zones.upstairs_center),target).is_empty():
			issues.append("Bedroom/balcony unreachable: "+zone)
			print("Navigation diagnostic: ",zone," walkable=",upper_nav.walkable(target)," target=",target)
			for block in upper_nav.blocks:
				if block.has_point(target):print("Blocking rectangle: ",block)
			print("Cross-bed clearance: ",upper_nav.clearance," step ",upper_nav.step," row241=",upper_nav.walkable(Vector2(600,241))," / ",upper_nav.walkable(Vector2(680,241)))
	for probe in WorldData.scenes[upper].get("balconyRailProbes",[{"x":888,"y":180}]):
		if upper_nav.walkable(WorldData.point(probe)):issues.append("Balcony outer railing has no collision")
	for profile in Residents.people():
		if profile.home.bed.module!=profile.key+"-bed" or profile.home.scene!=upper:issues.append("Wrong personal bed: "+profile.key)
		if not ResourceLoader.exists(profile.home.bed.atlas):issues.append("Missing sleep atlas: "+profile.key)
		var music: Dictionary=profile.get("music",{})
		if not music.is_empty():
			var atlas: Texture2D=load(str(music.atlas))
			var pixels: Image=atlas.get_image()
			if pixels.get_pixel(0,0).a>0.01:issues.append("Music atlas lost transparency: "+profile.key)
			var cell:=Vector2i(pixels.get_width()/2,pixels.get_height()/2)
			var frames: Dictionary={}
			for index in 4:frames[hash(pixels.get_region(Rect2i(Vector2i(index%2,int(index/2))*cell,cell)).get_data())]=true
			if frames.size()!=4:issues.append("Music loop needs four distinct frames: "+profile.key)
			var musician:=Character.new()
			musician.setup(profile.key,profile.name,profile.key);add_child(musician)
			musician.placed=true;musician.scene_id=upper;musician.want_scene=upper
			musician.feet=WorldData.point(WorldData.scenes[upper].zones.upstairs_center)
			musician.target=musician.feet;musician._display=musician.feet;musician.position=musician.feet
			musician.action="music_"+str(music.activity)
			musician.walk_order({"id":"check-action-"+profile.key,"actor":profile.key,"scene":upper,"zone":music.zone})
			for step in 2400:
				musician.tick(.05)
				if musician.order_id=="":break
			if musician.stage.get("music_action","")!=music.activity:issues.append("Music interaction did not arrive in action: "+profile.key)
			musician._time=0;musician._update_sprite()
			var first_region: Rect2=musician._sprite.region_rect
			musician._time=.5;musician._update_sprite()
			if musician._sprite.region_rect==first_region:issues.append("Music animation frame did not advance: "+profile.key)
			musician.queue_free()
	# Native movement in a throwaway game save; no model or memory calls.
	var body:=Character.new()
	body.setup("xiaoai","小爱","xiaoai")
	add_child(body)
	body.placed=true;body.scene_id=lower;body.want_scene=lower;body.want_zone="shared_left"
	body.feet=lower_start;body.target=body.feet;body._display=body.feet;body.position=body.feet
	body.walk_order({"id":"check-ascent","actor":"xiaoai","scene":upper,"zone":"upstairs_center"})
	var saw_north:=false
	var saw_south:=false
	var saw_east:=false
	for frame in 2400:
		body.tick(.05)
		if body.scene_id==lower:
			if body.feet.x<130 and body.feet.y<376:saw_north=true
			if body.feet.x<130 and body.feet.y>465:saw_south=true
			if body.feet.x>210 and body.feet.y>480:saw_east=true
		if body.scene_id==upper and body.order_id=="":break
	if body.scene_id!=upper or not (saw_north and saw_south and saw_east):issues.append("Native ascent did not follow north -> south -> east")
	for zone in ["xiaoai_sing","selena_studio"]:
		if not WorldData.scenes[upper].zones.has(zone):continue
		body.walk_order({"id":"check-music-"+zone,"actor":"xiaoai","scene":upper,"zone":zone})
		for frame in 2400:
			body.tick(.05)
			if body.order_id=="":break
		if body.order_id!="" or body.feet.distance_to(WorldData.point(WorldData.scenes[upper].zones[zone]))>3:issues.append("Native music entrance/seat route failed: "+zone)
	body.walk_order({"id":"check-descent","actor":"xiaoai","scene":lower,"zone":"shared_left"})
	for frame in 2400:
		body.tick(.05)
		if body.scene_id==lower and body.order_id=="":break
	if body.scene_id!=lower or body.order_id!="":issues.append("Native descent failed")
	body.queue_free()
	if not issues.is_empty():
		for issue in issues:push_error(issue)
		get_tree().quit(1)
	else:
		print("PASS: native ascent/descent and both music entrances/seat routes; kitchen/dining/living and bedroom/balcony access; rail collisions and old-furniture storage valid.")
		get_tree().quit()
