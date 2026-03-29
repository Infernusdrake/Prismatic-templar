class_name Player
extends CharacterBody3D

const SPEED := 5.0
const GRAVITY := 9.8
const DODGE_SPEED := 14.0
const DODGE_DURATION := 0.35
const DODGE_COOLDOWN := 0.8

const ATTACK_DAMAGE    := [8.0,  8.0,  18.0]
const ATTACK_POSTURE   := [10.0, 12.0, 28.0]
const ATTACK_DURATION  := [0.35, 0.35, 0.50]
const ATTACK_HIT_FRAME := [0.15, 0.15, 0.22]

var health     := 100.0
var max_health := 100.0

var is_dodging      := false
var is_invincible   := false
var dodge_timer     := 0.0
var dodge_cooldown  := 0.0
var dodge_dir       := Vector3.ZERO

var combo_index    := 0
var is_attacking   := false
var attack_timer   := 0.0
var combo_buffer   := false
var hit_registered := false

var locked_on      := false
var lock_on_target: Node3D = null

# Set by Arena after instantiation
var enemy: Node3D   = null
var camera_rig: Node3D = null

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D

signal health_changed(val: float, max_val: float)
signal died

func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.25, 0.5, 0.9)

	_mesh = MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.4
	cm.height = 1.8
	_mesh.mesh = cm
	_mesh.material_override = _mat
	_mesh.position.y = 0.9
	add_child(_mesh)

	var col := CollisionShape3D.new()
	var cs := CapsuleShape3D.new()
	cs.radius = 0.4
	cs.height = 1.8
	col.shape = cs
	col.position.y = 0.9
	add_child(col)

func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_handle_dodge(delta)
	_handle_attack(delta)
	_handle_movement(delta)
	_handle_lockon()
	move_and_slide()

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

func _handle_movement(delta: float) -> void:
	if is_dodging:
		velocity.x = dodge_dir.x * DODGE_SPEED
		velocity.z = dodge_dir.z * DODGE_SPEED
		return

	var input_dir := _read_input_dir()

	var cam_fwd := Vector3(0, 0, -1)
	var cam_right := Vector3(1, 0, 0)
	if camera_rig:
		var b := camera_rig.global_basis
		cam_fwd   = Vector3(-b.z.x, 0, -b.z.z).normalized()
		cam_right = Vector3( b.x.x, 0,  b.x.z).normalized()

	var move_dir := (cam_fwd * -input_dir.y + cam_right * input_dir.x)

	if is_attacking:
		velocity.x = move_toward(velocity.x, 0, SPEED * 8 * delta)
		velocity.z = move_toward(velocity.z, 0, SPEED * 8 * delta)
	else:
		velocity.x = move_dir.x * SPEED
		velocity.z = move_dir.z * SPEED

	if locked_on and lock_on_target:
		var look_pos := Vector3(lock_on_target.global_position.x,
								global_position.y,
								lock_on_target.global_position.z)
		look_at(look_pos)
	elif move_dir.length() > 0.05 and not is_attacking:
		look_at(global_position + move_dir)

func _handle_dodge(delta: float) -> void:
	if dodge_cooldown > 0:
		dodge_cooldown -= delta

	if is_dodging:
		dodge_timer -= delta
		is_invincible = dodge_timer > 0.05
		if dodge_timer <= 0:
			is_dodging   = false
			is_invincible = false
		return

	if Input.is_action_just_pressed("dodge") and dodge_cooldown <= 0 and not is_attacking:
		var input_dir := _read_input_dir()
		var cam_fwd   := Vector3(0, 0, -1)
		var cam_right := Vector3(1, 0, 0)
		if camera_rig:
			var b := camera_rig.global_basis
			cam_fwd   = Vector3(-b.z.x, 0, -b.z.z).normalized()
			cam_right = Vector3( b.x.x, 0,  b.x.z).normalized()

		if input_dir == Vector2.ZERO:
			dodge_dir = -global_transform.basis.z
		else:
			dodge_dir = (cam_fwd * -input_dir.y + cam_right * input_dir.x).normalized()

		is_dodging    = true
		is_invincible = true
		dodge_timer   = DODGE_DURATION
		dodge_cooldown = DODGE_COOLDOWN

		# Dodge flash
		var tw := create_tween()
		tw.tween_property(_mat, "albedo_color", Color(0.6, 0.9, 1.0), 0.05)
		tw.tween_property(_mat, "albedo_color", Color(0.25, 0.5, 0.9), 0.2)

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
	tw.tween_property(_mat, "albedo_color", col, 0.05)
	tw.tween_property(_mat, "albedo_color", Color(0.25, 0.5, 0.9), 0.15)

func _try_land_hit() -> void:
	if enemy == null:
		return
	if global_position.distance_to(enemy.global_position) <= 2.8:
		enemy.take_hit(ATTACK_DAMAGE[combo_index - 1], ATTACK_POSTURE[combo_index - 1])

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

func take_damage(amount: float) -> void:
	if is_invincible:
		return
	health = max(0.0, health - amount)
	health_changed.emit(health, max_health)

	var tw := create_tween()
	tw.tween_property(_mat, "albedo_color", Color(1, 0.3, 0.3), 0.05)
	tw.tween_property(_mat, "albedo_color", Color(0.25, 0.5, 0.9), 0.15)

	if health <= 0:
		died.emit()

func _read_input_dir() -> Vector2:
	var d := Vector2.ZERO
	if Input.is_action_pressed("move_forward"): d.y -= 1
	if Input.is_action_pressed("move_back"):    d.y += 1
	if Input.is_action_pressed("move_left"):    d.x -= 1
	if Input.is_action_pressed("move_right"):   d.x += 1
	return d.normalized() if d != Vector2.ZERO else Vector2.ZERO
