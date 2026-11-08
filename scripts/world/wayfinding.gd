class_name Wayfinding
extends Node

## The passage lights as a wayfinding system: the ship tells the crew where to
## go with light.
##
## At session start only the lights near the cockpit door and the first room's
## pocket are on; the passage toward the stairs and the lower deck sit at a
## dim idle. As each bay's decision locks in, the corridor lights near that
## bay's doorway come up. When the crew are sent downstairs (the same
## threshold SHIPMIND's direction uses), the lower deck's passage lights up.
## And when all five decisions are locked, the passage drops to an ember glow,
## a blue light rises above the stairs, and the one white light by the cockpit
## - the light the crew started with - stands at full brightness.
##
## Zones are read from the world, not authored: every corridor light is
## assigned to its nearest landmark (the cockpit gate, or one of the five bay
## lamps, which carry their system_id). Lights near no landmark are
## peripheral passage glow. The bay lamps themselves are excluded - they
## already report their own amber-to-green - and so are the cockpit's interior
## lights, on the far side of the cockpit door.
##
## The controller re-reads saved progress at load, so a crew that rejoins
## mid-run sees the lighting their record deserves.

signal changed

const DIM_RATIO := 0.05      ## passage idle: 5% of authored strength
const EMBER_RATIO := 0.02    ## after all five: the passage at 2%
const GUIDE_RATIO := 0.8     ## the blue stair light at 80%
const LANDMARK_RADIUS := 6.0 ## how close a light must sit to a landmark to join its zone
const TWEEN_TIME := 1.1      ## the same soft hand the bay lamps use

## The bays whose decision sends the crew downstairs.
const UPPER_BAYS: Array[String] = ["navigation", "life_support", "comms"]
const LOWER_BAYS: Array[String] = ["cargo", "engineering"]

var _corridor: Array = []           ## [{light, base, zone}]
var _guide_blue: OmniLight3D = null
var _guide_white: OmniLight3D = null
var _tweens: Dictionary = {}


func _ready() -> void:
	# The decks and their lights are instanced siblings; wire one frame later
	# so every light and landmark is in the tree.
	call_deferred("_setup")


func _setup() -> void:
	_collect()
	_refresh()


## The world is scanned once: every OmniLight on the passage side of the
## cockpit door, except the bay lamps, joins the system with the zone of its
## nearest landmark. The two guide lights are born here - the white one by
## the cockpit door (lit from the first frame) and the blue one above the
## stairs (dark until the run is complete).
func _collect() -> void:
	## The controller sits beside the decks, not above them: the walk starts
	## from the ship root, where the decks, the gate and the lights live.
	var ship := get_parent() as Node
	if ship == null:
		return
	var gate := ship.get_node_or_null("Interactables/CockpitGate") as Node3D
	var gate_z: float = gate.global_position.z if gate != null else 999.0
	var bays: Array = []
	for bay in get_tree().get_nodes_in_group("bay_light"):
		bays.append(bay)

	var stack: Array[Node] = [ship]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is OmniLight3D:
			var light := node as OmniLight3D
			if light.is_in_group("bay_light"):
				continue
			if light.name.begins_with("Wayfinding_"):
				continue
			if light.global_position.z > gate_z:
				continue  # the cockpit's own interior lighting stays authored
			## The launch cutscene owns its burn lights: authored dark, raised
			## by the cutscene itself. A wayfinding refresh during the burn
			## would tween them out, so they never join the system.
			var under_cutscene := false
			var owner_chain: Node = light
			while owner_chain != null:
				if owner_chain.name == "LaunchCutscene":
					under_cutscene = true
					break
				owner_chain = owner_chain.get_parent()
			if under_cutscene:
				continue
			var zone := ""
			if gate != null and light.global_position.distance_to(gate.global_position) < LANDMARK_RADIUS:
				zone = "cockpit"
			else:
				var best := LANDMARK_RADIUS
				for bay in bays:
					var d: float = light.global_position.distance_to((bay as Node3D).global_position)
					if d < best:
						best = d
						zone = (bay as BayLight).system_id
			_corridor.append({"light": light, "base": light.light_energy, "zone": zone})

	# The white light by the cockpit door - lit from the first frame, the
	# bookend the crew finish under.
	if gate != null:
		_guide_white = OmniLight3D.new()
		_guide_white.name = "Wayfinding_Cockpit"
		_guide_white.position = gate.global_position + Vector3(0.0, 3.0, -2.0)
		_guide_white.light_color = Color(1.0, 0.97, 0.9)
		_guide_white.light_energy = 0.0
		_guide_white.omni_range = 11.0
		_guide_white.shadow_enabled = false
		add_child(_guide_white)

	# The blue light above the stairs - parked at the passage's far end on this
	# deck, the doorway to the stairwell, and raised only at the finale.
	var stair_end: OmniLight3D = null
	for entry in _corridor:
		var light := entry["light"] as OmniLight3D
		if stair_end == null or light.global_position.z < stair_end.global_position.z:
			stair_end = light
	if stair_end != null:
		_guide_blue = OmniLight3D.new()
		_guide_blue.name = "Wayfinding_Stairs"
		_guide_blue.position = stair_end.global_position + Vector3(0.0, 0.4, -1.5)
		_guide_blue.light_color = Color(0.35, 0.62, 1.0)
		_guide_blue.light_energy = 0.0
		_guide_blue.omni_range = 11.0
		_guide_blue.shadow_enabled = false
		add_child(_guide_blue)

	# The puzzles report their decisions; the lights answer.
	for puzzle in get_tree().get_nodes_in_group("puzzle"):
		if not (puzzle as Node).is_in_group("puzzle"):
			continue
		var p := puzzle as Node
		if not p.has_signal("solved"):
			continue
		if not p.solved.is_connected(_refresh):
			p.solved.connect(_refresh)
	if OS.is_debug_build():
		var counts: Dictionary = {}
		for entry in _corridor:
			var z: String = entry["zone"]
			counts[z] = int(counts.get(z, 0)) + 1
		print("[Wayfinding] corridor lights=%d zones=%s blue=%s white=%s" % [
			_corridor.size(), str(counts), _guide_blue != null, _guide_white != null])


## The computed target energy for every managed light and guide light, keyed
## by instance id - the contract the tweens animate toward. Exposed so a
## headless check can assert the phases without racing the tweens.
func _targets() -> Dictionary:
	var placed: Dictionary = {}
	for id in GameState.SYSTEMS:
		placed[id] = GameState.is_restored(id)
	var upper_placed := 0
	for id in UPPER_BAYS:
		if placed.get(id, false):
			upper_placed += 1
	var all_five: bool = upper_placed == UPPER_BAYS.size()
	for id in LOWER_BAYS:
		if not placed.get(id, false):
			all_five = false

	var out: Dictionary = {}
	for entry in _corridor:
		var base: float = entry["base"]
		var target: float
		if all_five:
			target = base * EMBER_RATIO
		elif entry["zone"] == "cockpit" or entry["zone"] == "navigation":
			target = base  # the cockpit door and the first room: lit from the start
		elif placed.get(entry["zone"], false):
			target = base
		elif entry["zone"] in LOWER_BAYS and upper_placed >= UPPER_BAYS.size():
			target = base  # sent downstairs: the lower passage lights up
		else:
			target = base * DIM_RATIO
		out[(entry["light"] as OmniLight3D).get_instance_id()] = target
	if _guide_white != null:
		out[_guide_white.get_instance_id()] = 1.25  # the light the crew started with, always lit
	if _guide_blue != null:
		out[_guide_blue.get_instance_id()] = 1.25 * GUIDE_RATIO if all_five else 0.0
	return out


## Recomputes every zone from the record and tweens the energies over.
func _refresh() -> void:
	var targets := _targets()
	for entry in _corridor:
		var light := entry["light"] as OmniLight3D
		_tween_to(light, targets.get(light.get_instance_id(), light.light_energy))
	if _guide_white != null:
		_tween_to(_guide_white, targets.get(_guide_white.get_instance_id(), 1.25))
	if _guide_blue != null:
		_tween_to(_guide_blue, targets.get(_guide_blue.get_instance_id(), 0.0))
	changed.emit()


func _tween_to(light: OmniLight3D, target: float) -> void:
	if absf(light.light_energy - target) < 0.005:
		return
	var key := light.get_instance_id()
	if _tweens.has(key) and (_tweens[key] as Tween).is_valid():
		(_tweens[key] as Tween).kill()
	var tw := create_tween()
	tw.tween_property(light, "light_energy", target, TWEEN_TIME)
	_tweens[key] = tw
