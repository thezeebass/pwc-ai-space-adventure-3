class_name PauseMenu
extends CanvasLayer

## The in-run menu: the ship's settings and the way back out of the run.
##
## The jobs, in the order a player needs them: the SHIPMIND BOARD (live
## standings, readable mid-run), the music switch (so muting the soundtrack
## does not require leaving the run), the input mode chips (the test switch,
## usable mid-run), and RESET PROGRESS - the explicit clean start, which wipes
## the record and reloads the ship. There is no RESUME button: tapping outside
## the card closes the menu, and so does Escape - returning to the run is the
## gesture you are already making, not a button you must find.
##
## Escape opens and closes this menu. While it is up the run clock is stopped -
## GameState.tick only advances while run_running, and the menu owns that flag
## for as long as it is visible - so a paused crew is not billed for thinking.
## Opening is refused while any other overlay owns the screen, exactly as the
## dev menu does: two modals must never stack.

signal main_menu_requested
## The crew want the run wiped and started from the top. The controller owns
## the reload, because only it can hand the scene back in a clean state.
signal reset_requested

const PAPAYA := Color(0.863, 0.369, 0.153)
const TANGERINE := Color(0.816, 0.251, 0.149)
const GOLD := Color(0.941, 0.722, 0.224)
const WHITE := Color(1.0, 1.0, 1.0)
const INK := Color(0.93, 0.89, 0.85)
const MUTED := Color(0.72, 0.66, 0.62)

var _root: Control = null
var _card: PanelContainer = null
var _board_button: Button = null
var _text_size_buttons: Dictionary = {}
var _reset_button: Button = null
var _reset_confirm: HBoxContainer = null
var _reset_note: Label = null
## The SHIPMIND standings screen while it is up, hosted inside this layer.
var _board: ShipmindLeaderboard = null

var _open: bool = false


func _ready() -> void:
	layer = 110
	_build()
	visible = false
	TextZoom.register(_root)


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	InputRouter.set_ui_blocking(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# The clock stops while the crew are in the menu, and restarts on close.
	GameState.run_running = false
	_disarm_reset()
	_refresh_text_size_chips()
	# The menu is keyboard- and gamepad-reachable from here: focus lands on
	# the SHIPMIND BOARD, and Tab walks on to the audio and text controls.
	if _board_button != null:
		_board_button.grab_focus()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	_discard_board()
	InputRouter.set_ui_blocking(false)
	# Only a run that has started has a clock to hand back; the flag is what
	# GameState.tick reads, so restoring it here is the whole unpause.
	GameState.run_running = GameState.run_started
	_disarm_reset()
	for node in get_tree().get_nodes_in_group("input_layer"):
		if node.has_method("grab_mouse"):
			node.grab_mouse()


## Back to the title card. The UI block is left in place on purpose - the
## launch screen takes ownership of it when it opens - and the clock stays
## stopped until the crew press BEGIN again.
func main_menu() -> void:
	if not _open:
		return
	_open = false
	visible = false
	_discard_board()
	GameState.run_running = false
	main_menu_requested.emit()


## The standings ride on top of the menu card in this same layer: the dim and
## the card stay underneath, unreachable while the full-rect board is up, and
## closing the board simply reveals the menu again. No controller wiring is
## needed - the clock is stopped and the input block is already held by open().
func _on_text_size(size: int) -> void:
	GameState.ui_text_size = size
	GameState.save()
	## One call re-derives every registered screen - including this menu,
	## live, while it is open.
	TextZoom.set_size(size)


func _refresh_text_size_chips() -> void:
	for value in _text_size_buttons:
		var chip: Button = _text_size_buttons[value]
		chip.set_pressed_no_signal(int(value) == GameState.ui_text_size)


func _open_board() -> void:
	if _board != null:
		return
	_board = ShipmindLeaderboard.new()
	add_child(_board)
	_board.closed.connect(_close_board)
	## Same note as the completion screen's uplink: the board assembles itself
	## one frame after it enters the tree, so the fetch starts on that frame.
	_board.call_deferred("show_board")
	_root.visible = false


func _close_board() -> void:
	_discard_board()
	_root.visible = _open


func _discard_board() -> void:
	if _board != null:
		_board.queue_free()
		_board = null


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _board != null:
		# The standings screen is up: the first escape closes it, not the menu.
		_close_board()
	elif _open:
		close()
	elif not InputRouter.ui_blocking:
		# Another overlay owns the screen; do not stack two modals.
		open()
	else:
		return
	get_viewport().set_input_as_handled()


# --- Build -----------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.04, 0.025, 0.02, 0.86)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			close())
	_root.add_child(dim)

	var card := PanelContainer.new()
	card.name = "Card"
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.04, 0.03, 0.98)
	style.border_color = PAPAYA
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 34.0
	style.content_margin_right = 34.0
	style.content_margin_top = 26.0
	style.content_margin_bottom = 28.0
	card.add_theme_stylebox_override("panel", style)
	_root.add_child(card)
	_card = card
	_clamp_card_to_safe_zone()
	card.get_viewport().size_changed.connect(_clamp_card_to_safe_zone)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	card.add_child(column)

	var kicker := Label.new()
	kicker.text = "ADAMANT VERITY"
	kicker.add_theme_font_size_override("font_size", 30)
	kicker.add_theme_color_override("font_color", PAPAYA)
	column.add_child(kicker)

	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", WHITE)
	column.add_child(title)

	column.add_child(_spacer(8))

	# The live SHIPMIND standings, readable mid-run. The board replaces the
	# card while it is up and hands the card back when it closes; the clock is
	# already stopped because the menu underneath it is open.
	var board_button := Button.new()
	board_button.text = "LEADERBOARD"
	board_button.focus_mode = Control.FOCUS_ALL
	board_button.add_theme_font_size_override("font_size", 30)
	board_button.add_theme_color_override("font_color", PAPAYA)
	board_button.add_theme_color_override("font_hover_color", GOLD)
	var board_style := _ghost_style()
	board_style.border_color = TANGERINE
	board_button.add_theme_stylebox_override("normal", board_style)
	board_button.add_theme_stylebox_override("hover", board_style)
	board_button.add_theme_stylebox_override("pressed", board_style)
	board_button.add_theme_stylebox_override("focus", board_style)
	board_button.pressed.connect(_open_board)
	_board_button = board_button
	column.add_child(board_button)

	# The mixer, not just a music switch: music, ambience and sfx each carry
	# their own mute and fader, because "turn the music down" and "quiet the
	# sound effects" are different requests and one toggle cannot answer both.
	var audio_caption := Label.new()
	audio_caption.text = "AUDIO"
	audio_caption.add_theme_font_size_override("font_size", 30)
	audio_caption.add_theme_color_override("font_color", MUTED)
	column.add_child(audio_caption)
	var audio_panel := AudioPanel.new()
	audio_panel.name = "AudioPanel"
	column.add_child(audio_panel)

	## TEXT SIZE: how large the info popups read - SHIPMIND speech, prompts,
	## the walkthrough cards. S and M dip under the reading floor on purpose;
	## L is the floor itself.
	column.add_child(_spacer(6))
	var size_caption := Label.new()
	size_caption.text = "TEXT SIZE"
	size_caption.add_theme_font_size_override("font_size", 30)
	size_caption.add_theme_color_override("font_color", MUTED)
	column.add_child(size_caption)
	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 6)
	var size_group := ButtonGroup.new()
	size_group.allow_unpress = false
	for option in [[24, "S"], [28, "M"], [30, "L"]]:
		var chip := Button.new()
		chip.text = option[1]
		chip.toggle_mode = true
		chip.button_group = size_group
		chip.focus_mode = Control.FOCUS_NONE
		chip.add_theme_font_size_override("font_size", 30)
		chip.add_theme_color_override("font_color", MUTED)
		chip.add_theme_color_override("font_hover_color", WHITE)
		chip.add_theme_color_override("font_pressed_color", Color(0.1, 0.06, 0.04))
		var idle := _ghost_style()
		chip.add_theme_stylebox_override("normal", idle)
		var hovered := _ghost_style()
		hovered.border_color = TANGERINE
		chip.add_theme_stylebox_override("hover", hovered)
		var chosen := _ghost_style()
		chosen.bg_color = GOLD
		chosen.border_color = GOLD
		chip.add_theme_stylebox_override("pressed", chosen)
		chip.add_theme_stylebox_override("focus", idle)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.pressed.connect(_on_text_size.bind(int(option[0])))
		_text_size_buttons[int(option[0])] = chip
		size_row.add_child(chip)
	column.add_child(size_row)

	column.add_child(_spacer(10))
	_reset_button = Button.new()
	_reset_button.text = "RESET PROGRESS"
	_reset_button.focus_mode = Control.FOCUS_NONE
	_reset_button.tooltip_text = "Wipes the mission record and starts the run again."
	_reset_button.add_theme_font_size_override("font_size", 30)
	_reset_button.add_theme_color_override("font_color", MUTED)
	_reset_button.add_theme_color_override("font_hover_color", PAPAYA)
	var reset_rest := _ghost_style()
	reset_rest.border_color = Color(0.30, 0.22, 0.18)
	_reset_button.add_theme_stylebox_override("normal", reset_rest)
	var reset_hover := _ghost_style()
	reset_hover.border_color = PAPAYA
	_reset_button.add_theme_stylebox_override("hover", reset_hover)
	_reset_button.add_theme_stylebox_override("pressed", reset_hover)
	_reset_button.add_theme_stylebox_override("focus", reset_rest)
	_reset_button.pressed.connect(_on_reset_pressed)
	column.add_child(_reset_button)

	# Reset is destructive, so it asks once, in place: the single button gives
	# way to an explicit RESET EVERYTHING / CANCEL pair. A timer-based "press
	# again" was harder to read and could expire mid-decision.
	_reset_confirm = HBoxContainer.new()
	_reset_confirm.name = "ResetConfirm"
	_reset_confirm.add_theme_constant_override("separation", 10)
	_reset_confirm.visible = false
	column.add_child(_reset_confirm)

	var reset_yes := Button.new()
	reset_yes.name = "ResetEverything"
	reset_yes.text = "RESET EVERYTHING"
	reset_yes.focus_mode = Control.FOCUS_NONE
	reset_yes.custom_minimum_size = Vector2(0.0, 38.0)
	reset_yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_yes.add_theme_font_size_override("font_size", 30)
	reset_yes.add_theme_color_override("font_color", Color.WHITE)
	reset_yes.add_theme_color_override("font_hover_color", Color.WHITE)
	var yes_fill := StyleBoxFlat.new()
	yes_fill.bg_color = PAPAYA
	yes_fill.border_color = PAPAYA
	yes_fill.set_border_width_all(1)
	yes_fill.set_corner_radius_all(3)
	reset_yes.add_theme_stylebox_override("normal", yes_fill)
	var yes_hover: StyleBoxFlat = yes_fill.duplicate()
	yes_hover.bg_color = Color(0.94, 0.44, 0.18)
	reset_yes.add_theme_stylebox_override("hover", yes_hover)
	reset_yes.add_theme_stylebox_override("pressed", yes_fill)
	reset_yes.pressed.connect(_confirm_reset)
	_reset_confirm.add_child(reset_yes)

	var reset_no := Button.new()
	reset_no.name = "CancelReset"
	reset_no.text = "CANCEL"
	reset_no.focus_mode = Control.FOCUS_NONE
	reset_no.custom_minimum_size = Vector2(120.0, 38.0)
	reset_no.add_theme_font_size_override("font_size", 30)
	reset_no.add_theme_color_override("font_color", MUTED)
	reset_no.add_theme_color_override("font_hover_color", GOLD)
	var no_style := _ghost_style()
	reset_no.add_theme_stylebox_override("normal", no_style)
	reset_no.add_theme_stylebox_override("hover", no_style)
	reset_no.add_theme_stylebox_override("pressed", no_style)
	reset_no.add_theme_stylebox_override("focus", no_style)
	reset_no.pressed.connect(_disarm_reset)
	_reset_confirm.add_child(reset_no)

	_reset_note = Label.new()
	_reset_note.name = "ResetNote"
	_reset_note.text = "Clears every decision and the mandate, then starts over."
	_reset_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reset_note.add_theme_font_size_override("font_size", 30)
	_reset_note.add_theme_color_override("font_color", Color(0.55, 0.48, 0.44))
	column.add_child(_reset_note)


## The safe zone: the card is centred, but its 380px minimum width would ride
## the bezel on a narrow phone - it shrinks to live inside the margins.
func _clamp_card_to_safe_zone() -> void:
	if _card == null or _root == null:
		return
	var view: Vector2 = _root.get_viewport_rect().size
	var inset: float = Brand.safe_inset(view)
	_card.custom_minimum_size.x = minf(380.0, maxf(view.x - inset * 2.0, 240.0))


## The first press asks; it never wipes anything by itself. The explicit pair
## appears in place of the button, so the question and its answer sit together.
func _on_reset_pressed() -> void:
	if _reset_button != null:
		_reset_button.visible = false
	if _reset_confirm != null:
		_reset_confirm.visible = true
	if _reset_note != null:
		_reset_note.text = "This cannot be undone. Clear every decision and start the run over?"


func _confirm_reset() -> void:
	_disarm_reset()
	_open = false
	visible = false
	_discard_board()
	GameState.run_running = false
	reset_requested.emit()


func _disarm_reset() -> void:
	if _reset_confirm != null:
		_reset_confirm.visible = false
	if _reset_button != null:
		_reset_button.visible = true
	if _reset_note != null:
		_reset_note.text = "Clears every decision and the mandate, then starts over."


func _ghost_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.25)
	style.border_color = Color(0.4, 0.32, 0.26)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer
