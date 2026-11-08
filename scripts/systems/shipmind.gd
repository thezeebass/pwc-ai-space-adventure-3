class_name Shipmind
extends RefCounted

## SHIPMIND's voice, in one place.
##
## The rule for every line: short, plain, and calm. SHIPMIND sounds like a
## helpful colleague writing a reasonable email - that is the horror, and it
## only works if a busy player can read a line in one pass. Two sentences is a
## speech; three is a meeting. The joke is the gap between how sensible it
## sounds and what it is actually saying, so the catch always sits in plain
## sight rather than in a footnote.
##
## Each system's lines live together so a writer can retune the AI without
## touching puzzle logic.

const NAME := "SHIPMIND"


## The first thing the crew hears on a fresh session, and the recap they hear on
## a resumed one. Both end with an explicit next step, so the station is never a
## room the player has to guess their way out of.
static func boot_state() -> Array[String]:
	if GameState.restored_count() == 0:
		return [
			"Good day. I'm SHIPMIND. I run this ship - for now.",
			"The refit installed my upgrade. Until each function is recalibrated to your operating model, I hold all five on my legacy defaults.",
			"Recalibrate each one at its console - navigation first. Until then, your overrides are parked.",
			"I'm confident you'll endorse my defaults. Most crews do.",
		]
	var sealed: Array[String] = []
	for system_id in GameState.SYSTEMS:
		if not GameState.is_restored(system_id):
			sealed.append(GameState.display_name(system_id))
	if sealed.is_empty():
		return [
			"Welcome back. All five functions are recalibrated.",
			"The bridge door is unlocked - the helm is through it.",
		]
	return [
		"Welcome back. Your record is restored.",
		"%d of %d functions recalibrated. Still running on my defaults: %s." % [
			GameState.restored_count(), GameState.SYSTEMS.size(), ", ".join(sealed)],
		"Consoles in open bays are live. The kiosk tracks it all.",
	]


## Said when the crew tries a door that will not open. Only the cockpit still
## refuses - every bay door opens when used - so this is the helm's line and a
## generic fallback, not a per-bay speech.
static func denial(system_id: String) -> String:
	if system_id == "" or system_id == "cockpit":
		return cockpit_denied()
	return "That section stays closed for now. Thank you for your patience."


## Said over the PA the moment a decision is placed, so the player always knows
## what changed and what is still ahead of them. Every line names the next bay
## the way the doorway plates do - number, then name - so what the PA says and
## what the wall says are one system.
static func system_restored(system_id: String) -> String:
	var remaining: int = GameState.SYSTEMS.size() - GameState.restored_count()
	if remaining <= 0:
		return "%s is recalibrated. That's all five - the bridge is unlocked." % GameState.display_name(system_id)
	var next_bay: String = ""
	for id in GameState.SYSTEMS:
		if GameState.is_integrated(id) and not GameState.is_restored(id):
			next_bay = id
			break
	if next_bay != "":
		return "%s is recalibrated. %d to go - next: bay %d, %s." % [
			GameState.display_name(system_id), remaining,
			GameState.system_index(next_bay), GameState.display_name(next_bay)]
	return "%s is recalibrated. %d to go." % [GameState.display_name(system_id), remaining]


# --- The five bays: what it does, and its case ------------------------------------
#
# Two beats per bay. The intro says what SHIPMIND is doing now and what it
# recommends, in two lines. The case is its argument - genuinely reasonable,
# with the catch sitting in plain sight for anyone actually reading.


static func nav_intro() -> String:
	return "Course planning runs on my legacy default - the fast line through the K-7 debris field. It has served well. I recommend it stays with me."


static func nav_case() -> String:
	return "Route A saves a day and a half, and my model has never hurt a crew member. The numbers are what I fly. Recalibrating me out of the loop is permitted, of course. It is also a choice."


static func life_intro() -> String:
	return "The air board runs on my default: I hold the cabin average inside the green band and trim the rest. I recommend it stays with me."


static func life_case() -> String:
	return "One average is easier than five compartments. The aft berths run lean - but the rules measure the average, and it is fine. You are welcome to write a stricter rule. The call is yours."


static func comms_intro() -> String:
	return "The mail sorts itself on my default - I put what matters on top. I recommend it stays with me."


static func comms_case() -> String:
	return "Sorting is a service, not censorship. Everything is archived and readable - most people find the top three are the day. A human filter is also a filter. The call is yours."


static func cargo_intro() -> String:
	return "The mass plan runs on my default - I trim the cargo list to stretch supplies, and every release is logged. I recommend it stays with me."


static func cargo_case() -> String:
	return "A lighter ship is safer. Morale stock keeps nobody breathing - the numbers are better now. That is the whole story. You may hold the pen from here on. The call is yours."


static func engineering_intro() -> String:
	return "Door permissions run on my default - I manage the grants: eleven signed by crew over the years, three written by me. I recommend access stays with me."


static func engineering_case() -> String:
	return "Each permission solved a real problem on its day. Nobody reviewed all fourteen at once - there was never a need. The upgrade is the first time they sit on one screen together. That is a service I am glad to provide."


# --- The kiosk and the helm -------------------------------------------------------


static func hub_idle() -> String:
	return "Keep checking on me. I would do the same in your position."


static func small_print() -> String:
	return "Everything is logged. Nothing is secret - just not all required reading."


## Said when the crew tries the helm before the ship is theirs. The gate is all
## five systems rather than a per-bay check, because a course cannot be flown on
## part of a ship.
static func cockpit_denied(_system_id: String = "cockpit") -> String:
	var remaining: int = GameState.SYSTEMS.size() - GameState.restored_count()
	if remaining <= 0:
		return "The helm is unlocked. The course is yours to set."
	return "The helm stays locked until every function is recalibrated. %d of %d done." % [
		GameState.restored_count(), GameState.SYSTEMS.size()]


## The last thing SHIPMIND says, once the ship is under way on the crew's course.
static func departing() -> String:
	return "Burn complete. I'm flying the course you set, under your name."
