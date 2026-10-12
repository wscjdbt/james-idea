class_name BuffInstance
extends RefCounted
# RefCounted: lifetime follows the owning Unit's buffs dict, no manual free needed.

var def: BuffDef
var remaining_turns: int

func _init(p_def: BuffDef) -> void:
	def = p_def
	remaining_turns = def.duration_turns

func refresh() -> void:
	remaining_turns = def.duration_turns
