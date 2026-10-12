class_name Match
extends Node2D
# Match controller: holds Chaser/Runner, checks catch & turn-cap win conditions.

enum Result { ONGOING, CHASER_WIN, RUNNER_WIN }

const TURN_CAP := 20

var chaser: Unit
var runner: Unit
var result: int = Result.ONGOING
var turn_index: int = 0

func setup(p_chaser: Unit, p_runner: Unit) -> void:
	chaser = p_chaser
	runner = p_runner
	result = Result.ONGOING
	turn_index = 0

func check_catch() -> void:
	if result == Result.ONGOING and chaser.position == runner.position:
		result = Result.CHASER_WIN

func end_turn() -> void:
	turn_index += 1
	if turn_index >= TURN_CAP and result == Result.ONGOING:
		result = Result.RUNNER_WIN
