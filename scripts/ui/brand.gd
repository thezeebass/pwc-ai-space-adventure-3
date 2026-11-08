class_name Brand
extends RefCounted

## ONE PLACE FOR THE 2D BRAND LAYER.
##
## This milestone does not build the brand system: it only keeps every new or
## changed 2D component off the retired cyan accent and points them all at one
## source, so the PwC layer lands here in a single edit later - Orange 500 as
## the primary accent, the greys as neutrals, Georgia for headlines, body and
## SHIPMIND's voice, Arial Bold for labels and Arial for data.
##
## Rules the values already follow: orange is for key data and the primary
## action only, never a full-orange screen and never body text; the greys are
## surfaces and secondary text; nothing here is cool.
##
## The 3D station is NOT covered by this file. It keeps its own ember palette.

## Orange 500 - the future primary accent.
const ACCENT := Color(0.992157, 0.317647, 0.031373)
## #FE7C39 - the accent's lighter tint, for a selected state rather than a call
## to action.
const ACCENT_TINT := Color(0.996078, 0.486275, 0.223529)
## The dark surface a panel sits on. Near-black, warm-neutral, never pure black.
const SURFACE := Color(0.078431, 0.078431, 0.086275)
const SURFACE_RAISED := Color(0.129412, 0.133333, 0.145098)
## #F5F7F8 - primary text on a dark surface.
const INK := Color(0.960784, 0.968627, 0.972549)
## #DFE3E6 - dividers, quiet rules and secondary labels.
const NEUTRAL_LIGHT := Color(0.874510, 0.890196, 0.901961)
## #A1A8B3 - the quiet tone: a note that is not a warning.
const NEUTRAL := Color(0.631373, 0.658824, 0.701961)

## The type scale, in pixels. Sizes only for now: the families (Georgia for
## headlines, body and SHIPMIND's voice, Arial Bold for sub-heads and labels,
## Arial for data) belong to the brand layer and land here with it.
##
## THE FLOOR RULE: nothing in the game may render smaller than the intro
## screen's title - the smallest comfortable reading size on a phone held at
## arm's length. Body, data, labels and choices all sit at that floor; a
## screen's title sits a step above it so a title still reads as a title.
const SIZE_TITLE := 36
const SIZE_DATA := 30
const SIZE_LABEL := 30
const SIZE_SMALL := 30

## The terminal's readout body and the decision choices, at the floor. A
## decision screen prints a long readout and stacks eleven choices under it,
## so that screen now scrolls: legibility wins over density.
const SIZE_BODY := 30
## A choice button's own text, at the floor like every other touch label.
const SIZE_COMPACT := 30

## Screen-edge safe zone - the TV title-safe margin, or in graphic-design
## terms the minimum margin between UI chrome and the display's edge. A
## fraction of the shorter viewport edge, with an absolute floor so a phone
## in landscape (short edge ~360) still keeps honest distance from the bezel.
## Ask Brand.safe_inset() with the live viewport size; re-apply on resize.
const SAFE_ZONE_RATIO := 0.03
const SAFE_ZONE_FLOOR := 24.0


static func safe_inset(viewport_size: Vector2) -> float:
	return maxf(SAFE_ZONE_FLOOR, minf(viewport_size.x, viewport_size.y) * SAFE_ZONE_RATIO)

# --- The TUI voice ------------------------------------------------------------

## The ship's own machine text: the readout, the screen header and status, the
## footer and the read buttons. A different family from the brand voice is the
## whole point - the lore is what the ship prints, the decision control is what
## the crew touches, and the two should not look like each other.
##
## Share Tech Mono (Google Fonts, SIL OFL) is bundled with the project, so the
## web export carries it and no platform font is trusted. A monospace face also
## reads as terminal output at small sizes, which is what the readout is.
const FONT_TUI_PATH := "res://assets/fonts/ShareTechMono-Regular.ttf"
## The readout body, at the floor: legibility wins over the terminal's density.
const SIZE_TUI := 30
## Kickers, the footer and the status line, at the floor like everything else.
const SIZE_TUI_SMALL := 30
## The screen title, in the machine voice, a step above the body floor.
const SIZE_TUI_TITLE := 36

## The menu's TEXT SIZE control writes it; every info popup reads it. Defaults
## to the reading floor (L), and load_data() restores the saved choice.
static var info_text_size: int = 30

## The multiplier the UI text derives from that choice (L = 1.0, M = 0.933,
## S = 0.8). Anything that should follow the setting asks scaled() with the
## size it was designed at.
static func text_scale() -> float:
	return float(info_text_size) / 30.0


static func scaled(base: int) -> int:
	return maxi(int(round(base * text_scale())), 16)

## Console screens carry the most text in the game, so their type runs at a
## scale of its own - 10% under the floor for now. One constant retunes every
## console screen at once; raise or lower to taste.
const CONSOLE_TEXT_SCALE := 0.9

static func console_size(base: int) -> int:
	## The console screens keep their own -10% step (they carry the most
	## text), but that step rides on top of the menu's TEXT SIZE setting:
	## L keeps the approved 27px readouts, M and S take the consoles down
	## with everything else.
	return int(round(base * text_scale() * CONSOLE_TEXT_SCALE))

static var _tui_font: Font = null

## The bundled TUI face, loaded once. Returns null if the resource is missing
## (a fresh checkout before Godot has imported the TTF) - callers fall back to
## the default font rather than crashing the console.
static func tui_font() -> Font:
	if _tui_font == null:
		_tui_font = load(FONT_TUI_PATH)
	return _tui_font


## Puts the machine voice on a label in one call: the family and the size.
## font_size_override only lands when the font loaded, so a missing resource
## degrades to the default face at the label's own size.
## Buttons are labels with a mouse, and the <more> button reads in the machine
## voice too, so both are accepted.
static func apply_tui(control: Control, font_size: int) -> void:
	var font: Font = tui_font()
	if font != null:
		control.add_theme_font_override("font", font)
	control.add_theme_font_size_override("font_size", font_size)
