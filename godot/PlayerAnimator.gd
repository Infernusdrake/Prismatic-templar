class_name PlayerAnimator
extends Node

# ── Quaternius glTF animation names ──────────────────────────────────────────
const ANIM_IDLE   := "Idle"
const ANIM_WALK   := "Walk"
const ANIM_ATTACK := "SwordSlash"
const ANIM_HIT    := "RecieveHit"
const ANIM_DEATH  := "Death"

# ── Node refs ─────────────────────────────────────────────────────────────────
var _tree:     AnimationTree                     = null
var _playback: AnimationNodeStateMachinePlayback = null

# ─────────────────────────────────────────────────────────────────────────────
#  Setup — called when this node enters the tree (parent already added model)
# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_tree = AnimationTree.new()
	_tree.name = "AnimTree"
	# PlayerAnimator lives at  Player/PlayerAnimator
	# AnimTree lives at        Player/PlayerAnimator/AnimTree
	# Model lives at           Player/CharacterArmature
	# AnimationPlayer lives at Player/CharacterArmature/AnimationPlayer
	_tree.anim_player = NodePath("../../CharacterArmature/AnimationPlayer")
	add_child(_tree)

func init() -> void:
	_build_state_machine()
	_tree.active = true
	_playback = _tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if _playback:
		_playback.travel(ANIM_IDLE)

# ─────────────────────────────────────────────────────────────────────────────
#  Public API  (same surface as the old procedural PlayerAnimator)
# ─────────────────────────────────────────────────────────────────────────────

## Play a looping state animation.  Will not interrupt an in-flight one-shot.
func play(name: String) -> void:
	if _playback == null:
		return
	var target := _map(name)
	if target == "":
		return
	var cur := _playback.get_current_node()
	# Don't cut away from one-shot states (attack, react, death) mid-play
	if cur in [&"Attack", &"HitReact", &"Death"]:
		return
	if cur == target:
		return
	_playback.travel(target)

## Override: plays immediately regardless of current state.
func force_play(name: String) -> void:
	if _playback == null:
		return
	var target := _map(name)
	if target != "":
		_playback.travel(target)

## Stop the AnimationTree (used before finisher tweens take control).
func stop() -> void:
	if _tree:
		_tree.active = false

# ─────────────────────────────────────────────────────────────────────────────
#  Internal helpers
# ─────────────────────────────────────────────────────────────────────────────

func _map(name: String) -> String:
	match name:
		"idle":                              return ANIM_IDLE
		"walk":                              return ANIM_WALK
		"attack_1", "attack_2", "attack_3":  return ANIM_ATTACK
		"hit_react":                         return ANIM_HIT
		"dodge":                             return ANIM_IDLE   # no Roll state in SM
		"death":                             return ANIM_DEATH
		_:                                   return ""

func _build_state_machine() -> void:
	var sm := AnimationNodeStateMachine.new()

	# ── States ────────────────────────────────────────────────────────────────
	var n_idle   := AnimationNodeAnimation.new(); n_idle.animation   = ANIM_IDLE
	var n_walk   := AnimationNodeAnimation.new(); n_walk.animation   = ANIM_WALK
	var n_attack := AnimationNodeAnimation.new(); n_attack.animation = ANIM_ATTACK
	var n_hit    := AnimationNodeAnimation.new(); n_hit.animation    = ANIM_HIT
	var n_death  := AnimationNodeAnimation.new(); n_death.animation  = ANIM_DEATH

	sm.add_node("Idle",     n_idle,   Vector2(  0,   0))
	sm.add_node("Walk",     n_walk,   Vector2(200,   0))
	sm.add_node("Attack",   n_attack, Vector2(400,   0))
	sm.add_node("HitReact", n_hit,    Vector2(200, 180))
	sm.add_node("Death",    n_death,  Vector2(  0, 180))

	# ── Transitions ───────────────────────────────────────────────────────────
	# Idle ↔ Walk  (velocity-driven by Player code)
	_tr(sm, "Idle",     "Walk",     0.15, false)
	_tr(sm, "Walk",     "Idle",     0.15, false)

	# Idle / Walk → Attack  (attack trigger)
	_tr(sm, "Idle",     "Attack",   0.05, false)
	_tr(sm, "Walk",     "Attack",   0.05, false)

	# Attack → Idle  (auto-return after swing completes)
	_tr(sm, "Attack",   "Idle",     0.10, true)

	# Any → HitReact  (damage)
	for src: String in ["Idle", "Walk", "Attack", "Death"]:
		_tr(sm, src,    "HitReact", 0.05, false)

	# HitReact → Idle  (auto-return after reaction finishes)
	_tr(sm, "HitReact", "Idle",     0.10, true)

	# Any → Death  (health zero)
	for src: String in ["Idle", "Walk", "Attack", "HitReact"]:
		_tr(sm, src,    "Death",    0.10, false)

	_tree.tree_root = sm

func _tr(sm: AnimationNodeStateMachine, from: String, to: String,
		xfade: float, at_end: bool) -> void:
	var t := AnimationNodeStateMachineTransition.new()
	t.switch_mode = (AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
			if at_end else AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE)
	t.xfade_time = xfade
	sm.add_transition(from, to, t)
