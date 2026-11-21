class_name MoveSpec
extends RefCounted

## Typed representation of a single fighter move's frame data and properties.

var id: String = ""
var anim: String = ""
var startup: int = 0
var active: int = 0
var recovery: int = 0
var damage: float = 0.0
var hitstun: int = 0
var blockstun: int = 0
var knockback: float = 0.0
var launch: float = 0.0
var height: String = "mid"
var hitbox: Rect2 = Rect2()
var meter_gain: float = 0.0
var meter_cost: float = 0.0
var sfx: String = ""
var hit_sfx: String = ""
var lunge: float = 0.0
var armor: bool = false
var chip: float = 0.12
var knockdown: bool = false
var cancel_into: PackedStringArray = PackedStringArray()
var release_frame: int = -1
var has_projectile: bool = false
var projectile: Dictionary = {}


func total() -> int:
	return startup + active + recovery


static func from_dict(move_id: String, d: Dictionary) -> MoveSpec:
	var spec: MoveSpec = new()
	spec.id = move_id
	spec.anim = str(d.get("anim", ""))
	spec.startup = int(d.get("startup", 0))
	spec.active = int(d.get("active", 0))
	spec.recovery = int(d.get("recovery", 0))
	spec.damage = float(d.get("damage", 0.0))
	spec.hitstun = int(d.get("hitstun", 0))
	spec.blockstun = int(d.get("blockstun", 0))
	spec.knockback = float(d.get("knockback", 0.0))
	spec.launch = float(d.get("launch", 0.0))
	spec.height = str(d.get("height", "mid"))
	var hb: Variant = d.get("hitbox", Rect2())
	spec.hitbox = hb if hb is Rect2 else Rect2()
	spec.meter_gain = float(d.get("meter_gain", 0.0))
	spec.meter_cost = float(d.get("meter_cost", 0.0))
	spec.sfx = str(d.get("sfx", ""))
	spec.hit_sfx = str(d.get("hit_sfx", ""))
	spec.lunge = float(d.get("lunge", 0.0))
	spec.armor = bool(d.get("armor", false))
	spec.chip = float(d.get("chip", 0.12))
	spec.knockdown = bool(d.get("knockdown", false))

	var cancels := PackedStringArray()
	var raw_cancels: Variant = d.get("cancel_into", [])
	if raw_cancels is PackedStringArray:
		cancels = raw_cancels.duplicate()
	elif raw_cancels is Array:
		for entry in raw_cancels:
			cancels.append(str(entry))
	spec.cancel_into = cancels

	spec.release_frame = int(d.get("release_frame", -1))

	var raw_proj: Variant = d.get("projectile", {})
	if raw_proj is Dictionary and not (raw_proj as Dictionary).is_empty():
		spec.has_projectile = true
		spec.projectile = (raw_proj as Dictionary).duplicate(true)
	else:
		spec.has_projectile = false
		spec.projectile = {}

	return spec
