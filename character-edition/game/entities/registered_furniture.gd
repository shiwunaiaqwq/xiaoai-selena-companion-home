extends Node2D
## Trace narrow foreground silhouettes without painting rectangular floor over residents.
var pieces: Array[Polygon2D] = []
var night_pieces: Array[Polygon2D] = []

func map_axis(value: float, anchors: Array) -> float:
	for i in range(1,anchors.size()):
		if value<=float(anchors[i][0]):
			var a: Array=anchors[i-1]
			var b: Array=anchors[i]
			return lerpf(float(a[1]),float(b[1]),(value-float(a[0]))/(float(b[0])-float(a[0])))
	return float(anchors.back()[1])

func setup(layer: Dictionary, registration: Dictionary, image: Texture2D) -> void:
	position=Vector2(0,float(layer.depth))
	var offset_data: Array=layer.get("draw_offset",[0,0])
	var draw_offset:=Vector2(offset_data[0],offset_data[1])
	_make_pieces(layer.foreground_polygons,registration,image,draw_offset,pieces)
	if layer.has("night_foreground_polygons"):
		_make_pieces(layer.night_foreground_polygons,registration,image,draw_offset,night_pieces)
		for mesh in night_pieces:mesh.visible=false

func _make_pieces(contours: Array, registration: Dictionary, image: Texture2D, draw_offset: Vector2, target: Array[Polygon2D]) -> void:
	for contour: Array in contours:
		var mesh:=Polygon2D.new()
		var points:=PackedVector2Array()
		var uv:=PackedVector2Array()
		for p: Array in contour:
			points.append(Vector2(map_axis(p[0],registration.x),map_axis(p[1],registration.y))+draw_offset-position)
			uv.append(Vector2(p[0],p[1]))
		mesh.polygon=points;mesh.uv=uv;mesh.texture=image
		add_child(mesh);target.append(mesh)

func set_source_texture(image: Texture2D, night: bool=false) -> void:
	for mesh in pieces:
		mesh.texture=image
		mesh.visible=night_pieces.is_empty() or not night
	for mesh in night_pieces:
		mesh.texture=image
		mesh.visible=night
