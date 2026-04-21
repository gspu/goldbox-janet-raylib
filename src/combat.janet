# combat.janet — THAC0 combat, initiative, monster AI, spells
(import ./rng)
(import ./party)

# ── Combat state factory ──────────────────────────────────────

(defn make-combat [party-members monsters]
  "Build a fresh combat state table.
   Rolls initiative for every participant and sorts descending.
   Assigns isometric grid starting positions: heroes on left,
   monsters on right of a 12×8 battlefield."
  (let [combatants
        (array/concat
          (map (fn [ch]
                 @{:kind      :hero
                   :ref       ch
                   :name      (ch :name)
                   :initiative (+ (rng/d6) (party/stat-mod (ch :dex)))})
               (filter party/alive? party-members))
          (map (fn [m]
                 @{:kind       :monster
                   :ref        m
                   :name       (m :name)
                   :initiative (rng/d6)})
               monsters))]
    (sort-by |(- ($ :initiative)) combatants)

    # Assign starting grid positions.
    # Heroes occupy cols 1-2 on the left, monsters cols 8-10 on the right.
    # Rows are staggered so figures never overlap.
    (def hero-slots    [[2 0] [1 2] [2 4] [1 6]])
    (def monster-slots [[9 0] [10 2] [9 4] [10 6] [8 1] [11 3] [8 5] [10 0]])
    (def positions @{})
    (var hero-n 0)
    (var mon-n  0)
    (eachp [i c] combatants
      (if (= :hero (c :kind))
        (do (when (< hero-n (length hero-slots))
              (put positions i (hero-slots hero-n)))
            (++ hero-n))
        (do (when (< mon-n (length monster-slots))
              (put positions i (monster-slots mon-n)))
            (++ mon-n))))

    @{:combatants combatants
      :monsters   monsters
      :positions  positions
      :turn-idx   0
      :phase      :active   # :active | :victory | :defeat
      :buffs      @{}
      :log        @[]}))

# ── Logging ───────────────────────────────────────────────────

(defn- log! [state msg]
  (array/push (state :log) msg))

# ── Entity status helpers ─────────────────────────────────────

(defn can-act? [entity]
  "True if entity is alive and not incapacitated (asleep/held)."
  (let [s (entity :status)]
    (if s
      (= s :alive)
      (entity :alive))))

(defn effective-ac [combat-state entity]
  "Return AC with any active buffs applied."
  (let [base-ac (entity :ac)
        buffs (get-in combat-state [:buffs (entity :name)])]
    (if buffs
      (+ base-ac (or (buffs :ac-bonus) 0))
      base-ac)))

(defn effective-thac0 [combat-state entity]
  "Return THAC0 with any active buffs applied."
  (let [base-thac0 (entity :thac0)
        buffs (get-in combat-state [:buffs (entity :name)])]
    (if buffs
      (+ base-thac0 (or (buffs :thac0-bonus) 0))
      base-thac0)))

# ── THAC0 attack resolution ───────────────────────────────────

(defn- resolve-attack [combat-state attacker target]
  "Return [hit? damage] for one attack roll."
  (let [roll   (rng/d20)
        thac0  (effective-thac0 combat-state attacker)
        ac     (effective-ac combat-state target)
        hit    (>= roll (- thac0 ac))
        dmg    (if hit (+ (rng/d6) (rng/d6)) 0)]
    [hit dmg]))

# ── Spell resolution ──────────────────────────────────────────

(defn- resolve-spell [caster spell-name target combat-state log-fn]
  (case spell-name
    "Magic Missile"
      (let [dmg (+ 1 (rng/d4))]
        (party/take-damage! target dmg)
        (log-fn (string (caster :name) " fires Magic Missile for " dmg " damage!")))
    "Sleep"
      (do
        (put target :status :asleep)
        (log-fn (string (caster :name) " casts Sleep! " (target :name) " falls asleep!")))
    "Mirror Image"
      (do
        (put (combat-state :buffs) (caster :name) {:ac-bonus -2})
        (log-fn (string (caster :name) " creates mirror images. AC improved!")))
    "Cure Light Wounds"
      (let [heal (+ 1 (rng/d8))]
        (party/heal! target heal)
        (log-fn (string (caster :name) " heals " (target :name) " for " heal " HP.")))
    "Hold Person"
      (do
        (put target :status :held)
        (log-fn (string (caster :name) " casts Hold Person! " (target :name) " is paralysed!")))
    "Bless"
      (do
        (put (combat-state :buffs) (caster :name) {:thac0-bonus -1})
        (log-fn (string (caster :name) " calls Mishakal's blessing. THAC0 improved!")))
    # default
    (log-fn (string (caster :name) " fumbles the spell."))))

# ── Monster AI ────────────────────────────────────────────────

(defn- monster-turn! [state combatant heroes]
  (let [target (find can-act? heroes)]
    (if target
      (let [[hit dmg] (resolve-attack state (combatant :ref) target)]
        (if hit
          (do
            (party/take-damage! target dmg)
            (log! state (string (combatant :name) " hits " (target :name)
                                " for " dmg " damage!")))
          (log! state (string (combatant :name) " misses " (target :name) "."))))
      (log! state (string (combatant :name) " has no target.")))))

# ── Phase checks ──────────────────────────────────────────────

(defn- check-victory! [state heroes monsters]
  (when (all |(= ($ :status) :dead) monsters)
    (put state :phase :victory)
    (log! state "Victory! The enemy is defeated.")))

(defn- check-defeat! [state heroes]
  (when (all |(= ($ :status) :dead) heroes)
    (put state :phase :defeat)
    (log! state "The party has fallen... Game over.")))

# ── Public API ────────────────────────────────────────────────

(defn active-combatant [state]
  (let [cs (state :combatants)]
    (when (pos? (length cs))
      (cs (% (state :turn-idx) (length cs))))))

(defn hero-turn? [state]
  (let [c (active-combatant state)]
    (and c (= :hero (c :kind)) (can-act? (c :ref)))))

(defn living-monsters [state]
  (filter can-act? (state :monsters)))

(defn living-heroes [state combatants]
  (filter |(and (= :hero ($ :kind)) (can-act? ($ :ref))) combatants))

(defn advance-turn! [state]
  "Move to the next combatant, skipping dead/incapacitated ones.
   Returns the new phase keyword."
  (let [cs    (state :combatants)
        total (length cs)]
    (when (pos? total)
      (var steps 0)
      (put state :turn-idx (% (+ (state :turn-idx) 1) total))
      # Skip dead/incapacitated combatants (guard against infinite loop)
      (while (and (< steps total)
                  (let [c (cs (state :turn-idx))]
                    (not (can-act? (c :ref)))))
        (put state :turn-idx (% (+ (state :turn-idx) 1) total))
        (++ steps))
      # Auto-run monster turns immediately
      (let [c (cs (state :turn-idx))]
        (when (and (= :monster (c :kind)) (can-act? (c :ref))
                   (= :active (state :phase)))
          (let [heroes (map |($ :ref) (living-heroes state cs))]
            (monster-turn! state c heroes)
            (check-victory! state heroes (state :monsters))
            (check-defeat!  state heroes)
            (when (= :active (state :phase))
              (advance-turn! state)))))))
  (state :phase))

(defn hero-attack! [state hero target-idx]
  "The active hero attacks the monster at target-idx.
   Returns the new phase keyword."
  (let [monsters (living-monsters state)]
    (when (and (< target-idx (length monsters)) (= :active (state :phase)))
      (let [target    (monsters target-idx)
            [hit dmg] (resolve-attack state hero target)]
        (if hit
          (do
            (put target :hp (max 0 (- (target :hp) dmg)))
            (when (<= (target :hp) 0)
              (put target :alive false)
              (put target :status :dead))
            (log! state (string (hero :name) " hits " (target :name)
                                " for " dmg " damage!"
                                (if (not (target :alive)) " Slain!" ""))))
          (log! state (string (hero :name) " misses " (target :name) ".")))))
    (let [heroes (map |($ :ref)
                      (filter |(= :hero ($ :kind)) (state :combatants)))]
      (check-victory! state heroes (state :monsters))
      (check-defeat!  state heroes))
    (when (= :active (state :phase))
      (advance-turn! state)))
  (state :phase))

(defn hero-cast-spell! [state caster spell-name target]
  "The caster uses spell-name on target.
   target may be a hero (for healing) or a monster (for offensive spells)."
  (resolve-spell caster spell-name target state (fn [msg] (log! state msg)))
  (let [heroes (map |($ :ref)
                    (filter |(= :hero ($ :kind)) (state :combatants)))]
    (check-victory! state heroes (state :monsters))
    (check-defeat!  state heroes))
  (when (= :active (state :phase))
    (advance-turn! state))
  (state :phase))

(defn hero-flee! [state]
  "50 % chance to escape; on failure the monsters get a free round."
  (if (rng/rand-bool)
    (do
      (log! state "The party flees!")
      (put state :phase :fled))
    (do
      (log! state "Escape blocked!")
      (advance-turn! state)))
  (state :phase))

(defn combat-log [state]
  "Return the last 6 log entries."
  (let [lg (state :log)
        n  (length lg)]
    (if (<= n 6)
      lg
      (array/slice lg (- n 6)))))

(defn xp-reward [state]
  "Sum XP values of all slain monsters."
  (reduce (fn [acc m] (+ acc (if (= (m :status) :dead) (m :xp) 0)))
          0
          (state :monsters)))
