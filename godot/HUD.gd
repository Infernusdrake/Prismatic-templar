class_name HUD
extends CanvasLayer

var _player_hp_bar:  ProgressBar
var _enemy_hp_bar:   ProgressBar
var _posture_bar:    ProgressBar
var _execute_panel:  Panel
var _exec_timer_lbl: Label
var _combo_lbl:      Label
var _lockon_lbl:     Label
var _msg_lbl:        Label
var _msg_timer:      float = 0.0

var _exec_countdown := 0.0
var _exec_active    := false

# ── Parry feedback ────────────────────────────────────────────────────────────
var _parry_lbl:      Label    # flashes "PERFECT PARRY" / "BLOCK" / "MISS"
var _parry_timer:    float = 0.0

# ── Punish window ─────────────────────────────────────────────────────────────
var _punish_panel:   Panel
var _punish_bar:     ProgressBar
var _punish_lbl:     Label
var _punish_active   := false
var _punish_duration := 0.0
var _punish_remaining := 0.0
var _punish_tw:      Tween = null

func _ready() -> void:
	layer = 10
	_build()

func _process(delta: float) -> void:
	# Execute countdown
	if _exec_active:
		_exec_countdown -= delta
		if _exec_timer_lbl:
			_exec_timer_lbl.text = "%.1f" % max(0.0, _exec_countdown)

	# Timed message
	if _msg_timer > 0.0:
		_msg_timer -= delta
		if _msg_timer <= 0.0 and _msg_lbl:
			_msg_lbl.visible = false

	# Parry result label fade-out
	if _parry_timer > 0.0:
		_parry_timer -= delta
		if _parry_lbl:
			_parry_lbl.modulate.a = clamp(_parry_timer * 3.5, 0.0, 1.0)
		if _parry_timer <= 0.0 and _parry_lbl:
			_parry_lbl.visible = false

	# Punish window countdown
	if _punish_active:
		_punish_remaining -= delta
		if _punish_remaining <= 0.0:
			_punish_active = false
			if _punish_panel:
				_punish_panel.visible = false
		elif _punish_bar:
			_punish_bar.value = max(0.0, _punish_remaining)

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- Player health (bottom-left) ---
	var pl_vbox := VBoxContainer.new()
	pl_vbox.set_anchor_and_offset(SIDE_LEFT,   0, 20)
	pl_vbox.set_anchor_and_offset(SIDE_RIGHT,  0, 240)
	pl_vbox.set_anchor_and_offset(SIDE_TOP,    1, -90)
	pl_vbox.set_anchor_and_offset(SIDE_BOTTOM, 1, -20)
	root.add_child(pl_vbox)

	var pl_lbl := Label.new()
	pl_lbl.text = "PLAYER  HP"
	pl_lbl.add_theme_color_override("font_color", Color.WHITE)
	pl_vbox.add_child(pl_lbl)

	_player_hp_bar = ProgressBar.new()
	_player_hp_bar.custom_minimum_size = Vector2(200, 22)
	_player_hp_bar.max_value           = 100
	_player_hp_bar.value               = 100
	_player_hp_bar.show_percentage     = false
	_add_bar_fill(_player_hp_bar, Color(0.2, 0.7, 0.25))
	pl_vbox.add_child(_player_hp_bar)

	# --- Enemy section (top-center) ---
	var en_vbox := VBoxContainer.new()
	en_vbox.set_anchor_and_offset(SIDE_LEFT,   0.5, -160)
	en_vbox.set_anchor_and_offset(SIDE_RIGHT,  0.5,  160)
	en_vbox.set_anchor_and_offset(SIDE_TOP,    0,    20)
	en_vbox.set_anchor_and_offset(SIDE_BOTTOM, 0,   110)
	root.add_child(en_vbox)

	var en_name := Label.new()
	en_name.text = "ENEMY"
	en_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	en_name.add_theme_color_override("font_color", Color.WHITE)
	en_vbox.add_child(en_name)

	_enemy_hp_bar = ProgressBar.new()
	_enemy_hp_bar.custom_minimum_size = Vector2(300, 22)
	_enemy_hp_bar.max_value           = 100
	_enemy_hp_bar.value               = 100
	_enemy_hp_bar.show_percentage     = false
	_add_bar_fill(_enemy_hp_bar, Color(0.8, 0.15, 0.15))
	en_vbox.add_child(_enemy_hp_bar)

	var pt_lbl := Label.new()
	pt_lbl.text = "POSTURE"
	pt_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	en_vbox.add_child(pt_lbl)

	_posture_bar = ProgressBar.new()
	_posture_bar.custom_minimum_size = Vector2(300, 16)
	_posture_bar.max_value           = 100
	_posture_bar.value               = 0
	_posture_bar.show_percentage     = false
	_add_bar_fill(_posture_bar, Color(0.95, 0.75, 0.1))
	en_vbox.add_child(_posture_bar)

	# --- Execute prompt (center) ---
	_execute_panel = Panel.new()
	_execute_panel.set_anchor_and_offset(SIDE_LEFT,   0.5, -130)
	_execute_panel.set_anchor_and_offset(SIDE_RIGHT,  0.5,  130)
	_execute_panel.set_anchor_and_offset(SIDE_TOP,    0.5, -55)
	_execute_panel.set_anchor_and_offset(SIDE_BOTTOM, 0.5,  55)
	_execute_panel.visible = false
	var p_style := StyleBoxFlat.new()
	p_style.bg_color            = Color(0.05, 0.02, 0.0, 0.85)
	p_style.border_width_left   = 2
	p_style.border_width_right  = 2
	p_style.border_width_top    = 2
	p_style.border_width_bottom = 2
	p_style.border_color        = Color(1.0, 0.85, 0.1)
	_execute_panel.add_theme_stylebox_override("panel", p_style)
	root.add_child(_execute_panel)

	var exec_vbox := VBoxContainer.new()
	exec_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	exec_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_execute_panel.add_child(exec_vbox)

	var exec_title := Label.new()
	exec_title.text = ">>> EXECUTE <<<"
	exec_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	exec_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.1))
	exec_title.add_theme_font_size_override("font_size", 20)
	exec_vbox.add_child(exec_title)

	var exec_hint := Label.new()
	exec_hint.text = "Press  [ E ]"
	exec_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	exec_hint.add_theme_color_override("font_color", Color.WHITE)
	exec_vbox.add_child(exec_hint)

	_exec_timer_lbl = Label.new()
	_exec_timer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_exec_timer_lbl.add_theme_color_override("font_color", Color(1.0, 0.45, 0.1))
	_exec_timer_lbl.add_theme_font_size_override("font_size", 22)
	exec_vbox.add_child(_exec_timer_lbl)

	# --- Combo indicator (right-center) ---
	_combo_lbl = Label.new()
	_combo_lbl.set_anchor_and_offset(SIDE_LEFT,   1, -250)
	_combo_lbl.set_anchor_and_offset(SIDE_RIGHT,  1,  -20)
	_combo_lbl.set_anchor_and_offset(SIDE_TOP,    0.5, -20)
	_combo_lbl.set_anchor_and_offset(SIDE_BOTTOM, 0.5,  20)
	_combo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combo_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	_combo_lbl.add_theme_font_size_override("font_size", 22)
	root.add_child(_combo_lbl)

	# --- Lock-on indicator (bottom-right) ---
	_lockon_lbl = Label.new()
	_lockon_lbl.text = "[ LOCK-ON ]"
	_lockon_lbl.set_anchor_and_offset(SIDE_LEFT,   1, -160)
	_lockon_lbl.set_anchor_and_offset(SIDE_RIGHT,  1,  -20)
	_lockon_lbl.set_anchor_and_offset(SIDE_TOP,    1,  -50)
	_lockon_lbl.set_anchor_and_offset(SIDE_BOTTOM, 1,  -20)
	_lockon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_lockon_lbl.add_theme_color_override("font_color", Color(0.2, 1.0, 0.8))
	_lockon_lbl.visible = false
	root.add_child(_lockon_lbl)

	# --- Controls hint (bottom-center) ---
	var hint := Label.new()
	hint.text = "WASD Move  |  Space Dodge  |  LMB Attack  |  Q Parry  |  F Lock-on  |  E Execute  |  Tab Plan"
	hint.set_anchor_and_offset(SIDE_LEFT,   0.5, -420)
	hint.set_anchor_and_offset(SIDE_RIGHT,  0.5,  420)
	hint.set_anchor_and_offset(SIDE_TOP,    1,    -22)
	hint.set_anchor_and_offset(SIDE_BOTTOM, 1,      0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	hint.add_theme_font_size_override("font_size", 13)
	root.add_child(hint)

	# --- Parry result flash (center-left, brief) ---
	_parry_lbl = Label.new()
	_parry_lbl.set_anchor_and_offset(SIDE_LEFT,   0.5, -320)
	_parry_lbl.set_anchor_and_offset(SIDE_RIGHT,  0.5,   80)
	_parry_lbl.set_anchor_and_offset(SIDE_TOP,    0.5,  -15)
	_parry_lbl.set_anchor_and_offset(SIDE_BOTTOM, 0.5,   25)
	_parry_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_parry_lbl.add_theme_font_size_override("font_size", 28)
	_parry_lbl.visible = false
	root.add_child(_parry_lbl)

	# --- Punish window panel (right side, below combo) ---
	_punish_panel = Panel.new()
	_punish_panel.set_anchor_and_offset(SIDE_LEFT,   1, -230)
	_punish_panel.set_anchor_and_offset(SIDE_RIGHT,  1,  -20)
	_punish_panel.set_anchor_and_offset(SIDE_TOP,    0.5,  28)
	_punish_panel.set_anchor_and_offset(SIDE_BOTTOM, 0.5,  82)
	_punish_panel.visible = false
	var pu_style := StyleBoxFlat.new()
	pu_style.bg_color            = Color(0.06, 0.04, 0.0, 0.88)
	pu_style.border_width_left   = 2
	pu_style.border_width_right  = 2
	pu_style.border_width_top    = 2
	pu_style.border_width_bottom = 2
	pu_style.border_color        = Color(1.0, 0.88, 0.1)
	_punish_panel.add_theme_stylebox_override("panel", pu_style)
	root.add_child(_punish_panel)

	var pu_vbox := VBoxContainer.new()
	pu_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	pu_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_punish_panel.add_child(pu_vbox)

	_punish_lbl = Label.new()
	_punish_lbl.text = "◆ PUNISH WINDOW ◆"
	_punish_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_punish_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.1))
	_punish_lbl.add_theme_font_size_override("font_size", 13)
	pu_vbox.add_child(_punish_lbl)

	_punish_bar = ProgressBar.new()
	_punish_bar.custom_minimum_size = Vector2(170, 10)
	_punish_bar.max_value           = 3.5
	_punish_bar.value               = 3.5
	_punish_bar.show_percentage     = false
	_add_bar_fill(_punish_bar, Color(1.0, 0.85, 0.1))
	pu_vbox.add_child(_punish_bar)

	# --- Message overlay (center, big) ---
	_msg_lbl = Label.new()
	_msg_lbl.set_anchor_and_offset(SIDE_LEFT,   0.5, -300)
	_msg_lbl.set_anchor_and_offset(SIDE_RIGHT,  0.5,  300)
	_msg_lbl.set_anchor_and_offset(SIDE_TOP,    0.5, -40)
	_msg_lbl.set_anchor_and_offset(SIDE_BOTTOM, 0.5,  40)
	_msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.1))
	_msg_lbl.add_theme_font_size_override("font_size", 44)
	_msg_lbl.visible = false
	root.add_child(_msg_lbl)

func _add_bar_fill(bar: ProgressBar, color: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	bar.add_theme_stylebox_override("fill", s)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.15, 0.15)
	bar.add_theme_stylebox_override("background", bg)

# ─────────────────────────────────────────────────────────────────────────────
#  Public API
# ─────────────────────────────────────────────────────────────────────────────

func update_player_health(val: float, max_val: float) -> void:
	if _player_hp_bar:
		_player_hp_bar.max_value = max_val
		_player_hp_bar.value     = val

func update_enemy_health(val: float, max_val: float) -> void:
	if _enemy_hp_bar:
		_enemy_hp_bar.max_value = max_val
		_enemy_hp_bar.value     = val

func update_enemy_posture(val: float, max_val: float) -> void:
	if _posture_bar:
		_posture_bar.max_value = max_val
		_posture_bar.value     = val

func show_execute(on: bool, window: float = 2.0) -> void:
	_exec_active    = on
	_exec_countdown = window
	if _execute_panel:
		_execute_panel.visible = on

func update_combo(index: int) -> void:
	if _combo_lbl:
		var filled = "●".repeat(index)
		var empty = "○".repeat(3 - index)
		_combo_lbl.text = "  HIT  " + filled + empty if index > 0 else ""

func update_lockon(on: bool) -> void:
	if _lockon_lbl:
		_lockon_lbl.visible = on

func show_message(text: String, duration: float = 3.0) -> void:
	if _msg_lbl:
		_msg_lbl.text    = text
		_msg_lbl.visible = true
		_msg_timer       = duration

## Show a brief parry outcome label.  result = "perfect" | "block" | "miss"
func show_parry_result(result: String) -> void:
	if not _parry_lbl:
		return
	match result:
		"perfect":
			_parry_lbl.text = "◆ PERFECT PARRY ◆"
			_parry_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.15))
			_parry_lbl.add_theme_font_size_override("font_size", 30)
			_parry_timer = 1.5
			# Animate: scale punch then settle
			_parry_lbl.scale = Vector3(1.4, 1.4, 1.0)
			var tw := _parry_lbl.create_tween()
			tw.tween_property(_parry_lbl, "scale", Vector3.ONE, 0.25) \
					.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		"block":
			_parry_lbl.text = "BLOCK"
			_parry_lbl.add_theme_color_override("font_color", Color(0.5, 0.78, 1.0))
			_parry_lbl.add_theme_font_size_override("font_size", 24)
			_parry_timer = 0.9
			_parry_lbl.scale = Vector3.ONE
		"miss":
			_parry_lbl.text = "MISS"
			_parry_lbl.add_theme_color_override("font_color", Color(0.75, 0.22, 0.22))
			_parry_lbl.add_theme_font_size_override("font_size", 19)
			_parry_timer = 0.65
			_parry_lbl.scale = Vector3.ONE
	_parry_lbl.modulate.a = 1.0
	_parry_lbl.visible    = true

## Open or close the punish window countdown.
func set_punish_window(active: bool, duration: float) -> void:
	_punish_active    = active
	_punish_duration  = duration
	_punish_remaining = duration
	if _punish_panel:
		_punish_panel.visible = active
	if _punish_bar:
		_punish_bar.max_value = max(duration, 0.01)
		_punish_bar.value     = duration
	if active and _punish_lbl:
		# Pulse the label while open
		if _punish_tw and _punish_tw.is_running():
			_punish_tw.kill()
		_punish_tw = _punish_lbl.create_tween().set_loops()
		_punish_tw.tween_property(_punish_lbl, "modulate",
				Color(1.0, 0.88, 0.1, 0.4), 0.35)
		_punish_tw.tween_property(_punish_lbl, "modulate",
				Color(1.0, 0.88, 0.1, 1.0), 0.35)
	elif not active:
		if _punish_tw and _punish_tw.is_running():
			_punish_tw.kill()
