class_name Invite
## Invite codes: a short, typo-proof way to share "where my game is" without reading out IP addresses.
##
##   ABCDE-FGHIJ                      public IPv4 + port (the short code people read out)
##   ABCDE-FGHIJ.KLMNOPQ              ... + the host's address on its own network (same-house players)
##   ABCDE-FGHIJ.KLMNOPQ.<26 chars>   ... + the host's IPv6 address (often works with no port forwarding)
##
## Plain addresses still work in the join box too: 25.34.12.7, 1.2.3.4:24680, [2001:db8::1]:24680.

const ALPHA := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"   # Crockford base32: no I, L, O, U

## Make the code. lan4 / v6 can be "" when unknown.
static func make(pub4: String, port: int, lan4 := "", v6 := "") -> String:
	var b := _v4_bytes(pub4)
	if b.is_empty():
		b = _v4_bytes(lan4)
	if b.is_empty():
		return ""
	b.append((port >> 8) & 0xFF)
	b.append(port & 0xFF)
	var code := _b32(b)
	code = code.substr(0, 5) + "-" + code.substr(5)
	var l := _v4_bytes(lan4)
	if not l.is_empty() and lan4 != pub4:
		code += "." + _b32(l)
	elif v6 != "":
		code += "."
	var s6 := _v6_bytes(v6)
	if not s6.is_empty():
		code += "." + _b32(s6)
	return code

## Everything to try for whatever was typed in the join box: [{host, port}] in the best order
## (IPv6 first, it needs no port forwarding; the host's LAN address last).
static func candidates(text: String, default_port: int) -> Array:
	var t := text.strip_edges()
	var out: Array = []
	if t.is_empty():
		return out
	# a plain address?
	if t.begins_with("["):   # [v6]:port
		var close := t.find("]")
		if close > 0:
			var port := default_port
			if t.substr(close + 1).begins_with(":"):
				port = int(t.substr(close + 2))
			out.append({"host": t.substr(1, close - 1), "port": port})
			return out
	if t.count(":") >= 2 and t.is_valid_ip_address():
		out.append({"host": t, "port": default_port})
		return out
	var host_part := t.get_slice(":", 0)
	if host_part.is_valid_ip_address() or (host_part.contains(".") and not host_part.contains("-")):
		var p := default_port
		if t.contains(":"):
			p = int(t.get_slice(":", 1))
		out.append({"host": host_part, "port": p if p > 0 and p < 65536 else default_port})
		return out
	# an invite code
	var parts := t.to_upper().replace(" ", "").split(".")
	var main := _unb32(parts[0].replace("-", ""), 6)
	if main.size() != 6:
		return out
	var port2 := (int(main[4]) << 8) | int(main[5])
	var v4 := "%d.%d.%d.%d" % [main[0], main[1], main[2], main[3]]
	if parts.size() > 2 and parts[2] != "":
		var v6b := _unb32(parts[2], 16)
		if v6b.size() == 16:
			out.append({"host": _v6_string(v6b), "port": port2})
	out.append({"host": v4, "port": port2})
	if parts.size() > 1 and parts[1] != "":
		var lb := _unb32(parts[1], 4)
		if lb.size() == 4:
			out.append({"host": "%d.%d.%d.%d" % [lb[0], lb[1], lb[2], lb[3]], "port": port2})
	return out

# ------------------------------------------------------------------ addresses
static func _v4_bytes(ip: String) -> PackedByteArray:
	var b := PackedByteArray()
	var p := ip.strip_edges().split(".")
	if p.size() != 4:
		return b
	for x in p:
		if not x.is_valid_int() or int(x) < 0 or int(x) > 255:
			return PackedByteArray()
		b.append(int(x))
	return b

static func _v6_bytes(ip: String) -> PackedByteArray:
	var s := ip.strip_edges()
	if s == "" or not s.contains(":"):
		return PackedByteArray()
	if s.contains("%"):
		s = s.get_slice("%", 0)
	var head := s
	var tail := ""
	if s.contains("::"):
		head = s.get_slice("::", 0)
		tail = s.get_slice("::", 1)
	var hg := head.split(":", false)
	var tg := tail.split(":", false)
	if not s.contains("::") and hg.size() != 8:
		return PackedByteArray()
	var groups: Array = []
	for g in hg:
		groups.append(g)
	for i in 8 - hg.size() - tg.size():
		groups.append("0")
	for g2 in tg:
		groups.append(g2)
	if groups.size() != 8:
		return PackedByteArray()
	var b := PackedByteArray()
	for g3 in groups:
		var h := str(g3)
		if h.length() > 4 or not h.is_valid_hex_number():
			return PackedByteArray()
		var v := h.hex_to_int()
		b.append((v >> 8) & 0xFF)
		b.append(v & 0xFF)
	return b

static func _v6_string(b: PackedByteArray) -> String:
	var g: Array[String] = []
	for i in 8:
		g.append("%x" % ((int(b[i * 2]) << 8) | int(b[i * 2 + 1])))
	return ":".join(g)

## A public (internet-routable) IPv6 address: global unicast 2000::/3.
static func is_global_v6(ip: String) -> bool:
	if not ip.contains(":"):
		return false
	var first := ip.strip_edges().to_lower()
	return first.begins_with("2") or first.begins_with("3")

## A private / shared address that people outside can't reach directly.
static func is_private_v4(ip: String) -> bool:
	var b := _v4_bytes(ip)
	if b.size() != 4:
		return true
	return b[0] == 10 or b[0] == 127 or (b[0] == 172 and b[1] >= 16 and b[1] <= 31) or (b[0] == 192 and b[1] == 168) \
		or (b[0] == 100 and b[1] >= 64 and b[1] <= 127) or (b[0] == 169 and b[1] == 254)

## Carrier-grade NAT (the internet provider shares one address between many homes).
static func is_cgnat(ip: String) -> bool:
	var b := _v4_bytes(ip)
	return b.size() == 4 and b[0] == 100 and b[1] >= 64 and b[1] <= 127

# ------------------------------------------------------------------ base32
static func _b32(b: PackedByteArray) -> String:
	var out := ""
	var acc := 0
	var bits := 0
	for byte in b:
		acc = ((acc << 8) | int(byte)) & 0xFFFF
		bits += 8
		while bits >= 5:
			bits -= 5
			out += ALPHA[(acc >> bits) & 31]
	if bits > 0:
		out += ALPHA[(acc << (5 - bits)) & 31]
	return out

static func _unb32(s: String, nbytes: int) -> PackedByteArray:
	var out := PackedByteArray()
	var acc := 0
	var bits := 0
	for ch in s:
		var c := ch.to_upper()
		if c == "O":
			c = "0"
		elif c == "I" or c == "L":
			c = "1"
		var v := ALPHA.find(c)
		if v < 0:
			return PackedByteArray()
		acc = ((acc << 5) | v) & 0xFFFFFF
		bits += 5
		if bits >= 8:
			bits -= 8
			out.append((acc >> bits) & 0xFF)
	if out.size() < nbytes:
		return PackedByteArray()
	return out.slice(0, nbytes)
