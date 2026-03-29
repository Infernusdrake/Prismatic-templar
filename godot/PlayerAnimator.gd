class_name PlayerAnimator
extends Node

# ── Mixamo drop-in guide ──────────────────────────────────────────────────────
#
#  To swap these procedural capsule animations for real Mixamo rigs:
#
#  1. Download from mixamo.com (Y Bot, FBX for Unity, 30 fps, "without skin"):
#        Idle_Sword.fbx  Walk_Sword.fbx  Sword_Slash.fbx
#        Hit_Reaction.fbx  Dying_Backward.fbx  Dodge_Roll.fbx
#     Also export the Y Bot character mesh as a separate .glb.
#
#  2. Import into Godot: drag into godot/models/. In the Import dock:
#        Animations → Bake FPS 30  |  Animation → Import Rest as RESET
#
#  3. In Player._ready(), replace the CapsuleMesh block with:
#        var model := preload("res://models/YBot.glb").instantiate()
#        model.name = "Body"
#        add_child(model)
#
#  4. In _build_lib() below, replace each _make_*() call with the matching
#     imported AnimationLibrary resource, e.g.:
#        lib.add_animation("idle", _load_fbx_anim(
#            "res://models/Idle_Sword.fbx", "mixamo_com|Idle"))
#
#  5. Mixamo bone paths live under "Body/Armature/Skeleton3D:..." — the
#     AnimationPlayer root_node "../.." already points to Player (CharacterBody3D),
#     so the paths resolve correctly with no extra changes.
#
# ─────────────────────────────────────────────────────────────────────────────

const BODY := "Body"

var _anim:      AnimationPlayer
var _current:   String = ""
var _one_shot:  bool   = false   # true while a non-looping anim is in flight

func _ready() -> void:
	_anim = AnimationPlayer.new()
	_anim.name = "AnimPlayer"
	# Path from AnimPlayer: ".." = PlayerAnimator, "../.." = CharacterBody3D (Player)
	_anim.root_node              = NodePath("../..")
	_anim.playback_default_blend_time = 0.10
	add_child(_anim)
	_anim.animation_finished.connect(_on_finished)

func init() -> void:
	_build_lib()
	_anim.play("idle")
	_current = "idle"

# ─────────────────────────────────────────────────────────────────────────────
#  Public API
# ─────────────────────────────────────────────────────────────────────────────

## Play a looping state animation — will not interrupt a one-shot in progress.
func play(name: String) -> void:
	if _current == name:
		return
	if _one_shot:
		return
	_start(name)

## Play a one-shot animation, interrupting whatever is running.
func force_play(name: String) -> void:
	_one_shot = false   # clear so _start can proceed
	_start(name)

func stop() -> void:
	_anim.stop()
	_current  = ""
	_one_shot = false

# ─────────────────────────────────────────────────────────────────────────────
#  Internal
# ─────────────────────────────────────────────────────────────────────────────

func _start(name: String) -> void:
	if not _anim.has_animation(name):
		return
	_current = name
	var a := _anim.get_animation(name)
	_one_shot = (a != null and a.loop_mode == Animation.LOOP_NONE)
	_anim.play(name)

func _on_finished(_name: StringName) -> void:
	_one_shot = false
	_current  = ""

# ─────────────────────────────────────────────────────────────────────────────
#  Animation library
# ─────────────────────────────────────────────────────────────────────────────

func _build_lib() -> void:
	var lib := AnimationLibrary.new()
	lib.add_animation("idle",      _make_idle())
	lib.add_animation("walk",      _make_walk())
	lib.add_animation("attack_1",  _make_attack(0.35, 0.06, -0.20))
	lib.add_animation("attack_2",  _make_attack(0.35, 0.08, -0.18))
	lib.add_animation("attack_3",  _make_attack_heavy())
	lib.add_animation("hit_react", _make_hit_react())
	lib.add_animation("dodge",     _make_dodge())
	lib.add_animation("death",     _make_death())
	_anim.add_animation_library("", lib)

# ── Idle: gentle breathing bob ────────────────────────────────────────────────
func _make_idle() -> Animation:
	var a := Animation.new()
	a.length = 2.2
	a.loop_mode = Animation.LOOP_LINEAR
	_pos(a, [0.0, 1.1, 2.2],
		[_p(0,0.900,0), _p(0,0.910,0), _p(0,0.900,0)])
	_scl(a, [0.0, 1.1, 2.2],
		[Vector3(1.000,1.000,1.000),
		 Vector3(0.985,1.018,0.985),
		 Vector3(1.000,1.000,1.000)])
	return a

# ── Walk: bouncy step ────────────────────────────────────────────────────────
func _make_walk() -> Animation:
	var a := Animation.new()
	a.length = 0.44
	a.loop_mode = Animation.LOOP_LINEAR
	_pos(a, [0.0, 0.22, 0.44],
		[_p(0,0.885,0), _p(0,0.945,0), _p(0,0.885,0)])
	_scl(a, [0.0, 0.22, 0.44],
		[Vector3(1.06,0.90,1.06),
		 Vector3(0.94,1.10,0.94),
		 Vector3(1.06,0.90,1.06)])
	return a

# ── Light/mid attacks: pull-back then thrust ─────────────────────────────────
func _make_attack(len: float, pullback_z: float, strike_z: float) -> Animation:
	var a := Animation.new()
	a.length = len
	a.loop_mode = Animation.LOOP_NONE
	var wb := len * 0.25   # wind-back peak
	var sp := len * 0.55   # strike peak
	_pos(a, [0.0, wb, sp, len],
		[_p(0,0.900,0.00), _p(0,0.910,pullback_z),
		 _p(0,0.885,strike_z), _p(0,0.900,0.00)])
	_scl(a, [0.0, wb, sp, len],
		[Vector3(1.00,1.00,1.00), Vector3(0.86,1.14,1.22),
		 Vector3(1.22,0.82,0.68), Vector3(1.00,1.00,1.00)])
	return a

# ── Heavy attack: raise high then crash down ─────────────────────────────────
func _make_attack_heavy() -> Animation:
	var a := Animation.new()
	a.length = 0.50
	a.loop_mode = Animation.LOOP_NONE
	_pos(a, [0.0, 0.12, 0.30, 0.50],
		[_p(0,0.900, 0.00), _p(0,1.06, 0.08),
		 _p(0,0.700,-0.26), _p(0,0.900, 0.00)])
	_scl(a, [0.0, 0.12, 0.30, 0.50],
		[Vector3(1.00,1.00,1.00), Vector3(0.80,1.26,0.80),
		 Vector3(1.32,0.66,1.32), Vector3(1.00,1.00,1.00)])
	return a

# ── Hit reaction: squash and shove back ──────────────────────────────────────
func _make_hit_react() -> Animation:
	var a := Animation.new()
	a.length = 0.30
	a.loop_mode = Animation.LOOP_NONE
	_pos(a, [0.0, 0.06, 0.30],
		[_p(0,0.900,0.00), _p(0,0.860,0.18), _p(0,0.900,0.00)])
	_scl(a, [0.0, 0.06, 0.30],
		[Vector3(1.00,1.00,1.00), Vector3(1.30,0.70,1.30), Vector3(1.00,1.00,1.00)])
	return a

# ── Dodge: flatten low and stretch in travel direction ───────────────────────
func _make_dodge() -> Animation:
	var a := Animation.new()
	a.length = 0.35
	a.loop_mode = Animation.LOOP_NONE
	_pos(a, [0.0, 0.17, 0.35],
		[_p(0,0.900,0), _p(0,0.580,0), _p(0,0.900,0)])
	_scl(a, [0.0, 0.17, 0.35],
		[Vector3(1.00,1.00,1.00), Vector3(1.40,0.68,1.40), Vector3(1.00,1.00,1.00)])
	return a

# ── Death: float then crumple ─────────────────────────────────────────────────
func _make_death() -> Animation:
	var a := Animation.new()
	a.length = 0.80
	a.loop_mode = Animation.LOOP_NONE
	_pos(a, [0.0, 0.20, 0.80],
		[_p(0,0.900,0), _p(0,1.050,0), _p(0,0.030,0)])
	_scl(a, [0.0, 0.20, 0.80],
		[Vector3(1.00,1.00,1.00), Vector3(1.10,1.10,1.10), Vector3(1.40,0.04,1.40)])
	return a

# ── Track helpers ─────────────────────────────────────────────────────────────

func _pos(anim: Animation, times: Array, keys: Array) -> void:
	var t := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(t, BODY)
	for i in times.size():
		anim.position_track_insert_key(t, times[i], keys[i])

func _scl(anim: Animation, times: Array, keys: Array) -> void:
	var t := anim.add_track(Animation.TYPE_SCALE_3D)
	anim.track_set_path(t, BODY)
	for i in times.size():
		anim.scale_track_insert_key(t, times[i], keys[i])

func _p(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z)
