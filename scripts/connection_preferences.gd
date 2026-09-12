class_name ConnectionPreferences
extends RefCounted
## Local menu defaults, separate from server-owned pilot data.

const PATH := "user://connection.cfg"

var address: String = "127.0.0.1"
var port: int = FlightSession.PORT
var save_failed: bool = false


func load_from(path: String = PATH) -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	var saved_address: Variant = config.get_value("connection", "address", address)
	var saved_port: Variant = config.get_value("connection", "port", port)
	if saved_address is String and not saved_address.strip_edges().is_empty():
		address = saved_address.strip_edges()
	if saved_port is int and saved_port >= 1 and saved_port <= 65535:
		port = saved_port


func remember(host_address: String, udp_port: int, path: String = PATH) -> void:
	address = host_address
	port = udp_port
	var config := ConfigFile.new()
	config.set_value("connection", "address", address)
	config.set_value("connection", "port", port)
	save_failed = config.save(path) != OK
