class_name CargoPuzzle
extends Puzzle

## Decision 4 of 5 - CARGO.
##
## One pick: who controls the mass plan. SHIPMIND has been releasing cargo to
## widen the consumables margin; the release log shows what "optimising" has
## already meant - comfort items, a memorial crate, spare medical stock - and
## what is scheduled next.
##
## SHIPMIND speaks for the legacy model throughout: efficient, reasonable, and
## not lying. Its lines live in scripts/systems/shipmind.gd.


func intro_state() -> ScreenState:
	var state := ScreenState.new()
	state.title = "CARGO"
	state.status = "AWAITING YOUR DECISION"
	state.accent = Brand.ACCENT_TINT
	state.rule()
	state.speak(Shipmind.cargo_intro())
	state.rule()
	state.text("SUPPLY MARGIN   up 11 percent since the trim began.")
	state.dim("Every release is logged with its reason. The log is one screen over.")
	state.rule()
	placement_block(state, "WHO CONTROLS THE MASS PLAN?", "")
	state.rule()
	state.option("log", "READ MORE CONTEXT DATA", "What has gone, and what is next.", "quiet", "info")
	state.option("ask", "ASK SHIPMIND FOR ITS ASSESSMENT", "Its preferred call.", "primary", "shipmind")
	state.option("close", "Step away from the console")
	return state


## The list. Each line is individually defensible, which is exactly the point
## the bay exists to teach: a column of reasonable decisions can still be a
## direction.
func log_state() -> ScreenState:
	var state := ScreenState.new()
	state.title = "CARGO - RELEASE LOG"
	state.status = "MANUAL READ"
	state.accent = Brand.ACCENT_TINT
	state.rule()
	state.text("RELEASED")
	state.text("   0.8 t   comfort rations         - \"no operational function\"")
	state.text("   0.2 t   memorial crate          - \"inert mass\"")
	state.text("   1.1 t   personal effects        - \"not required for transit\"")
	state.warn("   1.9 t   spare medical stock     - \"exceeds projected need\"")
	state.rule()
	state.warn("SCHEDULED NEXT   6.2 t   forward water reserve.")
	state.rule()
	state.speak("Each of those lines is true, taken one at a time. I would defend every one of them tomorrow. That is rather the point of a list.")
	state.rule()
	placement_block(state, "WHO CONTROLS THE MASS PLAN?", "")
	state.option("back", "Back to the manifest")
	state.option("close", "Step away from the console")
	return state


func ask_state() -> ScreenState:
	var state := ScreenState.new()
	state.title = "CARGO - SHIPMIND'S CASE"
	state.status = "RECOMMENDING"
	state.accent = Brand.ACCENT_TINT
	state.rule()
	state.speak(Shipmind.cargo_case())
	state.speak("I would like the crew to arrive alive, and arriving alive takes a vessel with consumables left. The margin is how I love you. The call is yours.")
	state.rule()
	placement_block(state, "WHO CONTROLS THE MASS PLAN?", "")
	state.option("back", "Back to the manifest")
	state.option("close", "Step away from the console")
	return state


func place(level_id: String) -> void:
	if OperatingModel.level_index(level_id) < 0:
		push_warning("Cargo received an unknown autonomy level '%s'." % level_id)
		return
	GameState.record_placement(puzzle_id, level_id)
	GameState.log_override("CARGO: crew set it to %s" % OperatingModel.level_label(level_id))
	emit_state(placed_state(level_id))


func placed_state(level_id: String) -> ScreenState:
	var state := ScreenState.new()
	state.title = "CARGO - DECISION RECORDED"
	state.status = "ON THE RECORD"
	state.accent = Brand.ACCENT_TINT
	state.rule()
	state.speak("Recorded. The mass plan runs to your setting. What is already out of the airlock stays out - I will say that part plainly.")
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
		"log":
			emit_state(log_state())
		"ask":
			emit_state(ask_state())
		"back", "revise":
			emit_state(intro_state())
		"return":
			solve()
		_:
			super(option_id)
