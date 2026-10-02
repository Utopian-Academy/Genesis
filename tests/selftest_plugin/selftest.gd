@tool
extends EditorPlugin

# Phase 1 acceptance: Genesis can be disabled and re-enabled repeatedly with
# no leaked dock, no leaked objects and no errors. Run by tests/run_selftest.sh
# in a throwaway copy of the project; never enabled in the real one.

const CYCLES := 5


func _enter_tree() -> void:
	_run.call_deferred()


func _run() -> void:
	await _frames(30)
	var ok := true
	ok = _expect("enabled at start", _dock_count(), 1) and ok
	var objects_before := -1
	for i in CYCLES:
		EditorInterface.set_plugin_enabled("genesis", false)
		await _frames(5)
		ok = _expect("cycle %d disabled" % i, _dock_count(), 0) and ok
		EditorInterface.set_plugin_enabled("genesis", true)
		await _frames(5)
		ok = _expect("cycle %d enabled" % i, _dock_count(), 1) and ok
		var objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
		# The first cycle warms caches; after that, the count must hold still.
		if i == 1:
			objects_before = objects
		elif i > 1:
			print("GN_SELFTEST cycle %d objects %d (cycle 1: %d)" % [i, objects, objects_before])
			if objects - objects_before > 50:
				ok = false
				print("GN_SELFTEST FAIL object count grows each cycle")
	print("GN_SELFTEST RESULT %s" % ("PASS" if ok else "FAIL"))
	EditorInterface.get_base_control().get_tree().quit(0 if ok else 1)


func _dock_count() -> int:
	var found := 0
	for dock in EditorInterface.get_base_control().find_children("*", "EditorDock", true, false):
		if dock.get("title") == "Genesis" and dock.is_inside_tree():
			found += 1
	return found


func _expect(what: String, got: int, want: int) -> bool:
	var good := got == want
	print("GN_SELFTEST %s %s: %d dock(s), want %d" % ["ok  " if good else "FAIL", what, got, want])
	return good


func _frames(n: int) -> void:
	for i in n:
		await EditorInterface.get_base_control().get_tree().process_frame
