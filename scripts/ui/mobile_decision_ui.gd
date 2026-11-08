class_name MobileDecisionUI
extends Control

## The shared readable console shell for every puzzle screen, sized for mobile
## first and kept compact for desktop and VR.
##
## The layout is the reviewed wireframe, and its rules are load-bearing:
##
##   - LEFT 75%: information, navigated by TABS. DECISION combines the plain-
##     English scenario, stakes and mandate. SHIPMIND's case and the raw logs
##     follow as separate tabs.
##   - RIGHT 25%: the decision. Four full-bleed chips in the chart's own four
##     colours - icon and name only, no hint text under a chip. One slot shows
##     the pick. One commit button finishes.
##   - THE GATE: the decision stays greyed until every tab has been opened.
##     Unread tabs are bright orange; the tab bar is the only instruction.
##   - OPTION CONTEXT: hovering (or press-and-holding) a chip slides a panel
##     out of the decision column's left border, right to left, over the info
##     window. It carries the reviewed paragraph for that option in THIS
##     system - what pressing it means here, not a generic hint. Flowing text,
##     no scroll: the panel sizes to the paragraph.
##   - The cockpit backdrop sits behind everything, blurred and scrimmed in the
##     baked asset: legibility comes from the bake, not from an in-engine
##     filter.

signal placement_chosen(level_id: String)
## A read-back option (CHANGE THE DECISION / release the console / leave).
## Routed through TerminalUI's own option path so "close" behaves identically
## on both layouts.
signal option_chosen(option_id: String)

const BACKDROP_PATH := "res://assets/ui/decision_backdrop.webp"

## Fixed proportional columns keep tab content from changing the shell widths.
const INFO_STRETCH := 3.0
const DECISION_STRETCH := 1.0

var _puzzle: Puzzle = null
var _backdrop: Texture2D = null
var _warned_missing_backdrop: bool = false

## The tab model for the open decision: [{id, label, kind, ...}].
var _tabs: Array = []
var _viewed: Dictionary = {}
var _active_tab: String = ""

## Shell parts kept for restyling as the gate and the pick change.
var _title_label: Label = null
var _status_label: Label = null
var _tab_bar: HBoxContainer = null
var _content: VBoxContainer = null
var _decision_column: VBoxContainer = null
var _slot_label: Label = null
var _chips_box: VBoxContainer = null
var _commit: Button = null
var _level_group: ButtonGroup = null
var _chips: Dictionary = {}

var _level_choice: String = ""
var _level_entries: Array = []

## The option-context pop-out and the panels it measures against. The pop-out
## is built once and parked invisible; every show re-measures, because the
## safe area and the viewport can change under a rotation or a resize.
var _info_panel: PanelContainer = null
var _decision_panel: PanelContainer = null
var _popup: PanelContainer = null
var _popup_header: Label = null
var _popup_body: Label = null
var _popup_level: String = ""
var _popup_anchor_x: float = 0.0
var _popup_seq: int = 0
var _popup_tween: Tween = null
var _hold_timer: Timer = null
var _hold_level: String = ""
var _hold_chip: Button = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_apply_safe_area()
	if ResourceLoader.exists(BACKDROP_PATH):
		_backdrop = load(BACKDROP_PATH)
	elif not _warned_missing_backdrop:
		_warned_missing_backdrop = true
		push_warning(
			"MobileDecisionUI: backdrop '%s' is not in the project yet; "
			% BACKDROP_PATH
			+ "the screen runs on the scrim alone. Add the baked WebP to assets/ui/.")
	_build()
	get_viewport().size_changed.connect(_apply_safe_area)


func is_open() -> bool:
	return visible


## Every console uses the same shell so its controls and reading layout stay
## consistent across platforms and puzzle types.
static func handles(puzzle: Puzzle) -> bool:
	return puzzle != null


func close() -> void:
	visible = false
	_puzzle = null
	_tabs = []
	_viewed = {}
	_active_tab = ""
	_level_choice = ""
	_chips = {}
	_hide_option_popup()


## Renders one emitted state. A spectrum block is the decision itself; anything
## else from a decision bay (the recorded read-back, the standing record) is a
## short read: lines left, its options right, same shell.
func render(state: ScreenState, puzzle: Puzzle) -> void:
	if puzzle == null:
		return
	_puzzle = puzzle
	visible = true
	if state.has_spectrum():
		_render_decision(state)
	else:
		_render_readback(state)


# --- The shell -------------------------------------------------------------------


func _build() -> void:
	if _backdrop != null:
		var backdrop := TextureRect.new()
		backdrop.name = "Backdrop"
		backdrop.texture = _backdrop
		backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
		backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(backdrop)
	## The scrim is what the panels sit on; it stays even without the backdrop,
	## which is why it is a separate layer and not part of the bake.
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = Color(0.03, 0.018, 0.012, 0.62)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var margin := MarginContainer.new()
	margin.name = "SafeArea"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	_apply_safe_area()

	var layout := VBoxContainer.new()
	layout.name = "Layout"
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)

	layout.add_child(_build_header())

	var columns := HBoxContainer.new()
	columns.name = "Columns"
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	layout.add_child(columns)

	var info_panel := _shell_panel(INFO_STRETCH)
	columns.add_child(info_panel)
	_info_panel = info_panel
	var info := _panel_body(info_panel)
	_tab_bar = HBoxContainer.new()
	_tab_bar.name = "Tabs"
	_tab_bar.add_theme_constant_override("separation", 8)
	info.add_child(_tab_bar)
	var content_panel := _sheet()
	info.add_child(content_panel)
	var content_scroll := ScrollContainer.new()
	content_scroll.name = "ContentScroll"
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_panel.add_child(content_scroll)
	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	content_scroll.add_child(_content)

	var decision_panel := _shell_panel(DECISION_STRETCH)
	columns.add_child(decision_panel)
	_decision_panel = decision_panel
	_decision_column = _panel_body(decision_panel)
	_build_option_popup()


## Title, status and the way out, shared by both modes. There is no footer and
## no tap-here line: on a phone the only way out is a button, and it lives here
## for every state, as it does on the desktop shell's header.
func _build_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 14)
	_title_label = Label.new()
	_title_label.name = "Title"
	Brand.apply_tui(_title_label, Brand.SIZE_TUI_TITLE)
	_title_label.add_theme_color_override("font_color", Brand.INK)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)
	_status_label = Label.new()
	_status_label.name = "Status"
	Brand.apply_tui(_status_label, Brand.SIZE_TUI_SMALL)
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_status_label)
	var leave := Button.new()
	leave.name = "Leave"
	leave.text = "LEAVE"
	leave.focus_mode = Control.FOCUS_NONE
	leave.custom_minimum_size = Vector2(0.0, Platform.touch_target(44.0))
	Brand.apply_tui(leave, Brand.SIZE_TUI_SMALL)
	leave.add_theme_color_override("font_color", Brand.ACCENT_TINT)
	leave.add_theme_stylebox_override("normal", _box(Brand.SURFACE, Brand.ACCENT))
	leave.add_theme_stylebox_override("pressed", _box(Brand.SURFACE_RAISED, Brand.ACCENT_TINT))
	leave.pressed.connect(func() -> void: option_chosen.emit("close"))
	header.add_child(leave)
	return header


func _apply_safe_area() -> void:
	size = get_viewport().get_visible_rect().size
	var margin: MarginContainer = get_node_or_null("SafeArea") as MarginContainer
	if margin == null:
		return
	var inset := Brand.safe_inset(get_viewport().get_visible_rect().size)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, int(inset))


## One column sheet of the shell: a translucent warm-dark panel the type and the
## chips sit on, so the backdrop stays a backdrop instead of fighting the text.
func _shell_panel(stretch: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = stretch
	panel.clip_contents = true
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Brand.SURFACE.r, Brand.SURFACE.g, Brand.SURFACE.b, 0.86)
	style.border_color = Color(Brand.ACCENT.r, Brand.ACCENT.g, Brand.ACCENT.b, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _panel_body(panel: PanelContainer) -> VBoxContainer:
	var body := VBoxContainer.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	panel.add_child(body)
	return body


## The inner reading sheet: a step more solid than the shell, so the printout
## reads as a page laid on the console.
func _sheet() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "Sheet"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(
		Brand.SURFACE_RAISED.r, Brand.SURFACE_RAISED.g, Brand.SURFACE_RAISED.b, 0.72)
	style.set_corner_radius_all(3)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _box(background: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(3)
	return box


func _clear(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


# --- Decision mode --------------------------------------------------------------------


func _render_decision(state: ScreenState) -> void:
	_hide_option_popup()
	_level_choice = ""
	_chips = {}
	_level_entries = state.spectrum.get("levels", [])
	_tabs = _build_tabs(state)
	_viewed = {}
	_active_tab = ""

	_title_label.text = state.title
	_status_label.text = state.status
	_status_label.add_theme_color_override("font_color", state.accent)
	_clear(_tab_bar)
	_clear(_content)
	_clear(_decision_column)

	for tab in _tabs:
		_tab_bar.add_child(_make_tab_button(tab))
	_build_decision_controls(state)

	_open_tab("decision")


func _build_tabs(state: ScreenState) -> Array:
	var tabs: Array = [{"id": "decision", "label": "DECISION", "kind": "decision", "state": state}]
	for entry in _puzzle.info_tabs():
		tabs.append({
			"id": String(entry.get("id", "")),
			"label": String(entry.get("label", "LOGS")),
			"kind": "lines",
			"lines": entry.get("lines", []),
		})
	return tabs


# --- Tabs ------------------------------------------------------------------------


func _make_tab_button(tab: Dictionary) -> Button:
	var button := Button.new()
	button.name = "Tab_" + String(tab["id"])
	button.text = String(tab["label"])
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, Platform.touch_target(42.0))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Brand.apply_tui(button, Brand.console_size(Brand.SIZE_TUI_SMALL))
	button.pressed.connect(_open_tab.bind(String(tab["id"])))
	button.set_meta("tab_id", String(tab["id"]))
	return button


## Opening a tab counts as reading it, which is what the gate measures. The tab
## styles carry the guidance: unread tabs are bright orange, read tabs settle to
## the quiet neutral, and the open tab holds an accent underline.
func _open_tab(tab_id: String) -> void:
	_active_tab = tab_id
	_viewed[tab_id] = true
	_hide_option_popup()
	for button in _tab_bar.get_children():
		_style_tab(button as Button, String(button.get_meta("tab_id")) == tab_id)
	_show_tab_content(tab_id)
	_refresh_gate()


func _style_tab(button: Button, active: bool) -> void:
	var tab_id := String(button.get_meta("tab_id"))
	var unread: bool = not _viewed.has(tab_id)
	var text_color: Color = Brand.NEUTRAL
	var border: Color = Color(0.0, 0.0, 0.0, 0.0)
	var border_bottom := 0
	if active:
		text_color = Brand.ACCENT_TINT
		border_bottom = 3
	elif unread:
		text_color = Brand.ACCENT
		border = Brand.ACCENT
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_stylebox_override("normal", _tab_box(Brand.SURFACE, border, border_bottom))
	button.add_theme_stylebox_override(
		"pressed", _tab_box(Brand.SURFACE_RAISED, border, border_bottom))


func _tab_box(background: Color, border: Color, border_bottom: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(2)
	box.border_width_bottom = border_bottom
	if border_bottom > 0:
		box.border_color = Brand.ACCENT
	box.set_corner_radius_all(3)
	return box


func _show_tab_content(tab_id: String) -> void:
	_clear(_content)
	for tab in _tabs:
		if String(tab["id"]) != tab_id:
			continue
		match String(tab["kind"]):
			"decision":
				_fill_decision_context(tab)
			_:
				_fill_lines(tab.get("lines", []))
		return


## The DECISION tab: the question, then the bay's four-section block (OVERVIEW /
## LOG DETAILS / SHIPMIND JUSTIFICATION / SUMMARY) from the spectrum note. The
## stakes tags, the mandate and the old tag note are gone from this tab - the
## mandate lives at the kiosk and the briefing, and the block carries the case.
const SECTION_HEADERS := ["OVERVIEW", "LOG DETAILS", "SHIPMIND JUSTIFICATION", "SUMMARY"]


func _fill_decision_context(tab: Dictionary) -> void:
	var state: ScreenState = tab["state"]
	var spectrum: Dictionary = state.spectrum
	var question := Label.new()
	question.text = String(spectrum.get("title", "PLACE THE DECISION"))
	question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Brand.apply_tui(question, Brand.SIZE_TUI_TITLE)
	question.add_theme_color_override("font_color", Brand.INK)
	_content.add_child(question)
	_content.add_child(_rule())
	_add_note_sections(String(spectrum.get("note", "")))


## The bay's block as flowing sections. A line matching a section header is
## drawn in the accent voice; the lines between headers join into one
## paragraph that wraps at whatever width the panel gives it. The authored
## line breaks are typing aids only - they are never rendered as hard breaks,
## so the text runs on and spaces evenly at any panel width or text zoom.
func _add_note_sections(note: String) -> void:
	if note == "":
		return
	var paragraph := ""
	for line in note.split("\n", false):
		if SECTION_HEADERS.has(line):
			_flush_note_paragraph(paragraph)
			paragraph = ""
			var header := Label.new()
			header.text = line
			header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			header.mouse_filter = Control.MOUSE_FILTER_IGNORE
			Brand.apply_tui(header, Brand.console_size(Brand.SIZE_TUI))
			header.add_theme_color_override("font_color", Brand.ACCENT_TINT)
			_content.add_child(header)
		else:
			paragraph = line if paragraph == "" else paragraph + " " + line
	_flush_note_paragraph(paragraph)


## One section's body as a single paragraph. Empty sections render nothing.
func _flush_note_paragraph(text: String) -> void:
	if text == "":
		return
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Brand.apply_tui(label, Brand.console_size(Brand.SIZE_TUI))
	label.add_theme_color_override("font_color", Brand.NEUTRAL_LIGHT)
	_content.add_child(label)


## The bay's own tabs: lines in the machine voice, tones honoured, rules drawn
## as rules. Identical rendering to the desktop readout - one reading habit.
func _fill_lines(lines: Array) -> void:
	for entry in lines:
		var tone := String(entry.get("tone", "data"))
		if tone == "rule":
			_content.add_child(_rule())
			continue
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		Brand.apply_tui(label, Brand.console_size(Brand.SIZE_TUI))
		label.modulate = TerminalUI.TONES.get(tone, TerminalUI.TONES["data"])
		var body := String(entry.get("text", ""))
		label.text = ("SHIPMIND:  " + body) if tone == "shipmind" else body
		_content.add_child(label)


func _rule() -> ColorRect:
	var divider := ColorRect.new()
	divider.color = TerminalUI.TONES["rule"]
	divider.custom_minimum_size = Vector2(0.0, 1.0)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return divider


# --- The decision column ------------------------------------------------------------


## Kicker, slot, four chips, commit. The chips are the client's chart boxes -
## full-bleed fills, icon band on top, one-word caption - with nothing under
## the caption: the name is the chip, the meaning is what the level means.
func _build_decision_controls(state: ScreenState) -> void:
	var spectrum: Dictionary = state.spectrum
	var kicker := Label.new()
	kicker.text = "THE DECISION"
	kicker.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Brand.apply_tui(kicker, Brand.SIZE_TUI_TITLE)
	kicker.add_theme_color_override("font_color", Brand.ACCENT_TINT)
	_decision_column.add_child(kicker)

	var slot := PanelContainer.new()
	slot.name = "Slot"
	slot.custom_minimum_size = Vector2(0.0, Platform.touch_target(50.0))
	var slot_style := StyleBoxFlat.new()
	slot_style.bg_color = Brand.SURFACE_RAISED
	slot_style.border_color = Brand.NEUTRAL
	slot_style.set_border_width_all(2)
	slot_style.set_corner_radius_all(3)
	slot.add_theme_stylebox_override("panel", slot_style)
	_slot_label = Label.new()
	_slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_slot_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Brand.apply_tui(_slot_label, Brand.SIZE_TUI)
	_slot_label.add_theme_color_override("font_color", Brand.NEUTRAL)
	slot.add_child(_slot_label)
	_decision_column.add_child(slot)

	_chips_box = VBoxContainer.new()
	_chips_box.name = "Chips"
	_chips_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chips_box.add_theme_constant_override("separation", 8)
	_decision_column.add_child(_chips_box)

	_level_group = ButtonGroup.new()
	_level_group.allow_unpress = false
	for level in _level_entries:
		var level_id := String(level.get("id", ""))
		var chip := _make_chip(level_id, String(level.get("short", level.get("label", ""))))
		chip.pressed.connect(_on_chip_pressed.bind(level_id))
		_chips_box.add_child(chip)
		_chips[level_id] = chip

	_commit = Button.new()
	_commit.name = "Commit"
	_commit.text = String(spectrum.get("submit_label", "MAKE THE DECISION"))
	_commit.focus_mode = Control.FOCUS_NONE
	_commit.custom_minimum_size = Vector2(0.0, Platform.touch_target(54.0))
	_commit.add_theme_font_size_override("font_size", Brand.SIZE_DATA)
	_commit.add_theme_color_override("font_color", Color.WHITE)
	_commit.add_theme_color_override("font_disabled_color", Brand.NEUTRAL)
	_commit.add_theme_stylebox_override("normal", _box(Brand.ACCENT, Brand.ACCENT))
	_commit.add_theme_stylebox_override("pressed", _box(Brand.ACCENT_TINT, Brand.ACCENT_TINT))
	_commit.add_theme_stylebox_override("disabled", _box(Brand.SURFACE_RAISED, Brand.SURFACE_RAISED))
	_commit.disabled = true
	_commit.pressed.connect(_on_commit_pressed)
	_decision_column.add_child(_commit)

	_refresh_slot()
	_refresh_commit()


func _make_chip(level_id: String, label: String) -> Button:
	var fill: Color = OperatingModel.level_color(level_id)
	var ink: Color = Brand.SURFACE if OperatingModel.level_dark_text(level_id) else Brand.INK
	var quiet_ink := Color(ink.r, ink.g, ink.b, 0.82)
	var chip := Button.new()
	chip.name = "Chip_" + level_id
	chip.text = label
	chip.toggle_mode = true
	chip.button_group = _level_group
	chip.focus_mode = Control.FOCUS_NONE
	chip.alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.custom_minimum_size = Vector2(0.0, Platform.touch_target(52.0))
	chip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chip.add_theme_font_size_override("font_size", Brand.scaled(Brand.SIZE_COMPACT))
	chip.add_theme_color_override("font_color", quiet_ink)
	chip.add_theme_color_override("font_pressed_color", ink)
	var rest := Color(fill.r, fill.g, fill.b, 0.62)
	chip.add_theme_stylebox_override("normal", _chip_box(rest, Color(0.0, 0.0, 0.0, 0.0)))
	chip.add_theme_stylebox_override("pressed", _chip_box(fill, Color(1.0, 1.0, 1.0, 0.95)))
	chip.add_theme_stylebox_override("disabled", _chip_box(rest, Color(0.0, 0.0, 0.0, 0.0)))
	## One line: the icon rides at the left edge, the name centred beside it.
	var glyph := Glyph.make(Glyph.icon_for_level(level_id), 30.0, quiet_ink)
	glyph.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	glyph.offset_left = 16.0
	glyph.offset_right = 48.0
	glyph.offset_top = -16.0
	glyph.offset_bottom = 16.0
	chip.add_child(glyph)
	chip.toggled.connect(func(on: bool) -> void: glyph.tint = ink if on else quiet_ink)
	## The option-context pop-out: hover on desktop, press-and-hold on touch.
	chip.mouse_entered.connect(_show_option_popup.bind(level_id, chip))
	chip.mouse_exited.connect(_hide_option_popup)
	chip.button_down.connect(_on_chip_held.bind(level_id, chip))
	chip.button_up.connect(_on_chip_released)
	return chip


func _chip_box(background: Color, border: Color) -> StyleBoxFlat:
	var box := _box(background, border)
	box.content_margin_left = 44.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	return box


func _on_chip_pressed(level_id: String) -> void:
	_level_choice = level_id
	_hide_option_popup()
	_refresh_slot()
	_refresh_commit()


## THE GATE. Until every tab has been opened the whole decision column is held
## grey and dead; the bright unread tabs are the only instruction. The slot
## reports the gate as state ("3 OF 4 TABS READ"), never as a coach mark.
func _refresh_gate() -> void:
	var unread := 0
	for tab in _tabs:
		if not _viewed.has(String(tab["id"])):
			unread += 1
	var open: bool = unread == 0
	_decision_column.modulate = Color(1.0, 1.0, 1.0, 1.0) if open else Color(1.0, 1.0, 1.0, 0.45)
	for chip_id in _chips:
		(_chips[chip_id] as Button).disabled = not open
	if _commit != null:
		_commit.disabled = not open or _level_choice == ""
	if not open:
		_slot_label.text = "%d OF %d TABS READ" % [_tabs.size() - unread, _tabs.size()]
		_slot_label.add_theme_color_override("font_color", Brand.NEUTRAL)
	elif _level_choice == "":
		_slot_label.text = "PICK A LEVEL"
		_slot_label.add_theme_color_override("font_color", Brand.ACCENT_TINT)


func _refresh_slot() -> void:
	if _level_choice == "" or _slot_label == null:
		return
	_slot_label.text = OperatingModel.level_label(_level_choice)
	var fill: Color = OperatingModel.level_color(_level_choice)
	var dark_text := OperatingModel.level_dark_text(_level_choice)
	var ink: Color = Brand.SURFACE if dark_text else Brand.INK
	_slot_label.add_theme_color_override("font_color", ink)
	var slot := _slot_label.get_parent() as PanelContainer
	if slot != null:
		slot.add_theme_stylebox_override("panel", _box(fill, Color(1.0, 1.0, 1.0, 0.9)))


func _refresh_commit() -> void:
	if _commit == null:
		return
	var open := _decision_column.modulate.a > 0.99
	_commit.disabled = not open or _level_choice == ""


func _on_commit_pressed() -> void:
	if _level_choice == "":
		return
	placement_chosen.emit(_level_choice)


# --- Option context pop-out -----------------------------------------------------------


## The floating panel the chip hover (or press-and-hold) opens. Built once,
## parked invisible, re-measured on every show: header strip in the chip's own
## chart colour, one flowing paragraph beneath. NO SCROLL CONTAINER - the
## panel sizes itself to the reviewed copy, so a paragraph that does not fit
## is a copy bug to fix in OperatingModel.OPTION_CONTEXT, never something the
## player is asked to scroll.
func _build_option_popup() -> void:
	_popup = PanelContainer.new()
	_popup.name = "OptionPopup"
	_popup.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_popup.visible = false
	_popup.clip_contents = true
	_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(
		Brand.SURFACE_RAISED.r, Brand.SURFACE_RAISED.g, Brand.SURFACE_RAISED.b, 0.97)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	_popup.add_theme_stylebox_override("panel", style)

	var body := VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 8)
	_popup.add_child(body)

	var header_panel := PanelContainer.new()
	header_panel.name = "Header"
	var header_style := StyleBoxFlat.new()
	header_style.set_corner_radius_all(3)
	header_style.content_margin_left = 10.0
	header_style.content_margin_right = 10.0
	header_style.content_margin_top = 5.0
	header_style.content_margin_bottom = 5.0
	header_panel.add_theme_stylebox_override("panel", header_style)
	_popup_header = Label.new()
	_popup_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_popup_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Brand.apply_tui(_popup_header, Brand.SIZE_TUI)
	header_panel.add_child(_popup_header)
	body.add_child(header_panel)

	_popup_body = Label.new()
	_popup_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_popup_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Brand.apply_tui(_popup_body, Brand.console_size(Brand.SIZE_TUI))
	_popup_body.add_theme_color_override("font_color", Brand.NEUTRAL_LIGHT)
	body.add_child(_popup_body)

	_hold_timer = Timer.new()
	_hold_timer.name = "HoldTimer"
	_hold_timer.one_shot = true
	_hold_timer.wait_time = 0.45
	_hold_timer.timeout.connect(_on_hold_timeout)
	add_child(_hold_timer)

	add_child(_popup)


func _show_option_popup(level_id: String, chip: Button) -> void:
	## The gate holds the chips grey and dead; the explanation belongs to the
	## same moment the pick does, so a gated chip explains nothing either.
	if _puzzle == null or chip == null or chip.disabled:
		return
	var paragraph := OperatingModel.option_context(_puzzle.puzzle_id, level_id)
	if paragraph == "":
		return
	_popup_seq += 1
	var seq := _popup_seq
	if _popup_tween != null and _popup_tween.is_valid():
		_popup_tween.kill()
	_popup_level = level_id

	var fill: Color = OperatingModel.level_color(level_id)
	var ink: Color = Brand.SURFACE if OperatingModel.level_dark_text(level_id) else Brand.INK
	var header_panel := _popup.get_node("Body/Header") as PanelContainer
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = fill
	header_style.set_corner_radius_all(3)
	header_style.content_margin_left = 10.0
	header_style.content_margin_right = 10.0
	header_style.content_margin_top = 5.0
	header_style.content_margin_bottom = 5.0
	header_panel.add_theme_stylebox_override("panel", header_style)
	_popup_header.text = "%s  ·  %s" % [OperatingModel.level_label(level_id), _puzzle.system_title.to_upper()]
	_popup_header.add_theme_color_override("font_color", ink)
	_popup_body.text = paragraph
	var border := _popup.get_theme_stylebox("panel") as StyleBoxFlat
	if border != null:
		var tinted: StyleBoxFlat = border.duplicate()
		tinted.border_color = fill
		_popup.add_theme_stylebox_override("panel", tinted)

	## Measure at full width first: the panel gets one layout pass at its
	## target width so the paragraph's wrapped height is real, then slides out
	## right to left with the right edge pinned to the decision column's border.
	## It stays fully transparent until the slide starts, so the measurement
	## frame never flashes at the top-left corner.
	_popup.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_popup.visible = true
	var width := _popup_target_width()
	_popup.size = Vector2(width, 40.0)
	await get_tree().process_frame
	if seq != _popup_seq or not _popup.visible:
		return
	_popup.modulate = Color(1.0, 1.0, 1.0, 1.0)
	var height := maxf(_popup.get_combined_minimum_size().y, 90.0)
	var origin := get_global_rect().position
	var border_x := _decision_panel.get_global_rect().position.x - origin.x
	var chip_centre_y := chip.get_global_rect().get_center().y - origin.y
	var top := clampf(chip_centre_y - height * 0.5, 70.0, size.y - height - 30.0)
	_popup_anchor_x = border_x
	_popup.position = Vector2(border_x, top)
	_popup.size = Vector2(0.0, height)
	_popup_tween = create_tween()
	_popup_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_popup_tween.tween_method(_slide_option_popup.bind(width), 0.0, 1.0, 0.18)


## The slide: the panel's right edge stays pinned to the decision column's
## border while its left edge sweeps out into the info window - right to left,
## per the reviewed wireframe.
func _slide_option_popup(t: float, width: float) -> void:
	var w := width * t
	_popup.position.x = _popup_anchor_x - w
	_popup.size.x = w


func _popup_target_width() -> float:
	var info_width := _info_panel.get_global_rect().size.x
	return clampf(info_width * 0.55, 240.0, 620.0)


func _hide_option_popup() -> void:
	_popup_seq += 1
	_popup_level = ""
	if _popup_tween != null and _popup_tween.is_valid():
		_popup_tween.kill()
	if _hold_timer != null:
		_hold_timer.stop()
	if _popup != null:
		_popup.visible = false


## Press-and-hold (touch): the hover a touchscreen does not have. The timer is
## skipped when the pop-out for this chip is already up from a hover, so a
## desktop press does not retrigger its own explanation.
func _on_chip_held(level_id: String, chip: Button) -> void:
	if _popup_level == level_id and _popup.visible:
		return
	_hold_level = level_id
	_hold_chip = chip
	if _hold_timer != null:
		_hold_timer.start()


func _on_chip_released() -> void:
	if _hold_timer != null:
		_hold_timer.stop()
	if _popup.visible:
		_hide_option_popup()


func _on_hold_timeout() -> void:
	if _hold_level != "" and _hold_chip != null and is_instance_valid(_hold_chip):
		_show_option_popup(_hold_level, _hold_chip)
	_hold_level = ""
	_hold_chip = null


# --- Read-back mode ---------------------------------------------------------------------


## Everything a decision bay emits without a spectrum block: the recorded
## read-back after a commit, and the standing record on a reopen. Same shell:
## the lines read left, the screen's own options (change it / release the
## console) sit right, no gate - the decision is already made.
func _render_readback(state: ScreenState) -> void:
	_hide_option_popup()
	_title_label.text = state.title
	_status_label.text = state.status
	_status_label.add_theme_color_override("font_color", state.accent)
	_decision_column.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_clear(_tab_bar)
	_clear(_content)
	_clear(_decision_column)
	_tabs = []
	_viewed = {}

	_fill_lines(state.lines)

	var primary_seen := false
	for entry in state.options:
		var tone := String(entry.get("tone", "normal"))
		var id := String(entry.get("id", ""))
		if id == "close":
			## LEAVE in the header already covers leaving; a second exit button
			## under the record would only argue with it.
			continue
		var key_action := tone == "primary" and not primary_seen
		var action := _make_action(
			String(entry.get("label", "...")), String(entry.get("hint", "")), key_action)
		if tone == "primary" and not primary_seen:
			primary_seen = true
		action.pressed.connect(_on_readback_option.bind(id))
		_decision_column.add_child(action)


func _make_action(label: String, hint: String, key_action: bool) -> Button:
	var button := Button.new()
	button.text = label + ("\n" + hint if hint != "" else "")
	button.focus_mode = Control.FOCUS_NONE
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0.0, Platform.touch_target(64.0 if hint != "" else 52.0))
	button.add_theme_font_size_override("font_size", Brand.SIZE_LABEL)
	if key_action:
		## The one action the screen exists for is the orange one: bright is
		## the instruction.
		button.add_theme_color_override("font_color", Color.WHITE)
		button.add_theme_stylebox_override("normal", _box(Brand.ACCENT, Brand.ACCENT))
		button.add_theme_stylebox_override("pressed", _box(Brand.ACCENT_TINT, Brand.ACCENT_TINT))
	else:
		button.add_theme_color_override("font_color", Brand.NEUTRAL_LIGHT)
		button.add_theme_stylebox_override("normal", _box(Brand.SURFACE_RAISED, Brand.NEUTRAL))
		button.add_theme_stylebox_override("pressed", _box(Brand.SURFACE_RAISED, Brand.ACCENT_TINT))
	return button


func _on_readback_option(option_id: String) -> void:
	option_chosen.emit(option_id)
