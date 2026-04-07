class_name Player
extends CharacterBody3D

# ── Movement ──────────────────────────────────────────────────────────────────
const SPEED        := 5.0
const GRAVITY      := 9.8
const DODGE_SPEED  := 14.0
const DODGE_DURATION := 0.35
const DODGE_COOLDOWN := 0.8

# ── Attack combo ──────────────────────────────────────────────────────────────
const ATTACK_DAMAGE    := [8.0,  8.0,  18.0]
const ATTACK_POSTURE   := [10.0, 12.0, 28.0]
const ATTACK_DURATION  := [0.35, 0.35, 0.50]
const ATTACK_HIT_FRAME := [0.15, 0.15, 0.22]

# ── Opener (cinematic pre-combat sequence) ────────────────────────────────────
const OPENER_KILL_THRESHOLD := 0.60   # instant kill if enemy health ≤ 60 %
const OPENER_DAMAGE         := 30.0
const OPENER_POSTURE        := 50.0
const OPENER_MOVE_SPEED     := 7.0
const OPENER_RANGE          := 2.2

# ── Parry ─────────────────────────────────────────────────────────────────────
const PARRY_ACTIVE_DURATION := 0.42   # how long the window stays open
const PARRY_COOLDOWN        := 0.65   # lockout after any parry attempt / expiry
const PARRY_BLOCK_REDUCTION := 0.55   # fraction of damage absorbed on a block
const PARRY_BONUS_POSTURE   := 40.0   # extra posture damage on punish hit
const PARRY_BONUS_WINDOW    := 3.5    # seconds to land the punish hit

# ── Ranged attack ─────────────────────────────────────────────────────────────
const RANGED_DAMAGE     := 15.0
const RANGED_RANGE      := 25.0
const RANGED_COOLDOWN_T := 0.6
const RANGED_MIN_HOLD   := 0.1

enum ParryState { NONE, ACTIVE, COOLDOWN }

# ── State vars ────────────────────────────────────────────────────────────────
var health     := 100.0
var max_health := 100.0

var is_dodging     := false
var is_invincible  := false
var dodge_timer    := 0.0
var dodge_cooldown := 0.0
var dodge_dir      := Vector3.ZERO

var combo_index    := 0
var is_attacking   := false
var attack_timer   := 0.0
var combo_buffer   := false
var hit_registered := false

var parry_state        := ParryState.NONE
var parry_timer        := 0.0
var _parry_is_windup   := false   # true if parry was pressed during enemy WINDUP
var _parry_miss_grace  := 0.0    # non-zero after window expires; shows MISS on next hit
var parry_bonus_active := false
var parry_bonus_timer  := 0.0

var locked_on      := false
var lock_on_target: Node3D = null

# ── Opener state ──────────────────────────────────────────────────────────────
var input_frozen:    bool    = false
var _opener_active:  bool    = false
var _opener_target:  Node3D  = null
var _opener_stage:   int     = 0     # 0=move  1=attack  2=pause
var _opener_timer:   float   = 0.0

# ── References (set by Arena) ─────────────────────────────────────────────────
var enemy:      Node3D = null
var camera_rig: Node3D = null

# ── Visuals ───────────────────────────────────────────────────────────────────
var _mesh:         MeshInstance3D
var _mat:          StandardMaterial3D
var _parry_shield: MeshInstance3D
var _parry_smat:   StandardMaterial3D
var _parry_tw:     Tween = null
var _animator:     PlayerAnimator = null

# ── Ranged visuals ────────────────────────────────────────────────────────────
var _ranged_holding:   bool  = false
var _ranged_hold_time: float = 0.0
var _ranged_cooldown:  float = 0.0
var _charge_orb:   MeshInstance3D    = null
var _charge_mat:   StandardMaterial3D = null
var _flash_layer:  CanvasLayer        = null
var _flash_rect:   ColorRect          = null

# ── Hit-stop (full time-scale freeze, restored by a real-time SceneTreeTimer) ─
# _hit_stop_end_ms removed — restoration is now handled by the timer callback.

# ── Signals ───────────────────────────────────────────────────────────────────
signal health_changed(val: float, max_val: float)
signal died
signal parry_result(result: String)                       # "perfect" | "block" | "miss"
signal punish_window_changed(active: bool, dur: float)
signal opener_finished

# ─────────────────────────────────────────────────────────────────────────────
#  Setup
# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	# _mat kept as a dummy — existing flash-tween calls still compile and run
	# harmlessly on a material not applied to any visible surface.
	_mat  = StandardMaterial3D.new()
	# _mesh kept as a dummy reference for code that reads/tweens it.
	# It is intentionally NOT added to the scene tree.
	_mesh = MeshInstance3D.new()
	_mesh.name = "Body"

	# ── Quaternius glTF character (Kael / Ninja) ──────────────────────────────
	var gltf := load("res://assets/characters/Ninja_Male_Hair.glTF")
	if gltf:
		var inst: Node3D = gltf.instantiate()
		inst.name = "CharacterArmature"
		add_child(inst)

	# ── Collision capsule (unchanged) ─────────────────────────────────────────
	var col := CollisionShape3D.new()
	var cs  := CapsuleShape3D.new()
	cs.radius = 0.4
	cs.height = 1.8
	col.shape = cs
	col.position.y = 0.9
	add_child(col)

	# ── Chest glow — dark red OmniLight with heartbeat pulse ──────────────────
	var chest_light := OmniLight3D.new()
	chest_light.position     = Vector3(0, 1.0, 0)
	chest_light.light_color  = Color.from_string("#8B1A1A", Color.RED)
	chest_light.light_energy = 0.8
	chest_light.omni_range   = 1.5
	add_child(chest_light)
	var pulse_tw := create_tween().set_loops()
	pulse_tw.tween_property(chest_light, "light_energy", 0.6, 0.6)
	pulse_tw.tween_property(chest_light, "light_energy", 1.0, 0.6)

	# ── Animator — must be added AFTER the model so AnimationPlayer exists ────
	_animator = PlayerAnimator.new()
	add_child(_animator)
	_animator.init()

	# Parry shield bubble (sphere that wraps the capsule)
	_parry_smat = StandardMaterial3D.new()
	_parry_smat.albedo_color              = Color(0.5, 0.85, 1.0, 0.25)
	_parry_smat.emission_enabled          = true
	_parry_smat.emission                  = Color(0.5, 0.85, 1.0)
	_parry_smat.emission_energy_multiplier = 1.8
	_parry_smat.transparency             = BaseMaterial3D.TRANSPARENCY_ALPHA
	_parry_smat.cull_mode                = BaseMaterial3D.CULL_DISABLED
	_parry_smat.shading_mode             = BaseMaterial3D.SHADING_MODE_UNSHADED

	_parry_shield = MeshInstance3D.new()
	var psm := SphereMesh.new()
	psm.radius = 0.72
	psm.height = 1.9
	psm.rings  = 6
	psm.radial_segments = 14
	_parry_shield.mesh              = psm
	_parry_shield.material_override = _parry_smat
	_parry_shield.position.y        = 0.9
	_parry_shield.visible           = false
	add_child(_parry_shield)

	# ── Ranged charge orb — cyan sphere on Kael's right hand ──────────────────
	_charge_mat = StandardMaterial3D.new()
	_charge_mat.albedo_color               = Color(0.3, 0.85, 1.0, 0.9)
	_charge_mat.emission_enabled           = true
	_charge_mat.emission                   = Color(0.3, 0.85, 1.0)
	_charge_mat.emission_energy_multiplier = 3.0
	_charge_mat.transparency              = BaseMaterial3D.TRANSPARENCY_ALPHA
	_charge_mat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED

	_charge_orb = MeshInstance3D.new()
	var corb := SphereMesh.new()
	corb.radius = 0.08
	corb.height = 0.16
	_charge_orb.mesh              = corb
	_charge_orb.material_override = _charge_mat
	_charge_orb.position          = Vector3(0.35, 0.95, 0.3)   # approx right-hand
	_charge_orb.scale             = Vector3.ZERO
	_charge_orb.visible           = false
	add_child(_charge_orb)

	# ── Screen-space flash overlay ─────────────────────────────────────────────
	_flash_layer       = CanvasLayer.new()
	_flash_layer.layer = 15
	add_child(_flash_layer)
	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(0.3, 0.85, 1.0, 0.0)
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.visible      = false
	_flash_layer.add_child(_flash_rect)

# ─────────────────────────────────────────────────────────────────────────────
#  Per-frame
# ─────────────────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	pass   # hit-stop restoration is handled by SceneTreeTimer callback in _hit_stop()

func _physics_process(delta: float) -> void:
	_apply_gravity(delta)

	# Opener: auto-move → attack → pause → done
	if _opener_active:
		_run_opener(delta)
		move_and_slide()
		_update_animation()
		return

	# Input frozen (e.g. during planning-mode transition)
	if input_frozen:
		velocity.x = move_toward(velocity.x, 0.0, SPEED * 8 * delta)
		velocity.z = move_toward(velocity.z, 0.0, SPEED * 8 * delta)
		move_and_slide()
		return

	_handle_parry(delta)
	_handle_dodge(delta)
	_handle_attack(delta)
	_handle_ranged(delta)
	_handle_movement(delta)
	_handle_lockon()
	move_and_slide()
	_update_animation()

func _update_animation() -> void:
	if _animator == null:
		return
	var moving := Vector2(velocity.x, velocity.z).length() > 0.5
	if is_attacking:
		var anim_name := "attack_" + str(combo_index)
		_animator.play(anim_name)
	elif is_dodging:
		_animator.play("dodge")
	elif moving:
		_animator.play("walk")
	else:
		_animator.play("idle")

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

# ─────────────────────────────────────────────────────────────────────────────
#  Opener (cinematic auto-attack sequence)
# ─────────────────────────────────────────────────────────────────────────────

## Called by PlanningMode to kick off the cinematic opener.
func start_opener(tgt: Node3D) -> void:
	_opener_target = tgt
	_opener_stage  = 0
	_opener_active = true
	input_frozen   = true

func _run_opener(delta: float) -> void:
	match _opener_stage:
		0:  # ── Move toward target ──────────────────────────────────────────
			var dist := global_position.distance_to(_opener_target.global_position)
			if dist > OPENER_RANGE:
				var dir := (_opener_target.global_position - global_position)
				dir.y = 0.0
				dir    = dir.normalized()
				velocity.x = dir.x * OPENER_MOVE_SPEED
				velocity.z = dir.z * OPENER_MOVE_SPEED
				var look_t := Vector3(_opener_target.global_position.x,
									  global_position.y,
									  _opener_target.global_position.z)
				if look_t.distance_squared_to(global_position) > 0.01:
					look_at(look_t)
			else:
				velocity.x = 0.0
				velocity.z = 0.0
				_opener_stage = 1
				combo_index   = 0      # ensure attack_1
				_start_attack()

		1:  # ── Wait for attack animation to finish ─────────────────────────
			velocity.x = 0.0
			velocity.z = 0.0
			if not is_attacking:
				if _opener_target and not (_opener_target as Enemy).is_dead:
					var tgt := _opener_target as Enemy
					if tgt.health <= tgt.max_health * OPENER_KILL_THRESHOLD:
						tgt._die()
					else:
						tgt.take_hit(OPENER_DAMAGE, OPENER_POSTURE)
				_opener_stage = 2
				_opener_timer = 0.4

		2:  # ── Brief pause then restore control ────────────────────────────
			velocity.x    = 0.0
			velocity.z    = 0.0
			_opener_timer -= delta
			if _opener_timer <= 0.0:
				_opener_active = false
				input_frozen   = false
				opener_finished.emit()

# ─────────────────────────────────────────────────────────────────────────────
#  Movement
# ─────────────────────────────────────────────────────────────────────────────

func _handle_movement(delta: float) -> void:
	if is_dodging:
		velocity.x = dodge_dir.x * DODGE_SPEED
		velocity.z = dodge_dir.z * DODGE_SPEED
		return

	var input_dir := _read_input_dir()

	var cam_fwd   := Vector3(0, 0, -1)
	var cam_right := Vector3(1, 0, 0)
	if camera_rig:
		var b      := camera_rig.global_basis
		cam_fwd    = Vector3(-b.z.x, 0, -b.z.z).normalized()
		cam_right  = Vector3( b.x.x, 0,  b.x.z).normalized()

	var move_dir := cam_fwd * -input_dir.y + cam_right * input_dir.x

	if is_attacking:
		velocity.x = move_toward(velocity.x, 0, SPEED * 8 * delta)
		velocity.z = move_toward(velocity.z, 0, SPEED * 8 * delta)
	else:
		velocity.x = move_dir.x * SPEED
		velocity.z = move_dir.z * SPEED

	if locked_on and lock_on_target:
		look_at(Vector3(lock_on_target.global_position.x, global_position.y, lock_on_target.global_position.z))
	elif move_dir.length() > 0.05 and not is_attacking:
		look_at(global_position + move_dir)

# ─────────────────────────────────────────────────────────────────────────────
#  Dodge
# ─────────────────────────────────────────────────────────────────────────────

func _handle_dodge(delta: float) -> void:
	if dodge_cooldown > 0:
		dodge_cooldown -= delta

	if is_dodging:
		dodge_timer   -= delta
		is_invincible  = dodge_timer > 0.05
		if dodge_timer <= 0:
			is_dodging    = false
			is_invincible = false
		return

	if Input.is_action_just_pressed("dodge") and dodge_cooldown <= 0 and not is_attacking:
		var input_dir := _read_input_dir()
		var cam_fwd   := Vector3(0, 0, -1)
		var cam_right := Vector3(1, 0, 0)
		if camera_rig:
			var b      := camera_rig.global_basis
			cam_fwd    = Vector3(-b.z.x, 0, -b.z.z).normalized()
			cam_right  = Vector3( b.x.x, 0,  b.x.z).normalized()

		dodge_dir = (-global_transform.basis.z if input_dir == Vector2.ZERO
				else (cam_fwd * -input_dir.y + cam_right * input_dir.x).normalized())

		is_dodging     = true
		is_invincible  = true
		dodge_timer    = DODGE_DURATION
		dodge_cooldown = DODGE_COOLDOWN

		var tw := create_tween()
		tw.tween_property(_mat, "albedo_color", Color(0.6, 0.9, 1.0), 0.05)
		tw.tween_property(_mat, "albedo_color", Color(0.25, 0.5, 0.9), 0.2)

# ─────────────────────────────────────────────────────────────────────────────
#  Attack combo
# ─────────────────────────────────────────────────────────────────────────────

func _handle_attack(delta: float) -> void:
	if is_attacking:
		attack_timer -= delta
		var hit_t: float = ATTACK_DURATION[combo_index - 1] - ATTACK_HIT_FRAME[combo_index - 1]
		if not hit_registered and attack_timer <= hit_t:
			hit_registered = true
			_try_land_hit()

		if Input.is_action_just_pressed("attack") and combo_index < 3:
			combo_buffer = true

		if attack_timer <= 0:
			is_attacking = false
			if combo_buffer and combo_index < 3:
				combo_buffer = false
				_start_attack()
			else:
				combo_index  = 0
				combo_buffer = false
		return

	if Input.is_action_just_pressed("attack"):
		_start_attack()

func _start_attack() -> void:
	if combo_index >= 3:
		combo_index = 0
	combo_index    += 1
	is_attacking    = true
	hit_registered  = false
	attack_timer    = ATTACK_DURATION[combo_index - 1]

	var colors: Array[Color] = [Color(1.0, 0.85, 0.2), Color(1.0, 0.5, 0.1), Color(1.0, 0.15, 0.1)]
	var col: Color = colors[combo_index - 1]
	var tw := create_tween()
	tw.tween_property(_mat, "albedo_color", colors[combo_index - 1], 0.05)
	tw.tween_property(_mat, "albedo_color", Color(0.25, 0.5, 0.9),   0.15)

func _try_land_hit() -> void:
	if enemy == null:
		return
	if global_position.distance_to(enemy.global_position) > 2.8:
		return

	var bonus := 0.0
	if parry_bonus_active:
		bonus              = PARRY_BONUS_POSTURE
		parry_bonus_active = false
		punish_window_changed.emit(false, 0.0)

	enemy.take_hit(ATTACK_DAMAGE[combo_index - 1], ATTACK_POSTURE[combo_index - 1] + bonus)

	# Hit-stop: ~80 ms real-time freeze frame
	_hit_stop(80)

	# Camera shake on hit
	if camera_rig and camera_rig.has_method("shake"):
		camera_rig.shake(0.18)

	# Particle burst at the impact point (midway between attacker and target)
	var impact_pos := (global_position + enemy.global_position) * 0.5 + Vector3(0, 0.9, 0)
	var hit_color  := Color(1.0, 0.9, 0.2) if bonus > 0.0 else Color(1.0, 0.5, 0.15)
	_spawn_impact_fx(impact_pos, hit_color)

func _spawn_impact_fx(pos: Vector3, color: Color) -> void:
	var ps := GPUParticles3D.new()
	ps.top_level    = true
	ps.global_position = pos
	ps.emitting     = false
	ps.one_shot     = true
	ps.explosiveness = 1.0
	ps.amount       = 18
	ps.lifetime     = 0.45

	var mat := ParticleProcessMaterial.new()
	mat.direction            = Vector3(0, 1, 0)
	mat.spread               = 60.0
	mat.initial_velocity_min = 3.5
	mat.initial_velocity_max = 7.0
	mat.gravity              = Vector3(0, -6.0, 0)
	mat.scale_min            = 0.06
	mat.scale_max            = 0.14
	mat.color                = color
	ps.process_material = mat

	var mesh_inst := MeshInstance3D.new()
	var sm        := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	mesh_inst.mesh = sm
	var pm := StandardMaterial3D.new()
	pm.albedo_color              = color
	pm.emission_enabled          = true
	pm.emission                  = color
	pm.emission_energy_multiplier = 2.5
	pm.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_inst.material_override  = pm
	ps.draw_pass_1 = sm

	get_tree().root.add_child(ps)
	ps.emitting = true
	# Auto-remove after lifetime
	get_tree().create_timer(0.6).timeout.connect(ps.queue_free)

# ─────────────────────────────────────────────────────────────────────────────
#  Parry
# ─────────────────────────────────────────────────────────────────────────────

func _handle_parry(delta: float) -> void:
	# Grace window: if parry recently expired and hit arrives, show MISS
	if _parry_miss_grace > 0:
		_parry_miss_grace -= delta

	# Punish bonus countdown
	if parry_bonus_active:
		parry_bonus_timer -= delta
		if parry_bonus_timer <= 0:
			parry_bonus_active = false
			punish_window_changed.emit(false, 0.0)

	match parry_state:
		ParryState.ACTIVE:
			parry_timer -= delta
			if parry_timer <= 0:
				# Window expired without a hit
				_cancel_parry_pulse()
				_parry_shield.visible = false
				parry_state           = ParryState.COOLDOWN
				parry_timer           = PARRY_COOLDOWN
				_parry_miss_grace     = 0.5
		ParryState.COOLDOWN:
			parry_timer -= delta
			if parry_timer <= 0:
				parry_state = ParryState.NONE

	# Input: only when free (not attacking, not dodging, not in cooldown)
	if Input.is_action_just_pressed("parry") \
			and parry_state == ParryState.NONE \
			and not is_attacking and not is_dodging:
		parry_state       = ParryState.ACTIVE
		parry_timer       = PARRY_ACTIVE_DURATION
		_parry_miss_grace = 0.0
		# Classify at press-time: was enemy visibly winding up?
		_parry_is_windup  = enemy != null \
				and enemy.has_method("is_winding_up") \
				and enemy.is_winding_up()
		_show_parry_active()

func _show_parry_active() -> void:
	_cancel_parry_pulse()
	_parry_smat.albedo_color              = Color(0.5, 0.85, 1.0, 0.25)
	_parry_smat.emission                  = Color(0.5, 0.85, 1.0)
	_parry_smat.emission_energy_multiplier = 1.8
	_parry_shield.scale   = Vector3.ONE
	_parry_shield.visible = true
	# Pulsing glow while active
	_parry_tw = create_tween().set_loops()
	_parry_tw.tween_property(_parry_smat, "emission_energy_multiplier", 3.8, 0.12)
	_parry_tw.tween_property(_parry_smat, "emission_energy_multiplier", 1.4, 0.12)

func _cancel_parry_pulse() -> void:
	if _parry_tw and _parry_tw.is_running():
		_parry_tw.kill()
	_parry_tw = null

func _on_perfect_parry() -> void:
	_cancel_parry_pulse()
	parry_state = ParryState.COOLDOWN
	parry_timer = PARRY_COOLDOWN

	# Open punish window
	parry_bonus_active = true
	parry_bonus_timer  = PARRY_BONUS_WINDOW
	punish_window_changed.emit(true, PARRY_BONUS_WINDOW)

	# Stagger the enemy
	if enemy and enemy.has_method("receive_parry_stagger"):
		enemy.receive_parry_stagger()

	# Shield: flash gold then explode outward and fade
	_parry_smat.albedo_color              = Color(1.0, 0.95, 0.2, 0.6)
	_parry_smat.emission                  = Color(1.0, 0.95, 0.2)
	_parry_smat.emission_energy_multiplier = 4.0
	var burst := create_tween().set_parallel(true)
	burst.tween_property(_parry_shield, "scale",
			Vector3(2.8, 2.8, 2.8), 0.35)
	burst.tween_property(_parry_smat, "albedo_color",
			Color(1.0, 0.95, 0.2, 0.0), 0.35)
	burst.chain().tween_callback(func() -> void:
		_parry_shield.visible = false
		_parry_shield.scale   = Vector3.ONE)

	# Player gold flash
	var flash := create_tween()
	flash.tween_property(_mat, "albedo_color", Color(1.0, 0.95, 0.2), 0.04)
	flash.tween_property(_mat, "albedo_color", Color(0.25, 0.5, 0.9), 0.3)

	# Hit-stop (80 ms real-time freeze for that satisfying impact feel)
	_hit_stop(80)

	# Camera shake (small, crisp)
	if camera_rig and camera_rig.has_method("shake"):
		camera_rig.shake(0.12)

	# AUDIO: play parry_perfect.ogg  (metallic ring, high pitch, short tail)
	parry_result.emit("perfect")

func _on_block(amount: float) -> void:
	_cancel_parry_pulse()
	parry_state = ParryState.COOLDOWN
	parry_timer = PARRY_COOLDOWN

	# Absorb most of the damage
	var taken := amount * (1.0 - PARRY_BLOCK_REDUCTION)
	health = max(0.0, health - taken)
	health_changed.emit(health, max_health)

	# Small stagger on enemy
	if enemy and enemy.has_method("receive_block_stagger"):
		enemy.receive_block_stagger()

	# Shield: expand blue then fade
	_parry_smat.albedo_color              = Color(0.4, 0.65, 1.0, 0.7)
	_parry_smat.emission                  = Color(0.4, 0.65, 1.0)
	_parry_smat.emission_energy_multiplier = 3.0
	var burst := create_tween().set_parallel(true)
	burst.tween_property(_parry_shield, "scale",
			Vector3(1.9, 1.9, 1.9), 0.28)
	burst.tween_property(_parry_smat, "albedo_color",
			Color(0.4, 0.65, 1.0, 0.0), 0.28)
	burst.chain().tween_callback(func() -> void:
		_parry_shield.visible = false
		_parry_shield.scale   = Vector3.ONE)

	# Player blue flash
	var flash := create_tween()
	flash.tween_property(_mat, "albedo_color", Color(0.55, 0.75, 1.0), 0.04)
	flash.tween_property(_mat, "albedo_color", Color(0.25, 0.5, 0.9),  0.2)

	# Brief hit-stop (30 ms — you still took a hit, but you handled it)
	_hit_stop(30)

	# Camera shake (medium — you absorbed the blow)
	if camera_rig and camera_rig.has_method("shake"):
		camera_rig.shake(0.24)

	# AUDIO: play block.ogg  (heavy metallic thud, medium pitch)
	parry_result.emit("block")

	if health <= 0.0:
		died.emit()

func _hit_stop(real_ms: int) -> void:
	# Full freeze — Engine.time_scale = 0.0 halts all physics and animation.
	# SceneTreeTimer with ignore_time_scale=true runs on the OS clock, so it
	# fires after the real wall-clock duration regardless of time_scale.
	Engine.time_scale = 0.0
	get_tree().create_timer(real_ms * 0.001, true, false, true)\
			.timeout.connect(func() -> void: Engine.time_scale = 1.0)

# ─────────────────────────────────────────────────────────────────────────────
#  Lock-on
# ─────────────────────────────────────────────────────────────────────────────

func _handle_lockon() -> void:
	if Input.is_action_just_pressed("lock_on"):
		if locked_on:
			locked_on      = false
			lock_on_target = null
		elif enemy != null and global_position.distance_to(enemy.global_position) <= 10.0:
			locked_on      = true
			lock_on_target = enemy

	if locked_on and lock_on_target:
		if global_position.distance_to(lock_on_target.global_position) > 14.0:
			locked_on      = false
			lock_on_target = null

# ─────────────────────────────────────────────────────────────────────────────
#  Damage reception
# ─────────────────────────────────────────────────────────────────────────────

func take_damage(amount: float) -> void:
	if is_invincible:
		return

	# Parry interception
	if parry_state == ParryState.ACTIVE:
		if _parry_is_windup:
			_on_perfect_parry()
		else:
			_on_block(amount)
		return

	# Full damage — optionally show MISS if parry was recently attempted
	if _parry_miss_grace > 0:
		_parry_miss_grace = 0.0
		parry_result.emit("miss")

	health = max(0.0, health - amount)
	health_changed.emit(health, max_health)

	var tw := create_tween()
	tw.tween_property(_mat, "albedo_color", Color(1, 0.3, 0.3), 0.05)
	tw.tween_property(_mat, "albedo_color", Color(0.25, 0.5, 0.9), 0.18)

	# Heavier camera shake on full hit
	if camera_rig and camera_rig.has_method("shake"):
		camera_rig.shake(0.40)

	# Hit-stop (60 ms — shorter than attack landing, signals the player took damage)
	_hit_stop(60)

	# Hit reaction animation (only if not mid-attack to avoid interrupting combo)
	if _animator and not is_attacking:
		_animator.force_play("hit_react")

	# AUDIO: play player_hit.ogg  (impact thud, low pitch)

	if health <= 0.0:
		died.emit()

# ─────────────────────────────────────────────────────────────────────────────
#  Ranged attack
# ─────────────────────────────────────────────────────────────────────────────

func _handle_ranged(delta: float) -> void:
	if _ranged_cooldown > 0:
		_ranged_cooldown -= delta

	# Right-click pressed: begin charge
	if Input.is_action_just_pressed("ranged") and _ranged_cooldown <= 0 and not is_dodging:
		_ranged_holding   = true
		_ranged_hold_time = 0.0
		_charge_orb.visible = true
		_charge_orb.scale   = Vector3.ZERO
		var ctw := create_tween()
		ctw.tween_property(_charge_orb, "scale", Vector3.ONE, 0.25) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		# Charge orb colour pulses while building up
		var pulse := create_tween().set_loops(3)
		pulse.tween_property(_charge_mat, "emission_energy_multiplier", 6.0, 0.08)
		pulse.tween_property(_charge_mat, "emission_energy_multiplier", 3.0, 0.08)

	if _ranged_holding:
		_ranged_hold_time += delta

	# Dodge cancels charge without firing
	if _ranged_holding and is_dodging:
		_ranged_holding = false
		var ctw := create_tween()
		ctw.tween_property(_charge_orb, "scale", Vector3.ZERO, 0.06)
		ctw.tween_callback(func() -> void: _charge_orb.visible = false)

	# Right-click released: fire if held long enough
	if Input.is_action_just_released("ranged") and _ranged_holding:
		_ranged_holding = false
		var ctw := create_tween()
		ctw.tween_property(_charge_orb, "scale", Vector3.ZERO, 0.06)
		ctw.tween_callback(func() -> void: _charge_orb.visible = false)
		if _ranged_hold_time >= RANGED_MIN_HOLD and _ranged_cooldown <= 0:
			_fire_ranged()
			_ranged_cooldown = RANGED_COOLDOWN_T

func _fire_ranged() -> void:
	# Determine fire direction from camera; fall back to player facing
	var cam: Camera3D = null
	if camera_rig:
		cam = camera_rig.get_node_or_null("Camera3D") as Camera3D

	var origin    := global_position + Vector3(0, 1.0, 0)
	var direction := -global_transform.basis.z
	if cam:
		direction = -cam.global_transform.basis.z

	# Hitscan — find the closest enemy along the beam
	var hit_enemy: Node3D = null
	var hit_dist          := RANGED_RANGE
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e == null or e.is_dead:
			continue
		var aim_pt := e.global_position + Vector3(0, 0.9, 0)
		var to_e   := aim_pt - origin
		var proj   := to_e.dot(direction)
		if proj < 0.0 or proj > RANGED_RANGE:
			continue
		var closest := origin + direction * proj
		if closest.distance_to(aim_pt) < 0.75 and proj < hit_dist:
			hit_dist  = proj
			hit_enemy = e

	var impact_pos := origin + direction * hit_dist
	if hit_enemy:
		(hit_enemy as Enemy).take_hit(RANGED_DAMAGE, 5.0)
		impact_pos = hit_enemy.global_position + Vector3(0, 0.9, 0)

	_spawn_beam_fx(origin, direction, impact_pos)

	# Screen-space flash — cyan tint that fades quickly
	_flash_rect.color   = Color(0.3, 0.85, 1.0, 0.45)
	_flash_rect.visible = true
	var ftw := create_tween()
	ftw.tween_property(_flash_rect, "color", Color(0.3, 0.85, 1.0, 0.0), 0.12)
	ftw.tween_callback(func() -> void: _flash_rect.visible = false)

	if camera_rig and camera_rig.has_method("shake"):
		camera_rig.shake(0.10)

func _spawn_beam_fx(origin: Vector3, direction: Vector3, impact_pos: Vector3) -> void:
	var beam_length := origin.distance_to(impact_pos)
	var midpoint    := origin + direction * (beam_length * 0.5)

	# ── Beam cylinder ─────────────────────────────────────────────────────────
	var beam_mat := StandardMaterial3D.new()
	beam_mat.albedo_color               = Color(0.4, 0.9, 1.0, 0.9)
	beam_mat.emission_enabled           = true
	beam_mat.emission                   = Color(0.4, 0.9, 1.0)
	beam_mat.emission_energy_multiplier = 6.0
	beam_mat.transparency              = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.cull_mode                 = BaseMaterial3D.CULL_DISABLED

	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius    = 0.045
	beam_mesh.bottom_radius = 0.045
	beam_mesh.height        = beam_length

	var beam_inst := MeshInstance3D.new()
	beam_inst.mesh              = beam_mesh
	beam_inst.material_override = beam_mat
	get_tree().root.add_child(beam_inst)
	beam_inst.global_position = midpoint
	# Rotate local Y (cylinder axis) to align with beam direction
	var ref  := Vector3.RIGHT if abs(direction.dot(Vector3.UP)) > 0.99 else Vector3.UP
	var x_ax := ref.cross(direction).normalized()
	var z_ax := x_ax.cross(direction).normalized()
	beam_inst.global_transform.basis = Basis(x_ax, direction, z_ax)

	# Persist 0.15 s then fade out
	var btw := beam_inst.create_tween()
	btw.tween_interval(0.15)
	btw.tween_property(beam_mat, "albedo_color", Color(0.4, 0.9, 1.0, 0.0), 0.08)
	btw.tween_callback(beam_inst.queue_free)

	# ── Muzzle flash particles at origin ──────────────────────────────────────
	_spawn_ranged_particles(origin, Color(0.5, 0.95, 1.0), 12, 4.0)

	# ── Travelling orb along beam path ────────────────────────────────────────
	var orb_mat := StandardMaterial3D.new()
	orb_mat.albedo_color               = Color(0.85, 0.97, 1.0)
	orb_mat.emission_enabled           = true
	orb_mat.emission                   = Color(0.85, 0.97, 1.0)
	orb_mat.emission_energy_multiplier = 8.0
	orb_mat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED

	var orb_mi := MeshInstance3D.new()
	var orb_sm := SphereMesh.new()
	orb_sm.radius = 0.10
	orb_sm.height = 0.20
	orb_mi.mesh              = orb_sm
	orb_mi.material_override = orb_mat
	get_tree().root.add_child(orb_mi)
	orb_mi.global_position = origin

	var otw := orb_mi.create_tween()
	otw.tween_property(orb_mi, "global_position", impact_pos, 0.12)
	otw.tween_callback(func() -> void:
		_spawn_ranged_particles(impact_pos, Color(0.3, 0.85, 1.0), 24, 7.0)
		orb_mi.queue_free())

func _spawn_ranged_particles(pos: Vector3, color: Color, amount: int, speed_max: float) -> void:
	var ps := GPUParticles3D.new()
	ps.top_level       = true
	ps.global_position = pos
	ps.emitting        = false
	ps.one_shot        = true
	ps.explosiveness   = 1.0
	ps.amount          = amount
	ps.lifetime        = 0.50

	var mat := ParticleProcessMaterial.new()
	mat.direction            = Vector3(0, 1, 0)
	mat.spread               = 70.0
	mat.initial_velocity_min = speed_max * 0.45
	mat.initial_velocity_max = speed_max
	mat.gravity              = Vector3(0, -4.0, 0)
	mat.scale_min            = 0.04
	mat.scale_max            = 0.11
	mat.color                = color
	ps.process_material = mat

	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.10
	var pm := StandardMaterial3D.new()
	pm.albedo_color               = color
	pm.emission_enabled           = true
	pm.emission                   = color
	pm.emission_energy_multiplier = 3.5
	pm.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
	ps.draw_pass_1 = sm

	get_tree().root.add_child(ps)
	ps.emitting = true
	get_tree().create_timer(0.70).timeout.connect(ps.queue_free)

# ─────────────────────────────────────────────────────────────────────────────
#  Utility
# ─────────────────────────────────────────────────────────────────────────────

func _read_input_dir() -> Vector2:
	var d := Vector2.ZERO
	if Input.is_action_pressed("move_forward"): d.y -= 1
	if Input.is_action_pressed("move_back"):    d.y += 1
	if Input.is_action_pressed("move_left"):    d.x -= 1
	if Input.is_action_pressed("move_right"):   d.x += 1
	return d.normalized() if d != Vector2.ZERO else Vector2.ZERO
