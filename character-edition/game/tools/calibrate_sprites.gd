extends SceneTree

func _initialize() -> void:
	var file := "res://assets/world.json"
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(file))
	var report := {}
	for skin in ["xiaoai", "selena"]:
		for kind in ["walk", "actions"]:
			var spec: Dictionary = world.actors[skin][kind]
			var image := Image.load_from_file("res://assets/actors/" + spec.file)
			var measurements := []
			for i in 16:
				var r: Array = spec.rects[i]
				var cell := image.get_region(Rect2i(r[0],r[1],r[2],r[3]))
				# Scan opaque pixel clusters; stray near-transparent matte pixels do not define feet.
				var bottom := 0
				var top := cell.get_height()
				var left := cell.get_width()
				var right := 0
				for y in cell.get_height():
					for x in cell.get_width():
						if cell.get_pixel(x,y).a > 0.5:
							bottom = maxi(bottom,y)
							top = mini(top,y)
							left = mini(left,x)
							right = maxi(right,x)
				assert(bottom > top and left > 0 and right < cell.get_width()-1, "Sprite overlaps a cell boundary")
				spec.anchors[i] = [float(r[2])/2.0,bottom]
				measurements.append({"bounds":[left,top,right,bottom],"anchor":spec.anchors[i]})
			if kind == "actions":
				# Pelvis sits roughly 47 source pixels above the boot baseline.
				spec.seatY = [spec.anchors[0][1]-47,spec.anchors[4][1]-47,spec.anchors[8][1]-47,spec.anchors[12][1]-47]
			report[skin+"-"+kind] = measurements
	var out := FileAccess.open(file,FileAccess.WRITE)
	out.store_string(JSON.stringify(world,"  ")+"\n")
	out.close()
	var report_file := FileAccess.open("res://sprite-calibration.json",FileAccess.WRITE)
	report_file.store_string(JSON.stringify(report,"  ")+"\n")
	report_file.close()
	print("Calibrated 64 sprite cells from generated PNG alpha bounds.")
	quit()
