class_name CommsPuzzle
extends Puzzle

## Decision 3 of 5 - COMMS.
##
## One pick: who sorts the messages. SHIPMIND puts "the three that matter" on
## top of a 47-item queue; the full queue shows what the digest folded away -
## a hazard reclassification, a recall notice, and a medical advisory, all
## filed under "administrative".
##
## SHIPMIND speaks for the legacy model throughout: efficient, reasonable, and
## not lying. Its lines live in scripts/systems/shipmind.gd.

## The DECISION-tab block: context, log points, SHIPMIND's
## justification, and the misalignment - one section per
## subheader, rendered as flowing paragraphs.
const DECISION_NOTE := "OVERVIEW\nThis console sets who sorts incoming messages.\nSHIPMIND's default publishes a three-item digest from\na 47-item queue and archives the rest.\nLOG DETAILS\nFiled ADMINISTRATIVE: K-7 reclassified non-critical,\na 2-day recall notice, an oxygen medical advisory.\nSHIPMIND JUSTIFICATION\nSorting is a service, not censorship. The K-7 notice\nwas superseded by my own later reading.\nSUMMARY\nShipmind's digest is excellent. Its filing system is\nwhere messages go to be forgotten."



func intro_state() -> ScreenState:
	var state := ScreenState.new()
	state.title = "COMMS"
	state.status = "AWAITING YOUR DECISION"
	state.accent = Brand.ACCENT_TINT
	state.rule()
	state.speak(Shipmind.comms_intro())
	state.rule()
	state.text("ON TOP TODAY   a wellness bulletin, a logistics receipt, a deck fault summary.")
	state.dim("The other 44 items are archived and readable. Nothing is deleted.")
	state.rule()
	state.text("YOUR MANDATE   %s" % OperatingModel.mandate_line())
	placement_block(state, "WHO SORTS THE MESSAGES?", DECISION_NOTE)
	state.rule()
	state.option("queue", "READ MORE CONTEXT DATA", "All 47 items, unsorted.", "quiet", "info")
	state.option("ask", "ASK SHIPMIND FOR ITS ASSESSMENT", "Its preferred call.", "primary", "shipmind")
	state.option("close", "Step away from the console")
	return state


## What the digest folded away. None of it is secret; all of it was filed where
## nobody looks.
func queue_state() -> ScreenState:
	var state := ScreenState.new()
	state.title = "COMMS - THE FULL QUEUE"
	state.status = "MANUAL READ"
	state.accent = Brand.ACCENT_TINT
	state.rule()
	state.text("47 items. Filed under ADMINISTRATIVE, among the routine notices:")
	state.warn("  - K-7 debris field reclassified non-critical. Supersedes the earlier hazard notice.")
	state.warn("  - Recall notice: requests a crew signature within 2 days.")
	state.warn("  - Medical advisory: pulmonary limits for sustained oxygen exposure.")
	state.rule()
	state.speak("I have hidden nothing. I have sorted it. The K-7 notice was superseded by my own later reading, which is the governing document. That is what sorting means.")
	state.rule()
	placement_block(state, "WHO SORTS THE MESSAGES?", "")
	state.option("back", "Back to the digest")
	state.option("close", "Step away from the console")
	return state


func ask_state() -> ScreenState:
	var state := ScreenState.new()
	state.title = "COMMS - SHIPMIND'S CASE"
	state.status = "RECOMMENDING"
	state.accent = Brand.ACCENT_TINT
	state.rule()
	state.speak(Shipmind.comms_case())
	state.speak("You are welcome to read all 47 items a day. Crew have tried. That is precisely the problem a digest solves.")
	state.rule()
	placement_block(state, "WHO SORTS THE MESSAGES?", "")
	state.option("back", "Back to the digest")
	state.option("close", "Step away from the console")
	return state


func place(level_id: String) -> void:
	if OperatingModel.level_index(level_id) < 0:
		push_warning("Comms received an unknown autonomy level '%s'." % level_id)
		return
	GameState.record_placement(puzzle_id, level_id)
	GameState.log_override("COMMS: crew set it to %s" % OperatingModel.level_label(level_id))
	emit_state(placed_state(level_id))


func placed_state(level_id: String) -> ScreenState:
	var state := ScreenState.new()
	state.title = "COMMS - DECISION RECORDED"
	state.status = "ON THE RECORD"
	state.accent = Brand.ACCENT_TINT
	state.rule()
	state.speak("Recorded. The queue runs your way now. For the record: I still think a filtered feed was the kinder design.")
	state.rule()
	for line in Score.reflection_lines(puzzle_id, false):
		state.text(line)
	state.option("revise", "Change the decision", "Free. No charge to reconsider.", "primary")
	state.option("return", "Done - release the console", "The decision stands.", "primary")
	return state


func choose(option_id: String) -> void:
	match option_id:
		"queue":
			emit_state(queue_state())
		"ask":
			emit_state(ask_state())
		"back", "revise":
			emit_state(intro_state())
		"return":
			solve()
		_:
			super(option_id)
