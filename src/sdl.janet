# goldbox/src/sdl.janet
# Thin re-export of the janet_sdl2 native module.
# The actual C bindings live in ../janet_sdl2.c → compiled to janet_sdl2.so
#
# Build the native module first:
#   make native          (from the goldbox/ root)
#
# Then run:
#   janet src/main.janet

# Load the compiled .so from the project root.
# (import "../janet_sdl2") resolves relative to this file (src/),
# so "../janet_sdl2" points to goldbox/janet_sdl2.so
(import ../janet_sdl2 :as _sdl)

# Re-export everything under the sdl/ namespace so callers keep
# the same API they already use (sdl/init, sdl/fill-rect, etc.)

(def init            _sdl/init)
(def quit            _sdl/quit)
(def create-window   _sdl/create-window)
(def destroy-window  _sdl/destroy-window)
(def create-renderer _sdl/create-renderer)
(def destroy-renderer _sdl/destroy-renderer)
(def set-color       _sdl/set-color)
(def clear           _sdl/clear)
(def present         _sdl/present)
(def fill-rect       _sdl/fill-rect)
(def draw-rect       _sdl/draw-rect)
(def draw-line       _sdl/draw-line)
(def ticks           _sdl/ticks)
(def delay           _sdl/delay)
(def poll-events     _sdl/poll-events)
(def open-font       _sdl/open-font)
(def close-font      _sdl/close-font)
(def draw-text       _sdl/draw-text)

# Scancode constants (defined in the C module via DEF_SC macro)
(def SC_UP      _sdl/SC_UP)
(def SC_DOWN    _sdl/SC_DOWN)
(def SC_LEFT    _sdl/SC_LEFT)
(def SC_RIGHT   _sdl/SC_RIGHT)
(def SC_RETURN  _sdl/SC_RETURN)
(def SC_ESCAPE  _sdl/SC_ESCAPE)
(def SC_SPACE   _sdl/SC_SPACE)
(def SC_A       _sdl/SC_A)
(def SC_C       _sdl/SC_C)
(def SC_F       _sdl/SC_F)
(def SC_I       _sdl/SC_I)
(def SC_M       _sdl/SC_M)
(def SC_S       _sdl/SC_S)
(def SC_T       _sdl/SC_T)
(def SC_F1      _sdl/SC_F1)
(def SC_F2      _sdl/SC_F2)
(def SC_F3      _sdl/SC_F3)
(def SC_F4      _sdl/SC_F4)
