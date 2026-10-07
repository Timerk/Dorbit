class_name CombatEffect
extends Node3D
## Bounded presentation lifetime, independent of the ship's visibility and combat state.

var follow: WeakRef


func _process(_delta: float) -> void:
	if follow == null:
		set_process(false)
		return
	var ship := follow.get_ref() as SpaceShip
	if is_instance_valid(ship) and ship.alive and ship.is_visible_in_tree():
		global_position = ship.global_position
	else:
		# Leave the last hit visible at the death location when the ship is hidden or freed.
		follow = null
		set_process(false)
