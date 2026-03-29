class_name Enemy
extends CharacterBody3D

const EXECUTE_WINDOW    := 2.0
const EXECUTE_DAMAGE    := 50.0
const EXPIRE_DAMAGE     := 25.0
const POSTURE_REGEN     := 8.0
const POSTURE_REGEN_DELAY := 2.0

var health      := 100.0
var max_health  := 100.0
var posture     := 0.0
var max_posture := 100.0

var posture_regen_timer := 0.0
var execute_ready       := false
var execute_timer       := 0.0
var is_dead             := false
var is_finishering      := false

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D

signal health_changed(val: float, max_val: float)
signal posture_changed(val: float, max_val: float)
signal execute_available(on: bool)
signal died

func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.8, 0.15, 0.15)

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

	# Lock-on ring (flat torus-ish using a cylinder)
	var ring := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius    = 0.55
	cyl.bottom_radius = 0.55
	cyl.height        = 0.06
	cyl.rings         = 1
	ring.mesh = cyl
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color   = Color(0.2, 1.0, 0.8)
	ring_mat.emission_enabled = true
	ring_mat.emission       = Color(0.2, 1.0, 0.8)
	ring_mat.emission_energy_multiplier = 1.5
	ring.material_override = ring_mat
	ring.name = "LockRing"
	ring.visible = false
	add_child(ring)

func _physics_process(delta: float) -> void:
	if is_dead:
		return

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

func take_hit(dmg: float, posture_dmg: float) -> void:
	if is_dead or is_finishering:
		return

	health = max(0.0, health - dmg)
	health_changed.emit(health, max_health)
	posture_regen_timer = POSTURE_REGEN_DELAY

	if not execute_ready:
		posture = min(max_posture, posture + posture_dmg)
		posture_changed.emit(posture, max_posture)
		if posture >= max_posture:
			_trigger_execute()

	_flash_hit()

	if health <= 0.0:
		_die()

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
	_flash_stagger()

func _expire_execute() -> void:
	execute_ready = false
	execute_available.emit(false)
	# Heavy damage on miss, never lethal (keep at 1 hp minimum)
	health = max(1.0, health - EXPIRE_DAMAGE)
	health_changed.emit(health, max_health)
	posture = 0.0
	posture_changed.emit(posture, max_posture)
	_flash_stagger()

func _flash_hit() -> void:
	var tw := create_tween()
	tw.tween_property(_mat, "albedo_color", Color(1.0, 0.55, 0.55), 0.05)
	tw.tween_property(_mat, "albedo_color", Color(0.8, 0.15, 0.15), 0.12)

func _flash_stagger() -> void:
	var tw := create_tween()
	tw.tween_property(_mat, "albedo_color", Color(1.0, 0.95, 0.1),  0.1)
	tw.tween_property(_mat, "albedo_color", Color(0.8, 0.15, 0.15), 0.15)
	tw.tween_property(_mat, "albedo_color", Color(1.0, 0.95, 0.1),  0.1)
	tw.tween_property(_mat, "albedo_color", Color(0.8, 0.15, 0.15), 0.15)

func _play_finisher() -> void:
	is_finishering = true
	# Brief white flash then squash collapse
	var tw := create_tween()
	tw.tween_property(_mat, "albedo_color", Color(1, 1, 1), 0.15)
	tw.tween_interval(0.3)
	tw.tween_property(_mesh, "scale", Vector3(1.4, 0.05, 1.4), 0.45)
	tw.tween_callback(_die)

func _die() -> void:
	if is_dead:
		return
	is_dead = true
	died.emit()
	if not is_finishering:
		var tw := create_tween()
		tw.tween_property(_mesh, "scale", Vector3(1.0, 0.05, 1.0), 0.5)
