extends Node
## Netlify leaderboard client. Add as an Autoload singleton
## (Project > Project Settings > Autoload > pick this file, name it
## "LeaderboardClient"), then call it from anywhere.
##
## Signals:
##   leaderboard_received(entries: Array, total_players: int)
##   rank_preview_received(rank: int, total_players: int)
##   submit_completed(result: Dictionary)  # rank, total_players, entry, neighbours
##   request_failed(action: String, message: String)

signal leaderboard_received(entries: Array, total_players: int)
signal rank_preview_received(rank: int, total_players: int)
signal submit_completed(result: Dictionary)
signal request_failed(action: String, message: String)

## Your Netlify site's URL. The Android build must use the full https://
## address; the web build can use the same one.
## Where the leaderboard API lives. Web builds point at their own origin, so
## the same deploy works on any host; native builds (Android) need the absolute
## address. The origin is read through Engine.get_singleton because
## JavaScriptBridge only exists in web builds and a direct reference would not
## parse elsewhere.
var BASE_URL: String = "https://pwc-iom-space.netlify.app/api"
const QUEUE_PATH := "user://leaderboard_queue.json"

var _queue: Array = []
var _flushing := false


func _ready() -> void:
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var js_bridge: Object = Engine.get_singleton("JavaScriptBridge")
		var origin := str(js_bridge.eval("window.location.origin", true))
		if origin.begins_with("http"):
			BASE_URL = origin + "/api"
	_load_queue()
	if _queue.size() > 0:
		_flush()  # retry submissions that were saved while offline


# --- Public API ---------------------------------------------------------------

## Fetch the current top entries ("before" board).
func fetch_leaderboard(mode := "default", limit := 50) -> void:
	var url := "%s/leaderboard?mode=%s&limit=%d" % [BASE_URL, mode.uri_encode(), limit]
	var res: Dictionary = await _get_json(url)
	if res.ok:
		leaderboard_received.emit(res.data.get("entries", []), int(res.data.get("total_players", 0)))
	else:
		request_failed.emit("leaderboard", res.error)


## Where WOULD this score land? Call before submitting ("projected rank").
func fetch_rank_preview(score: int, mode := "default") -> void:
	var url := "%s/rank?mode=%s&score=%d" % [BASE_URL, mode.uri_encode(), score]
	var res: Dictionary = await _get_json(url)
	if res.ok:
		rank_preview_received.emit(int(res.data.get("rank", 0)), int(res.data.get("total_players", 0)))
	else:
		request_failed.emit("rank_preview", res.error)


## Queue a score for submission. Safe to call with no connectivity: the
## payload is written to disk and retried on the next launch or next submit.
func submit_score(player_name: String, score: int, mode := "default", completion_seconds := 0, email := "") -> void:
	var payload := {
		"name": player_name.strip_edges(),
		"score": score,
		"mode": mode,
		"completion_seconds": completion_seconds,
		"submission_id": _uuid4(),
		## The email is stored with the entry and never echoed back - the board
		## reads rank, pilot and score only.
		"email": email.strip_edges(),
	}
	_queue.append(payload)
	_save_queue()
	_flush()


## Manually retry whatever is still queued (e.g. from a "Retry" button).
func flush_queue() -> void:
	_flush()


# --- Internals ----------------------------------------------------------------

func _flush() -> void:
	if _flushing:
		return
	_flushing = true
	while _queue.size() > 0:
		var res: Dictionary = await _post_json(BASE_URL + "/submit", _queue[0])
		if not res.ok:
			request_failed.emit("submit", res.error)
			break  # offline or server down — keep the rest queued
		_queue.pop_front()
		_save_queue()
		submit_completed.emit(res.data)
	_flushing = false


func _get_json(url: String) -> Dictionary:
	var r := HTTPRequest.new()
	add_child(r)
	var err := r.request(url)
	if err != OK:
		r.queue_free()
		return {"ok": false, "error": "could not start request (%d)" % err}
	var completed: Array = await r.request_completed
	r.queue_free()
	return _parse_response(completed)


func _post_json(url: String, payload: Dictionary) -> Dictionary:
	var r := HTTPRequest.new()
	add_child(r)
	var err := r.request(
		url,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if err != OK:
		r.queue_free()
		return {"ok": false, "error": "could not start request (%d)" % err}
	var completed: Array = await r.request_completed
	r.queue_free()
	return _parse_response(completed)


func _parse_response(completed: Array) -> Dictionary:
	var result: int = completed[0]
	var code: int = completed[1]
	var body: PackedByteArray = completed[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "network error (%d)" % result}
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if code < 200 or code >= 300:
		var msg := "HTTP %d" % code
		if typeof(data) == TYPE_DICTIONARY and data.has("error"):
			msg = "%s: %s" % [msg, data["error"]]
		return {"ok": false, "error": msg}
	if typeof(data) != TYPE_DICTIONARY:
		return {"ok": false, "error": "bad response body"}
	return {"ok": true, "data": data}


func _load_queue() -> void:
	if not FileAccess.file_exists(QUEUE_PATH):
		return
	var f := FileAccess.open(QUEUE_PATH, FileAccess.READ)
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) == TYPE_ARRAY:
		_queue = data


func _save_queue() -> void:
	var f := FileAccess.open(QUEUE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_queue))


## Godot has no built-in UUID generator; roll a v4 UUID from crypto bytes.
func _uuid4() -> String:
	var b := Crypto.new().generate_random_bytes(16)
	b[6] = (b[6] & 0x0F) | 0x40  # version 4
	b[8] = (b[8] & 0x3F) | 0x80  # variant 1
	var h := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)
	]
