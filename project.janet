# project.janet — jpm build config for goldbox-janet

(declare-project
  :name        "goldbox"
  :description "Gold Box RPG Engine — Dragonlance, raylib backend"
  :license     "BSD-3-Clause")

(def prefix
  (case (os/which)
    :freebsd "/usr/local"
    "/usr"))

# Compile janet_raylib.c into both a shared .so AND a static .o
# that jpm can link directly into the executable.
(declare-native
  :name    "janet_raylib"
  :source  ["janet_raylib.c"]
  :cflags  [(string "-I" prefix "/include")]
  :lflags  [(string "-L" prefix "/lib")
            "-lraylib" "-lm" "-lpthread" "-ldl"])

# Standalone executable — embed the native module statically so
# the binary only needs janet_raylib.so alongside it at runtime.
(declare-executable
  :name    "goldbox"
  :entry   "src/main.janet"
  :natives ["janet_raylib"]
  :install false)
