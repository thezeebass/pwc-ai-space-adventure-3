class_name Sfx
extends RefCounted

## Every sound in the game, in one place.
##
## The players are SCENE NODES in main.tscn (the looping beds "sfx_ambience" and
## "sfx_music", the one-shots "sfx_voice") rather than being created on demand at
## runtime. That is the whole point of this revision:
##
## Adding a child to the scene root from another node's _ready() fails with
## "Parent node is busy setting up children, add_child() failed", and a play()
## on a player that never entered the tree then fails with "Playback can only
## happen when a node is inside the scene tree". That is exactly how the ambience
## came out silent. Scene nodes exist in the tree before any script's _ready()
## runs, so there is no timing window at all.
##
## If the scene nodes are ever missing, this falls back to creating a player
## under the scene root, deferred, and starts it when it actually enters the
## tree - so a one-shot is never silently dropped.

const COMPUTER := "res://assets/audio/computer_opening.mp3"
const DOOR := "res://assets/audio/door_opening.mp3"
const AMBIENCE := "res://assets/audio/space_ambience.mp3"
const MUSIC := "res://assets/audio/spacemusic.mp3"

const VOICE_GROUP := "sfx_voice"
const AMBIENCE_GROUP := "sfx_ambience"
const MUSIC_GROUP := "sfx_music"

## THE MIX. A level is written as a fraction of full scale because that is how a
## mix gets discussed, and the decibel value is derived from it rather than typed
## beside it, so the two cannot drift apart.
##
## Do not read a percentage as decibels. The conversion is logarithmic, so half
## scale is -6 dB and a third is about -10.5 dB rather than -50 and -70. Two of
## these sit much lower in decibels than their percentage suggests, which is why
## the arithmetic is done here rather than guessed at by hand.
const VOICE_LEVEL := 0.50
const AMBIENCE_LEVEL := 0.30
const MUSIC_LEVEL := 0.60

## THE MIXER. Three channels - music, ambience and sfx - each with its own mute
## and its own fader, because "turn the music down" and "turn the game down" are
## different requests and one global volume cannot answer both.
##
## The fader is a user multiplier (0..1) applied on top of each sound's design
## level, so a fader at 1.0 plays the mix as authored and a fader at 0.3 pulls
## that channel to thirty percent of it. Mute is a volume change, not a stop:
## a bed keeps playing at the mute floor so unmuting brings the track back
## exactly where it was rather than restarting it.
const CHANNELS: Array[String] = ["music", "ambience", "sfx"]
const CHANNEL_NAMES := {
	"music": "MUSIC",
	"ambience": "AMBIENCE",
	"sfx": "SFX",
}
const CHANNEL_ICONS := {
	"music": "note",
	"ambience": "waves",
	"sfx": "bolt",
}

const MUTE_DB := -80.0

## THE MIXER'S MEMORY. Faders and mutes are written to user://settings.cfg the
## moment they move, and read back at boot, so the mix the crew leaves behind is
## the mix they come back to. It sits beside the progress save, not inside it:
## mixer state is a preference about HOW the session sounds, while the progress
## save is a record of WHAT was decided.
const SETTINGS_PATH := "user://settings.cfg"

## THE HOUSE MIX. Every channel starts audible at a deliberate level - sfx 30%,
## ambience 20%, music 30% - so a first run has room tone and a soundtrack that
## sit under the ship rather than over it. The faders are all still there; these
## are only where they are found.
static var music_muted: bool = false
static var ambience_muted: bool = false
static var sfx_muted: bool = false

static var music_volume: float = 0.10
static var ambience_volume: float = 0.15
static var sfx_volume: float = 0.80

## One-shots are spread over the scene's voice players so a console opening over
## a door does not cut the first sound short.
static var _next: int = 0
static var _cache: Dictionary = {}

## Fallback players, only used if the scene has none. The looping beds keep one
## per group, so a scene missing its music node can never be handed the ambience
## player and left with no ambience at all.
static var _spare: Array[AudioStreamPlayer] = []
static var _spare_loops: Dictionary = {}
static var _pending: Dictionary = {}


## Fire a one-shot. Safe to call from anywhere, including during _ready.
static func play(path: String, level: float = VOICE_LEVEL) -> void:
	var player: AudioStreamPlayer = _free_voice()
	if player == null:
		push_warning("Sfx: no voice player available for '%s'." % path)
		return
	var stream: AudioStream = _stream(path, false)
	if stream == null:
		return
	player.stream = stream
	_apply_level(player, "sfx", level)
	player.play()


## The room tone, running under everything for the whole session.
static func play_ambience(path: String = AMBIENCE, level: float = AMBIENCE_LEVEL) -> void:
	_start_loop(AMBIENCE_GROUP, path, level)


## The soundtrack. Same contract as the ambience, and deliberately a SEPARATE
## player: both beds run at once, so they cannot share one.
static func play_music(path: String = MUSIC, level: float = MUSIC_LEVEL) -> void:
	_start_loop(MUSIC_GROUP, path, level)


static func stop_ambience() -> void:
	_stop_loop(AMBIENCE_GROUP)


static func stop_music() -> void:
	_stop_loop(MUSIC_GROUP)


# --- The mixer ------------------------------------------------------------------

## The music switch. Every player carrying the music group is retuned, and the
## static flag is what a future loop start reads, so the state survives a scene
## reload without anyone having to remember to re-apply it.
static func set_music_muted(muted: bool) -> void:
	set_channel_muted("music", muted)


static func toggle_music_muted() -> bool:
	return toggle_channel_muted("music")


static func channel_is_muted(channel: String) -> bool:
	match channel:
		"music":
			return music_muted
		"ambience":
			return ambience_muted
		"sfx":
			return sfx_muted
	return false


## Write the mixer to disk. Called on every fader move and mute flip: the write
## is tiny, so persisting continuously costs nothing and guarantees even a
## crash between sessions loses no preference.
static func save_settings() -> void:
	var config := ConfigFile.new()
	for channel in CHANNELS:
		config.set_value("mixer", channel + "_muted", channel_is_muted(channel))
		config.set_value("mixer", channel + "_volume", channel_volume(channel))
	config.save(SETTINGS_PATH)


## Read the mixer back from disk. A missing file - a first run, or a cache the
## browser has swept - falls back to the authored defaults without complaint.
static func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	for channel in CHANNELS:
		var muted: bool = bool(config.get_value("mixer", channel + "_muted", channel_is_muted(channel)))
		var volume: float = float(config.get_value("mixer", channel + "_volume", channel_volume(channel)))
		set_channel_muted(channel, muted)
		set_channel_volume(channel, volume)


static func set_channel_muted(channel: String, muted: bool) -> void:
	match channel:
		"music":
			music_muted = muted
		"ambience":
			ambience_muted = muted
		"sfx":
			sfx_muted = muted
	_apply_channel(channel)
	save_settings()


static func toggle_channel_muted(channel: String) -> bool:
	set_channel_muted(channel, not channel_is_muted(channel))
	return channel_is_muted(channel)


static func channel_volume(channel: String) -> float:
	match channel:
		"music":
			return music_volume
		"ambience":
			return ambience_volume
		"sfx":
			return sfx_volume
	return 1.0


## Set one channel's fader. Every player in that channel is retuned at once, so
## a fader move is heard immediately rather than on the next sound.
static func set_channel_volume(channel: String, value: float) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	match channel:
		"music":
			music_volume = clamped
		"ambience":
			ambience_volume = clamped
		"sfx":
			sfx_volume = clamped
	_apply_channel(channel)
	save_settings()


static func _group_for(channel: String) -> String:
	match channel:
		"music":
			return MUSIC_GROUP
		"ambience":
			return AMBIENCE_GROUP
	return VOICE_GROUP


static func _channel_for_group(group: String) -> String:
	match group:
		MUSIC_GROUP:
			return "music"
		AMBIENCE_GROUP:
			return "ambience"
	return "sfx"


## The decibels for a sound at its design level, through the channel's fader
## and mute. A muted channel plays at the mute floor; an unmuted one multiplies
## the design level by the fader.
static func _db_for(channel: String, level: float) -> float:
	if channel_is_muted(channel):
		return MUTE_DB
	return level_to_db(level * channel_volume(channel))


## Stamp a player with its design level and the decibels that follow from the
## channel's current fader. The meta is what lets a later fader move re-derive
## the level for a sound that is already playing.
static func _apply_level(player: AudioStreamPlayer, channel: String, level: float) -> void:
	player.set_meta("sfx_base_level", level)
	player.volume_db = _db_for(channel, level)


## Retune every player in a channel: beds and one-shots alike. This is what a
## mute toggle or a fader move lands on.
static func _apply_channel(channel: String) -> void:
	var tree: SceneTree = _tree()
	if tree == null:
		return
	var group := _group_for(channel)
	for node in tree.get_nodes_in_group(group):
		if node is AudioStreamPlayer:
			var player: AudioStreamPlayer = node
			if player.has_meta("sfx_base_level"):
				_apply_level(player, channel, player.get_meta("sfx_base_level"))
	var spare: AudioStreamPlayer = _spare_loops.get(group, null)
	if spare != null and is_instance_valid(spare) and spare.has_meta("sfx_base_level"):
		_apply_level(spare, channel, spare.get_meta("sfx_base_level"))


## Start a looping bed. Safe to call more than once: a call while it is already
## playing does nothing, which keeps it seamless across a scene reload. The bed
## starts at the level the channel's mixer currently asks for, so a boot with
## music muted starts the bed at the mute floor instead of blasting the mix and
## then being pulled down.
static func _start_loop(group: String, path: String, level: float) -> void:
	var player: AudioStreamPlayer = _loop_voice(group, path, level)
	if player == null:
		## A fresh fallback player is added deferred and starts itself on
		## tree_entered, so "no player yet" here is a bed on its way, not a
		## failure. Warning about it made every boot look broken.
		if _spare_loops.has(group) or _pending.has(group):
			return
		push_warning("Sfx: no player in group '%s' available for '%s'." % [group, path])
		return
	if player.playing:
		return
	## The fallback player is added deferred, so it can still be a frame away from
	## entering the tree. Playing it now would error, so its tree_entered handler
	## starts it instead.
	if not player.is_inside_tree():
		return
	player.play()


static func _stop_loop(group: String) -> void:
	var tree: SceneTree = _tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group(group):
		if node is AudioStreamPlayer:
			(node as AudioStreamPlayer).stop()
	var spare: AudioStreamPlayer = _spare_loops.get(group, null)
	if spare != null and is_instance_valid(spare):
		spare.stop()


## A level expressed as a fraction of full scale, as decibels. Decibels are
## logarithmic, so this is arithmetic rather than a guess: 0.5 is -6 dB and 0.3
## is about -10.5 dB. The floor exists only so that a level of exactly zero
## cannot produce a negative infinity.
static func level_to_db(level: float) -> float:
	return linear_to_db(clampf(level, 0.0001, 1.0))


## The player for a looping bed. Prefers the scene node carrying that group;
## otherwise creates one deferred and starts it on tree_entered, so a bed is
## never silently dropped.
static func _loop_voice(group: String, path: String, level: float) -> AudioStreamPlayer:
	var tree: SceneTree = _tree()
	if tree == null:
		return null
	var channel := _channel_for_group(group)
	for node in tree.get_nodes_in_group(group):
		if node is AudioStreamPlayer:
			var player: AudioStreamPlayer = node
			if player.stream == null:
				player.stream = _stream(path, true)
			## Stamp the design level and the current mix every time. A bed
			## saved with a stream already on it would otherwise keep the
			## volume it was saved with and quietly ignore the mixer.
			_apply_level(player, channel, level)
			## A bed that began on the boot screen (before this scene had its
			## own players) hands the track over instead of playing twice.
			var carried: AudioStreamPlayer = _spare_loops.get(group, null)
			if carried != null and is_instance_valid(carried):
				if carried.playing:
					player.play(carried.get_playback_position())
				carried.stop()
				_spare_loops.erase(group)
				_pending.erase(group)
			return player
	var spare: AudioStreamPlayer = _spare_loops.get(group, null)
	if spare != null and is_instance_valid(spare):
		return spare
	spare = AudioStreamPlayer.new()
	spare.name = "SfxLoop_%s" % group
	spare.add_to_group(group)
	_spare_loops[group] = spare
	_pending[group] = {"path": path, "level": level}
	spare.tree_entered.connect(_on_spare_loop_ready.bind(group), Object.CONNECT_ONE_SHOT)
	tree.root.add_child.call_deferred(spare)
	return null


static func _on_spare_loop_ready(group: String) -> void:
	var spare: AudioStreamPlayer = _spare_loops.get(group, null)
	if spare == null or not is_instance_valid(spare):
		return
	var pending: Dictionary = _pending.get(group, {})
	var stream: AudioStream = _stream(String(pending.get("path", "")), true)
	if stream == null:
		return
	spare.stream = stream
	_apply_level(spare, _channel_for_group(group), float(pending.get("level", 0.5)))
	if not spare.playing:
		spare.play()


## A voice for a one-shot: an idle scene player, else round-robin over them, else
## a spare created under the scene root.
static func _free_voice() -> AudioStreamPlayer:
	var tree: SceneTree = _tree()
	if tree == null:
		return null
	var voices: Array[Node] = tree.get_nodes_in_group(VOICE_GROUP)
	for node in voices:
		if node is AudioStreamPlayer and not (node as AudioStreamPlayer).playing:
			return node
	if not voices.is_empty():
		_next = (_next + 1) % voices.size()
		return voices[_next]
	for player in _spare:
		if is_instance_valid(player) and not player.playing:
			return player
	if _spare.size() >= 4:
		return _spare[0]
	var created := AudioStreamPlayer.new()
	created.name = "SfxVoice_%d" % _spare.size()
	created.add_to_group(VOICE_GROUP)
	_spare.append(created)
	tree.root.add_child.call_deferred(created)
	return created


## Loads and caches one stream. MP3 and Ogg both need their loop flag set at
## runtime, because the import setting cannot be read back from a script.
static func _stream(path: String, loop: bool) -> AudioStream:
	var cached: AudioStream = _cache.get(path, null)
	if cached != null:
		## The loop flag is re-applied rather than assumed. load() hands back ONE
		## shared resource per path, so without this, whichever caller asked last
		## would decide whether a bed loops.
		if loop:
			_apply_loop(cached)
		return cached
	var resource: Resource = load(path)
	if resource == null or not (resource is AudioStream):
		return null
	cached = resource as AudioStream
	if loop:
		_apply_loop(cached)
	_cache[path] = cached
	return cached


static func _apply_loop(stream: AudioStream) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true


## A one-line report of the audio state, for the boot log. Read-only: it proves
## each clip resolves and whether the beds are actually running at the level the
## mix asks for. The percentage is reported beside the decibels, because the
## conversion is logarithmic and nobody should have to do it in their head.
static func debug_state() -> String:
	var tree: SceneTree = _tree()
	if tree == null:
		return "no scene tree"
	var parts: Array[String] = []
	for channel in CHANNELS:
		var muted: String = "muted" if channel_is_muted(channel) else "%d%%" % int(round(channel_volume(channel) * 100.0))
		parts.append("%s %s [%s]" % [String(CHANNEL_NAMES[channel]), muted, _bed_state(_group_for(channel))])
	parts.append("voices=%d" % tree.get_nodes_in_group(VOICE_GROUP).size())
	parts.append("clips: computer=%s door=%s music=%s" % [
		str(_stream(COMPUTER, false) != null),
		str(_stream(DOOR, false) != null),
		str(_stream(MUSIC, true) != null),
	])
	return " | ".join(parts)


static func _bed_state(group: String) -> String:
	var tree: SceneTree = _tree()
	if tree == null:
		return "no tree"
	for node in tree.get_nodes_in_group(group):
		if node is AudioStreamPlayer:
			var player: AudioStreamPlayer = node
			if player.playing:
				return "playing %.1fdB" % player.volume_db
			return "stopped"
	return "no player"


static func _tree() -> SceneTree:
	var loop: MainLoop = Engine.get_main_loop()
	return loop as SceneTree
