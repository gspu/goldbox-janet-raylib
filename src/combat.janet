# combat.janet — THAC0 combat, initiative, monster AI, spells
(import ./rng)
(import ./party)

# ── Combat state factory ──────────────────────────────────────

(defn make-combat [party-members monsters]
  "Build a fresh combat state table.
   All living party members fight.
   Monsters roll initiative and act after heroes.
   Assigns isometric grid starting positions: heroes on left,
   monsters on right of a 12×8 battlefield."
  # Build hero combatants for all living party members
  (def heroes @[])
  (each pm party-members
    (when (party/alive? pm)
      (array/push heroes @{:kind       :hero
                          :ref        pm
                          :name       (pm :name)
                          :party-idx  (length heroes)
                          :initiative (+ (rng/d6) (party/stat-mod (pm :dex)))})))

  # Build monster combatants with initiative
  (def monster-combatants
    (map (fn [m]
           @{:kind       :monster
             :ref        m
             :name       (m :name)
             :initiative (rng/d6)})
         monsters))

  # Combine: heroes first, then monsters sorted by initiative
  (def combatants
    (array/concat heroes (sort-by |(- ($ :initiative)) monster-combatants)))

  # Assign starting grid positions.
  # Heroes on left, monsters on right.
  (def positions @{})
  # Place heroes in rows on left side (column 2, increasing rows)
  (var hero-row 0)
  (eachp [i c] combatants
    (when (= :hero (c :kind))
      (put positions i [2 hero-row])
      (set hero-row (+ hero-row 1))
      (when (>= hero-row 8) (set hero-row 0))))
  # Place monsters on right side
  (var mon-n 0)
  (eachp [i c] combatants
    (when (= :monster (c :kind))
      (when (< mon-n 8)
        (put positions i [(+ 8 (mod mon-n 4)) (if (even? mon-n) 0 2)])
        (++ mon-n))))

  @{:combatants combatants
    :monsters   monsters
    :positions  positions
    :turn-idx   0
    :phase      :active   # :active | :victory | :defeat
    :buffs      @{}
    :log        @[]})

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

(defn- check-victory! [state]
  (let [monsters (state :monsters)]
    (when (all |(= ($ :status) :dead) monsters)
      (put state :phase :victory)
      (log! state "Victory! The enemy is defeated."))))

(defn- check-defeat! [state]
  (let [heroes (filter |(and (= :hero ($ :kind)) (can-act? ($ :ref))) (state :combatants))]
    (when (empty? heroes)
      (put state :phase :defeat)
      (log! state "The party has fallen... Game over."))))



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

(defn advance-turn! [state party]
  (let [cs (state :combatants) total (length cs)]
    (when (pos? total)
      # Loop up to total times to find the next combatant that can act.
      (var tries 0)
      (var done false)
      (while (and (< tries total) (not done) (= :active (state :phase)))
        # Move to next combatant
        (put state :turn-idx (% (+ (state :turn-idx) 1) total))
        (let [c (cs (state :turn-idx))]
          (when (can-act? (c :ref))
            (cond
              (= :monster (c :kind))
                (do
                  (let [hs (map |($ :ref) (living-heroes state cs))]
                    (monster-turn! state c hs)
                    (check-victory! state)
                    (check-defeat! state))
                  # after monster turn, continue loop to next combatant
                  )
              (= :hero (c :kind))
                (do
                  # set this hero as active in party
                  (let [hero-ref (c :ref)]
                    (each ch party (put ch :active false))
                    (put hero-ref :active true))
                  (set done true))
              # else: unknown kind, stop
              (set done true))))
        (++ tries))
      (when (>= tries total)
        # No combatant could act; ensure phase is updated
        (check-victory! state)
        (check-defeat! state))
      (state :phase))))

(defn hero-attack! [state hero target-idx party]
  (let [mns (living-monsters state)]
    (when (and (< target-idx (length mns)) (= :active (state :phase)))
      (let [tgt (mns target-idx) [hit dmg] (resolve-attack state hero tgt)]
        (if hit
          (do (put tgt :hp (max 0 (- (tgt :hp) dmg)))
              (when (<= (tgt :hp) 0) (put tgt :alive false) (put tgt :status :dead))
              (log! state (string (hero :name) " hits " (tgt :name) " for " dmg " dmg!" (if (not (tgt :alive)) " Slain!" ""))))
          (log! state (string (hero :name) " misses " (tgt :name) "."))))
      (let [hs (map |($ :ref) (filter |(= :hero ($ :kind)) (state :combatants)))]
        (check-victory! state)
        (check-defeat! state))
      ))
  (state :phase))

(defn hero-cast-spell! [state caster spell-name target party]
  (resolve-spell caster spell-name target state (fn [msg] (log! state msg)))
  (check-victory! state)
  (check-defeat! state)
  (when (= :active (state :phase)) (advance-turn! state party))
  (state :phase))

(defn hero-flee! [state party]
  (if (rng/rand-bool)
    (do (log! state "The party flees!") (put state :phase :fled))
    (do (log! state "Escape blocked!")))
  (state :phase))

(defn combat-log [state]
  (let [lg (state :log) n (length lg)]
    (if (<= n 6) lg (array/slice lg (- n 6)))))

(defn xp-reward [state]
  (reduce (fn [acc m] (+ acc (if (= (m :status) :dead) (m :xp) 0))) 0 (state :monsters)))
