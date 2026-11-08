class_name ShipmindLeaderboard
extends Control
## SHIPMIND // LEADERBOARD — the in-game CRT terminal screen.
##
## Drop-in usage from your results flow:
##
##   var screen := ShipmindLeaderboard.new()
##   $UiLayer.add_child(screen)
##   screen.closed.connect(screen.queue_free)      # or return to your menu
##   screen.present_result(final_score, run_seconds)
##
## The screen fetches the board, shows the projected placement, walks the
## player through callsign entry, submits, then highlights their new row.
## Requires the LeaderboardClient autoload (LeaderboardClient.gd).
## A CLOSE control is built in (touch has no Escape key); `closed` fires from
## it or from Escape, and the host decides what happens next.
##
## Visual stack, bottom to top:
##   1. leaderboard_crt.webp   — the glass plate (behind everything)
##   2. leaderboard_frame.webp — the console frame; its window is transparent
##   3. the text UI            — clipped to that window, over the glass
##   4. crt_phosphor.gdshader  — scanlines/vignette, confined to the window

signal closed

const FONT_PATH := "res://library/shooter-scifi/fonts/ShareTechMono-Regular.ttf"
const CRT_TEXTURE_PATH := "res://assets/ui/leaderboard_crt.webp"
const FRAME_TEXTURE_PATH := "res://assets/ui/leaderboard_frame.webp"
const CRT_SHADER_PATH := "res://assets/ui/crt_phosphor.gdshader"
## Source-art dimensions and the frame's transparent window within them, in
## image pixels. The text layer is laid out inside this rect.
const IMG_SIZE := Vector2(2752, 1536)
const WINDOW_RECT := Rect2(742, 279, 1268, 959)
## Text is designed against a window this tall; _ui_scale follows the real one.
const DESIGN_WINDOW_HEIGHT := 700.0
const MAX_ROWS := 10

const COL_BG := Color("0b0805")
const COL_PHOSPHOR := Color("ffb343")
const COL_BRIGHT := Color("ffd97a")
const COL_DIM := Color("b26a1e")
const COL_FAINT := Color("6e4a1d")

var _font: Font
var _ui_scale := 1.0
var _mode := "default"
var _pending_score := 0
var _pending_seconds := 0
var _highlight := {}        # {"rank": int, "name": String} once a submission lands
var _row_labels: Array = [] # per row: {"rank": int, "name": String, "labels": Array}

var _text_root: Control
var _crt_overlay: ColorRect
var _title: Label
var _clock: Label
var _total: Label
var _projection: Label
var _grid: GridContainer
var _entry_row: HBoxContainer
var _name_edit: LineEdit
## The three details the crew enter, kept so a re-opened sheet starts where
## they left off, and the formatted name the entry is logged under.
var _first_name: String = ""
var _surname: String = ""
var _email: String = ""
var _pilot_name: String = ""
var _status: Label
var _cursor: ColorRect
## The board's content can outrun the frame's window on a phone, so it rides
## in a drag-to-scroll pane: a vertical drag pans it, and a release without a
## drag is still the "tap anywhere to leave" tap.
var _scroll: ScrollContainer
var _scroll_dragged: bool = false
var _scroll_press_at: Vector2 = Vector2.ZERO
## The callback the page calls back with the typed callsign.
var _js_done = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = load(FONT_PATH)
	# Defer one frame so `size` reflects the real viewport before layout.
	call_deferred("_start")


func _start() -> void:
	_build_layers()
	_layout()
	_build_ui()
	_connect_client()
	## Tap anywhere to leave: the screen itself is the landing spot for every
	## stray tap (labels and the art layers are click-transparent), and it
	## answers by closing. Guarded while the callsign row is up - mid entry a
	## stray thumb must not throw the run's result away.
	gui_input.connect(_on_gui_input)


## Any tap that no interactive control claimed lands here as the screen's own
## input; in attract mode (and after an entry is logged) that means "close".
## A mouse tap closes - a touch press never does: fingers drag the board, and
## at the scroll's edge the press bubbles up from the pane, so a touch that
## reaches the end of the list must not read as "leave". The CLOSE button is
## the way out on a touchscreen.
func _on_gui_input(event: InputEvent) -> void:
	var pressed: bool = event is InputEventMouseButton and event.pressed \
			and not DisplayServer.is_touchscreen_available()
	if pressed and not _entry_row.visible:
		closed.emit()


func _exit_tree() -> void:
	var c := get_node_or_null("/root/LeaderboardClient")
	if c == null:
		return
	for pair in [
		["leaderboard_received", _on_board],
		["rank_preview_received", _on_rank_preview],
		["submit_completed", _on_submitted],
		["request_failed", _on_failed],
	]:
		if c.is_connected(pair[0], pair[1]):
			c.disconnect(pair[0], pair[1])


# --- Public API ---------------------------------------------------------------

## Attract mode: standings only, no submission flow.
func show_board(mode := "default") -> void:
	_mode = mode
	_highlight = {}
	_projection.text = ""
	_entry_row.visible = false
	_status_line("FETCHING STANDINGS…")
	_client().fetch_leaderboard(mode, MAX_ROWS)


## Call when a run ends: shows the board, the projected placement, and opens
## the callsign entry row so the player can log their score.
func present_result(score: int, seconds: int, mode := "default") -> void:
	_mode = mode
	_pending_score = score
	_pending_seconds = seconds
	_highlight = {}
	_projection.text = ""
	_status_line("RUN COMPLETE — SCORE %s" % _fmt(score))
	_entry_row.visible = true
	_pilot_name = ""
	_email = ""
	## Desktops take the caret outright. On the web the crew tap the details
	## button and the page's own sheet answers with the keyboard.
	if _name_edit != null:
		_name_edit.text = ""
		if not OS.has_feature("web"):
			_name_edit.grab_focus()
	_client().fetch_leaderboard(mode, MAX_ROWS)
	_client().fetch_rank_preview(score, mode)


# --- Layered background + window layout ---------------------------------------

## The art layers: glass plate at the back, console frame over it. Both are
## full-rect and cover-scaled, so they stay registered at any aspect ratio.
func _build_layers() -> void:
	var crt := TextureRect.new()
	crt.texture = load(CRT_TEXTURE_PATH)
	crt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	crt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(crt)

	var frame := TextureRect.new()
	frame.texture = load(FRAME_TEXTURE_PATH)
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)

	# The text layer lives exactly inside the frame's transparent window.
	# Clipped, so a long board can never bleed over the console art.
	_text_root = Control.new()
	_text_root.clip_contents = true
	add_child(_text_root)


## Map WINDOW_RECT from image space into screen space (cover scaling, centred)
## and park the text layer there. Runs on build and on every resize.
func _layout() -> void:
	if _text_root == null:
		return
	var avail := size
	if avail.x <= 0.0 or avail.y <= 0.0:
		return
	var s := maxf(avail.x / IMG_SIZE.x, avail.y / IMG_SIZE.y)
	var origin := (avail - IMG_SIZE * s) * 0.5
	var r := Rect2(origin + WINDOW_RECT.position * s, WINDOW_RECT.size * s)
	_text_root.position = r.position
	_text_root.size = r.size
	if _crt_overlay:
		_crt_overlay.position = r.position
		_crt_overlay.size = r.size
	_ui_scale = clampf(r.size.y / DESIGN_WINDOW_HEIGHT, 0.6, 3.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


# --- UI construction ----------------------------------------------------------

func _build_ui() -> void:
	## The scroll pane: the header, the table and the callsign entry together
	## read taller than the glass on a phone, and the entry row sat below the
	## frame where no thumb could reach it. A vertical drag pans the whole
	## board; the scrollbar stays hidden - the CRT carries no chrome.
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.gui_input.connect(_on_scroll_input)
	_text_root.add_child(_scroll)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", int(40 * _ui_scale))
	margin.add_theme_constant_override("margin_right", int(40 * _ui_scale))
	margin.add_theme_constant_override("margin_top", int(28 * _ui_scale))
	margin.add_theme_constant_override("margin_bottom", int(24 * _ui_scale))
	_scroll.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(6 * _ui_scale))
	margin.add_child(vbox)

	# Header — title block left, clock + PWR + CLOSE right.
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title_block := VBoxContainer.new()
	title_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_block)
	_title = _mk_label("SHIPMIND", 64, COL_BRIGHT)
	title_block.add_child(_title)
	title_block.add_child(_mk_label(
		"INTELLIGENT OPERATING MODEL SIMULATION — LEADERBOARD", 20, COL_DIM))

	var header_right := VBoxContainer.new()
	header.add_child(header_right)
	_clock = _mk_label("", 20, COL_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	header_right.add_child(_clock)
	header_right.add_child(_mk_label("PWR ▮ ONLINE", 20, COL_DIM, HORIZONTAL_ALIGNMENT_RIGHT))
	# Touch has no Escape key, so the board always carries its own way out.
	header_right.add_child(_mk_close_button())

	vbox.add_child(_rule())

	_projection = _mk_label("", 20, COL_DIM)
	vbox.add_child(_projection)

	# Table — three columns: the rank, the pilot, the score. The ship type and
	# the docking status read as clutter on a phone; the run's numbers are the
	# board.
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", int(20 * _ui_scale))
	_grid.add_theme_constant_override("v_separation", int(4 * _ui_scale))
	vbox.add_child(_grid)
	_add_row_cells(["RANK", "PILOT", "SCORE"], COL_DIM, 20, false)

	# Details entry — hidden unless we're presenting a result. On the web the
	# crew enter three details - first name, surname and an email address -
	# through the page's own keyboard sheet; the name comes back formatted and
	# the entry submits itself. Native builds keep the plain field.
	_entry_row = HBoxContainer.new()
	_entry_row.add_theme_constant_override("separation", int(16 * _ui_scale))
	_entry_row.visible = false
	vbox.add_child(_entry_row)
	_entry_row.add_child(_mk_label("ENTER YOUR DETAILS:", 24, COL_PHOSPHOR))

	if OS.has_feature("web"):
		var details_button := Button.new()
		details_button.text = "TAP TO ENTER DETAILS"
		details_button.focus_mode = Control.FOCUS_NONE
		details_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details_button.custom_minimum_size = Vector2(0, int(40 * _ui_scale))
		if _font:
			details_button.add_theme_font_override("font", _font)
		details_button.add_theme_font_size_override("font_size", maxi(int(24 * _ui_scale), 12))
		details_button.add_theme_color_override("font_color", COL_BG)
		details_button.add_theme_color_override("font_hover_color", COL_BG)
		var btn_style := StyleBoxFlat.new()
		btn_style.bg_color = COL_PHOSPHOR
		btn_style.content_margin_left = 24
		btn_style.content_margin_right = 24
		details_button.add_theme_stylebox_override("normal", btn_style)
		details_button.add_theme_stylebox_override("hover", btn_style)
		details_button.add_theme_stylebox_override("pressed", btn_style)
		details_button.pressed.connect(_open_page_keyboard)
		_entry_row.add_child(details_button)
	else:
		_build_native_entry_row()

	vbox.add_child(_rule())

	# Footer — segment blocks, status line, blinking cursor.
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", int(18 * _ui_scale))
	vbox.add_child(footer)

	var segs := HBoxContainer.new()
	segs.add_theme_constant_override("separation", int(4 * _ui_scale))
	for i in 8:
		var s := ColorRect.new()
		s.color = COL_DIM if i < 6 else COL_FAINT
		s.custom_minimum_size = Vector2(int(18 * _ui_scale), int(14 * _ui_scale))
		segs.add_child(s)
	footer.add_child(segs)

	_status = _mk_label("STANDBY", 20, COL_PHOSPHOR)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_status)

	_total = _mk_label("", 20, COL_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	footer.add_child(_total)

	_cursor = ColorRect.new()
	_cursor.color = COL_PHOSPHOR
	_cursor.custom_minimum_size = Vector2(int(14 * _ui_scale), int(24 * _ui_scale))
	footer.add_child(_cursor)

	# Scanlines + vignette, confined to the window and input-transparent.
	_crt_overlay = ColorRect.new()
	_crt_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader: Shader = load(CRT_SHADER_PATH)
	if shader:
		var sm := ShaderMaterial.new()
		sm.shader = shader
		_crt_overlay.material = sm
	add_child(_crt_overlay)
	_layout()  # park the overlay on the window now that it exists

	# Ambient timers: clock, cursor blink, phosphor flicker on the title.
	var clock_timer := Timer.new()
	clock_timer.wait_time = 1.0
	clock_timer.timeout.connect(_tick_clock)
	add_child(clock_timer)
	clock_timer.start()
	_tick_clock()

	var blink := Timer.new()
	blink.wait_time = 0.53
	blink.timeout.connect(func():
		_cursor.visible = not _cursor.visible
	)
	add_child(blink)
	blink.start()

	var flicker := Timer.new()
	flicker.wait_time = 0.09
	flicker.timeout.connect(func():
		_title.modulate.a = 0.94 + randf() * 0.06
	)
	add_child(flicker)
	flicker.start()

	## Live board: while the screen is up, scores other pilots post arrive
	## every minute without a reload. The refresh is quiet - _on_board only
	## rewrites the status when it was still FETCHING, so an entry in progress
	## is never talked over - and the screen frees on close, so the polling
	## dies with it.
	var refresh := Timer.new()
	refresh.wait_time = 60.0
	refresh.timeout.connect(func(): _client().fetch_leaderboard(_mode, MAX_ROWS))
	add_child(refresh)
	refresh.start()

	## The text layer is click-transparent to its bones: taps fall through to
	## the screen itself, which closes on them - while the buttons and the
	## callsign field keep their own handling. The scroll pane is exempt too:
	## it must keep the drags that pan the board, and it hands back the taps
	## that mean "leave".
	var stack: Array[Node] = [_text_root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is Control and not (node is Button or node is LineEdit \
				or node is ScrollContainer):
			(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


## The scroll pane's own input: on a mouse, a press-and-release that never
## became a drag is the stray tap the screen answers by closing (attract mode
## only - mid entry a stray thumb must not throw the run's result away). On a
## touchscreen the release closes nothing: a finger's travel is how the board
## scrolls, and the CLOSE button is the way out - a touch that pans must never
## read as a tap on release.
func _on_scroll_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_scroll_press_at = event.position
			_scroll_dragged = false
		elif not _scroll_dragged and not _entry_row.visible \
				and not DisplayServer.is_touchscreen_available():
			closed.emit()
	elif event is InputEventMouseMotion \
			and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		if event.position.distance_to(_scroll_press_at) > 12.0:
			_scroll_dragged = true
	elif event is InputEventScreenDrag:
		if event.position.distance_to(_scroll_press_at) > 12.0:
			_scroll_dragged = true


## Native builds (outside the browser) keep the plain field and the LOG
## button: a physical keyboard needs no page-level sheet.
func _build_native_entry_row() -> void:
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.max_length = 24
	_name_edit.placeholder_text = "—"
	_name_edit.caret_blink = true
	_name_edit.custom_minimum_size = Vector2(0, int(40 * _ui_scale))
	_name_edit.text_changed.connect(func(t): _pilot_name = t.strip_edges())
	if _font:
		_name_edit.add_theme_font_override("font", _font)
	_name_edit.add_theme_font_size_override("font_size", maxi(int(24 * _ui_scale), 12))
	_name_edit.add_theme_color_override("font_color", COL_BRIGHT)
	_name_edit.add_theme_color_override("caret_color", COL_PHOSPHOR)
	_name_edit.add_theme_stylebox_override("normal", _field_style(COL_FAINT))
	_name_edit.add_theme_stylebox_override("focus", _field_style(COL_PHOSPHOR))
	_name_edit.text_submitted.connect(func(_t): _on_log_entry())
	_entry_row.add_child(_name_edit)

	var log_button := Button.new()
	log_button.text = "LOG ENTRY"
	log_button.focus_mode = Control.FOCUS_NONE
	log_button.custom_minimum_size = Vector2(0, int(40 * _ui_scale))
	if _font:
		log_button.add_theme_font_override("font", _font)
	log_button.add_theme_font_size_override("font_size", maxi(int(24 * _ui_scale), 12))
	log_button.add_theme_color_override("font_color", COL_BG)
	log_button.add_theme_color_override("font_hover_color", COL_BG)
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = COL_PHOSPHOR
	btn_style.content_margin_left = 24
	btn_style.content_margin_right = 24
	log_button.add_theme_stylebox_override("normal", btn_style)
	log_button.add_theme_stylebox_override("hover", btn_style)
	log_button.add_theme_stylebox_override("pressed", btn_style)
	log_button.pressed.connect(_on_log_entry)
	_entry_row.add_child(log_button)


# --- Client signal handlers ---------------------------------------------------

func _on_board(entries: Array, total_players: int) -> void:
	_clear_rows()
	_total.text = "PILOTS: %d" % total_players
	for entry in entries:
		if _row_labels.size() >= MAX_ROWS:
			break
		var pilot := String(entry.get("player_name", "—"))
		var rank := int(entry.get("rank", 0))
		_add_row_cells(
			["%02d" % rank, pilot.to_upper(), _fmt(int(entry.get("score", 0)))],
			COL_PHOSPHOR, 24, true, rank, pilot)
	if _status.text.begins_with("FETCHING"):
		_status_line("STANDINGS CURRENT")
	_apply_highlight()


func _on_rank_preview(rank: int, total_players: int) -> void:
	_projection.text = "CURRENT RUN PROJECTION: #%02d OF %d" % [rank, total_players]


func _on_submitted(result: Dictionary) -> void:
	var entry: Dictionary = result.get("entry", {})
	_highlight = {
		"rank": int(result.get("rank", 0)),
		"name": String(entry.get("player_name", "")).to_upper(),
	}
	_status_line("ENTRY LOGGED — POSITION #%02d OF %d" % [
		_highlight.rank, int(result.get("total_players", 0))])
	# Refresh the board so the new row renders, then gets highlighted.
	_client().fetch_leaderboard(_mode, MAX_ROWS)


func _on_failed(action: String, _message: String) -> void:
	if action == "submit":
		# LeaderboardClient has the payload queued on disk; it will retry
		# on the next launch or next submit.
		_status_line("UPLINK OFFLINE — ENTRY QUEUED, WILL SYNC")
	else:
		_status_line("UPLINK OFFLINE — SHOWING LAST DATA")


# --- Internals ----------------------------------------------------------------

func _client() -> Node:
	return get_node("/root/LeaderboardClient")


## Wire the autoload's signals to this screen. Called from _start; _exit_tree
## undoes it, so a freed screen never answers a late leaderboard response.
func _connect_client() -> void:
	var c := _client()
	c.leaderboard_received.connect(_on_board)
	c.rank_preview_received.connect(_on_rank_preview)
	c.submit_completed.connect(_on_submitted)
	c.request_failed.connect(_on_failed)


## Opens the shell-hosted details sheet: first name, surname, and an email
## address the page syntax-checks. Runs inside the tap's gesture - the browser
## guarantees the keyboard for a focus made there.
func _open_page_keyboard() -> void:
	if not bool(JavaScriptBridge.eval("!!window.pwcKeyboard")):
		push_warning("The page offers no details sheet; the entry cannot be logged.")
		return
	_js_done = JavaScriptBridge.create_callback(_on_page_keyboard_done)
	var js := JavaScriptBridge.get_interface("window")
	js.pwcKeyboardDone = _js_done
	var fields := JSON.stringify([
		{"label": "FIRST NAME", "value": _first_name, "kind": "text"},
		{"label": "SURNAME", "value": _surname, "kind": "text"},
		{"label": "EMAIL ADDRESS", "value": _email, "kind": "email"},
	])
	JavaScriptBridge.eval("window.pwcKeyboard.open(%s, window.pwcKeyboardDone);" % fields)


## The page answers with the three details as a JSON string (or null on
## cancel): a JS array does not survive the bridge as a GDScript array, so the
## sheet stringifies and the game parses. The name reads back the room-console
## way - first initial, surname - and the entry logs itself, the email riding
## along but never shown on the board.
func _on_page_keyboard_done(args: Array) -> void:
	if args.is_empty() or args[0] == null:
		return
	var values: Array = JSON.parse_string(String(args[0]))
	if values == null or values.size() < 3:
		return
	_first_name = String(values[0])
	_surname = String(values[1])
	_email = String(values[2])
	_pilot_name = _formatted_name()
	_on_log_entry()


func _formatted_name() -> String:
	var first := _first_name.strip_edges()
	var last := _surname.strip_edges()
	if first != "" and last != "":
		return "%s. %s" % [first.substr(0, 1).to_upper(), last.capitalize()]
	return (first + " " + last).strip_edges().capitalize()


func _on_log_entry() -> void:
	if _name_edit != null:
		_pilot_name = _name_edit.text.strip_edges()
	var pilot := _pilot_name
	if pilot.is_empty():
		_status_line("YOUR DETAILS ARE REQUIRED")
		return
	_entry_row.visible = false
	_status_line("LOGGING ENTRY — %s // %s PTS" % [pilot.to_upper(), _fmt(_pending_score)])
	_client().submit_score(pilot, _pending_score, _mode, _pending_seconds, _email)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			closed.emit()
			get_viewport().set_input_as_handled()


func _add_row_cells(
	texts: Array, color: Color, base_size: int, is_data: bool,
	rank := 0, pilot := ""
) -> void:
	var labels: Array = []
	## The columns hug their content: a wide pilot column pushed the score to
	## the far edge of the glass at larger text sizes.
	for i in texts.size():
		var l := _mk_label(String(texts[i]), base_size, color)
		if i == 2:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if is_data:
			l.custom_minimum_size.y = int(34 * _ui_scale)
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_grid.add_child(l)
		labels.append(l)
	if is_data:
		_row_labels.append({"rank": rank, "name": pilot.to_upper(), "labels": labels})


func _clear_rows() -> void:
	for row in _row_labels:
		for l in row.labels:
			l.queue_free()
	_row_labels.clear()


func _apply_highlight() -> void:
	if _highlight.is_empty():
		return
	for row in _row_labels:
		if row.rank == _highlight.rank and row.name == _highlight.name:
			for l in row.labels:
				l.add_theme_color_override("font_color", COL_BRIGHT)
			row.labels[0].text = "▶" + row.labels[0].text
			_pulse(row.labels)
			return


func _pulse(labels: Array) -> void:
	var set_alpha := func(a):
		for l in labels:
			l.modulate.a = a
	var tw := create_tween()
	tw.set_loops(4)
	tw.tween_method(set_alpha, 1.0, 0.55, 0.4)
	tw.tween_method(set_alpha, 0.55, 1.0, 0.4)


## The board's own clock, ticking in the header while the screen is up.
func _tick_clock() -> void:
	_clock.text = "T " + Time.get_time_string_from_system(true)


func _status_line(text: String) -> void:
	_status.text = text


func _fmt(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out


func _mk_label(text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	if _font:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", maxi(int(size * _ui_scale), 12))
	l.add_theme_color_override("font_color", color)
	return l


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = COL_FAINT
	r.custom_minimum_size = Vector2(0, 2)
	return r


func _field_style(border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(COL_BG, 0.0)
	sb.border_color = border
	sb.border_width_bottom = 2
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	return sb


## The exit: same bezel language as the rest of the terminal, sized for a thumb.
## Emits `closed`, which the host decides how to answer (free the screen, or
## hand the pause card back).
func _mk_close_button() -> Button:
	var button := Button.new()
	button.text = "CLOSE ✕"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(int(150 * _ui_scale), int(44 * _ui_scale))
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	if _font:
		button.add_theme_font_override("font", _font)
	button.add_theme_font_size_override("font_size", maxi(int(20 * _ui_scale), 12))
	button.add_theme_color_override("font_color", COL_PHOSPHOR)
	button.add_theme_color_override("font_hover_color", COL_BRIGHT)
	button.add_theme_color_override("font_pressed_color", COL_BRIGHT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(COL_BG, 0.0)
	style.border_color = COL_DIM
	style.set_border_width_all(2)
	style.set_corner_radius_all(2)
	style.content_margin_left = 16
	style.content_margin_right = 16
	button.add_theme_stylebox_override("normal", style)
	var hovered: StyleBoxFlat = style.duplicate()
	hovered.border_color = COL_PHOSPHOR
	button.add_theme_stylebox_override("hover", hovered)
	button.add_theme_stylebox_override("pressed", hovered)
	button.add_theme_stylebox_override("focus", style)
	button.pressed.connect(func(): closed.emit())
	return button
