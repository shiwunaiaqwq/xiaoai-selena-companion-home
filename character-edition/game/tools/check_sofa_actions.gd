extends Node

func _ready() -> void:
	call_deferred("check")

func check() -> void:
	var issues: Array[String]=[]
	var room:=Room.new()
	room.setup("xiaojingyu-home");add_child(room);room.build();room.visible=true
	var actors: Dictionary={}
	for key in ["xiaoai","selena"]:
		var profile: Dictionary=Residents.person(key)
		var spec: Dictionary=profile.sofa
		var c:=Character.new()
		c.setup(key,profile.name,key);room.add_child(c)
		c.placed=true;c.scene_id="xiaojingyu-home";c.want_scene=c.scene_id
		c.feet=WorldData.point(WorldData.scenes[c.scene_id].zones.shared_left if key=="xiaoai" else WorldData.scenes[c.scene_id].zones.shared_right)
		c.target=c.feet;c._display=c.feet;c.position=c.feet
		c.action=str(spec.actions[0])
		c.walk_order({"id":"check-sofa-"+key,"actor":key,"scene":spec.scene,"zone":spec.zone})
		for step in 2400:
			c.tick(.05)
			if c.order_id=="":break
		if c.order_id!="" or not c.stage.has("sofa_action"):issues.append("Seat route/action failed: "+key)
		c._update_sprite()
		if c._sprite.visible:issues.append("Duplicate resident sprite still visible: "+key)
		if c.activity_scale()!=1.0:issues.append("Seated composite received the ordinary activity scale: "+key)
		actors[key]=c
	await get_tree().process_frame
	var sofa: Node=room.furniture["living-sofa"]
	if sofa.refresh()!="both":issues.append("Both residents did not select the shared composite")
	actors.xiaoai.action="";actors.xiaoai.tick(.05)
	if sofa.refresh()!="selena":issues.append("Selena-only state failed")
	actors.selena.action="";actors.selena.tick(.05)
	if sofa.refresh()!="empty":issues.append("Empty sofa restore failed")
	for key in actors:
		var c: Character=actors[key]
		c._process(0)
		var expected: float=float(WorldData.actors[key].walk.scale)*1.4
		if not c._sprite.visible or absf(c._sprite.scale.x-expected)>.0001:issues.append("Ordinary activity scale/standing restore failed: "+key)
	actors.xiaoai.action="sofa_game";actors.xiaoai.tick(.05)
	if sofa.refresh()!="xiaoai":issues.append("Xiaoai-only state failed")
	for state in sofa.data().states:
		var spec: Dictionary=sofa.data().states[state]
		var texture: Texture2D=load(str(spec.atlas))
		var pixels:=texture.get_image()
		if pixels.get_pixel(0,0).a>.01:issues.append("Atlas transparency lost: "+state)
		var cell:=Vector2i(pixels.get_width()/2,pixels.get_height()/2)
		var distinct: Dictionary={}
		for index in 4:
			distinct[hash(pixels.get_region(Rect2i(Vector2i(index%2,int(index/2))*cell,cell)).get_data())]=true
			if spec.registration[index].size()!=3:issues.append("Missing couch registration: "+state)
		if state!="empty" and distinct.size()!=4:issues.append("Four distinct action frames required: "+state)
	sofa._clock=0;sofa.refresh()
	var first: Rect2=sofa._sprite.region_rect
	var fixed_front: Rect2=sofa._front.region_rect
	var fixed_position: Vector2=sofa._front.position
	sofa._clock=.5;sofa.refresh()
	if sofa._sprite.region_rect==first:issues.append("Composite animation did not advance")
	if sofa._front.region_rect!=fixed_front or sofa._front.position!=fixed_position:issues.append("Sofa body moved during action animation")
	if issues.is_empty():
		print("PASS: both native sofa approach routes, shared/solo/empty occupancy states, hidden duplicate bodies, four-frame transparent atlases, registration metadata and animation advancement.")
		get_tree().quit()
	else:
		for issue in issues:push_error(issue)
		get_tree().quit(1)
