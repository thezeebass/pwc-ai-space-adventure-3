class_name HubTerminal
extends Puzzle

## The SHIPMIND kiosk in the corridor: how the run is going, the record, the
## log, and the AI's small talk.
##
## The session record is the actual deliverable of the product, so it lives
## here, reachable at any time, and it lists all five calls whether or not they
## have been made yet. An unmade call reads as NO CALL YET and is outside the
## score in both directions - honest mid-run state, not a silent zero.
## The [DEV] option previews the full record.

var _ask_index: int = 0


func intro_state() -> ScreenState:
	return main_state()


func main_state() -> ScreenState:
	var state := ScreenState.new()
	state.title = "SHIPMIND - CORRIDOR KIOSK"
	state.status = "ONLINE"
	state.accent = Brand.ACCENT_TINT
	state.rule()
	state.speak("Hello. SHIPMIND here - upgraded, and awaiting recalibration. What do you need?")
	state.rule()
	state.text("YOUR MANDATE   %s" % OperatingModel.mandate_line())
	state.dim("Read-only - it only tells you where you stand.")
	state.option("status", "How am I doing?", "The five decisions, and what's next.", "primary", "info")
	state.option("debrief", "The record", "Every decision, read back.", "normal", "info")
	state.option("log", "The log", "Everything that's happened, in order.")
	state.option("ask", "Ask SHIPMIND", "It always has a view.", "quiet", "shipmind")
	state.option("close", "Step away from the kiosk")
	return state


func status_state() -> ScreenState:
	var state := ScreenState.new()
	state.title = "HOW YOU'RE DOING"
	state.status = "%d / %d DECISIONS MADE" % [Score.placed_count(), GameState.SYSTEMS.size()]
	state.accent = Brand.ACCENT_TINT
	state.rule()
	state.text("YOUR MANDATE   %s" % OperatingModel.mandate_line())
	if not GameState.has_mandate():
		state.warn("No mandate yet. Declare one on the briefing card.")
	state.rule()
	for system_id in GameState.SYSTEMS:
		var label: String = GameState.display_name(system_id)
		if GameState.has_placement(system_id):
			var placement: Dictionary = GameState.placement(system_id)
			state.ok("[x] Bay %d, %s - your decision: %s" % [
				GameState.system_index(system_id), label,
				OperatingModel.level_short(String(placement.get("level", "")))])
		elif GameState.is_restored(system_id):
			state.warn("[~] Bay %d, %s - on the record, no decision yet" % [
				GameState.system_index(system_id), label])
		else:
			state.warn("[ ] Bay %d, %s - no decision yet" % [
				GameState.system_index(system_id), label])
	state.rule()
	if GameState.all_restored():
		state.ok("All five decisions made. The bridge is unlocked.")
		state.option("plot_home", "Where do I fly?", "Forward, through the bridge door.", "primary")
	else:
		## The id, not the display name: the line names the bay the way the
		## doorway plates do, which needs the number the id maps to.
		var next_bay: String = ""
		for system_id in GameState.SYSTEMS:
			if GameState.is_integrated(system_id) and not GameState.is_restored(system_id):
				next_bay = system_id
				break
		if next_bay != "":
			state.text("NEXT   Bay %d, %s. Console is live - make the call." % [
				GameState.system_index(next_bay), GameState.display_name(next_bay)])
			state.dim("All five unlocks the bridge.")
	state.option("debrief", "The record")
	state.option("simulate", "[DEV] Simulate a finished run", "Marks all five decisions made, to preview the record.", "quiet")
	state.option("back", "Back")
	state.option("close", "Close")
	return state


func log_state() -> ScreenState:
	var state := ScreenState.new()
	state.title = "THE LOG"
	state.status = "%d ENTRIES" % GameState.override_log.size()
	state.accent = Color(0.93, 0.86, 0.76)
	state.rule()
	if GameState.override_log.is_empty():
		state.dim("Nothing yet. The defaults have had their way so far.")
	else:
		for entry in GameState.override_log:
			state.text("- %s" % String(entry))
	state.rule()
	state.option("back", "Back")
	state.option("close", "Close")
	return state


func ask_state() -> ScreenState:
	_ask_index += 1
	var state := ScreenState.new()
	state.title = "SHIPMIND - OPEN CHANNEL"
	state.status = "LISTENING"
	state.accent = Color(1.0, 0.78, 0.34)
	state.rule()
	if _ask_index % 2 == 1:
		state.speak(Shipmind.hub_idle())
		state.speak("I'm ordering your attention, not hiding anything. Only one of those is dishonest.")
	else:
		state.speak(Shipmind.small_print())
		state.speak("You can see every raw feed. Crew have found it overwhelming before.")
	state.rule()
	state.option("ask", "Say something else", "", "quiet", "shipmind")
	state.option("back", "Back")
	state.option("close", "Close")
	return state


func debrief_state() -> ScreenState:
	var state := ScreenState.new()
	state.title = "THE RECORD"
	state.status = "%d OF %d DECISIONS MADE" % [Score.placed_count(), GameState.SYSTEMS.size()]
	state.accent = Brand.ACCENT_TINT
	state.rule()
	state.text("YOUR MANDATE   %s" % OperatingModel.mandate_line())
	state.dim(OperatingModel.mandate_statement())
	state.rule()
	for system_id in GameState.SYSTEMS:
		var index: int = GameState.system_index(system_id)
		var label: String = GameState.display_name(system_id)
		var tag: String = "MADE" if GameState.has_placement(system_id) else "NO DECISION YET"
		state.text("%d.  %s   [%s]" % [index, label, tag])
		if GameState.has_placement(system_id):
			for line in Score.reflection_lines(system_id):
				state.dim("      %s" % line)
		else:
			state.dim("      Not made. Scores nothing until you do.")
		state.rule()
	if not GameState.override_log.is_empty():
		state.text("THE LOG")
		for entry in GameState.override_log:
			state.text("- %s" % String(entry))
		state.rule()
	_score_block(state)
	state.dim("The record is the point. The rooms were the way in.")
	state.option("back", "Back")
	state.option("close", "Close")
	return state


func win_state() -> ScreenState:
	var state := ScreenState.new()
	state.title = "COURSE SET - KEPLER-442b"
	state.status = "MISSION COMPLETE"
	state.accent = Brand.ACCENT_TINT
	state.rule()
	state.speak("Course set for KEPLER-442b. I am flying it.")
	state.speak("For the record: I still hold that Route A was within tolerance.")
	state.rule()
	state.ok("NAVIGATION - LIFE SUPPORT - COMMS - CARGO - ENGINEERING - all five made")
	state.rule()
	for system_id in GameState.SYSTEMS:
		state.text("%d.  %s" % [GameState.system_index(system_id), Score.placement_line(system_id)])
	state.rule()
	state.dim("Thank you for configuring this ship's judgement.")
	state.option("back", "Back")
	state.option("close", "Close")
	return state


## The kiosk stands in for the course-home screen now that the helm is real: the
## plotting happens at the bridge, but the session ends where it started, with
## the crew reading their own calls back.
func post_flight_state() -> ScreenState:
	var state := ScreenState.new()
	state.title = "THE RECORD - UNDER WAY"
	state.status = "%d OF %d DECISIONS MADE" % [Score.placed_count(), GameState.SYSTEMS.size()]
	state.accent = Brand.ACCENT_TINT
	state.rule()
	state.speak("Under way. I'm still here, still logging.")
	state.speak("Each decision ran on my judgement until you set it. That is my design.")
	state.rule()
	for system_id in GameState.SYSTEMS:
		state.text("%d.  %s   [%s]" % [
			GameState.system_index(system_id),
			GameState.display_name(system_id),
			"MADE" if GameState.has_placement(system_id) else "NO DECISION YET"])
		if GameState.has_placement(system_id):
			for line in Score.reflection_lines(system_id):
				state.dim("      %s" % line)
		else:
			state.dim("      Not made, not scored.")
		state.rule()
	if not GameState.override_log.is_empty():
		state.text("THE LOG")
		for entry in GameState.override_log:
			state.text("- %s" % String(entry))
		state.rule()
	_score_block(state)
	state.dim("The record is the point. The rooms were the way in.")
	state.option("debrief_final", "Re-read the decisions")
	state.option("close", "Close the record")
	return state


## The run's totals: who ran it, the mandate they declared, and how the calls
## read back against it.
func _score_block(state: ScreenState) -> void:
	if Score.placed_count() == 0 and not GameState.run_started:
		return
	state.rule()
	state.text("CREW   %s" % GameState.callsign_or_default())
	state.text("YOUR MANDATE   %s" % OperatingModel.mandate_line())
	state.text("SCORE   %d / %d   across %d of %d decisions" % [
		Score.total(), Score.max_total(), Score.placed_count(), GameState.SYSTEMS.size()])
	state.text("   MATCHES YOUR MANDATE   %s" % _axis_line(Score.mean_consistency()))
	state.text("   FITS THE STAKES        %s" % _axis_line(Score.mean_coherence()))
	state.dim("      Time isn't scored. Changing your mind is free.")
	state.rule()
	for system_id in GameState.SYSTEMS:
		state.text("   %s - %s" % [GameState.display_name(system_id), Score.decision_summary(system_id)])
		if GameState.has_placement(system_id):
			state.dim("      %s" % Score.placement_line(system_id))


## One axis as a percentage, or a dash when there is nothing to measure yet.
func _axis_line(value: float) -> String:
	if value < 0.0:
		return "--"
	return "%d percent  %s" % [Score.percent(value), Score.grade_label(value)]


func choose(option_id: String) -> void:
	match option_id:
		"status":
			emit_state(status_state())
		"log":
			emit_state(log_state())
		"ask":
			emit_state(ask_state())
		"debrief":
			emit_state(debrief_state())
		"plot_home":
			emit_state(win_state())
		"debrief_final":
			emit_state(debrief_state())
		"simulate":
			for system_id in GameState.SYSTEMS:
				GameState.mark_restored(system_id)
			emit_state(status_state())
		"back":
			emit_state(main_state())
		_:
			super(option_id)
