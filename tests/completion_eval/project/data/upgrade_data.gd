class_name UpgradeData
extends Resource

enum Kind { MAX_HEALTH, DOUBLE_JUMP, DASH, ATTACK_DAMAGE, MAGNET }

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var icon: Texture2D
@export var kind: Kind = Kind.MAX_HEALTH
@export var cost: int = 10
@export var value: float = 1.0
