# Gold Box Engine

A "vibe" recreation of the SSI Gold Box RPG engine,
written in [Janet](https://janet-lang.org/) with a raylib C native module,
targeting **FreeBSD** and **Linux**.

```
╔══════════════════════════════════════════════════════════════════════════════════╗
║  Arrows:Move  T:Talk  C:Rest  I:Inv  A:Attack  S:Spell  F:Flee  F10:Save/Load ESC:Quit ║
╠══════════════════╦═══════════════════════════╦══════════════════════════════════╣
║                  ║                           ║                                  ║
║  3D First-Person ║   Area Info / Combat Log  ║         Minimap                  ║
║      View        ║      / Dialog Panel       ║                                  ║
║     512×420      ║          310×420          ║         202×420                  ║
║                  ║                           ║                                  ║
╠══════════════════╩═══════════════════════════╩══════════════════════════════════╣
║  Tanis  Lv3  ████   Raistlin  Lv3  ██   Goldmoon  Lv3  ████   Tas  Lv3  ███   ║
╠═══════════════════════════════════════════════════════════════════════════════════╣
║ > The War of the Lance has begun. Takhisis stirs.                                ║
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

### Exploration

| Key | Action |
|---|---|
| `↑` | Move forward |
| `↓` | Move backward |
| `←` | Turn left 90° |
| `→` | Turn right 90° |
| `T` | Talk to nearby NPC |
| `C` | Rest (restore HP) |
| `I` | Inventory screen |
| `Enter` | Interact (door, stairs, port, chest) |
| `F1`–`F4` | Select active party member |
| `F10` | Open Save/Load menu |
| `ESC` | Quit game |

### Combat

| Key | Action |
|---|---|
| `A` / `Enter` | Attack selected target |
| `S` | Cast spell |
| `F` | Attempt to flee |

### Save/Load menu (F10)

| Key | Action |
|---|---|
| `↑` / `↓` | Select save slot |
| `S` | Save — prompts for a name (`a-z 0-9 - .`), then saves |
| `L` / `Enter` | Load from selected slot |
| `ESC` | Close menu |

---

## Save files

Save files are stored in **`~/.goldbox_janet/`** on both FreeBSD and Linux.

```
~/.goldbox_janet/
├── slot0.dat    ← save slot 0 (binary marshal)
├── slot0.meta   ← save slot 0 metadata (name + timestamp, plain text)
├── slot1.dat
├── slot1.meta
└── ...
```

Each `.meta` file contains two lines:

```
My Adventure
2026-03-20 14:32
```

The folder is created automatically on first save. To back up your saves, copy
the entire `~/.goldbox_janet/` directory.

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
│   ├── rng.janet         # Shared RNG (d4, d6, d8, d20, rand-int)
│   └── debug.janet       # Step-by-step crash diagnostic
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

map
################    # wall  . floor  D door  > stairs/exit
#.....#........#    < return-exit    C chest  P port/dock
...
################
endmap

npc otik "Otik" 7 3
Welcome to the Inn of the Last Home!
endnpc
```

Map prefix conventions:

| Prefix | Type | Floor / Ceiling colours |
|---|---|---|
| `o_` | Overland | Dirt brown / Heaven blue |
| `i_` | Interior / Castle | Stone gray / Brown |
| `d_` | Dungeon | Dark brown / Dark brown |
| `w_` | Water | Water blue / Heaven blue |

### Screen Layout (1024×768)

```
[key hints                                  1024×32 ]
[3D view 512×420] [text panel 310×420] [minimap 202×420]
[party stats bar                            1024×100]
[message log                                1024×36 ]
```

### THAC0 combat

```
roll  = d20
hit?  = (roll >= thac0 - target-ac)
damage = 2d6 on hit
```

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

**Font looks pixelated**

DejaVu is not installed. Install `dejavu` (FreeBSD) or `fonts-dejavu` (Debian).

---

## Setting

The game is set during the **War of the Lance** on Krynn. The party begins in
**Solace, Abanasinia** and journeys across 20 locations — from Darken Wood and
Que-Shu to the New Sea, Tarsis, Qualinesti, and the dungeons of Pax Tharkas.

### Heroes of the Lance

| Character | Race | Class |
|---|---|---|
| Tanis Half-Elven | Half-Elf | Ranger |
| Raistlin Majere | Human | Wizard |
| Goldmoon | Human | Cleric of Mishakal |
| Tasslehoff Burrfoot | Kender | Thief |

### Enemies

| Monster | AC | Notes |
|---|---|---|
| Baaz Draconian | 4 | Dragonarmy infantry |
| Kapak Draconian | 4 | Venomous claws |
| Bozak Draconian | 3 | Spellcasting draconian |
| Sivak Draconian | 1 | Elite shapeshifter |
| Aurak Draconian | 2 | Most powerful draconian type |
| Blue Dragon | −1 | End boss; lightning breath |
| Red Dragon | 0 | Guards Pax Tharkas |
| Sea Serpent | 3 | New Sea waters |

---

BSD-3-Clause. Fan/educational project. Dragonlance is a trademark of Wizards of the Coast.
