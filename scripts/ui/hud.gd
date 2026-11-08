class_name HUD
extends CanvasLayer

## The heads-up display: crosshair, aim prompt, the SHIPMIND subtitle line -
## and a readout strip that was rebuilt from five lines of text into icons.
##
## THE STRIP READS AS PICTURES. The old HUD printed the mandate and every
## decision as lines of "[x] SYSTEM - level" text, which asked the player to
## read a paragraph to remember where they were. Now: one chip for the mandate
## (the objective's icon beside the appetite's icon), then one small icon chip
## per ship system - lit when the crew holds it, hollow while its bay is open,
## dimmed while it is still SHIPMIND's - and two tiny score bars for
## CONSISTENCY and COHERENCE. The full written record is one keypress away
## (Tab, or the chevron when the cursor is free) and runs in smaller type,
## because it is now the second layer of information rather than the first.
##
## MOBILE MODE gets the minimal variant: chips and subtitle only, no bars, no
## callsign, no detail panel. set_compact() is driven by the station
## controller when the input mode changes.
##
## The run clock is still advanced here, and nowhere else, because a HUD is
## already processing every frame and GameState owns the elapsed value. WHAT
## THE HUD DOES NOT DO IS SCORE IT: speed is out of scope in the operating
## model, so the elapsed line is a readout for a host and nothing multiplies it
## by anything.
##
## Nothing is cached beyond a signature string: every value drawn is read back
## from GameState, Score and OperatingModel at the moment it is drawn, and the
## labels are only REBUILT when the numbers behind them change.

@onready var root: Control = $Root
@onready var crosshair: Control = $Root/Crosshair
@onready var prompt_label: Label = $Root/Prompt
@onready var subtitle: PanelContainer = $Root/Subtitle
@onready var subtitle_text: Label = $Root/Subtitle/Margin/VBox/Text
@onready var subtitle_speaker: Label = $Root/Subtitle/Margin/VBox/Speaker

const GOLD := Color(0.941, 0.722, 0.224)
const PAPAYA := Color(0.863, 0.369, 0.153)
const TANGERINE := Color(0.816, 0.251, 0.149)
const INK := Color(0.96, 0.92, 0.87)
const MUTED := Color(0.72, 0.66, 0.62)
const DIM := Color(0.42, 0.36, 0.33)
const CHIP_BG := Color(0.07, 0.045, 0.035, 0.82)

## Raised when the crew press the corner MENU button. The station controller
## owns what that means - it opens the pause menu - because the HUD only
## reports what was touched, same as it does for prompts.
signal menu_requested

var _say_token: int = 0
## The last score block drawn, as a cheap signature. Never a legitimate empty
## string, so the first refresh always draws.
var _score_signature: String = ""

## The code-built strip.
var _strip: VBoxContainer = null
var _menu_button_ref: Button = null
var _mandate_objective_glyph: Glyph = null
var _mandate_appetite_glyph: Glyph = null
var _mandate_label: Label = null
var _chips: Dictionary = {}
var _chip_counter: Label = null
var _bars: Dictionary = {}
var _bars_row_ref: HBoxContainer = null
var _expand_btn: Button = null
var _bar_percents: Dictionary = {}
var _detail: PanelContainer = null
var _detail_label: Label = null
var _callsign_label: Label = null
var _compact: bool = false


func _ready() -> void:
	clear_prompt()
	subtitle.visible = false
	_build_strip()
	set_compact(InputMode.is_touch())
	## This runs before the station controller loads the save - a child's _ready
	## fires before its parent's - so the first read here shows defaults. That is
	## why the score is refreshed every frame instead of once: the readout
	## corrects itself on the next frame rather than needing to be told when the
	## save arrived.
	refresh_objective()
	_refresh_score()
	## The speech box is pure information: it never blocks a tap. While
	## SHIPMIND talks at the top of the screen the box sits over the MENU
	## button's corner, and a thumb reaching for the menu must not land in
	## a panel that is only reading aloud.
	var stack: Array[Node] = [subtitle]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is Control:
			(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	## The safe zone is measured against the live viewport, so it re-applies
	## whenever the window changes shape under us.
	get_viewport().size_changed.connect(_apply_safe_area)
	## The screen joins the text-zoom system: the menu's TEXT SIZE choice
	## re-derives every label here from its design size.
	TextZoom.register(root)


func _process(delta: float) -> void:
	if GameState.run_running:
		GameState.tick(delta)
	_refresh_score()


func clear_prompt() -> void:
	prompt_label.text = ""


func set_prompt(text: String) -> void:
	prompt_label.text = text


## Mobile mode: chips and subtitle only. The bars, the callsign and the detail
## panel are the desktop's second layer; a thumb never needs them.
func set_compact(value: bool) -> void:
	_compact = value
	if _bars_row_ref != null:
		_bars_row_ref.visible = not _compact
	if _callsign_label != null:
		_callsign_label.visible = not _compact
	if _expand_btn != null:
		_expand_btn.visible = not _compact
	if _compact and _detail != null:
		_detail.visible = false
	_apply_touch_layout(value)


## On a touchscreen the subtitle moves to the top, so a thumb holding the
## sticks never covers what SHIPMIND is saying, and the text doubles up: a
## phone screen is read at arm's length, not at a monitor's distance.
func _apply_touch_layout(touch: bool) -> void:
	if subtitle == null:
		return
	## The subtitle reads at the menu's TEXT SIZE choice - the same floor as
	## every other info popup, at every setting.
	subtitle_text.add_theme_font_size_override("font_size", Brand.info_text_size)
	subtitle_speaker.add_theme_font_size_override("font_size", Brand.info_text_size)
	if touch:
		subtitle.set_anchors_preset(Control.PRESET_CENTER_TOP)
		subtitle.anchor_top = 0.0
		subtitle.anchor_bottom = 0.0
	else:
		subtitle.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		subtitle.anchor_top = 1.0
		subtitle.anchor_bottom = 1.0
	subtitle.anchor_left = 0.5
	subtitle.anchor_right = 0.5
	_apply_safe_area()


## The safe zone: nothing in the HUD rides the bezel. TV title-safe thinking -
## pills, buttons and captions keep a margin from every display edge, and the
## subtitle's width clamps to the live viewport instead of a fixed 860px that
## a narrow window would push through the margins. Re-applied on resize.


func _apply_safe_area() -> void:
	if root == null:
		return
	var view: Vector2 = root.get_viewport_rect().size
	var inset: float = Brand.safe_inset(view)
	if _strip != null:
		_strip.offset_left = inset
		_strip.offset_top = inset
	if _callsign_label != null:
		_callsign_label.offset_top = inset
		# The callsign sits left of the MENU button, sharing its top line.
		_callsign_label.offset_right = -(inset + 90.0)
		_callsign_label.offset_left = -(inset + 346.0)
	if _menu_button_ref != null:
		_menu_button_ref.offset_top = inset
		_menu_button_ref.offset_bottom = inset + 28.0
		_menu_button_ref.offset_right = -inset
		_menu_button_ref.offset_left = -inset - 78.0
	if _detail != null:
		_detail.offset_left = inset
		_detail.offset_top = inset + 112.0
	if subtitle != null:
		var half_width: float = minf(430.0, view.x * 0.5 - inset)
		subtitle.offset_left = -half_width
		subtitle.offset_right = half_width
		if _compact:
			subtitle.offset_top = inset
			subtitle.offset_bottom = inset + 102.0
		else:
			subtitle.offset_top = -196.0
			subtitle.offset_bottom = -112.0


func _unhandled_input(event: InputEvent) -> void:
	if _compact:
		return
	if event.is_action_pressed("hud_detail"):
		if _detail != null:
			_detail.visible = not _detail.visible
		get_viewport().set_input_as_handled()


## What the crew have placed so far, as chips. A decision that has not been
## placed reads as an open bay rather than as a deficit, because that is what
## it is: the record distinguishes "not yet placed" from "placed badly" and so
## does this strip.
func refresh_objective() -> void:
	for system_id in GameState.SYSTEMS:
		var chip: PanelContainer = _chips.get(system_id)
		if chip == null:
			continue
		var glyph: Glyph = chip.get_meta("glyph")
		var style: StyleBoxFlat = chip.get_meta("rest").duplicate()
		if GameState.has_placement(system_id):
			style.border_color = GOLD
			glyph.tint = GOLD
			chip.tooltip_text = "%s - your decision: %s" % [
				GameState.display_name(system_id),
				OperatingModel.level_short(String(GameState.placement(system_id).get("level", "")))]
		elif GameState.is_restored(system_id):
			style.border_color = PAPAYA
			glyph.tint = INK
			chip.tooltip_text = "%s - on the record, no decision yet" % GameState.display_name(system_id)
		elif GameState.is_integrated(system_id):
			style.border_color = Color(0.45, 0.34, 0.26)
			glyph.tint = INK
			chip.tooltip_text = "%s - console live, no decision yet" % GameState.display_name(system_id)
		else:
			style.border_color = Color(0.22, 0.17, 0.13)
			glyph.tint = DIM
			chip.tooltip_text = "%s - console not live yet" % GameState.display_name(system_id)
		chip.add_theme_stylebox_override("panel", style)
	if _chip_counter != null:
		_chip_counter.text = "%d/%d" % [Score.placed_count(), GameState.SYSTEMS.size()]
	_refresh_mandate_chip()


func _refresh_mandate_chip() -> void:
	if _mandate_label == null:
		return
	if GameState.has_mandate():
		_mandate_objective_glyph.icon = Glyph.icon_for_objective(OperatingModel.objective_id)
		_mandate_objective_glyph.tint = GOLD
		_mandate_appetite_glyph.icon = Glyph.icon_for_appetite(OperatingModel.appetite_id)
		_mandate_appetite_glyph.tint = GOLD
		_mandate_label.text = "%s  ·  %s" % [
			OperatingModel.objective_label(), OperatingModel.appetite_label()]
		_mandate_label.add_theme_color_override("font_color", INK)
	else:
		_mandate_objective_glyph.icon = "scroll"
		_mandate_objective_glyph.tint = DIM
		_mandate_appetite_glyph.icon = "question"
		_mandate_appetite_glyph.tint = DIM
		_mandate_label.text = "NO MANDATE YET"
		_mandate_label.add_theme_color_override("font_color", MUTED)


## One axis of the score, as a bar and a percentage. "--" before anything is
## placed, which is the sentinel Score returns for an axis with nothing to
## measure: a run that has placed nothing has not been consistent or
## inconsistent, and must not be shown as either.
func _refresh_score() -> void:
	var signature: String = "%d|%d|%d|%d|%s" % [
		Score.total(), int(GameState.elapsed), Score.placed_count(), GameState.restored_count(),
		OperatingModel.mandate_line()]
	if signature == _score_signature:
		return
	_score_signature = signature
	# The mandate chip rides the same signature - declaring one changes
	# mandate_line() - so it corrects itself the frame after BEGIN, exactly like
	# the bars do, instead of waiting for the next placement.
	_refresh_mandate_chip()
	_refresh_bars()
	_refresh_callsign()
	_refresh_detail()


func _refresh_bars() -> void:
	_set_bar("consistency", Score.mean_consistency())
	_set_bar("coherence", Score.mean_coherence())


func _set_bar(axis: String, value: float) -> void:
	var bar: MiniBar = _bars.get(axis)
	var percent: Label = _bar_percents.get(axis)
	if bar == null or percent == null:
		return
	if value < 0.0:
		bar.ratio = -1.0
		percent.text = "--"
		percent.add_theme_color_override("font_color", MUTED)
		return
	bar.ratio = Score.percent(value) / 100.0
	percent.text = "%d%%" % Score.percent(value)
	percent.add_theme_color_override("font_color", GOLD)


func _refresh_callsign() -> void:
	if _callsign_label != null:
		_callsign_label.text = "CREW  %s" % GameState.callsign_or_default()


## The written record, behind the disclosure. Same content the old HUD printed
## permanently, one layer down and in smaller type.
func _refresh_detail() -> void:
	if _detail_label == null:
		return
	var lines: Array[String] = []
	if GameState.has_mandate():
		lines.append("MANDATE      %s / %s" % [
			OperatingModel.objective_label(), OperatingModel.appetite_label()])
	else:
		lines.append("MANDATE      --")
	for system_id in GameState.SYSTEMS:
		var label: String = GameState.display_name(system_id)
		if GameState.has_placement(system_id):
			var level: String = String(GameState.placement(system_id).get("level", ""))
			lines.append("[x] %s  -  %s" % [label, OperatingModel.level_short(level)])
		elif GameState.is_restored(system_id):
			lines.append("[x] %s  -  on the record, no decision yet" % label)
		elif GameState.is_integrated(system_id):
			lines.append("[ ] %s  -  console live, no decision yet" % label)
		else:
			lines.append("[ ] %s  -  console not live yet" % label)
	lines.append("YOUR MANDATE  %s" % _axis_text(Score.mean_consistency()))
	lines.append("THE STAKES    %s" % _axis_text(Score.mean_coherence()))
	## Shown for a host's interest. NOT part of the score, and nothing here
	## multiplies it by anything.
	lines.append("ELAPSED      %s   (not scored)" % GameState.elapsed_text())
	_detail_label.text = "\n".join(lines)


func _axis_text(value: float) -> String:
	if value < 0.0:
		return "--"
	return "%d%%  %s" % [Score.percent(value), Score.grade_label(value)]


# --- Subtitles --------------------------------------------------------------------

func say_shipmind(text: String, seconds: float = 6.5) -> void:
	_say_token += 1
	var token: int = _say_token
	subtitle_speaker.text = Shipmind.NAME
	subtitle_text.text = text
	subtitle.visible = true
	await get_tree().create_timer(seconds).timeout
	if token == _say_token and is_inside_tree():
		subtitle.visible = false


func say_shipmind_lines(lines: Array, hold: float = 4.5) -> void:
	for line in lines:
		say_shipmind(String(line), hold)
		await get_tree().create_timer(hold).timeout


## A voice outside the fiction - the mode switch falling back to desktop, for
## instance - spoken by the same subtitle box under a different name so the
## player is told without breaking the SHIPMIND voice.
func say_system(text: String, seconds: float = 4.0) -> void:
	_say_token += 1
	var token: int = _say_token
	subtitle_speaker.text = "SYSTEM"
	subtitle_text.text = text
	subtitle.visible = true
	await get_tree().create_timer(seconds).timeout
	if token == _say_token and is_inside_tree():
		subtitle.visible = false


# --- The strip, built in code -------------------------------------------------------

func _build_strip() -> void:
	_strip = VBoxContainer.new()
	_strip.name = "Strip"
	_strip.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_strip.offset_left = 26.0
	_strip.offset_top = 20.0
	_strip.offset_right = 400.0
	_strip.add_theme_constant_override("separation", 6)
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_strip)

	_strip.add_child(_mandate_row_control())
	_strip.add_child(_chips_row_control())
	_bars_row_ref = _bars_row_control()
	_strip.add_child(_bars_row_ref)

	_callsign_label = Label.new()
	_callsign_label.name = "Callsign"
	_callsign_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_callsign_label.offset_left = -366.0
	_callsign_label.offset_top = 20.0
	_callsign_label.offset_right = -110.0
	_callsign_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_callsign_label.add_theme_color_override("font_color", PAPAYA)
	_callsign_label.add_theme_color_override("font_outline_color", Color(0.06, 0.03, 0.02))
	_callsign_label.add_theme_constant_override("outline_size", 4)
	_callsign_label.add_theme_font_size_override("font_size", 30)
	root.add_child(_callsign_label)

	_menu_button_ref = _menu_button()
	root.add_child(_menu_button_ref)

	_build_detail()


## The corner MENU button - the clear way out. Visible in every mode including
## mobile, where there is no Escape key at all: a player who wants to leave
## should never have to remember a shortcut to find the door.
func _menu_button() -> Button:
	var button := Button.new()
	button.name = "MenuButton"
	button.text = "MENU"
	button.focus_mode = Control.FOCUS_NONE
	button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	button.offset_left = -100.0
	button.offset_top = 16.0
	button.offset_right = -22.0
	button.offset_bottom = 44.0
	button.add_theme_font_size_override("font_size", 30)
	button.add_theme_color_override("font_color", MUTED)
	button.add_theme_color_override("font_hover_color", GOLD)
	button.add_theme_color_override("font_pressed_color", GOLD)
	var ghost := StyleBoxFlat.new()
	ghost.bg_color = Color(0.07, 0.045, 0.035, 0.82)
	ghost.border_color = Color(0.4, 0.32, 0.26)
	ghost.set_border_width_all(1)
	ghost.set_corner_radius_all(3)
	button.add_theme_stylebox_override("normal", ghost)
	var hover: StyleBoxFlat = ghost.duplicate()
	hover.border_color = TANGERINE
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", ghost)
	var glyph := Glyph.make("menu", 14.0, MUTED)
	glyph.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	glyph.offset_left = 10.0
	glyph.offset_right = 24.0
	glyph.offset_top = -7.0
	glyph.offset_bottom = 7.0
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(glyph)
	for state in ["normal", "hover", "pressed", "focus"]:
		var box: StyleBoxFlat = button.get_theme_stylebox(state) as StyleBoxFlat
		if box != null:
			var adjusted: StyleBoxFlat = box.duplicate()
			adjusted.content_margin_left = 30.0
			button.add_theme_stylebox_override(state, adjusted)
	button.pressed.connect(func() -> void: menu_requested.emit())
	return button


func _panel_style(border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = CHIP_BG
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	return style


func _mandate_row_control() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Mandate"
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var chip := PanelContainer.new()
	var style := _panel_style(Color(0.45, 0.34, 0.26))
	chip.add_theme_stylebox_override("panel", style)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(inner)

	_mandate_objective_glyph = Glyph.make("scroll", 16.0, DIM)
	inner.add_child(_mandate_objective_glyph)
	_mandate_appetite_glyph = Glyph.make("question", 16.0, DIM)
	inner.add_child(_mandate_appetite_glyph)
	_mandate_label = Label.new()
	_mandate_label.add_theme_font_size_override("font_size", 30)
	_mandate_label.add_theme_color_override("font_color", MUTED)
	_mandate_label.add_theme_color_override("font_outline_color", Color(0.06, 0.03, 0.02))
	_mandate_label.add_theme_constant_override("outline_size", 4)
	inner.add_child(_mandate_label)
	row.add_child(chip)
	return row


func _chips_row_control() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Chips"
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for system_id in GameState.SYSTEMS:
		var chip := PanelContainer.new()
		chip.name = "Chip_%s" % system_id
		chip.custom_minimum_size = Vector2(30.0, 30.0)
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		var style := _panel_style(Color(0.22, 0.17, 0.13))
		chip.add_theme_stylebox_override("panel", style)
		chip.set_meta("rest", style)
		var glyph := Glyph.make(Glyph.icon_for_system(system_id), 18.0, DIM)
		glyph.size_flags_vertical = Control.SIZE_EXPAND_FILL
		glyph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.set_meta("glyph", glyph)
		chip.add_child(glyph)
		_chips[system_id] = chip
		row.add_child(chip)

	_chip_counter = Label.new()
	_chip_counter.name = "Counter"
	_chip_counter.text = "0/%d" % GameState.SYSTEMS.size()
	_chip_counter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_chip_counter.add_theme_font_size_override("font_size", 30)
	_chip_counter.add_theme_color_override("font_color", MUTED)
	_chip_counter.add_theme_color_override("font_outline_color", Color(0.06, 0.03, 0.02))
	_chip_counter.add_theme_constant_override("outline_size", 4)
	row.add_child(_chip_counter)

	row.add_child(_expand_button_control())
	return row


func _expand_button_control() -> Button:
	var button := Button.new()
	button.name = "Expand"
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "The full record (Tab)"
	button.custom_minimum_size = Vector2(26.0, 26.0)
	button.add_theme_color_override("font_color", MUTED)
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0, 0, 0, 0.4)
	flat.set_corner_radius_all(4)
	button.add_theme_stylebox_override("normal", flat)
	button.add_theme_stylebox_override("hover", flat)
	button.add_theme_stylebox_override("pressed", flat)
	button.add_theme_stylebox_override("focus", flat)
	var glyph := Glyph.make("chevron", 14.0, MUTED)
	glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(glyph)
	button.pressed.connect(func() -> void:
		if _detail != null:
			_detail.visible = not _detail.visible)
	_expand_btn = button
	return button


func _bars_row_control() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Bars"
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var axis_labels := {"consistency": "MANDATE", "coherence": "STAKES"}
	for axis in ["consistency", "coherence"]:
		var name_label := Label.new()
		name_label.text = String(axis_labels.get(axis, axis.to_upper()))
		name_label.custom_minimum_size = Vector2(92.0, 0.0)
		name_label.add_theme_font_size_override("font_size", 30)
		name_label.add_theme_color_override("font_color", MUTED)
		name_label.add_theme_color_override("font_outline_color", Color(0.06, 0.03, 0.02))
		name_label.add_theme_constant_override("outline_size", 4)
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(name_label)

		var bar := MiniBar.new()
		bar.custom_minimum_size = Vector2(120.0, 12.0)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.fill_color = GOLD if axis == "consistency" else PAPAYA
		_bars[axis] = bar
		row.add_child(bar)

		var percent := Label.new()
		percent.custom_minimum_size = Vector2(38.0, 0.0)
		percent.text = "--"
		percent.add_theme_font_size_override("font_size", 30)
		percent.add_theme_color_override("font_color", MUTED)
		percent.add_theme_color_override("font_outline_color", Color(0.06, 0.03, 0.02))
		percent.add_theme_constant_override("outline_size", 4)
		_bar_percents[axis] = percent
		row.add_child(percent)
	return row


func _build_detail() -> void:
	_detail = PanelContainer.new()
	_detail.name = "Detail"
	_detail.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_detail.offset_left = 26.0
	_detail.offset_top = 132.0
	_detail.visible = false
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := _panel_style(Color(0.45, 0.34, 0.26))
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	_detail.add_theme_stylebox_override("panel", style)
	root.add_child(_detail)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.add_child(margin)

	_detail_label = Label.new()
	_detail_label.name = "Text"
	_detail_label.add_theme_font_size_override("font_size", 30)
	_detail_label.add_theme_color_override("font_color", INK)
	_detail_label.add_theme_constant_override("line_spacing", 3)
	margin.add_child(_detail_label)


## One score axis as a bar. Draws its own background and fill; the percentage
## lives in the label beside it, so the drawing never has to lay out text.
class MiniBar:
	extends Control

	var ratio: float = -1.0:
		set(value):
			ratio = value
			queue_redraw()
	var fill_color: Color = Color(0.941, 0.722, 0.224)

	func _draw() -> void:
		var height: float = 7.0
		var track := Rect2(Vector2(0.0, (size.y - height) * 0.5), Vector2(size.x, height))
		draw_rect(track, Color(0.16, 0.11, 0.085, 0.9))
		if ratio >= 0.0:
			var fill := Rect2(track.position, Vector2(track.size.x * clampf(ratio, 0.0, 1.0), height))
			draw_rect(fill, fill_color)
