class_name PrincipleCard
extends CanvasLayer

## The read-back shown when a decision is placed on the operating model.
##
## VERDICT FIRST, AND AS A PICTURE. The card used to print six lines of text and
## make the player read to the end to learn how they had done. It now leads with
## two meters - how far the placement followed the mandate, and how well it fit
## what the decision can cost - each with its own colour, number and reading. The
## rung that was chosen is drawn on the four-level spectrum in the client's own
## chart colours, so the placement is a position on a scale rather than a
## sentence about one. The written reasoning sits underneath in a quieter size,
## for the players who want it.
##
## The numbers come from Score and the colours from OperatingModel, so this card,
## the HUD and the end-of-run matrix can never disagree about the same placement.
##
## The class keeps its name because scenes/ui/principle_card.tscn instances it
## and the station controller holds it under that node name.

signal closed

@onready var root: Control = $Root
@onready var dim: ColorRect = $Root/Dim
@onready var card: PanelContainer = $Root/Card

var _open: bool = false
var _body: VBoxContainer = null
var _scroll: ScrollContainer = null
var _meters: GridContainer = null
var _dismiss: Button = null


func _ready() -> void:
	root.visible = false
	card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_build_frame()
	get_viewport().size_changed.connect(_relayout)
	_relayout()
	TextZoom.register(root)


func is_open() -> bool:
	return _open


## The card is built once and refilled per decision: the frame keeps its place on
## screen, only the reading inside it changes.
func _build_frame() -> void:
	for child in card.get_children():
		card.remove_child(child)
		child.queue_free()
	var frame := StyleBoxFlat.new()
	frame.bg_color = Brand.SURFACE
	frame.border_color = Brand.ACCENT
	frame.border_width_top = 3
	frame.set_corner_radius_all(3)
	card.add_theme_stylebox_override("panel", frame)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	card.add_child(margin)
	var stack := VBoxContainer.new()
	stack.name = "Stack"
	stack.add_theme_constant_override("separation", 6)
	margin.add_child(stack)
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	_scroll.add_child(_body)

	_dismiss = Button.new()
	_dismiss.name = "Dismiss"
	_dismiss.text = "DISMISS"
	## A pointer target, not a keyboard stop - the whole card already answers
	## a click or a key.
	_dismiss.focus_mode = Control.FOCUS_NONE
	_dismiss.custom_minimum_size = Vector2(0.0, 44.0 if _is_touch() else 34.0)
	_dismiss.add_theme_font_size_override("font_size", _px(15))
	_dismiss.add_theme_color_override("font_color", Brand.SURFACE)
	_dismiss.add_theme_color_override("font_hover_color", Brand.SURFACE)
	var dismiss_style := StyleBoxFlat.new()
	dismiss_style.bg_color = Brand.ACCENT
	dismiss_style.set_corner_radius_all(3)
	_dismiss.add_theme_stylebox_override("normal", dismiss_style)
	var dismiss_hover: StyleBoxFlat = dismiss_style.duplicate()
	dismiss_hover.bg_color = Brand.ACCENT_TINT
	_dismiss.add_theme_stylebox_override("hover", dismiss_hover)
	_dismiss.add_theme_stylebox_override("pressed", dismiss_hover)
	_dismiss.pressed.connect(dismiss)
	stack.add_child(_dismiss)


func show_card(system_id: String) -> void:
	_open = true
	_clear(_body)
	var quality: float = Score.decision_quality(system_id)
	_body.add_child(_kicker("YOUR DECISION  —  THE READ-BACK"))
	_body.add_child(_title("DECISION %d / %d" % [
		GameState.system_index(system_id), GameState.SYSTEMS.size()]))
	_body.add_child(_heading_row(system_id, quality))
	_meters = _meter_grid(system_id)
	_body.add_child(_meters)
	_body.add_child(_placement_row(system_id))
	_body.add_child(_spectrum_row(system_id))
	_body.add_child(_rule())
	_body.add_child(_reasoning(system_id))
	_body.add_child(_hint())
	root.visible = true
	root.modulate = Color(1, 1, 1, 0)
	create_tween().tween_property(root, "modulate", Color(1, 1, 1, 1), 0.22)
	_relayout()
	InputRouter.set_ui_blocking(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func dismiss() -> void:
	if not _open:
		return
	_open = false
	root.visible = false
	InputRouter.set_ui_blocking(false)
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	var dismissed: bool = false
	if event is InputEventMouseButton and event.pressed:
		dismissed = true
	elif event is InputEventScreenTouch and event.pressed:
		## A tap on a touchscreen, accepted explicitly rather than relying on the
		## engine emulating a mouse button from it.
		dismissed = true
	elif event is InputEventKey and event.pressed and not event.echo:
		dismissed = true
	elif event.is_action_pressed("interact"):
		dismissed = true
	if dismissed:
		dismiss()
		get_viewport().set_input_as_handled()


# --- The reading ------------------------------------------------------------------


## The decision, its icon and the verdict in one line. The verdict is a coloured
## chip on the chart's ramp so it reads before the words do.
func _heading_row(system_id: String, quality: float) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var glyph := Glyph.make(Glyph.icon_for_system(system_id), 26.0, Brand.ACCENT_TINT)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(glyph)
	var name_label := Label.new()
	name_label.text = GameState.display_name(system_id)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_label.add_theme_font_size_override("font_size", _px(16))
	name_label.add_theme_color_override("font_color", Brand.NEUTRAL_LIGHT)
	row.add_child(name_label)
	if quality >= 0.0:
		var verdict := Score.grade_label(quality).to_upper()
		var chip := ScoreVisuals.pill(verdict, ScoreVisuals.grade_color(quality),
			ScoreVisuals.grade_ink(quality), _px(14), Vector2(12.0, 6.0))
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(chip)
	else:
		row.add_child(ScoreVisuals.pill("NOT PLACED", Brand.SURFACE_RAISED,
			Brand.NEUTRAL, _px(12), Vector2(10.0, 5.0)))
	return row


func _meter_grid(system_id: String) -> GridContainer:
	var grid := GridContainer.new()
	grid.name = "Meters"
	grid.columns = 1 if _is_portrait() else 2
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 12)

	var consistency: float = Score.consistency(system_id)
	var coherence: float = Score.coherence(system_id)
	var mandate := ScoreVisuals.meter_block(
		"MATCHES YOUR MANDATE", consistency, Brand.ACCENT_TINT,
		Score.consistency_phrase(system_id).capitalize())
	mandate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(mandate)
	var stakes := ScoreVisuals.meter_block(
		"FITS THE STAKES", coherence, ScoreVisuals.PEACH,
		Score.coherence_phrase(system_id).capitalize())
	stakes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(stakes)
	return grid


## What was placed, as the chart's own box: its fill, its name and the one line
## that says what that level means in practice.
func _placement_row(system_id: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = "PLACED AT"
	Brand.apply_tui(label, _px(11))
	label.add_theme_color_override("font_color", Brand.NEUTRAL)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var placement: Dictionary = GameState.placement(system_id)
	if placement.is_empty():
		var none := ScoreVisuals.pill("NOT PLACED", Brand.SURFACE_RAISED, Brand.NEUTRAL,
			_px(13), Vector2(12.0, 7.0))
		row.add_child(none)
		return row
	var level_id: String = String(placement.get("level", ""))
	var pill := ScoreVisuals.level_pill(level_id, _px(14), true)
	pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(pill)
	return row


## The four levels, in their chart colours, with the chosen one raised out of the
## row. Position is the message: the player can see how far up the spectrum they
## placed without reading a single label.
func _spectrum_row(system_id: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var chosen: String = String(GameState.placement(system_id).get("level", ""))
	for level in OperatingModel.LEVELS:
		var level_id: String = String(level.get("id", ""))
		var picked: bool = level_id == chosen
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.custom_minimum_size = Vector2(0.0, 34.0 if picked else 28.0)
		var style := StyleBoxFlat.new()
		var fill: Color = OperatingModel.level_color(level_id)
		style.bg_color = fill if picked else Color(fill.r, fill.g, fill.b, 0.34)
		style.set_corner_radius_all(2)
		style.border_color = Color(1.0, 1.0, 1.0, 0.9 if picked else 0.0)
		style.set_border_width_all(2 if picked else 0)
		style.content_margin_left = 8.0
		style.content_margin_right = 8.0
		style.content_margin_top = 4.0
		style.content_margin_bottom = 4.0
		panel.add_theme_stylebox_override("panel", style)
		var ink: Color = ScoreVisuals.INK if OperatingModel.level_dark_text(level_id) else ScoreVisuals.INK_LIGHT
		var row_box := HBoxContainer.new()
		row_box.alignment = BoxContainer.ALIGNMENT_CENTER
		row_box.add_theme_constant_override("separation", 4)
		if picked:
			var check := Glyph.make("check", _px(11), ink)
			check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row_box.add_child(check)
		var caption := Label.new()
		caption.text = OperatingModel.level_short(level_id)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.add_theme_font_size_override("font_size", _px(11))
		caption.add_theme_color_override("font_color", ink if picked else Color(ink.r, ink.g, ink.b, 0.55))
		caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row_box.add_child(caption)
		panel.add_child(row_box)
		row.add_child(panel)
	return row


## The second layer: why the reading is what it is. It runs in the smaller voice
## under the pictures, because the pictures are the answer and this is the reason.
func _reasoning(system_id: String) -> Label:
	var lines: Array[String] = []
	var line: String = Score.proportionality_line(system_id)
	if line != "":
		lines.append(line)
	if GameState.has_placement(system_id):
		lines.append(Score.who_runs_line(system_id).capitalize())
	lines.append("Your mandate: %s" % OperatingModel.mandate_statement())
	var label := Label.new()
	label.text = "\n".join(lines)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", _px(13))
	label.add_theme_constant_override("line_spacing", 4)
	label.add_theme_color_override("font_color", Brand.NEUTRAL_LIGHT)
	return label


func _hint() -> Label:
	var label := Label.new()
	label.text = "TAP or press any key to carry on" if _is_touch() else "CLICK or press any key to carry on"
	Brand.apply_tui(label, _px(11))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_color_override("font_color", Brand.NEUTRAL)
	return label


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
	label.add_theme_font_size_override("font_size", _px(26))
	label.add_theme_color_override("font_color", Brand.INK)
	return label


func _rule() -> ColorRect:
	var rule := ColorRect.new()
	rule.color = Color(1.0, 0.88, 0.55, 0.35)
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	return rule


func _clear(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


# --- Layout -----------------------------------------------------------------------


## The panel is capped to the screen and its content scrolls inside it, so the
## panel itself never moves and a long reading is never clipped at both edges.
func _relayout() -> void:
	if card == null:
		return
	var view: Vector2 = get_viewport().get_visible_rect().size
	var inset := Brand.safe_inset(view)
	card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	card.position = Vector2(inset, inset)
	card.size = view - Vector2(inset * 2.0, inset * 2.0)
	if _meters != null and is_instance_valid(_meters):
		_meters.columns = 1 if _is_portrait() else 2


func _is_portrait() -> bool:
	var view: Vector2 = get_viewport().get_visible_rect().size
	return view.y > view.x


func _is_touch() -> bool:
	return Platform.touch_ui()


## One type scale for the card, from the same place every overlay reads it.
## The floor rule clamps after the multiplier: no platform scale may render a
## label below the game's reading floor.
func _px(base: float) -> int:
	var view: Vector2 = get_viewport().get_visible_rect().size
	if view.y < 500.0:
		return max(int(round(base * Platform.ui_scale() * 0.75)), 18)
	return max(int(round(base * Platform.ui_scale())), Brand.SIZE_SMALL)
