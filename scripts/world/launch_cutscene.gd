class_name LaunchCutscene
extends Node3D

## The departure, played from the helm.
##
## Three shots, and the sequence is built around one handoff. It opens at the
## helmsman's eye looking forward through the bridge glass - the planet, the
## station and the starfield the crew's bay windows have shown all game - then
## leaves the ship to watch it from outside as it gets under way.
##
## The last shot is an S around the stern: a sweep across the back of the ship,
## ignition at the end of it, and the reverse sweep out to the ship's left side
## while the three engines burn.
##
## The ship it shows is the corridor the crew actually walked: the kit walls and
## the bridge are real geometry built from these same numbers, so the vessel
## flying away is the vessel they have been inside, not a stand-in.
##
## The renderer is the WorldEnvironment every window already looks through, so
## this adds one camera, its own soft key, the three engine bells and their
## plumes - and touches nothing else: no new sky, no change to the station's
## lighting, no second starfield. The viewport is only taken over while the
## sequence runs, and the crew's own camera is restored on every exit path.

signal finished

const SHOT_INTERIOR_END := 1.6
const SHOT_REAR_END := 5.2
const PLUME_SHADER := "res://shaders/rocket_plume.gdshader"
## The last shot is one move: from behind the ship as the engines light, circling
## left around her to the port profile, then holding on the plumes.
const ARC_SETTLE_END := 13.2
const SHOT_END := 15.2

## The helmsman's eye, in the same coordinates the corridor itself uses, so the
## first shot lines up with the room the crew are standing in.
const BRIDGE_EYE := Vector3(0.0, 1.7, 24.2)

## Where the departure burn is lit. This is the HULL's stern, not the corridor's
## aft end: the ship the crew are inside runs 114 m along Z and its aft-most
## geometry is at Z -50.0, so an engine glow at the corridor's aft wall sits about
## 30 m inside the ship and throws its light on nothing the camera can see. Three
## metres behind that stern face and low, so the burn lands on the hull's own
## transom where its nozzles would be.
const ENGINE_GLOW := Vector3(0.0, 1.2, -52.0)

## THE THREE ENGINES.
##
## The hull's aft face is at Z -50.0 and the model carries its engine cluster
## there: two big nacelles low on the transom and a smaller third nozzle
## between and above them. These are measured off that cluster, not invented -
## a plume that starts beside a nozzle reads as a bug, however good the flame.
## Each nozzle carries a visible flame when the order to burn arrives. The
## plumes are geometry, not particles: a cone is deterministic, costs three
## draw calls and reads the same on web and in a headset, which matters for the
## one shot a crew sees exactly once.
const NOZZLE_POS: Array[Vector3] = [
	Vector3(-8.9, 1.9, -49.6),
	Vector3(0.0, 6.7, -49.6),
	Vector3(8.9, 1.9, -49.6),
]
## The centre nozzle is the smaller one; it scales its bell and its flame.
const NOZZLE_SIZE: Array[float] = [1.0, 0.72, 1.0]
const BELL_LENGTH := 3.2
## Long enough to read as thrust, short enough that the camera can hold the
## whole ship and its wake in one frame without the jets passing the lens.
var plume_length: float = 18.0

## THE PULL-OUT - the middle shot, and where the crew's exit from the ship is
## faked.
##
## This shot used to begin 11 m INSIDE the ship and travel out through the
## stern, and that is where the visible clipping came from. The hull imports as
## one closed mesh, so from inside it every hull face is a backface and is
## culled: the plating simply disappears and the camera is left looking at the
## module's own interior fittings hanging in space. None of that is meant to be
## seen from outside the ship.
##
## So the shot BEGINS outside the shell and never re-enters it. The hull's
## aft-most geometry is at Z -50.0, and both endpoints below are aft of that, so
## every frame of the pull-out is outside the ship by construction rather than by
## eye. These points moved when the ship model was replaced: the previous hull's
## stern was at Z -38.1, and leaving them where they were would have started the
## shot six metres inside the new one.
##
## What sells the exit is the cut in from the helm: the last inside frame is the
## crew's own view forward, and the first outside frame is the same heading with
## the ship now behind them and the burn lighting its stern.
##
## It ends exactly where the reveal arc begins, so the two shots are one
## continuous move and that join cannot drift apart.
const PULLOUT_EYE := Vector3(17.0, 7.5, -58.0)
const PULLOUT_END := Vector3(6.0, 6.4, -68.0)

## THE REVEAL - the last shot, and one move rather than an S.
##
## The engines light while the camera is still astern, looking straight down the
## wake at the three bells. From there the camera circles LEFT, one way only,
## round the ship's quarter to her port side, and settles on the whole 114 m hull
## in profile with the three jets trailing behind it.
##
## Nothing sweeps right at any point: the azimuth only ever runs one way, so the
## move reads as a single orbit rather than a pan out and back.
##
## The motion stays polar about the hull's long axis, so the ship turns into
## frame instead of shrinking. Height and aim are keyed separately, and look_at
## always gets Vector3.UP, so the horizon stays level and no roll is introduced.
##
## The first frame is the last frame of the pull-out, read off PULLOUT_END
## below, so the join between the two shots cannot jump.
##
## The ship, from the hull placement receipt: 114.0 m long, along Z from -50.0
## (stern) to 64.0 (bow), 38.4 m tall from Y -12.0, centred in Z at 7.0.
const ARC_CENTRE_Z := 7.0
## Azimuth, where 0 is abeam on the ship's left (+X) and -90 is dead astern.
## The sweep ends a few degrees aft of dead abeam: a three-quarter profile still
## reads as the whole hull in profile, and it keeps the stern clear of the frame
## edge so the wake stays in shot.
var arc_end_angle: float = -15.4
## 92 m out and aimed slightly aft of the hull's centre, so the frame holds the
## 114 m ship AND the flame behind it - aimed at the hull alone, the plumes ran
## off the right edge.
var arc_end_radius: float = 92.0
var arc_end_height: float = 20.0
const ARC_START_LOOK := Vector3(0.0, 1.5, 1.0)
var arc_end_look: Vector3 = Vector3(0.0, 5.0, -6.0)

var _camera: Camera3D = null
var _overlay: CanvasLayer = null
var _hud: CanvasLayer = null
var _player_camera: Camera3D = null
var _engine_glow: OmniLight3D = null
var _fill: DirectionalLight3D = null
var _plumes: Array[Node3D] = []
var _nozzle_lights: Array[OmniLight3D] = []
var _title_label: Label = null
var _caption_label: Label = null
var _caption_zone: String = ""
var _captions: Array[Dictionary] = []
var _elapsed: float = 0.0
var _running: bool = false


func _ready() -> void:
	_build_camera()
	_build_fill_light()
	_build_engine_glow()
	_build_engines()
	_build_overlay()
	set_overlay_visible(false)
	set_process(false)


## Called by the helm once the crew has ordered the launch.
func play() -> void:
	if _running:
		return
	_running = true
	## A replay (F9) starts from the top: without this the clock would still be
	## at the end of the previous run and the sequence would close on its first
	## frame.
	_elapsed = 0.0
	_caption_zone = ""
	set_overlay_visible(true)
	set_process(true)
	## Captured here rather than in _ready(): this is the last moment the crew's
	## camera is guaranteed to be the one rendering, and it has to be put back.
	_remember_player_camera()
	if _camera != null:
		_camera.global_position = BRIDGE_EYE
		_camera.look_at(BRIDGE_EYE + Vector3(0.0, 0.0, 1.0), Vector3.UP)
		_camera.current = true
	## The readout strip is for flying the ship, not for watching her leave: it
	## would sit over the last shot. It comes back with the controls on finish.
	_hud = get_node_or_null("../../UI/HUD") as CanvasLayer
	if _hud != null:
		_hud.visible = false
	## The sticks have no business over the last shot either: on a touchscreen
	## they are visible by their own always-on rule, so suppression - not the
	## mode switch - is what takes them off the screen for the departure. They
	## come back with the HUD on finish.
	var touch := get_node_or_null("../../UI/TouchControls") as TouchControls
	if touch != null:
		touch.set_suppressed(true)
	if _engine_glow != null:
		_engine_glow.light_energy = 0.6
	_drive_engines()
	## The input layer owns the screen, so the crew's look and move input cannot
	## fight the cutscene camera.
	InputRouter.set_ui_blocking(true)
	if OS.is_debug_build():
		print("[LaunchCutscene] departure started")


func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	_drive_shots()
	_advance_captions()
	_fade_overlay()
	if _elapsed >= SHOT_END:
		_finish()


## Shot 1 sits at the helm looking forward through the glass, including the
## ship's own bow in the lower frame. Shot 2 cuts to outside the stern - the
## crew's exit. Shot 3 is the S: across the back of the ship, ignition, then
## back the other way to the ship's left side with the plumes behind it.
func _drive_shots() -> void:
	if _camera == null:
		return
	if _elapsed < SHOT_INTERIOR_END:
		## A slow push forward at the helm, so the first shot is alive.
		var t: float = clampf(_elapsed / SHOT_INTERIOR_END, 0.0, 1.0)
		_camera.global_position = BRIDGE_EYE.lerp(BRIDGE_EYE + Vector3(0.0, 0.25, 1.1), t)
		_camera.look_at(BRIDGE_EYE + Vector3(0.0, -0.15, 40.0), Vector3.UP)
		_engine(0.6 + 0.8 * t)
	elif _elapsed < SHOT_REAR_END:
		## Outside the shell from the first frame to the last, so the hull is
		## never entered. The stern is still cold here: the burn is lit at the
		## end of the first sweep of the final shot.
		var t: float = clampf((_elapsed - SHOT_INTERIOR_END) / (SHOT_REAR_END - SHOT_INTERIOR_END), 0.0, 1.0)
		_camera.global_position = PULLOUT_EYE.lerp(PULLOUT_END, t)
		_camera.look_at(ARC_START_LOOK, Vector3.UP)
		_engine(1.2 + 1.2 * t)
	else:
		## The S around the stern: one sweep across the back, ignition at the
		## end of it, then the reverse sweep out to the ship's left profile.
		var start: Vector2 = _arc_start_offset()
		var azimuth: float
		var radius: float
		var height: float
		var look: Vector3
		var t: float = clampf((_elapsed - SHOT_REAR_END) / maxf(ARC_SETTLE_END - SHOT_REAR_END, 0.01), 0.0, 1.0)
		## Eased at both ends: the hold after ARC_SETTLE_END keeps the final pose.
		## The azimuth only ever decreases, so the camera circles one way round
		## the ship and never doubles back.
		var eased: float = smoothstep(0.0, 1.0, t)
		azimuth = lerpf(atan2(start.y, start.x), deg_to_rad(arc_end_angle), eased)
		radius = lerpf(start.length(), arc_end_radius, eased)
		height = lerpf(PULLOUT_END.y, arc_end_height, eased)
		look = ARC_START_LOOK.lerp(arc_end_look, eased)
		_camera.global_position = Vector3(
			cos(azimuth) * radius,
			height,
			ARC_CENTRE_Z + sin(azimuth) * radius)
		_camera.look_at(look, Vector3.UP)
		_engine(0.0)
		_drive_engines()
	_update_fill()


## Keeps the soft key pointing where the camera looks, and off while the shot is
## still inside the ship.
func _update_fill() -> void:
	if _fill == null or _camera == null:
		return
	var lit: bool = _elapsed >= SHOT_INTERIOR_END
	_fill.light_energy = 0.55 if lit else 0.0
	if lit:
		_fill.global_transform = Transform3D(_camera.global_transform.basis, _camera.global_position)


## The reveal arc is polar about the hull's long axis, so its opening frame is
## held as an offset from that axis: Vector2(x, z - ARC_CENTRE_Z). Reading it
## off PULLOUT_END is what keeps the join between the pull-out and the arc
## exact - the same point cannot drift out of agreement with itself the way two
## hand-copied sets of numbers would.
func _arc_start_offset() -> Vector2:
	return Vector2(PULLOUT_END.x, PULLOUT_END.z - ARC_CENTRE_Z)


## Developer helper, alongside the F9 replay: jump straight to a moment of the
## sequence and drive the shots to it, so a single frame can be inspected
## without watching the whole departure. Takes text because the editor's
## runtime transport passes every argument as a string.
func seek_to(text: String) -> void:
	play()
	_elapsed = maxf(float(text), 0.0)
	_drive_shots()
	_fade_overlay()
	## Held on that frame: the sequence would otherwise run on and finish.
	_running = false
	set_process(false)


func _engine(energy: float) -> void:
	if _engine_glow == null:
		return
	## The idle stern glow before ignition - see _drive_engines for the burn.
	_engine_glow.light_energy = energy * (0.92 + 0.08 * sin(_elapsed * 26.0))


## The burn. Three plumes grow out of the three bells at SHOT_REAR_END, each with
## its own flicker and its own light, so the ship reads as three engines rather
## than one wide glow - which is the whole point of the sweep across the back.
func _drive_engines() -> void:
	var thrust: float = _thrust_level()
	var flash: float = _ignition_flash_level()
	for i in _plumes.size():
		var plume: Node3D = _plumes[i]
		plume.visible = thrust > 0.02
		if not plume.visible:
			continue
		var wobble: float = 1.0 + 0.07 * sin(_elapsed * 27.0 + float(i) * 2.1)
		var width: float = 0.94 + 0.12 * thrust
		## The mesh is built in metres, so Z scales the burn from nothing to its
		## full length rather than stretching a unit stub into one.
		plume.scale = Vector3(width, width, maxf(thrust * wobble, 0.01))
	if _nozzle_lights.size() == _plumes.size():
		for i in _nozzle_lights.size():
			_nozzle_lights[i].light_energy = (2.2 + 2.6 * flash) * thrust
	if _engine_glow != null:
		_engine_glow.light_energy = (2.4 + 5.0 * flash) * thrust


## 0 before the order, then a quick ramp as the engines catch and settle. They
## light the moment the camera is clear of the hull and astern of the ship,
## which is where the sweep begins.
func _thrust_level() -> float:
	if _elapsed < SHOT_REAR_END:
		return 0.0
	var t: float = clampf((_elapsed - SHOT_REAR_END) / 0.5, 0.0, 1.0)
	return lerpf(0.45, 1.0, smoothstep(0.0, 1.0, t))


## A brief over-bright pulse riding on the first second of the burn, read only by
## the LIGHTS. It used to drive a glowing sphere on the cluster as well, and that
## sphere shrank from three metres to nothing: from astern it read as a white
## circle contracting in front of each exhaust. The light pulse is the part that
## belongs - it brightens the hull and the gas without drawing anything.
func _ignition_flash_level() -> float:
	if _elapsed < SHOT_REAR_END:
		return 0.0
	var t: float = clampf((_elapsed - SHOT_REAR_END) / 1.2, 0.0, 1.0)
	if t >= 1.0:
		return 0.0
	return (1.0 - t) * (1.0 - t)


## Developer shortcut. The departure is the one part of the game that cannot be
## reached in a few seconds - it needs all five systems and the helm - so tuning
## this shot would otherwise cost a full run per attempt. F9 replays it in place.
## Handled here rather than through InputMap, so a development-only key never
## has to appear in project settings.
func _unhandled_input(event: InputEvent) -> void:
	if _running:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		play()
		get_viewport().set_input_as_handled()


# --- Build --------------------------------------------------------------------

func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "CutsceneCamera"
	## Driven from _process, frame by frame: interpolating it would fight the
	## shot and add a physics tick of lag to every camera move.
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.fov = 70.0
	_camera.near = 0.1
	_camera.far = 6000.0
	add_child(_camera)


## The scene's sun sweeps a 240 s orbit, so where it stands when the crew reach
## the helm is luck: they can arrive with the whole stern in shadow and watch
## their own departure as a silhouette. This soft key rides with the cutscene
## camera and only from the pull-out onward, so the vessel being left is always
## legible without touching the station's lighting for the rest of the game.
func _build_fill_light() -> void:
	_fill = DirectionalLight3D.new()
	_fill.name = "CutsceneFill"
	_fill.light_color = Color(1.0, 0.93, 0.85)
	_fill.light_energy = 0.0
	_fill.shadow_enabled = false
	add_child(_fill)


## Behind the hull's own transom, where the engines are - see ENGINE_GLOW. The
## sun already lights the scene; this only has to read as the crew's own burn
## coming up.
func _build_engine_glow() -> void:
	_engine_glow = OmniLight3D.new()
	_engine_glow.name = "EngineGlow"
	_engine_glow.light_color = Color(1.0, 0.66, 0.32)
	_engine_glow.omni_range = 46.0
	_engine_glow.light_energy = 0.0
	_engine_glow.position = ENGINE_GLOW
	add_child(_engine_glow)


## The engine cluster: three plumes off the transom, and the lights they throw.
## Built here rather than in the hull scene because they only ever exist for
## this shot, and because the plumes are driven frame by frame from the shot's
## own clock.
##
## THE BELLS ARE NOT DRAWN. The hull carries its own engine cluster at the
## stern; adding modelled bells on top of it put three black funnels in front of
## the real nozzles, and the plume came out of the funnel instead of the engine.
## The bell's dimensions are still measured below, because the plume has to
## start where that recess ends - the geometry is used, the mesh is not.
func _build_engines() -> void:
	## Three layers, each with its own job: a wide, dim halo of cooling gas, the
	## orange body of the jet, and a short white core right at the bell. Their
	## alpha adds, so the cluster of three jets is bright where they overlap and
	## still keeps its edges.
	var haze_material := _flame_material(
		Color(1.0, 0.62, 0.26), Color(1.0, 0.18, 0.03), 0.40, 0.16,
		2.2, 0.15, 0.0, 1.0)
	var halo_material := _flame_material(
		Color(1.0, 0.72, 0.34), Color(1.0, 0.24, 0.04), 0.55, 0.30,
		2.2, 0.30, 0.0, 0.92)
	var outer_material := _flame_material(
		Color(1.0, 0.93, 0.74), Color(1.0, 0.44, 0.11), 1.10, 0.78,
		1.5, 0.65, 0.9, 1.0)
	var inner_material := _flame_material(
		Color(1.0, 1.0, 0.97), Color(1.0, 0.86, 0.52), 1.30, 0.70,
		2.8, 0.35, 0.4, 0.62)

	for i in NOZZLE_POS.size():
		var size_scale: float = NOZZLE_SIZE[i] if i < NOZZLE_SIZE.size() else 1.0
		var root := Node3D.new()
		root.name = "Nozzle%d" % (i + 1)
		root.position = NOZZLE_POS[i]
		add_child(root)

		## Measured, never added: see the note above the function.
		var bell_mesh := CylinderMesh.new()
		bell_mesh.top_radius = 2.2 * size_scale
		bell_mesh.bottom_radius = 1.2 * size_scale
		bell_mesh.height = BELL_LENGTH * (0.55 + 0.45 * size_scale)
		bell_mesh.radial_segments = 20
		bell_mesh.rings = 1
		bell_mesh.cap_top = false
		bell_mesh.cap_bottom = true

		var plume := Node3D.new()
		plume.name = "Plume"
		## The centre nozzle sits recessed in the stern, so its flame starts at
		## the mouth of that recess rather than at the hull face: started at the
		## face, the hull swallows it from every angle but dead astern.
		var recess: float = 0.8 if i == 1 else 0.0
		plume.position.z = -1.1 - recess
		plume.visible = false
		root.add_child(plume)
		_plumes.append(plume)

		## Three layers: a soft wide halo, the orange body of the flame, and a
		## hot core. Unshaded additive cones have no volume of their own, so the
		## layering is what stops the jet reading as a flat wedge.
		_plume_cone(plume, haze_material, 1.40 * size_scale, 1.0, 0.60)
		_plume_cone(plume, halo_material, 1.15 * size_scale, 0.92, 0.50)
		_plume_cone(plume, outer_material, 1.0 * size_scale, 1.0, 0.40)
		_plume_cone(plume, inner_material, 0.45 * size_scale, 0.62, 0.20)

		var light := OmniLight3D.new()
		light.name = "BurnLight"
		light.light_color = Color(1.0, 0.62, 0.28)
		light.omni_range = 34.0
		light.light_energy = 0.0
		light.position = Vector3(0.0, 0.0, -bell_mesh.height * 0.5)
		root.add_child(light)
		_nozzle_lights.append(light)


## One layer of flame, `length_scale` of the finished plume long. The plume
## holder's Z scale runs it out from the bell as the engines catch, so length
## and width still animate separately.
func _plume_cone(parent: Node3D, material: Material, radius_scale: float,
		length_scale: float, bulge: float) -> void:
	var cone := MeshInstance3D.new()
	var length: float = length_scale * plume_length
	cone.mesh = _plume_mesh(1.0 * radius_scale, length, bulge)
	cone.material_override = material
	cone.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	## The half-length offset puts the cone's mouth on the holder and its tip at
	## -length, so a holder scale of Z = 24 runs the flame 24 m behind the bell.
	cone.position.z = -length * 0.5
	parent.add_child(cone)


## The flame itself, built rather than borrowed from a primitive.
##
## A straight cone is the one shape exhaust never is: it leaves the bell, bulges
## as the gas expands, and then thins into a wisp. That is the profile below,
## and it is why four identical mesh layers still read as one volume - they are
## the same plume at four widths and four lengths.
##
## Normals are computed from the profile rather than left to the surface: the
## shader thins the flame where it is seen edge-on, and it needs to know which
## way the gas is facing to do it. They are built in the mesh's own metres for
## the same reason - normals taken from a stretched stub point down the jet, and
## the shader would fade the whole flame out as if it were facing away.
func _plume_mesh(radius: float, length: float, bulge: float) -> ArrayMesh:
	const SEGMENTS := 20
	const RINGS := 9
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	## Triangles are emitted unshared rather than indexed: the plume is a few
	## thousand vertices either way, and the arrays go straight into the surface
	## with nothing left to infer.
	for j in RINGS:
		for i in SEGMENTS:
			var t0: float = float(j) / float(RINGS)
			var t1: float = float(j + 1) / float(RINGS)
			var a0: float = TAU * float(i) / float(SEGMENTS)
			var a1: float = TAU * float(i + 1) / float(SEGMENTS)
			_plume_vertex(vertices, normals, uvs, radius, length, bulge, t0, a0)
			_plume_vertex(vertices, normals, uvs, radius, length, bulge, t1, a0)
			_plume_vertex(vertices, normals, uvs, radius, length, bulge, t1, a1)
			_plume_vertex(vertices, normals, uvs, radius, length, bulge, t0, a0)
			_plume_vertex(vertices, normals, uvs, radius, length, bulge, t1, a1)
			_plume_vertex(vertices, normals, uvs, radius, length, bulge, t0, a1)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _plume_vertex(vertices: PackedVector3Array, normals: PackedVector3Array,
		uvs: PackedVector2Array, radius: float, length: float, bulge: float,
		t: float, angle: float) -> void:
	var r: float = radius * _plume_radius(t, bulge)
	var slope: float = (radius * _plume_radius(minf(t + 0.01, 1.0), bulge)
		- radius * _plume_radius(maxf(t - 0.01, 0.0), bulge)) / 0.02
	var normal := Vector3(length * cos(angle), -slope, length * sin(angle))
	vertices.append(Vector3(cos(angle) * r, (t - 0.5) * length, sin(angle) * r))
	normals.append(normal.normalized() if normal.length() > 0.0001 else Vector3.UP)
	uvs.append(Vector2(angle / TAU, t))


## The flame leaves the bell a little narrower than the bell itself, then flares
## steadily as the gas expands. It is the shader's fade, not the geometry, that
## ends the plume: a shape that closes to a point reads as a blade.
func _plume_radius(t: float, bulge: float) -> float:
	return 0.92 + bulge * pow(maxf(t, 0.0), 0.75)


## The exhaust material: hot at the nozzle, cooling along its length, and soft
## at the edge. See shaders/rocket_plume.gdshader. The height is the cone's own
## mesh height, because the shader reads the gradient off model space: the
## layers share the material type but not their size.
func _flame_material(core: Color, flame: Color, energy: float, alpha: float,
		tip_fade: float = 1.5, turbulence: float = 0.45, collar: float = 0.0,
		height: float = 1.0) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(PLUME_SHADER) as Shader
	material.set_shader_parameter("core_color", core)
	material.set_shader_parameter("flame_color", flame)
	material.set_shader_parameter("body_energy", energy)
	material.set_shader_parameter("opacity", alpha)
	material.set_shader_parameter("tip_fade", tip_fade)
	material.set_shader_parameter("turbulence", turbulence)
	material.set_shader_parameter("collar", collar)
	## `height` arrives as a share of the finished plume, the same units
	## _plume_cone builds the mesh in.
	material.set_shader_parameter("cone_height", height * plume_length)
	return material


## A plain additive ball of light, for the moment of ignition. The plume shader
## assumes a cone, so the flash gets its own material rather than a gradient
## mapped onto a sphere.
func _glow_material(color: Color, energy: float, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	material.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, alpha)
	return material


func _build_overlay() -> void:
	## The captions live on their own CanvasLayer, not on this node. This node is
	## a Node3D, so the camera and the engine glow belong to the 3D scene;
	## hanging them off a CanvasLayer would put them outside it. Only the text
	## is 2D.
	_overlay = CanvasLayer.new()
	_overlay.name = "Overlay"
	_overlay.layer = 90
	add_child(_overlay)

	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(root)

	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.add_theme_font_size_override("font_size", 30)
	_title_label.modulate = Color(1.0, 0.88, 0.55)
	_title_label.position = Vector2(64.0, 58.0)
	root.add_child(_title_label)

	_caption_label = Label.new()
	_caption_label.name = "Caption"
	_caption_label.add_theme_font_size_override("font_size", 30)
	_caption_label.modulate = Color(0.92, 0.87, 0.82)
	_caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_caption_label)
	_place_caption("bottom")

	_captions = [
		{"at": 0.0, "title": "", "zone": "centre",
			"text": "Now equipped with a mandate that puts responsibility in the right hands,"},
		{"at": 5.0, "title": "", "zone": "bottom",
			"text": "The Adamant Verity's engines roar to life"},
		{"at": 8.2, "title": "", "zone": "bottom",
			"text": "The ship continues on its journey home, with man and machine working together."},
		{"at": 12.0, "title": "", "zone": "bottom",
			"text": "The Intelligent Operating Model is live."},
	]


## Subtitle placement per shot. The bridge shot holds its caption dead centre,
## over the black of space through the glass; everything from ignition on rides
## the bottom band - the block sits inside the bottom 15% of the screen with
## the bottom 5% kept clear, so the ship and the plumes are never covered.
func _place_caption(zone: String) -> void:
	if zone == "centre":
		_caption_label.set_anchors_preset(Control.PRESET_CENTER)
		_caption_label.position = Vector2(-390.0, -110.0)
		_caption_label.size = Vector2(780.0, 220.0)
		_caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	else:
		_caption_label.set_anchor(SIDE_LEFT, 0.5)
		_caption_label.set_anchor(SIDE_RIGHT, 0.5)
		_caption_label.anchor_top = 0.80
		_caption_label.anchor_bottom = 0.95
		_caption_label.offset_left = -390.0
		_caption_label.offset_right = 390.0
		_caption_label.offset_top = 0.0
		_caption_label.offset_bottom = 0.0
		_caption_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM


## The 3D nodes stay live while the sequence is closed and only the text
## toggles, because the camera and the light have to exist in the tree before
## play() can make them current.
func set_overlay_visible(value: bool) -> void:
	if _overlay != null:
		_overlay.visible = value


# --- Captions and exit ---------------------------------------------------------

func _advance_captions() -> void:
	for entry in _captions:
		if _elapsed >= float(entry["at"]):
			var zone: String = String(entry.get("zone", "bottom"))
			if zone != _caption_zone:
				_caption_zone = zone
				_place_caption(zone)
			var title: String = String(entry["title"])
			var body: String = String(entry["text"])
			if _title_label != null and _title_label.text != title:
				_title_label.text = title
			if _caption_label != null and _caption_label.text != body:
				_caption_label.text = body


## The text eases out over the last seconds so the return of control is a reveal
## rather than a cut.
func _fade_overlay() -> void:
	var fade_in: float = clampf(_elapsed / 0.6, 0.0, 1.0)
	var fade_out: float = clampf((SHOT_END - _elapsed) / 2.0, 0.0, 1.0)
	var alpha: float = minf(fade_in, fade_out)
	if _title_label != null:
		var a: Color = _title_label.modulate
		_title_label.modulate = Color(a.r, a.g, a.b, alpha)
	if _caption_label != null:
		var b: Color = _caption_label.modulate
		_caption_label.modulate = Color(b.r, b.g, b.b, alpha)


func _finish() -> void:
	if not _running:
		return
	_running = false
	set_process(false)
	set_overlay_visible(false)
	for plume in _plumes:
		plume.visible = false
	for light in _nozzle_lights:
		light.light_energy = 0.0
	if _engine_glow != null:
		_engine_glow.light_energy = 0.0
	if _fill != null:
		_fill.light_energy = 0.0
	if _hud != null and is_instance_valid(_hud):
		_hud.visible = true
	var touch := get_node_or_null("../../UI/TouchControls") as TouchControls
	if touch != null:
		touch.set_suppressed(false)
	## Order matters: the crew's camera has to be made current BEFORE this one
	## stands down, or the viewport would briefly have no camera at all.
	if _player_camera != null and is_instance_valid(_player_camera):
		_player_camera.current = true
	if _camera != null:
		_camera.current = false
	InputRouter.set_ui_blocking(false)
	if OS.is_debug_build():
		print("[LaunchCutscene] departure complete; control returned")
	finished.emit()


## The camera that was rendering before the cutscene took over.
func _remember_player_camera() -> void:
	_player_camera = null
	if _camera == null:
		return
	var viewport := _camera.get_viewport()
	if viewport != null:
		_player_camera = viewport.get_camera_3d()
	if _player_camera == _camera:
		## A previous dev seek left the cutscene camera current: it is not the
		## camera to hand control back to.
		_player_camera = null
	if _player_camera != null:
		return
	for node in get_tree().get_nodes_in_group("player_camera"):
		if node is Camera3D:
			_player_camera = node as Camera3D
			return
