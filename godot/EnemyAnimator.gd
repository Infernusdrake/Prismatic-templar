class_name EnemyAnimator
extends Node

# ── Mixamo drop-in guide ──────────────────────────────────────────────────────
#
#  To swap these procedural capsule animations for real Mixamo rigs:
#
#  1. Download from mixamo.com (Y Bot, FBX for Unity, 30 fps, "without skin"):
#        Idle.fbx  Walk.fbx  Sword_Slash.fbx  Sword_Slash_2.fbx
#        Sweep_Attack.fbx  Hit_Reaction.fbx  Dying_Backward.fbx
#     Also export the Y Bot character mesh as a separate .glb.
#
#  2. Import into Godot: drag into godot/models/. In the Import dock:
#        Animations → Bake FPS 30  |  Import Rest as RESET
#
#  3. In Enemy._ready(), replace the CapsuleMesh block with:
#        var model := preload("res://models/YBot.glb").instantiate()
#        model.name = "Body"
#        add_child(model)
#
#  4. In _build_lib() below, replace each _make_*() with loaded FBX anims:
#        lib.add_animation("windup_heavy",
#            _fbx("res://models/Sweep_Attack.fbx", "mixamo_com|Sweep_Attack"))
#     Helper to load one animation from an FBX AnimationLibrary:
#        func _fbx(path: String, name: String) -> Animation:
#            return ResourceLoader.load(path).get_animation(name)
#
#  5. If the Y Bot model needs mirroring (facing +Z), set model.rotation.y = PI.
#
# ─────────────────────────────────────────────────────────────────────────────

const BODY := "Body"

var _anim:     AnimationPlayer
var _current:  String = ""
var _one_shot: bool   = false

func _ready() -> void:
	_anim = AnimationPlayer.new()
	_anim.name = "AnimPlayer"
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

func play(name: String) -> void:
	if _current == name:
		return
	if _one_shot:
		return
	_start(name)

func force_play(name: String) -> void:
	_one_shot = false
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
	lib.add_animation("idle",          _make_idle())
	lib.add_animation("walk",          _make_walk())
	lib.add_animation("windup_light",  _make_windup(0.55,  0.08, 0.06))
	lib.add_animation("attack_light",  _make_strike(0.30, -0.28))
	lib.add_animation("windup_heavy",  _make_windup(1.30,  0.18, 0.10))
	lib.add_animation("attack_heavy",  _make_strike_heavy())
	lib.add_animation("windup_combo",  _make_windup(0.45,  0.06, 0.05))
	lib.add_animation("attack_combo",  _make_strike(0.25, -0.22))
	lib.add_animation("hit_react",     _make_hit_react())
	lib.add_animation("stagger",       _make_stagger())
	lib.add_animation("death",         _make_death())
	_anim.add_animation_library("", lib)

# ── Idle: slow weight sway ────────────────────────────────────────────────────
func _make_idle() -> Animation:
	var a := Animation.new()
	a.length = 2.6
	a.loop_mode = Animation.LOOP_LINEAR
	_pos(a, [0.0, 1.3, 2.6],
		[_p(0,0.900,0), _p(0,0.892,0), _p(0,0.900,0)])
	_scl(a, [0.0, 0.65, 1.3, 1.95, 2.6],
		[Vector3(1.00,1.00,1.00), Vector3(1.02,0.98,0.97),
		 Vector3(1.00,1.00,1.00), Vector3(0.97,0.98,1.02),
		 Vector3(1.00,1.00,1.00)])
	return a

# ── Walk: heavy stomp ────────────────────────────────────────────────────────
func _make_walk() -> Animation:
	var a := Animation.new()
	a.length = 0.50
	a.loop_mode = Animation.LOOP_LINEAR
	_pos(a, [0.0, 0.25, 0.50],
		[_p(0,0.870,0), _p(0,0.940,0), _p(0,0.870,0)])
	_scl(a, [0.0, 0.25, 0.50],
		[Vector3(1.08,0.88,1.08), Vector3(0.93,1.12,0.93), Vector3(1.08,0.88,1.08)])
	return a

# ── Windup: lean back and coil ────────────────────────────────────────────────
func _make_windup(len: float, raise_y: float, pullback_z: float) -> Animation:
	var a := Animation.new()
	a.length = len
	a.loop_mode = Animation.LOOP_NONE
	_pos(a, [0.0, len * 0.7, len],
		[_p(0,0.900,0.00), _p(0,0.900 + raise_y, pullback_z), _p(0,0.900+raise_y,pullback_z)])
	_scl(a, [0.0, len * 0.7, len],
		[Vector3(1.00,1.00,1.00), Vector3(0.84,1.22,0.84), Vector3(0.82,1.25,0.82)])
	return a

# ── Light/combo strike: lunge forward ────────────────────────────────────────
func _make_strike(len: float, strike_z: float) -> Animation:
	var a := Animation.new()
	a.length = len
	a.loop_mode = Animation.LOOP_NONE
	var sp := len * 0.45
	_pos(a, [0.0, sp, len],
		[_p(0,0.900,0.00), _p(0,0.880,strike_z), _p(0,0.900,0.00)])
	_scl(a, [0.0, sp, len],
		[Vector3(1.00,1.00,1.00), Vector3(1.28,0.74,0.72), Vector3(1.00,1.00,1.00)])
	return a

# ── Heavy strike: massive overhead slam ──────────────────────────────────────
func _make_strike_heavy() -> Animation:
	var a := Animation.new()
	a.length = 0.45
	a.loop_mode = Animation.LOOP_NONE
	_pos(a, [0.0, 0.20, 0.45],
		[_p(0,1.00,0.10), _p(0,0.650,-0.32), _p(0,0.900,0.00)])
	_scl(a, [0.0, 0.20, 0.45],
		[Vector3(0.82,1.25,0.82), Vector3(1.40,0.58,1.40), Vector3(1.00,1.00,1.00)])
	return a

# ── Hit reaction: stagger back ───────────────────────────────────────────────
func _make_hit_react() -> Animation:
	var a := Animation.new()
	a.length = 0.28
	a.loop_mode = Animation.LOOP_NONE
	_pos(a, [0.0, 0.07, 0.28],
		[_p(0,0.900,0.00), _p(0,0.880,0.20), _p(0,0.900,0.00)])
	_scl(a, [0.0, 0.07, 0.28],
		[Vector3(1.00,1.00,1.00), Vector3(1.26,0.72,1.26), Vector3(1.00,1.00,1.00)])
	return a

# ── Parry stagger: slow reel backwards ───────────────────────────────────────
func _make_stagger() -> Animation:
	var a := Animation.new()
	a.length = 1.80
	a.loop_mode = Animation.LOOP_NONE
	_pos(a, [0.0, 0.15, 0.60, 1.80],
		[_p(0,0.900,0.00), _p(0,0.840,0.35),
		 _p(0,0.840,0.40), _p(0,0.900,0.00)])
	_scl(a, [0.0, 0.15, 0.60, 1.80],
		[Vector3(1.00,1.00,1.00), Vector3(1.24,0.72,1.24),
		 Vector3(1.10,0.85,1.10), Vector3(1.00,1.00,1.00)])
	return a

# ── Death: crumple to ground ──────────────────────────────────────────────────
func _make_death() -> Animation:
	var a := Animation.new()
	a.length = 0.80
	a.loop_mode = Animation.LOOP_NONE
	_pos(a, [0.0, 0.22, 0.80],
		[_p(0,0.900,0), _p(0,1.060,0), _p(0,0.030,0)])
	_scl(a, [0.0, 0.22, 0.80],
		[Vector3(1.00,1.00,1.00), Vector3(1.12,1.12,1.12), Vector3(1.40,0.04,1.40)])
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
