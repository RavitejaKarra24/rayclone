#!/usr/bin/env python3
"""Generate the bundled emoji dataset for the "Emoji & Symbols" picker.

Standalone, dependency free (Python 3 stdlib only).

Strategy
--------
There is no simple way to parse `/System/Library/Fonts/Apple Color Emoji.ttc`
(stdlib-only parsing of a TTC of sbix bitmaps is not worth it), so the emoji
set is enumerated from explicit Unicode code point ranges (a well known
ordering of the emoji blocks), and `unicodedata.name()` is used to filter out
unassigned code points and to build human readable names.

Skin tone modifiers (U+1F3FB..U+1F3FF), regional indicator flag pairs
(U+1F1E6..U+1F1FF) and keycap sequences (base + U+20E3) are intentionally
excluded. Text-presentation emoji get U+FE0F appended so every emitted
sequence is fully qualified and renders as emoji.

Usage:
    python3 Scripts/generate_emoji.py
"""

from __future__ import annotations

import json
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_PATH = ROOT / "Sources" / "Rayclone" / "Resources" / "emoji.json"

MIN_ENTRIES = 900

VS16 = "\ufe0f"
ZWJ = "\u200d"

GROUP_ORDER = [
    "Smileys & People",
    "Animals & Nature",
    "Food & Drink",
    "Activity",
    "Travel & Places",
    "Objects",
    "Symbols",
    "Flags",
]

# --- Membership ranges ------------------------------------------------------
# (first, last, group).  Emoji blocks are walked code point by code point;
# unassigned code points are dropped because unicodedata has no name for them.
# Ranges are listed from the most specific block to the general ones; the first
# range that claims a code point wins.
SINGLE_RANGES: list[tuple[int, int, str]] = [
    # ---- Smileys & People -------------------------------------------------
    (0x1F600, 0x1F64F, "Smileys & People"),  # emoticons
    (0x1F910, 0x1F92F, "Smileys & People"),  # faces, monkeys, gestures
    (0x1F930, 0x1F93E, "Smileys & People"),  # pregnant, breast feeding, sports people
    (0x1F970, 0x1F976, "Smileys & People"),  # smiling face with hearts .. zany
    (0x1F977, 0x1F97A, "Smileys & People"),  # ninja, construction worker, pleading
    (0x1FAE0, 0x1FAE8, "Smileys & People"),  # melting face .. shaking face
    (0x1FAF0, 0x1FAF8, "Smileys & People"),  # hand gestures (Unicode 14/15)
    (0x1F9D0, 0x1F9DF, "Smileys & People"),  # money-mouth + people w/ fantasy roles
    (0x1F9B4, 0x1F9BF, "Smileys & People"),  # body parts (bone .. mechanical leg)
    (0x1FAC0, 0x1FAC5, "Smileys & People"),  # anatomical heart .. person with crown
    (0x1F90C, 0x1F90F, "Smileys & People"),  # pinched fingers, hand gestures
    (0x1F464, 0x1F487, "Smileys & People"),  # bust .. hair styling (people & families)
    (0x1F440, 0x1F450, "Smileys & People"),  # eyes, ear, nose, mouths, hands
    (0x1F463, 0x1F463, "Smileys & People"),  # footprints
    (0x1F48B, 0x1F48B, "Smileys & People"),  # kiss mark
    (0x1F493, 0x1F49F, "Smileys & People"),  # hearts
    (0x1F4A2, 0x1F4AB, "Smileys & People"),  # anger, bomb, sweat, speechless ..
    (0x1F4AF, 0x1F4AF, "Smileys & People"),  # hundred points
    (0x1F5A4, 0x1F5A4, "Smileys & People"),  # black heart
    (0x1F574, 0x1F575, "Smileys & People"),  # levitating person, detective
    (0x1F57A, 0x1F57A, "Smileys & People"),  # man dancing
    (0x1F590, 0x1F590, "Smileys & People"),  # hand with fingers splayed
    (0x1F595, 0x1F596, "Smileys & People"),  # middle finger, vulcan salute
    (0x1F3C2, 0x1F3CC, "Smileys & People"),  # person doing sports / activities
    (0x1F385, 0x1F385, "Smileys & People"),  # santa claus
    (0x1F6B4, 0x1F6B6, "Smileys & People"),  # cycling, mountain biking, walking
    (0x1F6C0, 0x1F6C0, "Smileys & People"),  # person taking a bath
    (0x261D, 0x261D, "Smileys & People"),  # index pointing up
    (0x26F9, 0x26F9, "Smileys & People"),  # person bouncing ball
    (0x270A, 0x270D, "Smileys & People"),  # fists, waving hand, writing hand
    # ---- Animals & Nature -------------------------------------------------
    (0x1F400, 0x1F43F, "Animals & Nature"),  # mammals, birds, reptiles, bugs, marine
    (0x1F330, 0x1F344, "Animals & Nature"),  # plants, trees, mushroom
    (0x1F980, 0x1F9AE, "Animals & Nature"),  # crutaceans, insects, mammals (Unicode 11+)
    (0x1FAB0, 0x1FABF, "Animals & Nature"),  # fly, worm, beetle, nest, coral, jellyfish
    (0x1F54A, 0x1F54A, "Animals & Nature"),  # dove
    (0x1F577, 0x1F578, "Animals & Nature"),  # spider, spider web
    # ---- Food & Drink -----------------------------------------------------
    (0x1F345, 0x1F37F, "Food & Drink"),  # fruit, vegetables, prepared food, drinks
    (0x1F950, 0x1F96F, "Food & Drink"),  # food (Unicode 10)
    (0x1F9C0, 0x1F9CB, "Food & Drink"),  # cheese, salt, canned food, ice cube, mate
    (0x1FAD0, 0x1FADE, "Food & Drink"),  # beans, pouring liquid, flatbread ..
    (0x1F3FA, 0x1F3FA, "Food & Drink"),  # amphora
    (0x2615, 0x2615, "Food & Drink"),  # hot beverage
    # ---- Activity ---------------------------------------------------------
    (0x1F380, 0x1F393, "Activity"),  # ribbons, party, amusements, games, sports eq.
    (0x1F396, 0x1F397, "Activity"),  # military medal, reminder ribbon
    (0x1F399, 0x1F39B, "Activity"),  # studio microphone, level slider, control knobs
    (0x1F39E, 0x1F3A0, "Activity"),  # film frames, admission tickets, carousel horse
    (0x1F3A1, 0x1F3C1, "Activity"),  # ferris wheel .. chequered flag
    (0x1F3CF, 0x1F3D3, "Activity"),  # cricket, field hockey, etc. (ball games)
    (0x1F3F8, 0x1F3F9, "Activity"),  # badminton, bow and arrow
    (0x1F3BE, 0x1F3BE, "Activity"),
    (0x1F945, 0x1F945, "Activity"),  # goal net
    (0x1F94A, 0x1F94D, "Activity"),  # boxing glove, martial arts, curling stone, lacrosse
    (0x26BD, 0x26BE, "Activity"),  # soccer ball, baseball
    (0x26F3, 0x26F3, "Activity"),  # flag in hole
    (0x26F8, 0x26F8, "Activity"),  # ice skate
    # ---- Travel & Places --------------------------------------------------
    (0x1F300, 0x1F308, "Travel & Places"),  # cyclone, foggy, night with stars, rainbow ..
    (0x1F30D, 0x1F321, "Travel & Places"),  # earth, moon, stars, shooting star, thermometer
    (0x1F324, 0x1F32C, "Travel & Places"),  # sun/cloud/rain/tornado/fog (sky & weather)
    (0x1F3D4, 0x1F3F0, "Travel & Places"),  # mountains, camping, houses, buildings
    (0x1F5FA, 0x1F5FF, "Travel & Places"),  # world map, statue of liberty, mount fuji
    (0x1F680, 0x1F6C5, "Travel & Places"),  # transport: rockets, cars, trains, planes
    (0x1F6D0, 0x1F6D2, "Travel & Places"),  # place of worship, stop sign, shopping cart
    (0x1F6D5, 0x1F6D7, "Travel & Places"),  # hindu temple, hut, elevator
    (0x1F6E3, 0x1F6E5, "Travel & Places"),  # motorway, railway track, motor boat
    (0x1F6E9, 0x1F6E9, "Travel & Places"),  # small airplane
    (0x1F6EB, 0x1F6EC, "Travel & Places"),  # airplane departure, airplane arriving
    (0x1F6F0, 0x1F6F0, "Travel & Places"),  # satellite
    (0x1F6F3, 0x1F6FC, "Travel & Places"),  # passenger ship, scooter, sled, flying saucer ..
    (0x1F550, 0x1F567, "Travel & Places"),  # clocks
    (0x1F54B, 0x1F54E, "Travel & Places"),  # kaaba, mosque, synagogue, menorah
    (0x2600, 0x2604, "Travel & Places"),  # sun, cloud, umbrella, snowman, comet
    (0x26C4, 0x26C5, "Travel & Places"),  # snowman w/o snow, sun behind cloud
    (0x26C8, 0x26C8, "Travel & Places"),  # cloud with lightning and rain
    (0x26E9, 0x26EA, "Travel & Places"),  # shinto shrine, church
    (0x26F0, 0x26F2, "Travel & Places"),  # mountain, umbrella on ground, fountain
    (0x26F5, 0x26F5, "Travel & Places"),  # sailboat
    (0x26FA, 0x26FA, "Travel & Places"),  # tent
    (0x26FD, 0x26FD, "Travel & Places"),  # fuel pump
    (0x2708, 0x2708, "Travel & Places"),  # airplane
    # ---- Objects ----------------------------------------------------------
    (0x1F4A1, 0x1F4A1, "Objects"),  # light bulb
    (0x1F4AC, 0x1F4AC, "Objects"),  # speech balloon
    (0x1F4AD, 0x1F4AD, "Objects"),  # thought balloon
    (0x1F4AE, 0x1F4AE, "Objects"),  # white flower
    (0x1F4B0, 0x1F4FF, "Objects"),  # money, mail, computers, books, stationery
    (0x1F50A, 0x1F517, "Objects"),  # speakers, magnifiers, locks, key, bell, bookmark
    (0x1F525, 0x1F52E, "Objects"),  # fire, torch, wrench, hammer, knife, microscope ..
    (0x1F549, 0x1F549, "Symbols"),  # om symbol
    (0x1F56F, 0x1F570, "Objects"),  # candle, mantelpiece clock
    (0x1F573, 0x1F573, "Objects"),  # hole
    (0x1F587, 0x1F587, "Objects"),  # linked paperclips
    (0x1F58A, 0x1F58D, "Objects"),  # pen, fountain pen, crayon, paintbrush
    (0x1F6CB, 0x1F6CB, "Objects"),  # couch and lamp
    (0x1F6CD, 0x1F6CF, "Objects"),  # shopping bags, bellhop bell, bed
    (0x1F3F7, 0x1F3F7, "Objects"),  # label
    (0x1F451, 0x1F462, "Objects"),  # crown, clothing, shoes, bags
    (0x1F5A5, 0x1F5A5, "Objects"),  # desktop computer
    (0x1F5A8, 0x1F5A8, "Objects"),  # printer
    (0x1F5B1, 0x1F5B2, "Objects"),  # computer mouse, trackball
    (0x1F5BC, 0x1F5BC, "Objects"),  # framed picture
    (0x1F5C2, 0x1F5C4, "Objects"),  # card index dividers, card file box, file cabinet
    (0x1F5D1, 0x1F5D3, "Objects"),  # wastebasket, sprial calendar ..
    (0x1F5DC, 0x1F5DE, "Objects"),  # clamp, dovetail joint, rolled-up newspaper
    (0x1F5E1, 0x1F5E3, "Objects"),  # dagger knife, speaking head
    (0x1F5E8, 0x1F5EF, "Objects"),  # left speech bubble .. right anger bubble
    (0x1F5F3, 0x1F5F3, "Objects"),  # ballot box with ballot
    (0x1F6D2, 0x1F6D2, "Objects"),  # shopping cart
    (0x1F6E0, 0x1F6E2, "Objects"),  # hammer and wrench, dagger, oil drum
    (0x1F576, 0x1F576, "Objects"),  # sunglasses
    (0x1F97B, 0x1F97F, "Objects"),  # sari, lab coat, goggles, hiking boot, flat shoe
    (0x1F93F, 0x1F93F, "Objects"),  # diving mask
    (0x1F9AF, 0x1F9AF, "Objects"),  # white cane
    (0x1F9E0, 0x1F9FF, "Objects"),  # brain, clothing, lab equipment, tools, baskets
    # ---- Symbols ----------------------------------------------------------
    (0x1F004, 0x1F004, "Symbols"),  # mahjong red dragon (0x1F000..0x1F003 are not emoji)
    (0x1F0CF, 0x1F0CF, "Symbols"),  # joker
    (0x1F170, 0x1F171, "Symbols"),  # A/B buttons
    (0x1F17E, 0x1F17F, "Symbols"),  # O button, P parking
    (0x1F18E, 0x1F18E, "Symbols"),  # AB button
    (0x1F191, 0x1F19A, "Symbols"),  # CL, cool, free, id, new, ng, ok, sos, up ..
    (0x1F201, 0x1F202, "Symbols"),  # squared katakana
    (0x1F21A, 0x1F21A, "Symbols"),
    (0x1F22F, 0x1F22F, "Symbols"),
    (0x1F232, 0x1F23A, "Symbols"),  # squared CJK shortcut signs
    (0x1F250, 0x1F251, "Symbols"),  # circled ideograph advantage / accept
    (0x1F4A0, 0x1F4A0, "Symbols"),  # diamond with a dot
    (0x1F500, 0x1F507, "Symbols"),  # shuffle, repeat, dim/bright/mute buttons
    (0x1F518, 0x1F53D, "Symbols"),  # radio button .. down button
    (0x2194, 0x2199, "Symbols"),  # left-right arrow ..
    (0x21A9, 0x21AA, "Symbols"),  # right arrow curving left/right
    (0x231A, 0x231B, "Symbols"),  # watch, hourglass
    (0x2328, 0x2328, "Symbols"),  # keyboard
    (0x23CF, 0x23CF, "Symbols"),  # eject
    (0x23E9, 0x23F3, "Symbols"),  # fast-forward .. hourglass done
    (0x23F8, 0x23FA, "Symbols"),  # pause, stop, record
    (0x24C2, 0x24C2, "Symbols"),  # circled M
    (0x25AA, 0x25AB, "Symbols"),  # small squares
    (0x25B6, 0x25B6, "Symbols"),  # play
    (0x25C0, 0x25C0, "Symbols"),  # reverse
    (0x25FB, 0x25FE, "Symbols"),  # white/black medium squares
    (0x260E, 0x260E, "Symbols"),  # telephone
    (0x2611, 0x2611, "Symbols"),  # ballot box with check
    (0x2618, 0x2618, "Symbols"),  # shamrock
    (0x2620, 0x2620, "Symbols"),  # skull and crossbones
    (0x2622, 0x2623, "Symbols"),  # radioactive, biohazard
    (0x2626, 0x2626, "Symbols"),  # orthodox cross
    (0x262A, 0x262A, "Symbols"),  # star and crescent
    (0x262E, 0x262F, "Symbols"),  # peace, yin yang
    (0x2638, 0x263A, "Symbols"),  # wheel of dharma, frowning, smiling
    (0x2640, 0x2640, "Symbols"),  # female sign
    (0x2642, 0x2642, "Symbols"),  # male sign
    (0x2648, 0x2653, "Symbols"),  # zodiac
    (0x265F, 0x2660, "Symbols"),  # chess pawn, spade
    (0x2663, 0x2663, "Symbols"),  # club suit
    (0x2665, 0x2666, "Symbols"),  # heart suit, diamond suit
    (0x2668, 0x2668, "Symbols"),  # hot springs
    (0x267B, 0x267B, "Symbols"),  # recycling symbol
    (0x267E, 0x267F, "Symbols"),  # infinity, wheelchair
    (0x2692, 0x2697, "Symbols"),  # hammer and pick .. alembic
    (0x2699, 0x2699, "Symbols"),  # gear
    (0x269B, 0x269C, "Symbols"),  # atom symbol, fleur-de-lis
    (0x26A0, 0x26A1, "Symbols"),  # warning, high voltage
    (0x26A7, 0x26A7, "Symbols"),  # transgender symbol
    (0x26AA, 0x26AB, "Symbols"),  # circles
    (0x26B0, 0x26B1, "Symbols"),  # coffin, funeral urn
    (0x26CE, 0x26CE, "Symbols"),  # ophiuchus
    (0x26CF, 0x26CF, "Symbols"),  # pick
    (0x26D1, 0x26D1, "Symbols"),  # rescue worker's helmet
    (0x26D3, 0x26D4, "Symbols"),  # chains, no entry
    (0x26F4, 0x26F4, "Travel & Places"),  # ferry
    (0x26F7, 0x26F7, "Smileys & People"),  # skier
    (0x2702, 0x2702, "Objects"),  # scissors
    (0x2705, 0x2705, "Symbols"),  # check mark button
    (0x270F, 0x270F, "Objects"),  # pencil
    (0x2712, 0x2712, "Objects"),  # black nib
    (0x2714, 0x2714, "Symbols"),  # check mark
    (0x2716, 0x2716, "Symbols"),  # multiply
    (0x271D, 0x271D, "Symbols"),  # latin cross
    (0x2721, 0x2721, "Symbols"),  # star of david
    (0x2728, 0x2728, "Symbols"),  # sparkles
    (0x2733, 0x2734, "Symbols"),  # eight-spoked asterisk, eight-pointed star
    (0x2744, 0x2744, "Symbols"),  # snowflake
    (0x2747, 0x2747, "Symbols"),  # sparkle
    (0x274C, 0x274C, "Symbols"),  # cross mark
    (0x274E, 0x274E, "Symbols"),  # cross mark button
    (0x2753, 0x2755, "Symbols"),  # question / exclamation marks
    (0x2757, 0x2757, "Symbols"),
    (0x2763, 0x2764, "Symbols"),  # heart exclamation, red heart
    (0x2795, 0x2797, "Symbols"),  # plus, minus, divide
    (0x27A1, 0x27A1, "Symbols"),  # right arrow
    (0x27B0, 0x27B0, "Symbols"),  # curly loop
    (0x27BF, 0x27BF, "Symbols"),  # double curly loop
    (0x2934, 0x2935, "Symbols"),  # arrows
    (0x2B05, 0x2B07, "Symbols"),  # left/up/down arrows
    (0x2B1B, 0x2B1C, "Symbols"),  # black/white large square
    (0x2B50, 0x2B50, "Symbols"),  # star
    (0x2B55, 0x2B55, "Symbols"),  # hollow red circle
    (0x3030, 0x3030, "Symbols"),  # wavy dash
    (0x303D, 0x303D, "Symbols"),  # part alternation mark
    (0x3297, 0x3297, "Symbols"),  # Japanese congratulations button
    (0x3299, 0x3299, "Symbols"),  # Japanese secret button
    # ---- Flags (only non-regional-indicator flags; RI pairs are excluded) --
    (0x1F3F3, 0x1F3F4, "Flags"),  # waving white flag, black flag
    (0x1F38C, 0x1F38C, "Flags"),  # crossed flags
    (0x1F6A9, 0x1F6A9, "Flags"),  # triangular flag
]

# Code points that live inside a range above but belong to another group.
GROUP_OVERRIDES: dict[int, str] = {
    0x1F336: "Food & Drink",  # hot pepper
    0x1F33D: "Food & Drink",  # ear of maize
    0x1F6D2: "Objects",  # shopping cart
    0x1F9E1: "Smileys & People",  # orange heart
    0x1FAE7: "Objects",  # bubbles
    0x1F32D: "Food & Drink",  # hot dog
    0x1F32E: "Food & Drink",  # taco
    0x1F32F: "Food & Drink",  # burrito
    0x1F37D: "Food & Drink",  # fork and knife with plate
    0x1F9AA: "Food & Drink",  # oyster
    0x1F9E0: "Smileys & People",  # brain
    0x1F9E7: "Activity",  # red envelope
    0x1F9E8: "Activity",  # firecracker
    0x1F9E9: "Activity",  # jigsaw puzzle
    0x1F9D0: "Smileys & People",  # money-mouth face
    0x1F93F: "Objects",  # diving mask
    0x1F3F3: "Flags",  # waving white flag (also the base of rainbow flag)
    0x1F576: "Objects",  # sunglasses
    0x1F6D1: "Symbols",  # stop sign
}

# Code points inside the ranges that are not standalone emoji, or that are
# explicitly forbidden by the dataset spec.
EXCLUDED_CODE_POINTS: set[int] = set(
    # skin tone modifiers (U+1F3FB..U+1F3FF)
    range(0x1F3FB, 0x1F400)
) | set(
    # regional indicators (flag pairs)
    range(0x1F1E6, 0x1F200)
) | set(
    # ZWJ hair components: only valid inside sequences
    range(0x1F9B0, 0x1F9B4)
) | {
    0x1F100,  # digit zero full stop, no emoji
    0x1F202,  # squared katakana sa: not emoji
    0x1F237,  # squared CJK ideograph 6708: not in the emoji font
    0x1F4FE,  # portable stereo: not emoji
    0x1F5E2,  # lips: not emoji
    0x1F5E9,  # right speech bubble: not emoji
    0x1F5EA,  # two speech bubbles: not emoji
    0x1F5EB,  # three speech bubbles: not emoji
    0x1F5EC,  # left thought bubble: not emoji
    0x1F5ED,  # right thought bubble: not emoji
    0x1F5EE,  # left anger bubble: not emoji
    0x1F93B,  # modern pentathlon: missing from Apple Color Emoji
}

# Code points that are emoji-presentation by default and therefore must *not*
# get U+FE0F appended.  Everything else below U+1F000 (arrows, dingbats, misc
# symbols) is text-presentation by default and gets VS16.
EMOJI_DEFAULT: list[tuple[int, int]] = [
    (0x231A, 0x231B),
    (0x23E9, 0x23F3),
    (0x24C2, 0x24C2),
    (0x25FD, 0x25FE),
    (0x2614, 0x2615),
    (0x2648, 0x2653),
    (0x267F, 0x267F),
    (0x2693, 0x2693),
    (0x26A1, 0x26A1),
    (0x26AA, 0x26AB),
    (0x26BD, 0x26BE),
    (0x26C4, 0x26C5),
    (0x26CE, 0x26CE),
    (0x26D4, 0x26D4),
    (0x26EA, 0x26EA),
    (0x26F2, 0x26F3),
    (0x26F5, 0x26F5),
    (0x26FA, 0x26FA),
    (0x26FD, 0x26FD),
    (0x2705, 0x2705),
    (0x270A, 0x270B),
    (0x2728, 0x2728),
    (0x274C, 0x274C),
    (0x274E, 0x274E),
    (0x2753, 0x2755),
    (0x2757, 0x2757),
    (0x2795, 0x2797),
    (0x27B0, 0x27B0),
    (0x27BF, 0x27BF),
    (0x2B1B, 0x2B1C),
    (0x2B50, 0x2B50),
    (0x2B55, 0x2B55),
    (0x1F004, 0x1F004),
    (0x1F0CF, 0x1F0CF),
    (0x1F18E, 0x1F18E),
    (0x1F191, 0x1F19A),
    (0x1F201, 0x1F201),
    (0x1F21A, 0x1F21A),
    (0x1F22F, 0x1F22F),
    (0x1F232, 0x1F23A),
    (0x1F250, 0x1F251),
]

# Supplementary plane code points whose default presentation is text, so they
# need U+FE0F to be displayed as emoji.
SUPPLEMENTARY_TEXT_DEFAULT: list[tuple[int, int]] = [
    (0x1F170, 0x1F171),
    (0x1F17E, 0x1F17F),
    (0x1F202, 0x1F202),
    (0x1F321, 0x1F321),
    (0x1F324, 0x1F32C),
    (0x1F336, 0x1F336),
    (0x1F37D, 0x1F37D),
    (0x1F396, 0x1F397),
    (0x1F399, 0x1F39B),
    (0x1F39E, 0x1F39F),
    (0x1F3F3, 0x1F3F5),
    (0x1F3F7, 0x1F3F7),
    (0x1F43F, 0x1F43F),
    (0x1F441, 0x1F441),
    (0x1F4FD, 0x1F4FD),
    (0x1F549, 0x1F54A),
    (0x1F56F, 0x1F570),
    (0x1F573, 0x1F575),
    (0x1F576, 0x1F576),
    (0x1F587, 0x1F587),
    (0x1F58A, 0x1F58D),
    (0x1F590, 0x1F590),
    (0x1F5A5, 0x1F5A5),
    (0x1F5A8, 0x1F5A8),
    (0x1F5B1, 0x1F5B2),
    (0x1F5BC, 0x1F5BC),
    (0x1F5C2, 0x1F5C4),
    (0x1F5D1, 0x1F5D3),
    (0x1F5DC, 0x1F5DE),
    (0x1F5E1, 0x1F5E1),
    (0x1F5E3, 0x1F5E3),
    (0x1F5E8, 0x1F5E8),
    (0x1F5EF, 0x1F5EF),
    (0x1F5F3, 0x1F5F3),
    (0x1F5FA, 0x1F5FA),
    (0x1F6CB, 0x1F6CB),
    (0x1F6CD, 0x1F6CF),
    (0x1F6E0, 0x1F6E5),
    (0x1F6E9, 0x1F6E9),
    (0x1F6F0, 0x1F6F0),
    (0x1F6F3, 0x1F6F3),
]

# --- ZWJ sequences ---------------------------------------------------------
# Only sequences that render on current macOS, no skin tone variants.
ZWJ_SEQUENCES: list[tuple[str, str, str]] = [
    # family / couples
    ("1F468 200D 1F469 200D 1F466", "family man woman boy", "Smileys & People"),
    ("1F468 200D 1F469 200D 1F467", "family man woman girl", "Smileys & People"),
    ("1F468 200D 1F469 200D 1F467 200D 1F466", "family man woman girl boy", "Smileys & People"),
    ("1F468 200D 1F469 200D 1F466 200D 1F466", "family man woman boy boy", "Smileys & People"),
    ("1F468 200D 1F469 200D 1F467 200D 1F467", "family man woman girl girl", "Smileys & People"),
    ("1F468 200D 1F468 200D 1F466", "family man man boy", "Smileys & People"),
    ("1F468 200D 1F468 200D 1F467", "family man man girl", "Smileys & People"),
    ("1F469 200D 1F469 200D 1F466", "family woman woman boy", "Smileys & People"),
    ("1F469 200D 1F469 200D 1F467", "family woman woman girl", "Smileys & People"),
    ("1F468 200D 1F466", "family man boy", "Smileys & People"),
    ("1F468 200D 1F467", "family man girl", "Smileys & People"),
    ("1F469 200D 1F466", "family woman boy", "Smileys & People"),
    ("1F469 200D 1F467", "family woman girl", "Smileys & People"),
    ("1F468 200D 1F468 200D 1F466 200D 1F466", "family man man boy boy", "Smileys & People"),
    ("1F469 200D 1F469 200D 1F466 200D 1F466", "family woman woman boy boy", "Smileys & People"),
    ("1F469 200D 2764 FE0F 200D 1F468", "couple with heart woman man", "Smileys & People"),
    ("1F468 200D 2764 FE0F 200D 1F468", "couple with heart man man", "Smileys & People"),
    ("1F469 200D 2764 FE0F 200D 1F469", "couple with heart woman woman", "Smileys & People"),
    ("1F469 200D 2764 FE0F 200D 1F48B 200D 1F468", "kiss woman man", "Smileys & People"),
    ("1F468 200D 2764 FE0F 200D 1F48B 200D 1F468", "kiss man man", "Smileys & People"),
    ("1F469 200D 2764 FE0F 200D 1F48B 200D 1F469", "kiss woman woman", "Smileys & People"),
    # gendered professions
    ("1F468 200D 2695 FE0F", "man health worker", "Smileys & People"),
    ("1F469 200D 2695 FE0F", "woman health worker", "Smileys & People"),
    ("1F468 200D 1F393", "man student", "Smileys & People"),
    ("1F469 200D 1F393", "woman student", "Smileys & People"),
    ("1F468 200D 1F3EB", "man teacher", "Smileys & People"),
    ("1F469 200D 1F3EB", "woman teacher", "Smileys & People"),
    ("1F468 200D 2696 FE0F", "man judge", "Smileys & People"),
    ("1F469 200D 2696 FE0F", "woman judge", "Smileys & People"),
    ("1F468 200D 1F33E", "man farmer", "Smileys & People"),
    ("1F469 200D 1F33E", "woman farmer", "Smileys & People"),
    ("1F468 200D 1F373", "man cook", "Smileys & People"),
    ("1F469 200D 1F373", "woman cook", "Smileys & People"),
    ("1F468 200D 1F527", "man mechanic", "Smileys & People"),
    ("1F469 200D 1F527", "woman mechanic", "Smileys & People"),
    ("1F468 200D 1F3ED", "man factory worker", "Smileys & People"),
    ("1F469 200D 1F3ED", "woman factory worker", "Smileys & People"),
    ("1F468 200D 1F4BC", "man office worker", "Smileys & People"),
    ("1F469 200D 1F4BC", "woman office worker", "Smileys & People"),
    ("1F468 200D 1F52C", "man scientist", "Smileys & People"),
    ("1F469 200D 1F52C", "woman scientist", "Smileys & People"),
    ("1F468 200D 1F4BB", "man technologist", "Smileys & People"),
    ("1F469 200D 1F4BB", "woman technologist", "Smileys & People"),
    ("1F468 200D 1F3A4", "man singer", "Smileys & People"),
    ("1F469 200D 1F3A4", "woman singer", "Smileys & People"),
    ("1F468 200D 1F3A8", "man artist", "Smileys & People"),
    ("1F469 200D 1F3A8", "woman artist", "Smileys & People"),
    ("1F468 200D 2708 FE0F", "man pilot", "Smileys & People"),
    ("1F469 200D 2708 FE0F", "woman pilot", "Smileys & People"),
    ("1F468 200D 1F680", "man astronaut", "Smileys & People"),
    ("1F469 200D 1F680", "woman astronaut", "Smileys & People"),
    ("1F468 200D 1F692", "man firefighter", "Smileys & People"),
    ("1F469 200D 1F692", "woman firefighter", "Smileys & People"),
    ("1F46E 200D 2642 FE0F", "man police officer", "Smileys & People"),
    ("1F46E 200D 2640 FE0F", "woman police officer", "Smileys & People"),
    ("1F482 200D 2642 FE0F", "man guard", "Smileys & People"),
    ("1F482 200D 2640 FE0F", "woman guard", "Smileys & People"),
    ("1F477 200D 2642 FE0F", "man construction worker", "Smileys & People"),
    ("1F477 200D 2640 FE0F", "woman construction worker", "Smileys & People"),
    ("1F473 200D 2642 FE0F", "man in tuxedo", "Smileys & People"),
    ("1F473 200D 2640 FE0F", "woman in tuxedo", "Smileys & People"),
    ("1F471 200D 2640 FE0F", "woman blonde hair", "Smileys & People"),
    ("1F471 200D 2642 FE0F", "man blonde hair", "Smileys & People"),
    ("1F9D4 200D 2642 FE0F", "man beard", "Smileys & People"),
    ("1F9D4 200D 2640 FE0F", "woman beard", "Smileys & People"),
    ("1F9D1 200D 1F4BB", "technologist", "Smileys & People"),
    ("1F9D1 200D 1F692", "firefighter", "Smileys & People"),
    ("1F9D1 200D 1F384", "mx claus", "Smileys & People"),
    ("1F9D1 200D 1F91D 200D 1F9D1", "people holding hands", "Smileys & People"),
    # heart / face composites
    ("2764 FE0F 200D 1F525", "heart on fire", "Smileys & People"),
    ("2764 FE0F 200D 1FA79", "mending heart", "Smileys & People"),
    ("1F441 FE0F 200D 1F5E8 FE0F", "eye in speech bubble", "Smileys & People"),
    ("1F636 200D 1F32B FE0F", "face in clouds", "Smileys & People"),
    ("1F62E 200D 1F4A8", "face exhaling", "Smileys & People"),
    ("1F62E 200D 1F4A5", "face with open eyes and hand over mouth", "Smileys & People"),
    ("1F635 200D 1F4AB", "face with spiral eyes", "Smileys & People"),
    ("1F642 200D 2194 FE0F", "head shaking horizontally", "Smileys & People"),
    ("1F642 200D 2195 FE0F", "head shaking vertically", "Smileys & People"),
    # animals
    ("1F43B 200D 2744 FE0F", "polar bear", "Animals & Nature"),
    ("1F408 200D 2B1B", "black cat", "Animals & Nature"),
    ("1F415 200D 1F9BA", "service dog", "Animals & Nature"),
    ("1F9AE 200D 1F9BA", "guide dog", "Animals & Nature"),
    ("1F431 200D 1F453", "cat with glasses", "Animals & Nature"),
    ("1FACF 200D 1F5E8 FE0F", "moose with speech bubble", "Animals & Nature"),
    # flags (non regional-indicator)
    ("1F3F3 FE0F 200D 1F308", "rainbow flag", "Flags"),
    ("1F3F3 FE0F 200D 26A7 FE0F", "transgender flag", "Flags"),
    ("1F3F4 200D 2620 FE0F", "pirate flag", "Flags"),
]

# --- Names / keywords ------------------------------------------------------

STOPWORDS = {
    "a",
    "an",
    "and",
    "as",
    "at",
    "by",
    "for",
    "from",
    "in",
    "of",
    "on",
    "or",
    "s",
    "the",
    "to",
    "with",
    "w",
    "without",
    "symbol",
    "sign",
    "button",
}

# Curated synonyms for the highest-frequency emoji, keyed by final name.
SYNONYMS: dict[str, list[str]] = {
    # faces & emotions
    "grinning face": ["grin", "happy", "smile"],
    "grinning face with smiling eyes": ["happy", "smile", "joy"],
    "rolling on the floor laughing": ["rofl", "lol", "laugh"],
    "face with tears of joy": ["laugh", "lol", "cry", "haha"],
    "slightly smiling face": ["smile", "happy"],
    "smiling face with smiling eyes": ["happy", "warm", "smile"],
    "smiling face with halo": ["angel", "innocent", "good"],
    "winking face": ["wink", "flirt", "joke"],
    "smiling face with heart shaped eyes": ["love", "crush", "adore"],
    "smiling face with smiling eyes and three hearts": ["love", "adore", "affection"],
    "face throwing a kiss": ["kiss", "love", "flirt"],
    "face savouring delicious food": ["yum", "tasty", "delicious"],
    "smiling face with sunglasses": ["cool", "chill", "sunglasses"],
    "grinning face with star eyes": ["starstruck", "wow", "amazed"],
    "face with party horn and party hat": ["party", "celebrate", "yay"],
    "smirking face": ["smug", "flirt", "confident"],
    "pensive face": ["sad", "thoughtful"],
    "disappointed face": ["sad", "letdown"],
    "crying face": ["cry", "sad", "tears"],
    "loudly crying face": ["cry", "sob", "sad"],
    "face with look of triumph": ["triumph", "huff", "proud"],
    "pouting face": ["angry", "mad", "rage"],
    "serious face with symbols covering mouth": ["swearing", "cursing", "angry"],
    "shocked face with exploding head": ["mind blown", "shock", "wow"],
    "face screaming in fear": ["scream", "scared", "horror"],
    "overheated face": ["hot", "heat", "sweat"],
    "freezing face": ["cold", "freezing", "winter"],
    "sleeping face": ["sleep", "zzz", "tired"],
    "drooling face": ["drool", "hungry"],
    "nauseated face": ["sick", "gross", "disgust"],
    "face with open mouth vomiting": ["sick", "puke", "ill"],
    "face with medical mask": ["sick", "mask", "ill"],
    "face with thermometer": ["sick", "fever", "ill"],
    "thinking face": ["think", "hmm", "consider"],
    "face with finger covering closed lips": ["quiet", "secret", "hush"],
    "smiling face with smiling eyes and hand covering mouth": ["oops", "giggle", "shy"],
    "lying face": ["lie", "pinocchio"],
    "face without mouth": ["silent", "blank"],
    "neutral face": ["meh", "blank", "neutral"],
    "face with rolling eyes": ["eyeroll", "annoyed", "whatever"],
    "grimacing face": ["awkward", "eek"],
    "face with pleading eyes": ["please", "beg", "puppy eyes"],
    "flushed face": ["embarrassed", "blush", "shy"],
    "smiling face with tear": ["grateful", "touched", "tear"],
    "face holding back tears": ["teary", "grateful", "proud"],
    "melting face": ["melt", "sarcasm", "hot"],
    "saluting face": ["salute", "yes sir", "respect"],
    "shaking face": ["shake", "vibrate", "nervous"],
    "hugging face": ["hug", "comfort", "care"],
    "face palm": ["facepalm", "smh", "oops"],
    "zipper mouth face": ["secret", "silence", "quiet"],
    "money mouth face": ["money", "rich", "cash"],
    # hands & people
    "handshake": ["deal", "agreement", "hello"],
    "person with folded hands": ["please", "thanks", "pray"],
    "thumbs up sign": ["like", "approve", "yes"],
    "thumbs down sign": ["dislike", "no", "disapprove"],
    "clapping hands sign": ["applause", "clap", "bravo"],
    "person raising both hands in celebration": ["hooray", "celebrate", "yay"],
    "waving hand sign": ["hello", "hi", "bye", "wave"],
    "ok hand sign": ["ok", "okay", "perfect"],
    "victory hand": ["peace", "victory", "v"],
    "hand with index and middle fingers crossed": ["luck", "hope", "fingers crossed"],
    "flexed biceps": ["strong", "muscle", "power"],
    "shrug": ["shrug", "idk", "dunno"],
    "eyes": ["eyes", "look", "see"],
    "eye": ["eye", "look", "watch"],
    "brain": ["brain", "smart", "think"],
    "heart hands": ["love", "heart", "hands"],
    # hearts & symbols
    "heavy black heart": ["love", "heart", "red", "valentine"],
    "orange heart": ["love", "heart"],
    "yellow heart": ["love", "heart", "happy"],
    "green heart": ["love", "heart"],
    "blue heart": ["love", "heart"],
    "purple heart": ["love", "heart"],
    "black heart": ["love", "heart", "dark"],
    "white heart": ["love", "heart"],
    "broken heart": ["heartbreak", "sad", "love"],
    "sparkling heart": ["love", "sparkle", "heart"],
    "beating heart": ["love", "heartbeat", "pulse"],
    "heart with arrow": ["love", "cupid", "heart"],
    "hundred points symbol": ["100", "perfect", "score"],
    "fire": ["hot", "flame", "lit"],
    "sparkles": ["sparkle", "shiny", "magic"],
    "white medium star": ["star", "favourite", "rating"],
    "glowing star": ["star", "shine"],
    "warning sign": ["warn", "caution", "alert"],
    "high voltage sign": ["lightning", "power", "electric"],
    "white heavy check mark": ["check", "tick", "done", "yes"],
    "cross mark": ["x", "no", "wrong", "delete"],
    "black question mark ornament": ["question", "help", "why"],
    "heavy exclamation mark symbol": ["exclamation", "important", "alert"],
    "electric light bulb": ["idea", "bulb", "bright"],
    "bell": ["bell", "notification", "alert"],
    # objects & places
    "rocket": ["rocket", "launch", "ship"],
    "party popper": ["party", "celebrate", "tada"],
    "confetti ball": ["party", "celebrate", "confetti"],
    "trophy": ["trophy", "win", "award"],
    "sports medal": ["medal", "winner", "prize"],
    "wrapped present": ["gift", "present", "birthday"],
    "red gift envelope": ["red envelope", "lucky money", "gift"],
    "birthday cake": ["birthday", "cake", "party"],
    "hot beverage": ["coffee", "tea", "drink"],
    "beer mug": ["beer", "drink", "pub"],
    "slice of pizza": ["pizza", "food", "italian"],
    "hamburger": ["burger", "food", "fast food"],
    "red apple": ["apple", "fruit", "food"],
    "dog face": ["dog", "puppy", "pet"],
    "cat face": ["cat", "kitten", "pet"],
    "paw prints": ["paw", "pet", "animal"],
    "earth globe europe africa": ["world", "earth", "global"],
    "house building": ["home", "house", "building"],
    "automobile": ["car", "vehicle", "drive"],
    "airplane": ["plane", "flight", "travel"],
    "globe with meridians": ["web", "internet", "world"],
    "lock": ["lock", "secure", "private"],
    "open lock": ["unlock", "open"],
    "alarm clock": ["clock", "alarm", "time"],
    "rainbow": ["rainbow", "pride"],
    "rainbow flag": ["pride", "lgbt", "rainbow"],
}


def clean_name(raw: str) -> str:
    name = raw.lower().replace("_", " ")
    name = name.replace("-", " ")
    # Drop quotation marks and stray punctuation that appears in some names.
    for ch in ('"', "'", "(", ")", ":", ";", ".", ",", "!", "?"):
        name = name.replace(ch, " ")
    return " ".join(name.split())


def name_for_codepoint(cp: int) -> str | None:
    try:
        raw = unicodedata.name(chr(cp))
    except ValueError:
        return None
    return clean_name(raw)


def synthesize_zwj_name(sequence: str) -> str:
    """Build a readable name from the components of a ZWJ sequence."""
    parts: list[str] = []
    for chunk in sequence.split(ZWJ):
        cps = [int(tok, 16) for tok in chunk.split() if tok.upper() != "FE0F"]
        if not cps:
            continue
        piece = " ".join(name_for_codepoint(cp) or "" for cp in cps).strip()
        if piece and piece not in parts:
            parts.append(piece)
    return " ".join(parts)


def accepts_code_point(cp: int) -> bool:
    if cp in EXCLUDED_CODE_POINTS:
        return False
    ch = chr(cp)
    category = unicodedata.category(ch)
    # Only pictographic-ish characters: no controls, formats, surrogates.
    if category[0] in {"C", "Z"}:
        return False
    return name_for_codepoint(cp) is not None


def needs_vs16(cp: int) -> bool:
    if cp >= 0x1F000:
        # Most of the supplementary emoji blocks are emoji-presentation by
        # default; these few are text-presentation and need U+FE0F.
        return any(lo <= cp <= hi for lo, hi in SUPPLEMENTARY_TEXT_DEFAULT)
    return not any(lo <= cp <= hi for lo, hi in EMOJI_DEFAULT)


def build_singles() -> list[dict]:
    group_of: dict[int, str] = {}
    for first, last, group in SINGLE_RANGES:
        for cp in range(first, last + 1):
            if cp in group_of:
                continue
            group_of[cp] = group
    # Explicit overrides win over the range table.
    for cp, group in GROUP_OVERRIDES.items():
        if cp in group_of:
            group_of[cp] = group

    entries: list[dict] = []
    for group in GROUP_ORDER:
        for cp in sorted(cp for cp, g in group_of.items() if g == group):
            if not accepts_code_point(cp):
                continue
            name = name_for_codepoint(cp)
            if not name:
                continue
            emoji = chr(cp) + (VS16 if needs_vs16(cp) else "")
            entries.append({"emoji": emoji, "name": name, "group": group})
    return entries


def build_zwj() -> list[dict]:
    entries: list[dict] = []
    for sequence, curated_name, group in ZWJ_SEQUENCES:
        text = "".join(chr(int(tok, 16)) for tok in sequence.split())
        name = clean_name(curated_name) or synthesize_zwj_name(text)
        if not name:
            name = synthesize_zwj_name(text)
        entries.append({"emoji": text, "name": name, "group": group})
    # Stable order: group order, then the order declared in ZWJ_SEQUENCES.
    rank = {group: idx for idx, group in enumerate(GROUP_ORDER)}
    entries.sort(key=lambda e: (rank[e["group"]],))
    return entries


def build_keywords(name: str) -> list[str]:
    words: list[str] = []
    for word in name.split():
        word = word.strip()
        if not word or word.isdigit():
            continue
        if word in STOPWORDS:
            continue
        if word not in words:
            words.append(word)
    keywords = words[:4]
    for extra in SYNONYMS.get(name, []):
        if extra not in keywords:
            keywords.append(extra)
        if len(keywords) >= 6:
            break
    if not keywords:
        keywords = ["emoji"]
    return keywords[:6]


def main() -> int:
    entries = build_singles() + build_zwj()

    # De-duplicate by emoji string while keeping first occurrence.
    seen: set[str] = set()
    unique: list[dict] = []
    for entry in entries:
        if entry["emoji"] in seen:
            continue
        seen.add(entry["emoji"])
        unique.append(entry)

    data = [
        {
            "emoji": entry["emoji"],
            "name": entry["name"],
            "keywords": build_keywords(entry["name"]),
            "group": entry["group"],
            "order": index,
        }
        for index, entry in enumerate(unique)
    ]

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(data, ensure_ascii=False, indent=1) + "\n"
    # newline="\n" keeps the output byte-identical across platforms.
    with open(OUT_PATH, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(payload)

    print(f"Wrote {len(data)} emoji entries to {OUT_PATH.relative_to(ROOT)}")
    if len(data) < MIN_ENTRIES:
        print(
            f"error: only {len(data)} entries produced, expected at least {MIN_ENTRIES}",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
