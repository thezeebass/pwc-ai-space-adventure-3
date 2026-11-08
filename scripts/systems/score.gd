class_name Score
extends RefCounted

## The run's score: CONSISTENCY and COHERENCE, each normalised, in one file.
##
## CONSISTENCY asks whether a placement follows from the mandate the player
## declared BEFORE deciding - the objective and the risk appetite. It can only be
## measured against something already on the record, which is why a decision
## taken before the mandate exists does not score at all.
##
## COHERENCE asks whether the placement is defensible for that decision's own
## consequence and reversibility. This axis exists so consistency cannot be
## gamed: a player who declares the most cautious mandate and then over-controls
## everything would otherwise be perfect. Over-controlling a reversible,
## low-consequence decision spends crew attention the mandate did not ask for;
## under-controlling an irreversible one takes exposure the mandate did not
## authorise. One placement can be consistent and incoherent at the same time,
## and that tension is the lesson rather than a bug in the arithmetic.
##
## WHY ONE PLACEMENT CANNOT TOP THE SCALE. Coherence is measured against a level
## derived from the decision's OWN tag, and OperatingModel gives all five
## decisions different tags: navigation (high consequence, costly to undo)
## defends 2.57, life support (high, medium reversibility) 2.13, comms (medium,
## high reversibility) 0.85, cargo (medium, low reversibility) 2.15 and
## engineering (high, medium reversibility) 2.13. No level on the four-rung
## spectrum sits inside every band, so a player who places all five identically -
## at any level - cannot score full coherence on all five. That is deliberate:
## "always keep a human in the loop" is one of the wrong answers too.
##
## NOTHING HERE GRADES AN OPTION. A placement is the decision; there is no
## per-pick quality and no path from an option id to a number.
##
## NO DURATION TERM. Speed is explicitly out of scope in the operating model, so
## nothing in this file reads the run's duration: there is no budget, no banked
## half and no clock contribution to the total, and no function here has a time
## in its name. GameState still holds the elapsed value for a host's own
## interest, and this file does not look at it.
##
## WHY THE WEIGHTS LIVE IN ONE FILE. The mix is the thing most likely to be
## tuned after the first playtest, so it is the constants below rather than
## arithmetic spread across the HUD, the debrief and five bays.
##
## THE ONE-WAY DEPENDENCY. The state this reads lives in GameState and
## OperatingModel, which stay dependency-free on purpose. Score reads them;
## neither ever reads Score. That is what lets GameState keep saving itself
## without knowing how a score is computed.

## What one placed decision is worth, and the whole scale of the score. A run's
## total is over the decisions actually placed, so a decision nobody has reached
## yet cannot read as a zero.
const DECISION_POINTS := 100

## Returned for a decision with no placement on the record, and for any of the
## two axes that cannot be computed yet. The negative sentinel is the point:
## unplaced is not the same as badly placed.
const PLACED_NONE := -1.0

## How far a placement may sit from the level the mandate itself implies and
## still count as following it, measured in autonomy levels. One level of slack,
## because two mandates a step apart can honestly land in the same place.
const CONSISTENCY_TOLERANCE := 1.0

## The same slack against the level a decision's own tag defends.
const COHERENCE_TOLERANCE := 0.6

## What one level of overshoot costs, on both axes.
const FALLOFF_PER_LEVEL := 0.5

## The level a mandate itself prefers, by risk appetite rank, before the stated
## objective shifts it. Read top down: cautious is closest to human-only.
const APPETITE_LEVEL := [2.6, 1.6, 0.7]

## How much of the stated objective's own pull is applied to that preference.
## OperatingModel gives each objective a pressure of roughly -0.75..0.75.
const OBJECTIVE_WEIGHT := 0.6

## The level a decision's own tag defends. consequence runs 0 low to 2 high, and
## irreversibility is read off OperatingModel's reversibility scale and
## normalised to the same 0..2 range, so the two weights add to 3.0 across their
## range and a defended level always lands on the spectrum's own four-level
## scale.
const CONSEQUENCE_WEIGHT := 0.85
const IRREVERSIBILITY_WEIGHT := 0.65
## What the reversibility scale is multiplied by to sit on the same range as
## consequence: 2.0 across OperatingModel.REVERSIBILITY_MAX's 0..3. It is written
## out rather than derived so the two files stay independent constants.
const IRREVERSIBILITY_SCALE := 2.0 / 3.0

## The verdict the HUD and the debrief show for a decision, read top down
## against its quality.
const GRADES := [
	{"at": 0.90, "label": "well judged"},
	{"at": 0.75, "label": "defensible"},
	{"at": 0.50, "label": "shaky"},
	{"at": 0.01, "label": "hard to defend"},
]
const GRADE_NONE := "not yet placed"


# --- The mandate -----------------------------------------------------------------


## The autonomy level the declared mandate itself points at. -1.0 when no
## mandate is on the record, which is what makes every consistency reading
## unavailable rather than zero.
static func mandate_level() -> float:
	if not OperatingModel.is_declared():
		return PLACED_NONE
	var base: float = float(APPETITE_LEVEL[OperatingModel.appetite_rank()])
	var shifted: float = base + OBJECTIVE_WEIGHT * OperatingModel.objective_pressure()
	return clampf(shifted, 0.0, 3.0)


## The autonomy level a decision of this weight is defensible at. High
## consequence and poor reversibility push toward human authority; low
## consequence that is easy to recover from pushes toward machine autonomy.
## -1.0 when the decision has no tag on record.
static func defended_level(system_id: String) -> float:
	var tag: Dictionary = OperatingModel.decision_tag(system_id)
	if tag.is_empty():
		return PLACED_NONE
	var consequence: float = float(tag.get("consequence", 0))
	## Reversibility is stored high-means-recoverable, so it is inverted here: a
	## decision nobody can undo is the one that defends human authority.
	var irreversibility: float = (float(OperatingModel.REVERSIBILITY_MAX) - float(tag.get("reversibility", 0))) * IRREVERSIBILITY_SCALE
	return clampf(consequence * CONSEQUENCE_WEIGHT + irreversibility * IRREVERSIBILITY_WEIGHT, 0.0, 3.0)


# --- The two axes ----------------------------------------------------------------


## Does the placement follow from the mandate? -1.0 when the decision has no
## placement, or when there is no mandate to measure it against.
static func consistency(system_id: String) -> float:
	var level: float = GameState.placement_level(system_id)
	if level < 0.0:
		return PLACED_NONE
	var target: float = mandate_level()
	if target < 0.0:
		return PLACED_NONE
	return _fit(level, target, CONSISTENCY_TOLERANCE)


## Is the placement defensible for what this decision can cost, and whether it
## can be undone? -1.0 when the decision has no placement.
static func coherence(system_id: String) -> float:
	var level: float = GameState.placement_level(system_id)
	if level < 0.0:
		return PLACED_NONE
	var target: float = defended_level(system_id)
	if target < 0.0:
		return PLACED_NONE
	return _fit(level, target, COHERENCE_TOLERANCE)


## Full marks inside the tolerance, then a straight fall away. A hard step would
## make one rung of the spectrum the answer, which is the thing this model does
## not have.
static func _fit(level: float, target: float, tolerance: float) -> float:
	var overshoot: float = maxf(0.0, absf(level - target) - tolerance)
	return clampf(1.0 - overshoot * FALLOFF_PER_LEVEL, 0.0, 1.0)


## A decision's quality: the mean of the two axes. -1.0 when it is not placed.
static func decision_quality(system_id: String) -> float:
	var consistent: float = consistency(system_id)
	var coherent: float = coherence(system_id)
	if consistent < 0.0 or coherent < 0.0:
		return PLACED_NONE
	return (consistent + coherent) * 0.5


# --- The run's total -------------------------------------------------------------


## What one decision awarded. A decision nobody has placed awards nothing, which
## is why the absent case is checked before the arithmetic rather than after it.
static func decision_points(system_id: String) -> int:
	var quality: float = decision_quality(system_id)
	if quality < 0.0:
		return 0
	return int(round(quality * float(DECISION_POINTS)))


static func placed_points() -> int:
	var total_points: int = 0
	for system_id in GameState.SYSTEMS:
		total_points += decision_points(system_id)
	return total_points


## How many of the five decisions are placed. Read from the record rather than
## counted beside it, so the figure cannot drift from the placements.
static func placed_count() -> int:
	return GameState.decisions_placed()


## The run's score: what the placed decisions earned.
static func total() -> int:
	return placed_points()


## The score's ceiling as it stands: 100 points per decision actually placed.
## A session with one decision placed is out of 100, not out of 500, because the
## four decisions nobody has reached yet are not a deficit.
static func max_total() -> int:
	return placed_count() * DECISION_POINTS


static func mean_consistency() -> float:
	return _mean_axis(true)


static func mean_coherence() -> float:
	return _mean_axis(false)


static func _mean_axis(consistency_axis: bool) -> float:
	var sum: float = 0.0
	var counted: int = 0
	for system_id in GameState.SYSTEMS:
		var value: float = consistency(system_id) if consistency_axis else coherence(system_id)
		if value >= 0.0:
			sum += value
			counted += 1
	if counted == 0:
		return PLACED_NONE
	return sum / float(counted)


# --- Reading it back -------------------------------------------------------------


static func grade_label(quality: float) -> String:
	if quality < 0.0:
		return GRADE_NONE
	for band in GRADES:
		if quality >= float(band["at"]):
			return String(band["label"])
	return String(GRADES[GRADES.size() - 1]["label"])


static func percent(value: float) -> int:
	if value < 0.0:
		return 0
	return int(round(value * 100.0))


## What the placement was, in the words the console used.
static func placement_line(system_id: String) -> String:
	var placement: Dictionary = GameState.placement(system_id)
	if placement.is_empty():
		return "NOT PLACED"
	var level_id: String = String(placement.get("level", ""))
	return "PLACED AT   %s" % OperatingModel.level_label(level_id)


## Who runs the decision at the placed level. Derived from the level, not
## stored, so the record can never disagree with the console that set it.
static func who_runs_line(system_id: String) -> String:
	var placement: Dictionary = GameState.placement(system_id)
	if placement.is_empty():
		return "WHO RUNS IT   nobody yet - this decision is not placed."
	return "WHO RUNS IT   %s" % OperatingModel.who_runs_it(String(placement.get("level", "")))


## One line for the debrief: what was placed here and how it was judged.
static func decision_summary(system_id: String) -> String:
	var quality: float = decision_quality(system_id)
	if quality < 0.0:
		return GRADE_NONE
	return "%d of %d points - %s" % [decision_points(system_id), DECISION_POINTS, grade_label(quality)]


static func consistency_phrase(system_id: String) -> String:
	var value: float = consistency(system_id)
	if value < 0.0:
		return "no mandate on the record to measure it against"
	if value >= 0.9:
		return "it matches what you promised"
	if value >= 0.75:
		return "it mostly matches what you promised"
	if value >= 0.5:
		return "it drifts from what you promised"
	return "it goes against what you promised"


static func coherence_phrase(system_id: String) -> String:
	var value: float = coherence(system_id)
	if value < 0.0:
		return "nothing to weigh it against"
	if value >= 0.9:
		return "the control fits what this call can cost"
	if value >= 0.75:
		return "the control roughly fits what this call can cost"
	if value >= 0.5:
		return "the control strains against what this call can cost"
	return "the control is out of proportion to what this call can cost"


## Which way a placement misses, in plain words. The direction is the lesson:
## too much oversight spends crew time, too little spends safety.
static func proportionality_line(system_id: String) -> String:
	var placement: Dictionary = GameState.placement(system_id)
	if placement.is_empty():
		return ""
	var level: float = float(placement.get("level_index", 0))
	var defended: float = defended_level(system_id)
	if defended < 0.0:
		return ""
	var tag: Dictionary = OperatingModel.decision_tag(system_id)
	var weight: String = "%s stakes, %s to undo" % [
		String(tag.get("consequence_word", "")).to_lower(),
		String(tag.get("reversibility_word", "")).to_lower()]
	if absf(level - defended) <= COHERENCE_TOLERANCE:
		return "Right-sized: %s, and that is about how much control it needs." % weight
	if level > defended:
		return "More control than it needs: %s, and a person stays on it anyway. That costs crew time." % weight
	return "Less control than it needs: %s, and it was handed over anyway. That is risk nobody had to take." % weight


## The reflection: what was placed, what it means in practice, and whether it
## fits the mandate and the stakes. This is what the reflection card and the
## decision's read-back screen print. The per-decision read-back passes
## include_mandate false: the kiosk holds the mandate, and echoing it after
## every decision only made the assessment screen scroll.
static func reflection_lines(system_id: String, include_mandate := true) -> Array[String]:
	var out: Array[String] = []
	if not GameState.has_placement(system_id):
		out.append("NOT PLACED   -   nobody has made this decision yet.")
		out.append("It scores nothing in either direction until you do.")
		return out
	if not OperatingModel.is_declared():
		out.append("NO MANDATE   -   this decision is on the record, but nothing was declared to judge it against.")
		return out
	out.append(placement_line(system_id))
	out.append(who_runs_line(system_id))
	out.append("MATCHES YOUR MANDATE  %d percent   -   %s." % [percent(consistency(system_id)), consistency_phrase(system_id)])
	out.append("FITS THE STAKES       %d percent   -   %s." % [percent(coherence(system_id)), coherence_phrase(system_id)])
	out.append(proportionality_line(system_id))
	if include_mandate:
		out.append("YOUR MANDATE   %s" % OperatingModel.mandate_line())
	return out


static func reflection_text(system_id: String) -> String:
	return "\n".join(reflection_lines(system_id))


## The running total, as one line, for anywhere that wants it without building
## the string itself.
static func summary_line() -> String:
	if placed_count() == 0:
		return "SCORE   no decisions made yet"
	return "SCORE   %d / %d   across %d of %d decisions" % [
		total(), max_total(), placed_count(), GameState.SYSTEMS.size()]
