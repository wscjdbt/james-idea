class_name BuffDef
extends Resource
# Static definition of a buff. Data-driven (instantiated as .tres resources).

# Stacking modes (v1 only REFRESH; NONE reserved for v2)
const STACKING_REFRESH := 0
const STACKING_NONE := 1

# Effect types
const EFFECT_MP_DELTA := 0
const EFFECT_RESTRICT := 1

# Restrict bitmask flags
const RESTRICT_STUN := 1
const RESTRICT_ROOT := 2
const RESTRICT_SILENCE := 4

@export var id: String
@export var stack_group_id: String
@export var stacking_mode: int = STACKING_REFRESH
@export var duration_turns: int = 1
@export var effect_type: int = EFFECT_MP_DELTA
@export var mp_delta: int = 0
@export var restrict_flags: int = 0
