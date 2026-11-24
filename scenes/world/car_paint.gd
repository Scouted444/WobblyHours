class_name CarPaint
extends RefCounted
## Colours of the toy car. Change these two lines to repaint it (any Color works, e.g. Color.html("#ffcc00")).
## BODY also sets the darker trim (side skirts, mudguards, dashboard) automatically.

const BODY := Color(0.85, 0.12, 0.1)    # red
const ROOF := Color(0.95, 0.95, 0.95)   # white

## Repaint the car's materials named "body", "body_dark" and "roof" (keeps their texture and shine).
static func apply(root: Node) -> void:
	var want := {"body": BODY, "body_dark": BODY.darkened(0.3), "roof": ROOF}
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if mat == null or not want.has(String(mat.resource_name)):
				continue
			var m2 := mat.duplicate() as BaseMaterial3D
			m2.albedo_color = want[String(mat.resource_name)]
			mi.set_surface_override_material(i, m2)
