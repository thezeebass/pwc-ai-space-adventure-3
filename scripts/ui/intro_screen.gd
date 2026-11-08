class_name IntroScreen
extends CanvasLayer

## The story's front door: a full-screen telling of the situation, played
## before the launch card.
##
## The card's "WHY YOU'RE HERE" sheet answers the question in three lines.
## This screen tells the same three lines as a narrative - one beat at a
## time, each carried by a production still in the ship's retro television
## look. The picture claims two thirds of the screen and meets the words
## through a leaning seam, dressed with parallel diagonal lines that turn
## into straight edge lines through rounded corners: the same vocabulary as
## the ship's warm-yellow console styling, drawn in gold on near-black.
##
## THE PICTURES THEMSELVES NEVER MOVE. The three stills sit side by side on a
## strip three screens wide, and stepping a beat slides the strip right to left -
## the next picture arrives from the right edge and the previous one leaves on
## the left, the way a sequence is meant to read. That slide is the only motion:
## no zoom, no drift and no shake, so each frame stays exactly as composed.
##
## The crossfade that used to be here was the source of the jitter: it swapped
## two textures with opposite alpha tweens while a third scale tween was being
## killed and restarted on the incoming node, so a still could be seen snapping
## back a few pixels mid-fade. One strip, one slide, and no tween on a picture
## itself - nothing here restarts a tween that is already running.
##
## Clicking anywhere, the button, or ENTER steps through the beats; ESC skips
## the whole telling. When the last beat is read the screen hands back to the
## mandate card that has waited underneath it the entire time.

signal finished

const PAPAYA := Color(0.863, 0.369, 0.153)
const TANGERINE := Color(0.816, 0.251, 0.149)
const GOLD := Color(0.941, 0.722, 0.224)
const WHITE := Color(1.0, 1.0, 1.0)
const BODY := Color(0.93, 0.89, 0.85)
const MUTED := Color(0.72, 0.66, 0.62)
const GROUND := Color(0.06, 0.032, 0.022)
const PANEL := Color(0.09, 0.055, 0.04)

## The picture field claims the top of the screen and leans as it descends:
## a diagonal seam, not a vertical split. The seam leans left as it falls,
## so the words' ground widens toward the top, where the ornament lanes live.
const SEAM_TOP := 0.60
const SEAM_BOTTOM := 0.65
## The words sit clear of the seam's widest reach.
const WORDS_LEFT := 0.675

## Held the other way up the seam turns on its side: the picture claims the
## top two thirds, the words the bottom third, and the whole screen reads on
## thirds, the way a poster is meant to be read.
const WORDS_TOP_PORTRAIT := 0.62

const IMAGE_PATHS := [
	"res://assets/ui/intro/intro_crew.png",
	"res://assets/ui/intro/intro_transit.png",
	"res://assets/ui/intro/intro_bridge.png",
]

## The pan between two stills. A whole screen of travel needs time to read as a
## move rather than a cut.
const PAN_SECONDS := 1.15

## The briefing, one beat per still - the same three lines the launch card's
## situation sheet carries.
const BEATS := [
	"You are aboard the survey ship Adamant Verity, mid-refit to the "
		+ "Intelligent Operating Model.",
	"The ship's AI - SHIPMIND - has flown her for years, on defaults it is "
		+ "completely sure of. The refit upgraded it. Until each function is "
		+ "recalibrated, the defaults keep running.",
	"Go room to room and recalibrate each function at its console - automated, "
		+ "review, sign-off, or human-only. When all five are set, the cockpit "
		+ "opens.",
]

var _root: Control = null
## The frame the strip is seen through, and the strip itself: one slot per still,
## each slot clipping its own still so a strip wider than the screen never shows
## its neighbour through the one on view.
var _frame: Control = null
var _strip: Control = null
var _slots: Array[Control] = []
var _stills: Array[TextureRect] = []
var _decor: Control = null
var _catcher: Button = null
var _panel: Control = null
var _words_fit: Control = null
var _words_margin: MarginContainer = null
var _beat_label: Label = null
var _counter: Label = null
var _dashes: Array[ColorRect] = []
var _button: Button = null

var _textures: Array[Texture2D] = []
var _beat: int = 0
var _done: bool = false
var _pan_tween: Tween = null
var _text_tween: Tween = null


func _ready() -> void:
	layer = 130
	_load_textures()
	_build()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_open()
	_relayout_layout()
	## The strip is sized from the frame's real width, which is not resolved
	## until the first layout pass - so it is measured once more after it is.
	_size_strip.call_deferred()
	TextZoom.register(_root)


## Which way is the screen held? Portrait - taller than it is wide - stacks
## the picture over the words; landscape splits them left and right, the way
## the seam was drawn first.
func _is_portrait() -> bool:
	var view: Vector2 = get_viewport().get_visible_rect().size
	return view.y > view.x


func _relayout_layout() -> void:
	if _panel == null:
		return
	if _is_portrait():
		_panel.anchor_left = 0.0
		_panel.anchor_right = 1.0
		_panel.anchor_top = 0.0
		_panel.anchor_bottom = 1.0
	else:
		_panel.anchor_left = 0.0
		_panel.anchor_right = 1.0
		_panel.anchor_top = 0.0
		_panel.anchor_bottom = 1.0
	_fit_words.call_deferred()


## A safety net for narrow windows: the words column is laid out at its
## natural width and only scaled down when it genuinely cannot fit the panel.
## Without this the card's fixed-width button row pushed the whole column past
## the right edge of the screen on a landscape window.
func _fit_words() -> void:
	if _panel == null or _words_fit == null or _words_margin == null:
		return
	var panel: Vector2 = _panel.size
	if panel.x < 2.0 or panel.y < 2.0:
		return
	_words_fit.scale = Vector2.ONE
	_words_fit.position = (panel - Vector2(minf(panel.x, 820.0), panel.y)) * 0.5
	_words_fit.size = Vector2(minf(panel.x, 820.0), panel.y)
	var needed: Vector2 = _words_margin.get_combined_minimum_size()
	if needed.x < 1.0 or needed.y < 1.0:
		return
	var fit: float = minf(1.0, minf(panel.x / needed.x, panel.y / needed.y))
	_words_fit.scale = Vector2(fit, fit)
	_words_fit.position = (panel - _words_fit.size * fit) * 0.5


func _process(_delta: float) -> void:
	# The cursor is the only way to step through the telling, so the open
	# screen enforces its own visibility, the same way the launch card does.
	if is_open() and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if _done or not _root.visible:
		return
	if event.is_action_pressed("ui_accept"):
		_advance()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_finish()
		get_viewport().set_input_as_handled()


# --- The beats ------------------------------------------------------------------

func _advance() -> void:
	if _done:
		return
	if _beat >= BEATS.size() - 1:
		## Every beat has now been on the screen: the telling is earned, and
		## later tellings may be skipped.
		GameState.intro_seen_once = true
		GameState.save()
		_finish()
		return
	_show_beat(_beat + 1)


## The telling finishes by being read through - or, once the crew have seen
## all three beats at least once, by skipping. A first telling cannot skip:
## the flag is exactly what the crew have just earned by reaching this line.
func _finish() -> void:
	if _done or not GameState.intro_seen_once:
		return
	_done = true
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, 0.35)
	tween.tween_callback(_close)


## True while the telling owns the screen: the station controller asks before it
## treats a back gesture as "leave the menu".
func is_open() -> bool:
	return visible and not _done and _root != null and _root.visible


## The way past the telling without reading it - the ESC key, and the back
## gesture on a phone or in a browser, both land here.
func skip() -> void:
	_finish()


func _close() -> void:
	_root.visible = false
	finished.emit()


func _show_beat(index: int, first: bool = false) -> void:
	_beat = index
	_button.text = "TO THE SHIP" if index == BEATS.size() - 1 else "CONTINUE"
	_refresh_progress(index)
	_pan_to(index, first)
	if first or _text_tween == null:
		_beat_label.text = String(BEATS[index])
		_beat_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	else:
		_text_tween.kill()
		_text_tween = create_tween()
		_text_tween.tween_property(_beat_label, "modulate:a", 0.0, 0.18)
		_text_tween.tween_callback(func() -> void:
			_beat_label.text = String(BEATS[index]))
		_text_tween.tween_property(_beat_label, "modulate:a", 1.0, 0.25)
		_text_tween.tween_callback(_fit_words)
	## The words have changed size: a longer beat wraps onto another line, so the
	## fit is measured again after every step. Without this the column was only
	## ever fitted for the first beat, and on a phone - where the type is a tier
	## larger - the later beats ran out of the panel and over the picture.
	_fit_words.call_deferred()


func _refresh_progress(index: int) -> void:
	_counter.text = "%02d / %02d" % [index + 1, BEATS.size()]
	for i in _dashes.size():
		var dash: ColorRect = _dashes[i]
		if i < index:
			dash.color = PAPAYA
		elif i == index:
			dash.color = GOLD
		else:
			dash.color = Color(0.35, 0.26, 0.20)


## The one move the pictures make. Stepping a beat slides the strip right to left
## by exactly one frame, so the move is the strip travelling rather than a
## picture jumping.
func _pan_to(index: int, first: bool) -> void:
	if _strip == null or _frame == null:
		return
	var screen: float = _frame.size.x
	if screen < 2.0:
		screen = get_viewport().get_visible_rect().size.x
	var target: float = -float(index) * screen
	if _pan_tween != null:
		_pan_tween.kill()
		_pan_tween = null
	if first:
		_strip.position.x = target
	else:
		_pan_tween = create_tween()
		_pan_tween.tween_property(_strip, "position:x", target, PAN_SECONDS) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# --- Open / close ---------------------------------------------------------------

func _open() -> void:
	InputRouter.set_ui_blocking(true)
	_root.modulate = Color(1.0, 1.0, 1.0, 0.0)
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.7)
	_show_beat(0, true)
	_relayout()


## Replays the telling for a crew who wants the story again from the mandate
## card. Resets the beats and plays them over from the first still.
func replay() -> void:
	_done = false
	_beat = 0
	visible = true
	InputRouter.set_ui_blocking(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root.visible = true
	_root.modulate = Color(1.0, 1.0, 1.0, 0.0)
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.5)
	_show_beat(0, true)
	_relayout()


func _on_viewport_resized() -> void:
	_relayout_layout()
	_relayout()


func _relayout() -> void:
	if _decor != null:
		_decor.queue_redraw()
	_size_strip()


func _load_textures() -> void:
	for path in IMAGE_PATHS:
		var texture: Texture2D = load(path) as Texture2D
		if texture == null:
			push_warning("IntroScreen: missing artwork at %s - the telling runs without it." % path)
		_textures.append(texture)


# --- Build ----------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = GROUND
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(backdrop)

	_build_strip()

	var shade := ColorRect.new()
	shade.name = "ReadabilityShade"
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.03, 0.02, 0.015, 0.52)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)
	_decor = Control.new()
	_decor.name = "Decor"
	_decor.set_anchors_preset(Control.PRESET_FULL_RECT)
	_decor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_decor.draw.connect(_on_decor_draw)
	_root.add_child(_decor)

	# Every click off the words steps the telling forward.
	_catcher = Button.new()
	_catcher.name = "Advance"
	_catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	_catcher.flat = true
	_catcher.focus_mode = Control.FOCUS_NONE
	_catcher.pressed.connect(_advance)
	_root.add_child(_catcher)

	_build_words()


## The pictures as one strip: three slots on a track three screens wide, seen
## through one clipping frame. A slot clips its own still, so the strip can hold
## three screens of pictures without showing the neighbouring shot through it.
func _build_strip() -> void:
	_frame = Control.new()
	_frame.name = "Frame"
	## Anchored top-left and sized from the viewport in _size_strip(): a
	## full-rect frame is only as big as the layout has got to, and at _ready it
	## has not been laid out at all - which is how the strip first came out as
	## three narrow slices of the screen instead of one picture.
	_frame.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_frame.position = Vector2.ZERO
	_frame.clip_contents = true
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_frame)

	_strip = Control.new()
	_strip.name = "Strip"
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_strip)

	for i in _textures.size():
		var slot := Control.new()
		slot.name = "Still%d" % (i + 1)
		slot.clip_contents = true
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_strip.add_child(slot)
		var still := _image_rect("Image")
		if _textures[i] != null:
			still.texture = _textures[i]
		slot.add_child(still)
		_slots.append(slot)
		_stills.append(still)


## Lays the strip out for the current frame size and parks it on the beat that
## is being read. Called on every resize, because a strip measured against the
## old width would leave the wrong still under the words.
func _size_strip() -> void:
	if _frame == null or _strip == null:
		return
	var screen: Vector2 = get_viewport().get_visible_rect().size
	if screen.x < 2.0 or screen.y < 2.0:
		return
	_frame.position = Vector2.ZERO
	_frame.size = screen
	_strip.size = Vector2(screen.x * float(_slots.size()), screen.y)
	# A running pan owns the strip's position. Re-parking it here would snap it
	# to the destination and make the picture twitch mid-move.
	if _pan_tween == null or not _pan_tween.is_running():
		_strip.position = Vector2(-float(_beat) * screen.x, 0.0)
	for i in _slots.size():
		var slot: Control = _slots[i]
		slot.position = Vector2(float(i) * screen.x, 0.0)
		slot.size = screen
		_stills[i].scale = Vector2.ONE


func _image_rect(rect_name: String) -> TextureRect:
	var rect := TextureRect.new()
	rect.name = rect_name
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _build_words() -> void:
	_panel = Control.new()
	_panel.name = "Words"
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_panel)

	_words_fit = Control.new()
	_words_fit.name = "Fit"
	_words_fit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_words_fit.clip_contents = true
	_panel.add_child(_words_fit)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var side_margin: int = 28 if _is_portrait() else 40
	var top_margin: int = 18 if _is_portrait() else 24
	margin.add_theme_constant_override("margin_left", side_margin)
	margin.add_theme_constant_override("margin_right", side_margin)
	margin.add_theme_constant_override("margin_top", top_margin)
	margin.add_theme_constant_override("margin_bottom", top_margin)
	_words_margin = margin
	_words_fit.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var kicker := Label.new()
	kicker.name = "Kicker"
	kicker.text = "THE SITUATION"
	## The title's size is the floor for every label on this screen: the
	## briefing must read at arm's length, so nothing drops below it. The
	## kicker keeps heading weight through its papaya colour instead.
	kicker.add_theme_font_size_override("font_size", _text_size(30))
	kicker.add_theme_color_override("font_color", PAPAYA)
	## The words are centred on their ground rather than ranged left against the
	## seam: the ground is a third of a landscape screen, and a left-ranged
	## column in it reads as a block shoved into the corner.
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(kicker)

	var title := Label.new()
	title.name = "Title"
	title.text = "WHY YOU'RE HERE"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", _text_size(30))
	## The title defines the screen's text floor, so it cannot grow for
	## weight - a dark outline reads as the bold the mono face has none of.
	title.add_theme_constant_override("outline_size", 3)
	title.add_theme_color_override("font_outline_color", Color(0.06, 0.032, 0.022, 0.85))
	title.add_theme_color_override("font_color", WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.color = GOLD
	rule.custom_minimum_size = Vector2(64.0, 2.0)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(rule)

	column.add_child(_gap(16))

	_beat_label = Label.new()
	_beat_label.name = "Beat"
	_beat_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_beat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_beat_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_beat_label.custom_minimum_size = Vector2(0.0, 140.0 if Platform.touch_ui() else 200.0)
	_beat_label.add_theme_font_size_override("font_size", _text_size(30))
	_beat_label.add_theme_constant_override("line_spacing", 8)
	_beat_label.add_theme_color_override("font_color", BODY)
	_beat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_beat_label)

	column.add_child(_gap(10))

	var progress := HBoxContainer.new()
	progress.name = "Progress"
	progress.add_theme_constant_override("separation", 10)
	progress.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(progress)
	for i in BEATS.size():
		var dash := ColorRect.new()
		dash.name = "Dash%d" % i
		dash.custom_minimum_size = Vector2(44.0, 4.0)
		dash.pivot_offset = Vector2(22.0, 2.0)
		dash.rotation = -0.42
		progress.add_child(dash)
		_dashes.append(dash)
	_counter = Label.new()
	_counter.name = "Counter"
	_counter.add_theme_font_size_override("font_size", _text_size(30))
	_counter.add_theme_color_override("font_color", MUTED)
	_counter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress.add_child(_counter)

	column.add_child(_gap(22))

	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation", 18)
	column.add_child(actions)
	_button = Button.new()
	_button.name = "Continue"
	_button.text = "CONTINUE"
	# Flexible width: the words panel is only a slice of a landscape screen, so
	# a fixed 220px button plus the skip button used to overrun its right edge.
	_button.custom_minimum_size = Vector2(0.0, _button_height())
	_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button.add_theme_font_size_override("font_size", _text_size(30))
	_button.add_theme_color_override("font_color", Color(0.10, 0.06, 0.04))
	_button.add_theme_color_override("font_hover_color", Color(0.10, 0.06, 0.04))
	_button.add_theme_color_override("font_pressed_color", Color(0.10, 0.06, 0.04))
	var fill := StyleBoxFlat.new()
	fill.bg_color = GOLD
	fill.border_color = TANGERINE
	fill.set_border_width_all(2)
	fill.set_corner_radius_all(3)
	_button.add_theme_stylebox_override("normal", fill)
	var hover: StyleBoxFlat = fill.duplicate()
	hover.bg_color = Color(1.0, 0.82, 0.36)
	_button.add_theme_stylebox_override("hover", hover)
	_button.add_theme_stylebox_override("focus", hover)
	_button.pressed.connect(_advance)
	actions.add_child(_button)

	var skip_button := Button.new()
	skip_button.name = "Skip"
	skip_button.text = "SKIP"
	skip_button.focus_mode = Control.FOCUS_NONE
	skip_button.custom_minimum_size = Vector2(0.0, _button_height())
	skip_button.add_theme_font_size_override("font_size", _text_size(30))
	skip_button.add_theme_color_override("font_color", MUTED)
	skip_button.add_theme_color_override("font_hover_color", GOLD)
	skip_button.add_theme_color_override("font_pressed_color", GOLD)
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0, 0, 0, 0)
	flat.set_border_width_all(0)
	flat.content_margin_left = 6.0
	flat.content_margin_right = 6.0
	skip_button.add_theme_stylebox_override("normal", flat)
	skip_button.add_theme_stylebox_override("hover", flat)
	skip_button.add_theme_stylebox_override("pressed", flat)
	skip_button.add_theme_stylebox_override("focus", flat)
	skip_button.pressed.connect(_finish)
	## The skip is earned: until the crew have read all three beats once, the
	## button stays off the screen and ESC answers nothing.
	skip_button.visible = GameState.intro_seen_once
	actions.add_child(skip_button)

	column.add_child(_gap(10))


func _gap(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


## A touch floor on text and buttons: on a phone held at arm's length, a label
## at monitor size is a squint. Text steps up a tier on touch; buttons sit at
## the fingertip's comfortable target. Both scale back down on a desktop. The
## multiplier itself lives in Platform, so every overlay steps up together.
func _text_size(base: int) -> int:
	return max(int(round(float(base) * Platform.ui_scale())), Brand.SIZE_SMALL)


func _button_height() -> float:
	## The button row carries 30px type now, so the boxes grew with it:
	## a 48px-high button could not hold the label without clipping it.
	return Platform.touch_target(56.0) + (8.0 if Platform.touch_ui() else 0.0)


# --- The drawn frame ------------------------------------------------------------

## The seam and its ornament are drawn, not composed from rects, so the
## diagonals stay exact at any window size.
func _on_decor_draw() -> void:
	var view: Vector2 = _decor.size
	if view.x < 2.0 or view.y < 2.0:
		return
	var seam_top := Vector2(view.x * SEAM_TOP, 0.0)
	var seam_bot := Vector2(view.x * SEAM_BOTTOM, view.y)
	var dir := (seam_bot - seam_top).normalized()
	var side := dir.orthogonal()
	if side.x < 0.0:
		side = -side

	# The words' ground: everything right of the seam.
	_decor.draw_colored_polygon(
		PackedVector2Array([seam_top, Vector2(view.x, 0.0), Vector2(view.x, view.y), seam_bot]),
		Color(PANEL, 0.0))

	# Quiet lanes hugging the seam, fading out before the ornaments take over.
	var accents := [
		{"off": 16.0, "color": GOLD, "width": 2.0},
		{"off": 34.0, "color": PAPAYA, "width": 2.0},
		{"off": 56.0, "color": Color(0.45, 0.34, 0.26), "width": 1.5},
	]
	var fade := view.y * 0.24
	for accent in accents:
		var off: float = accent["off"]
		var a: Color = accent["color"]
		var w: float = accent["width"]
		var top := seam_top + side * off + dir * (fade / dir.y)
		var bottom := seam_bot + side * off - dir * (fade / dir.y)
		_decor.draw_line(top, bottom, Color(a, 0.0), w)

	# The signature: three parallel diagonals rising with the seam, each
	# turning into a straight line along the top edge through a rounded
	# corner - and the mirrored descent that exits toward the bottom of the
	# frame. The lanes stay inside the wedge between seam and words, and both
	# groups stop short of the middle, where the briefing text lives.
	var lanes: Array[Dictionary] = []
	var rise := -dir
	for k in lanes.size():
		var lane: Dictionary = lanes[k]
		var radius := 26.0

		# Rising: the lane starts mid-frame, climbs, and bends right at the
		# top edge of the wedge.
		var base_top: Vector2 = seam_bot + side * float(lane["off"])
		var corner_top: Vector2 = base_top + rise * ((84.0 + 34.0 * k - base_top.y) / rise.y)
		var run_top := minf((0.40 * view.y - corner_top.y) / absf(rise.y),
			0.42 * view.y)
		if run_top > radius + 16.0:
			_decor.draw_polyline(
				_bent_line(corner_top, rise, Vector2.RIGHT, radius,
					run_top, view.x - corner_top.x),
				lane["color"], lane["width"])

		# Descending: the lane starts mid-frame, falls, and bends left with a
		# short tail that stops just short of the seam.
		var base_bot: Vector2 = seam_top + side * float(lane["off"])
		var corner_bot: Vector2 = base_bot + dir * ((view.y - 84.0 - 34.0 * k - base_bot.y) / dir.y)
		var run_bot := minf((corner_bot.y - 0.60 * view.y) / absf(dir.y),
			0.42 * view.y)
		if run_bot > radius + 16.0:
			var seam_x_at_corner: float = lerpf(seam_top.x, seam_bot.x,
				corner_bot.y / view.y)
			_decor.draw_polyline(
				_bent_line(corner_bot, dir, Vector2.LEFT, radius,
					run_bot, corner_bot.x - seam_x_at_corner - 26.0),
				lane["color"], lane["width"])

	# Film-gate corners on the picture side: quiet gold marks that say
	# "this is the frame the story is told in".
	var gate := Color(GOLD, 0.75)
	_decor.draw_polyline(
		_bent_line(Vector2(18.0, 18.0), Vector2.LEFT, Vector2.DOWN, 12.0, 44.0, 44.0),
		gate, 2.0)
	_decor.draw_polyline(
		_bent_line(Vector2(18.0, view.y - 18.0), Vector2.LEFT, Vector2.UP, 12.0, 44.0, 44.0),
		gate, 2.0)


## A straight run that turns a corner through a rounded fillet. The line
## travels in along d_in, rounds the corner, and leaves along d_out - the
## motif of the ship's consoles, redrawn in two dimensions.
func _bent_line(corner: Vector2, d_in: Vector2, d_out: Vector2, radius: float,
		tail_in: float, tail_out: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var turn := absf((-d_in).angle_to(d_out))
	if turn < 0.05 or turn > PI - 0.05:
		# Nearly a straight line: nothing to round.
		points.append(corner - d_in * tail_in)
		points.append(corner + d_out * tail_out)
		return points
	var reach := radius / tan(turn * 0.5)
	# The fillet's centre sits radius away from both lines, inside the turn.
	var n_in := d_in.orthogonal()
	if n_in.dot(d_out) < 0.0:
		n_in = -n_in
	var n_out := d_out.orthogonal()
	if n_out.dot(d_in) > 0.0:
		n_out = -n_out
	var along := radius * (1.0 - n_in.dot(n_out)) / n_in.dot(d_out)
	var centre := corner + n_out * radius + d_out * along
	var t_in := corner - d_in * reach
	var t_out := corner + d_out * reach
	points.append(corner - d_in * maxf(tail_in, reach + 6.0))
	points.append(t_in)
	var sweep := wrapf((t_out - centre).angle() - (t_in - centre).angle(), -PI, PI)
	for i in 9:
		var angle := (t_in - centre).angle() + sweep * (float(i) / 9.0)
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	points.append(t_out)
	points.append(corner + d_out * tail_out)
	return points
