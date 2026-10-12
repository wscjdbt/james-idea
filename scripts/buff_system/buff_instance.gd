class_name BuffInstance
extends RefCounted
# Runtime instance of a BuffDef on a Unit.

var def: BuffDef
var remaining_turns: int

func _init(p_def: BuffDef) -> void:
	def = p_def
	remaining_turns = def.duration_turns

func refresh() -> void:
	remaining_turns = def.duration_turns
