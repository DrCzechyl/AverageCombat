class_name FighterSpec
extends RefCounted

## Typed representation of a fighter's metadata, build parameters, and moveset.

var id: String = ""
var name: String = ""
var title: String = ""
var bio: String = ""
var sheet: String = ""
var portrait: String = ""
var accent: Color = Color.WHITE
var alt_tint: Color = Color.WHITE
var health: float = 1000.0
var walk_speed: float = 235.0
var back_speed: float = 195.0
var jump_velocity: float = -1000.0
var damage_scale: float = 1.0
var weight: float = 1.0
var throw_range: float = 108.0
var throw_damage: float = 110.0
var special_name: String = "SPECIAL"
var moves: Dictionary = {}


func get_move(move_name: String) -> MoveSpec:
	var m: Variant = moves.get(move_name, null)
	return m as MoveSpec if m is MoveSpec else null


static func from_dict(d: Dictionary) -> FighterSpec:
	var spec: FighterSpec = new()
	spec.id = str(d.get("id", ""))
	spec.name = str(d.get("name", ""))
	spec.title = str(d.get("title", ""))
	spec.bio = str(d.get("bio", ""))
	spec.sheet = str(d.get("sheet", ""))
	spec.portrait = str(d.get("portrait", ""))

	var accent_val: Variant = d.get("accent", Color.WHITE)
	spec.accent = accent_val if accent_val is Color else Color.WHITE
	var tint_val: Variant = d.get("alt_tint", Color.WHITE)
	spec.alt_tint = tint_val if tint_val is Color else Color.WHITE

	var raw_build: Variant = d.get("build", {})
	var build: Dictionary = raw_build if raw_build is Dictionary else {}
	spec.health = float(build.get("health", d.get("health", 1000.0)))
	spec.walk_speed = float(build.get("walk_speed", d.get("walk_speed", 235.0)))
	spec.back_speed = float(build.get("back_speed", d.get("back_speed", 195.0)))
	spec.jump_velocity = float(build.get("jump_velocity", d.get("jump_velocity", -1000.0)))
	spec.damage_scale = float(build.get("damage_scale", d.get("damage_scale", 1.0)))
	spec.weight = float(build.get("weight", d.get("weight", 1.0)))
	spec.throw_range = float(build.get("throw_range", d.get("throw_range", 108.0)))
	spec.throw_damage = float(build.get("throw_damage", d.get("throw_damage", 110.0)))
	spec.special_name = str(d.get("special_name", "SPECIAL"))

	var parsed_moves: Dictionary = {}
	var raw_moves: Variant = d.get("moves", {})
	if raw_moves is Dictionary:
		for move_name in raw_moves:
			var mv: Variant = raw_moves[move_name]
			var key := str(move_name)
			if mv is MoveSpec:
				parsed_moves[key] = mv
			elif mv is Dictionary:
				parsed_moves[key] = MoveSpec.from_dict(key, mv)
	spec.moves = parsed_moves

	return spec
