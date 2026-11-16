extends CanvasLayer
## Follow either of two independently skinned residents in one shared world.

const NAMES := {"xiaoai":"小爱", "selena":"赛琳娜"}
var selected := "xiaoai"
var buttons := {}

func _ready() -> void:
	layer = 40
	var args := OS.get_cmdline_user_args()
	var index := args.find("--skin")
	if index >= 0 and index+1 < args.size() and NAMES.has(args[index+1]):
		selected = args[index+1]
	var panel := PanelContainer.new()
	panel.name = "CompanionSelector"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left = -298
	panel.offset_right = -18
	panel.offset_top = -112
	panel.offset_bottom = -54
	var style := StyleBoxFlat.new()
	style.bg_color = Color("202b4dee")
	style.set_corner_radius_all(12)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel",style)
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	panel.add_child(row)
	for skin in NAMES:
		var button := Button.new()
		button.text = "跟随" + NAMES[skin]
		button.custom_minimum_size = Vector2(128,42)
		button.add_theme_font_size_override("font_size",21)
		button.toggle_mode = true
		button.pressed.connect(select.bind(skin))
		row.add_child(button)
		buttons[skin] = button
	call_deferred("bind_body")

func bind_body() -> void:
	var bodies := get_tree().get_nodes_in_group("world_residents")
	if bodies.size() != 2:
		push_error("Shared preview requires two resident bodies")
		return
	get_window().title = "小屋世界 · 小爱与赛琳娜"
	select(selected)
	var args:=OS.get_cmdline_user_args()
	var scene_index:=args.find("--scene")
	if scene_index>=0 and scene_index+1<args.size() and WorldData.scenes.has(args[scene_index+1]):
		get_parent()._on_scene_picked(str(args[scene_index+1]))

func select(skin: String) -> void:
	if not NAMES.has(skin):
		return
	selected = skin
	var world: Control = get_parent()
	for index in world.characters.size():
		if world.characters[index].key == skin:
			if world.follow != index:
				world._on_follow_picked(index)
			break
	for key in buttons:
		buttons[key].set_pressed_no_signal(key == skin)
		buttons[key].modulate = Color("ffc1df") if key == "xiaoai" else Color("cbc5ff")
