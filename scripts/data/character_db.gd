class_name CharacterDB
extends RefCounted

## All fighter data lives here so designers can tune the game without touching
## the simulation. Move distances are in screen pixels, times are in 60 Hz ticks.
##
## Hitbox / hurtbox space: origin is between the fighter's feet, +x is "forward"
## (the direction the fighter faces). A negative y is up.

const CELL_W := 64
const CELL_H := 96
const SHEET_COLS := 6

const GROUND_Y := 600.0
const ARENA_LEFT := 160.0
const ARENA_RIGHT := 1120.0
const BODY_HALF_WIDTH := 36.0

const MAX_HEALTH := 1000.0
const METER_MAX := 100.0
const METER_COST := 50.0

## Sprite sheet row layout. Must match tools/gen_art.py.
const ANIMS := {
	"idle": {"row": 0, "frames": 4, "fps": 6.0, "loop": true},
	"walk": {"row": 1, "frames": 6, "fps": 10.0, "loop": true},
	"crouch": {"row": 2, "frames": 2, "fps": 4.0, "loop": true},
	"jump": {"row": 3, "frames": 2, "fps": 6.0, "loop": false},
	"block": {"row": 4, "frames": 2, "fps": 6.0, "loop": true},
	"hurt": {"row": 5, "frames": 2, "fps": 8.0, "loop": false},
	"ko": {"row": 6, "frames": 2, "fps": 4.0, "loop": false},
	"light": {"row": 7, "frames": 4, "fps": 16.0, "loop": false},
	"heavy": {"row": 8, "frames": 5, "fps": 14.0, "loop": false},
	"special": {"row": 9, "frames": 6, "fps": 14.0, "loop": false},
	"win": {"row": 10, "frames": 4, "fps": 8.0, "loop": true},
	"low": {"row": 11, "frames": 4, "fps": 14.0, "loop": false},
}

## Shared normals. Per-character tweaks (below) adjust these.
const BASE_MOVES := {
	"jab": {
		"anim": "light", "startup": 5, "active": 3, "recovery": 9,
		"damage": 45.0, "hitstun": 13, "blockstun": 8,
		"knockback": 120.0, "launch": 0.0, "height": "high",
		"hitbox": Rect2(24, -238, 94, 38),
		"meter_gain": 7.0, "sfx": "swing", "hit_sfx": "hit_light",
		"lunge": 0.0, "armor": false, "chip": 0.12,
	},
	"heavy": {
		"anim": "heavy", "startup": 11, "active": 4, "recovery": 20,
		"damage": 95.0, "hitstun": 20, "blockstun": 12,
		"knockback": 300.0, "launch": 0.0, "height": "mid",
		"hitbox": Rect2(20, -224, 112, 74),
		"meter_gain": 12.0, "sfx": "swing", "hit_sfx": "hit_heavy",
		"lunge": 0.0, "armor": false, "chip": 0.12,
	},
	"low": {
		"anim": "low", "startup": 6, "active": 3, "recovery": 13,
		"damage": 45.0, "hitstun": 13, "blockstun": 8,
		"knockback": 90.0, "launch": 0.0, "height": "low",
		"hitbox": Rect2(22, -74, 100, 52),
		"meter_gain": 7.0, "sfx": "swing", "hit_sfx": "hit_light",
		"lunge": 0.0, "armor": false, "chip": 0.12,
	},
	"sweep": {
		"anim": "low", "startup": 12, "active": 4, "recovery": 22,
		"damage": 85.0, "hitstun": 16, "blockstun": 12,
		"knockback": 180.0, "launch": 520.0, "height": "low",
		"hitbox": Rect2(20, -70, 116, 54),
		"meter_gain": 12.0, "sfx": "swing", "hit_sfx": "hit_heavy",
		"lunge": 40.0, "armor": false, "chip": 0.12,
	},
	"air": {
		"anim": "heavy", "startup": 5, "active": 8, "recovery": 6,
		"damage": 75.0, "hitstun": 18, "blockstun": 11,
		"knockback": 220.0, "launch": 0.0, "height": "high",
		"hitbox": Rect2(18, -140, 110, 96),
		"meter_gain": 10.0, "sfx": "swing", "hit_sfx": "hit_heavy",
		"lunge": 0.0, "armor": false, "chip": 0.12,
	},
}

const SPECIALS := {
	"dave": {
		"name": "SEVERANCE PACKAGE",
		"blurb": "Swing a cardboard box of your personal effects.",
		"anim": "special", "startup": 15, "active": 5, "recovery": 24,
		"damage": 140.0, "hitstun": 26, "blockstun": 14,
		"knockback": 420.0, "launch": 0.0, "height": "mid",
		"hitbox": Rect2(16, -238, 130, 92),
		"meter_gain": 0.0, "meter_cost": 50.0,
		"sfx": "swing", "hit_sfx": "hit_heavy",
		"lunge": 240.0, "armor": false, "chip": 0.15,
	},
	"karen": {
		"name": "CEASE AND DESIST",
		"blurb": "File a formal complaint. From a distance.",
		"anim": "special", "startup": 14, "active": 4, "recovery": 26,
		"damage": 95.0, "hitstun": 20, "blockstun": 12,
		"knockback": 260.0, "launch": 0.0, "height": "mid",
		"hitbox": Rect2(30, -232, 70, 60),
		"meter_gain": 0.0, "meter_cost": 50.0,
		"sfx": "projectile", "hit_sfx": "hit_light",
		"lunge": 0.0, "armor": false, "chip": 0.12,
		"projectile": {
			"speed": 820.0, "life": 0.9, "damage": 95.0,
			"hitstun": 20, "blockstun": 12, "knockback": 260.0,
			# At ground level the clipboard overlaps both standing and crouching.
			"spawn_offset": Vector2(66, -158),
			"rect": Rect2(-13, -26, 26, 34),
		},
	},
	"tony": {
		"name": "EVICTION NOTICE",
		"blurb": "Slow, armored, and legally binding.",
		"anim": "special", "startup": 20, "active": 6, "recovery": 26,
		"damage": 165.0, "hitstun": 28, "blockstun": 16,
		"knockback": 460.0, "launch": 0.0, "height": "mid",
		"hitbox": Rect2(14, -240, 140, 100),
		"meter_gain": 0.0, "meter_cost": 50.0,
		"sfx": "swing", "hit_sfx": "hit_heavy",
		"lunge": 140.0, "armor": true, "chip": 0.15,
	},
	"chad": {
		"name": "REPLY ALL",
		"blurb": "A high-speed, low-empathy dash.",
		"anim": "special", "startup": 9, "active": 5, "recovery": 15,
		"damage": 90.0, "hitstun": 22, "blockstun": 11,
		"knockback": 340.0, "launch": 0.0, "height": "mid",
		"hitbox": Rect2(18, -232, 140, 90),
		"meter_gain": 0.0, "meter_cost": 50.0,
		"sfx": "swing", "hit_sfx": "hit_heavy",
		"lunge": 420.0, "armor": false, "chip": 0.12,
	},
}

const ROSTER := {
	"dave": {
		"name": "DAVE",
		"title": "MID-LEVEL MANAGEMENT",
		"bio": "Three coffees deep and two weeks behind on a report nobody reads. His whole life is a meeting that should have been an email.",
		"sheet": "res://assets/sprites/fighters/dave.png",
		"accent": Color("d9b45b"),
		"stats": {"power": 3, "speed": 3, "defense": 3},
		"build": {
			"health": 1000.0, "walk_speed": 235.0, "back_speed": 195.0,
			"jump_velocity": -1000.0, "damage_scale": 1.0, "weight": 1.0,
		},
		"tweaks": {},
	},
	"karen": {
		"name": "KAREN",
		"title": "HOA PRESIDENT",
		"bio": "Has a clipboard, a group chat, and a strong opinion about your fence height. Will escalate. Already has.",
		"sheet": "res://assets/sprites/fighters/karen.png",
		"accent": Color("b07ac0"),
		"stats": {"power": 4, "speed": 2, "defense": 2},
		"build": {
			"health": 940.0, "walk_speed": 205.0, "back_speed": 175.0,
			"jump_velocity": -1020.0, "damage_scale": 0.97, "weight": 0.95,
		},
		"tweaks": {},
	},
	"tony": {
		"name": "TONY",
		"title": "THE LANDLORD",
		"bio": "Owns the building, the parking spot, and possibly your soul. Carries a plunger for reasons he refuses to explain.",
		"sheet": "res://assets/sprites/fighters/tony.png",
		"accent": Color("c49a4e"),
		"stats": {"power": 5, "speed": 1, "defense": 4},
		"build": {
			"health": 1160.0, "walk_speed": 186.0, "back_speed": 160.0,
			"jump_velocity": -940.0, "damage_scale": 1.1, "weight": 1.28,
		},
		"tweaks": {
			"jab": {"startup": 6, "damage": 50.0},
			"heavy": {"startup": 13, "damage": 110.0},
		},
	},
	"chad": {
		"name": "CHAD",
		"title": "UNPAID INTERN",
		"bio": "Works for exposure. Has a laptop, a hoodie, and the unearned confidence of someone whose parents pay rent.",
		"sheet": "res://assets/sprites/fighters/chad.png",
		"accent": Color("6fc0ae"),
		"stats": {"power": 2, "speed": 5, "defense": 2},
		"build": {
			"health": 900.0, "walk_speed": 268.0, "back_speed": 225.0,
			"jump_velocity": -1050.0, "damage_scale": 0.88, "weight": 0.9,
		},
		"tweaks": {
			"jab": {"startup": 4, "recovery": 8},
			"heavy": {"startup": 10},
		},
	},
}

const ORDER := ["dave", "karen", "tony", "chad"]

const BASE_HURTBOX := Rect2(-30, -246, 60, 246)
const CROUCH_HURTBOX := Rect2(-33, -158, 66, 158)
const AIR_HURTBOX := Rect2(-30, -246, 60, 200)


static func get_character(id: String) -> Dictionary:
	var source: Dictionary = ROSTER.get(id, ROSTER["dave"]).duplicate(true)
	source["id"] = id if ROSTER.has(id) else "dave"
	source["moves"] = BASE_MOVES.duplicate(true)
	for move_name in source.get("tweaks", {}):
		var tweak: Dictionary = source["tweaks"][move_name]
		for key in tweak:
			source["moves"][move_name][key] = tweak[key]
	var special: Dictionary = SPECIALS.get(source["id"], SPECIALS["dave"]).duplicate(true)
	source["moves"]["special"] = special
	source["special_name"] = special.get("name", "SPECIAL")
	return source


static func random_other(id: String) -> String:
	var pool: Array = ORDER.filter(func(c): return c != id)
	return pool[randi() % pool.size()]


static func move_total(move: Dictionary) -> int:
	return int(move.startup) + int(move.active) + int(move.recovery)


static func move_frame_index(tick: int, total: int, frame_count: int) -> int:
	# Spread the sprite frames evenly across the whole move so animation always
	# finishes exactly when the move does.
	if total <= 0 or frame_count <= 0:
		return 0
	var f := int(floor(float(tick) / float(total) * float(frame_count)))
	return clampi(f, 0, frame_count - 1)
