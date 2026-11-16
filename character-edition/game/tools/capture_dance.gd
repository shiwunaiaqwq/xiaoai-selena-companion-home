extends Node
func _ready() -> void:call_deferred("capture")
func capture() -> void:
	await get_tree().create_timer(.6).timeout
	get_parent()._on_scene_picked("qianxia-park")
	get_parent().follow=-1
	get_parent()._layout()
	var args:=OS.get_cmdline_user_args()
	var folder:=str(args[args.find("--capture-dance")+1])
	DirAccess.make_dir_recursive_absolute(folder)
	var dancers: Array=get_tree().get_nodes_in_group("ambient_npcs").filter(func(n):return n.special)
	for n in dancers:n.set_process(false);n.clock=0;n.pause=999;n.route.clear()
	for i in 32:
		for n in dancers:n.advance(.02)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(folder.path_join("%03d.png"%i))
	get_tree().quit()
