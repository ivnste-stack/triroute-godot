extends SceneTree
## Headless test runner:
##   godot --headless --path godot -s res://tests/run_tests.gd
## Runs every test_*.gd in res://tests (each a RefCounted with test_* methods returning "" on success
## or an error message). Exit code 0 = all passed.

func _initialize() -> void:
	var failed := 0
	var passed := 0
	var dir := DirAccess.open("res://tests")
	var files := []
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	for f in files:
		var suite: Object = load("res://tests/" + f).new()
		for m in suite.get_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			var err: String = suite.call(name)
			if err == "":
				passed += 1
				print("  ok   %s.%s" % [f.get_basename(), name])
			else:
				failed += 1
				print("  FAIL %s.%s: %s" % [f.get_basename(), name, err])
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
