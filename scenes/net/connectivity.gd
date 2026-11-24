class_name Connectivity
extends Node
## Makes a hosted party reachable from other people's PCs without a VPN or a server of our own:
##   1. asks the router to open the game's UDP port (UPnP, like most PC games do)
##   2. finds the public IPv4 address (and IPv6, if the internet connection has one)
##   3. turns that into an invite code friends paste into the Join box
##   4. announces the party on the local network so people in the same house just click it
## Lives under the Net autoload as Net.link.

signal host_info_changed
signal lan_games_changed

const LAN_PORT := 24681

var hosting := false
var invite_short := ""      # ABCDE-FGHIJ
var invite_full := ""       # with the LAN and IPv6 parts (what "Copy invite" copies)
var router_ok := false      # the port was opened on the router
var router_msg := "Checking your router..."
var public_v4 := ""
var public_v6 := ""
var lan_v4 := ""
var cgnat := false
var lan_games := {}         # "ip" -> {name, players, port, seen}

var _thread: Thread
var _upnp: UPNP
var _udp_out: PacketPeerUDP
var _udp_in: PacketPeerUDP
var _beacon_t := 0.0
var _router_ext := ""
var _http4: HTTPRequest
var _http6: HTTPRequest

func _process(delta: float) -> void:
	if hosting and _udp_out != null:
		_beacon_t -= delta
		if _beacon_t <= 0.0:
			_beacon_t = 1.0
			_beacon()
	if _udp_in != null:
		var changed := false
		while _udp_in.get_available_packet_count() > 0:
			var pkt := _udp_in.get_packet()
			var ip := _udp_in.get_packet_ip()
			var d: Variant = JSON.parse_string(pkt.get_string_from_utf8())
			if d is Dictionary and int((d as Dictionary).get("wh", 0)) == 1:
				changed = changed or not lan_games.has(ip)
				lan_games[ip] = {"name": str(d.get("name", "?")).left(24), "players": int(d.get("n", 1)),
					"port": int(d.get("port", Net.PORT)), "ver": str(d.get("ver", "")), "seen": Time.get_ticks_msec()}
		for k in lan_games.keys():
			if Time.get_ticks_msec() - int(lan_games[k]["seen"]) > 4000:
				lan_games.erase(k)
				changed = true
		if changed:
			lan_games_changed.emit()

# ======================================================================= hosting
func start_host() -> void:
	hosting = true
	router_ok = false
	cgnat = false
	public_v4 = ""
	public_v6 = ""
	_router_ext = ""
	router_msg = "Opening a port on your router..."
	lan_v4 = _pick_lan_v4()
	for a in IP.get_local_addresses():
		if Invite.is_global_v6(a) and public_v6 == "":
			public_v6 = a
	_update_code()
	# the router (UPnP discovery blocks for a couple of seconds, so it runs on a thread)
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = Thread.new()
	_thread.start(_upnp_open)
	# what the internet sees us as
	_http4 = _ask("https://api.ipify.org", _got_v4)
	_http6 = _ask("https://api64.ipify.org", _got_v6)
	# shout about the party on the local network
	_udp_out = PacketPeerUDP.new()
	_udp_out.set_broadcast_enabled(true)
	_udp_out.set_dest_address("255.255.255.255", LAN_PORT)
	_beacon_t = 0.0

func stop_host() -> void:
	if not hosting:
		return
	hosting = false
	if _udp_out != null:
		_udp_out.close()
		_udp_out = null
	for h in [_http4, _http6]:
		if is_instance_valid(h):
			(h as Node).queue_free()
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	if router_ok and _upnp != null:
		var u := _upnp
		_thread = Thread.new()
		_thread.start(func(): u.delete_port_mapping(Net.PORT, "UDP"))
	router_ok = false
	invite_short = ""
	invite_full = ""

func _upnp_open() -> void:
	var u := UPNP.new()
	var err := u.discover(2500, 2, "InternetGatewayDevice")
	var ok := false
	var ext := ""
	var msg := ""
	if err != UPNP.UPNP_RESULT_SUCCESS or u.get_gateway() == null or not u.get_gateway().is_valid_gateway():
		msg = "Couldn't find your router (UPnP may be switched off on it)"
	else:
		var r := u.add_port_mapping(Net.PORT, Net.PORT, "Wobbly Hours", "UDP", 0)
		if r == UPNP.UPNP_RESULT_SUCCESS:
			ok = true
			msg = "Router port %d opened automatically" % Net.PORT
		else:
			msg = "Your router refused to open port %d (UPnP error %d)" % [Net.PORT, r]
		ext = u.query_external_address()
	call_deferred("_upnp_done", u, ok, ext, msg)

func _upnp_done(u: UPNP, ok: bool, ext: String, msg: String) -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	if not hosting:
		if ok:
			u.delete_port_mapping(Net.PORT, "UDP")
		return
	_upnp = u
	router_ok = ok
	router_msg = msg
	_router_ext = ext
	if ext != "" and Invite.is_cgnat(ext):
		cgnat = true
	if public_v4 == "" and ext != "" and not Invite.is_private_v4(ext):
		public_v4 = ext
	_update_code()

func _ask(url: String, cb: Callable) -> HTTPRequest:
	var h := HTTPRequest.new()
	h.timeout = 6.0
	add_child(h)
	h.request_completed.connect(func(result: int, code: int, _hd: PackedStringArray, body: PackedByteArray):
		h.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			cb.call(body.get_string_from_utf8().strip_edges()))
	if h.request(url) != OK:
		h.queue_free()
		return null
	return h

func _got_v4(ip: String) -> void:
	if not hosting or not ip.is_valid_ip_address() or ip.contains(":"):
		return
	public_v4 = ip
	# the router's outside address isn't the one the internet sees: the provider shares it (CGNAT)
	if _router_ext != "" and _router_ext != ip:
		cgnat = true
	_update_code()

func _got_v6(ip: String) -> void:
	if not hosting or not Invite.is_global_v6(ip):
		return
	public_v6 = ip
	_update_code()

func _update_code() -> void:
	invite_short = ""
	invite_full = ""
	var main_v4 := public_v4 if public_v4 != "" else lan_v4
	if main_v4 != "":
		invite_full = Invite.make(main_v4, Net.PORT, lan_v4, public_v6)
		invite_short = invite_full.get_slice(".", 0)
	host_info_changed.emit()

## Lines for the host to read: how reachable the party is, and what to do if it isn't.
func status_lines() -> Array[String]:
	var l: Array[String] = []
	l.append(("OK: " if router_ok else "!! ") + router_msg)
	if public_v6 != "":
		l.append("OK: you have IPv6, so friends who also have it can join even without the router port")
	if cgnat:
		l.append("!! Your internet provider shares your IP with other homes (CGNAT): friends on IPv4 can't reach you. Ask your provider for a public IP, use IPv6, or let a friend host.")
	elif not router_ok:
		l.append("If friends can't join: forward UDP port %d to this PC (%s) in your router settings, or have someone else host." % [Net.PORT, lan_v4 if lan_v4 != "" else "this PC"])
	l.append("Windows may ask to allow Wobbly Hours through the firewall: click Allow (tick both Private and Public).")
	return l

func _beacon() -> void:
	var n := str(Net.players.get(1, {}).get("name", "Someone"))
	var msg := JSON.stringify({"wh": 1, "name": n + "'s party", "n": Net.players.size(), "port": Net.PORT, "ver": GameVersion.VERSION})
	_udp_out.put_packet(msg.to_utf8_buffer())

## Our address on the home network (skips VPN adapters like Hamachi 25.x / Radmin 26.x).
func _pick_lan_v4() -> String:
	var best := ""
	for a in IP.get_local_addresses():
		if a.contains(":") or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		if a.begins_with("192.168.") or a.begins_with("10.") or (a.begins_with("172.") and Invite.is_private_v4(a)):
			if best == "" or a.begins_with("192.168."):
				best = a
	return best

# ===================================================================== finding games
func listen_lan() -> void:
	if _udp_in != null:
		return
	_udp_in = PacketPeerUDP.new()
	if _udp_in.bind(LAN_PORT) != OK:
		_udp_in = null   # (another copy of the game is already listening)

func stop_listening() -> void:
	if _udp_in != null:
		_udp_in.close()
		_udp_in = null
	lan_games.clear()

func _exit_tree() -> void:
	stop_host()
	stop_listening()
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
