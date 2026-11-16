extends Node

func _ready() -> void:
	call_deferred("check")

func check() -> void:
	var issues: Array[String]=[]
	var count:=0
	for id in WanderingNpc.data().scenes:
		var room:=Room.new()
		room.setup(str(id));add_child(room);room.visible=false
		var regular: Dictionary={}
		var special:=0
		for npc in room.get_children():
			if not npc is WanderingNpc:continue
			count+=1
			if npc.special:special+=1
			else:regular[npc.skin]=int(regular.get(npc.skin,0))+1
			if npc.patrol.is_empty():issues.append("No patrol points: "+id)
			var before: Vector2=npc.position
			for step in 400:
				npc.advance(.1)
				if not npc.nav.walkable(npc.position):issues.append("NPC crossed furniture: "+id);break
			if before.distance_to(npc.position)<1:issues.append("NPC did not patrol: "+id+"/"+npc.skin)
			if absf(npc.sprite.scale.x-npc.sprite.scale.y)>.00001:issues.append("Character stretched")
			if npc.special and npc.sprite.material==null:issues.append("Missing pixel finish")
		if id=="qianxia-park":
			if not regular.is_empty():issues.append("Park contains ordinary NPCs")
		elif regular!={"blonde":1,"blue":1,"xiaojingyu":1}:issues.append("Uneven NPC distribution: "+id)
		if special!=(2 if id=="qianxia-park" else 0):issues.append("Special gait outside park / missing pair: "+id)
		room.free()
	if count!=14:issues.append("Expected 14 ambient NPCs, got "+str(count))
	if issues.is_empty():print("PASS: 12 ordinary NPCs across four public scenes; park has only the pair; collision-valid movement and uniform scaling.")
	else:
		for issue in issues:push_error(issue)
	get_tree().quit(0 if issues.is_empty() else 1)
