# Gold Box Engine

A "vibe" recreation of the SSI Gold Box RPG engine,
written in [Janet](https://janet-lang.org/) with a raylib C native module,
targeting **FreeBSD** and **Linux**.

```
╔══════════════════════════════════════════════════════════════════════════════════════╗
║  Arrows:Move  T:Talk  C:Rest  I:Inv  A:Attack  S:Spell  F:Flee  F10:Save  ESC:Quit ║
╠══════════════════╦════════════════════════════╦═══════════════════════════════════  ║
║                  ║                            ║                                   ║ ║
║  3D First-Person ║  Area Info / Combat Log    ║         Minimap                   ║ ║
║      View        ║    / Spell Selection       ║                                   ║ ║
║     512×420      ║         310×420            ║         202×420                   ║ ║
║                  ║                            ║                                   ║ ║
╠══════════════════╩════════════════════════════╩═══════════════════════════════════╣
║  Tanis  Lv3  ████   Raistlin  Lv3  ██   Goldmoon  Lv3  ████   Tas  Lv3  ███      ║
╠═══════════════════════════════════════════════════════════════════════════════════╣
║ > The War of the Lance has begun. Takhisis stirs.                                 ║
╚═══════════════════════════════════════════════════════════════════════════════════╝
```

---

## Prerequisites

### FreeBSD
```sh
pkg install janet jpm raylib dejavu
```

### Linux (Debian / Ubuntu)
```sh
sudo apt install janet libraylib-dev fonts-dejavu
```
> `jpm` is not packaged for Debian — build it from source:
> ```sh
> git clone https://github.com/janet-lang/jpm && cd jpm && sudo janet bootstrap.janet
> ```

### Linux (Arch)
```sh
sudo pacman -S janet raylib ttf-dejavu
```
> Install jpm via the AUR: `yay -S jpm` or build from source as above.

| Package | Purpose |
|---|---|
| `janet` | Language runtime |
| `jpm` | Janet package manager — required for `make exe` only |
| `raylib` | Window, renderer, input, font |
| `dejavu` | DejaVu Mono font (UI text, optional) |

---

## Building

### Development (Janet interpreter)

```sh
make clean && make native
make run
```

### Native executable

```sh
make exe
cd build && ./goldbox
```

Output in `build/`:

```
build/
├── goldbox           ← standalone executable
├── janet_raylib.so   ← native module
└── maps/             ← map data files
```

---

## Controls

### Start screen

| Key | Action |
|---|---|
| `N` | New game — opens character creation |
| `L` | Load game — opens save/load menu |
| `↑` / `↓` | Move cursor between options |
| `Enter` | Confirm selection |
| `ESC` | Quit |

### Character creation

| Key | Action |
|---|---|
| `↑` / `↓` / `←` / `→` | Cycle race or class |
| Type | Enter character name (up to 16 chars) |
| `R` | Reroll stats for current member |
| `Enter` / `Tab` | Advance to next field / member |
| `ESC` | Back to start screen |

Stats are rolled 4d6-drop-lowest with racial bonuses applied automatically.
The party is pre-filled with the Dragonlance heroes; every field can be changed freely.

### Exploration

| Key | Action |
|---|---|
| `↑` | Move forward |
| `↓` | Move backward |
| `←` | Turn left 90° |
| `→` | Turn right 90° |
| `T` | Talk to nearby NPC |
| `C` | Rest (restore 50 % HP to all living members) |
| `I` | Inventory / character sheet |
| `Enter` | Interact (door, stairs, port, chest) |
| `1`–`4` | Select active party member |
| `F10` | Open Save/Load menu |
| `ESC` | Quit game |

### Combat — isometric view

When an encounter starts, the 3D view is replaced by an isometric tactical
battlefield. Heroes appear on the left (cols 1–2), monsters on the right
(cols 8–10). Each figure is labelled with its initial letter; the active
combatant is ringed in yellow. **Facing arrows** on each hero point toward
the nearest living enemy so you can read the battlefield at a glance.

| Key | Action |
|---|---|
| `A` / `Enter` | Attack the first living enemy |
| `S` | Open spell selection menu |
| `F` | Attempt to flee (50 % chance; on failure monsters act) |
| `↑` / `↓` | Cycle target (reserved for future use) |

### Spell selection

Pressing `S` during your hero's turn opens a full spell-selection panel in
the text area without leaving the isometric view. The targeted figure is
highlighted with a coloured ring (red = enemy, cyan = ally).

| Key | Action |
|---|---|
| `↑` / `↓` | Cycle through the caster's spell list |
| `←` / `→` | Cycle through targets within the current group |
| `T` | Toggle target group: Enemies ↔ Allies |
| `Enter` | Cast the selected spell on the selected target |
| `ESC` | Cancel — return to combat without casting |

Offensive spells (Magic Missile, Sleep, Hold Person) should be aimed at
enemies. Healing spells (Cure Light Wounds) and buffs (Bless, Mirror Image)
should be aimed at allies.

### Save/Load menu (`F10`)

| Key | Action |
|---|---|
| `↑` / `↓` | Select save slot (10 slots available) |
| `S` | Save — prompts for a name, then writes to selected slot |
| `L` / `Enter` | Load from selected slot |
| `DEL` | Delete selected slot |
| `ESC` / `F10` | Close menu |

During name entry: type freely (`a-z 0-9 - .`), `Backspace` to delete,
`Enter` to confirm, `ESC` to cancel.

---

## Save files

Save files live in **`~/.goldbox_janet/`** on both FreeBSD and Linux.

```
~/.goldbox_janet/
├── slot0.dat    ← binary marshal of full game state
├── slot0.meta   ← display name + timestamp (plain text)
├── slot1.dat
├── slot1.meta
└── ...          ← up to slot9
```

The folder is created automatically on first save. To back up, copy the
entire `~/.goldbox_janet/` directory.

---

## Project Structure

```
goldbox-janet/
├── Makefile              # Build system (BSD make / GNU make compatible)
├── project.janet         # jpm config for make exe
├── janet_raylib.c        # C native module: raylib bindings for Janet
├── src/
│   ├── main.janet        # Entry point, main loop, window lifetime
│   ├── engine.janet      # Input dispatch, state machine, message bus
│   ├── world.janet       # Tile map loader, entity system, fog-of-war
│   ├── party.janet       # Characters, D&D stats, XP, levelling
│   ├── combat.janet      # THAC0 combat, initiative, monster AI, spells
│   ├── ui.janet          # Gold Box split-screen renderer (1024×768)
│   ├── savegame.janet    # Save / load system (10 named slots)
│   ├── rng.janet         # Shared RNG (d4, d6, d8, d20, rand-int, rand-bool)
│   └── debug.janet       # 41-step crash diagnostic
└── maps/                 # 20 map files (o_ overland, i_ interior, d_ dungeon, w_ water)
    ├── o_solace.map
    ├── i_inn_last_home.map
    ├── d_xak_tsaroth.map
    ├── w_newsea.map
    └── ...
```

### Map file format

Maps live in `maps/*.map` and are loaded at runtime:

```
level 0
spawn 4 3 north

# Optional texture overrides
textures
wall  my_wall
floor my_floor
endtextures

map
################    # wall  . floor  D door(closed)  d door(open)
#.....#........#    > stairs-down    < stairs-up
...                 C chest          P port/dock
################
endmap

npc otik "Otik" 7 3
Welcome to the Inn of the Last Home!
endnpc
```

Map prefix conventions:

| Prefix | Type | Default wall / floor / ceiling |
|---|---|---|
| `o_` | Overland | stone_wall / dirt / sky |
| `i_` | Interior / Castle | castle_stone / wood_floor / dark_brick |
| `d_` | Dungeon | dungeon_stone / stone_tile / dungeon_stone |
| `w_` | Water | cave_wall / water / sky |

Per-map `textures` blocks override any of these keys.

### Screen layout (1024×768)

```
[key hints                                  1024×32 ]
[3D view 512×420] [text panel 310×420] [minimap 202×420]
[party stats bar                            1024×100]
[message log                                1024×36 ]
```

During combat the 3D view is replaced by the isometric battlefield and the
text panel shows the combat log (or the spell-selection panel when `S` is pressed).

### Game state

A single mutable table threaded through all subsystems:

```janet
@{:mode        :explore      # :startscreen | :charcreate | :explore | :splash
                              # :combat | :spell-select | :dialog | :inventory | :savemenu
  :world       {...}         # tiles, entities, player, fog, level
  :party       [...]         # array of character tables
  :active-idx  0             # currently selected party member
  :combat      {...}         # active combat state, or nil
  :spell-menu  {...}         # spell-select state: spell-idx, target-mode, target-idx
  :dialog-npc  {...}         # NPC being talked to, or nil
  :messages    [...]         # scrolling message log (last 6 lines)
  :tick        0             # frame counter
  :running     true}         # set to false to exit the main loop
```

### THAC0 combat

```
roll   = d20
hit?   = (roll >= thac0 - target-ac)
damage = 2d6 on hit (melee)
```

Initiative is rolled once at combat start (d6 + DEX modifier for heroes,
d6 for monsters) and determines turn order for the entire encounter.
Monster turns run automatically; the player acts on each hero's turn.

### Spells

| Spell | Caster | Effect |
|---|---|---|
| Magic Missile | Wizard | 1d4+1 damage to one enemy |
| Sleep | Wizard | Incapacitates one enemy instantly |
| Mirror Image | Wizard | Caster gains −2 AC (permanent for encounter) |
| Cure Light Wounds | Cleric / Paladin | Heals 1d8+1 HP to one ally |
| Hold Person | Cleric | Incapacitates one enemy instantly |
| Bless | Cleric / Paladin | Caster gains +1 THAC0 (permanent for encounter) |

---

## Troubleshooting

**`janet.h` not found**
```sh
pkg install janet           # FreeBSD
sudo apt install janet      # Debian
```

**`raylib.h` not found**
```sh
pkg install raylib                  # FreeBSD
sudo apt install libraylib-dev      # Debian/Ubuntu
```

**`could not find module janet_raylib`**
```sh
make clean && make native
```

**`jpm: command not found`**
```sh
pkg install janet    # FreeBSD (jpm ships with janet >= 1.17)
# Linux: build from https://github.com/janet-lang/jpm
```

**Signal 11 (segfault) on startup**

Run `make debug`. Most common causes:

- `src/janet_raylib.so` missing — run `make native` first
- `BeginDrawing` called outside a window — `rl/clear` must follow `rl/open-window`

**Font looks pixelated**

DejaVu is not installed. Install `dejavu` (FreeBSD) or `fonts-dejavu` (Debian).
The game falls back to raylib's built-in 8×8 bitmap font automatically.

---

## Setting

The game is set during the **War of the Lance** on Krynn. The party begins in
**Solace, Abanasinia** and journeys across 20 locations — from Darken Wood and
Que-Shu to the New Sea, Tarsis, Qualinesti, and the dungeons of Pax Tharkas.

### Heroes of the Lance (default party)

| Character | Race | Class | Spells |
|---|---|---|---|
| Tanis Half-Elven | Half-Elf | Ranger | — |
| Raistlin Majere | Human | Wizard | Magic Missile, Sleep, Mirror Image |
| Goldmoon | Human | Cleric of Mishakal | Cure Light Wounds, Hold Person, Bless |
| Tasslehoff Burrfoot | Kender | Thief | — |

All four can be renamed, reclassed, and rerolled during character creation.

### Enemies

| Monster | AC | XP | Notes |
|---|---|---|---|
| Goblin | 6 | 15 | Common lowland threat |
| Dark Wolf | 6 | 25 | Darken Wood pack hunter |
| Skeleton | 7 | 35 | Undead; immune to sleep |
| Baaz Draconian | 4 | 65 | Dragonarmy infantry |
| Kapak Draconian | 4 | 120 | Venomous claws |
| Bozak Draconian | 3 | 270 | Spellcasting draconian |
| Sea Serpent | 3 | 500 | New Sea waters |
| Sivak Draconian | 1 | 650 | Elite shapeshifter |
| Aurak Draconian | 2 | 975 | Most powerful draconian type |
| Red Dragon | 0 | 6000 | Guards Pax Tharkas |
| Blue Dragon | −1 | 7000 | End boss; lightning breath |

---

BSD-3-Clause. Fan/educational project. Dragonlance is a trademark of Wizards of the Coast.
