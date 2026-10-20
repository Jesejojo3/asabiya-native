extends SceneTree

var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	call_deferred("_run")

func _wait(bridge: BridgeSource, condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		bridge.poll()
		if condition.call(): return true
		if bridge._stopped(): return false
		await process_frame
	return false

func _measure(server: String, fluid: bool, full_size: bool) -> Dictionary:
	var bridge := BridgeSource.new(null, server)
	bridge.world_config = {"seed":"Asabiya","width":400 if full_size else 24,"height":200 if full_size else 16,"detail":4,"landFraction":0.33}
	bridge.fluid_playback = fluid
	check(bridge.start(), "server starts")
	var ready: bool = await _wait(bridge, func(): return bridge.can_advance() and not bridge.years().is_empty())
	check(ready, "initial exact snapshot loads")
	if not ready:
		bridge.close()
		return {}
	var start_year: int = bridge.years()[-1]
	var count := 53 # Final pause deliberately falls between checkpoints.
	var observed: Array[int] = []
	var deferred: Array[int] = []
	var on_frame := func():
		var year: int = bridge.years()[-1]
		if not observed.is_empty() and year == observed[-1]: return
		observed.append(year)
		var frame: HistoryFrame = bridge.frame(year)
		if frame.digest_mode == "deferred-v1":
			check(frame.state_digest == "", "deferred frame never invents a fingerprint")
			deferred.append(year)
		else:
			check(frame.state_digest.length() == 64, "verified year has a full fingerprint")
		if year >= start_year + count:
			bridge.pause()
			check(not bridge.can_advance(), "pause stays busy until its exact snapshot arrives")
	bridge.frames_changed.connect(on_frame)
	var started := Time.get_ticks_usec()
	bridge.start_live(0)
	var completed: bool = await _wait(bridge, func(): return not bridge.is_live() and bridge.can_advance() and bridge.years()[-1] == start_year + count)
	var elapsed: int = Time.get_ticks_usec() - started
	check(completed, "live playback stops at requested complete year")
	var expected: Array[int] = []
	for i in count: expected.append(start_year + i + 1)
	check(observed == expected, "every consecutive year was published once")
	check(not deferred.is_empty() if fluid else deferred.is_empty(), "verification follows selected playback mode")
	var final: HistoryFrame = bridge.frame(start_year + count)
	check(final != null and final.digest_mode == "" and final.state_digest.length() == 64, "pausing replaces the deferred frame with an exact current snapshot")
	if not completed or final == null:
		bridge.close()
		return {}
	var proof := {}
	bridge.request("get_replay", {}, func(response: Dictionary): proof.assign(response.get("data", {})))
	var got_proof: bool = await _wait(bridge, func(): return not proof.is_empty())
	check(got_proof and proof.get("finalSHA256") == final.state_digest, "paused fingerprint agrees with replay")
	for i in 5:
		bridge.poll()
		await process_frame
	check(bridge.years()[-1] == start_year + count, "pause never advances another year")
	bridge.frames_changed.disconnect(on_frame)
	var result := {"fluid":fluid,"fullSize":full_size,"years":count,"elapsedMs":elapsed/1000.0,"yearsPerSecond":count*1000000.0/elapsed,"sha":final.state_digest,"replay":proof}
	print("FLUID_SAMPLE ", JSON.stringify({"fluid":fluid,"fullSize":full_size,"years":count,"elapsedMs":result.elapsedMs,"yearsPerSecond":result.yearsPerSecond,"sha":final.state_digest}))
	if not full_size:
		bridge.start_live(0)
		bridge.poll()
		check(bridge._live_advance_pending, "a complete year is in flight")
		bridge.pause()
		bridge.start_live(0)
		check(not bridge.is_live() and not bridge.can_advance(), "resume is blocked while pause verification is pending")
		var paused: bool = await _wait(bridge, func(): return bridge.can_advance())
		check(paused and bridge.years()[-1] == start_year + count + 1, "pause in flight finishes exactly the one accepted year")
		var paused_frame: HistoryFrame = bridge.frame(bridge.years()[-1])
		check(paused_frame != null and paused_frame.digest_mode == "" and paused_frame.state_digest.length() == 64, "in-flight pause also finishes with an exact snapshot")
	await bridge.shutdown()
	return result

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var server := ""
	for i in range(args.size()-1):
		if args[i] == "--server": server = args[i+1]
	check(server != "", "real Go server required")
	if server == "":
		quit(1)
		return
	var benchmark := args.has("--benchmark")
	for repetition in (3 if benchmark else 1):
		var exact: Dictionary = await _measure(server, false, benchmark)
		var fluid: Dictionary = await _measure(server, true, benchmark)
		check(not exact.is_empty() and not fluid.is_empty(), "both playback modes complete")
		if not exact.is_empty() and not fluid.is_empty():
			check(exact.sha == fluid.sha and exact.replay == fluid.replay, "modes preserve final state, RNG and all replay commands")
	print("Fluid playback: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
