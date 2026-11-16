extends Node
var host:Node
var output:String
func _ready() -> void:call_deferred("run")
func run() -> void:
	host=get_parent();host.follow=-1
	var args:Array=OS.get_cmdline_user_args();output=args[args.find("--visual-audit")+1]
	DirAccess.make_dir_recursive_absolute(output)
	var kinds:Array=["sofa_phone","eat_phone","read","write","listen","select","washface","prep","tea","water","tidy","bench","onsen_rest","chess","arcade","outside_eat","sofa_rest","sofa_read","sofa_music","sofa_album","eat","cook","wash_food","wash_dishes","view","wardrobe","mirror","diary","desk_read","old_letters","shower","soak","music","sleep","phone"]
	if "--phone-audit" in args:kinds=["sofa_phone","eat_phone"]
	for kind:String in kinds:
		for light:int in 2:
			var sheet:=Image.create(1950,1274,false,Image.FORMAT_RGB8)
			for actor_index:int in 2:
				var actor:String="xiaoai" if actor_index==0 else "selena"
				if actor=="xiaoai" and kind in ["diary","desk_read","old_letters"]:continue
				if actor=="selena" and kind=="sofa_album":continue
				BedroomPreview.audit_light=light
				if kind in ["music","sleep","phone"]:host._art_preview.preview(kind)
				else:host._art_preview.domestic_preview(kind,actor)
				await get_tree().process_frame
				var c:Node=host.characters[actor_index]
				if kind in ["music","sleep","phone"]:host._on_scene_picked(c.scene_id)
				var focus:Vector2=c.feet-Vector2(0,40)
				if kind.begins_with("sofa_"):focus=Vector2(450,443)
				if kind in ["diary","desk_read","old_letters"]:focus=Vector2(560,240)
				if kind=="washface":focus=Vector2(184,200)
				if kind=="chess":focus=Vector2(880,180)
				if kind=="outside_eat":focus=Vector2(480,425)
				if kind=="arcade":focus=Vector2(304,280)
				if kind=="shower":focus=Vector2(348,170)
				if kind=="soak":focus=Vector2(520,190)
				host.follow=-1;host._room_camera.zoom=2.5;host._room_camera.center=focus;host._room_camera._apply()
				for phase:int in 2:
					for node:Node in host.rooms[c.scene_id].get_children():
						if node.get_script() in [load("res://entities/life_activities_v18.gd"),load("res://entities/home_activities.gd"),load("res://entities/sofa_actions.gd")]:
							node.set_process(false)
							if node is SofaActions:node._clock=float(phase)*(4.0 if kind=="sofa_phone" else 1.6);node.refresh()
							else:node.clock=float(phase)*1.6;node._process(0);node.queue_redraw()
					await get_tree().physics_frame
					await get_tree().physics_frame
					await get_tree().process_frame
					await RenderingServer.frame_post_draw
					var shot:Image=get_viewport().get_texture().get_image()
					var crop:Image=shot.get_region(Rect2i(23,43,975,637))
					crop.convert(Image.FORMAT_RGB8)
					sheet.blit_rect(crop,Rect2i(0,0,975,637),Vector2i(phase*975,actor_index*637))
					for node:Node in host.rooms[c.scene_id].get_children():
						if node.get_script() in [load("res://entities/life_activities_v18.gd"),load("res://entities/home_activities.gd"),load("res://entities/sofa_actions.gd")]:node.set_process(true)
			sheet.save_png(output+"/"+kind+("-day" if light==0 else "-night")+".png")
		print("AUDITED "+kind)
	for kind:String in (["sofa_phone","eat_phone"] if "--phone-audit" in args else ["sofa_phone","eat_phone","sofa_pair","eat","chess","outside_eat","cook","wash_food","washface","prep","tea","bench","arcade"]):
		BedroomPreview.audit_light=0;host._art_preview.domestic_preview(kind,"both")
		host.follow=-1;host._room_camera.zoom=1.7
		var c:Node=host.characters[0];host._room_camera.center=c.feet-Vector2(0,40)
		if kind.begins_with("sofa_"):host._room_camera.center=Vector2(450,440)
		if kind=="chess":host._room_camera.center=Vector2(880,190)
		if kind=="outside_eat":host._room_camera.center=Vector2(480,425)
		if kind=="washface":host._room_camera.center=Vector2(280,250)
		if kind=="arcade":host._room_camera.center=Vector2(330,300)
		host._room_camera._apply()
		await get_tree().physics_frame;await get_tree().physics_frame;await get_tree().process_frame;await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output+"/pair-"+kind+".png")
	for kind:String in ["eat_phone","sofa_phone"]:
		host._art_preview.domestic_preview(kind,"both")
		host.characters[1].action="home_eat" if kind=="eat_phone" else "sofa_read"
		host.characters[1].stage=host.characters[1]._stage_now()
		host._room_camera.zoom=2.5;host._room_camera.center=Vector2(680,145) if kind=="eat_phone" else Vector2(450,443);host._room_camera._apply()
		await get_tree().physics_frame;await get_tree().physics_frame;await get_tree().process_frame;await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output+"/mixed-"+kind+".png")
	BedroomPreview.audit_light=-1;host._art_preview.preview("");get_tree().quit()
