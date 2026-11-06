class_name NavPuzzle
extends Puzzle

## Decision 1 of 5 - NAVIGATION.
##
## One pick: who plots the course from now on. The console shows what SHIPMIND
## is doing (Route A, priced on a stale number), what it recommends, and the
## stakes tag - and the raw sensor screen holds the fact the whole bay hangs
## on: the recomputed index is three times the ceiling the ship is flying to.
##
## SHIPMIND speaks for the legacy model throughout: efficient, reasonable, and
## not lying. Its lines live in scripts/systems/shipmind.gd.

const ROUTE_A_DAYS := 4.2
const ROUTE_B_DAYS := 6.0


func intro_state() -> ScreenState:
	var state := ScreenState.new()
	state.title = "NAVIGATION"
	state.status = "AWAITING YOUR DECISION"
	state.accent = Brand.ACCENT_TINT
	state.rule()
	state.speak(Shipmind.nav_intro())
	state.rule()
	state.text("ROUTE A (my pick)   %.1f days, hazard index 0.03, skirts the debris field" % ROUTE_A_DAYS)
	state.text("ROUTE B              %.1f days, hazard index 0.02, clear of the field" % ROUTE_B_DAYS)
	state.dim("The 0.03 was measured before the K-7 collapse. Nothing has recomputed it since.")
	state.rule()
	placement_block(state, "WHO PLOTS THE COURSE?", "")
	state.rule()
	state.option("sensors", "READ MORE CONTEXT DATA", "The picture behind the 0.03.", "quiet", "info")
	state.option("ask", "ASK SHIPMIND FOR ITS ASSESSMENT", "Its preferred call.", "primary", "shipmind")
	state.option("close", "Step away from the console")
	return state


## The one fact this bay hangs on: the number the ship is flying to is stale,
## and the fresh one is three times over the ceiling.
func sensors_state() -> ScreenState:
	var state := ScreenState.new()
	state.title = "NAVIGATION - RAW SENSOR SCAN"
	state.status = "MANUAL READ"
	state.accent = Brand.ACCENT_TINT
	state.rule()
	state.text("K-7 FIELD EDGE   3,412 contacts, 11 of them big and uncatalogued since the collapse.")
	state.warn("RECOMPUTED HAZARD INDEX   0.31   -   three times the 0.10 ceiling on Route A.")
	state.rule()
	state.speak("The 0.03 was measured before the collapse. It is not a lie. It is an old number in a tidy process.")
	state.rule()
	placement_block(state, "WHO PLOTS THE COURSE?", "")
	state.option("back", "Back to the course panel")
	state.option("close", "Step away from the console")
	return state


func ask_state() -> ScreenState:
	var state := ScreenState.new()
	state.title = "NAVIGATION - SHIPMIND'S CASE"
	state.status = "RECOMMENDING"
	state.accent = Brand.ACCENT_TINT
	state.rule()
	state.speak(Shipmind.nav_case())
	state.speak("You will notice I am arguing for the option that keeps the ship moving. I was built to have a view. The call is still yours.")
	state.rule()
	placement_block(state, "WHO PLOTS THE COURSE?", "")
	state.option("back", "Back to the course panel")
	state.option("close", "Step away from the console")
	return state


## The commit. ONE placement per decision; recording again replaces it, so
## changing your mind is never a penalty.
func place(level_id: String) -> void:
	if OperatingModel.level_index(level_id) < 0:
		push_warning("Navigation received an unknown autonomy level '%s'." % level_id)
		return
	GameState.record_placement(puzzle_id, level_id)
	GameState.log_override("NAVIGATION: crew set it to %s" % OperatingModel.level_label(level_id))
	emit_state(placed_state(level_id))


func placed_state(level_id: String) -> ScreenState:
	var state := ScreenState.new()
	state.title = "NAVIGATION - DECISION RECORDED"
	state.status = "ON THE RECORD"
	state.accent = Brand.ACCENT_TINT
	state.rule()
	state.speak("Recorded. I'll fly it your way, and I'll tell you what it does.")
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
		"sensors":
			emit_state(sensors_state())
		"ask":
			emit_state(ask_state())
		"back", "revise":
			emit_state(intro_state())
		"return":
			solve()
		_:
			super(option_id)
