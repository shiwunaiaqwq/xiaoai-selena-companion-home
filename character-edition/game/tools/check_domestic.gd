extends Node
func _ready() -> void:call_deferred("check")
func check() -> void:
	var issues:Array[String]=[]
	var world:Node=get_parent()
	var home:String="xiaojingyu-home"
	var bath:String="shared-home-bathroom"
	if WorldData.scene_path(home,bath)!=[home,bath] or WorldData.scene_path(bath,home)!=[bath,home]:issues.append("Bathroom passage is not reciprocal")
	for id:String in [home,bath,"shared-home-upstairs"]:
		var scene:Dictionary=WorldData.scenes[id]
		var nav:RoomNav=WorldData.nav(id)
		var start:Vector2=WorldData.point(scene.entries.door if scene.entries.has("door") else scene.entries.stairs)
		var names:Array=["bathroom_door","dining_xiaoai","dining_selena","cook_stove","kitchen_wash"] if id==home else ["bath_door","bath_sink","bath_shower","bath_soak","bath_toilet","bath_towels"] if id==bath else ["selena_diary","xiaoai_balcony","selena_balcony","xiaoai_wardrobe","selena_wardrobe","xiaoai_mirror","selena_mirror"]
		for name:String in names:
			var target:Vector2=WorldData.point(scene.zones[name])
			if not nav.walkable(target) or nav.route(start,target).is_empty():issues.append("Unreachable use point: "+id+"/"+name)
	for row:Array in [["sofa_phone","both"],["sofa_phone","xiaoai"],["sofa_phone","selena"],["eat_phone","both"],["eat_phone","xiaoai"],["eat_phone","selena"],["desk_read","selena"],["old_letters","selena"],["sofa_rest","xiaoai"],["sofa_read","xiaoai"],["sofa_music","xiaoai"],["eat","both"],["eat","xiaoai"],["eat","selena"],["cook","xiaoai"],["cook","selena"],["diary","selena"],["shower","xiaoai"],["shower","selena"],["soak","xiaoai"],["soak","selena"],["wash_food","xiaoai"],["wash_food","selena"],["wash_dishes","xiaoai"],["wash_dishes","selena"],["view","both"],["wardrobe","xiaoai"],["wardrobe","selena"],["mirror","xiaoai"],["mirror","selena"],["sofa_rest","selena"],["sofa_read","selena"],["sofa_music","selena"],["sofa_album","xiaoai"],["sofa_pair","both"]]:
		world._art_preview.domestic_preview(row[0],row[1])
		await get_tree().process_frame
		await get_tree().process_frame
		for c:Node in world.characters:
			if row[1]!="both" and c.key!=row[1]:continue
			if (not c.stage.has("sofa_action")) if str(row[0]).begins_with("sofa_") else c.stage.get("home_activity","")!=row[0]:issues.append("Wrong visual state: "+str(row))
			if c._sprite.visible:issues.append("Duplicate standing body: "+str(row))
	for kind:String in load("res://entities/life_activities_v18.gd").KINDS:
		for actor:String in ["xiaoai","selena"]:
			world._art_preview.domestic_preview(kind,actor)
			await get_tree().process_frame
			await get_tree().process_frame
			for c:Node in world.characters:
				if c.key!=actor:continue
				if c.stage.get("life_activity","")!=kind:issues.append("Missing life pose: "+actor+"/"+kind)
				if c._sprite.visible:issues.append("Duplicate life body: "+actor+"/"+kind)
			var shown:bool=false
			for room:Node in world.rooms.values():
				if not room is Room or room.scene_id!=world.characters.filter(func(c):return c.key==actor)[0].scene_id:continue
				for presentation:Node in room.get_children():
					if presentation.get_script()!=load("res://entities/life_activities_v18.gd"):continue
					if presentation.poses.has(actor):shown=presentation.poses[actor].visible and presentation.poses[actor].texture!=null
			if not shown:issues.append("No rendered life texture: "+actor+"/"+kind)
			var dest:Array=load("res://entities/life_activities_v18.gd").destination(kind,actor)
			if not WorldData.nav(dest[0]).walkable(WorldData.point(WorldData.scenes[dest[0]].zones[dest[1]])):issues.append("Blocked life approach: "+str(dest))
	world._art_preview.preview("")
	if BedroomPreview.mode!="":issues.append("Preview did not restore live mode")
	if issues.is_empty():print("PASS: reciprocal bathroom doors, all domestic approach routes, all individual/shared action states, balcony and cabinet/mirror routes, no duplicate bodies, and restoration of live mode.")
	else:
		for issue:String in issues:push_error(issue)
	get_tree().quit(0 if issues.is_empty() else 1)

