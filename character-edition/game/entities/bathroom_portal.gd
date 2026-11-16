extends Node2D
## A compact frosted door in the existing wall, above the stair entry.
func _draw() -> void:
	draw_rect(Rect2(-2,-2,56,59),Color("382a23"))
	draw_rect(Rect2(0,0,52,56),Color("a16b3c"))
	draw_rect(Rect2(4,3,44,50),Color("544a40"))
	draw_rect(Rect2(7,5,38,45),Color("b5c9c7"))
	for y in range(8,48,4):draw_line(Vector2(8,y),Vector2(44,y),Color(.89,.94,.91,.22),1)
	draw_line(Vector2(26,5),Vector2(26,50),Color("777b73"),2)
	draw_rect(Rect2(41,28,2,9),Color("eee4c9"))
	draw_rect(Rect2(-1,53,54,4),Color("d7cbb5"))
	# Tiny bath pictogram, readable at room scale.
	draw_rect(Rect2(18,17,17,8),Color("f3f0dd"))
	draw_line(Vector2(16,16),Vector2(37,16),Color("fff8df"),2)
	draw_line(Vector2(20,25),Vector2(20,28),Color("eee4cc"),2)
	draw_line(Vector2(33,25),Vector2(33,28),Color("eee4cc"),2)
