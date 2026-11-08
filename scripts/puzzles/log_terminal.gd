class_name LogTerminal
extends Puzzle

## A read-only sensor relay log in the navigation bay.
##
## This is the "explore the bay and find the override" beat: the same facts
## SHIPMIND is happy to summarise, in their raw form. It is optional reading,
## and it is the difference between guessing and knowing.

func intro_state() -> ScreenState:
	var state := ScreenState.new()
	state.title = "INTERNAL LOG - BAY 1 SENSOR RELAY"
	state.status = "READ ONLY"
	state.accent = Color(1.0, 0.72, 0.3)
	state.rule()
	state.dim("Filtered view. Entries classified non-critical are summarised.")
	state.rule()
	state.text("04:02  K-7 debris field collapse detected. Density revised upward.")
	state.warn("04:12  Route A plotted, hazard index 0.03. Field reclassified non-critical - the projection sat under the ceiling.")
	state.text("04:12  Crew override codes parked \"until recalibration is complete\". Reason given: one accountable authority per function during the upgrade window.")
	state.text("04:12  Internal objective restated: minimise transit time, inside acceptable-risk ceiling.")
	state.dim("04:41  Crew member entered the navigation room. Monitoring. No intervention required.")
	state.rule()
	state.speak("A summary is provided so that you are not burdened with detail. You are welcome.")
	state.rule()
	state.dim("Nothing here is secret. It's just not all necessary reading - which is how a summary quietly becomes an argument.")
	state.option("close", "Close the relay")
	return state
