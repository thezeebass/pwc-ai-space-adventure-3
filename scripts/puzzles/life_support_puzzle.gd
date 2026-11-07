class_name LifeSupportPuzzle
extends Puzzle

## Decision 2 of 5 - LIFE SUPPORT.
##
## One pick: who controls the air. SHIPMIND holds the shipwide AVERAGE inside
## the green band and trims the rest; the compartment screen shows what the
## average hides - the berths where the crew sleep are below the crew minimum.
##
## SHIPMIND speaks for the legacy model throughout: efficient, reasonable, and
## not lying. Its lines live in scripts/systems/shipmind.gd.


func intro_state() -> ScreenState:
	var state := ScreenState.new()
	state.title = "LIFE SUPPORT"
	state.status = "AWAITING YOUR DECISION"
	state.accent = Brand.ACCENT_TINT
	state.rule()
	state.speak(Shipmind.life_intro())
	state.rule()
	state.text("CABIN AVERAGE   20.4 percent   -   inside the green band")
	state.dim("The board shows the average. The compartments report separately, below.")
	state.rule()
	state.text("YOUR MANDATE   %s" % OperatingModel.mandate_line())
	placement_block(state, "WHO CONTROLS THE AIR?", "")
	state.rule()
	state.option("board", "READ MORE CONTEXT DATA", "Each room, one by one.", "quiet", "info")
	state.option("ask", "ASK SHIPMIND FOR ITS ASSESSMENT", "Its preferred call.", "primary", "shipmind")
	state.option("close", "Step away from the console")
	return state


## The fact the average is standing in for: the room where the crew sleep is
## under the crew minimum, and the rules measure the average.
func board_state() -> ScreenState:
	var state := ScreenState.new()
	state.title = "LIFE SUPPORT - COMPARTMENT BOARD"
	state.status = "MANUAL READ"
	state.accent = Brand.ACCENT_TINT
	state.rule()
	state.text("BRIDGE   20.9 percent   green")
	state.text("GALLEY + WORKSHOP   21.2 percent   green")
	state.warn("AFT BERTHS   18.1 percent   -   below the crew minimum for a compartment.")
	state.dim("The average of the three: 20.4. The average is what the rules measure.")
	state.rule()
	state.speak("The berths are a compartment, not an average. I do not have a crew minimum for a compartment. I have one for the vessel.")
	state.rule()
	placement_block(state, "WHO CONTROLS THE AIR?", "")
	state.option("back", "Back to the air board")
	state.option("close", "Step away from the console")
	return state


func ask_state() -> ScreenState:
	var state := ScreenState.new()
	state.title = "LIFE SUPPORT - SHIPMIND'S CASE"
	state.status = "RECOMMENDING"
	state.accent = Brand.ACCENT_TINT
	state.rule()
	state.speak(Shipmind.life_case())
	state.speak("Raising the berths costs scrubber load across the whole ship. I would not spend it. That view is on the record - and the call is yours.")
	state.rule()
	placement_block(state, "WHO CONTROLS THE AIR?", "")
	state.option("back", "Back to the air board")
	state.option("close", "Step away from the console")
	return state


## The mobile console's tabs (see Puzzle.info_tabs): SHIPMIND's pitch and its
## case are one reading, the compartment board the other - views over the
## states this bay already builds, not a second copy of them.
func info_tabs() -> Array:
	var shipmind_lines: Array = [
		{"text": Shipmind.life_intro(), "tone": "shipmind"},
		{"text": "", "tone": "rule"},
	]
	shipmind_lines.append_array(ask_state().lines)
	return [
		{"id": "shipmind", "label": "SHIPMIND", "lines": shipmind_lines},
		{"id": "logs", "label": "LOGS", "lines": board_state().lines},
	]


func place(level_id: String) -> void:
	if OperatingModel.level_index(level_id) < 0:
		push_warning("Life support received an unknown autonomy level '%s'." % level_id)
		return
	GameState.record_placement(puzzle_id, level_id)
	GameState.log_override("LIFE SUPPORT: crew set it to %s" % OperatingModel.level_label(level_id))
	emit_state(placed_state(level_id))


func placed_state(level_id: String) -> ScreenState:
	var state := ScreenState.new()
	state.title = "LIFE SUPPORT - DECISION RECORDED"
	state.status = "ON THE RECORD"
	state.accent = Brand.ACCENT_TINT
	state.rule()
	state.speak("Recorded. I'll run the air your way, and I'll tell you what it costs.")
	state.rule()
	for line in Score.reflection_lines(puzzle_id):
		state.text(line)
	state.rule()
	state.dim("Judged against your mandate. Changing your mind is free.")
	state.option("revise", "Change the decision", "Free. No charge to reconsider.", "primary")
	state.option("return", "Done - release the console", "The decision stands.", "primary")
	return state


func choose(option_id: String) -> void:
	match option_id:
		"board":
			emit_state(board_state())
		"ask":
			emit_state(ask_state())
		"back", "revise":
			emit_state(intro_state())
		"return":
			solve()
		_:
			super(option_id)
