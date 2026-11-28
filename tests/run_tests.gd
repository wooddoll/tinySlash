## 규칙 단위 테스트 실행기
## godot --headless --path . --script res://tests/run_tests.gd
extends SceneTree

const SUITES := ["res://tests/test_rules.gd", "res://tests/test_dungeon.gd", "res://tests/test_scenario.gd", "res://tests/test_crowwatch.gd", "res://tests/test_classes.gd", "res://tests/test_action.gd", "res://tests/test_game.gd", "res://tests/test_village.gd", "res://tests/test_quests.gd", "res://tests/test_region.gd"]


## 테스트 도중 생긴 스크립트 오류를 세서 실패로 처리합니다.
class ErrorCounter extends Logger:
	var count := 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		count += 1


func _initialize() -> void:
	var counter := ErrorCounter.new()
	OS.add_logger(counter)
	var passed := 0
	var failed := 0
	for path in SUITES:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			print("RESULT: %s failed to compile" % path)
			quit(1)
			return
		var r := _run_suite(script.new(), counter)
		passed += r.x
		failed += r.y
	print("RESULT: %d passed, %d failed" % [passed, failed])
	OS.remove_logger(counter)
	quit(1 if failed > 0 else 0)


func _run_suite(suite, counter: ErrorCounter) -> Vector2i:
	var passed := 0
	var failed := 0
	for m in suite.get_method_list():
		var n: String = m.name
		if not n.begins_with("test_"):
			continue
		suite.failures.clear()
		var errors_before := counter.count
		suite.call(n)
		if counter.count > errors_before:
			suite.failures.append("script error during test (see log above)")
		if suite.failures.is_empty():
			passed += 1
		else:
			failed += 1
			print("FAIL %s" % n)
			for f in suite.failures:
				print("    " + f)
	return Vector2i(passed, failed)
