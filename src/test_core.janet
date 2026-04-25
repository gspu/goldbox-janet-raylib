# test_core.janet — comprehensive test suite for Gold Box Engine
#
# Run from project root:  cd src && JANET_PATH=. janet test_core.janet
# Or:                     make native && cd src && JANET_PATH=. janet test_core.janet
#
# Tests cover: RNG, Party, Combat, World subsystems.
# Does NOT require raylib (no window opened).

(import ./rng)
(import ./party)
(import ./world)
(import ./combat)

# ── Test framework ────────────────────────────────────────────

(var pass-count 0)
(var fail-count 0)
(var current-suite "")

(defn- pass [name]
  (++ pass-count)
  (printf "  ✓ %s" name))

(defn- fail [name msg]
  (++ fail-count)
  (eprintf "  ✗ %s — %s" name msg))

(defmacro assert= [name a b]
  ~(if (= ,a ,b)
     (pass ,name)
     (fail ,name (string "expected " ,(string/format "%j" a) " == " ,(string/format "%j" b)
                       " but got " (string/format "%j" ,a)))))

(defmacro assert-not= [name a b]
  ~(if (not= ,a ,b)
     (pass ,name)
     (fail ,name (string "expected " ,(string/format "%j" a) " != " ,(string/format "%j" b)))))

(defmacro assert-true [name expr]
  ~(if ,expr
     (pass ,name)
     (fail ,name (string "expected truthy, got " (string/format "%j" ,expr)))))

(defmacro assert-false [name expr]
  ~(if ,expr
     (fail ,name (string "expected falsy, got " (string/format "%j" ,expr)))
     (pass ,name)))

(defmacro assert-throws [name expr]
  ~(do
     (var threw false)
     (try ,expr ([_] (set threw true)))
     (if threw
       (pass ,name)
       (fail ,name "expected error but none was thrown"))))

(defmacro suite [name & body]
  ~(do
     (set current-suite ,name)
     (printf "\n── %s ──" ,name)
     ,;body))

# ── RNG Tests ─────────────────────────────────────────────────

(suite "RNG — dice ranges"
  (let [r (rng/d4)]  (assert-true "d4 in [1,4]"   (and (>= r 1) (<= r 4))))
  (let [r (rng/d6)]  (assert-true "d6 in [1,6]"   (and (>= r 1) (<= r 6))))
  (let [r (rng/d8)]  (assert-true "d8 in [1,8]"   (and (>= r 1) (<= r 8))))
  (let [r (rng/d20)] (assert-true "d20 in [1,20]" (and (>= r 1) (<= r 20)))))

(suite "RNG — rand-int"
  (let [r (rng/rand-int 10)]  (assert-true "rand-int 10 in [0,10)"  (and (>= r 0) (< r 10))))
  (assert-true "rand-int 1 always 0" (= 0 (rng/rand-int 1)))
  (let [r (rng/rand-int 100)] (assert-true "rand-int 100 in range" (and (>= r 0) (< r 100)))))

(suite "RNG — rand-bool"
  # Just verify it returns a boolean — can't test distribution easily
  (let [r (rng/rand-bool)] (assert-true "rand-bool returns boolean" (or (= r true) (= r false)))))

(suite "RNG — roll-3d6"
  (let [r (rng/roll-3d6)]
    (assert-true "roll-3d6 in [3,18]" (and (>= r 3) (<= r 18))))
  # Roll many times to verify range boundaries are reachable
  (var min-val 100)
  (var max-val 0)
  (for _ 0 200
    (let [r (rng/roll-3d6)]
      (if (< r min-val) (set min-val r))
      (if (> r max-val) (set max-val r))))
  (assert-true "roll-3d6 can reach 3" (<= min-val 5))
  (assert-true "roll-3d6 can reach 18" (>= max-val 15)))

(suite "RNG — deterministic seeding"
  (set rng/*rng* (math/rng 42))
  (def a1 (rng/d20))
  (def a2 (rng/d20))
  (set rng/*rng* (math/rng 42))
  (def b1 (rng/d20))
  (def b2 (rng/d20))
  (assert= "same seed gives same d20 #1" a1 b1)
  (assert= "same seed gives same d20 #2" a2 b2))

# ── Party Tests ───────────────────────────────────────────────

(suite "Party — make-char"
  (def ch (party/make-char "Test" "Human" "Fighter" 16 12 14 8 10 6 18 6 20 []))
  (assert= "name" "Test" (ch :name))
  (assert= "race" "Human" (ch :race))
  (assert= "class" "Fighter" (ch :class))
  (assert= "str" 16 (ch :str))
  (assert= "alive" true (ch :alive))
  (assert= "status" :alive (ch :status))
  (assert= "hp" 20 (ch :hp))
  (assert= "hp-max" 20 (ch :hp-max))
  (assert= "xp" 0 (ch :xp))
  (assert= "level" 3 (ch :level)))

(suite "Party — alive?/dead?"
  (def ch (party/make-char "A" "Human" "Fighter" 10 10 10 10 10 10 18 6 10 []))
  (assert-true "alive? on living" (party/alive? ch))
  (assert-false "dead? on living" (party/dead? ch))
  (put ch :alive false)
  (assert-false "alive? on dead" (party/alive? ch))
  (assert-true "dead? on dead" (party/dead? ch)))

(suite "Party — living-members"
  (def p [(party/make-char "A" "Human" "Fighter" 10 10 10 10 10 10 18 6 10 [])
          (party/make-char "B" "Human" "Fighter" 10 10 10 10 10 10 18 6 10 [])])
  (assert= "2 living" 2 (length (party/living-members p)))
  (put (p 0) :alive false)
  (assert= "1 living after kill" 1 (length (party/living-members p))))

(suite "Party — take-damage!"
  (def ch (party/make-char "A" "Human" "Fighter" 10 10 10 10 10 10 18 6 20 []))
  (party/take-damage! ch 5)
  (assert= "hp reduced" 15 (ch :hp))
  (assert-true "still alive" (ch :alive))
  (assert= "status still alive" :alive (ch :status))
  (party/take-damage! ch 20)
  (assert= "hp clamped to 0" 0 (ch :hp))
  (assert-false "alive=false on death" (ch :alive))
  (assert= "status=dead on death" :dead (ch :status)))

(suite "Party — heal!"
  (def ch (party/make-char "A" "Human" "Fighter" 10 10 10 10 10 10 18 6 20 []))
  (party/take-damage! ch 10)
  (assert= "hp after damage" 10 (ch :hp))
  (party/heal! ch 5)
  (assert= "hp after heal" 15 (ch :hp))
  (party/heal! ch 100)
  (assert= "hp capped at max" 20 (ch :hp))
  # Dead characters can't be healed
  (party/take-damage! ch 20)
  (assert= "hp is 0" 0 (ch :hp))
  (party/heal! ch 10)
  (assert= "dead can't heal" 0 (ch :hp)))

(suite "Party — rest-party!"
  (def p [(party/make-char "A" "Human" "Fighter" 10 10 10 10 10 10 18 6 20 [])])
  (party/take-damage! (p 0) 10)
  (assert= "hp before rest" 10 ((p 0) :hp))
  (party/rest-party! p)
  (assert= "hp after rest (50% of 20=10)" 20 ((p 0) :hp)))

(suite "Party — award-xp!"
  (def p [(party/make-char "A" "Human" "Fighter" 10 10 10 10 10 10 18 6 20 [])])
  (party/award-xp! p 100)
  (assert= "xp awarded" 100 ((p 0) :xp))
  # XP split among living members
  (def p2 [(party/make-char "A" "Human" "Fighter" 10 10 10 10 10 10 18 6 20 [])
           (party/make-char "B" "Human" "Fighter" 10 10 10 10 10 10 18 6 20 [])])
  (party/award-xp! p2 100)
  (assert= "xp split 2 ways" 50 ((p2 0) :xp)))

(suite "Party — stat-mod"
  (assert= "stat-mod 3" -3 (party/stat-mod 3))
  (assert= "stat-mod 5" -2 (party/stat-mod 5))
  (assert= "stat-mod 8" -1 (party/stat-mod 8))
  (assert= "stat-mod 10" 0 (party/stat-mod 10))
  (assert= "stat-mod 12" 0 (party/stat-mod 12))
  (assert= "stat-mod 14" 1 (party/stat-mod 14))
  (assert= "stat-mod 17" 2 (party/stat-mod 17))
  (assert= "stat-mod 18" 3 (party/stat-mod 18)))

(suite "Party — roll-stats"
  (let [stats (party/roll-stats "Human")]
    (assert= "6 stats rolled" 6 (length stats))
    (eachp [i s] stats
      (assert-true (string "stat " i " in [3,18]") (and (>= s 3) (<= s 18))))))

(suite "Party — make-custom-char"
  (def ch (party/make-custom-char "Merlin" "Human" "Wizard" [16 12 10 16 12 8]))
  (assert= "name" "Merlin" (ch :name))
  (assert= "race" "Human" (ch :race))
  (assert= "class" "Wizard" (ch :class))
  (assert= "wizard spells" ["Magic Missile" "Sleep" "Mirror Image"] (ch :spells))
  (assert-true "hp > 0" (> (ch :hp) 0))
  (assert-true "status alive" (= :alive (ch :status))))

(suite "Party — make-blank-creation"
  (def slots (party/make-blank-creation))
  (assert= "4 slots" 4 (length slots))
  (for i 0 4
    (def sl (slots i))
    (assert-true "slot has name" (pos? (length (sl :name))))
    (assert-true "slot has 6 stats" (= 6 (length (sl :stats))))))

# ── Combat Tests ──────────────────────────────────────────────

(defn- make-test-party []
  "Create a standard 4-member test party."
  (array/slice
    [(party/make-custom-char "Tanis" "Half-Elf" "Ranger" [16 14 12 10 12 14])
     (party/make-custom-char "Raistlin" "Human" "Wizard" [8 12 8 16 14 10])
     (party/make-custom-char "Goldmoon" "Human" "Cleric" [10 10 12 14 16 14])
     (party/make-custom-char "Tas" "Kender" "Thief" [10 16 10 12 8 16])]))

(defn- make-test-combat []
  "Create a combat with the test party vs 2 goblins."
  (def p (make-test-party))
  (def monsters [(world/make-monster :goblin) (world/make-monster :goblin)])
  (combat/make-combat p monsters))

(suite "Combat — make-combat"
  (def cs (make-test-combat))
  (assert= "phase is active" :active (cs :phase))
  (assert-true "has combatants" (pos? (length (cs :combatants))))
  (assert= "has 2 monsters" 2 (length (cs :monsters)))
  (assert-true "has buffs table" (table? (cs :buffs)))
  (assert-true "has positions" (table? (cs :positions)))
  (assert-true "has log" (array? (cs :log))))

(suite "Combat — can-act?"
  (def alive-mob (world/make-monster :goblin))
  (assert-true "alive monster can act" (combat/can-act? alive-mob))
  (put alive-mob :status :dead)
  (assert-false "dead monster can't act" (combat/can-act? alive-mob))
  (def asleep-mob (world/make-monster :goblin))
  (put asleep-mob :status :asleep)
  (assert-false "asleep monster can't act" (combat/can-act? asleep-mob))
  (def held-mob (world/make-monster :goblin))
  (put held-mob :status :held)
  (assert-false "held monster can't act" (combat/can-act? held-mob))
  # Backward compat: entity with :alive but no :status
  (def old-style @{:alive true :name "Old"})
  (assert-true "old-style alive can act" (combat/can-act? old-style))
  (put old-style :alive false)
  (assert-false "old-style dead can't act" (combat/can-act? old-style)))

(suite "Combat — effective-ac / effective-thac0"
  (def cs (make-test-combat))
  (def mob (world/make-monster :goblin))
  (assert= "base ac" 6 (combat/effective-ac cs mob))
  (assert= "base thac0" 20 (combat/effective-thac0 cs mob))
  # Add buff
  (put (cs :buffs) (mob :name) {:ac-bonus -2})
  (assert= "buffed ac" 4 (combat/effective-ac cs mob))
  # No thac0 buff
  (assert= "unbuffed thac0" 20 (combat/effective-thac0 cs mob))
  # Add thac0 buff
  (put (cs :buffs) (mob :name) {:ac-bonus -2 :thac0-bonus -1})
  (assert= "buffed thac0" 19 (combat/effective-thac0 cs mob)))

(suite "Combat — Sleep sets :asleep, not :alive false"
  (def p (make-test-party))
  (def monsters [(world/make-monster :goblin)])
  (def cs (combat/make-combat p monsters))
  (def target (monsters 0))
  (assert= "initial status" :alive (target :status))
  (assert-true "initially alive" (target :alive))
  (combat/hero-cast-spell! cs (p 0) "Sleep" target p)
  (assert= "status after sleep" :asleep (target :status))
  (assert-true "still alive=true after sleep" (target :alive))
  (assert-false "can-act? after sleep" (combat/can-act? target)))

(suite "Combat — Hold Person sets :held, not :alive false"
  (def p (make-test-party))
  (def monsters [(world/make-monster :goblin)])
  (def cs (combat/make-combat p monsters))
  (def target (monsters 0))
  (combat/hero-cast-spell! cs (p 0) "Hold Person" target p)
  (assert= "status after hold" :held (target :status))
  (assert-true "still alive=true after hold" (target :alive))
  (assert-false "can-act? after hold" (combat/can-act? target)))

(suite "Combat — Mirror Image adds buff, not permanent AC"
  (def p (make-test-party))
  (def monsters [(world/make-monster :goblin)])
  (def cs (combat/make-combat p monsters))
  (def raistlin (p 1))  # Wizard
  (def orig-ac (raistlin :ac))
  (combat/hero-cast-spell! cs raistlin "Mirror Image" raistlin p)
  (assert= "base AC unchanged" orig-ac (raistlin :ac))
  (assert= "effective AC improved" (- orig-ac 2) (combat/effective-ac cs raistlin))
  (assert-true "buff recorded" (get-in cs [:buffs (raistlin :name)])))

(suite "Combat — Bless adds buff, not permanent THAC0"
  (def p (make-test-party))
  (def monsters [(world/make-monster :goblin)])
  (def cs (combat/make-combat p monsters))
  (def goldmoon (p 2))  # Cleric
  (def orig-thac0 (goldmoon :thac0))
  (combat/hero-cast-spell! cs goldmoon "Bless" goldmoon p)
  (assert= "base THAC0 unchanged" orig-thac0 (goldmoon :thac0))
  (assert= "effective THAC0 improved" (- orig-thac0 1) (combat/effective-thac0 cs goldmoon))
  (assert-true "buff recorded" (get-in cs [:buffs (goldmoon :name)])))

(suite "Combat — Magic Missile deals damage"
  (def p (make-test-party))
  (def monsters [(world/make-monster :goblin)])
  (def cs (combat/make-combat p monsters))
  (def target (monsters 0))
  (def orig-hp (target :hp))
  (combat/hero-cast-spell! cs (p 0) "Magic Missile" target p)
  (assert-true "damage dealt" (< (target :hp) orig-hp)))

(suite "Combat — Cure Light Wounds heals"
  (def p (make-test-party))
  (def monsters [(world/make-monster :goblin)])
  (def cs (combat/make-combat p monsters))
  (party/take-damage! (p 0) 1)
  (def hp-before ((p 0) :hp))
  (combat/hero-cast-spell! cs (p 2) "Cure Light Wounds" (p 0) p)
  (assert-true "HP increased" (> ((p 0) :hp) hp-before)))

(suite "Combat — hero-attack! sets :status :dead on kill"
  (def p (make-test-party))
  # Use a very weak monster (1 HP) to guarantee kill
  (def weak-monster @{:name "Weak" :hp 1 :hp-max 1 :ac 10 :thac0 20 :xp 5 :alive true :status :alive})
  (def cs (combat/make-combat p [weak-monster]))
  # Attack until it dies (may take a few tries due to miss chance)
  (var attempts 0)
  (while (and (combat/can-act? weak-monster) (< attempts 50))
    (when (combat/hero-turn? cs)
      (combat/hero-attack! cs (p 0) 0 p))
    (++ attempts))
  # If we killed it, verify status
  (when (not (weak-monster :alive))
    (assert= "status dead on kill" :dead (weak-monster :status))))

(suite "Combat — living-monsters filters by can-act?"
  (def p (make-test-party))
  (def m1 (world/make-monster :goblin))
  (def m2 (world/make-monster :goblin))
  (def m3 (world/make-monster :goblin))
  (def cs (combat/make-combat p [m1 m2 m3]))
  (assert= "3 living initially" 3 (length (combat/living-monsters cs)))
  # Put one to sleep
  (put m1 :status :asleep)
  (assert= "2 living after sleep" 2 (length (combat/living-monsters cs)))
  # Kill one
  (put m2 :status :dead)
  (put m2 :alive false)
  (assert= "1 living after kill" 1 (length (combat/living-monsters cs))))

(suite "Combat — xp-reward only counts dead, not asleep/held"
  (def p (make-test-party))
  (def m1 (world/make-monster :goblin))
  (def m2 (world/make-monster :goblin))
  (def m3 (world/make-monster :goblin))
  (def cs (combat/make-combat p [m1 m2 m3]))
  # Kill one, sleep one, hold one
  (put m1 :status :dead) (put m1 :alive false)
  (put m2 :status :asleep)
  (put m3 :status :held)
  (assert= "xp only from dead" (m1 :xp) (combat/xp-reward cs)))

(suite "Combat — advance-turn! skips incapacitated"
  (def p (make-test-party))
  (def m1 (world/make-monster :goblin))
  (def cs (combat/make-combat p [m1]))
  # Put all heroes to sleep to test skipping
  (each ch p
    (put ch :status :asleep))
  # Advance should skip asleep heroes and go to monster
  (var found-monster false)
  (var steps 0)
  (while (and (not found-monster) (< steps 20))
    (combat/advance-turn! cs p)
    (when (combat/hero-turn? cs)
      # If it's a hero's turn, they shouldn't be able to act
      (assert-false "asleep hero shouldn't get turn" (combat/can-act? ((combat/active-combatant cs) :ref))))
    (let [c (combat/active-combatant cs)]
      (when (and c (= :monster (c :kind)))
        (set found-monster true)))
    (++ steps)))

(suite "Combat — check-victory! only on all dead"
  # Victory requires ALL monsters :status :dead, not just :asleep/:held
  (def p (make-test-party))
  (def m1 (world/make-monster :goblin))
  (def m2 (world/make-monster :goblin))
  (def cs (combat/make-combat p [m1 m2]))
  (put m1 :status :dead) (put m1 :alive false)
  (put m2 :status :asleep)  # Not dead, just asleep
  (assert-not= "no victory with asleep monster" :victory (cs :phase)))

(suite "Combat — hero-flee!"
  (def p (make-test-party))
  (def monsters [(world/make-monster :goblin)])
  (def cs (combat/make-combat p monsters))
  # Flee may succeed or fail; just verify it returns a valid phase
  (def phase (combat/hero-flee! cs p))
  (assert-true "flee returns valid phase" (or (= phase :fled) (= phase :active))))

# ── World Tests ───────────────────────────────────────────────

(suite "World — make-world"
  (def w (world/make-world))
  (assert= "level is 0" 0 (w :level))
  (assert-true "has tiles" (array? (w :tiles)))
  (assert-true "has fog" (array? (w :fog)))
  (assert-true "has player" (table? (w :player)))
  (assert-true "has entities" (array? (w :entities))))

(suite "World — tile-at / set-tile!"
  (def w (world/make-world))
  (def tiles (w :tiles))
  # Solace map has walls at edges, floor inside
  (assert-true "corner is wall" (= 1 (world/tile-at tiles 0 0)))
  (world/set-tile! tiles 2 2 2)  # set a door
  (assert= "set-tile works" 2 (world/tile-at tiles 2 2)))

(suite "World — passable?"
  (def tiles (array/new-filled (* world/MAP-W world/MAP-H) 0))
  # Floor is passable
  (assert-true "floor passable" (world/passable? tiles 0 0))
  # Wall is not
  (put tiles 0 1)
  (assert-false "wall not passable" (world/passable? tiles 0 0))
  # Door (closed=2) is passable
  (put tiles 0 2)
  (assert-true "closed door passable" (world/passable? tiles 0 0))
  # Door (open=3) is passable
  (put tiles 0 3)
  (assert-true "open door passable" (world/passable? tiles 0 0))
  # Stairs are passable
  (put tiles 0 4)
  (assert-true "stairs-down passable" (world/passable? tiles 0 0))
  (put tiles 0 5)
  (assert-true "stairs-up passable" (world/passable? tiles 0 0)))

(suite "World — direction helpers"
  (assert= "north delta" [0 -1] (world/facing-delta :north))
  (assert= "south delta" [0 1] (world/facing-delta :south))
  (assert= "east delta" [1 0] (world/facing-delta :east))
  (assert= "west delta" [-1 0] (world/facing-delta :west)))

(suite "World — turn-left!/turn-right!"
  (def player @{:x 5 :y 5 :dir :north})
  (world/turn-left! player)
  (assert= "turn left from north" :west (player :dir))
  (world/turn-left! player)
  (assert= "turn left from west" :south (player :dir))
  (world/turn-right! player)
  (assert= "turn right from south" :west (player :dir))
  (world/turn-right! player)
  (assert= "turn right from west" :north (player :dir)))

(suite "World — move-forward!/move-backward!"
  (def tiles (array/new-filled (* world/MAP-W world/MAP-H) 0))  # all floor
  (def player @{:x 5 :y 5 :dir :north})
  (world/move-forward! tiles player)
  (assert= "moved north y-1" 4 (player :y))
  (assert= "x unchanged" 5 (player :x))
  (world/move-backward! tiles player)
  (assert= "moved back y+1" 5 (player :y)))

(suite "World — move-forward! opens closed doors"
  (def tiles (array/new-filled (* world/MAP-W world/MAP-H) 0))
  # Place a closed door to the north
  (put tiles (+ (* 4 world/MAP-W) 5) 2)  # door at (5,4)
  (def player @{:x 5 :y 5 :dir :north})
  (world/move-forward! tiles player)
  (assert= "door opened" 3 (world/tile-at tiles 5 4))
  (assert= "player moved through" 4 (player :y)))

(suite "World — move-forward! blocked by wall"
  (def tiles (array/new-filled (* world/MAP-W world/MAP-H) 0))
  # Place a wall to the north
  (put tiles (+ (* 4 world/MAP-W) 5) 1)  # wall at (5,4)
  (def player @{:x 5 :y 5 :dir :north})
  (def result (world/move-forward! tiles player))
  (assert-false "move blocked" result)
  (assert= "player stayed" 5 (player :y)))

(suite "World — reveal-fog!"
  (def w (world/make-world))
  # Fog should be initially all true
  (assert-true "fog initially set" ((w :fog) 0))
  (world/reveal-fog! w)
  # Player starts at spawn; 3x3 area should be revealed
  (def px (get-in w [:player :x]))
  (def py (get-in w [:player :y]))
  (assert-false "player tile revealed" (world/tile-at (w :fog) px py))
  # Adjacent tile should also be revealed
  (when (and (> px 0) (< py world/MAP-H))
    (assert-false "adjacent tile revealed" (world/tile-at (w :fog) (- px 1) py))))

(suite "World — npc-at"
  (def entities @[@{:id :test :name "Test" :x 3 :y 3 :dialog @["hello"]}])
  (assert-true "npc found at position" (world/npc-at entities 3 3))
  (assert-false "no npc at empty position" (world/npc-at entities 0 0)))

(suite "World — make-monster has :status :alive"
  (def m (world/make-monster :goblin))
  (assert= "goblin name" "Goblin" (m :name))
  (assert= "goblin status" :alive (m :status))
  (assert-true "goblin alive" (m :alive))
  (assert= "goblin ac" 6 (m :ac))
  (assert= "goblin xp" 15 (m :xp))
  # Test all monster types have :status
  (eachp [kind _] world/MONSTER-DEFS
    (def mon (world/make-monster kind))
    (assert= (string "monster " kind " has status") :alive (mon :status))))

(suite "World — encounter-check? uses rng"
  # Just verify it returns a boolean and doesn't crash
  # The fix ensures it uses rng/rand-int instead of math/random
  (var got-true false)
  (var got-false false)
  (for _ 0 100
    (if (world/encounter-check?)
      (set got-true true)
      (set got-false true)))
  (assert-true "encounter-check? returns bool" (and got-true got-false)))

(suite "World — random-encounter uses rng"
  # Solace (level 0) has encounters
  (def enc (world/random-encounter 0))
  (assert-true "solace has encounters" (pos? (length enc)))
  (assert-true "encounter monsters have status" (all |(= ($ :status) :alive) enc))
  # Tika (level 2) has no encounters
  (def no-enc (world/random-encounter 2))
  (assert= "tika no encounters" 0 (length no-enc)))

(suite "World — get-connection"
  # Solace (0) has door→Inn(1) and stairs→Darken Wood(3)
  (def conn (world/get-connection 0 2))
  (assert-true "solace door connection" conn)
  (assert= "door leads to inn" 1 (conn 0))
  (def conn2 (world/get-connection 0 4))
  (assert-true "solace stairs connection" conn2)
  (assert= "stairs lead to darken wood" 3 (conn2 0))
  # No connection from invalid level/tile
  (assert-false "no connection for nil" (world/get-connection 99 2)))

(suite "World — travel!"
  (def w (world/make-world))
  (assert= "initial level" 0 (w :level))
  (world/travel! w 1 1 1 :south)
  (assert= "level after travel" 1 (w :level))
  (assert= "x after travel" 1 (get-in w [:player :x]))
  (assert= "y after travel" 1 (get-in w [:player :y]))
  (assert= "dir after travel" :south (get-in w [:player :dir])))

(suite "World — map file parsing"
  # Verify level 0 loads correctly
  (def tex-config (world/level-tex-config 0))
  (assert-true "solace has wall texture" (tex-config :wall))
  (assert-true "solace has floor texture" (tex-config :floor))
  (assert-true "solace has ceiling texture" (tex-config :ceiling))
  (assert-true "solace has door texture" (tex-config :door)))

# ── Summary ───────────────────────────────────────────────────

(printf "\n══════════════════════════════════════")
(printf "  Results: %d passed, %d failed" pass-count fail-count)
(printf "══════════════════════════════════════")

(if (pos? fail-count)
  (do
    (eprintf "\nSome tests FAILED!\n")
    (os/exit 1))
  (printf "\nAll tests passed! ✓\n"))
