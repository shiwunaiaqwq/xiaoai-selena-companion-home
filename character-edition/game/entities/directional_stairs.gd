extends Node2D
## One staircase geometry, viewed below and above. North is low; south is high.
## The generated wood atlas supplies texture; ports, treads, rails and slab share coordinates.
const WOOD = preload("res://assets/renovation/stairs-wall-up.png")
const RISE := 108.0
const PROJECTION := 0.33
const NORTH := 365.0
const SOUTH := 510.0
const LEFT := 80.0
const RIGHT := 150.0
const LANDING_END := 225.0
var upper := false
var rails := Node2D.new()

func setup(scene: String, _layer: Dictionary) -> void:
	upper = scene == "shared-home-upstairs"
	position.y = 340 + float(_layer.get("render_offset_y",0))
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rails.z_index = 2
	rails.draw.connect(_draw_rails)
	add_child(rails)

func _process(_dt: float) -> void:
	var night: bool = Daylight.reading(SharedFeed.now_ms()).phase == "night"
	if upper:night=BedroomPreview.night(night)
	modulate = Color(.55,.59,.78) if night else Color.WHITE

func point(x: float, y: float, height: float) -> Vector2:
	return Vector2(x,y-height*PROJECTION+(RISE*PROJECTION if upper else 0))

func wood(c: CanvasItem, rect: Rect2, dark := false) -> void:
	c.draw_texture_rect_region(WOOD,rect,Rect2(220,180,200,80),Color(.57,.45,.37) if dark else Color(.92,.87,.78))
	c.draw_rect(rect,Color("55301d"),false,1)
	c.draw_line(rect.position,rect.position+Vector2(rect.size.x,0),Color("e6b477"),1)

func _draw() -> void:
	draw_set_transform(Vector2(0,-340))
	if upper:
		draw_rect(Rect2(79,363,75,149),Color("34251e"))
		draw_rect(Rect2(84,369,63,138),Color("17151c"))
		# Interior well walls below the second-floor slab.
		draw_rect(Rect2(80,370,7,140),Color("62402b"))
		draw_rect(Rect2(145,370,7,140),Color("493021"))
	else:
		# Closed structural base and south fascia; neither entrance is on this face.
		wood(self,Rect2(80,506,145,36),true)
		draw_rect(Rect2(150,380,5,127),Color("75462a"))
	for step in 10:
		var y := NORTH+(SOUTH-NORTH)*step/10.0
		var z := RISE*step/10.0
		var start := point(LEFT,y,z)
		wood(self,Rect2(start,Vector2(RIGHT-LEFT,(SOUTH-NORTH)/10.0)))
		draw_line(start+Vector2(1,1),start+Vector2(69,1),Color("704326"),2)
	var at := point(LEFT,SOUTH,RISE)
	wood(self,Rect2(at,Vector2(LANDING_END-LEFT,32)))
	# Open east threshold: a continuous walkable connection to upstairs floor.
	draw_line(at+Vector2(144,1),at+Vector2(144,31),Color("e8b77d"),2)
	draw_set_transform(Vector2.ZERO)

func post(c: CanvasItem, x: float, y: float, z: float) -> void:
	var base := point(x,y,z)
	var top := point(x,y,z+52)
	c.draw_rect(Rect2(top-Vector2(2,0),Vector2(5,base.y-top.y+2)),Color("512e1d"))
	c.draw_rect(Rect2(top-Vector2(1,0),Vector2(2,base.y-top.y)),Color("ad7542"))
	c.draw_rect(Rect2(top-Vector2(3,2),Vector2(7,4)),Color("6b4127"))
	c.draw_line(top-Vector2(2,1),top+Vector2(3,-1),Color("ddb273"),1)

func beam(c: CanvasItem, a: Vector2, b: Vector2) -> void:
	c.draw_line(a,b,Color("4a2b1b"),5)
	c.draw_line(a-Vector2(0,1),b-Vector2(0,1),Color("a86e3c"),3)
	c.draw_line(a-Vector2(0,2),b-Vector2(0,2),Color("e1ae6a"),1)

func _draw_rails() -> void:
	rails.draw_set_transform(Vector2(0,-340))
	if upper:
		for y in [365.0,400.0,438.0,475.0,510.0]:post(rails,152,y,RISE)
		beam(rails,point(152,365,RISE+52),point(152,510,RISE+52))
		post(rails,82,365,RISE)
		beam(rails,point(82,365,RISE+52),point(152,365,RISE+52))
	else:
		for step in [0,2,4,6,8,10]:
			post(rails,151,NORTH+(SOUTH-NORTH)*step/10.0,RISE*step/10.0)
		beam(rails,point(151,NORTH,52),point(151,SOUTH,RISE+52))
		# Wall-side handrail; low north entrance is completely open.
		beam(rails,point(82,NORTH,52),point(82,SOUTH,RISE+52))
	# South edge closed, east side open. Same physical landing on both floors.
	for x in [82.0,150.0,224.0]:post(rails,x,542,RISE)
	beam(rails,point(82,542,RISE+52),point(224,542,RISE+52))
	post(rails,224,510,RISE)
	beam(rails,point(151,510,RISE+52),point(224,510,RISE+52))
	rails.draw_set_transform(Vector2.ZERO)
