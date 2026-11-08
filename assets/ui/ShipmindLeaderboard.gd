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
const FONT_FLOOR := 30
const MAX_ROWS := 10
const ACTIVE_WINDOW_SECONDS := 900   # submissions younger than this read "ACTIVE"

const COL_BG := Color("0b0805")
const COL_PHOSPHOR := Color("ffb343")
const COL_BRIGHT := Color("ffd97a")
const COL_DIM := Color("b26a1e")
const COL_FAINT := Color("6e4a1d")

# Decorative until the API carries a real ship_type field: a stable per-pilot
# hull assignment, so the same callsign always "flies" the same frame.
const SHIP_FRAMES := ["O-Prowler", "Gold-Ares", "Rust-Vane", "C-Mothership", "Red-Vane", "Pink-Stern"]

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
var _status: Label
var _cursor: ColorRect
## The board's content can outrun the frame's window on a phone, so it rides
## in a drag-to-scroll pane: a vertical drag pans it, and a release without a
## drag is still the "tap anywhere to leave" tap.
var _scroll: ScrollContainer
var _scroll_dragged: bool = false
var _scroll_press_at: Vector2 = Vector2.ZERO


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
func _on_gui_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventScreenTouch and event.pressed)
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
	_name_edit.text = ""
	## Desktops take the caret outright. A web keyboard answers only a focus
	## that a gesture started: a programmatic focus raises nothing, so on the
	## web the crew tap the field themselves and that tap does the focusing.
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

	# Table.
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", int(20 * _ui_scale))
	_grid.add_theme_constant_override("v_separation", int(4 * _ui_scale))
	vbox.add_child(_grid)
	_add_row_cells(["RANK", "PILOT NAME", "SHIP TYPE", "SCORE", "STATUS"], COL_DIM, 20, false)

	# Callsign entry — hidden unless we're presenting a result.
	_entry_row = HBoxContainer.new()
	_entry_row.add_theme_constant_override("separation", int(16 * _ui_scale))
	_entry_row.visible = false
	vbox.add_child(_entry_row)
	_entry_row.add_child(_mk_label("ENTER CALLSIGN:", 24, COL_PHOSPHOR))

	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.max_length = 24
	_name_edit.placeholder_text = "—"
	_name_edit.caret_blink = true
	_name_edit.custom_minimum_size = Vector2(0, int(40 * _ui_scale))
	## The tap that focuses the field on the web - the keyboard answers a
	## gesture, not a flag (see _on_name_input).
	_name_edit.gui_input.connect(_on_name_input)
	if _font:
		_name_edit.add_theme_font_override("font", _font)
	_name_edit.add_theme_font_size_override("font_size", maxi(int(24 * _ui_scale), FONT_FLOOR))
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
	log_button.add_theme_font_size_override("font_size", maxi(int(24 * _ui_scale), FONT_FLOOR))
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


## The scroll pane's own input: a press-and-release that never became a drag is
## the same stray tap the screen answers by closing (attract mode only - mid
## entry a stray thumb must not throw the run's result away). A press that
## travels is a scroll, and the pane pans it.
func _on_scroll_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_scroll_press_at = event.position
			_scroll_dragged = false
		elif not _scroll_dragged and not _entry_row.visible:
			closed.emit()
	elif event is InputEventMouseMotion \
			and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		if event.position.distance_to(_scroll_press_at) > 12.0:
			_scroll_dragged = true


# --- Client signal handlers ---------------------------------------------------

func _on_board(entries: Array, total_players: int) -> void:
	_clear_rows()
	_total.text = "PILOTS: %d" % total_players
	for entry in entries:
		if _row_labels.size() >= MAX_ROWS:
			break
		var pilot := String(entry.get("player_name", "—"))
		var rank := int(entry.get("rank", 0))
		var status := _status_from(String(entry.get("created_at", "")))
		_add_row_cells(
			["%02d" % rank, pilot.to_upper(), _ship_type_for(pilot),
			 _fmt(int(entry.get("score", 0))), status],
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


## The tap that focuses the callsign field on the web. A field that is already
## focused never re-runs the focus hook the keyboard answers, so the tap drops
## and re-grabs focus - and the keyboard itself is re-raised a beat later: the
## engine's own handlers make the canvas take focus back around the tap, which
## can close the keyboard the moment it opens. Raising it again after the steal
## wins, and is harmless when the keyboard is already up.
func _on_name_input(event: InputEvent) -> void:
	if OS.has_feature("web") and (
			(event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and event.pressed)):
		_name_edit.release_focus()
		_name_edit.grab_focus()
		_raise_keyboard.call_deferred()
		get_tree().create_timer(0.25).timeout.connect(_raise_keyboard)


## Puts the keyboard up under the callsign field directly, whatever the focus
## dance just did.
func _raise_keyboard() -> void:
	if not _entry_row.visible or not _name_edit.has_focus():
		return
	var rect := _name_edit.get_global_rect()
	DisplayServer.virtual_keyboard_show(_name_edit.text,
		Rect2i(rect.position, rect.size),
		DisplayServer.KEYBOARD_TYPE_DEFAULT, _name_edit.max_length,
		0, _name_edit.text.length())


func _on_log_entry() -> void:
	var pilot := _name_edit.text.strip_edges()
	if pilot.is_empty():
		_status_line("CALLSIGN REQUIRED")
		return
	_entry_row.visible = false
	_status_line("LOGGING ENTRY — %s // %s PTS" % [pilot.to_upper(), _fmt(_pending_score)])
	_client().submit_score(pilot, _pending_score, _mode, _pending_seconds)


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
	for i in texts.size():
		var l := _mk_label(String(texts[i]), base_size, color)
		if i == 0:
			l.custom_minimum_size.x = int(70 * _ui_scale)
		elif i == 1 or i == 2:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		elif i == 3:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			l.custom_minimum_size.x = int(200 * _ui_scale)
		elif i == 4:
			l.custom_minimum_size.x = int(170 * _ui_scale)
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


## Decorative hull assignment — stable per callsign. Swap for real data when
## the API carries ship_type.
func _ship_type_for(pilot: String) -> String:
	var h := 0
	for i in pilot.length():
		h = (h * 31 + pilot.unicode_at(i)) % 1000003
	return SHIP_FRAMES[h % SHIP_FRAMES.size()]


## STATUS is derived from the entry's timestamp: anything logged in the last
## ACTIVE_WINDOW_SECONDS reads ACTIVE, older entries read DOCKED.
func _status_from(created_at: String) -> String:
	var s := created_at.strip_edges().trim_suffix("Z")
	if s.length() < 19:
		return "DOCKED"
	var t := Time.get_unix_time_from_datetime_string(s)
	if t <= 0:
		return "DOCKED"
	if Time.get_unix_time_from_system() - t < ACTIVE_WINDOW_SECONDS:
		return "ACTIVE"
	return "DOCKED"


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
	l.add_theme_font_size_override("font_size", maxi(int(size * _ui_scale), FONT_FLOOR))
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
	button.add_theme_font_size_override("font_size", maxi(int(20 * _ui_scale), FONT_FLOOR))
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
