# Gold Box Engine

A "vibe" recreation of the SSI Gold Box RPG engine,
written in [Janet](https://janet-lang.org/) with a raylib C native module,
targeting **FreeBSD** and **Linux**.

```
## Prerequisites

### FreeBSD
```sh
pkg install janet jpm raylib dejavu
```

### Linux (Debian / Ubuntu)
```sh
sudo apt install janet libraylib-dev fonts-dejavu
```

### Linux (Arch)
```sh
sudo pacman -S janet raylib ttf-dejavu
```

| Package | Purpose |
|---|---|
| `janet` | Language runtime |
| `raylib` | Window, renderer, input, font |
| `dejavu` | DejaVu Mono font (UI text, optional) |

raylib ships its own font renderer — there is no separate TTF library dependency.
The game falls back to raylib's built-in bitmap font if DejaVu is not installed.

---

## Building

```sh
cd goldbox-janet
make clean && make native
```

This compiles `janet_raylib.c` into `janet_raylib.so` and copies it into `src/`.

Verify the export:

```sh
make symbols
```

Expected output:

```
OK: _janet_init exported
```

---

## Running

```sh
make run
```

Or directly:

```sh
cd src && janet main.janet
```

---

## Debugging

```sh
make debug
```

Runs `src/debug.janet` — a 41-step diagnostic that tests every subsystem in
isolation.  The last printed step number tells you exactly where a crash occurred.

Steps 1–17 are pure Janet (no native module).  Step 18 imports `janet_raylib`,
step 20 opens the window, step 27 loads the font, steps 28–35 exercise every draw
call, steps 36–37 test the event ring-buffer.

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
| `Enter` | Interact (chest, stairs) |
| `F1`–`F4` | Select active party member |

### Combat

| Key | Action |
|---|---|
| `A` / `Enter` | Attack selected target |
| `S` | Cast spell |
| `F` | Attempt to flee |

---

## Project Structure

```
goldbox-janet/
├── Makefile              # Build system (BSD make / GNU make compatible)
├── janet_raylib.c        # C native module: raylib bindings for Janet
├── janet_raylib.map      # ELF linker version script (exports _janet_init only)
├── src/
│   ├── main.janet        # Entry point, main loop, window lifetime
│   ├── engine.janet      # Input dispatch, state machine, message bus
│   ├── world.janet       # Tile maps, entity system, fog-of-war, two levels
│   ├── party.janet       # Characters, D&D stats, XP, levelling
│   ├── combat.janet      # THAC0 combat, initiative, monster AI, spells
│   ├── ui.janet          # Gold Box split-screen renderer (1024×768)
│   ├── rng.janet         # Shared RNG (d6, d20, rand-int, rand-bool)
│   └── debug.janet       # 41-step crash diagnostic
└── maps/                 # Reserved for future .map file format
```

### Screen Layout (1024×768)

```
[title bar                                  1024×32 ]
[3D view 512×420] [text panel 310×420] [minimap 202×420]
[party stats bar                            1024×100]
[message log                                1024×36 ]
```

---

### Game state

A single mutable table threaded through all subsystems:

```janet
@{:mode        :explore      # :explore | :combat | :dialog | :inventory
  :world       {...}         # tiles, entities, player, fog, level
  :party       [...]         # array of character tables
  :active-idx  0             # currently selected party member
  :combat      {...}         # active combat state, or nil
  :dialog-npc  {...}         # NPC being talked to, or nil
  :messages    [...]         # scrolling message log (last 6 lines)
  :tick        0             # frame counter
  :running     true}         # set to false to exit the main loop
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

**`could not find module ./janet_raylib`**
```sh
make clean && make native
```

**Signal 11 (segfault) on startup**

Run `make debug`.  Most common causes:
- `src/janet_raylib.so` missing — run `make native` first
- `BeginDrawing` called outside a window — `rl/clear` must follow `rl/create-window`

**Font looks pixelated / wrong size**

DejaVu is not installed; the game is using raylib's built-in 8×8 bitmap font.
Install `dejavu` (FreeBSD) or `fonts-dejavu` (Debian).

---

## Setting

The game is set during the **War of the Lance** on Krynn.  The party begins in
**Solace, Abanasinia** and descends into the **Ruins of Xak Tsaroth** in search
of the Disks of Mishakal.

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

---

BSD-3-Clause. Fan/educational project. Dragonlance is a trademark of Wizards of the Coast.
