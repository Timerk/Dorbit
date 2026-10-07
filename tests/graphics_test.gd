extends "res://tests/encounter_test.gd"
## Run with an isolated APPDATA profile, then repeat with -- --restart.


func run() -> void:
	sector = preload("res://scenes/sector.tscn").instantiate()
	sector.client_only = false
	root.add_child(sector)
	sector.set_physics_process(false)
	await sync_physics()
	var menu := sector.settings_menu
	var environment := (sector.get_node("WorldEnvironment") as WorldEnvironment).environment
	var sun := sector.get_node("Sun") as DirectionalLight3D
	if "--restart" in OS.get_cmdline_user_args():
		check(is_equal_approx(root.scaling_3d_scale, 0.75), "Render scale is applied after restarting")
		check(root.anisotropic_filtering_level == Viewport.ANISOTROPY_16X, "Filtering is applied after restarting")
		check(environment.glow_enabled and environment.ssao_enabled, "Bloom and SSAO are applied after restarting")
		check(sun.shadow_enabled and sun.directional_shadow_max_distance == 500.0, "Shadow quality is applied after restarting")
		check(sector.settings.effects_quality == 1, "Effects quality survives restarting")
		sector.settings = GameSettings.new()
		sector.apply_graphics(false)
		sector.settings.save()
		await finish()
		return

	check(is_equal_approx(root.scaling_3d_scale, 1.0) and root.anisotropic_filtering_level == Viewport.ANISOTROPY_DISABLED, "Older profiles retain native rendering and disabled filtering")
	check(not environment.glow_enabled and not environment.ssao_enabled and not sun.shadow_enabled, "New environment effects default to off")
	check(sector.settings.effects_quality == 2, "Existing combat effects remain enabled by default")
	menu.open()
	menu.tabs.current_tab = 2
	for setting: String in GameSettings.GRAPHICS_LEVELS:
		var choice := menu.graphics_options[setting]
		for index in range(choice.item_count):
			select_option(menu, setting, index)
			var loaded := GameSettings.new()
			loaded.load_from()
			check(loaded.get(setting) == GameSettings.GRAPHICS_LEVELS[setting][index], "%s choice %d saves immediately" % [setting, index])
			if setting == "render_scale":
				check(is_equal_approx(root.scaling_3d_scale, loaded.render_scale), "Render scale changes the live viewport")
			elif setting == "anisotropic_filtering":
				var rock := sector.get_node("Asteroid0").find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
				var expected := BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if index == 0 else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				check((rock.material_override as BaseMaterial3D).texture_filter == expected, "Filtering switches live material samplers in Compatibility")
			elif setting == "shadow_quality":
				check(sun.shadow_enabled == (index > 0), "Shadow choice enables or disables the sun's shadows")
				if index > 0:
					check(sun.directional_shadow_max_distance == [180.0, 300.0, 500.0][index - 1], "Shadow choice applies its distance budget")
			menu.sync_controls()
			check(choice.selected == index, "Reopening controls preserves %s choice" % setting)
	for enabled in [true, false]:
		menu.bloom.button_pressed = enabled
		check(environment.glow_enabled == enabled, "Bloom toggles the real environment immediately")
		menu.ssao.button_pressed = enabled
		check(environment.ssao_enabled == enabled, "SSAO toggles the real environment immediately")
		var loaded := GameSettings.new()
		loaded.load_from()
		check(loaded.bloom == enabled and loaded.ssao == enabled, "Environment toggles save immediately")
		menu.sync_controls()
		check(menu.bloom.button_pressed == enabled and menu.ssao.button_pressed == enabled, "Environment toggles reflect saved state")
	var surface := SectorVisuals.asteroid_surface()
	check(surface.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC, "Asteroid materials support anisotropic filtering")
	var station := Node3D.new()
	SectorVisuals.station(station, Vector3.ZERO)
	var textured_surfaces := 0
	for part: MeshInstance3D in station.find_children("*", "MeshInstance3D", true, false):
		for index in range(part.mesh.get_surface_count()):
			var material := part.get_active_material(index) as BaseMaterial3D
			if material != null and material.albedo_texture != null:
				textured_surfaces += 1
				check(material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC, "Textured station materials support anisotropic filtering")
	check(textured_surfaces > 0, "Filtering checks include actual imported station textures")
	station.free()

	# Changing the presentation setting must clear old effects and never suppress damage.
	select_option(menu, "effects_quality", 2)
	SectorVisuals.laser(sector, Vector3.ZERO, Vector3(0, 0, -20), false)
	check(get_nodes_in_group("transient_feedback").size() == 1, "High effects render laser feedback")
	select_option(menu, "effects_quality", 0)
	await process_frame
	check(get_nodes_in_group("transient_feedback").is_empty(), "Off removes existing visual effects")
	var previous_health := sector.player.hull + sector.player.shield
	sector.player.take_damage(100.0, sector.alien)
	SectorVisuals.laser(sector, Vector3.ZERO, Vector3(0, 0, -20), false)
	SectorVisuals.explosion(sector, Vector3.ZERO)
	check(get_nodes_in_group("transient_feedback").is_empty(), "Off suppresses laser, damage and destruction meshes")
	check(is_equal_approx(previous_health - sector.player.hull - sector.player.shield, 100.0), "Effects off preserves authoritative damage")
	select_option(menu, "effects_quality", 1)
	SectorVisuals.impact(sector.player, sector.player.position, true, true)
	check(get_nodes_in_group("transient_feedback").size() == 2, "Low uses a shield ring and one hull spark")
	for index in range(50):
		SectorVisuals.impact(sector.player, sector.player.position, true, true)
		SectorVisuals.laser(sector, Vector3.ZERO, Vector3(0, 0, -20), false)
		SectorVisuals.explosion(sector, Vector3.ZERO)
	check(get_nodes_in_group("transient_feedback").size() == 32, "Low caps mixed combat feedback at 32 meshes")
	select_option(menu, "effects_quality", 2)
	await process_frame
	SectorVisuals.impact(sector.player, sector.player.position, true, true)
	check(get_nodes_in_group("transient_feedback").size() == 3, "High restores the shield ring and both hull sparks")
	select_option(menu, "effects_quality", 0)
	await process_frame
	var victim := sector.alien
	victim.time_since_hit = 100.0
	sector.session.active = false
	sector.player.position = Vector3(0, 0, -200)
	victim.position = Vector3(0, 0, -210)
	victim.home_position = victim.position
	var credits_before := sector.credits
	victim.take_damage(victim.hull + victim.shield + 1.0, sector.player)
	check(not victim.alive and sector.credits > credits_before, "Effects off preserves alien destruction and rewards")
	check(get_nodes_in_group("transient_feedback").is_empty(), "Actual destruction remains visually off")

	var invalid := ConfigFile.new()
	for setting: String in GameSettings.GRAPHICS_LEVELS:
		invalid.set_value("graphics", setting, -99)
	invalid.set_value("graphics", "bloom", "true")
	invalid.set_value("graphics", "ssao", 1)
	invalid.save("user://invalid-graphics.cfg")
	var loaded := GameSettings.new()
	loaded.load_from("user://invalid-graphics.cfg")
	check(loaded.render_scale == 1.0 and loaded.anisotropic_filtering == 0 and loaded.shadow_quality == 0 and loaded.effects_quality == 2 and not loaded.bloom and not loaded.ssao, "Malformed graphics preferences retain usable defaults")
	invalid.set_value("graphics", "render_scale", NAN)
	invalid.set_value("graphics", "shadow_quality", 1.0)
	invalid.save("user://invalid-graphics.cfg")
	loaded.load_from("user://invalid-graphics.cfg")
	check(loaded.render_scale == 1.0 and loaded.shadow_quality == 0, "Non-finite scales and non-integer levels are rejected")
	invalid.clear()
	invalid.save("user://invalid-graphics.cfg")
	loaded = GameSettings.new()
	loaded.load_from("user://invalid-graphics.cfg")
	check(loaded.render_scale == 1.0 and loaded.anisotropic_filtering == 0 and loaded.shadow_quality == 0 and loaded.effects_quality == 2 and not loaded.bloom and not loaded.ssao, "Profiles without the new keys retain the original rendering defaults")
	select_option(menu, "render_scale", 2)
	select_option(menu, "anisotropic_filtering", 1)
	select_option(menu, "shadow_quality", 3)
	select_option(menu, "effects_quality", 1)
	menu.bloom.button_pressed = true
	menu.ssao.button_pressed = true
	await finish()


func select_option(menu: SettingsMenu, setting: String, index: int) -> void:
	menu.graphics_options[setting].select(index)
	menu.graphics_options[setting].item_selected.emit(index)


func finish() -> void:
	print("Graphics checks: %d passed, %d failed" % [checks - failures, failures])
	for voice in sector.audio.voices:
		voice.stop()
	await create_timer(0.1).timeout
	sector.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
