extends Node3D
## ATHAR's hunter: a genuine, rigged and animated glTF character.
##
## Phase 3 animated a body assembled from Godot primitives. That model had no
## real anatomy: shoulders were spheres, limbs were capsules and the cloak was a
## cone, which is why it read as a distorted toy at camera distance. This rig
## replaces it with a licensed 3D character (Quaternius "Adventurer", CC0, see
## assets/models/ASSET_MANIFEST.json) that ships with a 62-bone skeleton and 24
## animation clips.
##
## What the rig still owns, and what it deliberately does not:
##
##   - It is presentation only. Movement, stamina and combat rules live in
##     scripts/main.gd and scripts/gameplay/combat_controller.gd.
##   - It reads no random numbers, so the seeded world layout is unchanged.
##   - It never builds a substitute body. If the asset is missing the hunter is
##     simply invisible, `missing_reason` explains why, and the game keeps
##     running (see RegionTests / CombatTests "missing model" checks).
##
## The clips ATHAR needs but the Adventurer asset does not contain (a dedicated
## bow draw, a crouch, a jump and a shield block) are approximated by the closest
## clip the asset does have, and every approximation is listed in
## assets/models/ASSET_MANIFEST.json so it is never reported as a real clip.

const ModelAsset := preload("res://scripts/visuals/model_asset.gd")
const U := preload("res://scripts/visuals/rig_utils.gd")

const MODEL_PATH := "res://assets/models/characters/adventurer.glb"
## Real-world height of the hunter in metres, matching the collision capsule.
const HEIGHT := 1.80
## Planar speeds the walk and run clips were authored for. Playback is scaled
## from these so the feet do not skate.
const WALK_SPEED := 1.45
const RUN_SPEED := 5.2
## Cross-fade used between locomotion states, in seconds.
const LOCOMOTION_FADE := 0.18

## Clip names (short form, exporter prefixes stripped).
const CLIP_IDLE := "Idle"
const CLIP_WALK := "Walk"
const CLIP_RUN := "Run"
const CLIP_ROLL := "Roll"
const CLIP_LIGHT := "Sword_Slash"
const CLIP_HEAVY := "Punch_Right"
const CLIP_HIT := "HitRecieve"
const CLIP_DEATH := "Death"
const CLIP_AIM := "Idle_Gun_Pointing"
const CLIP_BLOCK := "Idle_Sword"
const CLIP_INTERACT := "Interact"

## One-shot actions, mapping the game's action name to a clip.
const ACTIONS := {
	"roll": CLIP_ROLL,
	"light": CLIP_LIGHT,
	"heavy": CLIP_HEAVY,
	"hit": CLIP_HIT,
	"death": CLIP_DEATH,
	"interact": CLIP_INTERACT,
	"aim": CLIP_AIM,
}

## Hunter palette applied over the imported flat colours, so the character sits
## in ATHAR's dark wilderness tones instead of the asset's default green.
const PALETTE := [
	{"match": "black", "color": Color(0.07, 0.065, 0.075), "roughness": 0.7},
	{"match": "grey", "color": Color(0.30, 0.30, 0.32), "roughness": 0.6},
	{"match": "brown2", "color": Color(0.13, 0.10, 0.075), "roughness": 0.95},
	{"match": "brown", "color": Color(0.22, 0.155, 0.105), "roughness": 0.95},
	{"match": "lightgreen", "color": Color(0.28, 0.32, 0.24), "roughness": 0.95},
	{"match": "green", "color": Color(0.16, 0.19, 0.155), "roughness": 0.98},
	{"match": "hair", "color": Color(0.16, 0.11, 0.075), "roughness": 0.95},
	{"match": "gold", "color": Color(0.66, 0.51, 0.24), "roughness": 0.4, },
]

var model: Node3D
var skeleton: Skeleton3D
var player: AnimationPlayer
var animation_tree: AnimationTree
var missing_reason := ""
var model_ready := false
## Clip that was requested most recently; tests and the HUD read this.
var current_clip := ""

var _playback: AnimationNodeStateMachinePlayback
## Short clip name -> the animation name inside the imported AnimationPlayer.
## glTF keeps an exporter prefix ("CharacterArmature|Idle"), so every lookup
## goes through this table instead of guessing the prefix.
var _clips := {}
var _one_shot := ""
var _one_shot_until := 0.0
var _materials := {}
var _blocking := false
var _aiming := false
var _dead := false
var _gait_state := "Idle"


func _ready() -> void:
	_build()


func is_ready() -> bool:
	return model_ready


## Loads the asset. Safe to call twice; the second call is ignored.
func _build() -> void:
	if model_ready or missing_reason != "":
		return
	var result := ModelAsset.load_model(MODEL_PATH, HEIGHT)
	if not result.ok:
		missing_reason = result.reason
		push_warning("ATHAR hunter model unavailable: %s" % missing_reason)
		return
	model = result.root
	model.name = "Model"
	add_child(model)
	skeleton = result.skeleton
	player = result.player
	ModelAsset.recolour(model, PALETTE)
	_hide_expensive_shadows(model)
	_attach_gear()
	_build_state_machine()
	model_ready = true
	_play("Idle")


## Small props that read as a wilderness hunter: the bow and quiver are attached
## to the skeleton's hands/back rather than drawn into the imported mesh, so a
## future weapon swap only replaces the prop.
func _attach_gear() -> void:
	var hand := _bone_with("hand", "r")
	if hand < 0:
		hand = _bone_with("hand", "")
	if hand >= 0:
		var attach := BoneAttachment3D.new()
		attach.name = "BowHand"
		attach.bone_idx = hand
		skeleton.add_child(attach)
		# An armature authored in centimetres scales its bones by 100, and a
		# BoneAttachment3D inherits that scale: without this correction the bow
		# would be a hundred times too big. The attachment is scaled back to
		# metres so the prop's own dimensions mean what they say.
		var bone_scale: Vector3 = skeleton.get_bone_global_rest(hand).basis.get_scale()
		attach.scale = Vector3.ONE / maxf(bone_scale.x, 0.0001)
		_build_bow(attach)
	var spine := _bone_with("spine", "")
	if spine < 0:
		spine = _bone_with("chest", "")
	if spine >= 0:
		var quiver_attach := BoneAttachment3D.new()
		quiver_attach.name = "QuiverMount"
		quiver_attach.bone_idx = spine
		skeleton.add_child(quiver_attach)
		var spine_scale: Vector3 = skeleton.get_bone_global_rest(spine).basis.get_scale()
		quiver_attach.scale = Vector3.ONE / maxf(spine_scale.x, 0.0001)
		_build_quiver(quiver_attach)


func _bone_with(fragment: String, side: String) -> int:
	if skeleton == null:
		return -1
	for i in range(skeleton.get_bone_count()):
		var name := skeleton.get_bone_name(i).to_lower()
		if name.find(fragment) >= 0 and (side == "" or name.ends_with(side)):
			return i
	return -1


func _build_bow(parent: Node3D) -> void:
	var pivot := U.pivot(parent, "Bow", Vector3(0.02, 0.0, 0.0))
	pivot.rotation_degrees = Vector3(0, 0, 12)
	var wood := U.material(_materials, Color(0.26, 0.17, 0.10), 0.7)
	var string_mat := U.material(_materials, Color(0.80, 0.77, 0.66), 0.6)
	var tips := [Vector3(0, -0.42, 0.02), Vector3(0, -0.24, -0.06), Vector3(0, 0.0, -0.09), Vector3(0, 0.24, -0.06), Vector3(0, 0.42, 0.02)]
	for i in range(tips.size() - 1):
		U.strut(pivot, tips[i], tips[i + 1], 0.014, wood)
	U.strut(pivot, tips[0], tips[4], 0.004, string_mat)
	U.part(pivot, U.tapered(0.022, 0.022, 0.13, 8), U.material(_materials, Color(0.16, 0.12, 0.08), 0.9), Vector3(0, 0, -0.085))


func _build_quiver(parent: Node3D) -> void:
	var pivot := U.pivot(parent, "Quiver", Vector3(-0.13, 0.16, 0.08))
	pivot.rotation_degrees = Vector3(8, 0, -28)
	var leather := U.material(_materials, Color(0.19, 0.13, 0.09), 0.9)
	U.part(pivot, U.tapered(0.062, 0.052, 0.34, 8), leather, Vector3.ZERO)
	for i in range(3):
		var a := (i - 1) * 0.03
		U.strut(pivot, Vector3(a, 0.15, 0), Vector3(a * 1.2, 0.32, 0.01), 0.006, U.material(_materials, Color(0.30, 0.20, 0.12), 0.7))
		U.part(pivot, U.box(Vector3(0.02, 0.045, 0.01)), U.material(_materials, Color(0.66, 0.51, 0.24), 0.5), Vector3(a * 1.2, 0.34, 0.01))


## Skinned characters do not need per-part shadows at this scale on a phone; the
## capsule still casts one, and disabling the per-surface shadow keeps the
## mobile renderer from drawing the character a second time.
func _hide_expensive_shadows(root: Node) -> void:
	for child in root.get_children():
		if child is MeshInstance3D:
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_hide_expensive_shadows(child)


func _build_state_machine() -> void:
	if player == null:
		return
	_clips = _catalogue(player)
	animation_tree = AnimationTree.new()
	animation_tree.name = "AnimationTree"
	add_child(animation_tree)
	animation_tree.anim_player = animation_tree.get_path_to(player)
	var sm := AnimationNodeStateMachine.new()
	var added: Array[String] = []
	for clip in [CLIP_IDLE, CLIP_WALK, CLIP_RUN, CLIP_ROLL, CLIP_LIGHT, CLIP_HEAVY, CLIP_HIT, CLIP_DEATH, CLIP_AIM, CLIP_BLOCK, CLIP_INTERACT]:
		if not _clips.has(clip):
			continue
		var node := AnimationNodeAnimation.new()
		node.animation = String(_clips[clip])
		sm.add_node(clip, node)
		added.append(clip)
	# Only transitions between states that actually exist are added: a missing
	# clip must not leave a dangling transition, which Godot reports as an error.
	for clip in added:
		if clip != CLIP_IDLE and added.has(CLIP_IDLE):
			sm.add_transition(clip, CLIP_IDLE, _transition(0.22))
	for pair in [[CLIP_IDLE, CLIP_WALK], [CLIP_WALK, CLIP_RUN], [CLIP_RUN, CLIP_WALK]]:
		if added.has(pair[0]) and added.has(pair[1]):
			sm.add_transition(pair[0], pair[1], _transition(LOCOMOTION_FADE))
	animation_tree.tree_root = sm
	animation_tree.active = true
	_playback = animation_tree.get("parameters/playback")
	player.animation_finished.connect(_on_animation_finished)


func _transition(xfade: float) -> AnimationNodeStateMachineTransition:
	var t := AnimationNodeStateMachineTransition.new()
	t.xfade_time = xfade
	t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
	return t


## Maps short clip names ("Idle") to the names the importer produced
## ("CharacterArmature|Idle"). The prefix is whatever the exporter wrote, so it
## is read from the file rather than hard-coded.
static func _catalogue(anim_player: AnimationPlayer) -> Dictionary:
	var table := {}
	for name in anim_player.get_animation_list():
		var bar := String(name).find("|")
		var short := String(name).substr(bar + 1) if bar >= 0 else String(name)
		table[short] = String(name)
	return table


func _play(clip_name: String) -> void:
	if player == null or not _clips.has(clip_name):
		return
	current_clip = clip_name
	if _playback != null:
		_playback.travel(clip_name)
	else:
		player.play(String(_clips[clip_name]))


## Chooses idle/walk/run from the planar speed. One-shot actions keep priority
## until their clip finishes, so an attack is never cut off by movement.
func animate(delta: float, speed: float) -> void:
	if not model_ready:
		return
	if _dead:
		return
	if _one_shot != "":
		_one_shot_until -= delta
		if _one_shot_until > 0.0:
			return
		_one_shot = ""
	if _aiming:
		_set_gait(CLIP_AIM, 1.0)
		return
	if _blocking:
		_set_gait(CLIP_BLOCK, 1.0)
		return
	if speed < 0.12:
		_set_gait(CLIP_IDLE, 1.0)
	elif speed < WALK_SPEED * 1.35:
		_set_gait(CLIP_WALK, clampf(speed / WALK_SPEED, 0.55, 1.45))
	else:
		_set_gait(CLIP_RUN, clampf(speed / RUN_SPEED, 0.7, 1.5))


func _set_gait(clip_name: String, playback_speed: float) -> void:
	if _gait_state != clip_name:
		_gait_state = clip_name
		_play(clip_name)
	if player != null:
		player.speed_scale = playback_speed


## Plays a one-shot action. Returns false when the asset cannot provide it.
func play_action(action: String) -> bool:
	if not model_ready or _dead:
		return false
	var clip_name: String = ACTIONS.get(action, "")
	if clip_name == "" or player == null or not _clips.has(clip_name):
		return false
	_one_shot = action
	_one_shot_until = player.get_animation(String(_clips[clip_name])).length
	player.speed_scale = 1.0
	current_clip = clip_name
	if _playback != null:
		_playback.travel(clip_name)
	return true


## True while a one-shot action is still playing.
func action_active() -> bool:
	return _one_shot != ""


func play_death() -> void:
	if not model_ready:
		return
	_dead = true
	_one_shot = ""
	if player != null and _clips.has(CLIP_DEATH):
		current_clip = CLIP_DEATH
		player.speed_scale = 1.0
		if _playback != null:
			_playback.travel(CLIP_DEATH)
		else:
			player.play(String(_clips[CLIP_DEATH]))


func revive() -> void:
	_dead = false
	_one_shot = ""
	_play(CLIP_IDLE)


func set_blocking(value: bool) -> void:
	_blocking = value


func set_aiming(value: bool) -> void:
	_aiming = value


func is_blocking() -> bool:
	return _blocking


func is_aiming() -> bool:
	return _aiming


func _on_animation_finished(clip_name: String) -> void:
	var short := clip_name
	var bar := short.find("|")
	if bar >= 0:
		short = short.substr(bar + 1)
	if _dead and short == CLIP_DEATH:
		return
	if short in ACTIONS.values() or short == CLIP_HEAVY:
		_one_shot = ""
