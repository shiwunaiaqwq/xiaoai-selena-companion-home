class_name BedroomPreview
extends CanvasLayer
## Explicit art-pose preview; never submits owner messages or writes the AstrBot database.
static var mode := ""
static var audit_light:int=-1
var world: Control
var saved := {}

static func night(fallback: bool) -> bool:
	if audit_light>=0:return audit_light==1
	if mode=="sofa":return true if "--sofa-night" in OS.get_cmdline_user_args() else fallback
	if mode=="music" and "--music-night" in OS.get_cmdline_user_args():return true
	return mode in ["sleep","phone","night"] or (not mode in ["day","music"] and fallback)

func _ready() -> void:
	layer=41
	world=get_parent()
	var panel:=HBoxContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left=18;panel.offset_top=-66;panel.offset_bottom=-18
	panel.add_theme_constant_override("separation",8)
	add_child(panel)
	for item in [["睡姿预览","sleep"],["床上手机","phone"],["恢复站立",""],["唱歌／弹琴","music"]]:
		var button:=Button.new()
		button.text=item[0];button.custom_minimum_size=Vector2(110,40)
		button.add_theme_font_size_override("font_size",19)
		button.pressed.connect(preview.bind(item[1]))
		panel.add_child(button)
	for item in [["日间布局",true],["夜间布局",false]]:
		var button:=Button.new()
		button.text=item[0];button.custom_minimum_size=Vector2(110,40)
		button.add_theme_font_size_override("font_size",19)
		button.pressed.connect(layout_preview.bind(item[1]))
		panel.add_child(button)
	var first:=Button.new()
	first.text="一楼布局";first.custom_minimum_size=Vector2(110,40)
	first.add_theme_font_size_override("font_size",19)
	first.pressed.connect(first_floor_preview);panel.add_child(first)
	var sofa_menu:=MenuButton.new()
	sofa_menu.text="沙发动作";sofa_menu.custom_minimum_size=Vector2(110,40)
	sofa_menu.add_theme_font_size_override("font_size",19)
	panel.add_child(sofa_menu)
	var popup:=sofa_menu.get_popup()
	for title in ["两人一起：游戏／喝茶","小爱单独打游戏","赛琳娜单独喝茶","恢复站立"]:popup.add_item(title)
	popup.id_pressed.connect(func(id:int):
		if id==3:preview("")
		elif id>=4:sofa_variant(["sofa_rest","sofa_read","sofa_music","sofa_album","sofa_pair"][id-4],"both" if id==8 else "xiaoai" if id==7 else "selena")
		else:sofa_walk(["both","xiaoai","selena"][id]))
	var menu:=MenuButton.new()
	menu.text="生活动作";menu.custom_minimum_size=Vector2(110,40);menu.add_theme_font_size_override("font_size",19);panel.add_child(menu)
	var options: Array=[["赛琳娜书桌阅读","desk_read","selena"],["赛琳娜翻旧信","old_letters","selena"],["两人吃饭","eat","both"],["小爱吃饭","eat","xiaoai"],["赛琳娜吃饭","eat","selena"],["小爱做饭","cook","xiaoai"],["赛琳娜做饭","cook","selena"],["赛琳娜写日记","diary","selena"],["小爱淋浴","shower","xiaoai"],["赛琳娜淋浴","shower","selena"],["小爱泡澡","soak","xiaoai"],["赛琳娜泡澡","soak","selena"],["结束预览，恢复实时","","both"]]
	options.append_array([["赛琳娜沙发休息","sofa_rest","selena"],["赛琳娜沙发看书","sofa_read","selena"],["赛琳娜沙发听音乐","sofa_music","selena"],["小爱沙发看相册","sofa_album","xiaoai"],["两人看相册／看书","sofa_pair","both"],["两人阳台看风景","view","both"],["小爱整理衣柜","wardrobe","xiaoai"],["赛琳娜整理衣柜","wardrobe","selena"],["小爱照镜子","mirror","xiaoai"],["赛琳娜照镜子","mirror","selena"],["小爱洗菜","wash_food","xiaoai"],["赛琳娜洗菜","wash_food","selena"],["小爱洗碗","wash_dishes","xiaoai"],["赛琳娜洗碗","wash_dishes","selena"]])
	for item:Array in [["沙发休息","sofa_rest"],["沙发看书","sofa_read"],["沙发听音乐","sofa_music"]]:options.append(["小爱"+item[0],item[1],"xiaoai"])
	for item:Array in [["洗漱","washface"],["准备食材","prep"],["泡茶","tea"],["照料盆栽","water"],["收拾房间","tidy"],["阅读","read"],["整理歌词／乐谱","write"],["听练习回放","listen"],["挑选杂志","select"],["公园长椅歇脚","bench"],["汤屋休息","onsen_rest"],["玩机台","arcade"],["棋桌游戏","chess"],["外出吃饭","outside_eat"]]:
		for actor:String in ["xiaoai","selena"]:options.append([("小爱" if actor=="xiaoai" else "赛琳娜")+item[0],item[1],actor])
	for item:Array in [["沙发看手机","sofa_phone"],["吃饭看手机","eat_phone"]]:
		for actor:String in ["xiaoai","selena","both"]:options.append([("两人" if actor=="both" else "小爱" if actor=="xiaoai" else "赛琳娜")+item[0],item[1],actor])
	for option in options:menu.get_popup().add_item(option[0])
	menu.get_popup().id_pressed.connect(func(id:int):domestic_walk(options[id][1],options[id][2]))
	for title:String in ["赛琳娜休息","赛琳娜看书","赛琳娜听音乐","小爱看相册","两人看相册／看书"]:popup.add_item(title)
	var args:=OS.get_cmdline_user_args()
	var domestic_index:=args.find("--home-action")
	if domestic_index>=0 and domestic_index+2<args.size():call_deferred("domestic_preview",args[domestic_index+1],args[domestic_index+2])
	var sofa_index:=args.find("--sofa-preview")
	if sofa_index>=0 and sofa_index+1<args.size():
		call_deferred("sofa_preview",str(args[sofa_index+1]))
		if "--sofa-closeup" in args:call_deferred("focus_sofa")
	elif "--pose-preview" in OS.get_cmdline_user_args():
		call_deferred("preview","sleep")
	elif "--music-preview" in OS.get_cmdline_user_args():
		call_deferred("preview","music")
		if "--music-closeup" in OS.get_cmdline_user_args():call_deferred("focus_music")
	elif "--layout-preview" in OS.get_cmdline_user_args():
		call_deferred("layout_preview",true)
	elif "--first-floor-preview" in OS.get_cmdline_user_args():
		call_deferred("first_floor_preview")

func first_floor_preview() -> void:
	layout_preview(true)
	world._on_scene_picked("xiaojingyu-home")

func focus_sofa() -> void:
	WorldData.scenes["xiaojingyu-home"].camera={"enabled":true,"zoom":1.0,"focus":[480,320]}
	world._layout()
	world._room_camera.zoom=1.4
	world._room_camera.center=Vector2(450,430)
	world._room_camera._apply()

func sofa_walk(value: String) -> void:
	preview("")
	mode="sofa"
	for c: Character in world.characters:
		if value!="both" and value!=c.key:continue
		var spec: Dictionary=Residents.person(c.key).get("sofa",{})
		if spec.is_empty():continue
		save_before(c)
		c.sleeping=false;c.action=str(spec.actions[0])
		c.label="沙发上打游戏" if c.key=="xiaoai" else "沙发上喝茶"
		c.walk_order({"id":"art-sofa-"+c.key,"actor":c.key,"scene":spec.scene,"zone":spec.zone})
	world._on_scene_picked("xiaojingyu-home")

func sofa_preview(value: String) -> void:
	preview("")
	mode="sofa"
	for c: Character in world.characters:
		if value!="both" and value!=c.key:continue
		var spec: Dictionary=Residents.person(c.key).get("sofa",{})
		if spec.is_empty():continue
		save_before(c)
		c.scene_id=str(spec.scene);c.want_scene=c.scene_id;c.want_zone=str(spec.zone)
		c.feet=WorldData.point(WorldData.scenes[c.scene_id].zones[c.want_zone])
		c.target=c.feet;c._display=c.feet;c.position=c.feet;c.route.clear();c.order_id="";c.next_scene="";c.placed=true
		c.sleeping=false;c.action=str(spec.actions[0]);c.state=Character.State.IDLE
		c.label="沙发上打游戏" if c.key=="xiaoai" else "沙发上喝茶"
		c.stage=c._stage_now();c.room_changed.emit(c)
	world._on_scene_picked("xiaojingyu-home")

func focus_music() -> void:
	world._room_camera.zoom=1.5
	world._room_camera.center=Vector2(570,550)
	world._room_camera._apply()

func layout_preview(daytime: bool) -> void:
	preview("")
	mode="day" if daytime else "night"
	world._on_scene_picked("shared-home-upstairs")

func save_before(c: Character) -> void:
	if saved.has(c.key):return
	var initial: Array=Residents.person(c.key).start
	var previous_scene: String=c.scene_id if c.placed else str(initial[0])
	var previous_zone: String=c.want_zone if c.placed else str(initial[1])
	var previous_feet: Vector2=c.feet if c.placed else WorldData.point(WorldData.scenes[previous_scene].zones[previous_zone])
	saved[c.key]={"scene":previous_scene,"zone":previous_zone,"feet":previous_feet,"sleeping":c.sleeping,"action":c.action,"label":c.label,"order":c.order_id,"next":c.next_scene,"route":c.route.duplicate(),"target":c.target,"state":c.state}

func interact(key: String) -> void:
	for c: Character in world.characters:
		if c.key!=key:continue
		var spec: Dictionary=Residents.person(key).get("music",{})
		if spec.is_empty():return
		save_before(c)
		mode="music";c.sleeping=false;c.action="music_"+str(spec.activity)
		c.label="练歌动作预览" if spec.activity=="sing" else "弹琴动作预览"
		c.walk_order({"id":"art-music-"+key,"actor":key,"scene":spec.scene,"zone":spec.zone})
		world._on_scene_picked(str(spec.scene))

func preview(value: String) -> void:
	mode=value
	for c: Character in world.characters:
		if value!="":
			save_before(c)
			c.scene_id="shared-home-upstairs";c.want_scene=c.scene_id
			c.want_zone=("xiaoai_sing" if c.key=="xiaoai" else "selena_studio") if value=="music" else c._home.bed.zone
			c.feet=WorldData.point(WorldData.scenes[c.scene_id].zones[c.want_zone])
			c.target=c.feet;c._display=c.feet;c.position=c.feet;c.route.clear();c.order_id="";c.next_scene="";c.placed=true
			c.sleeping=value=="sleep";c.action=("music_sing" if c.key=="xiaoai" else "music_piano") if value=="music" else ("bed_phone" if value=="phone" else "")
			c.label=("练歌动作预览" if c.key=="xiaoai" else "弹琴动作预览") if value=="music" else ("睡姿预览" if value=="sleep" else "床上手机预览")
			c.state=Character.State.ASLEEP if c.sleeping else Character.State.IDLE
			c.stage=c._stage_now();c.room_changed.emit(c)
		elif saved.has(c.key):
			var before: Dictionary=saved[c.key]
			c.scene_id=before.scene;c.want_scene=before.scene;c.want_zone=before.zone
			c.feet=before.feet;c.target=c.feet;c._display=c.feet;c.position=c.feet;c.route.clear()
			c.order_id=before.order;c.next_scene=before.next;c.route=before.route;c.target=before.target
			c.sleeping=before.sleeping;c.action=before.action;c.state=before.state
			c.label=before.label
			c.stage={};c.room_changed.emit(c)
	if value=="":saved.clear()
	world._on_scene_picked("shared-home-upstairs" if value!="" else "xiaojingyu-home")

func domestic_preview(kind:String,actor:String="both") -> void:
	if kind in load("res://entities/life_activities_v18.gd").KINDS:life_preview(kind,actor,true);return
	if kind.begins_with("sofa_"):sofa_variant(kind,actor,true);return
	preview("")
	if kind=="":return
	mode="domestic"
	var id:="shared-home-upstairs" if kind in ["diary","desk_read","old_letters","view","wardrobe","mirror"] else "shared-home-bathroom" if kind in ["shower","soak"] else "xiaojingyu-home"
	for c:Character in world.characters:
		if actor!="both" and actor!=c.key:continue
		save_before(c)
		var zone:=c.key+"_balcony" if kind=="view" else c.key+"_"+kind if kind in ["wardrobe","mirror"] else "kitchen_wash" if kind in ["wash_food","wash_dishes"] else "selena_diary" if kind in ["diary","desk_read","old_letters"] else "bath_"+kind if kind in ["shower","soak"] else "cook_stove" if kind=="cook" else "dining_"+c.key
		c.scene_id=id;c.want_scene=id;c.want_zone=zone;c.feet=WorldData.point(WorldData.scenes[id].zones[zone]);c.target=c.feet;c._display=c.feet;c.position=c.feet;c.route.clear();c.order_id="";c.next_scene="";c.placed=true;c.sleeping=false;c.action="home_"+kind;c.state=Character.State.IDLE;c.label={"eat_phone":"吃饭看手机","eat":"吃饭动作预览","cook":"做饭动作预览","desk_read":"书桌阅读","old_letters":"翻看旧信与手记","diary":"写日记动作预览","shower":"淋浴动作预览","soak":"泡澡动作预览"}.get(kind,{"view":"阳台看风景","wardrobe":"整理衣柜","mirror":"照镜整理仪容","wash_food":"洗菜","wash_dishes":"洗碗"}.get(kind,kind));c.stage=c._stage_now();c.room_changed.emit(c)
	world._on_scene_picked(id)

func domestic_walk(kind:String,actor:String="both") -> void:
	if kind in load("res://entities/life_activities_v18.gd").KINDS:life_preview(kind,actor,false);return
	if kind.begins_with("sofa_"):sofa_variant(kind,actor,false);return
	preview("")
	if kind=="":return
	mode="domestic"
	var id:="shared-home-upstairs" if kind in ["diary","desk_read","old_letters","view","wardrobe","mirror"] else "shared-home-bathroom" if kind in ["shower","soak"] else "xiaojingyu-home"
	for c:Character in world.characters:
		if actor!="both" and actor!=c.key:continue
		save_before(c)
		var zone:=c.key+"_balcony" if kind=="view" else c.key+"_"+kind if kind in ["wardrobe","mirror"] else "kitchen_wash" if kind in ["wash_food","wash_dishes"] else "selena_diary" if kind in ["diary","desk_read","old_letters"] else "bath_"+kind if kind in ["shower","soak"] else "cook_stove" if kind=="cook" else "dining_"+c.key
		c.sleeping=false;c.action="home_"+kind;c.label={"eat_phone":"走到餐桌吃饭看手机","eat":"走到餐桌吃饭","cook":"走到灶台做饭","desk_read":"走到书桌阅读","old_letters":"翻看旧信与手记","diary":"走到书桌写日记","shower":"前往淋浴","soak":"前往浴缸"}.get(kind,{"view":"阳台看风景","wardrobe":"整理衣柜","mirror":"照镜整理仪容","wash_food":"洗菜","wash_dishes":"洗碗"}.get(kind,kind))
		c.walk_order({"id":"art-domestic-"+c.key,"actor":c.key,"scene":id,"zone":zone})
	world._on_scene_picked(id)
func sofa_variant(kind:String,actor:String,instant:bool=false) -> void:
	if instant:sofa_preview(actor)
	else:sofa_walk(actor)
	for c:Character in world.characters:
		if actor!="both" and actor!=c.key:continue
		c.action=("sofa_album" if c.key=="xiaoai" else "sofa_read") if kind=="sofa_pair" else kind
		c.label={"sofa_phone":"沙发看手机","sofa_rest":"沙发休息","sofa_read":"沙发看书","sofa_music":"沙发听音乐","sofa_album":"沙发看相册"}.get(c.action,kind)
		if instant:c.stage=c._stage_now()

func life_preview(kind:String,actor:String,instant:bool) -> void:
	preview("");mode="domestic"
	var destination:Array=[]
	for c:Character in world.characters:
		if actor!="both" and actor!=c.key:continue
		destination=load("res://entities/life_activities_v18.gd").destination(kind,c.key)
		save_before(c);c.sleeping=false;c.action="life_"+kind;c.label={"washface":"洗漱","prep":"准备食材","tea":"泡茶","water":"照料盆栽","tidy":"收拾房间","read":"阅读","write":"整理歌词／乐谱","listen":"听练习回放","select":"挑选物品","bench":"长椅歇脚","onsen_rest":"汤屋休息","chess":"棋桌游戏","arcade":"玩机台","outside_eat":"外出吃饭"}.get(kind,kind)
		if instant:
			c.scene_id=destination[0];c.want_scene=c.scene_id;c.want_zone=destination[1]
			c.feet=WorldData.point(WorldData.scenes[c.scene_id].zones[c.want_zone]);c.target=c.feet;c._display=c.feet;c.position=c.feet;c.route.clear();c.order_id="";c.next_scene="";c.placed=true;c.state=Character.State.IDLE;c.stage=c._stage_now();c.room_changed.emit(c)
		else:c.walk_order({"id":"art-life-"+c.key,"actor":c.key,"scene":destination[0],"zone":destination[1]})
	if not destination.is_empty():world._on_scene_picked(destination[0])
