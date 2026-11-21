extends SceneTree
## Headless test runner for the command line:
##   godot --headless --path godot -s res://tests/run_tests.gd
## The same tests also run on screen when you start the project (F5) — see scripts/main.gd.

func _initialize() -> void:
	var r := TestRunner.run_all()
	for l in r.lines:
		print("  " + l)
	quit(1 if r.failed else 0)
