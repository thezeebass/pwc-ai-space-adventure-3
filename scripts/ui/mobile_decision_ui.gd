class_name MobileDecisionUI
extends Control

## The phone-landscape decision console: the five bays' one-pick decision, drawn
## for a thumb on a small wide screen.
##
## TerminalUI stays the renderer for desktop, VR and every non-decision console
## (the hub monologue, the log stations, the helm). On a touch device, for a
## decision bay, TerminalUI delegates to this shell instead: same ScreenState
## in, same signals out, and the puzzle still never touches a Control node.
##
## The layout is the reviewed wireframe, and its rules are load-bearing:
##
##   - LEFT ~66%: information, navigated by TABS. Tab one is OVERVIEW and carries
##     the dilemma alone - the question and its stakes, nothing else. The bay's
##     own tabs (SHIPMIND's case, the raw logs) follow, and SUMMARY closes with
##     the mandate and the tag note. NOTHING scrolls: a tab's content is short
##     by contract, and what does not fit is a content bug, not a cue for a
##     scrollbar.
##   - RIGHT ~33%: the decision. Four full-bleed chips in the chart's own four
##     colours - icon and name only, no hint text under a chip. One slot shows
##     the pick. One commit button finishes.
##   - THE GATE: the decision stays greyed until every tab has been opened.
##     Unread tabs are bright orange; that brightness IS the instruction, and it
##     is the only one - no coach marks, no tap-here text. One pick, tap to
##     place, commit to record.
##   - The cockpit backdrop sits behind everything, blurred and scrimmed in the
##     baked asset: legibility comes from the bake, not from an in-engine
##     filter.

signal placement_chosen(level_id: String)
## A read-back option (CHANGE THE DECISION / release the console / leave).
## Routed through TerminalUI's own option path so "close" behaves identically
## on both layouts.
signal option_chosen(option_id: String)

const BACKDROP_PATH := "res://assets/ui/decision_backdrop.webp"

## The column split, as stretch ratios: information 2, decision 1 - the reviewed
## 66/33 landscape split.
const INFO_STRETCH := 2.0
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


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
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


## True when this shell takes the screen: a touch device and a puzzle that is
## one of the five placed decisions. Everything else stays on TerminalUI.
static func handles(puzzle: Puzzle) -> bool:
	return Platform.touch_ui() and puzzle != null and puzzle.is_decision_bay()


func close() -> void:
	visible = false
	_puzzle = null
	_tabs = []
	_viewed = {}
	_active_tab = ""
	_level_choice = ""
	_chips = {}


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
	var info := _panel_body(info_panel)
	_tab_bar = HBoxContainer.new()
	_tab_bar.name = "Tabs"
	_tab_bar.add_theme_constant_override("separation", 8)
	info.add_child(_tab_bar)
	var content_panel := _sheet()
	info.add_child(content_panel)
	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	content_panel.add_child(_content)

	var decision_panel := _shell_panel(DECISION_STRETCH)
	columns.add_child(decision_panel)
	_decision_column = _panel_body(decision_panel)


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
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Brand.SURFACE.r, Brand.SURFACE.g, Brand.SURFACE.b, 0.86)
	style.border_color = Color(0.941, 0.722, 0.224, 0.35)
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


# --- Decision mode -----------------------------------------------------------------


func _render_decision(state: ScreenState) -> void:
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

	## OVERVIEW is what the console opens on; opening it counts as a look.
	_open_tab("overview")


func _build_tabs(state: ScreenState) -> Array:
	var tabs: Array = [{"id": "overview", "label": "OVERVIEW", "kind": "overview", "state": state}]
	for entry in _puzzle.info_tabs():
		tabs.append({
			"id": String(entry.get("id", "")),
			"label": String(entry.get("label", "LOGS")),
			"kind": "lines",
			"lines": entry.get("lines", []),
		})
	tabs.append({"id": "summary", "label": "SUMMARY", "kind": "summary"})
	return tabs


# --- Tabs ------------------------------------------------------------------------


func _make_tab_button(tab: Dictionary) -> Button:
	var button := Button.new()
	button.name = "Tab_" + String(tab["id"])
	button.text = String(tab["label"])
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, Platform.touch_target(42.0))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
			"overview":
				_fill_overview(tab)
			"summary":
				_fill_summary()
			_:
				_fill_lines(tab.get("lines", []))
		return


## OVERVIEW: the dilemma alone. The question in the brand voice, the stakes tag
## under it in the machine voice - the two glances the decision is made from.
## Nothing else lives here; everything else has its own tab.
func _fill_overview(tab: Dictionary) -> void:
	var state: ScreenState = tab["state"]
	var spectrum: Dictionary = state.spectrum
	var question := Label.new()
	question.text = String(spectrum.get("title", "PLACE THE DECISION"))
	question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	question.add_theme_font_size_override("font_size", Brand.SIZE_TITLE)
	question.add_theme_color_override("font_color", Brand.INK)
	_content.add_child(question)
	_content.add_child(_rule())
	var tag_row := HBoxContainer.new()
	tag_row.add_theme_constant_override("separation", 22)
	var consequence := String(spectrum.get("consequence", ""))
	if consequence != "":
		tag_row.add_child(_tag("STAKES   " + consequence, Brand.ACCENT))
	var reversibility := String(spectrum.get("reversibility", ""))
	if reversibility != "":
		tag_row.add_child(_tag("CAN UNDO   " + reversibility, Brand.NEUTRAL_LIGHT))
	_content.add_child(tag_row)


## SUMMARY: what the decision is read against - the declared mandate and the
## stakes in a sentence. The same for every bay, so it is built here once from
## the model rather than repeated in five puzzle files.
func _fill_summary() -> void:
	var mandate := Label.new()
	mandate.text = "YOUR MANDATE   %s" % OperatingModel.mandate_line()
	mandate.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Brand.apply_tui(mandate, Brand.console_size(Brand.SIZE_TUI))
	mandate.add_theme_color_override("font_color", Brand.NEUTRAL_LIGHT)
	_content.add_child(mandate)
	_content.add_child(_rule())
	var tag: Dictionary = OperatingModel.decision_tag(_puzzle.puzzle_id)
	var note := String(tag.get("tag_note", ""))
	if note != "":
		var note_label := Label.new()
		note_label.text = note
		note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		Brand.apply_tui(note_label, Brand.console_size(Brand.SIZE_TUI))
		note_label.add_theme_color_override("font_color", Brand.NEUTRAL_LIGHT)
		_content.add_child(note_label)
	var free := Label.new()
	free.text = "Judged against your mandate. Changing your mind is free."
	Brand.apply_tui(free, Brand.console_size(Brand.SIZE_TUI_SMALL))
	free.add_theme_color_override("font_color", Brand.NEUTRAL)
	_content.add_child(free)


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


func _tag(text: String, tint: Color) -> Label:
	var label := Label.new()
	label.text = text
	Brand.apply_tui(label, Brand.console_size(Brand.SIZE_TUI_SMALL))
	label.add_theme_color_override("font_color", tint)
	return label


# --- The decision column ------------------------------------------------------------


## Kicker, slot, four chips, commit. The chips are the client's chart boxes -
## full-bleed fills, icon band on top, one-word caption - with nothing under
## the caption: the name is the chip, the meaning is what the level means.
func _build_decision_controls(state: ScreenState) -> void:
	var spectrum: Dictionary = state.spectrum
	var kicker := Label.new()
	kicker.text = "THE DECISION"
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
	_commit.add_theme_color_override("font_color", Brand.SURFACE)
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
	var ink: Color = Brand.SURFACE if OperatingModel.level_dark_text(level_id) else Brand.INK_LIGHT
	var quiet_ink := Color(ink.r, ink.g, ink.b, 0.82)
	var chip := Button.new()
	chip.name = "Chip_" + level_id
	chip.text = label
	chip.toggle_mode = true
	chip.button_group = _level_group
	chip.focus_mode = Control.FOCUS_NONE
	chip.alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chip.custom_minimum_size = Vector2(0.0, 88.0)
	chip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chip.add_theme_font_size_override("font_size", Brand.SIZE_COMPACT)
	chip.add_theme_color_override("font_color", quiet_ink)
	chip.add_theme_color_override("font_pressed_color", ink)
	var rest := Color(fill.r, fill.g, fill.b, 0.62)
	chip.add_theme_stylebox_override("normal", _chip_box(rest, Color(0.0, 0.0, 0.0, 0.0)))
	chip.add_theme_stylebox_override("pressed", _chip_box(fill, Color(1.0, 1.0, 1.0, 0.95)))
	chip.add_theme_stylebox_override("disabled", _chip_box(rest, Color(0.0, 0.0, 0.0, 0.0)))
	var glyph := Glyph.make(Glyph.icon_for_level(level_id), 30.0, quiet_ink)
	glyph.set_anchors_preset(Control.PRESET_CENTER_TOP)
	glyph.offset_left = -15.0
	glyph.offset_right = 15.0
	glyph.offset_top = 10.0
	glyph.offset_bottom = 40.0
	chip.add_child(glyph)
	chip.toggled.connect(func(on: bool) -> void: glyph.tint = ink if on else quiet_ink)
	return chip


func _chip_box(background: Color, border: Color) -> StyleBoxFlat:
	var box := _box(background, border)
	box.content_margin_top = 46.0
	box.content_margin_bottom = 8.0
	return box


func _on_chip_pressed(level_id: String) -> void:
	_level_choice = level_id
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
	var ink: Color = Brand.SURFACE if dark_text else Brand.INK_LIGHT
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


# --- Read-back mode -----------------------------------------------------------------


## Everything a decision bay emits without a spectrum block: the recorded
## read-back after a commit, and the standing record on a reopen. Same shell:
## the lines read left, the screen's own options (change it / release the
## console) sit right, no gate - the decision is already made.
func _render_readback(state: ScreenState) -> void:
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
		var action := _make_action(String(entry.get("label", "...")), key_action)
		if tone == "primary" and not primary_seen:
			primary_seen = true
		action.pressed.connect(_on_readback_option.bind(id))
		_decision_column.add_child(action)


func _make_action(label: String, key_action: bool) -> Button:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0.0, Platform.touch_target(52.0))
	button.add_theme_font_size_override("font_size", Brand.SIZE_LABEL)
	if key_action:
		## The one action the screen exists for is the orange one: bright is
		## the instruction.
		button.add_theme_color_override("font_color", Brand.SURFACE)
		button.add_theme_stylebox_override("normal", _box(Brand.ACCENT, Brand.ACCENT))
		button.add_theme_stylebox_override("pressed", _box(Brand.ACCENT_TINT, Brand.ACCENT_TINT))
	else:
		button.add_theme_color_override("font_color", Brand.NEUTRAL_LIGHT)
		button.add_theme_stylebox_override("normal", _box(Brand.SURFACE_RAISED, Brand.NEUTRAL))
		button.add_theme_stylebox_override("pressed", _box(Brand.SURFACE_RAISED, Brand.ACCENT_TINT))
	return button


func _on_readback_option(option_id: String) -> void:
	option_chosen.emit(option_id)
