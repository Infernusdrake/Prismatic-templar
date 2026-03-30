extends Node3D

var _player:  Player
var _enemies: Array[Enemy] = []
var _hud:     HUD
var _cam:     CameraRig
var _plan:    PlanningMode
var _env:     Environment    # stored for planning-mode desaturation

var _game_over := false

func _ready() -> void:
	_setup_input_map()
	_build_environment()
	_build_lighting()
	_build_ground()
	_build_walls()
	_spawn_player()
	_spawn_enemies()
	_spawn_camera()
	_spawn_hud()
	_spawn_planning_mode()
	# Connect after one frame so all _ready() calls have finished
	call_deferred("_connect_signals")

# ──────────────────────────────────────────────
#  Input
# ──────────────────────────────────────────────

func _setup_input_map() -> void:
	var key_actions := {
		"move_forward":  KEY_W,
		"move_back":     KEY_S,
		"move_left":     KEY_A,
		"move_right":    KEY_D,
		"dodge":         KEY_SPACE,
		"lock_on":       KEY_F,          # moved from Tab — Tab is now planning mode
		"execute":       KEY_E,
		"parry":         KEY_Q,
		"restart":       KEY_R,
		"planning_mode": KEY_Z,
	}
	for name in key_actions:
		if not InputMap.has_action(name):
			InputMap.add_action(name)
		var ev := InputEventKey.new()
		ev.keycode = key_actions[name]
		InputMap.action_add_event(name, ev)

	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("attack", mb)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()

# ──────────────────────────────────────────────
#  World building
# ──────────────────────────────────────────────

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode      = Environment.BG_COLOR
	_env.background_color     = Color(0.05, 0.05, 0.10)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color  = Color(0.40, 0.40, 0.50)
	_env.ambient_light_energy = 0.65
	we.environment = _env
	add_child(we)

func _build_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -30, 0)
	sun.light_energy     = 1.6
	sun.shadow_enabled   = true
	add_child(sun)

func _build_ground() -> void:
	var body := StaticBody3D.new()

	var mi  := MeshInstance3D.new()
	var pm  := PlaneMesh.new()
	pm.size = Vector2(32, 32)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.18, 0.22)
	mi.material_override = mat
	body.add_child(mi)

	var col   := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size      = Vector3(32, 0.1, 32)
	col.shape       = shape
	col.position.y  = -0.05
	body.add_child(col)

	add_child(body)
	_add_grid()

func _add_grid() -> void:
	var im := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var half := 14
	for i in range(-half, half + 1, 2):
		mesh.surface_set_color(Color(0.3, 0.3, 0.35))
		mesh.surface_add_vertex(Vector3(i, 0.01, -half))
		mesh.surface_add_vertex(Vector3(i, 0.01,  half))
		mesh.surface_add_vertex(Vector3(-half, 0.01, i))
		mesh.surface_add_vertex(Vector3( half, 0.01, i))
	mesh.surface_end()
	im.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color               = Color(0.3, 0.3, 0.38)
	mat.vertex_color_use_as_albedo = true
	im.material_override = mat
	add_child(im)

func _build_walls() -> void:
	var positions := [
		[Vector3(0,  1.5, -16), Vector3(32, 3, 0.5)],
		[Vector3(0,  1.5,  16), Vector3(32, 3, 0.5)],
		[Vector3(-16, 1.5,  0), Vector3(0.5, 3, 32)],
		[Vector3( 16, 1.5,  0), Vector3(0.5, 3, 32)],
	]
	for p in positions:
		var wall  := StaticBody3D.new()
		var mi    := MeshInstance3D.new()
		var bm    := BoxMesh.new()
		bm.size   = p[1]
		mi.mesh   = bm
		var mat   := StandardMaterial3D.new()
		mat.albedo_color = Color(0.25, 0.25, 0.30)
		mi.material_override = mat
		wall.add_child(mi)
		var col   := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = p[1]
		col.shape  = shape
		wall.add_child(col)
		wall.position = p[0]
		add_child(wall)

# ──────────────────────────────────────────────
#  Entity spawning
# ──────────────────────────────────────────────

func _spawn_player() -> void:
	_player = Player.new()
	_player.position = Vector3(0, 0, 4)
	add_child(_player)

func _spawn_enemies() -> void:
	# Three enemies: [0] elite flanker, [1] primary (drives HUD bars), [2] back-line
	var positions := [
		Vector3(-4, 0, -6),
		Vector3( 3, 0, -7),
		Vector3( 0, 0, -11),
	]
	for i in 3:
		var e := Enemy.new()
		e.position = positions[i]
		e.target   = _player
		if i == 0:
			e.is_elite   = true
			e.enemy_name = "Crux"
		add_child(e)
		_enemies.append(e)

	_player.enemy = _enemies[1]   # default combat reference

func _spawn_camera() -> void:
	_cam = CameraRig.new()
	_cam.target = _player
	add_child(_cam)
	_player.camera_rig = _cam

func _spawn_hud() -> void:
	_hud = HUD.new()
	add_child(_hud)

func _spawn_planning_mode() -> void:
	_plan = PlanningMode.new()
	add_child(_plan)
	_plan.setup(_player, _enemies, _cam, _env)

# ──────────────────────────────────────────────
#  Signal connections
# ──────────────────────────────────────────────

func _connect_signals() -> void:
	_player.health_changed.connect(_hud.update_player_health)
	_player.died.connect(_on_player_died)
	_player.parry_result.connect(_hud.show_parry_result)
	_player.punish_window_changed.connect(_hud.set_punish_window)

	# Only the primary non-elite enemy (index 1) drives the HUD health/posture bars
	_enemies[1].health_changed.connect(_hud.update_enemy_health)
	_enemies[1].posture_changed.connect(_hud.update_enemy_posture)

	for e in _enemies:
		e.execute_available.connect(_on_execute_available)
		e.died.connect(_on_enemy_died)

# ──────────────────────────────────────────────
#  Per-frame logic
# ──────────────────────────────────────────────

func _process(_delta: float) -> void:
	if _game_over:
		return

	# Execute input — check all alive enemies
	if Input.is_action_just_pressed("execute"):
		for e in _enemies:
			if not e.is_dead:
				e.attempt_execute(_player.global_position)

	# HUD updates
	if _player:
		_hud.update_combo(_player.combo_index if _player.is_attacking else 0)
		_hud.update_lockon(_player.locked_on)
		for e in _enemies:
			e.set_lock_ring(_player.locked_on and _player.lock_on_target == e)

# ──────────────────────────────────────────────
#  Event handlers
# ──────────────────────────────────────────────

func _on_execute_available(on: bool) -> void:
	_hud.show_execute(on, Enemy.EXECUTE_WINDOW)

func _on_player_died() -> void:
	_game_over = true
	_hud.show_message("YOU  DIED\n\nPress R to restart", 999.0)

func _on_enemy_died() -> void:
	for e in _enemies:
		if not e.is_dead:
			return
	_game_over = true
	_hud.show_message("ALL ENEMIES DEFEATED\n\nPress R to restart", 999.0)
