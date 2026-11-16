extends Node

func _ready() -> void:
	call_deferred("check")

func check() -> void:
	var world_data: Node = get_node("/root/WorldData")
	var downstairs: String = "xiaojingyu-home"
	var upstairs: String = "shared-home-upstairs"
	var issues: Array[String] = []
	if world_data.scene_path(downstairs,upstairs) != [downstairs,upstairs]:issues.append("Upstairs route missing")
	if world_data.scene_path(upstairs,downstairs) != [upstairs,downstairs]:issues.append("Downstairs route missing")
	HomeGrid.choose(downstairs)
	var layout := HomeGrid.defaults()
	if layout.stored.size() != 28:issues.append("Old furniture not fully stored")
	for scene in [downstairs,upstairs]:
		var nav: RoomNav = world_data.nav(scene)
		for point in [Vector2(123,349),Vector2(110,495),Vector2(373,468),Vector2(724,484)]:
			if not nav.walkable(point):issues.append(scene+" blocked at "+str(point))
		if nav.route(Vector2(373,468),Vector2(123,349)).is_empty():issues.append(scene+" cannot reach stair landing")
		if not is_equal_approx(float(WorldData.scenes[scene].modules["shared-stairs"].x),80.0):issues.append("Staircase is not flush with left wall")
		for layer in world_data.layers[scene].layers:
			if not layer.id in ["xj-window","xj-main-light","shared-stairs"]:issues.append("Old furniture layer: "+str(layer.id))
		for id in ["xj-bed","xj-sofa","xj-desk","xj-tank"]:
			if world_data.scenes[scene].modules.has(id):issues.append("Ghost module: "+id)
	var people := Residents.people()
	if people.size()!=2 or people[0].key!="xiaoai" or people[1].key!="selena":issues.append("Shared residents changed")
	if not issues.is_empty():
		for issue in issues:push_error(issue)
		get_tree().quit(1)
	else:
		print("PASS: 28 items stored; two independent residents; both floors and stair landing navigable; no old furniture layers/modules.")
		get_tree().quit()
