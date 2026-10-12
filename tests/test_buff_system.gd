extends SceneTree
# Test runner for buff-system AC verification.
# Run: godot --headless --script tests/test_buff_system.gd
# Each AC = one test method. RED first, then GREEN.
# A failure -> push_error + OS.exit(1) so the shell sees a non-zero exit code.

var _failed := false

func _init():
	_run_all_tests()
	if _failed:
		print("=== TESTS FAILED ===")
		quit(1)
	else:
		print("=== ALL TESTS PASSED ===")
		quit(0)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error("FAIL: " + message)
		print("FAIL: " + message)
		quit(1)

func _run_all_tests():
	_test_ac1_slow_reduces_mp()
	_test_ac2_slow_replaces_haste()
	_test_ac3_slow_refresh_duration()
	_test_ac6_buff_expiry_restores()
	_test_ac5_root_vs_silence()
	_test_ac4_stun_immediate()
	_test_ac7_catch_same_tile()
	_test_ac8_runner_survives_20_turns()

# Source: spec/buff-system AC-1
# AC-1: Apply slow_down to Runner (base_mp=3) -> effective_mp == 2 (3 + (-1))
func _test_ac1_slow_reduces_mp():
	var UnitScript = load("res://scripts/combat/unit.gd")
	_check(UnitScript != null, "AC-1 PRE: unit.gd not found")
	var runner = UnitScript.new()
	runner.base_mp = 3
	var slow_def = load("res://resources/buffs/slow_down.tres")
	_check(slow_def != null, "AC-1 PRE: slow_down.tres not found")
	runner.apply_buff(slow_def)
	var actual = runner.effective_mp()
	_check(actual == 2, "AC-1: expected effective_mp=2, got " + str(actual))
	print("AC-1 PASS: effective_mp == " + str(actual))

# Source: spec/buff-system AC-2
# AC-2: Runner has Haste (mp=4) then apply Slow -> Haste replaced, Slow takes effect, mp=2
func _test_ac2_slow_replaces_haste():
	var UnitScript = load("res://scripts/combat/unit.gd")
	var runner = UnitScript.new()
	runner.base_mp = 3
	var haste_def = load("res://resources/buffs/speed_up.tres")
	_check(haste_def != null, "AC-2 PRE: speed_up.tres not found")
	runner.apply_buff(haste_def)
	_check(runner.effective_mp() == 4, "AC-2 step1: expected mp=4 after haste, got " + str(runner.effective_mp()))
	var slow_def = load("res://resources/buffs/slow_down.tres")
	runner.apply_buff(slow_def)
	_check(runner.buffs.size() == 1, "AC-2: SPEED group should hold exactly 1 buff after replace, got " + str(runner.buffs.size()))
	_check(runner.effective_mp() == 2, "AC-2: expected mp=2 after slow replaces haste, got " + str(runner.effective_mp()))
	print("AC-2 PASS: slow replaced haste, effective_mp == " + str(runner.effective_mp()))

# Source: spec/buff-system AC-3
# AC-3: Re-apply slow_down to a unit already slowed -> remaining_turns refreshed to 3 (not stacked)
func _test_ac3_slow_refresh_duration():
	var UnitScript = load("res://scripts/combat/unit.gd")
	var runner = UnitScript.new()
	runner.base_mp = 3
	var slow_def = load("res://resources/buffs/slow_down.tres")
	runner.apply_buff(slow_def)
	# Simulate 1 tick having passed (remaining 3 -> 2) without depending on tick_buffs (AC-6 impl)
	runner.buffs["SPEED"].remaining_turns = 2
	# Re-apply: REFRESH should reset remaining to def.duration_turns (3)
	runner.apply_buff(slow_def)
	_check(runner.buffs["SPEED"].remaining_turns == 3, "AC-3: expected remaining=3 after refresh, got " + str(runner.buffs["SPEED"].remaining_turns))
	_check(runner.effective_mp() == 2, "AC-3: mp should still be 2 (no stack), got " + str(runner.effective_mp()))
	print("AC-3 PASS: remaining refreshed to 3, mp still == " + str(runner.effective_mp()))

# Source: spec/buff-system AC-6
# AC-6: When remaining_turns hits 0, buff is removed and mp/restrictions restored
func _test_ac6_buff_expiry_restores():
	var UnitScript = load("res://scripts/combat/unit.gd")
	var runner = UnitScript.new()
	runner.base_mp = 3
	_check(runner.has_method("tick_buffs"), "AC-6 PRE: Unit has no tick_buffs method")
	var slow_def = load("res://resources/buffs/slow_down.tres")
	runner.apply_buff(slow_def)
	_check(runner.effective_mp() == 2, "AC-6 setup: mp should be 2 with slow, got " + str(runner.effective_mp()))
	# duration=3 -> tick 3 times: remaining 3->2->1->0 (removed)
	runner.tick_buffs()
	runner.tick_buffs()
	runner.tick_buffs()
	_check(not runner.buffs.has("SPEED"), "AC-6: SPEED buff should be removed after expiry, still has: " + str(runner.buffs.keys()))
	_check(runner.effective_mp() == 3, "AC-6: mp should restore to 3 after expiry, got " + str(runner.effective_mp()))
	print("AC-6 PASS: buff expired and removed, mp == " + str(runner.effective_mp()))

# Source: spec/buff-system AC-5
# AC-5: ROOT unit can skill but can't move; SILENCE unit can move but can't skill
func _test_ac5_root_vs_silence():
	var UnitScript = load("res://scripts/combat/unit.gd")
	var runner = UnitScript.new()
	runner.base_mp = 3
	_check(runner.has_method("can_move"), "AC-5 PRE: Unit has no can_move method")
	_check(runner.has_method("can_skill"), "AC-5 PRE: Unit has no can_skill method")
	var root_def = load("res://resources/buffs/root.tres")
	_check(root_def != null, "AC-5 PRE: root.tres not found")
	runner.apply_buff(root_def)
	_check(runner.can_move() == false, "AC-5: ROOT should block move, can_move=" + str(runner.can_move()))
	_check(runner.can_skill() == true, "AC-5: ROOT should allow skill, can_skill=" + str(runner.can_skill()))
	# Separate unit for silence to avoid ROOT+SILENCE coexistence confound
	var runner2 = UnitScript.new()
	runner2.base_mp = 3
	var silence_def = load("res://resources/buffs/silence.tres")
	_check(silence_def != null, "AC-5 PRE: silence.tres not found")
	runner2.apply_buff(silence_def)
	_check(runner2.can_move() == true, "AC-5: SILENCE should allow move, can_move=" + str(runner2.can_move()))
	_check(runner2.can_skill() == false, "AC-5: SILENCE should block skill, can_skill=" + str(runner2.can_skill()))
	print("AC-5 PASS: root blocks move/allows skill; silence allows move/blocks skill")

# Source: spec/buff-system AC-4
# AC-4: Stun immediately zeroes remaining MP, blocks move+skill; remaining 2->1 after tick
func _test_ac4_stun_immediate():
	var UnitScript = load("res://scripts/combat/unit.gd")
	var runner = UnitScript.new()
	runner.base_mp = 3
	var stun_def = load("res://resources/buffs/stun.tres")
	_check(stun_def != null, "AC-4 PRE: stun.tres not found")
	runner.apply_buff(stun_def)
	_check(runner.can_move() == false, "AC-4: STUN should block move, can_move=" + str(runner.can_move()))
	_check(runner.can_skill() == false, "AC-4: STUN should block skill, can_skill=" + str(runner.can_skill()))
	_check(runner.effective_mp() == 0, "AC-4: STUN should zero remaining MP, got " + str(runner.effective_mp()))
	runner.tick_buffs()
	_check(runner.buffs.has("STUN"), "AC-4: STUN should still be active after 1 tick")
	_check(runner.buffs["STUN"].remaining_turns == 1, "AC-4: STUN remaining should be 1 after tick (2->1), got " + str(runner.buffs["STUN"].remaining_turns))
	print("AC-4 PASS: stun zeroed MP, blocks move+skill, remaining 2->1")

# Source: spec/buff-system AC-7
# AC-7: After any action, if Chaser and Runner same tile -> game ends, CHASER_WIN
func _test_ac7_catch_same_tile():
	var UnitScript = load("res://scripts/combat/unit.gd")
	var chaser = UnitScript.new()
	var runner = UnitScript.new()
	chaser.position = Vector2(0, 0)
	runner.position = Vector2(1, 0)
	var MatchScript = load("res://scripts/game/match.gd")
	_check(MatchScript != null, "AC-7 PRE: match.gd not found")
	var m = MatchScript.new()
	_check(m.has_method("setup"), "AC-7 PRE: Match has no setup method")
	m.setup(chaser, runner)
	_check(m.has_method("check_catch"), "AC-7 PRE: Match has no check_catch method")
	# Different tiles: no catch
	m.check_catch()
	_check(m.result == 0, "AC-7: expected ONGOING(0) when different tiles, got " + str(m.result))
	# Move chaser to runner's tile, check again
	chaser.position = runner.position
	m.check_catch()
	_check(m.result == 1, "AC-7: expected CHASER_WIN(1) when same tile, got " + str(m.result))
	print("AC-7 PASS: same tile -> CHASER_WIN")

# Source: spec/buff-system AC-8
# AC-8: After 20 full turns (both acted 20x) without catch -> game ends, RUNNER_WIN
func _test_ac8_runner_survives_20_turns():
	var UnitScript = load("res://scripts/combat/unit.gd")
	var chaser = UnitScript.new()
	var runner = UnitScript.new()
	chaser.position = Vector2(0, 0)
	runner.position = Vector2(20, 0)  # Far apart, no catch
	var MatchScript = load("res://scripts/game/match.gd")
	var m = MatchScript.new()
	m.setup(chaser, runner)
	_check(m.has_method("end_turn"), "AC-8 PRE: Match has no end_turn method")
	for i in range(20):
		m.end_turn()
	_check(m.result == 2, "AC-8: expected RUNNER_WIN(2) after 20 turns no catch, got " + str(m.result))
	print("AC-8 PASS: 20 turns survived -> RUNNER_WIN")
