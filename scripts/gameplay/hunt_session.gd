extends RefCounted
## One hunt: capture bookkeeping and the repeatable hunt loop.
##
## Kept separate from the scene so the "exactly once" rules are testable without
## a renderer. The scene asks try_capture() every physics frame; only the first
## successful call fires deer_captured, so no duplicate capture feedback, HUD
## updates or hunt restarts can occur.

signal deer_captured
signal hunt_started(index: int)

## Centre-to-centre distance at which reaching the deer counts as a capture.
## The hunter capsule is 0.40 m and the deer capsule 0.45 m, so their surfaces
## touch near 0.85 m; 1.8 m is a forgiving reach while still requiring contact.
const CAPTURE_DISTANCE := 1.8

var capture_distance := CAPTURE_DISTANCE
var is_captured := false
var capture_count := 0
var hunt_index := 1


func distance_in_reach(distance: float) -> bool:
	return distance <= capture_distance


## Captures the deer if it is in reach. Returns true only for the single
## successful capture of the current hunt.
func try_capture(distance: float) -> bool:
	if is_captured:
		return false
	if not distance_in_reach(distance):
		return false
	is_captured = true
	capture_count += 1
	deer_captured.emit()
	return true


## Starts the next hunt. Returns false unless the previous deer was captured.
func begin_new_hunt() -> bool:
	if not is_captured:
		return false
	is_captured = false
	hunt_index += 1
	hunt_started.emit(hunt_index)
	return true
