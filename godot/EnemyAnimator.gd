class_name EnemyAnimator
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
#  Setup
# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_tree = AnimationTree.new()
	_tree.name = "AnimTree"
	# EnemyAnimator lives at  Enemy/EnemyAnimator
	# AnimTree lives at       Enemy/EnemyAnimator/AnimTree
	# Model lives at          Enemy/CharacterArmature
	# AnimationPlayer lives at Enemy/CharacterArmature/AnimationPlayer
	_tree.anim_player = NodePath("../../CharacterArmature/AnimationPlayer")
	add_child(_tree)

func init() -> void:
	_build_state_machine()
	_tree.active = true
	_playback = _tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if _playback:
		_playback.travel(ANIM_IDLE)

# ─────────────────────────────────────────────────────────────────────────────
#  Public API
# ─────────────────────────────────────────────────────────────────────────────

func play(name: String) -> void:
	if _playback == null:
		return
	var target := _map(name)
	if target == "":
		return
	var cur := _playback.get_current_node()
	if cur in [&"Attack", &"HitReact", &"Death"]:
		return
	if cur == target:
		return
	_playback.travel(target)

func force_play(name: String) -> void:
	if _playback == null:
		return
	var target := _map(name)
	if target != "":
		_playback.travel(target)

func stop() -> void:
	if _tree:
		_tree.active = false

# ─────────────────────────────────────────────────────────────────────────────
#  Internal
# ─────────────────────────────────────────────────────────────────────────────

func _map(name: String) -> String:
	match name:
		"idle":                                       return ANIM_IDLE
		"walk":                                       return ANIM_WALK
		# Windup phases hold Idle pose; the orb/ring telegraph handles the cue
		"windup_light", "windup_heavy", "windup_combo": return ANIM_IDLE
		"attack_light", "attack_heavy", "attack_combo": return ANIM_ATTACK
		"hit_react", "stagger":                       return ANIM_HIT
		"death":                                      return ANIM_DEATH
		_:                                            return ""

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
	_tr(sm, "Idle",     "Walk",     0.15, false)
	_tr(sm, "Walk",     "Idle",     0.15, false)
	_tr(sm, "Idle",     "Attack",   0.05, false)
	_tr(sm, "Walk",     "Attack",   0.05, false)
	_tr(sm, "Attack",   "Idle",     0.10, true)
	for src: String in ["Idle", "Walk", "Attack", "Death"]:
		_tr(sm, src,    "HitReact", 0.05, false)
	_tr(sm, "HitReact", "Idle",     0.10, true)
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
