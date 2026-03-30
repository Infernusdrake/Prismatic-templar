class_name Enemy
extends CharacterBody3D

# ── Identity data pools ───────────────────────────────────────────────────────
const NAMES  := ["Soldato", "Ardent", "Vexer", "Riven", "Thorn"]
const TRAITS := ["Aggressive", "Patient", "Caller", "Berserker", "Coward"]
const GEMS   := {
	"Ruby":     Color(1.00, 0.10, 0.10),
	"Sapphire": Color(0.15, 0.35, 1.00),
	"Emerald":  Color(0.10, 0.80, 0.30),
	"Topaz":    Color(1.00, 0.60, 0.10),
	"Amethyst": Color(0.60, 0.20, 1.00),
}

# ── Existing combat constants ────────────────────────────────────────────────
const EXECUTE_WINDOW      := 2.0
const EXECUTE_DAMAGE      := 50.0
const EXPIRE_DAMAGE       := 25.0
const POSTURE_REGEN       := 8.0
const POSTURE_REGEN_DELAY := 2.0

# ── AI constants ─────────────────────────────────────────────────────────────
const AGGRO_RANGE    := 8.0
const DEAGGRO_RANGE  := 14.0
const ATTACK_RANGE   := 2.8   # distance at which enemy starts a windup
const HIT_RANGE      := 3.4   # distance within which the swing deals damage
const PATROL_SPEED   := 1.5
const CHASE_SPEED    := 3.2
const LUNGE_SPEED    := 9.0
const GRAVITY        := 9.8

# ── Attack timings ────────────────────────────────────────────────────────────
# [light, heavy, combo_hit1_windup, combo_hit2_windup]
const WINDUP_T   := [0.55, 1.30, 0.45, 0.22]
const ATTACK_T   := [0.30, 0.45, 0.25, 0.25]
const RECOVERY_T := [0.70, 1.10, 0.00, 0.90]   # combo_hit1 recovery handled inline
const COOLDOWN_T := [1.30, 2.20, 0.00, 1.60]

# ── Attack damage ─────────────────────────────────────────────────────────────
const DMG_LIGHT := 10.0
const DMG_HEAVY := 22.0
const DMG_COMBO := 7.0   # per hit

# ── State machine ─────────────────────────────────────────────────────────────
enum State { IDLE, PATROL, CHASE, WINDUP, ATTACKING, RECOVERY, COOLDOWN }
enum Atk   { LIGHT, HEAVY, COMBO }

var ai_state   := State.IDLE
var ai_timer   := 0.0
var cur_atk    := Atk.LIGHT
var combo_step := 0          # 0 = first hit, 1 = second hit
var _hit_done  := false

# ── References ────────────────────────────────────────────────────────────────
var target: Node3D = null    # set by Arena after spawning
var _spawn_pos  := Vector3.ZERO
var _patrol_pos := Vector3.ZERO

# ── Existing state ────────────────────────────────────────────────────────────
var health      := 100.0
var max_health  := 100.0
var posture     := 0.0
var max_posture := 100.0

var posture_regen_timer := 0.0
var execute_ready       := false
var execute_timer       := 0.0
var is_dead             := false
var is_finishering      := false

# ── Identity (randomised in _ready, overridable before add_child) ─────────────
var enemy_name:   String = "Soldato"
var combat_trait: String = "Aggressive"
var gem_type:     String = "Ruby"
var gem_color:    Color  = Color(1.0, 0.1, 0.1)
var is_elite:     bool   = false

# ── Planning-mode state ───────────────────────────────────────────────────────
var mark_index:              int  = -1    # -1=unmarked, 1-4=mark order
var _posture_first_hit_used: bool = false

# ── Visuals ───────────────────────────────────────────────────────────────────
var _mesh:        MeshInstance3D
var _mat:         StandardMaterial3D
var _charge_orb:  MeshInstance3D
var _charge_mat:  StandardMaterial3D
var _danger_ring: MeshInstance3D
var _active_tw:   Tween = null
var _animator:    EnemyAnimator = null

signal health_changed(val: float, max_val: float)
signal posture_changed(val: float, max_val: float)
signal execute_available(on: bool)
signal died

# ─────────────────────────────────────────────────────────────────────────────
#  Setup
# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_spawn_pos = position

	# Randomise identity (can be overridden by Arena before add_child via set_deferred)
	if not is_elite:
		enemy_name   = NAMES [randi() % NAMES.size()]
	combat_trait = TRAITS[randi() % TRAITS.size()]
	var gem_keys := GEMS.keys()
	gem_type  = gem_keys[randi() % gem_keys.size()]
	gem_color = GEMS[gem_type]

	# _mat kept as a dummy for existing flash-tween code — not rendered.
	_mat = StandardMaterial3D.new()

	# ── Quaternius glTF character (Knight) ────────────────────────────────────
	var gltf := load("res://assets/characters/Knight_Golden_Male.glTF")
	if gltf:
		var inst: Node3D = gltf.instantiate()
		inst.name = "CharacterArmature"
		add_child(inst)
		# _mesh points to the model root so finisher/death scale tweens are visible.
		_mesh = inst
	else:
		# Fallback: invisible dummy so tween targets never crash
		_mesh = MeshInstance3D.new()
		_mesh.name = "Body"

	# ── Collision capsule (unchanged) ─────────────────────────────────────────
	var col := CollisionShape3D.new()
	var cs  := CapsuleShape3D.new()
	cs.radius = 0.4
	cs.height = 1.8
	col.shape = cs
	col.position.y = 0.9
	add_child(col)

	# ── Animator — must be added AFTER the model so AnimationPlayer exists ────
	_animator = EnemyAnimator.new()
	add_child(_animator)
	_animator.init()

	# Lock-on ring
	var ring := MeshInstance3D.new()
	var cyl  := CylinderMesh.new()
	cyl.top_radius    = 0.55
	cyl.bottom_radius = 0.55
	cyl.height        = 0.06
	cyl.rings         = 1
	ring.mesh = cyl
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color              = Color(0.2, 1.0, 0.8)
	ring_mat.emission_enabled          = true
	ring_mat.emission                  = Color(0.2, 1.0, 0.8)
	ring_mat.emission_energy_multiplier = 1.5
	ring.material_override = ring_mat
	ring.name    = "LockRing"
	ring.visible = false
	add_child(ring)

	# Charge orb (telegraph indicator)
	_charge_mat = StandardMaterial3D.new()
	_charge_mat.albedo_color              = Color.WHITE
	_charge_mat.emission_enabled          = true
	_charge_mat.emission                  = Color.WHITE
	_charge_mat.emission_energy_multiplier = 3.0
	_charge_mat.transparency             = BaseMaterial3D.TRANSPARENCY_ALPHA

	_charge_orb = MeshInstance3D.new()
	var orb := SphereMesh.new()
	orb.radius = 0.22
	orb.height = 0.44
	_charge_orb.mesh              = orb
	_charge_orb.material_override = _charge_mat
	_charge_orb.position          = Vector3(0, 1.3, -0.55)
	_charge_orb.scale             = Vector3.ZERO
	add_child(_charge_orb)

	# Danger ring (ground indicator for heavy attack)
	var d_mat := StandardMaterial3D.new()
	d_mat.albedo_color              = Color(1.0, 0.1, 0.1, 0.55)
	d_mat.emission_enabled          = true
	d_mat.emission                  = Color(1.0, 0.15, 0.05)
	d_mat.emission_energy_multiplier = 1.2
	d_mat.transparency              = BaseMaterial3D.TRANSPARENCY_ALPHA

	_danger_ring = MeshInstance3D.new()
	var dr := CylinderMesh.new()
	dr.top_radius    = HIT_RANGE
	dr.bottom_radius = HIT_RANGE
	dr.height        = 0.04
	dr.rings         = 1
	_danger_ring.mesh              = dr
	_danger_ring.material_override = d_mat
	_danger_ring.position.y        = 0.05
	_danger_ring.visible           = false
	add_child(_danger_ring)

	ai_timer = randf_range(1.0, 3.0)   # stagger first idle

# ─────────────────────────────────────────────────────────────────────────────
#  Physics / AI loop
# ─────────────────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	# Posture regen
	if posture_regen_timer > 0:
		posture_regen_timer -= delta
	elif posture > 0 and not execute_ready:
		posture = max(0.0, posture - POSTURE_REGEN * delta)
		posture_changed.emit(posture, max_posture)

	# Execute countdown
	if execute_ready:
		execute_timer -= delta
		if execute_timer <= 0.0:
			_expire_execute()
		# Freeze horizontal movement while execute-ready (stunned)
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	# Run AI
	if not is_finishering:
		ai_timer -= delta
		_run_ai(delta)

	move_and_slide()

func _run_ai(delta: float) -> void:
	match ai_state:
		State.IDLE:     _ai_idle(delta)
		State.PATROL:   _ai_patrol(delta)
		State.CHASE:    _ai_chase(delta)
		State.WINDUP:   _ai_windup(delta)
		State.ATTACKING: _ai_attacking(delta)
		State.RECOVERY: _ai_recovery(delta)
		State.COOLDOWN: _ai_cooldown(delta)
	_update_anim()

func _update_anim() -> void:
	if _animator == null:
		return
	var moving := Vector2(velocity.x, velocity.z).length() > 0.5
	match ai_state:
		State.WINDUP:
			match cur_atk:
				Atk.LIGHT: _animator.play("windup_light")
				Atk.HEAVY: _animator.play("windup_heavy")
				Atk.COMBO: _animator.play("windup_combo")
		State.ATTACKING:
			match cur_atk:
				Atk.LIGHT: _animator.play("attack_light")
				Atk.HEAVY: _animator.play("attack_heavy")
				Atk.COMBO: _animator.play("attack_combo")
		State.RECOVERY, State.COOLDOWN:
			_animator.play("idle")
		State.CHASE:
			if moving:
				_animator.play("walk")
			else:
				_animator.play("idle")
		State.PATROL:
			if moving:
				_animator.play("walk")
			else:
				_animator.play("idle")
		_:
			_animator.play("idle")

# ─────────────────────────────────────────────────────────────────────────────
#  AI states
# ─────────────────────────────────────────────────────────────────────────────

func _ai_idle(_delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0

	if target and _dist_to_target() <= AGGRO_RANGE:
		_enter(State.CHASE)
		return

	if ai_timer <= 0:
		_pick_patrol_target()
		_enter(State.PATROL, randf_range(3.5, 6.0))

func _ai_patrol(delta: float) -> void:
	if target and _dist_to_target() <= AGGRO_RANGE:
		_enter(State.CHASE)
		return

	var d := global_position.distance_to(_patrol_pos)
	if d < 0.6 or ai_timer <= 0:
		_enter(State.IDLE, randf_range(1.5, 3.0))
		return

	_move_toward(_patrol_pos, PATROL_SPEED, delta)

func _ai_chase(delta: float) -> void:
	if target == null:
		_enter(State.IDLE, 2.0)
		return

	var dist := _dist_to_target()

	if dist > DEAGGRO_RANGE:
		_enter(State.IDLE, 2.0)
		return

	if dist <= ATTACK_RANGE:
		_choose_attack()
		return

	_move_toward(target.global_position, CHASE_SPEED, delta)

func _ai_windup(_delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if target:
		_face(target.global_position)

	if ai_timer <= 0:
		_hit_done = false
		_enter(State.ATTACKING, _get_atk_t(cur_atk, combo_step))

func _ai_attacking(delta: float) -> void:
	# Lunge toward player during first half of swing
	if target and ai_timer > _get_atk_t(cur_atk, combo_step) * 0.45:
		_move_toward(target.global_position, LUNGE_SPEED, delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	# Land hit at midpoint
	var half := _get_atk_t(cur_atk, combo_step) * 0.5
	if not _hit_done and ai_timer <= half:
		_hit_done = true
		_do_hit()

	if ai_timer > 0:
		return

	# Transition out
	_hide_windup()

	if cur_atk == Atk.COMBO and combo_step == 0:
		# Chain straight into second hit windup
		combo_step = 1
		_hit_done  = false
		_start_windup_visual(Atk.COMBO, 1)
		_enter(State.WINDUP, WINDUP_T[2 + 1])   # WINDUP_T[3]
	else:
		combo_step = 0
		_enter(State.RECOVERY, _get_rec_t(cur_atk))

func _ai_recovery(_delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if ai_timer <= 0:
		_enter(State.COOLDOWN, _get_cd_t(cur_atk))

func _ai_cooldown(_delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if ai_timer <= 0:
		if target and _dist_to_target() <= DEAGGRO_RANGE:
			_enter(State.CHASE)
		else:
			_enter(State.IDLE, 2.0)

# ─────────────────────────────────────────────────────────────────────────────
#  Helpers
# ─────────────────────────────────────────────────────────────────────────────

func _enter(new_state: State, duration: float = 0.0) -> void:
	ai_state = new_state
	ai_timer = duration

func _dist_to_target() -> float:
	return global_position.distance_to(target.global_position)

func _move_toward(pos: Vector3, speed: float, _delta: float) -> void:
	var dir := (pos - global_position)
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	dir = dir.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	look_at(Vector3(pos.x, global_position.y, pos.z))

func _face(pos: Vector3) -> void:
	var t := Vector3(pos.x, global_position.y, pos.z)
	if t.distance_squared_to(global_position) > 0.01:
		look_at(t)

func _pick_patrol_target() -> void:
	var angle := randf() * TAU
	var dist  := randf_range(2.5, 5.5)
	_patrol_pos = _spawn_pos + Vector3(cos(angle) * dist, 0, sin(angle) * dist)
	_patrol_pos.x = clamp(_patrol_pos.x, -13.0, 13.0)
	_patrol_pos.z = clamp(_patrol_pos.z, -13.0, 13.0)

func _choose_attack() -> void:
	var roll := randf()
	if roll < 0.45:
		cur_atk = Atk.LIGHT
	elif roll < 0.75:
		cur_atk = Atk.COMBO
	else:
		cur_atk = Atk.HEAVY
	combo_step = 0
	_hit_done  = false
	var wd := _get_wd_t(cur_atk, 0)
	_start_windup_visual(cur_atk, 0)
	_enter(State.WINDUP, wd)

func _do_hit() -> void:
	if target == null:
		return
	if global_position.distance_to(target.global_position) > HIT_RANGE:
		return
	var dmg: float
	match cur_atk:
		Atk.LIGHT: dmg = DMG_LIGHT
		Atk.HEAVY: dmg = DMG_HEAVY
		Atk.COMBO: dmg = DMG_COMBO
	if target.has_method("take_damage"):
		target.take_damage(dmg)

# ─────────────────────────────────────────────────────────────────────────────
#  Timing tables
# ─────────────────────────────────────────────────────────────────────────────

func _get_wd_t(atk: Atk, step: int) -> float:
	match atk:
		Atk.LIGHT: return WINDUP_T[0]
		Atk.HEAVY: return WINDUP_T[1]
		Atk.COMBO: return WINDUP_T[2 + step]
	return 0.5

func _get_atk_t(atk: Atk, step: int) -> float:
	match atk:
		Atk.LIGHT: return ATTACK_T[0]
		Atk.HEAVY: return ATTACK_T[1]
		Atk.COMBO: return ATTACK_T[2 + step]
	return 0.3

func _get_rec_t(atk: Atk) -> float:
	match atk:
		Atk.LIGHT: return RECOVERY_T[0]
		Atk.HEAVY: return RECOVERY_T[1]
		Atk.COMBO: return RECOVERY_T[3]   # only used after second hit
	return 0.7

func _get_cd_t(atk: Atk) -> float:
	match atk:
		Atk.LIGHT: return COOLDOWN_T[0]
		Atk.HEAVY: return COOLDOWN_T[1]
		Atk.COMBO: return COOLDOWN_T[3]
	return 1.3

# ─────────────────────────────────────────────────────────────────────────────
#  Windup visuals
# ─────────────────────────────────────────────────────────────────────────────

func _start_windup_visual(atk: Atk, step: int) -> void:
	if _active_tw and _active_tw.is_running():
		_active_tw.kill()

	var dur := _get_wd_t(atk, step)

	match atk:
		Atk.LIGHT:
			# Orange orb growing from zero
			_charge_mat.albedo_color = Color(1.0, 0.45, 0.05)
			_charge_mat.emission     = Color(1.0, 0.45, 0.05)
			_charge_orb.scale        = Vector3.ZERO
			_active_tw = create_tween().set_parallel(true)
			_active_tw.tween_property(_charge_orb, "scale",       Vector3.ONE,              dur)
			_active_tw.tween_property(_mat,         "albedo_color", Color(0.95, 0.40, 0.08), dur * 0.6)

		Atk.HEAVY:
			# Magenta/red pulsing orb + danger ring appears
			_charge_mat.albedo_color = Color(1.0, 0.04, 0.55)
			_charge_mat.emission     = Color(1.0, 0.04, 0.55)
			_charge_orb.scale        = Vector3.ZERO
			_danger_ring.visible     = true
			_danger_ring.scale       = Vector3.ZERO
			_active_tw = create_tween().set_parallel(true)
			_active_tw.tween_property(_charge_orb,   "scale",        Vector3.ONE * 2.2,        dur * 0.85)
			_active_tw.tween_property(_danger_ring,  "scale",        Vector3.ONE,              dur * 0.5)
			# Body pulses via a separate looping tween
			var pulse := create_tween().set_loops(int(dur / 0.35) + 1)
			pulse.tween_property(_mat, "albedo_color", Color(1.0, 0.04, 0.55), 0.18)
			pulse.tween_property(_mat, "albedo_color", Color(0.8, 0.15, 0.15), 0.17)

		Atk.COMBO:
			var is_second := step == 1
			var c := Color(1.0, 0.82, 0.05) if not is_second else Color(1.0, 0.50, 0.08)
			_charge_mat.albedo_color = c
			_charge_mat.emission     = c
			_charge_orb.scale        = Vector3.ZERO
			_active_tw = create_tween().set_parallel(true)
			_active_tw.tween_property(_charge_orb, "scale",        Vector3.ONE * 0.75,       dur)
			_active_tw.tween_property(_mat,         "albedo_color", c,                        dur * 0.5)

func _hide_windup() -> void:
	if _active_tw and _active_tw.is_running():
		_active_tw.kill()
	_charge_orb.scale    = Vector3.ZERO
	_danger_ring.visible = false
	_mat.albedo_color    = Color(0.8, 0.15, 0.15)

# ─────────────────────────────────────────────────────────────────────────────
#  Hit reception (called by Player attacks)
# ─────────────────────────────────────────────────────────────────────────────

func take_hit(dmg: float, posture_dmg: float) -> void:
	if is_dead or is_finishering:
		return

	health = max(0.0, health - dmg)
	health_changed.emit(health, max_health)
	posture_regen_timer = POSTURE_REGEN_DELAY

	# Planning-mode bonus: first hit on a marked enemy gets 1.5× posture damage
	if mark_index >= 0 and not _posture_first_hit_used:
		posture_dmg *= 1.5
		_posture_first_hit_used = true

	if not execute_ready:
		posture = min(max_posture, posture + posture_dmg)
		posture_changed.emit(posture, max_posture)
		if posture >= max_posture:
			_trigger_execute()

	_flash_hit()
	if _animator:
		_animator.force_play("hit_react")

	# Particle burst at chest height
	var impact_pos := global_position + Vector3(0, 1.0, 0)
	_spawn_impact_fx(impact_pos, Color(1.0, 0.4, 0.1))

	if health <= 0.0:
		_die()

func _spawn_impact_fx(pos: Vector3, color: Color) -> void:
	var ps := GPUParticles3D.new()
	ps.top_level       = true
	ps.global_position = pos
	ps.emitting        = false
	ps.one_shot        = true
	ps.explosiveness   = 1.0
	ps.amount          = 14
	ps.lifetime        = 0.40

	var mat := ParticleProcessMaterial.new()
	mat.direction            = Vector3(0, 1, 0)
	mat.spread               = 55.0
	mat.initial_velocity_min = 2.5
	mat.initial_velocity_max = 5.5
	mat.gravity              = Vector3(0, -6.0, 0)
	mat.scale_min            = 0.05
	mat.scale_max            = 0.12
	mat.color                = color
	ps.process_material = mat

	var sm  := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	var pm := StandardMaterial3D.new()
	pm.albedo_color              = color
	pm.emission_enabled          = true
	pm.emission                  = color
	pm.emission_energy_multiplier = 2.5
	pm.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
	ps.draw_pass_1 = sm

	get_tree().root.add_child(ps)
	ps.emitting = true
	get_tree().create_timer(0.55).timeout.connect(ps.queue_free)

# ─────────────────────────────────────────────────────────────────────────────
#  Execute system (unchanged)
# ─────────────────────────────────────────────────────────────────────────────

func attempt_execute(attacker_pos: Vector3) -> bool:
	if not execute_ready or is_dead:
		return false
	if attacker_pos.distance_to(global_position) > 3.0:
		return false

	execute_ready = false
	execute_available.emit(false)

	var would_kill := health <= EXECUTE_DAMAGE
	if would_kill:
		_play_finisher()
	else:
		health = max(0.0, health - EXECUTE_DAMAGE)
		health_changed.emit(health, max_health)
		posture = 0.0
		posture_changed.emit(posture, max_posture)
		_flash_stagger()
		if health <= 0.0:
			_die()
	return true

func set_lock_ring(on: bool) -> void:
	var ring := get_node_or_null("LockRing")
	if ring:
		ring.visible = on

func get_execute_remaining() -> float:
	return execute_timer

func _trigger_execute() -> void:
	execute_ready = true
	execute_timer = EXECUTE_WINDOW
	execute_available.emit(true)
	_hide_windup()
	_flash_stagger()

func _expire_execute() -> void:
	execute_ready = false
	execute_available.emit(false)
	health = max(1.0, health - EXPIRE_DAMAGE)
	health_changed.emit(health, max_health)
	posture = 0.0
	posture_changed.emit(posture, max_posture)
	_flash_stagger()
	# Re-enter combat after stagger
	_enter(State.RECOVERY, 0.8)

# ─────────────────────────────────────────────────────────────────────────────
#  Planning-mode API
# ─────────────────────────────────────────────────────────────────────────────

## Called by PlanningMode to mark/unmark this enemy.
## idx -1 = unmark; 1-4 = mark order.
func set_marked(idx: int) -> void:
	mark_index              = idx
	_posture_first_hit_used = false
	if idx >= 0:
		_mat.emission_enabled          = true
		_mat.emission                  = Color(0.5, 0.7, 1.0) if not is_elite \
		                                 else Color(1.0, 0.85, 0.2)
		_mat.emission_energy_multiplier = 1.4
	else:
		_mat.emission_enabled = false

# ─────────────────────────────────────────────────────────────────────────────
#  Flash helpers
# ─────────────────────────────────────────────────────────────────────────────

func _flash_hit() -> void:
	var tw := create_tween()
	tw.tween_property(_mat, "albedo_color", Color(1.0, 0.55, 0.55), 0.05)
	tw.tween_property(_mat, "albedo_color", Color(0.8, 0.15, 0.15), 0.12)

func _flash_stagger() -> void:
	var tw := create_tween()
	tw.tween_property(_mat, "albedo_color", Color(1.0, 0.95, 0.1),  0.10)
	tw.tween_property(_mat, "albedo_color", Color(0.8, 0.15, 0.15), 0.15)
	tw.tween_property(_mat, "albedo_color", Color(1.0, 0.95, 0.1),  0.10)
	tw.tween_property(_mat, "albedo_color", Color(0.8, 0.15, 0.15), 0.15)

# ─────────────────────────────────────────────────────────────────────────────
#  Parry responses (called by Player)
# ─────────────────────────────────────────────────────────────────────────────

## Returns true while the enemy is visibly telegraphing an attack (windup phase).
## Player checks this at parry press-time to classify perfect vs. block.
func is_winding_up() -> bool:
	return ai_state == State.WINDUP

## Perfect-parry stagger: long vulnerable window, cyan-white flash.
func receive_parry_stagger() -> void:
	_hide_windup()
	_enter(State.RECOVERY, 1.8)
	if _animator:
		_animator.force_play("stagger")
	# AUDIO: play parry_stagger.ogg  (heavy impact, enemy grunt)
	var tw := create_tween()
	tw.tween_property(_mat, "albedo_color", Color(0.7, 1.0, 1.0), 0.05)
	tw.tween_property(_mat, "albedo_color", Color(0.95, 0.95, 0.95), 0.20)
	tw.tween_property(_mat, "albedo_color", Color(0.8, 0.15, 0.15),  0.45)

## Block stagger: cancels an ongoing windup/attack, short recovery.
func receive_block_stagger() -> void:
	if ai_state == State.WINDUP or ai_state == State.ATTACKING:
		_hide_windup()
		_enter(State.RECOVERY, 0.45)
	# AUDIO: play block_stagger.ogg  (short clang, medium pitch)
	var tw := create_tween()
	tw.tween_property(_mat, "albedo_color", Color(0.65, 0.65, 1.0), 0.05)
	tw.tween_property(_mat, "albedo_color", Color(0.8, 0.15, 0.15), 0.22)

func _play_finisher() -> void:
	is_finishering = true
	_hide_windup()
	# Stop animator so tween has full control of the mesh
	if _animator:
		_animator.stop()
	var tw := create_tween()
	tw.tween_property(_mat,  "albedo_color", Color(1, 1, 1),             0.15)
	tw.tween_interval(0.3)
	tw.tween_property(_mesh, "scale",        Vector3(1.4, 0.05, 1.4),    0.45)
	tw.tween_callback(_die)

func _die() -> void:
	if is_dead:
		return
	is_dead = true
	_hide_windup()
	died.emit()
	if not is_finishering:
		if _animator:
			_animator.force_play("death")
		else:
			var tw := create_tween()
			tw.tween_property(_mesh, "scale", Vector3(1.0, 0.05, 1.0), 0.5)
