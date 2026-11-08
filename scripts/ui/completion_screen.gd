class_name CompletionScreen
extends CanvasLayer

## THE END OF THE RUN, SHOWN WHEN THE SHIP HAS FLOWN.
##
## The departure cutscene hands control back to the cockpit and this takes the
## stage: the whole run as one picture. Five decisions across four autonomy
## levels is a matrix, and a matrix is the only shape that shows a run's pattern
## at a glance - which rungs this crew kept choosing, and where they broke their
## own pattern. Each decision's score sits at the end of its row, coloured on the
## client's own ramp, so the shape of the run and the cost of it are read
## together rather than in a list of sentences.
##
## Under the matrix is the one thing left to do: log the run on the SHIPMIND
## uplink. The button raises the uplink's own screen (see ShipmindLeaderboard)
## over this one - the network board, shared by every device the crew fly
## from - with the run's score carried in and the callsign asked for there.
## This screen holds no form and keeps no board of its own: one board, the
## uplink, and one way onto it.
##
## PLATFORM NOTE. Everything here is pointer-driven - a click, a tap, a
## controller-driven pointer - and no control needs a keyboard to be dismissed.
## The callsign is typed on the uplink screen, which carries its own
## touch-sized entry row, so a headset can log a run without this screen ever
## showing a text field.

signal closed

const ORANGE := ScoreVisuals.ORANGE
const PEACH := ScoreVisuals.PEACH
const OFF_WHITE := ScoreVisuals.OFF_WHITE
const SLATE := ScoreVisuals.SLATE

var _open: bool = false
var _root: Control = null
var _panel: PanelContainer = null
var _scroll: ScrollContainer = null
var _content: VBoxContainer = null
## The SHIPMIND standings screen while it is up, hosted inside this layer.
var _uplink: ShipmindLeaderboard = null


func _ready() -> void:
	layer = 125
	_build_shell()
	get_viewport().size_changed.connect(_relayout)
	root_visible(false)
	TextZoom.register(_root)


func is_open() -> bool:
	return _open


## The cockpit is visible behind this: the crew are back in their seats, looking
## at what their five decisions added up to.
func show_screen() -> void:
	_open = true
	root_visible(true)
	_rebuild()
	_relayout()
	TextZoom.apply(_root)
	InputRouter.set_ui_blocking(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if not _open:
		return
	_open = false
	_discard_uplink()
	root_visible(false)
	InputRouter.set_ui_blocking(false)
	for node in get_tree().get_nodes_in_group("input_layer"):
		if node.has_method("grab_mouse"):
			node.grab_mouse()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		## While the uplink is up the first escape is its own: the board closes
		## and hands the results back, and only a second one leaves the ship.
		if _uplink != null:
			_close_uplink_board()
		else:
			close()
		get_viewport().set_input_as_handled()


# --- The shell -------------------------------------------------------------------


func _build_shell() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.016, 0.014, 0.9)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(backdrop)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var style := StyleBoxFlat.new()
	style.bg_color = Brand.SURFACE
	style.border_color = Brand.ACCENT
	style.border_width_top = 3
	style.set_corner_radius_all(3)
	_panel.add_theme_stylebox_override("panel", style)
	_root.add_child(_panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", _px(34))
	margin.add_theme_constant_override("margin_right", _px(34))
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 18)
	_panel.add_child(margin)

	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(_scroll)

	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", _px(9))
	_scroll.add_child(_content)


func root_visible(value: bool) -> void:
	if _root != null:
		_root.visible = value


func _rebuild() -> void:
	_clear(_content)
	_build_results_page()


## THE ONE PAGE: WHAT THE RUN ADDED UP TO. Nothing to fill in, nothing to
## scroll to - the run as a picture, the uplink, and the way back to the ship.
func _build_results_page() -> void:
	_content.add_child(_kicker("THE RUN IS FLOWN  —  ADAMANT VERITY UNDER WAY"))
	_content.add_child(_title("MISSION COMPLETE"))
	_content.add_child(_summary_row())
	_content.add_child(ScoreVisuals.caption(
		"Your mandate: %s" % OperatingModel.mandate_statement(), Brand.NEUTRAL))
	_content.add_child(_rule())
	_content.add_child(_section("YOUR FIVE DECISIONS"))
	_content.add_child(_matrix())
	_content.add_child(_gap(_px(8)))
	_content.add_child(_uplink_actions())


# --- The run, as a picture -----------------------------------------------------------


## The headline: the total as the biggest number on the screen, its own meter,
## and the verdict it earns - beside the two axes the total is made of.
func _summary_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _px(26))

	var score_box := VBoxContainer.new()
	score_box.add_theme_constant_override("separation", 4)
	score_box.custom_minimum_size = Vector2(_px(190), 0.0)
	score_box.add_child(_section("RUN SCORE"))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	var total := Label.new()
	total.text = "%d" % Score.total()
	total.add_theme_font_size_override("font_size", _px(40))
	total.add_theme_color_override("font_color", Brand.INK)
	line.add_child(total)
	var ceiling := Label.new()
	ceiling.text = "/ %d" % Score.max_total()
	ceiling.add_theme_font_size_override("font_size", _px(18))
	ceiling.add_theme_color_override("font_color", Brand.NEUTRAL)
	ceiling.size_flags_vertical = Control.SIZE_SHRINK_END
	line.add_child(ceiling)
	score_box.add_child(line)

	var quality: float = _mean_quality()
	if quality >= 0.0:
		var verdict := ScoreVisuals.pill(Score.grade_label(quality).to_upper(),
			ScoreVisuals.grade_color(quality), ScoreVisuals.grade_ink(quality),
			_px(13), Vector2(10.0, 5.0))
		verdict.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		score_box.add_child(verdict)
	var progress := ScoreVisuals.Meter.new()
	progress.custom_minimum_size = Vector2(0.0, 10.0)
	progress.fill_color = ORANGE
	progress.show_ratio(float(Score.total()) / maxf(float(Score.max_total()), 1.0))
	score_box.add_child(progress)
	score_box.add_child(ScoreVisuals.caption(
		"%d of %d decisions placed" % [Score.placed_count(), GameState.SYSTEMS.size()],
		Brand.NEUTRAL))
	row.add_child(score_box)

	var axes := GridContainer.new()
	axes.columns = 1 if _is_portrait() else 2
	axes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	axes.add_theme_constant_override("h_separation", 24)
	axes.add_theme_constant_override("v_separation", 10)
	var consistency := ScoreVisuals.meter_block("MATCHES YOUR MANDATE", Score.mean_consistency(),
		Brand.ACCENT_TINT, _axis_word(Score.mean_consistency()), true)
	consistency.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	axes.add_child(consistency)
	var coherence := ScoreVisuals.meter_block("FITS THE STAKES", Score.mean_coherence(),
		PEACH, _axis_word(Score.mean_coherence()), true)
	coherence.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	axes.add_child(coherence)
	row.add_child(axes)
	return row


## Five decisions down the side, the four autonomy levels across the top, and the
## decision's own score at the end of its row. The chosen rung is the filled box;
## the empty ones are the rungs this crew chose not to use, which is information
## too - a run that never leaves the first column says something.
func _matrix() -> Control:
	var grid := GridContainer.new()
	grid.name = "Matrix"
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)

	grid.add_child(_cell_label("DECISION", 10, Brand.NEUTRAL))
	for level in OperatingModel.LEVELS:
		var level_id: String = String(level.get("id", ""))
		var head := ScoreVisuals.pill(OperatingModel.level_short(level_id),
			OperatingModel.level_color(level_id),
			ScoreVisuals.INK if OperatingModel.level_dark_text(level_id) else ScoreVisuals.INK_LIGHT,
			_px(10), Vector2(8.0, 5.0))
		head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(head)
	grid.add_child(_cell_label("SCORE", 10, Brand.NEUTRAL))

	for system_id in GameState.SYSTEMS:
		grid.add_child(_row_name(system_id))
		var chosen: String = String(GameState.placement(system_id).get("level", ""))
		for level in OperatingModel.LEVELS:
			grid.add_child(_matrix_cell(system_id, String(level.get("id", "")), chosen))
		grid.add_child(_score_chip(system_id))
	return grid


func _row_name(system_id: String) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(_px(150), 0.0)
	box.add_theme_constant_override("separation", 0)
	var name_label := Label.new()
	name_label.text = GameState.display_name(system_id)
	name_label.add_theme_font_size_override("font_size", _px(13))
	name_label.add_theme_color_override("font_color", Brand.INK)
	box.add_child(name_label)
	var tag: Dictionary = OperatingModel.decision_tag(system_id)
	var stakes := Label.new()
	stakes.text = "%s STAKES  ·  %s TO UNDO" % [
		String(tag.get("consequence_word", "")), String(tag.get("reversibility_word", ""))]
	stakes.add_theme_font_size_override("font_size", _px(9))
	stakes.add_theme_color_override("font_color", Brand.NEUTRAL)
	box.add_child(stakes)
	return box


func _matrix_cell(system_id: String, level_id: String, chosen: String) -> Control:
	var picked: bool = level_id == chosen and chosen != ""
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0.0, _px(36))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fill: Color = OperatingModel.level_color(level_id)
	var style := StyleBoxFlat.new()
	style.bg_color = fill if picked else Color(fill.r, fill.g, fill.b, 0.12)
	style.border_color = Color(1.0, 1.0, 1.0, 0.9) if picked else Color(fill.r, fill.g, fill.b, 0.34)
	style.set_border_width_all(2 if picked else 1)
	style.set_corner_radius_all(2)
	panel.add_theme_stylebox_override("panel", style)
	if picked:
		var ink: Color = ScoreVisuals.INK if OperatingModel.level_dark_text(level_id) else ScoreVisuals.INK_LIGHT
		var check := Glyph.make("check", _px(16), ink)
		check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		check.size_flags_vertical = Control.SIZE_EXPAND_FILL
		panel.add_child(check)
		panel.tooltip_text = "%s - %s" % [
			GameState.display_name(system_id), OperatingModel.level_summary(level_id)]
	return panel


func _score_chip(system_id: String) -> Control:
	var quality: float = Score.decision_quality(system_id)
	if quality < 0.0:
		var none := ScoreVisuals.pill("--", Brand.SURFACE_RAISED, Brand.NEUTRAL, _px(12), Vector2(10.0, 5.0))
		none.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return none
	var chip := ScoreVisuals.pill("%d" % Score.decision_points(system_id),
		ScoreVisuals.grade_color(quality), ScoreVisuals.grade_ink(quality),
		_px(13), Vector2(10.0, 5.0))
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.tooltip_text = "%s - %s" % [
		GameState.display_name(system_id), Score.grade_label(quality)]
	return chip


# --- The way onto the board ----------------------------------------------------------


## The one thing left to do with the run. The uplink button raises the SHIPMIND
## standings over this screen with the run's score already carried in; beside
## it, the quiet way back to the ship. The score lives on the network board,
## not here, so there is no form on this page and nothing to correct.
func _uplink_actions() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", _px(10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var note := ScoreVisuals.caption(
		"Time isn't scored. Changing your mind is free.", Brand.NEUTRAL)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(note)
	row.add_child(_quiet_button("BACK TO THE SHIP", close))
	box.add_child(row)
	var uplink := _primary_button("LOG IT ON THE SHIPMIND UPLINK", _open_uplink_board)
	uplink.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(uplink)
	return box


## The uplink rides on top of this screen in the same layer: the results stay
## underneath, unreachable while the full-rect board is up, and closing the
## board hands the results back exactly as the crew left them. No controller
## wiring is needed - the input block is already held by show_screen().
func _open_uplink_board() -> void:
	if _uplink != null:
		return
	_uplink = ShipmindLeaderboard.new()
	add_child(_uplink)
	_uplink.closed.connect(_close_uplink_board)
	## The board assembles itself one frame after it enters the tree, so the
	## run is presented on the next frame too: presenting into a screen that
	## is not built yet would write the score line into nothing.
	_uplink.call_deferred("present_result", Score.total(), int(GameState.elapsed))
	_root.visible = false


func _close_uplink_board() -> void:
	_discard_uplink()
	_root.visible = _open


func _discard_uplink() -> void:
	if _uplink != null:
		_uplink.queue_free()
		_uplink = null


func _primary_button(label_text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.name = label_text.capitalize().replace(" ", "")
	button.text = label_text
	button.custom_minimum_size = Vector2(_px(230), _px(48))
	button.add_theme_font_size_override("font_size", _px(14))
	button.add_theme_color_override("font_color", ScoreVisuals.INK)
	button.add_theme_color_override("font_hover_color", ScoreVisuals.INK)
	button.add_theme_color_override("font_pressed_color", ScoreVisuals.INK)
	var fill := StyleBoxFlat.new()
	fill.bg_color = ORANGE
	fill.set_corner_radius_all(2)
	button.add_theme_stylebox_override("normal", fill)
	var hover: StyleBoxFlat = fill.duplicate()
	hover.bg_color = Brand.ACCENT_TINT
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.pressed.connect(handler)
	return button


func _quiet_button(label_text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.name = label_text.capitalize().replace(" ", "")
	button.text = label_text
	button.custom_minimum_size = Vector2(0.0, _px(44))
	button.add_theme_font_size_override("font_size", _px(12))
	button.add_theme_color_override("font_color", Brand.INK)
	button.add_theme_color_override("font_hover_color", Brand.ACCENT_TINT)
	button.add_theme_stylebox_override("normal", _field_box(Color(0.0, 0.0, 0.0, 0.0), Brand.NEUTRAL))
	button.add_theme_stylebox_override("hover", _field_box(Color(0.0, 0.0, 0.0, 0.0), Brand.ACCENT_TINT))
	button.pressed.connect(handler)
	return button


func _gap(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


func _field_box(background: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(2)
	box.content_margin_left = 10.0
	box.content_margin_right = 10.0
	return box


# --- Small pieces -------------------------------------------------------------------


func _kicker(text: String) -> Label:
	var label := Label.new()
	label.text = text
	Brand.apply_tui(label, _px(12))
	label.add_theme_color_override("font_color", Brand.ACCENT_TINT)
	return label


func _title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", _px(30))
	label.add_theme_color_override("font_color", Brand.INK)
	return label


func _section(text: String) -> Label:
	var label := Label.new()
	label.text = text
	Brand.apply_tui(label, _px(11))
	label.add_theme_color_override("font_color", Brand.NEUTRAL)
	return label


func _cell_label(text: String, size: int, tint: Color, width: float = 0.0) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", _px(size))
	label.add_theme_color_override("font_color", tint)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if width > 0.0:
		label.custom_minimum_size = Vector2(width, 0.0)
	else:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _rule() -> ColorRect:
	var rule := ColorRect.new()
	rule.color = Color(1.0, 1.0, 1.0, 0.12)
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	return rule


func _mean_quality() -> float:
	var total: float = 0.0
	var counted: int = 0
	for system_id in GameState.SYSTEMS:
		var quality: float = Score.decision_quality(system_id)
		if quality >= 0.0:
			total += quality
			counted += 1
	if counted == 0:
		return -1.0
	return total / float(counted)


func _axis_word(value: float) -> String:
	if value < 0.0:
		return "nothing to measure yet"
	return Score.grade_label(value).capitalize()


func _clear(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


# --- Layout -----------------------------------------------------------------------


func _relayout() -> void:
	if _panel == null:
		return
	var view: Vector2 = get_viewport().get_visible_rect().size
	var width: float = minf(view.x - _px(36), 1060.0)
	var height: float = minf(view.y - _px(36), 660.0)
	_panel.size = Vector2(maxf(width, 280.0), maxf(height, 240.0))
	_panel.position = (view - _panel.size) * 0.5


func _is_portrait() -> bool:
	var view: Vector2 = get_viewport().get_visible_rect().size
	return view.y > view.x


## One type scale for the screen, stepped up where the only pointer is a thumb
## and again in a headset, where the panel is read from further away. The
## multiplier is Platform's, shared with every other overlay. The floor rule
## clamps after the multiplier so nothing ever renders below the reading floor.
func _px(base: float) -> int:
	return max(int(round(base * Platform.ui_scale())), Brand.SIZE_SMALL)
