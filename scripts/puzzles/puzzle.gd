class_name Puzzle
extends Node

## Base class for one ship system's decision.
##
## A puzzle is a small state machine that describes screens. It never touches a
## Control node, never reads input, and never knows which platform is running -
## TerminalUI renders it and hands back option ids, and for a spectrum decision
## the level the player committed.
##
## THE CONTRACT - ONE PICK PER DECISION
##
##   start()        routes to the right screen: a placed decision opens for
##                  reconsideration, an unplaced bay shows its spectrum, and a
##                  decision opened before the mandate was declared is refused.
##   intro_state()  the bay's own opening screen. A migrated bay puts its
##                  spectrum block on it.
##   place()        the spectrum commit lands here with the level id - the one
##                  and only pick. The bay records ONE placement through
##                  GameState, and recording it again replaces it. Who runs the
##                  decision afterwards is derived from the level itself; the
##                  earlier model's guardrail and owner picks were cut because
##                  they asked more reading than the decision was worth.
##   choose()       every other option: asking SHIPMIND why, going back.
##                  NOTHING chosen this way scores.
##
## THERE IS NO PER-OPTION GRADING ANY MORE. A placement IS the decision, and
## Score reads it back against the mandate and the decision's own weight.
## See docs/adding-a-system.md for what a bay looks like.

signal state_changed(state: ScreenState)
signal solved(puzzle_id: String)

@export var puzzle_id: String = ""
@export var system_title: String = "SHIP SYSTEM"
## Legacy of the principle-card era, still declared because the deck scenes
## serialise it. Nothing reads it: a decision is named by its placement.
@export var principle_index: int = 0

var is_solved: bool = false


func _ready() -> void:
	# Registered here rather than in the station scene: game.gd wires the solved
	# signal by group, so a new bay gets persistence, the reflection card and the
	# objective refresh by construction (see docs/adding-a-system.md).
	add_to_group("puzzle")


func start() -> void:
	if is_solved or GameState.is_restored(puzzle_id) or GameState.has_placement(puzzle_id):
		# A placed decision reads back as a record instead of asking the crew to
		# decide it twice - including one placed and never released, which a
		# reload would otherwise offer the spectrum to all over again.
		## A decision bay may revise from the record, so its solve must be able
		## to run again after a re-commit. The helm is not a decision bay: it
		## stays solved so a second release cannot relaunch the ship.
		if is_decision_bay():
			is_solved = false
		state_changed.emit(done_state())
		return
	if not is_decision_bay():
		# The helm and the corridor kiosk are not scored decisions: the helm is
		# where the run ends and the kiosk is where it is read back.
		state_changed.emit(intro_state())
		return
	if placement_pending():
		# Checked before the mandate, because a bay that cannot be placed at all
		# has nothing to declare a mandate FOR: it says so plainly rather than
		# sending the crew to the briefing card for a decision that does not
		# exist yet.
		state_changed.emit(not_placed_state())
		return
	if not OperatingModel.is_declared():
		# The ordering the whole model rests on. Consistency is measured against
		# the mandate, so a decision taken before the mandate exists could not be
		# judged at all - and it is not recorded instead.
		state_changed.emit(no_mandate_state())
		return
	state_changed.emit(intro_state())


## True for a bay that is one of the five placed decisions. False for the helm
## and the kiosk, which are read-outs rather than decisions.
func is_decision_bay() -> bool:
	return GameState.SYSTEMS.has(puzzle_id)


## True for a bay still on the legacy contract, which has not been migrated to
## the autonomy spectrum yet. Those four bays keep compiling and keep their own
## screens, and they record NOTHING until they are migrated.
func placement_pending() -> bool:
	return false


func done_state() -> ScreenState:
	var state := ScreenState.new()
	state.title = system_title
	state.accent = Brand.ACCENT_TINT
	state.rule()
	if GameState.has_placement(puzzle_id):
		state.status = "DECISION MADE"
		state.ok("Your decision on %s is on the record." % GameState.display_name(puzzle_id).to_lower())
		for line in Score.reflection_lines(puzzle_id):
			state.text(line)
	else:
		# A restored system with no placement on record is possible on a save
		# written before the operating model existed. It is read back as history
		# rather than re-decided.
		state.status = "ON THE RECORD"
		state.ok("%s is already recorded in this session." % GameState.display_name(puzzle_id))
		state.dim("No decision on the record. Nothing is charged.")
	state.rule()
	state.dim("This console reads the record back. The decision is not asked for twice.")
	state.rule()
	if GameState.has_placement(puzzle_id) and is_decision_bay():
		state.option("revise", "Change the decision", "Free. No charge to reconsider.", "primary")
	state.option("close", "Leave the console")
	return state


func intro_state() -> ScreenState:
	var state := ScreenState.new()
	state.title = system_title
	state.status = "NO IMPLEMENTATION"
	state.warn("This console has no screen implemented yet.")
	state.option("close", "Close terminal")
	return state


## Shown when a decision console is opened with no mandate on the record. It is
## the visible half of the rule that the mandate comes first.
func no_mandate_state() -> ScreenState:
	var state := ScreenState.new()
	state.title = system_title
	state.status = "NO MANDATE"
	state.accent = Brand.NEUTRAL_LIGHT
	state.rule()
	state.warn("No mandate yet - nothing here can be judged without one.")
	state.dim("Start from the briefing card: pick the objective and risk level, then come back.")
	state.rule()
	state.option("close", "Leave the console")
	return state


## Shown by a bay that has NOT been migrated to the autonomy spectrum yet. It is
## deliberately not a score of zero: a decision nobody has placed is not a
## decision that was placed badly, and the record has to say which of the two it
## is. The four bays not yet migrated report this and score nothing.
func not_placed_state() -> ScreenState:
	var state := ScreenState.new()
	state.title = system_title
	state.status = "NO DECISION YET"
	state.accent = Brand.NEUTRAL_LIGHT
	state.rule()
	state.text("Nobody has made the decision on %s yet." % GameState.display_name(puzzle_id).to_lower())
	state.dim("Not wired for decisions in this build. Nothing is recorded.")
	state.rule()
	state.option("close", "Leave the console")
	return state


func choose(option_id: String) -> void:
	if option_id == "return":
		solve()
		return
	if option_id == "revise" and is_decision_bay():
		## Back to the decision surface from the standing record. Bays that
		## handle "revise" in their own choose() never reach this fallback.
		state_changed.emit(intro_state())
		return
	push_warning("Puzzle '%s' ignored unknown option '%s'" % [puzzle_id, option_id])


## The decision screen's additional information tabs: an ordered list of
## {id, label, lines:[{text, tone}]}. The renderer builds the combined decision
## context; a bay declares only its supporting evidence and SHIPMIND's case.
func info_tabs() -> Array:
	return []


## The spectrum commit. A bay that carries a spectrum block overrides this and
## records the placement; a bay without one never receives it.
func place(level_id: String) -> void:
	push_warning("Puzzle '%s' has no spectrum placement but received '%s'." % [puzzle_id, level_id])


# --- The shared spectrum vocabulary ---------------------------------------------
#
# The five bays ask one question, in the same words: who should make this call -
# SHIPMIND alone, SHIPMIND with a crew undo, SHIPMIND asking first, or the crew.
# Everything that is the same in all five lives here, so a bay cannot rearrange
# the question.


## THE ONE PLACEMENT CONTROL, drawn the same way in all five bays: the decision's
## own stakes tag, the four levels, and one commit. The block's guardrail and
## owner sections are switched OFF here - the pick is the level, and nothing
## else. TerminalUI skips a section whose title is empty.
func placement_block(state: ScreenState, title: String, note: String) -> void:
	state.spectrum_block(title, note)
	state.spectrum_guardrail_title("")
	state.spectrum_owner_title("")
	var tag: Dictionary = OperatingModel.decision_tag(puzzle_id)
	state.spectrum_tag(
		String(tag.get("consequence_word", "")),
		String(tag.get("reversibility_word", "")),
		String(tag.get("tag_note", "")))
	for level in OperatingModel.LEVELS:
		state.spectrum_level(
			String(level["id"]), String(level["label"]), String(level["hint"]),
			false, String(level["short"]))
	state.spectrum_submit("MAKE THE DECISION")


func emit_state(state: ScreenState) -> void:
	state_changed.emit(state)


func solve() -> void:
	if is_solved:
		return
	is_solved = true
	solved.emit(puzzle_id)
