# rng.janet — shared random-number utilities
# Uses Janet's built-in math/rng (xorshift, no overflow issues).

(var *rng* (math/rng (os/time)))

(defn rand-int
  "Return a random integer in [0, n)."
  [n]
  (math/rng-int *rng* n))

(defn d4  [] (+ 1 (rand-int 4)))
(defn d6  [] (+ 1 (rand-int 6)))
(defn d8  [] (+ 1 (rand-int 8)))
(defn d20 [] (+ 1 (rand-int 20)))

(defn rand-bool
  "Return true with probability 0.5."
  []
  (= 0 (rand-int 2)))

(defn roll-3d6
  "Roll 3d6 — standard D&D ability score."
  []
  (+ (d6) (d6) (d6)))
