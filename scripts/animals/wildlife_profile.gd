extends RefCounted
## Species blueprint plus a per-animal personality for ATHAR wildlife.
##
## A profile is plain data: sensing ranges, how long the animal remembers a
## threat, how quickly it settles, and the distance at which it commits to
## flight. The deer blueprint is the only one shipped in this phase, but the
## class is species-agnostic: a future animal passes its own blueprint and gets
## the same sensing, memory and personality model for free.
##
## Personality never changes movement speeds or the detection floor, so the
## hunt stays fair and the existing balance tests keep their meaning. Traits only
## shift perception and patience within a bounded band (see TRAITS).

## Named temperaments. Every multiplier is >= 0.74, so no archetype can make an
## animal blind or fearless; they only shade how it reads the world.
##
## Sight *range* is deliberately not a trait: DETECT_RADIUS is a tuned gameplay
## distance, and temperaments must not silently move it. They shift the field of
## view, hearing, memory, patience and the distance at which an animal commits to
## flight, all inside a bounded band.
const ARCHETYPES := ["steady", "cautious", "bold", "nervous"]

const TRAITS := {
	"steady": {"fov": 1.00, "hearing": 1.00, "memory": 1.00, "recovery": 1.00, "confirm": 0.82},
	"cautious": {"fov": 1.03, "hearing": 1.05, "memory": 1.30, "recovery": 1.35, "confirm": 0.90},
	"bold": {"fov": 0.93, "hearing": 0.92, "memory": 0.80, "recovery": 0.85, "confirm": 0.74},
	"nervous": {"fov": 1.00, "hearing": 1.18, "memory": 1.10, "recovery": 1.15, "confirm": 0.86},
}

## Jitter applied on top of the archetype, so two "cautious" deer are still
## different animals. Small enough that it cannot cross a fairness boundary.
const TRAIT_JITTER := 0.06

var species := ""
var archetype := "steady"
## Furthest distance at which the animal can identify a threat by sight.
var vision_range := 13.0
## Horizontal field of view in degrees, centred on the facing direction. Deer
## have wide-set eyes, so this stays panoramic and only leaves a rear blind arc.
var vision_angle := 300.0
## Inside this radius a moving threat is noticed regardless of facing: it is
## too close to miss. Kept below vision_range so the field of view still matters.
var proximity_range := 10.0
## Furthest distance at which a running threat can be heard. Quiet movement
## carries only about a third of this far; see wildlife_perception.gd.
var hearing_range := 18.0
## Seconds a threat stays in memory after it is last seen or heard.
var memory_time := 6.0
## Seconds spent returning to normal behaviour before grazing again.
var recovery_time := 4.0
## Inside this distance the animal commits to flight instead of investigating.
var confirm_distance := 10.6
## Sightings nearer than this while walking make the animal look, not run.
var investigate_distance := 7.0


## Fills the profile from a species blueprint, then rolls one deterministic
## personality from `rng`. The same generator and seed always gives the same
## animal; call it once, in the animal's constructor.
func setup(species_name: String, blueprint: Dictionary, rng: RandomNumberGenerator) -> void:
	species = species_name
	vision_range = float(blueprint.get("vision_range", vision_range))
	vision_angle = float(blueprint.get("vision_angle", vision_angle))
	proximity_range = float(blueprint.get("proximity_range", proximity_range))
	hearing_range = float(blueprint.get("hearing_range", hearing_range))
	memory_time = float(blueprint.get("memory_time", memory_time))
	recovery_time = float(blueprint.get("recovery_time", recovery_time))
	investigate_distance = float(blueprint.get("investigate_distance", investigate_distance))
	_roll(rng)


## Chooses an archetype and shades its traits. Called once, at construction.
func _roll(rng: RandomNumberGenerator) -> void:
	archetype = ARCHETYPES[rng.randi_range(0, ARCHETYPES.size() - 1)]
	var traits: Dictionary = TRAITS[archetype]
	vision_angle = clampf(vision_angle * float(traits["fov"]), 200.0, 340.0)
	hearing_range = hearing_range * float(traits["hearing"]) * _jitter(rng)
	memory_time = memory_time * float(traits["memory"]) * _jitter(rng)
	recovery_time = maxf(1.0, recovery_time * float(traits["recovery"]) * _jitter(rng))
	confirm_distance = vision_range * float(traits["confirm"])
	investigate_distance = minf(investigate_distance, confirm_distance - 1.0)


func _jitter(rng: RandomNumberGenerator) -> float:
	return 1.0 + rng.randf_range(-TRAIT_JITTER, TRAIT_JITTER)


## Short human-readable summary, used by the HUD status line and the tests.
func describe() -> String:
	return "%s (%s): sight %.1f m, hearing %.1f m, memory %.1f s" % [
		species, archetype, vision_range, hearing_range, memory_time,
	]
