extends Node3D
## ATHAR's deer: a genuine, rigged and animated glTF animal.
##
## The Phase 3 deer was assembled from capsules and spheres and posed by hand.
## This rig loads the Quaternius "Stag" (CC0, 38 bones, 14 clips; see
## assets/models/ASSET_MANIFEST.json) and drives it with a small animation state
## machine, so grazing, walking, bolting and dying are real skeletal animation.
##
## The rig is presentation only: behaviour (grazing, detection, fleeing) lives in
## scripts/animals/deer_ai.gd. It reads no random numbers, so seeded worlds stay
## identical, and it never builds a substitute body: if the asset is missing the
## deer is invisible and `missing_reason` says why.

const ModelAsset := preload("res://scripts/visuals/model_asset.gd")

const MODEL_PATH := "res://assets/models/animals/stag.glb"
## Shoulder height of a mature stag, in metres. The collision capsule in
## main.gd is built around this.
const HEIGHT := 1.55
const WALK_SPEED := 1.6
const GALLOP_SPEED := 6.4
const FADE := 0.2

const CLIP_GRAZE := "Eating"
const CLIP_IDLE := "Idle"
const CLIP_IDLE_UP := "Idle_2"
const CLIP_HEAD_LOW := "Idle_Headlow"
const CLIP_WALK := "Walk"
const CLIP_GALLOP := "Gallop"
const CLIP_DEATH := "Death"
const CLIP_HIT := "Idle_HitReact_Left"
const CLIP_KICK := "Attack_Kick"

## Behaviour state -> the clip that state should hold when the animal is still.
const STATE_CLIPS := {
	"GRAZING": CLIP_GRAZE,
	"WANDERING": CLIP_IDLE,
	"OBSERVING": CLIP_IDLE,
	"RESTING": CLIP_HEAD_LOW,
	"RETURNING": CLIP_IDLE,
	"INVESTIGATING": CLIP_IDLE_UP,
	"ALERTED": CLIP_IDLE_UP,
	"FLEEING": CLIP_GALLOP,
	"ESCAPING": CLIP_GALLOP,
	"CAPTURED": CLIP_DEATH,
}

var model: Node3D
var skeleton: Skeleton3D
var player: AnimationPlayer
var animation_tree: AnimationTree
var missing_reason := ""
var model_ready := false
var current_clip := ""

var _playback: AnimationNodeStateMachinePlayback
## Short clip name -> imported animation name ("Armature|Walk" and friends).
var _clips := {}
var _state := "GRAZING"
var _gait := ""
var _dead := false


func _ready() -> void:
	_build()


func is_ready() -> bool:
	return model_ready


func _build() -> void:
	if model_ready or missing_reason != "":
		return
	var result := ModelAsset.load_model(MODEL_PATH, HEIGHT)
	if not result.ok:
		missing_reason = result.reason
		push_warning("ATHAR deer model unavailable: %s" % missing_reason)
		return
	model = result.root
	model.name = "Model"
	add_child(model)
	skeleton = result.skeleton
	player = result.player
	_build_state_machine()
	model_ready = true
	_play(CLIP_GRAZE)


func _build_state_machine() -> void:
	if player == null:
		return
	for name in player.get_animation_list():
		var bar := String(name).find("|")
		var short := String(name).substr(bar + 1) if bar >= 0 else String(name)
		_clips[short] = String(name)
	animation_tree = AnimationTree.new()
	animation_tree.name = "AnimationTree"
	add_child(animation_tree)
	animation_tree.anim_player = animation_tree.get_path_to(player)
	var sm := AnimationNodeStateMachine.new()
	var added: Array[String] = []
	for clip in [CLIP_GRAZE, CLIP_IDLE, CLIP_IDLE_UP, CLIP_HEAD_LOW, CLIP_WALK, CLIP_GALLOP, CLIP_DEATH, CLIP_HIT]:
		if not _clips.has(clip):
			continue
		var node := AnimationNodeAnimation.new()
		node.animation = String(_clips[clip])
		sm.add_node(clip, node)
		added.append(clip)
	# The deer can change state in any direction, so every pair of states that
	# exists gets a transition. get_node_list() is deliberately not used: the
	# state machine also holds the built-in Start/End nodes, and transitioning
	# from/to those is invalid.
	for from in added:
		for to in added:
			if from == to:
				continue
			var t := AnimationNodeStateMachineTransition.new()
			t.xfade_time = 0.35 if (from == CLIP_DEATH or to == CLIP_DEATH) else FADE
			sm.add_transition(from, to, t)
	animation_tree.tree_root = sm
	animation_tree.active = true
	_playback = animation_tree.get("parameters/playback")


func _play(clip_name: String) -> void:
	if player == null or not _clips.has(clip_name):
		return
	current_clip = clip_name
	if _playback != null:
		_playback.travel(clip_name)
	else:
		player.play(String(_clips[clip_name]))


## Behaviour hint from deer_ai.gd. Only the pose changes; movement decisions are
## made by the AI, not here.
func set_state(state: String) -> void:
	if _state == state:
		return
	_state = state
	if _dead:
		return
	_apply_state()


func _apply_state() -> void:
	if not model_ready or _dead:
		return
	var still: String = STATE_CLIPS.get(_state, CLIP_IDLE)
	_set_gait(still, 1.0)


## Advances the pose. `speed` is the planar speed in metres per second; the gait
## follows the real speed, so a bolting deer gallops and a strolling one walks.
func animate(delta: float, speed: float) -> void:
	if not model_ready or _dead:
		return
	var clip_name := ""
	if speed > GALLOP_SPEED * 0.45:
		clip_name = CLIP_GALLOP
	elif speed > 0.18:
		clip_name = CLIP_WALK
	else:
		clip_name = String(STATE_CLIPS.get(_state, CLIP_IDLE))
	if clip_name == CLIP_GALLOP:
		_set_gait(clip_name, clampf(speed / GALLOP_SPEED, 0.75, 1.35))
	elif clip_name == CLIP_WALK:
		_set_gait(clip_name, clampf(speed / WALK_SPEED, 0.6, 1.4))
	else:
		_set_gait(clip_name, 1.0)
	# A grazer lifts its head now and then; the asset's own Idle_2 clip provides
	# that gesture, so no hand-made pose is needed.
	if _state == "GRAZING" and speed < 0.1 and player != null:
		player.speed_scale = 1.0


func _set_gait(clip_name: String, speed_scale: float) -> void:
	if _gait != clip_name:
		_gait = clip_name
		_play(clip_name)
	if player != null:
		player.speed_scale = speed_scale


func play_death() -> void:
	if not model_ready:
		return
	_dead = true
	_gait = CLIP_DEATH
	if player != null and _clips.has(CLIP_DEATH):
		current_clip = CLIP_DEATH
		player.speed_scale = 1.0
		if _playback != null:
			_playback.travel(CLIP_DEATH)
		else:
			player.play(String(_clips[CLIP_DEATH]))


## Clip names this asset actually provides, for the asset/tests report.
func clip_names() -> PackedStringArray:
	if player == null:
		return PackedStringArray()
	return player.get_animation_list()
