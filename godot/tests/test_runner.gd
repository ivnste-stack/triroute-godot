class_name TestRunner
extends RefCounted
## Runs every test_*.gd in res://tests. Used by the main scene (results on screen, press F5 in the editor)
## and by run_tests.gd (headless, for the command line).

## Returns {"passed": int, "failed": int, "lines": PackedStringArray}
static func run_all() -> Dictionary:
	var lines := PackedStringArray()
	var passed := 0
	var failed := 0
	var files := []
	for f in DirAccess.open("res://tests").get_files():
		# exported / imported projects may list scripts as .gd.remap
		var name: String = f.trim_suffix(".remap")
		if name.begins_with("test_") and name.ends_with(".gd") and not files.has(name):
			files.append(name)
	files.sort()
	for f in files:
		var script: Variant = load("res://tests/" + f)
		if not (script is GDScript) or not script.can_instantiate():
			failed += 1
			lines.append("FAIL  %s: does not compile (see the error log)" % f.get_basename())
			continue
		var suite: Object = script.new()
		for m in suite.get_method_list():
			var mname: String = m.name
			if not mname.begins_with("test_"):
				continue
			# a test returns "" when it passes, or why it failed; a script error stops it and returns null
			var res: Variant = suite.call(mname)
			var err: String = res if res is String else "stopped by a script error (see the error log)"
			if err == "":
				passed += 1
				lines.append("ok    %s · %s" % [f.get_basename(), mname])
			else:
				failed += 1
				lines.append("FAIL  %s · %s: %s" % [f.get_basename(), mname, err])
	lines.append("%d passed, %d failed" % [passed, failed])
	return {"passed": passed, "failed": failed, "lines": lines}
