extends CanvasLayer
## The completed four-frame reception animation, only after a committed gift.
var _sprite: Sprite2D
var _elapsed := 0.0
var _meta := {}
var _row := 0
var _base := Vector2(185,240)

func play(actor:String,gift_name:String) -> void:
	layer=90
	_meta=JSON.parse_string(FileAccess.get_file_as_string("res://assets/gift-happy-v20.json"))
	_row=_meta.actors.find(actor)
	if _row<0:queue_free();return
	var dim:=ColorRect.new();dim.color=Color(0,0,0,0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(dim)
	var panel:=PanelContainer.new()
	panel.position=(get_viewport().get_visible_rect().size-Vector2(400,410))/2;panel.size=Vector2(400,410)
	var style:=StyleBoxFlat.new();style.bg_color=Hud.PAPER
	style.border_color=Color("c78ba6") if actor=="xiaoai" else Color("8b83bc")
	style.set_border_width_all(3);style.set_content_margin_all(15)
	panel.add_theme_stylebox_override("panel",style);add_child(panel)
	var box:=VBoxContainer.new();panel.add_child(box)
	var title:=Label.new();title.text=("小爱" if actor=="xiaoai" else "赛琳娜")+"收到了 "+gift_name
	title.add_theme_font_size_override("font_size",19);title.add_theme_color_override("font_color",Hud.INK)
	title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(title)
	var stage:=Control.new();stage.custom_minimum_size=Vector2(370,270);box.add_child(stage)
	_sprite=Sprite2D.new();_sprite.texture=load(str(_meta.texture));_sprite.region_enabled=true
	_sprite.centered=false;_sprite.scale=Vector2.ONE*0.52;stage.add_child(_sprite)
	var note:=Label.new();note.text="礼物和你留下的话，已经收进她的背包"
	note.add_theme_color_override("font_color",Hud.WOOD);note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(note)
	var close:=Button.new();close.text="回到小屋";close.pressed.connect(queue_free);box.add_child(close)
	_process(0)

func _process(delta:float) -> void:
	if _sprite==null:return
	_elapsed+=delta
	var frame:=3
	var start:=0.0
	for i in 4:
		var duration:=float(_meta.duration_seconds[i])
		if _elapsed<start+duration:frame=i;break
		start+=duration
	var cell:=Vector2(_sprite.texture.get_width()/4.0,_sprite.texture.get_height()/2.0)
	_sprite.region_rect=Rect2(Vector2(frame,_row)*cell,cell)
	_sprite.offset=-Vector2(float(_meta.anchor_x[_row][frame]),float(_meta.baseline[_row]))
	var hop:=sin(clampf((_elapsed-1.05)/0.8,0,1)*PI)*float(_meta.jump_height_world)*2.5 if frame==2 else 0.0
	_sprite.position=_base-Vector2(0,hop)
