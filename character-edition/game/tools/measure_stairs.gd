extends SceneTree

func _initialize() -> void:
	var images := {"up":"res://assets/renovation/stairs-wall-up.png", "down":"res://assets/renovation/stairs-down.png"}
	var result := {}
	for key in images:
		var image := Image.load_from_file(images[key])
		var left := image.get_width()
		var top := image.get_height()
		var right := 0
		var bottom := 0
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x,y).a >= 0.8:
					left=mini(left,x);top=mini(top,y);right=maxi(right,x);bottom=maxi(bottom,y)
		result[key] = {"image":images[key],"size":[image.get_width(),image.get_height()],"region":[left,top,right-left+1,bottom-top+1]}
	var file := FileAccess.open("res://stair-boundaries.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  ")+"\n")
	file.close()
	print(JSON.stringify(result))
	quit()
