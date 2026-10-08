extends SceneTree
## Run outside the exported pack to check menus and their dynamically loaded art.


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	for directory: String in ["res://docs/ammo-art", "res://docs/sector-art"]:
		if DirAccess.dir_exists_absolute(directory):
			push_error("Documentation artwork must not enter the client pack: " + directory)
			quit(1)
			return
	var sector := (load("res://scenes/sector.tscn") as PackedScene).instantiate() as Sector
	root.add_child(sector)
	await process_frame
	await process_frame
	var menu := sector.main_menu
	if not sector.offline or not menu.home.is_visible_in_tree() or menu.start_button.disabled or menu.ship_art.texture == null:
		push_error("Exported offline Overview did not load its starter ship and Start.")
		quit(1)
		return
	for page: String in ["hangar", "shop", "cargo", "refining", "quests", "settings", "connection", "skylab", "gates"]:
		menu.select_page(page)
		await process_frame
		await process_frame
		var panel: Control
		match page:
			"hangar": panel = sector.equipment_menu
			"shop", "cargo": panel = sector.shop
			"refining": panel = sector.resource_workshop
			"quests": panel = sector.hud.contract_panel
			"settings": panel = sector.settings_menu.panel
			"connection": panel = sector.session.menu
			"skylab": panel = sector.skylab_menu
			_: panel = menu.placeholder
		if not panel.is_visible_in_tree() or menu.start_button.is_visible_in_tree():
			push_error("Exported offline %s did not open independently of Overview." % page)
			quit(1)
			return
		if page == "settings":
			for tab in 3:
				sector.settings_menu.tabs.current_tab = tab
				await process_frame
		if page == "cargo":
			for resource: String in CargoResources.TYPES:
				var texture := load("res://assets/ui/resources/%s.png" % resource) as Texture2D
				var image := texture.get_image() if texture != null else null
				if image == null or image.get_width() < 1024 or image.get_height() < 1024 or image.get_used_rect().size == image.get_size() or image.get_pixel(0, 0).a != 0.0:
					push_error("Packaged %s artwork must be high resolution with transparent padding." % resource)
					quit(1)
					return
		if page == "skylab":
			var scene := sector.skylab_menu.art.texture
			var standard := load("res://assets/ui/skylab/robot-standard.png") as Texture2D
			var advanced := load("res://assets/ui/skylab/robot-advanced.png") as Texture2D
			if scene == null or scene.get_width() < 1500 or standard == null or advanced == null:
				push_error("Packaged Skylab must include its detailed station scene and robot artwork.")
				quit(1)
				return
			for robot: Texture2D in [standard, advanced]:
				if robot.get_width() < 1024 or robot.get_image().get_pixel(0, 0).a != 0.0:
					push_error("Packaged collector robots must be detailed transparent artwork.")
					quit(1)
					return
	menu.show_home()
	sector.session.launch()
	if sector.preflight or menu.visible or sector.session.active:
		push_error("Exported offline Start did not enter solo flight.")
		quit(1)
		return
	for page: String in ["hangar", "shop", "cargo", "refining", "quests", "settings", "connection", "skylab", "gates", "overview"]:
		menu.select_page(page)
		await process_frame
		await process_frame
		if not menu.visible or menu.selected_page != page or sector.preflight or menu.start_button.is_visible_in_tree() or not menu.resume_button.is_visible_in_tree():
			push_error("Exported offline flight %s must use the shared menu without Start or docking." % page)
			quit(1)
			return
	menu.resume_button.pressed.emit()
	sector.set_paused(true)
	await process_frame
	await process_frame
	await process_frame
	var pause := sector.settings_menu.pause_panel.get_global_rect()
	if not sector.settings_menu.pause_panel.is_visible_in_tree() or not sector.settings_menu.main_menu_button.is_visible_in_tree() or pause.size.x < 500 or pause.size.y > 450:
		push_error("Exported flight menu must open readably and expose Quit to main menu without resizing.")
		quit(1)
		return
	sector.settings_menu.main_menu_button.pressed.emit()
	if not sector.preflight or not menu.home.is_visible_in_tree():
		push_error("Exported solo flight could not return to Overview.")
		quit(1)
		return
	print("Packaged menus: every destination, eight high-resolution transparent resources, three Settings tabs and solo launch/return loaded")
	quit(0)
