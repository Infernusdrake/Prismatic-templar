class_name CameraRig
extends Node3D

const SENS_H   := 0.003
const SENS_V   := 0.002
const DISTANCE := 7.0
const HEIGHT   := 1.6

var target: Node3D = null
var yaw   := 0.0
var pitch := -0.38

var _shake_amt := 0.0
const SHAKE_DECAY := 14.0

func _ready() -> void:
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	add_child(cam)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and \
			Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		yaw   -= event.relative.x * SENS_H
		pitch  = clamp(pitch - event.relative.y * SENS_V, -1.1, 0.3)

	if event.is_action_pressed("ui_cancel"):
		var captured := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
		Input.set_mouse_mode(
			Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
		)

func _process(_delta: float) -> void:
	if not target:
		return

	# Yaw-only rotation on this node (player reads .global_basis for movement)
	rotation.y = yaw

	var focus := target.global_position + Vector3(0, HEIGHT * 0.5, 0)
	var cam_dir := Vector3(
		sin(yaw)  * cos(-pitch),
		sin(-pitch),
		cos(yaw)  * cos(-pitch)
	)
	var cam_pos := focus + cam_dir * DISTANCE

	# Apply screen-space shake offset
	var shake_offset := Vector3.ZERO
	if _shake_amt > 0.005:
		shake_offset = Vector3(
			randf_range(-1.0, 1.0) * _shake_amt,
			randf_range(-1.0, 1.0) * _shake_amt,
			0.0
		)
		_shake_amt = move_toward(_shake_amt, 0.0, SHAKE_DECAY * _delta)

	var cam := get_child(0) as Camera3D
	if cam:
		cam.global_position = cam_pos + shake_offset
		cam.look_at(focus, Vector3.UP)

## Add trauma to the camera shake (call from Player on hit / parry outcome).
## Multiple callers accumulate — the larger value wins.
func shake(intensity: float) -> void:
	_shake_amt = max(_shake_amt, intensity)
