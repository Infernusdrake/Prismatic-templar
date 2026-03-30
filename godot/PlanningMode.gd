class_name PlanningMode
extends Node

# ── Constants ─────────────────────────────────────────────────────────────────
const MAX_MARKS   := 4
const DESAT_VALUE := 0.15     # world saturation while planning
const HOLD_ACTION := "planning_mode"

# Mark number glyphs ①②③④
const MARK_GLYPHS := ["①", "②", "③", "④"]

# ── References (set by Arena.setup()) ────────────────────────────────────────
var _player:   Player
var _enemies:  Array          # Array[Enemy]
var _cam_rig:  CameraRig
var _env:      Environment

# ── State ─────────────────────────────────────────────────────────────────────
var is_active:      bool  = false
var marked_enemies: Array = []   # ordered Array[Enemy], up to MAX_MARKS

# ── Overlay ───────────────────────────────────────────────────────────────────
var _layer:       CanvasLayer
var _vignette:    ColorRect       # dark fullscreen tint
var _cards:       Array = []      # Array[Control], one per enemy
var _card_marks:  Array = []      # Array[Label], mark glyph per card
var _desat_tw:    Tween = null

# ─────────────────────────────────────────────────────────────────────────────
#  Setup (called by Arena before the scene tree settles)
# ─────────────────────────────────────────────────────────────────────────────

func setup(player: Player, enemies: Array, cam_rig: CameraRig, env: Environment) -> void:
	_player  = player
	_enemies = enemies
	_cam_rig = cam_rig
	_env     = env
	_build_overlay()

func _ready() -> void:
	pass

# ─────────────────────────────────────────────────────────────────────────────
#  Overlay construction
# ─────────────────────────────────────────────────────────────────────────────

func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 20        # above HUD (layer 10)
	add_child(_layer)

	# Fullscreen dark vignette (hidden until active)
	_vignette = ColorRect.new()
	_vignette.color = Color(0.0, 0.0, 0.05, 0.45)
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.visible = false
	_layer.add_child(_vignette)

	# Build one card per enemy (all hidden initially)
	for i in _enemies.size():
		var card := _build_card(_enemies[i] as Enemy, i)
		_layer.add_child(card)
		_cards.append(card)

func _build_card(enemy: Enemy, idx: int) -> Control:
	# Root container — acts as the clickable card
	var root := Control.new()
	root.custom_minimum_size = Vector2(180, 84)
	root.visible = false

	# Background panel with styled border
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color          = Color(0.04, 0.04, 0.10, 0.88)
	style.border_width_left   = 2
	style.border_width_right  = 2
	style.border_width_top    = 2
	style.border_width_bottom = 2
	var border_col := Color(1.0, 0.85, 0.10) if enemy.is_elite \
					  else Color(0.78, 0.78, 0.88)
	style.border_color    = border_col
	style.corner_radius_top_left     = 4
	style.corner_radius_top_right    = 4
	style.corner_radius_bottom_left  = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)

	# Content layout
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",   8)
	margin.add_theme_constant_override("margin_right",  8)
	margin.add_theme_constant_override("margin_top",    6)
	margin.add_theme_constant_override("margin_bottom", 6)
	root.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)

	# ── Row 1: [crown] [mark glyph] [name] ───────────────────────────────────
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 3)
	vbox.add_child(row1)

	# Crown label (elite only)
	if enemy.is_elite:
		var crown := Label.new()
		crown.text = "♛"
		crown.add_theme_color_override("font_color", Color(1.0, 0.85, 0.10))
		crown.add_theme_font_size_override("font_size", 14)
		row1.add_child(crown)

	# Mark glyph (updated each frame)
	var mark_lbl := Label.new()
	mark_lbl.text = ""
	mark_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.3))
	mark_lbl.add_theme_font_size_override("font_size", 14)
	row1.add_child(mark_lbl)
	_card_marks.append(mark_lbl)

	# Enemy name
	var name_lbl := Label.new()
	name_lbl.text = enemy.enemy_name
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	name_lbl.add_theme_font_size_override("font_size", 14)
	row1.add_child(name_lbl)

	# ── Row 2: [gem dot] [gem type] ──────────────────────────────────────────
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 5)
	vbox.add_child(row2)

	var gem_dot := ColorRect.new()
	gem_dot.custom_minimum_size = Vector2(12, 12)
	gem_dot.color = enemy.gem_color
	# Centre the dot vertically inside the row
	var dot_wrap := CenterContainer.new()
	dot_wrap.custom_minimum_size = Vector2(12, 18)
	dot_wrap.add_child(gem_dot)
	row2.add_child(dot_wrap)

	var gem_lbl := Label.new()
	gem_lbl.text = enemy.gem_type
	gem_lbl.add_theme_color_override("font_color", enemy.gem_color.lightened(0.2))
	gem_lbl.add_theme_font_size_override("font_size", 11)
	row2.add_child(gem_lbl)

	# ── Row 3: trait ─────────────────────────────────────────────────────────
	var trait_lbl := Label.new()
	trait_lbl.text = enemy.combat_trait
	trait_lbl.add_theme_color_override("font_color", Color(0.62, 0.62, 0.72))
	trait_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(trait_lbl)

	# ── Invisible click button over the whole card ────────────────────────────
	var btn := Button.new()
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.flat = true
	# Make the button visually invisible
	var empty_style := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal",   empty_style)
	btn.add_theme_stylebox_override("hover",    empty_style)
	btn.add_theme_stylebox_override("pressed",  empty_style)
	btn.add_theme_stylebox_override("focus",    empty_style)
	btn.pressed.connect(_on_card_clicked.bind(idx))
	root.add_child(btn)

	return root

# ─────────────────────────────────────────────────────────────────────────────
#  Per-frame
# ─────────────────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	# Hold → activate; release → deactivate
	if Input.is_action_just_pressed(HOLD_ACTION) and not is_active:
		_activate()
	elif Input.is_action_just_released(HOLD_ACTION) and is_active:
		_deactivate()

	if not is_active:
		return

	# Project each enemy's position to screen and reposition its card
	var cam := _cam_rig.get_node("Camera3D") as Camera3D
	if cam == null:
		return
	for i in _enemies.size():
		var e := _enemies[i] as Enemy
		if e.is_dead:
			_cards[i].visible = false
			continue
		_cards[i].visible = true
		var world_pt := e.global_position + Vector3(0, 2.6, 0)
		var screen_pt := cam.unproject_position(world_pt)
		# Only show card if the point is in front of the camera
		var local_pt := cam.global_transform.affine_inverse() * world_pt
		if local_pt.z >= 0:
			_cards[i].visible = false
			continue
		_cards[i].global_position = screen_pt - _cards[i].size * 0.5
		# Refresh mark glyph
		var e_mark: int = e.mark_index
		_card_marks[i].text = MARK_GLYPHS[e_mark - 1] if e_mark >= 1 and e_mark <= MAX_MARKS else ""

# ─────────────────────────────────────────────────────────────────────────────
#  Activate / Deactivate
# ─────────────────────────────────────────────────────────────────────────────

func _activate() -> void:
	is_active = true

	# Freeze the world (AI + player physics pause; hit-stop uses real time so unaffected)
	Engine.time_scale = 0.0

	# Show vignette
	_vignette.visible = true
	_vignette.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_vignette, "modulate:a", 1.0, 0.25)

	# Desaturate world
	_env.adjustment_enabled    = true
	_env.adjustment_saturation = 1.0
	_kill_desat_tw()
	_desat_tw = create_tween()
	_desat_tw.tween_property(_env, "adjustment_saturation", DESAT_VALUE, 0.30)

	# Pull camera back
	_cam_rig.set_planning_mode(true)

	# Show cards (positions updated in _process)
	for i in _cards.size():
		if not (_enemies[i] as Enemy).is_dead:
			_cards[i].visible = true

	# Release mouse so player can click cards
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _deactivate() -> void:
	is_active = false

	# Hide cards
	for card in _cards:
		card.visible = false
	_vignette.visible = false

	# Restore saturation
	_kill_desat_tw()
	_desat_tw = create_tween()
	_desat_tw.tween_property(_env, "adjustment_saturation", 1.0, 0.30)
	_desat_tw.tween_callback(func() -> void: _env.adjustment_enabled = false)

	# Restore camera distance
	_cam_rig.set_planning_mode(false)

	# Recapture mouse for camera look
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Restore time — but only if we're not about to freeze for the opener
	# (opener restores it once player moves)
	Engine.time_scale = 1.0

	# Trigger opener if enemies are marked
	if marked_enemies.size() > 0:
		_trigger_opener()

func _kill_desat_tw() -> void:
	if _desat_tw and _desat_tw.is_running():
		_desat_tw.kill()
	_desat_tw = null

# ─────────────────────────────────────────────────────────────────────────────
#  Mark management
# ─────────────────────────────────────────────────────────────────────────────

func _on_card_clicked(idx: int) -> void:
	var e := _enemies[idx] as Enemy
	if e.is_dead:
		return
	if e.mark_index >= 0:
		# Unmark this enemy
		marked_enemies.erase(e)
		e.set_marked(-1)
		_renumber_marks()
	elif marked_enemies.size() < MAX_MARKS:
		# Mark with the next available number
		marked_enemies.append(e)
		e.set_marked(marked_enemies.size())   # 1-based

func _renumber_marks() -> void:
	for i in marked_enemies.size():
		(marked_enemies[i] as Enemy).set_marked(i + 1)

# ─────────────────────────────────────────────────────────────────────────────
#  Cinematic opener
# ─────────────────────────────────────────────────────────────────────────────

func _trigger_opener() -> void:
	# Find the first non-elite marked enemy
	var opener_tgt: Enemy = null
	for e in marked_enemies:
		if not (e as Enemy).is_elite:
			opener_tgt = e as Enemy
			break

	if opener_tgt == null:
		# Only elites were marked — skip opener, just aggro from mark 3+
		_aggro_from_mark(3)
		return

	# Hand off to Player's opener state machine
	_player.start_opener(opener_tgt)
	_player.opener_finished.connect(_on_opener_finished, CONNECT_ONE_SHOT)

func _on_opener_finished() -> void:
	# Enemies at mark 3+ immediately enter chase to create pressure
	_aggro_from_mark(3)

func _aggro_from_mark(from_mark: int) -> void:
	for e in marked_enemies:
		var en := e as Enemy
		if en.mark_index >= from_mark and not en.is_dead:
			en._enter(Enemy.State.CHASE)
