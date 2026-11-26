extends "res://tests/network_test.gd"
## NetSimulator relay with raw UDP sockets: delay, jitter, loss, duplication,
## live reconfiguration and flushing on stop, in both directions.

var server := PacketPeerUDP.new()
var client := PacketPeerUDP.new()
var relay := NetSimulator.new()
var relay_ip := ""
var relay_port := 0


func run() -> void:
	check(server.bind(0, "127.0.0.1") == OK, "Server socket binds")
	check(relay.start("127.0.0.1", server.get_local_port()) == OK, "Relay starts")
	check(relay.is_running() and relay.listen_port > 0, "Relay reports its listening port")
	check(relay.start("127.0.0.1", server.get_local_port()) == ERR_ALREADY_IN_USE, "A running relay cannot start twice")
	check(client.bind(0, "127.0.0.1") == OK, "Client socket binds")
	client.set_dest_address("127.0.0.1", relay.listen_port)
	relay.set_seed(1234)
	# The server learns the relay's upstream address from the first datagram.
	client.put_packet(PackedByteArray([0]))
	check(not receive(server, 500).is_empty(), "A datagram reaches the server unchanged in time")
	relay_ip = server.get_packet_ip()
	relay_port = server.get_packet_port()
	server.set_dest_address(relay_ip, relay_port)
	server.put_packet(PackedByteArray([1]))
	check(receive(client, 500) == PackedByteArray([1]), "Replies return to the client")

	relay.configure(NetSimulator.UP, 60.0)
	relay.configure(NetSimulator.DOWN, 25.0)
	var up := delays(client, server, 8)
	var down := delays(server, client, 8)
	print("Relay delays: up %s ms, down %s ms" % [up, down])
	check(within(up, 59.0, 75.0), "Upstream latency is applied within tolerance")
	check(within(down, 24.0, 40.0), "Downstream latency is applied independently")

	# Live changes apply to datagrams that arrive afterwards.
	relay.configure(NetSimulator.UP, 0.0)
	var live := delays(client, server, 5)
	check(within(live, 0.0, 12.0), "Lowering latency while running takes effect immediately")
	relay.set_round_trip(100.0, 40.0)
	check(relay.symmetric() and is_equal_approx(relay.conditions(NetSimulator.DOWN)["latency_ms"], 50.0), "Round-trip settings split evenly per direction")
	var jittered := delays(client, server, 30)
	print("Jittered delays: %s ms" % jittered)
	check(within(jittered, 29.0, 80.0) and NetStats.percentile(jittered, 0.9) - jittered[0] > 15.0, "Jitter spreads delays within its bound")

	relay.configure(NetSimulator.BOTH, 0.0)
	relay.reset_stats()
	relay.configure(NetSimulator.UP, 0.0, 0.0, 20.0)
	var arrived := burst(client, server, 2000)
	var stats: Dictionary = relay.stats()
	print("Upstream loss: %d of 2000 arrived, stats %s" % [arrived, stats["up"]])
	check(arrived >= 1540 and arrived <= 1660, "Upstream loss rate stays near 20%")
	check(stats["up"]["dropped_packets"] == 2000 - arrived and stats["up"]["received_packets"] == 2000, "Loss statistics account for every datagram")

	relay.configure(NetSimulator.UP, 0.0)
	relay.configure(NetSimulator.DOWN, 0.0, 0.0, 0.0, 10.0)
	relay.reset_stats()
	arrived = burst(server, client, 2000)
	stats = relay.stats()
	print("Downstream duplication: %d datagrams from 2000, stats %s" % [arrived, stats["down"]])
	check(arrived >= 2140 and arrived <= 2260, "Downstream duplication rate stays near 10%")
	check(stats["down"]["forwarded_packets"] == arrived and stats["down"]["duplicated_packets"] == arrived - 2000, "Duplication statistics match deliveries")
	check(stats["up"]["received_packets"] == 0, "Each direction keeps its own statistics")

	# Stopping delivers queued datagrams at once, so disconnect notices are not lost.
	relay.configure(NetSimulator.UP, 2000.0)
	client.put_packet(PackedByteArray([7]))
	OS.delay_msec(20)
	var stopped_at := Time.get_ticks_msec()
	relay.stop()
	check(receive(server, 300) == PackedByteArray([7]) and Time.get_ticks_msec() - stopped_at < 300, "Stopping flushes queued datagrams")
	check(not relay.is_running() and relay.listen_port == 0, "The relay stops cleanly")
	var scripted := NetSimulator.new()
	check(scripted.configure_from_args(PackedStringArray(["--netsim-rtt=150", "--netsim-jitter=30", "--netsim-loss=5"])), "Simulator arguments enable the relay")
	check(scripted.conditions(NetSimulator.UP) == {"latency_ms": 75.0, "jitter_ms": 15.0, "loss_percent": 5.0, "duplicate_percent": 0.0}, "Simulator arguments set round-trip conditions")
	check(not NetSimulator.new().configure_from_args(PackedStringArray(["--offline"])), "The relay stays off without simulator arguments")
	server.close()
	client.close()
	print("Network simulator checks: %d passed, %d failed" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)


## Waits up to `timeout_ms` for one datagram.
func receive(socket: PacketPeerUDP, timeout_ms: int) -> PackedByteArray:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if socket.get_available_packet_count() > 0:
			return socket.get_packet()
		pass # Spin: OS sleeps can last a 15.6 ms timer tick on Windows.
	return PackedByteArray()


## Sends `count` datagrams one at a time; returns the sorted delays in ms.
func delays(sender: PacketPeerUDP, receiver: PacketPeerUDP, count: int) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for index in count:
		var sent := Time.get_ticks_usec()
		sender.put_packet(PackedByteArray([index]))
		result.append((Time.get_ticks_usec() - sent) / 1000.0 if not receive(receiver, 1000).is_empty() else INF)
	result.sort()
	return result


## No delay below `low`, and 90% of them at most `high`; the slack absorbs
## occasional scheduler stalls on busy CI machines.
func within(samples: PackedFloat32Array, low: float, high: float) -> bool:
	return samples[0] >= low and NetStats.percentile(samples, 0.9) <= high


## Sends `count` datagrams in small batches and returns how many arrived.
func burst(sender: PacketPeerUDP, receiver: PacketPeerUDP, count: int) -> int:
	var arrived := 0
	for index in count:
		sender.put_packet(PackedByteArray([index & 255, index >> 8]))
		if index % 20 == 19:
			OS.delay_usec(2000)
			while receiver.get_available_packet_count() > 0:
				receiver.get_packet()
				arrived += 1
	var deadline := Time.get_ticks_msec() + 300
	while Time.get_ticks_msec() < deadline:
		while receiver.get_available_packet_count() > 0:
			receiver.get_packet()
			arrived += 1
		OS.delay_usec(500)
	return arrived
