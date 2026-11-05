extends RefCounted
## ATHAR's melee combat rules: attacks, dodge, block and stamina.
##
## This is pure logic with no scene nodes, so the combat suite can step it
## headless and assert exact timings. The hunter rig only reacts to it, and
## main.gd decides what a landed hit does to the world.
##
## Design notes:
##   - Every action is affordable in stamina or it is refused; nothing is
##     "queued" silently, so a touch always gets an answer.
##   - Attacks have three phases (windup, active, recovery). Only the active
##     window can hit anything, which is what makes spacing matter.
##   - A dodge makes the hunter invulnerable for its middle section and costs
##     stamina, so it cannot be spammed.
##   - Blocking is a held state: it soaks most damage but drains stamina, and a
##     hit that arrives with no stamina left breaks the guard.
##
## The controller never touches the player's position; main.gd moves the body.

signal state_changed(previous: String, current: String)
signal attack_started(kind: String)
signal attack_window(kind: String)
signal attack_finished(kind: String)
signal dodged
signal block_broken
signal hit_taken(amount: float, blocked: bool)

const MAX_STAMINA := 100.0
const STAMINA_REGEN := 24.0
## Seconds after spending stamina before regeneration starts.
const REGEN_DELAY := 0.55

const COST_LIGHT := 11.0
const COST_HEAVY := 24.0
const COST_DODGE := 17.0
## Stamina drained per second while the guard is held.
const BLOCK_DRAIN := 7.0
## Stamina taken by a blocked hit.
const BLOCK_IMPACT := 9.0
## Fraction of incoming damage stopped by a raised guard.
const BLOCK_REDUCTION := 0.8

## Phase lengths in seconds: windup, active window, recovery.
const LIGHT := {"windup": 0.16, "active": 0.12, "recover": 0.30, "damage": 18.0, "reach": 2.0}
const HEAVY := {"windup": 0.34, "active": 0.16, "recover": 0.52, "damage": 34.0, "reach": 2.3}
const DODGE := {"duration": 0.55, "invulnerable_from": 0.06, "invulnerable_to": 0.38}
const HIT_STUN := 0.34

const IDLE := "idle"
const LIGHT_STATE := "light"
const HEAVY_STATE := "heavy"
const DODGE_STATE := "dodge"
const HIT_STATE := "hit"
const DEAD_STATE := "dead"

var stamina := MAX_STAMINA
var health := 100.0
var state := IDLE
## Current attack definition while state is light/heavy.
var attack: Dictionary = {}
## Time spent in the current state.
var elapsed := 0.0
var blocking := false
var aiming := false
## Set for one frame when the active window opens; main.gd consumes it.
var hit_pending := false
var hit_kind := ""

var _cooldown := 0.0
var _regen_hold := 0.0


func update(delta: float) -> void:
	elapsed += delta
	_cooldown = maxf(0.0, _cooldown - delta)
	if _regen_hold > 0.0:
		_regen_hold -= delta
	elif not blocking:
		stamina = minf(MAX_STAMINA, stamina + STAMINA_REGEN * delta)
	if blocking:
		stamina = maxf(0.0, stamina - BLOCK_DRAIN * delta)
		if stamina <= 0.0:
			_set_blocking(false)
			block_broken.emit()
	match state:
		LIGHT_STATE, HEAVY_STATE:
			_advance_attack()
		DODGE_STATE:
			if elapsed >= float(DODGE["duration"]):
				_set_state(IDLE)
		HIT_STATE:
			if elapsed >= HIT_STUN:
				_set_state(IDLE)
	if aiming and state == IDLE:
		return


func _advance_attack() -> void:
	var windup := float(attack["windup"])
	var active := float(attack["active"])
	var recover := float(attack["recover"])
	if elapsed >= windup and elapsed < windup + active and not hit_pending and hit_kind == "":
		hit_pending = true
		hit_kind = state
		attack_window.emit(state)
	elif elapsed >= windup + active and elapsed < windup + active + recover:
		if hit_kind != "":
			# The window has passed; a later swing must open a new one.
			hit_kind = ""
	elif elapsed >= windup + active + recover:
		attack_finished.emit(state)
		attack = {}
		_set_state(IDLE)


## Starts a light attack. Returns false when it cannot start (stamina, state).
func request_light() -> bool:
	return _start_attack(LIGHT_STATE, LIGHT, COST_LIGHT)


func request_heavy() -> bool:
	return _start_attack(HEAVY_STATE, HEAVY, COST_HEAVY)


func _start_attack(kind: String, definition: Dictionary, cost: float) -> bool:
	if state in [DEAD_STATE, HIT_STATE, DODGE_STATE, LIGHT_STATE, HEAVY_STATE]:
		return false
	if stamina < cost:
		return false
	stamina -= cost
	_regen_hold = REGEN_DELAY
	attack = definition
	hit_pending = false
	hit_kind = ""
	_set_state(kind)
	attack_started.emit(kind)
	return true


## Rolls out of the way. Returns false when the hunter cannot dodge.
func request_dodge() -> bool:
	if state in [DEAD_STATE, HIT_STATE, DODGE_STATE, LIGHT_STATE, HEAVY_STATE]:
		return false
	if stamina < COST_DODGE:
		return false
	stamina -= COST_DODGE
	_regen_hold = REGEN_DELAY
	_set_state(DODGE_STATE)
	dodged.emit()
	return true


func is_invulnerable() -> bool:
	return state == DODGE_STATE and elapsed >= float(DODGE["invulnerable_from"]) and elapsed <= float(DODGE["invulnerable_to"])


func is_attacking() -> bool:
	return state in [LIGHT_STATE, HEAVY_STATE]


## "windup", "active", "recover" or "" for the current attack.
func attack_phase() -> String:
	if not is_attacking() or attack.is_empty():
		return ""
	var windup := float(attack["windup"])
	if elapsed < windup:
		return "windup"
	if elapsed < windup + float(attack["active"]):
		return "active"
	return "recover"


func current_reach() -> float:
	return float(attack.get("reach", 0.0))


func current_damage() -> float:
	return float(attack.get("damage", 0.0))


## Applies an incoming hit. Returns "dodged", "blocked", "hit" or "ignored".
func take_hit(amount: float) -> String:
	if state == DEAD_STATE:
		return "ignored"
	if is_invulnerable():
		return "dodged"
	var blocked := blocking and stamina > 0.0
	if blocked:
		stamina = maxf(0.0, stamina - BLOCK_IMPACT)
		_regen_hold = REGEN_DELAY
		health = maxf(0.0, health - amount * (1.0 - BLOCK_REDUCTION))
		hit_taken.emit(amount, true)
		if stamina <= 0.0:
			_set_blocking(false)
			block_broken.emit()
	else:
		health = maxf(0.0, health - amount)
		hit_taken.emit(amount, false)
		if health > 0.0:
			attack = {}
			hit_pending = false
			hit_kind = ""
			_set_state(HIT_STATE)
	if health <= 0.0:
		_set_state(DEAD_STATE)
		return "hit"
	return "blocked" if blocked else "hit"


func set_blocking(value: bool) -> void:
	if state in [DEAD_STATE, DODGE_STATE, HIT_STATE]:
		value = false
	_set_blocking(value)


func _set_blocking(value: bool) -> void:
	if blocking == value:
		return
	blocking = value
	if value:
		aiming = false


func set_aiming(value: bool) -> void:
	aiming = value
	if value:
		_set_blocking(false)


func is_dead() -> bool:
	return state == DEAD_STATE


func heal_full() -> void:
	health = 100.0
	stamina = MAX_STAMINA
	attack = {}
	_set_state(IDLE)


func _set_state(next: String) -> void:
	if state == next:
		elapsed = 0.0
		return
	var previous := state
	state = next
	elapsed = 0.0
	state_changed.emit(previous, next)
