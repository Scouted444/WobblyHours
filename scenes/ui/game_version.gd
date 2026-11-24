class_name GameVersion
extends RefCounted
## The game's version (compiled in, so exported builds know it too). Bumped with every update.
const VERSION := "1.26"
const DATE := "2026-11-23"

## Compare "1.23" style versions: >0 if a is newer than b.
static func compare(a: String, b: String) -> int:
	var pa := a.strip_edges().split(" ")[0].split(".")
	var pb := b.strip_edges().split(" ")[0].split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return 1 if x > y else -1
	return 0
