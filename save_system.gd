class_name SaveSystem extends Node
## Supabase cloud saves. The shared Gogi project enforces email confirmation, so the game
## persists via two prefixed SECURITY DEFINER RPCs keyed by a per-device secret token
## (128-bit, kept in localStorage) — the table itself stays RLS-locked to authenticated.
## Anon key is a public client credential by design.

const SB_URL := "https://xhhmxabftbyxrirvvihn.supabase.co"
const SB_ANON := "sb_publishable_NZHoIxqqpSvVBP8MrLHCYA_gmg1AbN-"
const RPC_SAVE := "usr_nmexs7bytxq2_verdance_save"
const RPC_LOAD := "usr_nmexs7bytxq2_verdance_load"

var device_id := ""
var _busy := false
var _pending: Dictionary = {}   # a save requested while one is in flight — sent after


func _ready() -> void:
	device_id = _device_id()


func _device_id() -> String:
	if OS.has_feature("web"):
		var js := "(function(){var k='verdance_device';var v=localStorage.getItem(k);" \
			+ "if(!v){v=([1e7]+-1e3+-4e3+-8e3+-1e11).replace(/[018]/g,function(c){" \
			+ "return (c^crypto.getRandomValues(new Uint8Array(1))[0]&15>>c/4).toString(16)});" \
			+ "localStorage.setItem(k,v);}return v;})()"
		var v: String = str(JavaScriptBridge.eval(js, true))
		if v.length() >= 16:
			return v
	# non-web (headless verify) — session-local id; cloud round-trip still exercised
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return "local-%d-%d" % [rng.randi(), rng.randi()]


## Fetch the save blob; {} when none exists or on any failure.
func load_save() -> Dictionary:
	var req := HTTPRequest.new()
	add_child(req)
	req.timeout = 8.0
	var hdrs := PackedStringArray([
		"Content-Type: application/json", "apikey: " + SB_ANON,
		"Authorization: Bearer " + SB_ANON])
	var body := JSON.stringify({"p_device": device_id})
	if req.request(SB_URL + "/rest/v1/rpc/" + RPC_LOAD, hdrs, HTTPClient.METHOD_POST, body) != OK:
		req.queue_free()
		return {}
	var res: Array = await req.request_completed
	req.queue_free()
	if int(res[1]) != 200:
		return {}
	var parsed: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


## Fire-and-forget upsert; coalesces bursts (one request in flight at a time).
func save(blob: Dictionary) -> void:
	if _busy:
		_pending = blob
		return
	_busy = true
	var req := HTTPRequest.new()
	add_child(req)
	req.timeout = 8.0
	var hdrs := PackedStringArray([
		"Content-Type: application/json", "apikey: " + SB_ANON,
		"Authorization: Bearer " + SB_ANON])
	var body := JSON.stringify({"p_device": device_id, "p_data": blob})
	if req.request(SB_URL + "/rest/v1/rpc/" + RPC_SAVE, hdrs, HTTPClient.METHOD_POST, body) != OK:
		req.queue_free()
		_busy = false
		return
	await req.request_completed
	req.queue_free()
	_busy = false
	if not _pending.is_empty():
		var nxt := _pending
		_pending = {}
		save(nxt)
