class_name TerminalUI
extends CanvasLayer

## Renders a ScreenState as a diegetic ship terminal: a printout that types
## itself out line by line, plus option buttons.
##
## The renderer knows nothing about puzzles. It prints whatever state a Puzzle
## emits, sends option presses back through "option_chosen", and - when the
## state carries a spectrum block - draws the placement control and sends the
## chosen level, guardrail and accountable-owner ids back through
## "placement_chosen". It never reads input or platform state of its own, so
## desktop, touch and VR are all the same screen.

signal option_chosen(option_id: String)
## A spectrum commit: the level the player chose, the single guardrail they
## attached to it, and the named role that owns the outcome. All three are handed
## back together, so a placement is never half-recorded. The owner is empty for a
## human-only placement, where the operator owns it by definition.
signal placement_chosen(level_id: String, guardrail_id: String, owner_id: String)
signal opened
signal closed

@export var print_interval: float = 0.06

@onready var root: Control = $Root
@onready var dim: ColorRect = $Root/Dim
@onready var title_label: Label = $Root/Panel/VBox/Header/TitleLabel
@onready var status_label: Label = $Root/Panel/VBox/Header/StatusLabel
@onready var rule_bar: ColorRect = $Root/Panel/VBox/Rule
@onready var vbox: VBoxContainer = $Root/Panel/VBox
@onready var scroll: ScrollContainer = $Root/Panel/VBox/Columns/Readout/Scroll
@onready var print_box: VBoxContainer = $Root/Panel/VBox/Columns/Readout/Scroll/Print
@onready var options_box: VBoxContainer = $Root/Panel/VBox/Columns/Decision/Options
@onready var decision_scroll: ScrollContainer = $Root/Panel/VBox/Columns/Decision/DecisionScroll
## The placement control's host, which owns its own scroller. The decision panel
## is the half of the screen that overflows, because the four levels, three
## guardrails and three owner roles are a lot of reading; giving it a scroll of
## its own is what keeps the option buttons pinned and visible while it happens.
@onready var _spectrum_box: VBoxContainer = $Root/Panel/VBox/Columns/Decision/DecisionScroll/Spectrum
## The commit button's host, below the scroller rather than inside it. The three
## choices are a lot of reading and the commit is the one control the decision
## cannot finish without, so it stays pinned while the steps scroll above it.
@onready var _commit_host: VBoxContainer = $Root/Panel/VBox/Columns/Decision/CommitHost
@onready var footer: Label = $Root/Panel/VBox/Footer
@onready var header: HBoxContainer = $Root/Panel/VBox/Header

## The footer is the only place the two control schemes are allowed to differ on
## screen. A phone has no ESC and no keyboard, so its way out is the CLOSE
## button rather than a key.
const FOOTER_DESKTOP := "CLICK or any key skips the print   -   ESC closes"
const FOOTER_TOUCH := "TAP the readout to print it all   -   TAP CLOSE to leave"

const TONES := {
	"shipmind": Color(0.941, 0.722, 0.224),
	"data": Color(0.9, 0.86, 0.82),
	"ok": Color(1.0, 0.88, 0.55),
	"warn": Color(0.863, 0.369, 0.153),
	"dim": Color(0.62, 0.54, 0.48),
	"rule": Color(0.42, 0.24, 0.15),
}

var _puzzle: Puzzle = null
var _pending: Array[Dictionary] = []
var _print_index: int = 0
var _timer: Timer
## The phone-landscape shell for the five decision bays. Owned and driven from
## here so every entry point - console interactables, game.gd, the dev probe -
## keeps talking to the one TerminalUI in the group; which layout the player
## sees is a rendering decision, not a wiring one.
var _mobile: MobileDecisionUI = null

## What the player has picked so far, in the ids the screen was written with.
## Held here rather than on ScreenState because a ScreenState is a description
## of a screen, not the state of a control.
var _level_choice: String = ""
var _guardrail_choice: String = ""
var _owner_choice: String = ""
## Which of the block's levels demand a named owner, captured from the block when
## it is drawn. Everything above human-only does; human-only does not, because
## the operator is the accountable owner already.
var _levels_require_owner: Dictionary = {}
## The live line under the owner list, saying what the level picked right now
## requires. It is how the owner rule is read before the commit rather than
## discovered when the commit refuses.
var _owner_requirement: Label = null
var _commit: Button = null
## The placement control's own state beyond the three ids: the entries each
## section was drawn from, so a press can find the option it belongs to and
## reveal its detail block; the detail panels themselves ([panel, kicker,
## body], one per section, hidden until that section's option is chosen); and
## the spectrum track the level stops ride on.
var _level_entries: Array = []
var _guardrail_entries: Array = []
var _owner_entries: Array = []
var _level_detail: Array = []
var _guardrail_detail: Array = []
var _owner_detail: Array = []
var _track: SpectrumTrack = null


func _ready() -> void:
	add_to_group("terminal_ui")
	_timer = Timer.new()
	_timer.one_shot = false
	_timer.timeout.connect(_print_step)
	add_child(_timer)
	dim.gui_input.connect(_on_dim_input)
	## The readout itself reveals on a tap as well as the backdrop: it is where
	## the player is looking while it prints, so it is where they will tap.
	scroll.gui_input.connect(_on_dim_input)
	## The machine voice on the chrome: the screen frame is what the ship prints,
	## so it is written in the TUI face. The decision control below keeps the
	## brand voice - the crew's own tool, not the ship's.
	Brand.apply_tui(title_label, Brand.SIZE_TUI_TITLE)
	Brand.apply_tui(status_label, Brand.SIZE_TUI_SMALL)
	Brand.apply_tui(footer, Brand.SIZE_TUI_SMALL)
	Brand.apply_tui($Root/Panel/VBox/Columns/Readout/ReadoutTitle, Brand.SIZE_TUI_SMALL)
	Brand.apply_tui($Root/Panel/VBox/Columns/Decision/DecisionTitle, Brand.SIZE_TUI_SMALL)
	_build_close_button()
	_mobile = MobileDecisionUI.new()
	add_child(_mobile)
	_mobile.placement_chosen.connect(_on_mobile_placement)
	_mobile.option_chosen.connect(_on_option_pressed)
	footer.text = FOOTER_TOUCH if touch_mode() else FOOTER_DESKTOP
	root.visible = false


## True on a device whose only pointer is a finger.
func touch_mode() -> bool:
	return DisplayServer.is_touchscreen_available()


## A way out of the terminal that does not depend on a keyboard.
##
## The screen used to close only on ESC, which a touchscreen does not have: on
## a phone the sole exit was an option button that happened to be labelled
## "close", and a screen is not obliged to offer one, so a console could strand
## the player with no way back. The button sits in the header, so it exists for
## every state, and it is built in code for the same reason the spectrum block
## is: the terminal draws whatever state it is handed.
func _build_close_button() -> void:
	var button := Button.new()
	button.name = "CloseButton"
	button.text = "CLOSE"
	## FOCUS_NONE: this is a pointer target, not a keyboard stop. Left in the
	## focus chain it would steal focus from the option buttons.
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, 50.0 if touch_mode() else 34.0)
	button.add_theme_font_size_override("font_size", Brand.SIZE_LABEL)
	button.add_theme_color_override("font_color", Brand.ACCENT_TINT)
	button.pressed.connect(close)
	header.add_child(button)


func is_open() -> bool:
	return root.visible or (_mobile != null and _mobile.is_open())


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
	if _mobile != null and _mobile.is_open():
		_mobile.close()
	if _puzzle != null and _puzzle.state_changed.is_connected(_render):
		_puzzle.state_changed.disconnect(_render)
	_puzzle = null
	_timer.stop()
	root.visible = false
	InputRouter.set_ui_blocking(false)
	closed.emit()


func _render(state: ScreenState) -> void:
	## A decision bay on a touch device renders in the mobile shell - including
	## the spectrum-less states around it (the recorded read-back, the standing
	## record), so a bay never switches layout mid-conversation. Everything
	## else keeps the printout below.
	if _mobile != null and (_mobile.is_open() or MobileDecisionUI.handles(_puzzle)):
		root.visible = false
		_mobile.render(state, _puzzle)
		return
	title_label.text = state.title
	status_label.text = state.status
	status_label.modulate = state.accent
	rule_bar.color = state.accent
	_clear(print_box)
	_clear(options_box)
	_clear(_spectrum_box)
	_clear(_commit_host)
	## A placement is committed once per screen, so each new screen starts with
	## nothing picked and the commit button closed. That is what makes "revise
	## the placement" a clean second look at the decision rather than a
	## half-remembered one.
	_level_choice = ""
	_guardrail_choice = ""
	_owner_choice = ""
	_levels_require_owner.clear()
	_owner_requirement = null
	_commit = null
	## Every line prints. There is no fold any more: the readout scrolls, and a
	## control that has to be found and pressed to read the screen it belongs to
	## is a second thing to do before the one thing the screen is for.
	_pending = state.lines.duplicate()
	_print_index = 0
	if state.has_spectrum():
		_draw_spectrum(state.spectrum)
	for entry in state.options:
		options_box.add_child(_make_option_button(entry))
	_start_print()


func _start_print() -> void:
	if _pending.is_empty():
		return
	_timer.start(print_interval)
	_print_step()


func _print_step() -> void:
	if _print_index >= _pending.size():
		_timer.stop()
		return
	var entry: Dictionary = _pending[_print_index]
	_print_index += 1
	_add_line(String(entry.get("text", "")), String(entry.get("tone", "data")))
	_snap_scroll()
	if _print_index >= _pending.size():
		_timer.stop()


func _reveal_all() -> void:
	if _print_index >= _pending.size():
		return
	_timer.stop()
	while _print_index < _pending.size():
		var entry: Dictionary = _pending[_print_index]
		_print_index += 1
		_add_line(String(entry.get("text", "")), String(entry.get("tone", "data")))
		_snap_scroll()


func _add_line(value: String, tone: String) -> void:
	if tone == "rule":
		var divider := ColorRect.new()
		divider.color = TONES["rule"]
		divider.custom_minimum_size = Vector2(0.0, 1.0)
		divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		print_box.add_child(divider)
		return
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## The machine voice: bundled mono face, one step under the brand body, and
	## the tone tints from the terminal's own palette.
	Brand.apply_tui(label, Brand.SIZE_TUI)
	label.modulate = TONES.get(tone, TONES["data"])
	label.text = ("SHIPMIND:  " + value) if tone == "shipmind" else value
	print_box.add_child(label)


## Every option on a terminal screen reads like the decision chips do: ONE
## line of text with a glyph anchoring the left edge, in the machine voice.
## A picture first, so the crew can find the same read on every screen without
## parsing words - and so a hint never turns a button into a paragraph.
func _make_option_button(entry: Dictionary) -> Button:
	var touch: bool = touch_mode()
	var button := Button.new()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(0.0, Platform.touch_target(52.0 if touch else 44.0))
	var tone: String = String(entry.get("tone", "normal"))
	var key := tone == "primary"
	var danger := tone == "danger"
	var text_tint: Color = Brand.ACCENT_TINT if key \
			else (Color(0.98, 0.55, 0.42) if danger else Brand.NEUTRAL_LIGHT)
	var icon_tint: Color = Brand.ACCENT if key \
			else (Color(0.98, 0.55, 0.42) if danger else Brand.NEUTRAL_LIGHT)
	button.add_theme_color_override("font_color", text_tint)
	button.add_theme_color_override("font_hover_color", Brand.ACCENT_TINT)
	button.add_theme_color_override("font_pressed_color", Brand.ACCENT_TINT)
	button.add_theme_color_override("font_focus_color", Brand.ACCENT_TINT)
	var border: Color = Brand.ACCENT if key \
			else (Color(0.98, 0.55, 0.42) if danger else Brand.NEUTRAL)
	button.add_theme_stylebox_override("normal", _icon_box(Brand.SURFACE, border))
	button.add_theme_stylebox_override("hover", _icon_box(Brand.SURFACE_RAISED, Brand.ACCENT))
	button.add_theme_stylebox_override("pressed", _icon_box(Brand.SURFACE_RAISED, Brand.ACCENT))
	button.add_theme_stylebox_override("focus", _ring())
	var row := HBoxContainer.new()
	row.name = "Content"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	## The row sits inside the stylebox's content margins, so the glyph's left
	## edge lines up with the border language the choice buttons use.
	row.offset_left = 14.0
	row.offset_right = -14.0
	row.offset_top = 8.0
	row.offset_bottom = -8.0
	row.add_theme_constant_override("separation", 10)
	var icon_name: String = String(entry.get("icon", ""))
	if icon_name == "":
		icon_name = _default_option_icon(String(entry.get("id", "")))
	var glyph := Glyph.make(icon_name, 22.0, icon_tint)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(glyph)
	var label := Label.new()
	label.text = String(entry.get("label", "..."))
	Brand.apply_tui(label, Brand.SIZE_TUI)
	label.add_theme_color_override("font_color", text_tint)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	button.add_child(row)
	button.pressed.connect(func() -> void: _on_option_pressed(String(entry.get("id", ""))))
	return button


## An option that names no picture still gets one, from what it does - a button
## never renders as bare text.
func _default_option_icon(id: String) -> String:
	match id:
		"close":
			return "close"
		"log":
			return "scroll"
		_:
			return "chevron"


## The icon button's fill: the same corner and border language as the choice
## buttons, with the left margin the glyph band needs.
func _icon_box(background: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(3)
	box.content_margin_left = 14.0
	box.content_margin_right = 14.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	return box


# --- The autonomy spectrum block -----------------------------------------------


## Draws the placement control: what the decision weighs, the four levels, the
## guardrails and one commit button. Two ButtonGroups, not one - a level and
## a guardrail are two different choices, and sharing a group would make picking
## a guardrail clear the level.
##
## The three steps are numbered 1 / 2 / 3 in the machine voice, because they are
## the same three steps at every console in the ship and the crew should be able
## to see that at a glance: place the decision, set the guardrail, name the
## owner. The commit button is pinned below the scroller (in its own host), so
## the one control the placement cannot finish without never scrolls away.
func _draw_spectrum(block: Dictionary) -> void:
	var guardrail_group := ButtonGroup.new()
	guardrail_group.allow_unpress = false
	var owner_group := ButtonGroup.new()
	owner_group.allow_unpress = false

	_spectrum_box.add_child(_spectrum_title(String(block.get("title", "PLACE THE DECISION"))))
	var note: String = String(block.get("note", ""))
	if note != "":
		_spectrum_box.add_child(_note_label(note, Brand.NEUTRAL))
	var tag_note: String = String(block.get("tag_note", ""))
	if tag_note != "":
		_spectrum_box.add_child(_note_label(tag_note, Brand.NEUTRAL))
	_spectrum_box.add_child(_step_kicker("1", "DECISION"))
	_spectrum_box.add_child(_gap(4))

	var levels: Array = block.get("levels", [])
	_level_entries = levels
	for level in levels:
		## Which levels need an owner is the block's own statement, and the
		## default is the strict one: a level that does not say gets asked for
		## an owner rather than being let through.
		_levels_require_owner[String(level.get("id", ""))] = bool(level.get("requires_owner", true))
	_spectrum_box.add_child(_level_slider(levels))
	_level_detail = _detail_panel()
	_spectrum_box.add_child(_level_detail[0])

	var guardrail_title: String = String(block.get("guardrail_title", ""))
	if guardrail_title != "":
		_spectrum_box.add_child(_gap(6))
		_spectrum_box.add_child(_step_kicker("2", "GUARDRAIL"))
		_spectrum_box.add_child(_note_label(guardrail_title, Brand.ACCENT_TINT))

	var guardrails: Array = block.get("guardrails", [])
	_guardrail_entries = guardrails
	for guardrail in guardrails:
		## Label only. What the guardrail is, is the choice; what it costs is
		## the detail block that opens under the one chosen.
		var button: Button = BrandTokens.choice_button(
			guardrail_group, String(guardrail.get("label", "")))
		button.pressed.connect(_on_guardrail_pressed.bind(String(guardrail.get("id", ""))))
		_spectrum_box.add_child(button)
	if not guardrails.is_empty():
		_guardrail_detail = _detail_panel()
		_spectrum_box.add_child(_guardrail_detail[0])

	## The accountability step. It comes after the guardrail because it is the
	## last thing a placement has to answer for: who owns the outcome.
	var owner_title: String = String(block.get("owner_title", ""))
	if owner_title != "":
		_spectrum_box.add_child(_gap(6))
		_spectrum_box.add_child(_step_kicker("3", "OWNER"))
		_spectrum_box.add_child(_note_label(owner_title, Brand.ACCENT_TINT))
	var owner_note: String = String(block.get("owner_note", ""))
	if owner_note != "":
		_spectrum_box.add_child(_note_label(owner_note, Brand.NEUTRAL))
	## The requirement line only exists where an owner step exists: a one-pick
	## block (the game's five bays) has no owner question to explain.
	if owner_title != "":
		_owner_requirement = _note_label("", Brand.NEUTRAL_LIGHT)
		_spectrum_box.add_child(_owner_requirement)
	var owners: Array = block.get("owners", [])
	_owner_entries = owners
	for owner_role in owners:
		var owner_button: Button = BrandTokens.choice_button(
			owner_group, String(owner_role.get("label", "")))
		owner_button.pressed.connect(_on_owner_pressed.bind(String(owner_role.get("id", ""))))
		_spectrum_box.add_child(owner_button)
	if not owners.is_empty():
		_owner_detail = _detail_panel()
		_spectrum_box.add_child(_owner_detail[0])
	_refresh_owner_requirement()

	_commit = Button.new()
	_commit.name = "Commit"
	_commit.text = String(block.get("submit_label", "COMMIT THE PLACEMENT"))
	_commit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	## Taller on a touch device: this is the one button the decision cannot be
	## finished without, so it is the worst place to make a fingertip guess.
	_commit.custom_minimum_size = Vector2(0.0, 58.0 if touch_mode() else 42.0)
	_commit.add_theme_font_size_override("font_size", Brand.SIZE_DATA)
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
	_commit_host.add_child(_commit)


func _on_level_pressed(level_id: String) -> void:
	_level_choice = level_id
	_update_track_selection(level_id)
	_show_level_detail(level_id)
	_refresh_owner_requirement()
	_refresh_commit()


func _on_guardrail_pressed(guardrail_id: String) -> void:
	_guardrail_choice = guardrail_id
	var entry := _find_entry(_guardrail_entries, guardrail_id)
	var body := String(entry.get("hint", ""))
	var cost := String(entry.get("cost", ""))
	if body != "" and cost != "":
		body = body + "\n" + cost
	elif body == "":
		body = cost
	_show_detail(_guardrail_detail, String(entry.get("label", "")), body)
	_refresh_commit()


func _on_owner_pressed(owner_id: String) -> void:
	_owner_choice = owner_id
	var entry := _find_entry(_owner_entries, owner_id)
	_show_detail(_owner_detail, String(entry.get("label", "")), String(entry.get("hint", "")))
	_refresh_commit()


## The chosen level's detail: the full label in the small accent voice, the
## level's own explanation in the smaller neutral voice beneath. Human-only's
## explanation already says what it means, so nothing extra is added here.
func _show_level_detail(level_id: String) -> void:
	var entry := _find_entry(_level_entries, level_id)
	if entry.is_empty():
		return
	_show_detail(_level_detail, String(entry.get("label", "")), String(entry.get("hint", "")))
	## The detail block carries the chosen level's colour down its left edge, so
	## the reading under the slider belongs to the box that was pressed.
	if _level_detail.size() < 1:
		return
	var panel := _level_detail[0] as PanelContainer
	var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null:
		return
	var tinted: StyleBoxFlat = style.duplicate()
	tinted.border_color = OperatingModel.level_color(level_id)
	tinted.border_width_left = 4
	panel.add_theme_stylebox_override("panel", tinted)




## One entry out of the list a section was drawn from, or empty for an unknown
## id - the same never-half-accept discipline the model files use.
func _find_entry(entries: Array, id: String) -> Dictionary:
	for entry in entries:
		if String(entry.get("id", "")) == id:
			return entry
	return {}


## The chosen option's detail: its full label in the small accent voice, its
## explanation in the smaller neutral voice beneath. This is the second layer
## of the disclosure: the button carries the name, the block carries the
## meaning, and it appears only for the option that was chosen.
func _show_detail(detail: Array, kicker_text: String, body_text: String) -> void:
	if detail.size() < 3:
		return
	var panel: Control = detail[0]
	panel.visible = true
	(detail[1] as Label).text = kicker_text
	(detail[2] as Label).text = body_text


## The chosen rung, as distance: the accent fill on the track runs from the
## first stop to the one selected, so "how much authority is delegated" reads
## as position, not as a list of toggles.
func _update_track_selection(level_id: String) -> void:
	if _track == null:
		return
	var index := 0
	for entry in _level_entries:
		if String(entry.get("id", "")) == level_id:
			_track.selected = index
			_track.queue_redraw()
			return
		index += 1


## True when a placement at this level has to name a role that owns it.
## Everything above human-only does; the block says so per level.
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


## The requirement, in the words the current level calls for. It is written to be
## read before the commit: the rule is legible on the screen rather than
## discovered when the commit refuses.
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
		_puzzle.solve()
	## The placement is in and the bay is solved: the completion flow releases
	## the console and raises the score card (verdict, meters, spectrum). The
	## decision is never asked twice - a reopen reads the standing record.


# --- The level slider ----------------------------------------------------------


## The four levels of the autonomy spectrum, drawn as a slider: one row of four
## stops riding on a track, each stop an icon with its one-word caption under
## it. This is the list-item-anchoring rule from the UX skill applied to the
## game's central control - the eye reads four pictures left to right (the
## model acting alone, a human watching, a stamp of authorisation, a person)
## before it reads any words, and the line under them says the rungs are
## positions on one spectrum, not four unrelated checkboxes.
##
## The detail is the second layer: each stop's full label and what the level
## means live in a smaller block that appears under the slider only for the
## setting chosen - the same disclosure the mandate picker uses on the launch
## screen, so both places teach the same reading habit.
func _level_slider(levels: Array) -> Control:
	var holder := VBoxContainer.new()
	holder.name = "LevelSlider"
	holder.add_theme_constant_override("separation", 2)
	_track = SpectrumTrack.new()
	_track.name = "Track"
	_track.stop_count = maxi(levels.size(), 2)
	_track.custom_minimum_size = Vector2(0.0, 8.0)
	holder.add_child(_track)
	var row := HBoxContainer.new()
	row.name = "Stops"
	row.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for level in levels:
		var level_id: String = String(level.get("id", ""))
		var stop := _level_stop(group, level_id, String(level.get("short", level.get("label", ""))))
		stop.pressed.connect(_on_level_pressed.bind(level_id))
		row.add_child(stop)
	holder.add_child(row)
	return holder


## One stop of the slider, drawn as the client's own chart box: the level's fill,
## its name, and its icon in the band above. Toggling is the selection - the
## chosen stop sits at full fill with a white edge, the others are held back at
## two thirds - and the icon brightens with it, so the chosen picture is the
## bright one. The four fills are the four boxes of "Autonomy levels at the
## gate", which is what makes the control readable before its labels are.
func _level_stop(group: ButtonGroup, level_id: String, label: String) -> Button:
	var touch: bool = DisplayServer.is_touchscreen_available()
	var glyph_size := 34.0 if touch else 30.0
	var top_margin := 56.0 if touch else 48.0
	var fill: Color = OperatingModel.level_color(level_id)
	var ink: Color = ScoreVisuals.INK if OperatingModel.level_dark_text(level_id) else ScoreVisuals.INK_LIGHT
	var quiet_ink := Color(ink.r, ink.g, ink.b, 0.78)
	var button := Button.new()
	button.toggle_mode = true
	button.button_group = group
	button.focus_mode = Control.FOCUS_ALL
	button.text = label
	## Wrapping, because "HUMAN SIGN-OFF" is a wider word than the old "ASK
	## FIRST" and the four stops have to share a narrow column on a phone.
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.custom_minimum_size = Vector2(0.0, 96.0 if touch else 82.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", Brand.SIZE_SMALL)
	button.add_theme_color_override("font_color", quiet_ink)
	button.add_theme_color_override("font_hover_color", ink)
	button.add_theme_color_override("font_pressed_color", ink)
	button.add_theme_color_override("font_focus_color", ink)
	var rest := Color(fill.r, fill.g, fill.b, 0.62)
	button.add_theme_stylebox_override("normal", _stop_box(rest, Color(0.0, 0.0, 0.0, 0.0), top_margin))
	button.add_theme_stylebox_override("hover", _stop_box(fill, Color(1.0, 1.0, 1.0, 0.55), top_margin))
	button.add_theme_stylebox_override("pressed", _stop_box(fill, Color(1.0, 1.0, 1.0, 0.95), top_margin))
	button.add_theme_stylebox_override("focus", _ring())
	var glyph := Glyph.make(Glyph.icon_for_level(level_id), glyph_size, quiet_ink)
	glyph.set_anchors_preset(Control.PRESET_CENTER_TOP)
	glyph.offset_left = -glyph_size / 2.0
	glyph.offset_right = glyph_size / 2.0
	glyph.offset_top = 10.0
	glyph.offset_bottom = 10.0 + glyph_size
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(glyph)
	button.toggled.connect(func(on: bool): glyph.tint = ink if on else quiet_ink)
	return button


## A stop's fill: the same family as the shared choice button, but with the top
## margin the icon band needs, which is what pushes the caption into the bottom
## band of the button.
func _stop_box(background: Color, border: Color, top_margin: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(3)
	box.content_margin_left = 8.0
	box.content_margin_right = 8.0
	box.content_margin_top = top_margin
	box.content_margin_bottom = 8.0
	return box


## A detail block: the smaller, secondary voice one section reveals for its
## chosen option. Built hidden; showing it fills the kicker (the option's full
## name, in the small accent voice) and the body (its explanation, in the
## smaller neutral voice). Nothing here knows which section owns it - levels,
## guardrails and owners each get their own instance.
func _detail_panel() -> Array:
	var panel := PanelContainer.new()
	panel.name = "Detail"
	var style := StyleBoxFlat.new()
	style.bg_color = Brand.SURFACE_RAISED
	style.border_color = Brand.NEUTRAL
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	var kicker := Label.new()
	kicker.add_theme_font_size_override("font_size", Brand.SIZE_SMALL)
	kicker.add_theme_color_override("font_color", Brand.ACCENT_TINT)
	box.add_child(kicker)
	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", Brand.SIZE_SMALL)
	body.add_theme_color_override("font_color", Brand.NEUTRAL_LIGHT)
	box.add_child(body)
	panel.visible = false
	return [panel, kicker, body]


## The line the stops ride on. A quiet base line spans the whole spectrum; the
## accent fill runs from the first stop to the selected one, so the position of
## the selection on the spectrum is drawn, not implied. Stop centres are
## computed from this control's own width, which matches the stop row's width
## because both span the same column.
class SpectrumTrack:
	extends Control

	var selected: int = -1
	var stop_count: int = 4

	func _draw() -> void:
		if stop_count < 2:
			return
		var y := size.y * 0.5
		var first := size.x * 0.5 / float(stop_count)
		var last := size.x * (float(stop_count) - 0.5) / float(stop_count)
		draw_line(Vector2(first, y), Vector2(last, y), Brand.NEUTRAL, 2.0)
		if selected >= 0:
			var to := size.x * (float(selected) + 0.5) / float(stop_count)
			draw_line(Vector2(first, y), Vector2(to, y), Brand.ACCENT, 3.0)


func _spectrum_title(text: String) -> Label:
	var label := Label.new()
	label.name = "SpectrumTitle"
	label.text = text
	label.add_theme_font_size_override("font_size", Brand.SIZE_TITLE)
	label.add_theme_color_override("font_color", Brand.INK)
	return label


## A step kicker: "1 · DECISION" in the machine voice. The three steps are the
## recurring shape of every console, so the numbers are the part that reads
## first and the words stay short.
func _step_kicker(number: String, word: String) -> Label:
	var label := Label.new()
	label.name = "Step" + number
	label.text = "%s · %s" % [number, word]
	Brand.apply_tui(label, Brand.SIZE_TUI_SMALL)
	label.add_theme_color_override("font_color", Brand.NEUTRAL)
	return label


func _note_label(text: String, tint: Color) -> Label:
	var label := Label.new()
	label.name = "Note"
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", Brand.SIZE_SMALL)
	label.add_theme_color_override("font_color", tint)
	return label


func _commit_fill(background: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.set_corner_radius_all(3)
	return box


func _ring() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	box.border_color = Brand.ACCENT
	box.set_border_width_all(2)
	box.set_corner_radius_all(3)
	return box


func _gap(height: float) -> Control:
	var spacer := Control.new()
	spacer.name = "Gap"
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.custom_minimum_size = Vector2(0.0, height)
	return spacer


func _on_option_pressed(option_id: String) -> void:
	if option_id == "close":
		close()
		return
	option_chosen.emit(option_id)
	if _puzzle != null and is_instance_valid(_puzzle):
		_puzzle.choose(option_id)


## The mobile shell's commit. Identical contract to the desktop spectrum's:
## the level id goes to listeners and to the puzzle, which records it and emits
## the read-back the shell then renders.
func _on_mobile_placement(level_id: String) -> void:
	placement_chosen.emit(level_id, "", "")
	if _puzzle != null and is_instance_valid(_puzzle):
		_puzzle.place(level_id)
		_puzzle.solve()
	## The placement is in and the bay is solved: the completion flow releases
	## the console and raises the score card (verdict, meters, spectrum). The
	## decision is never asked twice - a reopen reads the standing record.


## Reveals the readout on a click or a tap. Both are needed: a touchscreen never
## sends an InputEventMouseButton at all, so the click-only version of this left
## a phone unable to skip the typewriter and read the screen.
func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_reveal_all()
	elif event is InputEventScreenTouch and event.pressed:
		_reveal_all()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_reveal_all()
		return
	## A touch that nothing else consumed also reveals the readout, so the whole
	## screen is a skip target and not only the dimmed border. The option buttons
	## and the CLOSE button are Controls and take their own taps first, so this
	## never fires from a press that was meant for one of them.
	if event is InputEventScreenTouch and event.pressed:
		_reveal_all()


## Keeps the newest printed line in view, by moving the bar by hand.
##
## ScrollContainer has no scroll_to_bottom() in this engine build, and calling
## it crashed the terminal on the first printed line of every screen - the whole
## game died the moment a console was pressed. The bar is therefore set from its
## own maximum, and only AFTER a frame, because that maximum is not updated
## until the new line has been laid out: reading it in the same frame as the
## line is added scrolls to where the bar used to end.
##
## A screen whose content is shorter than the viewport has nothing to scroll,
## so its maximum is zero and this leaves it where it is.
func _snap_scroll() -> void:
	await get_tree().process_frame
	if is_inside_tree() and is_instance_valid(scroll):
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
