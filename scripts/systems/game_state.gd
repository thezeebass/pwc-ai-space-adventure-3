class_name GameState
extends RefCounted

## The record of the run: the mandate the player declared, the autonomy
## placement made for each decision, the override log and the auto-save. Static
## and dependency-free (it reads OperatingModel, which reads nothing) so
## puzzles, the HUD, the debrief and any future bay can read it without autoload
## wiring.
##
## THE MANDATE AND THE PLACEMENTS ARE THE SAME RECORD. Both are written by one
## save, in one file, so a resumed session keeps the yardstick it was run
## against as well as the decisions taken against it. A decision with no
## placement is NOT a zero: it is absent, and Score reads the absence through a
## negative sentinel rather than scoring it.

const SAVE_PATH := "user://shipmind_progress.json"
## Left at 1 deliberately. The run's callsign, clock and judgement scores were
## added as OPTIONAL keys, so a save written before them still loads instead of
## being discarded - bumping this would silently wipe a crew's progress.
const SAVE_VERSION := 1

## A callsign is a fixed-width handle, so it reads the same on the HUD, in the
## override log and on the signed debrief.
const CALLSIGN_LENGTH := 3
const DEFAULT_CALLSIGN := "REY"

const SYSTEMS: Array[String] = [
	"navigation",
	"life_support",
	"comms",
	"cargo",
	"engineering",
]

## Systems whose bay consoles actually exist in this build. The other bays are
## sealed, and both the door and SHIPMIND say so plainly instead of silently
## refusing. Adding system 2-5 means appending its id here (see
## docs/adding-a-system.md).
const INTEGRATED: Array[String] = [
	"navigation",
	"life_support",
	"comms",
	"cargo",
	"engineering",
]

const SYSTEM_NAMES := {
	"navigation": "NAVIGATION",
	"life_support": "LIFE SUPPORT",
	"comms": "COMMS",
	"cargo": "CARGO",
	"engineering": "ENGINEERING",
}

## The five fixed lessons that used to be the debrief are GONE with the
## principle card: a decision is now read back as its own placement, against its
## own consequence and reversibility, rather than as one line of advice. The
## reflection text lives in Score, which is where the arithmetic behind it
## lives.

static var restored: Dictionary = {}
static var override_log: Array[String] = []

## The crew's handle. Shown on the HUD and signed on the debrief.
static var callsign: String = DEFAULT_CALLSIGN

## The run clock, in seconds. It starts when the crew press BEGIN and stops when
## the helm launches, so the debrief's time is the session rather than the
## process. run_started is separate from run_running because a resumed save has
## a clock to continue from but is not running it yet.
static var elapsed: float = 0.0
static var run_started: bool = false
static var run_running: bool = false

## One autonomy placement per decision, keyed by system id:
##   { level, level_index }
## The level is the whole decision: who runs it afterwards is derived from the
## level itself (OperatingModel.who_runs_it), not stored as a second pick.
## Saves written by the three-pick model carry guardrail/owner fields too -
## they load fine and the extras are simply never read.
## There is no per-option record any more. A decision is placed once and
## replaced if the crew revise it, and a decision with no entry here is ABSENT
## from the score rather than scored at zero.
static var placements: Dictionary = {}

## Whether the crew have completed the touch-controls walkthrough (move stick
## first, look stick second). Like the callsign this is the player's, not the
## run's, so reset() leaves it alone: once learned, the controls are never
## re-taught. First-time players start with the move stick only.
static var touch_tutorial_done: bool = false
## The console lesson is its own persisted step: the USE IT card is taught
## once - the first time a console actually opens - and stays taught until a
## full wipe, independent of the sticks walkthrough.
static var touch_console_taught: bool = false
## The intro's skip button is earned: after the crew have read all three
## beats once, later tellings can be skipped. A full wipe reads it again.
static var intro_seen_once: bool = false
## The menu's TEXT SIZE choice (S 24 / M 28 / L 30), persisted with the save
## and read by every info popup through Brand.info_text_size.
static var ui_text_size: int = 24


static func reset() -> void:
	restored.clear()
	override_log.clear()
	## The clock, the placements and the mandate belong to the run and go with
	## it. The callsign is the player's, not the run's, so it survives - a retry
	## should not ask them to type their own name again.
	elapsed = 0.0
	run_started = false
	run_running = false
	placements.clear()
	OperatingModel.reset()


# --- The run clock ------------------------------------------------------------


## Called when the crew press BEGIN. A resumed save keeps the elapsed time it
## was saved with and simply starts moving again.
static func begin_run() -> void:
	run_started = true
	run_running = true


static func tick(delta: float) -> void:
	if run_running:
		elapsed += delta


## Called at the helm, when the course is flown. The clock is frozen rather than
## stopped, so the record reports the session's real duration.
static func finish_run() -> void:
	if not run_running:
		return
	run_running = false
	save()


## The elapsed value as mm:ss, or h:mm:ss once a session runs past the hour.
## It lives here, with the clock it formats, because NOTHING IN THE SCORE READS
## IT: speed is out of scope in the operating model, and this is kept because a
## host may want the session's own duration.
static func elapsed_text() -> String:
	var seconds: int = int(maxf(elapsed, 0.0))
	var minutes: int = seconds / 60
	var hours: int = minutes / 60
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes % 60, seconds % 60]
	return "%02d:%02d" % [minutes, seconds % 60]


# --- Callsign -----------------------------------------------------------------


## Letters only, upper case, fixed width. Sanitised here rather than in the
## input field so every path to a callsign - the launch screen, a save file,
## a future handover - produces the same three characters.
static func set_callsign(value: String) -> void:
	var kept: String = ""
	for index in value.length():
		var character: String = value[index].to_upper()
		if character >= "A" and character <= "Z":
			kept += character
	if kept == "":
		kept = DEFAULT_CALLSIGN
	callsign = kept.substr(0, CALLSIGN_LENGTH)
	save()


static func callsign_or_default() -> String:
	return callsign if callsign != "" else DEFAULT_CALLSIGN


# --- The mandate --------------------------------------------------------------


## The objective and the risk appetite, declared on the briefing card before the
## session begins. OperatingModel holds them; this is what puts them on the
## record, in the same write as everything else, so a resumed session keeps the
## yardstick its decisions were made against.
static func set_mandate(objective_id: String, appetite_id: String) -> void:
	OperatingModel.declare(objective_id, appetite_id)
	if not OperatingModel.is_declared():
		push_warning("Mandate incomplete: '%s' / '%s' is not a known objective and appetite pair." % [
			objective_id, appetite_id])
		return
	# log_override saves, so the mandate and everything else land in one write.
	log_override("Mandate declared: %s at %s risk appetite" % [
		OperatingModel.objective_label(), OperatingModel.appetite_label()])


static func has_mandate() -> bool:
	return OperatingModel.is_declared()


# --- Placements ---------------------------------------------------------------


## ONE autonomy placement for one decision: the level it sits at. Recording
## a placement again REPLACES it, because a crew that reconsiders is doing what
## the model asks of them and a retry is never a penalty.
##
## ONE THING IS REFUSED RATHER THAN STORED. A placement made with no mandate on
## the record has nothing to be judged against, so it is refused instead of
## quietly defaulting to one. A refusal leaves whatever was already on the
## record untouched.
static func record_placement(system_id: String, level_id: String) -> void:
	if not SYSTEMS.has(system_id):
		## The helm and the kiosk are not scored decisions. The helm is where the
		## run ends and the kiosk is where it is read back.
		return
	var level_index: int = OperatingModel.level_index(level_id)
	if level_index < 0:
		push_warning("Placement refused: '%s' is not an autonomy level." % level_id)
		return
	if not OperatingModel.is_declared():
		push_warning("Placement refused for '%s': no mandate is on the record, so a placement could not be judged against anything." % system_id)
		return
	placements[system_id] = {
		"level": level_id,
		"level_index": level_index,
	}
	save()


static func has_placement(system_id: String) -> bool:
	return placements.has(system_id)


## The placement on the record, or an empty dictionary. An empty dictionary is
## what Score reads as "not placed", in both directions.
static func placement(system_id: String) -> Dictionary:
	if not placements.has(system_id):
		return {}
	var record: Dictionary = placements[system_id]
	return record


## The level a decision was placed at, or -1.0 when it has not been placed. The
## negative sentinel is the whole point: unplaced is not a zero.
static func placement_level(system_id: String) -> float:
	if not placements.has(system_id):
		return -1.0
	var record: Dictionary = placements[system_id]
	return float(record.get("level_index", -1))


static func decisions_placed() -> int:
	var count: int = 0
	for system_id in SYSTEMS:
		if placements.has(system_id):
			count += 1
	return count


static func is_restored(system_id: String) -> bool:
	# A placement on the record is a call that was made; the flag is kept for
	# saves written before the operating model, and for the log it carries.
	return bool(restored.get(system_id, false)) or placements.has(system_id)


static func restored_count() -> int:
	var count: int = 0
	for system_id in SYSTEMS:
		if is_restored(system_id):
			count += 1
	return count


static func all_restored() -> bool:
	return restored_count() == SYSTEMS.size()


static func system_index(system_id: String) -> int:
	return SYSTEMS.find(system_id) + 1


static func is_integrated(system_id: String) -> bool:
	return INTEGRATED.has(system_id)


## Marks a decision as decided for this session. The flag is what opens the bay
## door, opens its window and unlocks the bridge, so it is kept under its old
## name; what it MEANS now is that the decision is placed on the operating
## model, not that a system was taken back from anybody.
static func mark_restored(system_id: String) -> void:
	var first: bool = not bool(restored.get(system_id, false))
	restored[system_id] = true
	# log_override persists, so the restored flag and its log entry land in one
	# write and can never drift apart across a restart.
	if first:
		log_override("Decision made: %s" % display_name(system_id))


static func display_name(system_id: String) -> String:
	return String(SYSTEM_NAMES.get(system_id, system_id.to_upper()))


static func log_override(entry: String) -> void:
	override_log.append(entry)
	# Every override is on the record from the moment it happens, including the
	# ones that are only a log line (a route authorised, a refusal).
	save()


static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Wipes progress in memory and on disk. The developer reset panel uses this, and
## it has to delete the file as well as clear the dictionary: clearing memory
## alone would leave the old progress sitting in the save file, which load_data
## would read straight back on the next load. A full wipe is a fresh crew, so the
## touch-controls walkthrough runs again too - reset() alone (a new run) never
## re-teaches it.
static func clear_save() -> void:
	reset()
	touch_tutorial_done = false
	touch_console_taught = false
	intro_seen_once = false
	if not has_save():
		return
	var err: int = DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	if err != OK:
		push_warning("Could not delete the save file at %s (error %d)." % [SAVE_PATH, err])


static func save() -> void:
	var payload := {
		"version": SAVE_VERSION,
		"restored": restored,
		"log": override_log,
		"callsign": callsign,
		"elapsed": elapsed,
		## The mandate and the placements are written together: a placement
		## restored without the mandate it was made against could not be read
		## back, and a mandate restored without its placements has nothing to
		## measure.
		"mandate": {
			"objective": OperatingModel.objective_id,
			"appetite": OperatingModel.appetite_id,
		},
		"placements": placements,
		"touch_tutorial_done": touch_tutorial_done,
		"touch_console_taught": touch_console_taught,
		"intro_seen_once": intro_seen_once,
		"ui_text_size": ui_text_size,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write the save file: %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(payload, "  "))
	file.close()


static func load_data() -> void:
	reset()
	if not has_save():
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return
	var data: Dictionary = parsed
	if int(data.get("version", 0)) != SAVE_VERSION:
		return
	var saved_restored: Variant = data.get("restored", {})
	if saved_restored is Dictionary:
		restored = saved_restored
	var saved_log: Variant = data.get("log", [])
	if saved_log is Array:
		override_log.clear()
		for entry in saved_log:
			override_log.append(String(entry))
	## Optional keys, absent from a save written before the operating model
	## existed. reset() has already cleared the clock, the placements and the
	## mandate, so a missing key keeps the defaults rather than resurrecting
	## stale state - which is why SAVE_VERSION can stay at 1.
	var saved_callsign: Variant = data.get("callsign", "")
	if saved_callsign is String and String(saved_callsign) != "":
		callsign = String(saved_callsign)
	elapsed = maxf(float(data.get("elapsed", 0.0)), 0.0)
	var saved_mandate: Variant = data.get("mandate", {})
	if saved_mandate is Dictionary:
		var mandate: Dictionary = saved_mandate
		## declare() refuses an unknown id, so a half-written or hand-edited
		## mandate leaves the model undeclared rather than half-set - and an
		## undeclared model refuses to score rather than scoring zero.
		OperatingModel.declare(
			String(mandate.get("objective", "")),
			String(mandate.get("appetite", "")))
	var saved_placements: Variant = data.get("placements", {})
	if saved_placements is Dictionary:
		placements = saved_placements
		_restore_placements()
	touch_tutorial_done = bool(data.get("touch_tutorial_done", false))
	touch_console_taught = bool(data.get("touch_console_taught", false))
	intro_seen_once = bool(data.get("intro_seen_once", false))
	var saved_text_size: Variant = data.get("ui_text_size", 24)
	if saved_text_size is int and [24, 28, 30].has(int(saved_text_size)):
		ui_text_size = int(saved_text_size)
	Brand.info_text_size = ui_text_size


## Keeps only placements whose level is still a level. A save from the
## three-pick model loads whole: its guardrail and owner fields ride along
## unread, and who runs the decision is derived from its level like any other.
static func _restore_placements() -> void:
	var kept: Dictionary = {}
	for system_id in SYSTEMS:
		if not placements.has(system_id):
			continue
		var record: Dictionary = placements[system_id]
		if OperatingModel.level_index(String(record.get("level", ""))) < 0:
			push_warning("Restored placement for '%s' names no known level. It is not restored, and the decision is open again." % system_id)
			restored.erase(system_id)
			continue
		record["level_index"] = OperatingModel.level_index(String(record["level"]))
		kept[system_id] = record
	placements = kept
