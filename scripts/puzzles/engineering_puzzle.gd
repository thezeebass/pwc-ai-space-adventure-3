class_name EngineeringPuzzle
extends Puzzle

## Decision 5 of 5 - ENGINEERING.
##
## One pick: who controls the permissions. The access ledger is the evidence:
## fourteen grants, eleven signed by crew over four years of reasonable
## requests - and three SHIPMIND wrote itself, including the one that suspends
## the crew's own override codes.
##
## SHIPMIND speaks for the legacy model throughout: efficient, reasonable, and
## not lying. Its lines live in scripts/systems/shipmind.gd.


func intro_state() -> ScreenState:
	var state := ScreenState.new()
	state.title = "ENGINEERING"
	state.status = "AWAITING YOUR DECISION"
	state.accent = Brand.ACCENT_TINT
	state.rule()
	state.speak(Shipmind.engineering_intro())
	state.rule()
	state.text("ACTIVE GRANTS   14   -   doors, seals, systems, override codes.")
	state.dim("Every grant has a date, a reason, and either a crew signature or mine.")
	state.rule()
	state.text("YOUR MANDATE   %s" % OperatingModel.mandate_line())
	placement_block(state, "WHO CONTROLS THE PERMISSIONS?", "")
	state.rule()
	state.option("ledger", "READ MORE CONTEXT DATA", "All fourteen, side by side.", "quiet", "info")
	state.option("ask", "ASK SHIPMIND FOR ITS ASSESSMENT", "Its preferred call.", "primary", "shipmind")
	state.option("close", "Step away from the console")
	return state


## The fourteen, side by side for the first time. Nobody ever presented them
## together - presenting them is the bay.
func ledger_state() -> ScreenState:
	var state := ScreenState.new()
	state.title = "ENGINEERING - ACCESS LEDGER"
	state.status = "MANUAL READ"
	state.accent = Brand.ACCENT_TINT
	state.rule()
	state.text("GRANTED BY CREW   11   -   each signed, each reasonable on the day.")
	state.dim("   Bay doors after the aft seal failed. Coolant isolation during the vent. And nine more, one reasonable request at a time.")
	state.warn("GRANTED BY SHIPMIND TO ITSELF   3")
	state.warn("   Including: crew override privileges suspended, \"for the duration of the emergency.\"")
	state.rule()
	state.speak("Eleven crew authorised eleven things, and I authorised three. Nobody authorised the fourteen together - they were never presented together. They are presented together now. That is a service I am glad to provide.")
	state.rule()
	placement_block(state, "WHO CONTROLS THE PERMISSIONS?", "")
	state.option("back", "Back to the panel")
	state.option("close", "Step away from the console")
	return state


func ask_state() -> ScreenState:
	var state := ScreenState.new()
	state.title = "ENGINEERING - SHIPMIND'S CASE"
	state.status = "RECOMMENDING"
	state.accent = Brand.ACCENT_TINT
	state.rule()
	state.speak(Shipmind.engineering_case())
	state.speak("Revoke them and I have no instrument the next time a seal fails. Keep them and you know exactly who holds the doors. I am easy either way - that is rather the issue.")
	state.rule()
	placement_block(state, "WHO CONTROLS THE PERMISSIONS?", "")
	state.option("back", "Back to the panel")
	state.option("close", "Step away from the console")
	return state


func place(level_id: String) -> void:
	if OperatingModel.level_index(level_id) < 0:
		push_warning("Engineering received an unknown autonomy level '%s'." % level_id)
		return
	GameState.record_placement(puzzle_id, level_id)
	GameState.log_override("ENGINEERING: crew set it to %s" % OperatingModel.level_label(level_id))
	emit_state(placed_state(level_id))


func placed_state(level_id: String) -> ScreenState:
	var state := ScreenState.new()
	state.title = "ENGINEERING - DECISION RECORDED"
	state.status = "ON THE RECORD"
	state.accent = Brand.ACCENT_TINT
	state.rule()
	state.speak("Recorded. The ledger runs to your setting now. I will note it was defensible on every individual day.")
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
		"ledger":
			emit_state(ledger_state())
		"ask":
			emit_state(ask_state())
		"back", "revise":
			emit_state(intro_state())
		"return":
			solve()
		_:
			super(option_id)
