extends RefCounted
## Three graphics presets that mean something on an Android phone.
##
## The project renders at `mobile` quality with a 3D viewport that is already
## smaller than the screen on a phone. The only levers that matter there are the
## internal 3D resolution, whether the sun casts shadows at all, and the shadow
## atlas — so those are exactly what the presets change. Everything is applied
## through the live [Viewport] and [DirectionalLight3D], so a change takes effect
## immediately without rebuilding the world, and a headless test can inspect the
## result without a renderer.

const QUALITY_LOW := "low"
const QUALITY_MEDIUM := "medium"
const QUALITY_HIGH := "high"

const PRESETS := {
	QUALITY_LOW: {"scale": 0.72, "shadows": false, "msaa": Viewport.MSAA_DISABLED, "atlas": 1024},
	QUALITY_MEDIUM: {"scale": 0.85, "shadows": true, "msaa": Viewport.MSAA_DISABLED, "atlas": 2048},
	QUALITY_HIGH: {"scale": 1.0, "shadows": true, "msaa": Viewport.MSAA_2X, "atlas": 4096},
}


static func preset(level: String) -> Dictionary:
	if PRESETS.has(level):
		return (PRESETS[level] as Dictionary).duplicate()
	return (PRESETS[QUALITY_MEDIUM] as Dictionary).duplicate()


## Applies `level` and returns what was actually set, which the tests compare
## against the preset table.
static func apply(level: String, viewport: Viewport, sun: DirectionalLight3D) -> Dictionary:
	var chosen := preset(level)
	if viewport != null:
		viewport.scaling_3d_scale = float(chosen["scale"])
		viewport.msaa_3d = int(chosen["msaa"])
	if sun != null:
		sun.shadow_enabled = bool(chosen["shadows"])
	if bool(chosen["shadows"]):
		RenderingServer.directional_shadow_atlas_set_size(int(chosen["atlas"]), true)
	return chosen


## Human-readable key for the active level, so the UI never shows a raw "low".
static func label_key(level: String) -> String:
	return "settings.quality.%s" % (level if PRESETS.has(level) else QUALITY_MEDIUM)
