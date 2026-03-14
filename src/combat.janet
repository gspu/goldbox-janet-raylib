# combat.janet — THAC0 combat, initiative, monster AI, spells
(import ./rng)
(import ./party)

# ── Combat state factory ──────────────────────────────────────

(defn make-combat [party-members monsters]
  "Build a fresh combat state table.
   Rolls initiative for every participant and sorts descending."
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
    @{:combatants combatants
      :monsters   monsters
      :turn-idx   0
      :phase      :active   # :active | :victory | :defeat
      :log        @[]}))

# ── Logging ───────────────────────────────────────────────────

(defn- log! [state msg]
  (array/push (state :log) msg))

# ── THAC0 attack resolution ───────────────────────────────────

(defn- resolve-attack [attacker target]
  "Return [hit? damage] for one attack roll."
  (let [roll   (rng/d20)
        thac0  (attacker :thac0)
        ac     (target  :ac)
        hit    (>= roll (- thac0 ac))
        dmg    (if hit (+ (rng/d6) (rng/d6)) 0)]
    [hit dmg]))

# ── Spell resolution ──────────────────────────────────────────

(defn- resolve-spell [caster spell-name target log-fn]
  (case spell-name
    "Magic Missile"
      (let [dmg (+ 1 (rng/d4))]
        (party/take-damage! target dmg)
        (log-fn (string (caster :name) " fires Magic Missile for " dmg " damage!")))
    "Sleep"
      (do
        (put target :alive false)  # treated as incapacitation for simplicity
        (log-fn (string (caster :name) " casts Sleep! " (target :name) " falls asleep!")))
    "Mirror Image"
      (do
        (put caster :ac (- (caster :ac) 2))   # temporary AC bonus
        (log-fn (string (caster :name) " creates mirror images. AC improved!")))
    "Cure Light Wounds"
      (let [heal (+ 1 (rng/d8))]
        (party/heal! target heal)
        (log-fn (string (caster :name) " heals " (target :name) " for " heal " HP.")))
    "Hold Person"
      (do
        (put target :alive false)
        (log-fn (string (caster :name) " casts Hold Person! " (target :name) " is paralysed!")))
    "Bless"
      (do
        (put caster :thac0 (- (caster :thac0) 1))   # improve THAC0 for the party leader
        (log-fn (string (caster :name) " calls Mishakal's blessing. THAC0 improved!")))
    # default
    (log-fn (string (caster :name) " fumbles the spell."))))

# ── Monster AI ────────────────────────────────────────────────

(defn- monster-turn! [state combatant heroes]
  (let [target (find party/alive? heroes)]
    (if target
      (let [[hit dmg] (resolve-attack (combatant :ref) target)]
        (if hit
          (do
            (party/take-damage! target dmg)
            (log! state (string (combatant :name) " hits " (target :name)
                                " for " dmg " damage!")))
          (log! state (string (combatant :name) " misses " (target :name) "."))))
      (log! state (string (combatant :name) " has no target.")))))

# ── Phase checks ──────────────────────────────────────────────

(defn- check-victory! [state heroes monsters]
  (when (all |(not ($ :alive)) monsters)
    (put state :phase :victory)
    (log! state "Victory! The enemy is defeated.")))

(defn- check-defeat! [state heroes]
  (when (all party/dead? heroes)
    (put state :phase :defeat)
    (log! state "The party has fallen... Game over.")))

# ── Public API ────────────────────────────────────────────────

(defn active-combatant [state]
  (let [cs (state :combatants)]
    (when (pos? (length cs))
      (cs (% (state :turn-idx) (length cs))))))

(defn hero-turn? [state]
  (let [c (active-combatant state)]
    (and c (= :hero (c :kind)) (party/alive? (c :ref)))))

(defn living-monsters [state]
  (filter |($ :alive) (state :monsters)))

(defn living-heroes [state combatants]
  (filter |(and (= :hero ($ :kind)) (party/alive? ($ :ref))) combatants))

(defn advance-turn! [state]
  "Move to the next combatant, skipping dead ones.
   Returns the new phase keyword."
  (let [cs    (state :combatants)
        total (length cs)]
    (when (pos? total)
      (var steps 0)
      (put state :turn-idx (% (+ (state :turn-idx) 1) total))
      # Skip dead combatants (guard against infinite loop)
      (while (and (< steps total)
                  (let [c (cs (state :turn-idx))]
                    (or (and (= :hero    (c :kind)) (party/dead? (c :ref)))
                        (and (= :monster (c :kind)) (not ((c :ref) :alive))))))
        (put state :turn-idx (% (+ (state :turn-idx) 1) total))
        (++ steps))
      # Auto-run monster turns immediately
      (let [c (cs (state :turn-idx))]
        (when (and (= :monster (c :kind)) ((c :ref) :alive)
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
            [hit dmg] (resolve-attack hero target)]
        (if hit
          (do
            (put target :hp (max 0 (- (target :hp) dmg)))
            (when (<= (target :hp) 0)
              (put target :alive false))
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
  (resolve-spell caster spell-name target (fn [msg] (log! state msg)))
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
  (reduce (fn [acc m] (+ acc (if (not (m :alive)) (m :xp) 0)))
          0
          (state :monsters)))
