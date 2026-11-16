class_name Dock
extends PanelContainer
## Three owner panels backed by the original AstrBot household.
const RECEIPT = preload("res://ui/home_gift_receipt.gd")
const NAMES = {"xiaoai":"小爱", "selena":"赛琳娜"}
var tab := "log"
var _who := "xiaoai"
var _bag_tab := "owned"
var _day := ""
var _journal_day := {}
var _data := {}
var _top: HBoxContainer
var _bar: HFlowContainer
var _section: VBoxContainer
var _scroll: ScrollContainer
var _list: VBoxContainer
var _collection: ContentList
var _font: SystemFont
var _clock := 0.0
var _next := 0.0
var _seq := 0
var _note := ""
var _pending := false
var _last_command := 0.0
var _signature := ""
var _textures := {}
var _received := {}
var _modal: CanvasLayer

func _ready() -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei","SimHei"])
	add_theme_font_override("font",_font)
	add_theme_stylebox_override("panel",_box(Hud.PAPER,Hud.WOOD_D,3,8))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",6)
	add_child(column)
	_top=HBoxContainer.new();column.add_child(_top)
	_bar=HFlowContainer.new();column.add_child(_bar)
	_bar.add_theme_constant_override("h_separation",5)
	_bar.add_theme_constant_override("v_separation",5)
	_section=VBoxContainer.new();column.add_child(_section)
	_scroll=ScrollContainer.new();column.add_child(_scroll)
	_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	_list=VBoxContainer.new();_scroll.add_child(_list)
	_list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation",8)
	_collection=ContentList.new();column.add_child(_collection)
	VadsLink.panel_arrived.connect(_on_panel)
	VadsLink.panel_done.connect(_on_done)
	VadsLink.connection_changed.connect(func(_connected):refresh())
	var args:=OS.get_cmdline_user_args()
	var arg:=args.find("--dock")
	if arg>=0 and arg+1<args.size() and args[arg+1] in ["log","bag","diary"]:tab=args[arg+1]
	rebuild()

func refresh() -> void:
	_next=0

func show_object(scene:String,_id:String) -> void:
	if scene=="qianxia-shop":tab="bag";_bag_tab="shop"
	else:tab="log"
	refresh();rebuild()

func _process(delta:float) -> void:
	_clock+=delta
	if _pending and _clock-_last_command>15:
		_pending=false;_note="结果还没回来，先刷新背包确认后再试";_next=0;rebuild()
	if is_visible_in_tree() and VadsLink.connected and _clock>=_next:
		_next=_clock+5;_seq+=1
		VadsLink.send({"type":"panel.get","id":_seq,"panel":"usage","day":_day})

func _on_panel(frame:Dictionary) -> void:
	if frame.get("panel")!="usage" or str(frame.get("day",""))!=_day:return
	if frame.get("ok")!=true or not frame.get("data") is Dictionary:
		_note=str(frame.get("error","小屋暂时没有回应"));rebuild();return
	var stable:Dictionary=frame.data.duplicate(true)
	for person in stable.get("residents",{}).values():
		person.get("features",{}).erase("server_time")
		person.get("features",{}).get("backpack",{}).get("affection",{}).erase("updated_at")
	var signature:=JSON.stringify(stable)
	if signature!=_signature:
		_signature=signature;_data=frame.data;rebuild()

func _on_done(frame:Dictionary) -> void:
	if not str(frame.get("action","")).begins_with("gift.") and frame.get("action")!="journal.request":return
	_pending=false
	var value:Dictionary=frame.get("data",{}) if frame.get("data") is Dictionary else {}
	_note=str(value.get("message","已经记下了")) if frame.get("ok")==true else str(frame.get("error","这次没完成，请稍后再试"))
	if frame.get("ok")==true and frame.get("action")=="gift.buy" and not value.get("replayed",false):
		var id:=str(value.get("id",""))
		if id!="" and not _received.has(id):
			_received[id]=true
			var receipt:=RECEIPT.new();add_child(receipt)
			receipt.play(str(value.get("character",frame.get("who",_who))),str(value.get("name","礼物")))
	refresh();rebuild()

func _command(action:String,fields:Dictionary={}) -> void:
	if _pending or not VadsLink.connected:return
	_pending=true;_last_command=_clock;_seq+=1
	var id:="home-"+str(int(Time.get_unix_time_from_system()*1000))+"-"+str(randi())
	var payload:={"type":"panel.do","id":_seq,"action":action,"who":_who,"request_id":id}
	payload.merge(fields,true);VadsLink.send(payload)
	_note="正在送到她手边" if action=="gift.buy" else "正在记录"
	rebuild()

func _features() -> Dictionary:
	var residents:Dictionary=_data.get("residents",{})
	return residents.get(_who,{}).get("features",{})

func _clear(node:Node) -> void:
	for child in node.get_children():node.remove_child(child);child.queue_free()

func _change(callable:Callable) -> void:
	callable.call();_note="";_scroll.scroll_vertical=0;rebuild();refresh()

func rebuild() -> void:
	if _top==null:return
	for node in [_top,_bar,_section,_list]:_clear(node)
	for pair in [["log","每日记录"],["bag","背包"],["diary","小屋日记"]]:
		var id:String=pair[0]
		_button(pair[1],tab==id,func():_change(func():tab=id),_top)
	for who in NAMES:
		var actor:String=who
		_button(NAMES[who]+(" · 姐姐" if who=="selena" else " · 妹妹"),_who==who,func():_change(func():_who=actor),_bar)
	_collection.visible=tab in ["log","bag"];_scroll.visible=tab=="diary"
	if _note!="":_section.add_child(_label(_note,12,Hud.WOOD))
	var data:=_features()
	if data.is_empty() or data.has("error"):
		var message:=str(data.get("error","正在接上她的小屋生活"))
		if _collection.visible:_collection.present("loading",[],1,"",message)
		else:_list.add_child(_label(message))
		return
	match tab:
		"log":_records(data)
		"bag":_bag(data)
		"diary":_diary(data)

func _date_controls(days:Array) -> void:
	var row:=HBoxContainer.new();_section.add_child(row)
	var options:=OptionButton.new();_style(options)
	options.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var choices:Array=days.duplicate()
	var today:=Time.get_datetime_string_from_unix_time(int(SharedFeed.now_ms()/1000)+28800).substr(0,10)
	if not today in choices:choices.push_front(today)
	for day in choices:options.add_item(str(day))
	options.select(maxi(0,choices.find(_day if _day!="" else today)))
	options.item_selected.connect(func(index):_change(func():_day=str(choices[index])))
	row.add_child(options)
	_button("今天",_day=="" or _day==today,func():_change(func():_day=""),row)

func _records(data:Dictionary) -> void:
	_date_controls(data.get("days",[]))
	var rows:=[]
	var facts:Array=data.get("records",[]).duplicate();facts.reverse()
	for fact in facts:
		rows.append({"id":str(fact.id),"title":str(fact.activity),"detail":str(fact.detail),
			"meta":str(fact.time).substr(11,5)+(" · "+str(fact.room) if fact.get("room","")!="" else ""),
			"category":{"activity":"日常","progress":"小进展","housemate":"姐妹闲聊","gift":"收到礼物","gift_use":"使用礼物","gift_store":"收好心意"}.get(str(fact.kind),"共同片段")})
	_collection.present("home-log:"+_who+":"+str(data.get("day","")),rows,1,
		str(data.get("day",""))+" · "+NAMES[_who]+"的 "+str(rows.size())+" 段小日常","这一天还没有留下小屋片段")

func _bag(data:Dictionary) -> void:
	var bar:=HBoxContainer.new();_section.add_child(bar)
	_button("她的收藏",_bag_tab=="owned",func():_change(func():_bag_tab="owned"),bar)
	_button("逛小卖部",_bag_tab=="shop",func():_change(func():_bag_tab="shop"),bar)
	var bag:Dictionary=data.get("backpack",{})
	var affection:Dictionary=bag.get("affection",{})
	var score:="好感度 "+str(affection.value)+" · "+str(affection.get("level","")) if affection.get("connected",false) else "好感度正在连接原系统"
	_section.add_child(_label(score,12,Color("b96f93") if _who=="xiaoai" else Color("716aac")))
	var rows:=[]
	if _bag_tab=="shop":
		for item in bag.get("catalog",[]):
			rows.append({"id":item.id,"title":item.name,"detail":item.description,"meta":str(item.price)+" 小屋零钱","category":item.category,"product":item,"icon":_icon(item)})
		_collection.present("home-shop:"+_who,rows,2,"小屋零钱 "+str(bag.get("wallet",{}).get("coins",0))+" · 挑一件送给"+NAMES[_who],"小卖部正在摆好货架",true,{"card":_shop_card,"min_height":185})
	else:
		for item in bag.get("items",[]):
			rows.append({"id":item.gift_id,"title":item.name,"detail":item.location,"meta":str(item.received_at).substr(5,11).replace("T"," "),"category":"留作纪念" if item.status=="used" else item.category,"product":item,"icon":_icon(item)})
		_collection.present("home-bag:"+_who,rows,2,NAMES[_who]+"收好的 "+str(bag.get("total",0))+" 份心意","还没有收到礼物，去小卖部挑一件吧",true,{"card":_gift_card,"min_height":190})

func _icon(item:Dictionary) -> Texture2D:
	var file:=str(item.get("atlas",""))
	if not _textures.has(file):_textures[file]=load(file)
	var texture:=AtlasTexture.new();texture.atlas=_textures[file]
	var region:Array=item.get("region",[0,0,1,1])
	texture.region=Rect2(region[0],region[1],region[2],region[3])
	return texture

func _card_base(row:Dictionary) -> Array:
	var panel:=PanelContainer.new()
	panel.add_theme_stylebox_override("panel",_box(Hud.PAPER_H,Hud.PAPER_D,1,6));panel.clip_contents=true
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",4);panel.add_child(box)
	var icon:=TextureRect.new();icon.texture=row.icon
	icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size=Vector2(88,88);box.add_child(icon)
	var label:=_label(str(row.title),13);label.max_lines_visible=2;box.add_child(label)
	return [panel,box]

func _shop_card(row:Dictionary) -> Control:
	var pair:=_card_base(row)
	var box:VBoxContainer=pair[1]
	box.add_child(_label(str(row.meta),12,Hud.WOOD))
	_button("选这件",false,func():_gift_dialog(row.product),box).disabled=_pending
	pair[0].tooltip_text=str(row.detail)
	return pair[0]

func _gift_card(row:Dictionary) -> Control:
	var pair:=_card_base(row)
	var box:VBoxContainer=pair[1]
	var item:Dictionary=row.product
	var place:=_label(str(item.location),11,Hud.INK2);place.max_lines_visible=2;box.add_child(place)
	var line:=_label(str(item.get("reaction","")) if item.get("reaction","")!="" else "心意已收好，等她留句话",11,Hud.WOOD)
	line.max_lines_visible=2;box.add_child(line)
	_button("翻看这份心意",false,func():_owned_dialog(item),box).disabled=_pending
	pair[0].tooltip_text=str(item.get("note",""))
	return pair[0]

func _open_modal(title:String) -> VBoxContainer:
	if is_instance_valid(_modal):_modal.queue_free()
	_modal=CanvasLayer.new();_modal.layer=80;add_child(_modal)
	var dim:=ColorRect.new();dim.color=Color(0,0,0,0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_modal.add_child(dim)
	var panel:=PanelContainer.new();panel.add_theme_stylebox_override("panel",_box(Hud.PAPER,Hud.WOOD_D,3,15))
	panel.position=(get_viewport_rect().size-Vector2(440,460))/2;panel.size=Vector2(440,460);_modal.add_child(panel)
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",10);panel.add_child(box)
	box.add_child(_label(title,19,Hud.WOOD))
	return box

func _gift_dialog(item:Dictionary) -> void:
	var recipient:=_who
	var box:=_open_modal("送给"+NAMES[recipient]+" · "+str(item.name))
	box.add_child(_label(str(item.description)))
	box.add_child(_label("价格 "+str(item.price)+" 小屋零钱",13,Hud.WOOD))
	box.add_child(_label("随礼留一句话",13))
	var note:=TextEdit.new();note.custom_minimum_size=Vector2(0,100)
	note.placeholder_text="想对她说的话，200字以内";note.add_theme_font_size_override("font_size",14)
	note.text_changed.connect(func():
		if note.text.length()>200:note.text=note.text.left(200))
	box.add_child(note)
	_button("买下并送给她",false,func():
		var message:=note.text
		_modal.queue_free();_who=recipient
		_command("gift.buy",{"item":item.id,"note":message}),box)
	_button("再看看",false,func():_modal.queue_free(),box)

func _owned_dialog(item:Dictionary) -> void:
	var recipient:=_who
	var box:=_open_modal(str(item.name)+" · "+str(item.received_at).substr(0,10))
	if item.get("note","")!="":box.add_child(_label("你留下的话："+str(item.note)))
	if item.get("reaction","")!="":box.add_child(_label(NAMES[recipient]+"："+str(item.reaction)))
	box.add_child(_label("收在："+str(item.location)+" · 用过 "+str(item.use_count)+" 次",12,Hud.INK2))
	for pair in [["use","拿来用一会儿"],["carry","随身带着"],["store","收回合适的位置"],["treasure","留作纪念"]]:
		var action:String=pair[0]
		var button:=_button(pair[1],false,func():
			_modal.queue_free();_who=recipient
			_command("gift.act",{"gift_id":item.gift_id,"operation":action}),box)
		button.disabled=item.status=="used" and action!="treasure"
	_button("合上",false,func():_modal.queue_free(),box)

func _diary(data:Dictionary) -> void:
	_button("整理今天的小屋随记",false,func():_command("journal.request"),_section).disabled=_pending
	_section.add_child(_label("这里只记小屋生活，与空间日记分别保存",12,Hud.INK2))
	var rows:Array=data.get("journals",[])
	if rows.is_empty():
		_list.add_child(_label("今天的片段正在慢慢积累，也可以先整理一页随记",14,Hud.INK2));return
	var selected:=str(_journal_day.get(_who,rows[0].day))
	var options:=OptionButton.new();_style(options)
	for page in rows:options.add_item(str(page.day)+(" · 今天的随记" if page.status=="draft" else ""))
	var index:=0
	for i in rows.size():
		if rows[i].day==selected:index=i
	options.select(index)
	options.item_selected.connect(func(i):_change(func():_journal_day[_who]=rows[i].day));_section.add_child(options)
	var page:Dictionary=rows[index]
	if page.status in ["pending","running"]:_list.add_child(_label("她正在整理这一天的小片段",13,Hud.WOOD))
	if str(page.content)!="":_list.add_child(_label(str(page.content),15))
	elif page.status=="failed":_list.add_child(_label("这一页还没有写完，可以稍后再整理",13,Hud.INK2))
	_button("重新整理这一页",false,func():_command("journal.request",{"day":page.day}),_list).disabled=_pending

func _label(value:String,font_size:=13,color:=Hud.INK) -> Label:
	var label:=Label.new();label.text=value
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size",font_size);label.add_theme_color_override("font_color",color)
	return label

func _button(value:String,selected:bool,action:Callable,parent:Control) -> Button:
	var button:=Button.new();button.text=value;button.focus_mode=Control.FOCUS_NONE
	button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND;_style(button)
	if selected:button.add_theme_stylebox_override("normal",_box(Hud.PAPER_D,Hud.WOOD_D,2,4))
	button.pressed.connect(action);parent.add_child(button)
	return button

func _style(control:Control) -> void:
	control.add_theme_font_override("font",_font);control.add_theme_font_size_override("font_size",13)
	for state in ["normal","hover","pressed","focus"]:control.add_theme_stylebox_override(state,_box(Hud.PAPER_H,Hud.WOOD_L,1,4))
	for state in ["font_color","font_hover_color","font_pressed_color"]:control.add_theme_color_override(state,Hud.INK)

func _box(color:Color,border:Color,width:int,padding:int) -> StyleBoxFlat:
	var box:=StyleBoxFlat.new();box.bg_color=color;box.border_color=border
	box.set_border_width_all(width);box.set_content_margin_all(padding)
	return box
