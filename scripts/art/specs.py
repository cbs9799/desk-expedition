"""Prompt specs for every generated art asset. Output: art/raw/<key>.png"""

STYLE = (
    "a 2D pixel-art game sprite sheet in the style of late-1990s 32-bit console JRPG battle sprites "
    "(crisp chunky pixels, 1px dark outlines, 3-4 tone shading, saturated colors, NO anti-aliasing, NO blur). "
    "Solid flat pure magenta (#FF00FF) background everywhere, no ground, no cast shadows, no text, no grid lines, "
    "no borders. Frames evenly spaced in a grid with plenty of magenta between them, no frame touching another. "
    "Same character, same size, same colors in every frame."
)

WORLD = "It lives in a miniature world on top of an office desk, where stationery and desk objects are giant terrain."

HERO_LAYOUT = (
    "Layout: 4 rows, 6 frames per row:\n"
    "row 1: walk cycle (6 frames)\n"
    "row 2: {attack} (6 frames)\n"
    "row 3: idle breathing (3 frames) then jump: crouch, airborne, land (3 frames)\n"
    "row 4: hurt (2 frames), knocked down (2 frames), happy waving victory (2 frames)"
)

HEROES = {
    "hero_warrior": ("a tiny cute chibi knight (2.5 heads tall, big head, expressive eyes): wears a silver sewing "
                     "THIMBLE as a helmet, holds a round red BOTTLE-CAP shield, wields a sewing-needle sword, brown "
                     "tunic, chubby body",
                     "sword attack: wind-up, swing, follow-through, recover"),
    "hero_archer": ("a tiny cute chibi archer girl (2.5 heads tall, big head, expressive eyes, freckles): wears a "
                    "hooded cloak made of a bright green STICKY NOTE, short orange hair, holds a bow made from a bent "
                    "silver PAPER CLIP, quiver of TOOTHPICK arrows, light leather outfit",
                    "bow attack: nock arrow, draw, full draw, release, follow-through, lower bow"),
    "hero_mage": ("a tiny cute chibi wizard boy (2.5 heads tall, big head, round glasses): wears a tall pointy "
                  "yellow hat shaped like a sharpened PENCIL TIP (wood-colored brim, dark graphite point), navy blue "
                  "robe with stars, holds a short CRAYON staff whose tip glows orange",
                  "spell cast: raise staff, gather power (glowing tip), point staff forward, cast burst, hold, recover"),
}

MONSTER_LAYOUT = (
    "Layout: 3 rows, 4 frames per row:\n"
    "row 1: {move} (4 frames)\n"
    "row 2: attack: anticipation, lunge, impact, recover (4 frames)\n"
    "row 3: hurt flinch (2 frames), defeated / collapsing (2 frames)"
)

# region: (ground monster, flyer, heavy, boss) — each (key, description)
REGIONS = [
    ("notebook", "a lined notebook-paper meadow with pencils lying around and eraser crumbs", [
        ("eraser_slime", "a cute pink ERASER-CRUMB slime blob with eyes, crumbly texture", "hop"),
        ("paper_crane", "a small white origami PAPER CRANE monster with angry eyes, flying", "flap wings flying"),
        ("eraser_golem", "a chunky golem made of stacked pink and blue ERASERS, small eyes, stubby arms", "heavy walk"),
        ("stapler_king", "a big BOSS: a fierce black-and-silver STAPLER monster with a tiny gold crown, jaw opens like a mouth with staple teeth", "stomp walk"),
    ]),
    ("pencilcup", "a canyon of giant pencils standing in a pencil cup on a wooden desk", [
        ("shaving_slime", "a cute slime made of curly wooden PENCIL SHAVINGS with eyes", "hop"),
        ("clip_bat", "a small bat whose wings are bent colorful PAPER CLIPS, flying", "flap wings flying"),
        ("stub_golem", "a golem made of stubby short PENCILS bundled together with a rubber band", "heavy walk"),
        ("sharpener_giant", "a big BOSS: a giant metal PENCIL SHARPENER monster with glowing eyes and blade, tiny gold crown", "stomp walk"),
    ]),
    ("mug", "a swamp of spilled coffee next to a giant ceramic mug, sugar cubes as rocks, rising steam", [
        ("coffee_slime", "a cute brown COFFEE DROP slime with a foam top and eyes", "hop"),
        ("teabag_ghost", "a small floating TEA BAG ghost with a string tail and spooky cute eyes", "float bobbing"),
        ("sugar_golem", "a golem made of white SUGAR CUBES stacked into a body, sparkly", "heavy walk"),
        ("mug_octopus", "a big BOSS: an octopus monster bursting out of a COFFEE MUG, brown tentacles, tiny gold crown", "tentacle sway"),
    ]),
    ("planter", "a jungle inside a desk plant pot: soil, succulents, big green leaves", [
        ("moss_slime", "a cute green MOSS slime with a tiny sprout on top and eyes", "hop"),
        ("dandelion_sprite", "a small fluffy white DANDELION SEED fairy monster, floating", "float bobbing"),
        ("cactus_golem", "a golem shaped like a small potted CACTUS with spines and a grumpy face", "heavy walk"),
        ("succulent_king", "a big BOSS: a giant SUCCULENT plant monster king with thick leaves, flower crown and angry face", "stomp walk"),
    ]),
    ("monitor", "a fortress made of keyboard keys and cables, lit by the blue glow of a computer monitor", [
        ("dust_bunny", "a cute gray fluffy DUST BUNNY ball with long ears and eyes", "hop"),
        ("cursor_ghost", "a small glowing white MOUSE-CURSOR ARROW shaped ghost, floating", "float bobbing"),
        ("keycap_golem", "a golem built from KEYBOARD KEYCAPS (with letters W A S D), glowing eye", "heavy walk"),
        ("mouse_dragon", "a big BOSS: a DRAGON made from a wireless computer MOUSE, scroll-wheel spine, glowing red LED eyes, cable tail, tiny gold crown", "stomp walk"),
    ]),
]

BACKDROP = (
    "A wide side-scrolling 2D pixel-art game background in the style of late-1990s 32-bit console games "
    "(crisp chunky pixels, rich saturated palette, NO anti-aliasing, NO blur, no characters, no text, no UI). "
    "Landscape, horizon at about 70% height; the bottom 25% is a flat walkable ground surface seen from the side. "
    "Scene: {scene}, seen at miniature scale as if you were a tiny person on the desk. "
    "The left and right edges should continue naturally so the image can tile horizontally: keep every large "
    "object (pencils, cups, boxes) fully inside the middle 70% of the image, and let the outer 15% on each side "
    "show only continuous background (sky, distant scenery, ground) with no objects cut by the edge."
)

PROPS = (
    "A row of 6 separate 2D pixel-art foreground props for a side-scrolling game, in the style of late-1990s 32-bit "
    "console games (crisp chunky pixels, 1px dark outlines, saturated colors, NO anti-aliasing). Solid flat pure "
    "magenta (#FF00FF) background, items evenly spaced in one row, not touching, each standing on an invisible "
    "ground line, no shadows, no text. Props for: {scene}, at miniature scale (tiny adventurers walk past them). "
    "Mix of sizes: some small, some tall."
)

ACCESSORIES = (
    "A row of 6 separate tiny 2D pixel-art hat accessories for chibi game characters, side view facing right, "
    "late-1990s 32-bit console style (crisp chunky pixels, 1px dark outline, saturated colors, NO anti-aliasing). "
    "Solid flat pure magenta (#FF00FF) background, evenly spaced, not touching, no text. In order: a red ribbon bow, "
    "a small gold crown, a pink flower, a striped party cone hat, a green sprout with two leaves, a tiny wizard star."
)


def all_specs():
    specs = {}
    for key, (desc, attack) in HEROES.items():
        specs[key] = f"Image: {STYLE}\n\nCharacter: {desc}. {WORLD} Side view facing RIGHT in every frame.\n\n" + \
            HERO_LAYOUT.format(attack=attack)
    for region, scene, mons in REGIONS:
        for key, desc, move in mons:
            specs[f"mon_{key}"] = f"Image: {STYLE}\n\nMonster: {desc}. {WORLD} Side view facing LEFT in every frame.\n\n" + \
                MONSTER_LAYOUT.format(move=move)
        specs[f"bg_{region}"] = "Image: " + BACKDROP.format(scene=scene)
        specs[f"props_{region}"] = "Image: " + PROPS.format(scene=scene)
    specs["accessories"] = "Image: " + ACCESSORIES
    return specs


# --- v0.2.2: rare guests, endless drawer depths, boss trophies ---------------------------------
GUESTS = [
    ("guest_usb_fairy", "a tiny cute FAIRY made from a lost USB flash drive, glowing cyan LED wings, sparkly, shy smile", "flutter flying"),
    ("guest_gold_pencil", "a cute floating GOLDEN PENCIL spirit with a glowing tip and a tiny halo, sparkly gold", "float bobbing"),
    ("guest_sugar_prince", "a cute tiny SUGAR CUBE prince with a little cape and crown, sparkling white", "proud strut walk"),
    ("guest_ladybug_knight", "a cute LADYBUG knight standing upright with a tiny leaf shield and thorn lance", "march walk"),
    ("guest_pixel_cat", "a cute glowing SCREENSAVER CAT made of blue light and pixels, floating, starry tail", "float bobbing"),
]

DRAWER_SCENE = ("the inside of a dark desk DRAWER: rubber bands, scattered coins, old receipts, paper clips, a flashlight "
                "beam from above, mysterious and cozy")

TROPHIES = (
    "A row of 6 separate tiny 2D pixel-art trophy items for a side-scrolling game, late-1990s 32-bit console style "
    "(crisp chunky pixels, 1px dark outline, saturated colors, NO anti-aliasing). Solid flat pure magenta (#FF00FF) "
    "background, evenly spaced, not touching, each standing upright on a small wooden plaque, no text. In order: "
    "a giant bent STAPLE, a pencil-sharpener BLADE, a broken MUG HANDLE, a pink SUCCULENT FLOWER, a computer mouse "
    "SCROLL WHEEL, an old brass DRAWER KEY."
)

_base_all_specs = all_specs


def all_specs():
    specs = _base_all_specs()
    for key, desc, move in GUESTS:
        specs[f"mon_{key}"] = f"Image: {STYLE}\n\nMonster: {desc}. {WORLD} Side view facing LEFT in every frame.\n\n" + \
            MONSTER_LAYOUT.format(move=move)
    specs["bg_drawer"] = "Image: " + BACKDROP.format(scene=DRAWER_SCENE)
    specs["props_drawer"] = "Image: " + PROPS.format(scene=DRAWER_SCENE)
    specs["trophies"] = "Image: " + TROPHIES
    return specs
