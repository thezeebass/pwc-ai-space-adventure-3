class_name TextZoom
extends RefCounted

## UI text zoom: the pause menu's TEXT SIZE choice (S 24 / M 28 / L 30)
## applied as a ratio over every font-size override in the registered
## screens. Screens register their root once, at ready - their builders
## always build at design sizes - and the first registration captures each
## override's design value as the base that every setting scales. The pause
## menu registers too, so changing the setting reshapes the menu itself,
## live, while you watch.

static var _roots: Array[Control] = []
static var _bases: Dictionary = {}


## Register a screen root and apply the current setting to it immediately.
static func register(root: Control) -> void:
	for existing in _roots:
		if existing == root:
			return
	_roots.append(root)
	apply(root)


## Change the setting and re-derive every registered screen in one pass.
static func set_size(size: int) -> void:
	Brand.info_text_size = size
	apply_all()


static func apply_all() -> void:
	for root in _roots:
		if is_instance_valid(root):
			apply(root)


## Walk a screen (or any subtree) and re-derive every font-size override
## from its captured design base. Overrides not seen before are captured
## now - their current value is their design size.
static func apply(root: Control) -> void:
	var ratio: float = float(Brand.info_text_size) / 30.0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is Control and node.has_theme_font_size_override("font_size"):
			var key := "%d|%s" % [node.get_instance_id(), node.get_path()]
			if not _bases.has(key):
				_bases[key] = node.get_theme_font_size("font_size")
			node.add_theme_font_size_override(
				"font_size", maxi(int(round(float(_bases[key]) * ratio)), 12))


## A freshly created control (a typed readout line, a rebuilt row) starts at
## its design size; sweep just that node so it matches the screen around it.
static func apply_node(node: Control) -> void:
	var ratio: float = float(Brand.info_text_size) / 30.0
	if node.has_theme_font_size_override("font_size"):
		var key := "%d|%s" % [node.get_instance_id(), node.get_path()]
		if not _bases.has(key):
			_bases[key] = node.get_theme_font_size("font_size")
		node.add_theme_font_size_override(
			"font_size", maxi(int(round(float(_bases[key]) * ratio)), 12))
