class_name ConsoleUI
extends CanvasLayer

## The ship console as a touch display, not a printout.
##
## This is the second terminal renderer, for the screens that are about
## touching rather than reading: the five bay decisions and the corridor
## kiosks. The layout is one column so a phone held upright is the primary
## shape; the lore - the system readout and SHIPMIND's case - is never on
## screen by default. A screen carries its working surface and two buttons,
## and the lore appears only when it is summoned.
##
## THE LAYOUT, IN ORDER:
##   1. The screen's title and status, on a slanted header band.
##   2. The working surface: a slider for each thing the crew sets (the
##      autonomy spectrum, one per setting) and the commit button for it.
##   3. Two tiles at the foot of the screen: READOUT and SHIPMIND, with the
##      close control. Tapping a tile opens its overlay full-screen; tapping
##      its header or the X folds it away.
##
## THE FLYOUTS ARE THE TUI. The readout overlay and the shipmind overlay are
## the machine-voice surface the old dual-column terminal was, written in the
## bundled mono face, so the lore keeps its own language and the touch surface
## keeps its own.
##
## CONSOLE.INI TUNING lives at the top of this file, not in the scene: the
## numbers that say what "touch display" means (corner radii, band angles,
## overlay margins, button floors) are gathered where they can be tuned
## without touching logic.

signal option_chosen(option_id: String)
signal placement_chosen(level_id: String, guardrail_id: String, owner_id: String)
signal opened
signal closed


# --- The console's own style, in one place -----------------------------------

## The overlays and panels, as fractions of the screen. Overlay margin is the
## black ring left around a flyout; band angle is the slant on the header.
const OVERLAY_MARGIN := 0.035
const BAND_ANGLE := -3.0
const BAND_HEIGHT := 64.0
const CORNER_RADIUS := 6

## Touch floors: a fingertip needs about this much of a control before a tap
## feels deliberate. Desktop keeps the tighter floor because a pointer is
## precise; the compact phone layout is the primary shape, so the touch floor
## is the reference.
const BUTTON_FLOOR := 56.0
const TILE_HEIGHT := 92.0
const SLIDER_HEIGHT := 64.0

## Sliders map to the autonomy spectrum's four stops: automated within
## guardrails, human review, human sign-off, human-only. The position is the
## choice, and the crew drags to the stop - the same grammar as a thruster
## slider, which is the ship's own way of tuning how much it trusts a machine.
const SPECTRUM_STOPS := ["AUTOMATED", "REVIEW", "SIGN-OFF", "HUMAN-ONLY"]

## The footer is quiet: it is the only line of instruction the console has,
## and it is never the point of the screen.
const FOOTER_DESKTOP := "TAP a tile to open it   -   TAP CLOSE to leave"
const FOOTER_TOUCH := "TAP a tile to open it   -   TAP CLOSE to leave"


@onready var root: Control = $Root
@onready var dim: ColorRect = $Root/Dim
@onready var panel: PanelContainer = $Root/Panel
@onready var band: PanelContainer = $Root/Panel/VBox/Band
@onready var band_title: Label = $Root/Panel/VBox/Band/Margin/HBox/TitleLabel
@onready var band_status: Label = $Root/Panel/VBox/Band/Margin/HBox/StatusLabel
@onready var band_rule: ColorRect = $Root/Panel/VBox/Rule
@onready var vbox: VBoxContainer = $Root/Panel/VBox
@onready var work_box: VBoxContainer = $Root/Panel/VBox/Work
@onready var tiles: HBoxContainer = $Root/Panel/VBox/Tiles
@onready var footer: Label = $Root/Panel/VBox/Footer
@onready var readout_overlay: Control = $Root/ReadoutOverlay
@onready var readout_title: Label = $Root/ReadoutOverlay/Margin/VBox/Header/Title
@onready var readout_scroll: ScrollContainer = $Root/ReadoutOverlay/Margin/VBox/Scroll
@onready var readout_body: VBoxContainer = $Root/ReadoutOverlay/Margin/VBox/Scroll/Body
@onready var readout_close: Button = $Root/ReadoutOverlay/Margin/VBox/Header/Close
@onready var shipmind_overlay: Control = $Root/ShipmindOverlay
@onready var shipmind_title: Label = $Root/ShipmindOverlay/Margin/VBox/Header/Title
@onready var shipmind_scroll: ScrollContainer = $Root/ShipmindOverlay/Margin/VBox/Scroll
@onready var shipmind_body: VBoxContainer = $Root/ShipmindOverlay/Margin/VBox/Scroll/Body
@onready var shipmind_close: Button = $Root/ShipmindOverlay/Margin/VBox/Header/Close

var _puzzle: Puzzle = null
var _pending_readout: Array[Dictionary] = []
var _readout_index: int = 0
var _timer: Timer

## What the crew has set so far. The slider maps the level id onto a spectrum
## position; the guardrail and owner are chosen from their own lists.
var _level_choice: String = ""
var _guardrail_choice: String = ""
var _owner_choice: String = ""
var _commit: Button = null
var _level_slider: SpectrumSlider = null
var _level_entries: Array = []
var _guardrail_tiles: Array = []
var _guardrail_entries: Array = []
var _owner_tiles: Array = []
var _owner_entries: Array = []
var _guardrail_detail: Array = []
var _owner_detail: Array = []
var _level_detail: Array = []
var _owner_requirement: Label = null
var _levels_require_owner: Dictionary = {}

## The flyouts' print pace, seconds per line.
const PRINT_INTERVAL := 0.35


func _ready() -> void:
	add_to_group("terminal_ui")
	_timer = Timer.new()
	_timer.one_shot = false
	_timer.timeout.connect(_print_step)
	add_child(_timer)
	dim.gui_input.connect(_on_dim_input)
	## The machine voice is the flyouts' own face; the band and footer are the
	## console's chrome, so they read in the machine voice too.
	_apply_console_text_size()
	readout_close.pressed.connect(func() -> void: _close_overlay("readout"))
	shipmind_close.pressed.connect(func() -> void: _close_overlay("shipmind"))
	_build_close_button()
	_build_tiles()
	footer.text = FOOTER_TOUCH if touch_mode() else FOOTER_DESKTOP
	root.visible = false
	readout_overlay.visible = false
	shipmind_overlay.visible = false
	TextZoom.register(root)


## The console's type re-derives from the menu's TEXT SIZE choice and its own
## -10% step; called at ready and whenever the setting changes mid-session.
func _apply_console_text_size() -> void:
	Brand.apply_tui(band_title, Brand.console_size(Brand.SIZE_TUI_TITLE))
	Brand.apply_tui(band_status, Brand.console_size(Brand.SIZE_TUI_SMALL))
	Brand.apply_tui(footer, Brand.console_size(Brand.SIZE_TUI_SMALL))
	Brand.apply_tui(readout_title, Brand.console_size(Brand.SIZE_TUI_TITLE))
	Brand.apply_tui(shipmind_title, Brand.console_size(Brand.SIZE_TUI_TITLE))


## True on a device whose only pointer is a finger.
func touch_mode() -> bool:
	return DisplayServer.is_touchscreen_available()


func _build_close_button() -> void:
	var button := Button.new()
	button.name = "CloseButton"
	button.text = "CLOSE"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, 44.0 if touch_mode() else 32.0)
	button.add_theme_font_size_override("font_size", Brand.console_size(Brand.SIZE_LABEL))
	button.add_theme_color_override("font_color", Brand.ACCENT_TINT)
	button.pressed.connect(close)
	band.get_node("Margin/HBox").add_child(button)


## The two lore tiles at the foot of the console. READOUT and SHIPMIND look
## and behave the same: a tap opens the matching overlay, and the overlay's
## own header folds it away.
func _build_tiles() -> void:
	for tile in [_lore_tile("READOUT", "Readout"), _lore_tile("SHIPMIND", "Shipmind")]:
		tiles.add_child(tile)


func _lore_tile(title: String, overlay: String) -> Button:
	var tile := Button.new()
	tile.name = "Tile%s" % overlay
	tile.text = title
	tile.toggle_mode = true
	tile.focus_mode = Control.FOCUS_ALL
	tile.custom_minimum_size = Vector2(0.0, TILE_HEIGHT)
	tile.add_theme_font_size_override("font_size", Brand.console_size(Brand.SIZE_LABEL))
	tile.add_theme_color_override("font_color", Brand.NEUTRAL)
	tile.add_theme_color_override("font_hover_color", Brand.INK)
	tile.add_theme_color_override("font_pressed_color", Brand.ACCENT_TINT)
	tile.add_theme_stylebox_override("normal", _tile_box(Brand.SURFACE, Brand.NEUTRAL))
	tile.add_theme_stylebox_override("hover", _tile_box(Brand.SURFACE_RAISED, Brand.ACCENT))
	tile.add_theme_stylebox_override("pressed", _tile_box(Brand.SURFACE_RAISED, Brand.ACCENT))
	tile.add_theme_stylebox_override("focus", _ring())
	tile.pressed.connect(_on_tile_pressed.bind(overlay))
	return tile


func _tile_box(background: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(CORNER_RADIUS)
	box.content_margin_left = 10.0
	box.content_margin_right = 10.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	return box


func is_open() -> bool:
	return root.visible


func open(puzzle: Puzzle) -> void:
	if puzzle == null or _puzzle != null:
		return
	_puzzle = puzzle
	if not puzzle.state_changed.is_connected(_render):
		puzzle.state_changed.connect(_render)
	root.visible = true
	InputRouter.set_ui_blocking(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	puzzle.start()
	opened.emit()


func close() -> void:
	if _puzzle != null and _puzzle.state_changed.is_connected(_render):
		_puzzle.state_changed.disconnect(_render)
	_puzzle = null
	_timer.stop()
	root.visible = false
	_close_overlays()
	InputRouter.set_ui_blocking(false)
	closed.emit()


func _close_overlays() -> void:
	readout_overlay.visible = false
	shipmind_overlay.visible = false
	for tile in tiles.get_children():
		tile.set_pressed_no_signal(false)


func _close_overlay(which: String) -> void:
	match which:
		"readout":
			readout_overlay.visible = false
		"shipmind":
			shipmind_overlay.visible = false
	_sync_tiles()


## The console renders a screen as a band and a working surface: the lore is
## held in the two flyouts, so what the crew sees is the decision and the
## tiles that open the context, not a wall of text.
func _render(state: ScreenState) -> void:
	band_title.text = state.title
	band_status.text = state.status
	band_status.modulate = state.accent
	band_rule.color = state.accent
	_clear(work_box)
	_commit = null
	_level_slider = null
	_guardrail_tiles = []
	_owner_tiles = []
	_level_choice = ""
	_guardrail_choice = ""
	_owner_choice = ""
	_levels_require_owner.clear()
	_owner_requirement = null

	## The readout lines are queued for the flyout, never printed here. The
	## tile is the way in; pressing it is the choice to read the ship's own
	## account of itself.
	_pending_readout = state.lines.duplicate()
	_readout_index = 0

	if state.has_spectrum():
		_draw_spectrum(state.spectrum)
	else:
		## A read-only console - the kiosk, the helm, a log - shows its options
		## on the working surface, because there is nothing to place.
		_options_work(state)
	_start_readout()


## The decision surface: one slider per thing the crew sets, then the commit.
## Everything here is built in code, because the screen it is drawn for is
## data, not a layout - a bay can add a level without a scene change.
func _draw_spectrum(block: Dictionary) -> void:
	var levels: Array = block.get("levels", [])
	for level in levels:
		_levels_require_owner[String(level.get("id", ""))] = bool(level.get("requires_owner", true))

	## The slider is the whole placement, one per console: drag from the
	## automated stop toward human-only, and the setting is the stop it lands
	## on. The captain's thruster, not a list of checkboxes.
	_level_slider = SpectrumSlider.new()
	_level_slider.custom_minimum_size = Vector2(0.0, SLIDER_HEIGHT)
	_level_slider.stop_count = maxi(levels.size(), 2)
	_level_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_level_slider.stop_pressed.connect(_on_level_stop)
	work_box.add_child(_level_slider)
	var level_detail := _detail_panel()
	work_box.add_child(level_detail[0])
	var level_labels := HBoxContainer.new()
	level_labels.add_theme_constant_override("separation", 8)
	for stop in SPECTRUM_STOPS:
		var stop_label := Label.new()
		stop_label.text = stop
		stop_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stop_label.add_theme_font_size_override("font_size", Brand.console_size(Brand.SIZE_SMALL))
		stop_label.add_theme_color_override("font_color", Brand.NEUTRAL)
		level_labels.add_child(stop_label)
	work_box.add_child(level_labels)

	var guardrail_title: String = String(block.get("guardrail_title", ""))
	if guardrail_title != "":
		work_box.add_child(_section_label("2 · GUARDRAIL", guardrail_title))
	var guardrails: Array = block.get("guardrails", [])
	_guardrail_entries = guardrails
	for guardrail in guardrails:
		var tile := _choice_tile(String(guardrail.get("label", "")), guardrail.get("id", ""))
		tile.pressed.connect(_on_guardrail_pressed.bind(String(guardrail.get("id", ""))))
		work_box.add_child(tile)
		_guardrail_tiles.append(tile)
	if not guardrails.is_empty():
		var guardrail_detail := _detail_panel()
		work_box.add_child(guardrail_detail[0])

	var owner_title: String = String(block.get("owner_title", ""))
	if owner_title != "":
		work_box.add_child(_section_label("3 · OWNER", owner_title))
	_owner_requirement = _note_label("", Brand.NEUTRAL_LIGHT)
	work_box.add_child(_owner_requirement)
	var owners: Array = block.get("owners", [])
	_owner_entries = owners
	for owner_role in owners:
		var tile := _choice_tile(String(owner_role.get("label", "")), owner_role.get("id", ""))
		tile.pressed.connect(_on_owner_pressed.bind(String(owner_role.get("id", ""))))
		work_box.add_child(tile)
		_owner_tiles.append(tile)
	if not owners.is_empty():
		var owner_detail := _detail_panel()
		work_box.add_child(owner_detail[0])
	_refresh_owner_requirement()

	_commit = Button.new()
	_commit.name = "Commit"
	_commit.text = String(block.get("submit_label", "COMMIT THE PLACEMENT"))
	_commit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_commit.custom_minimum_size = Vector2(0.0, BUTTON_FLOOR)
	_commit.add_theme_font_size_override("font_size", Brand.console_size(Brand.SIZE_DATA))
	_commit.add_theme_color_override("font_color", Brand.SURFACE)
	_commit.add_theme_color_override("font_hover_color", Brand.SURFACE)
	_commit.add_theme_color_override("font_pressed_color", Brand.SURFACE)
	_commit.add_theme_color_override("font_disabled_color", Brand.NEUTRAL)
	_commit.add_theme_stylebox_override("normal", _commit_fill(Brand.ACCENT))
	_commit.add_theme_stylebox_override("hover", _commit_fill(Brand.ACCENT_TINT))
	_commit.add_theme_stylebox_override("pressed", _commit_fill(Brand.ACCENT_TINT))
	_commit.add_theme_stylebox_override("focus", _ring())
	_commit.add_theme_stylebox_override("disabled", _commit_fill(Brand.SURFACE_RAISED))
	_commit.disabled = true
	_commit.pressed.connect(_on_commit_pressed)
	work_box.add_child(_commit)


## A read-only console's working surface: no slider, just the options as
## full-width buttons. The readout flyout still carries the lore.
func _options_work(state: ScreenState) -> void:
	for entry in state.options:
		work_box.add_child(_make_option_button(entry))


func _section_label(step: String, title: String) -> Label:
	var label := Label.new()
	label.text = "%s  %s" % [step, title]
	label.add_theme_font_size_override("font_size", Brand.console_size(Brand.SIZE_TUI_SMALL))
	label.add_theme_color_override("font_color", Brand.ACCENT_TINT)
	return label


func _choice_tile(label: String, _id: String) -> Button:
	var tile := Button.new()
	tile.text = label
	tile.toggle_mode = true
	tile.focus_mode = Control.FOCUS_ALL
	## A fingertip's comfortable target: the full floor on touch, a hair under
	## on desktop so the stack still fits one screen.
	var tile_h: float = BUTTON_FLOOR if touch_mode() else BUTTON_FLOOR - 10.0
	tile.custom_minimum_size = Vector2(0.0, tile_h)
	tile.alignment = HORIZONTAL_ALIGNMENT_LEFT
	tile.add_theme_font_size_override("font_size", Brand.console_size(Brand.SIZE_LABEL))
	tile.add_theme_color_override("font_color", Brand.NEUTRAL)
	tile.add_theme_color_override("font_hover_color", Brand.INK)
	tile.add_theme_color_override("font_pressed_color", Brand.ACCENT_TINT)
	tile.add_theme_stylebox_override("normal", _tile_box(Brand.SURFACE, Brand.NEUTRAL))
	tile.add_theme_stylebox_override("hover", _tile_box(Brand.SURFACE_RAISED, Brand.ACCENT))
	tile.add_theme_stylebox_override("pressed", _tile_box(Brand.SURFACE_RAISED, Brand.ACCENT))
	tile.add_theme_stylebox_override("focus", _ring())
	return tile


func _make_option_button(entry: Dictionary) -> Button:
	var button := Button.new()
	button.text = String(entry.get("label", "..."))
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(0.0,
		BUTTON_FLOOR if touch_mode() else BUTTON_FLOOR - 10.0)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", Brand.console_size(Brand.SIZE_LABEL))
	button.add_theme_color_override("font_color", Brand.NEUTRAL)
	button.add_theme_color_override("font_hover_color", Brand.INK)
	button.add_theme_stylebox_override("normal", _tile_box(Brand.SURFACE, Brand.NEUTRAL))
	button.add_theme_stylebox_override("hover", _tile_box(Brand.SURFACE_RAISED, Brand.ACCENT))
	button.add_theme_stylebox_override("pressed", _tile_box(Brand.SURFACE_RAISED, Brand.ACCENT))
	button.add_theme_stylebox_override("focus", _ring())
	button.pressed.connect(func() -> void: _on_option_pressed(String(entry.get("id", ""))))
	return button


# --- The working surface: choices and the commit -----------------------------

func _on_level_stop(index: int) -> void:
	## The slider's stop index maps back to the level id: index 0 is automated,
	## and the spectrum's own order is the truth, so the levels array is the
	## lookup and nothing is hard-coded.
	if _level_entries.is_empty():
		return
	_level_choice = String(_level_entries[index].get("id", ""))
	_level_slider.selected = index
	_level_slider.queue_redraw()
	_show_level_detail(_level_choice)
	_refresh_owner_requirement()
	_refresh_commit()


func _on_guardrail_pressed(guardrail_id: String) -> void:
	_guardrail_choice = guardrail_id
	for tile in _guardrail_tiles:
		tile.set_pressed_no_signal(String(tile.get("id", "")) == guardrail_id)
	var entry := _find_entry(_guardrail_entries, guardrail_id)
	var body := String(entry.get("hint", "")) + ("\n" + String(entry.get("cost", "")) if String(entry.get("cost", "")) != "" else "")
	_show_detail(_guardrail_detail, String(entry.get("label", "")), body)
	_refresh_commit()


func _on_owner_pressed(owner_id: String) -> void:
	_owner_choice = owner_id
	for tile in _owner_tiles:
		tile.set_pressed_no_signal(String(tile.get("id", "")) == owner_id)
	var entry := _find_entry(_owner_entries, owner_id)
	_show_detail(_owner_detail, String(entry.get("label", "")), String(entry.get("hint", "")))
	_refresh_commit()


func _show_level_detail(level_id: String) -> void:
	var entry := _find_entry(_level_entries, level_id)
	if entry.is_empty():
		return
	_show_detail(_level_detail, String(entry.get("label", "")), String(entry.get("hint", "")))


func _find_entry(entries: Array, id: String) -> Dictionary:
	for entry in entries:
		if String(entry.get("id", "")) == id:
			return entry
	return {}


func _show_detail(detail: Array, kicker_text: String, body_text: String) -> void:
	if detail.size() < 3:
		return
	(detail[0] as Control).visible = true
	(detail[1] as Label).text = kicker_text
	(detail[2] as Label).text = body_text


func requires_owner(level_id: String) -> bool:
	if _levels_require_owner.is_empty():
		return false
	return bool(_levels_require_owner.get(level_id, true))


## The commit stays closed until the decision is complete. A placement is its
## level; a block that ALSO lists guardrails or owner roles asks for those too,
## and one that lists none - the game's five bays - commits on the level alone.
func _refresh_commit() -> void:
	if _commit == null:
		return
	if _level_choice == "":
		_commit.disabled = true
		return
	if not _guardrail_entries.is_empty() and _guardrail_choice == "":
		_commit.disabled = true
		return
	_commit.disabled = requires_owner(_level_choice) and not _owner_entries.is_empty() and _owner_choice == ""


func _refresh_owner_requirement() -> void:
	if _owner_requirement == null or not is_instance_valid(_owner_requirement):
		return
	if _level_choice == "":
		_owner_requirement.text = "Choose a level. Every level above human-only has to name the owner; human-only does not."
		return
	if requires_owner(_level_choice):
		_owner_requirement.text = "A NAMED OWNER IS REQUIRED at this level. Pick the role that answers for the outcome."
	else:
		_owner_requirement.text = "HUMAN-ONLY: the accountable owner is the operator at the console. No separate role is recorded."


func _on_commit_pressed() -> void:
	if _level_choice == "":
		return
	var level_id: String = _level_choice
	if not _guardrail_entries.is_empty() and _guardrail_choice == "":
		return
	if requires_owner(level_id) and not _owner_entries.is_empty() and _owner_choice == "":
		return
	placement_chosen.emit(level_id, _guardrail_choice, _owner_choice)
	if _puzzle != null and is_instance_valid(_puzzle):
		_puzzle.place(level_id)


# --- The lore flyouts ---------------------------------------------------------

func _on_tile_pressed(overlay: String) -> void:
	var showing: bool = false
	match overlay:
		"Readout":
			showing = not readout_overlay.visible
			readout_overlay.visible = showing
			if showing:
				shipmind_overlay.visible = false
				_sync_tiles()
				_show_readout()
		"Shipmind":
			showing = not shipmind_overlay.visible
			shipmind_overlay.visible = showing
			if showing:
				readout_overlay.visible = false
				_sync_tiles()
				_show_shipmind()


func _sync_tiles() -> void:
	for tile in tiles.get_children():
		tile.set_pressed_no_signal(
			(tile.name == "TileReadout" and readout_overlay.visible) or
			(tile.name == "TileShipmind" and shipmind_overlay.visible))


func _start_readout() -> void:
	## The lore is queued for its flyout; nothing prints until the tile opens it.
	## When the console renders a fresh screen the queue resets, so an old
	## screen's readout never leaks into the next one.
	_timer.stop()


func _print_step() -> void:
	if _readout_index >= _pending_readout.size():
		_timer.stop()
		return
	var entry: Dictionary = _pending_readout[_readout_index]
	_readout_index += 1
	_add_flyout_line(readout_body, String(entry.get("text", "")), String(entry.get("tone", "data")))
	_snap_scroll(readout_scroll)
	if _readout_index >= _pending_readout.size():
		_timer.stop()


func _show_readout() -> void:
	## The tile opens the flyout and the lore prints at its own pace; the
	## readout is the ship's own account of itself, and it reads the same
	## whether the crew is watching yet or not.
	_timer.start(PRINT_INTERVAL)


func _show_shipmind() -> void:
	## SHIPMIND's case is the same flyout with the same voice; the content is
	## the screen's shipmind lines, queued the same way as the readout.
	if shipmind_body.get_child_count() == 0:
		for entry in _pending_readout:
			if String(entry.get("tone", "")) == "shipmind":
				_add_flyout_line(shipmind_body, String(entry.get("text", "")), "shipmind")


func _add_flyout_line(body: VBoxContainer, value: String, tone: String) -> void:
	if tone == "rule":
		var divider := ColorRect.new()
		divider.color = TONES["rule"]
		divider.custom_minimum_size = Vector2(0.0, 1.0)
		divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(divider)
		return
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Brand.apply_tui(label, Brand.console_size(Brand.SIZE_TUI))
	label.modulate = TONES.get(tone, TONES["data"])
	label.text = ("SHIPMIND:  " + value) if tone == "shipmind" else value
	body.add_child(label)
	TextZoom.apply_node(label)


const TONES := {
	"shipmind": Color(0.941, 0.722, 0.224),
	"data": Color(0.9, 0.86, 0.82),
	"ok": Color(1.0, 0.88, 0.55),
	"warn": Color(0.863, 0.369, 0.153),
	"dim": Color(0.62, 0.54, 0.48),
	"rule": Color(0.42, 0.24, 0.15),
}


func _detail_panel() -> Array:
	var panel := PanelContainer.new()
	panel.name = "Detail"
	var style := StyleBoxFlat.new()
	style.bg_color = Brand.SURFACE_RAISED
	style.border_color = Brand.NEUTRAL
	style.set_border_width_all(1)
	style.set_corner_radius_all(CORNER_RADIUS)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	var kicker := Label.new()
	kicker.add_theme_font_size_override("font_size", Brand.console_size(Brand.SIZE_SMALL))
	kicker.add_theme_color_override("font_color", Brand.ACCENT_TINT)
	box.add_child(kicker)
	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", Brand.console_size(Brand.SIZE_SMALL))
	body.add_theme_color_override("font_color", Brand.NEUTRAL_LIGHT)
	box.add_child(body)
	panel.visible = false
	return [panel, kicker, body]


func _commit_fill(background: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.set_corner_radius_all(CORNER_RADIUS)
	return box


func _ring() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	box.border_color = Brand.ACCENT
	box.set_border_width_all(2)
	box.set_corner_radius_all(CORNER_RADIUS)
	return box


func _note_label(text: String, tint: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", Brand.console_size(Brand.SIZE_SMALL))
	label.add_theme_color_override("font_color", tint)
	return label


func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _snap_scroll(scroll: ScrollContainer) -> void:
	await get_tree().process_frame
	if is_inside_tree() and is_instance_valid(scroll):
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_reveal_readout()
	elif event is InputEventScreenTouch and event.pressed:
		_reveal_readout()


func _reveal_readout() -> void:
	_timer.stop()
	while _readout_index < _pending_readout.size():
		var entry: Dictionary = _pending_readout[_readout_index]
		_readout_index += 1
		_add_flyout_line(readout_body, String(entry.get("text", "")), String(entry.get("tone", "data")))
	_snap_scroll(readout_scroll)


func _on_option_pressed(option_id: String) -> void:
	if option_id == "close":
		close()
		return
	option_chosen.emit(option_id)
	if _puzzle != null and is_instance_valid(_puzzle):
		_puzzle.choose(option_id)


func _unhandled_input(event: InputEvent) -> void:
	if not root.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if readout_overlay.visible or shipmind_overlay.visible:
			_close_overlays()
		else:
			close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_reveal_readout()
		return
	if event is InputEventScreenTouch and event.pressed:
		_reveal_readout()


# --- The slider ----------------------------------------------------------------


## A spectrum slider: the crew drags a thumb along a track of stops, and the
## stop it lands on is the choice. Drawn rather than assembled from buttons,
## because a slider is the console's own grammar - the thruster, not a menu.
class SpectrumSlider:
	extends Control

	signal stop_pressed(index: int)

	var selected: int = -1
	var stop_count: int = 4
	var _dragging: bool = false
	var _track_color: Color = Color(0.42, 0.24, 0.15)
	var _fill_color: Color = Color(0.992157, 0.317647, 0.031373)
	var _stop_color: Color = Color(0.631373, 0.658824, 0.701961)
	var _thumb_color: Color = Color(0.996078, 0.486275, 0.223529)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_snap_to(event.position.x)
			else:
				_dragging = false
		elif event is InputEventScreenTouch:
			if event.pressed:
				_dragging = true
				_snap_to(event.position.x)
			else:
				_dragging = false
		elif event is InputEventMouseMotion and _dragging:
			_snap_to(event.position.x)

	func _snap_to(x: float) -> void:
		if stop_count < 2:
			return
		var stop_width: float = size.x / float(stop_count)
		var index: int = int(clampf(x / stop_width, 0.0, float(stop_count - 1)))
		if index != selected:
			selected = index
			stop_pressed.emit(index)
			queue_redraw()

	func _draw() -> void:
		if stop_count < 2:
			return
		var stop_width: float = size.x / float(stop_count)
		var track_y: float = size.y * 0.5
		## The track: a line the thumb rides on, with a stop marked at each
		## centre. The fill runs to the selected stop, so "how much" is a
		## position, not a number.
		draw_line(Vector2(stop_width * 0.5, track_y), Vector2(size.x - stop_width * 0.5, track_y), _track_color, 3.0)
		for i in stop_count:
			var stop_x: float = stop_width * (float(i) + 0.5)
			draw_circle(Vector2(stop_x, track_y), 6.0, _stop_color)
			if selected >= 0 and i <= selected:
				draw_circle(Vector2(stop_x, track_y), 6.0, _fill_color)
		if selected >= 0:
			var thumb_x: float = stop_width * (float(selected) + 0.5)
			draw_circle(Vector2(thumb_x, track_y), 11.0, _thumb_color)
