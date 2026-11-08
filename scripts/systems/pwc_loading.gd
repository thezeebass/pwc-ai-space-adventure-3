extends Node

## Observes the existing boot, intro and main-scene flow without changing
## those scripts. The browser cover is removed only after Godot has
## presented a real frame; otherwise the HTML shell would disappear as soon as
## the WASM/PCK download finished and expose the old grey gap.


func _enter_tree() -> void:
	# Autoloads enter before the main scene, but their _ready can run after the
	# boot scene's children. Subscribe here so the first intro is observed too.
	get_tree().node_added.connect(_on_node_added)


func _ready() -> void:
	_mark("loading.autoload")


func _on_node_added(node: Node) -> void:
	var script := node.get_script() as Script
	if script == null:
		return
	var file := script.resource_path.get_file()
	match file:
		"boot.gd":
			_mark("boot.added")
			node.ready.connect(_mark.bind("boot.ready"), CONNECT_ONE_SHOT)
		"intro_screen.gd":
			node.ready.connect(_on_intro_ready, CONNECT_ONE_SHOT)
			if node.has_signal("finished"):
				node.connect("finished", _on_intro_finished)
		"game.gd":
			_mark("main.added")
			node.ready.connect(_on_main_ready, CONNECT_ONE_SHOT)
		"kit_shell.gd", "station_dressing.gd", "ship_hull.gd", "ship_exterior.gd":
			var stage := file.get_basename()
			_mark(stage + ".begin")
			node.ready.connect(_mark.bind(stage + ".end"), CONNECT_ONE_SHOT)


func _on_intro_ready() -> void:
	_mark("intro.ready")
	_hide_after_draw()


func _on_intro_finished() -> void:
	var current := get_tree().current_scene
	if current == null:
		return
	var script := current.get_script() as Script
	if script != null and script.resource_path.get_file() == "boot.gd":
		_mark("boot.waiting_for_main")
		show_cover("Preparing the ship", "The briefing is complete. Loading decks, geometry and ship systems…")


func _on_main_ready() -> void:
	_mark("main.ready")
	_hide_after_draw()


func _hide_after_draw() -> void:
	await RenderingServer.frame_post_draw
	hide_cover()


func _mark(stage: String) -> void:
	var elapsed: int = Time.get_ticks_msec()
	print("[PWC_LOAD] %d ms | %s" % [elapsed, stage])
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"if (window.pwcLoading) window.pwcLoading.stage(%s, %d);" % [JSON.stringify(stage), elapsed])


func show_cover(title: String, detail: String) -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(
		"if (window.pwcLoading) window.pwcLoading.show(%s, %s);" % [JSON.stringify(title), JSON.stringify(detail)])


func hide_cover() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if (window.pwcLoading) window.pwcLoading.hide();")
