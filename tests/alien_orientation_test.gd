extends "res://tests/encounter_test.gd"
## Exercise actual alien steering at the vertical look-at singularity.


func run() -> void:
	var enemy := Alien.new()
	enemy.render_enabled = false
	root.add_child(enemy)
	for initial: Basis in [Basis.IDENTITY, Basis.from_euler(Vector3(0.3,0.7,0.8))]:
		for direction: Vector3 in [Vector3.UP,Vector3.DOWN,Vector3(0.01,1,0.01).normalized(),Vector3(-0.01,-1,0.01).normalized(),Vector3.FORWARD,Vector3.RIGHT]:
			enemy.position = Vector3(0,500,0)
			enemy.global_basis = initial
			enemy.home_position = enemy.position+direction*100.0
			enemy.returning = true
			enemy.return_time = 0.0
			var stable := true
			for step in range(180):
				var before := enemy.global_basis.get_rotation_quaternion()
				enemy.velocity = Vector3.ZERO
				enemy.fly(1.0/60.0,null,Vector3.ZERO)
				var after := enemy.global_basis
				stable = stable and after.is_finite() and absf(after.determinant()-1.0) < 0.0001
				stable = stable and before.angle_to(after.get_rotation_quaternion()) < 0.17
			check(stable,"Steering remains finite, orthonormal and smooth toward %s" % direction)
			check((-enemy.global_basis.z).dot(direction) > 0.999,"Alien actually faces its destination, including vertical flight")
			if absf(direction.dot(Vector3.UP)) < 0.98:
				check(enemy.global_basis.y.dot(Vector3.UP) > 0.999,"Ordinary horizontal steering retains world-up leveling")
	# Sweep through the pole rather than choosing a new roll on every frame.
	for direction: Vector3 in [Vector3(0.03,1,0).normalized(),Vector3.UP,Vector3(-0.03,1,0).normalized()]:
		enemy.position = Vector3(0,500,0)
		enemy.home_position = enemy.position+direction*100.0
		enemy.returning = true
		enemy.return_time = 0.0
		var previous_up := enemy.global_basis.y
		for step in range(120):
			enemy.velocity = Vector3.ZERO
			enemy.fly(1.0/60.0,null,Vector3.ZERO)
		check(enemy.global_basis.y.dot(previous_up) > 0.0,"Crossing a vertical destination does not flip the alien's roll")
	enemy.home_position = enemy.position
	enemy.returning = true
	var unchanged := enemy.global_basis
	enemy.fly(1.0/60.0,null,Vector3.ZERO)
	check(enemy.global_basis.is_equal_approx(unchanged),"Coincident destination retains the current orientation")
	enemy.free()
	print("Alien orientation: %d passed, %d failed" % [checks-failures,failures])
	quit(0 if failures == 0 else 1)
