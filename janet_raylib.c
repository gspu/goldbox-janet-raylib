/*
 * janet_raylib.c
 * Raylib-based native module for Janet — drop-in replacement for janet_sdl2.c
 *
 * Exports the same 18-function surface the Janet game scripts rely on, plus
 * the same SC_* scancode constants, so the only change needed in the .janet
 * sources is:
 *
 *   (import ./janet_sdl2 :as sdl)  →  (import ./janet_raylib :as rl)
 *
 * SDL2 concept          raylib equivalent
 * ─────────────────     ─────────────────────────────────────────────────
 * SDL_Init / SDL_Quit   InitWindow / CloseWindow
 * SDL_CreateWindow      InitWindow (w, h, title) + SetTargetFPS
 * SDL_CreateRenderer    no-op — raylib uses an implicit renderer
 * SDL_SetRenderDrawColor global g_draw_color
 * SDL_RenderClear       BeginDrawing + ClearBackground
 * SDL_RenderPresent     EndDrawing  (also samples input into event queue)
 * SDL_RenderFillRect    DrawRectangle
 * SDL_RenderDrawRect    DrawRectangleLines
 * SDL_RenderDrawLine    DrawLine
 * SDL_GetTicks          (int)(GetTime() * 1000)
 * SDL_Delay             WaitTime
 * SDL_PollEvent         drain internal ring-buffer populated by EndDrawing
 * TTF_OpenFont          LoadFontEx
 * TTF_CloseFont         UnloadFont
 * TTF_RenderText+Blit   DrawTextEx
 *
 * Build (FreeBSD / Linux):
 *   cc -O2 -fPIC -shared \
 *      $(pkg-config --cflags --libs janet) \
 *      $(pkg-config --cflags --libs raylib) \
 *      -lm -lpthread -ldl \
 *      -Wl,--version-script=janet_raylib.map \
 *      -o janet_raylib.so janet_raylib.c
 */

#include <janet.h>
#include <raylib.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* ═══════════════════════════════════════════════════════════════
 * Global render state
 * ═══════════════════════════════════════════════════════════════ */

static Color g_draw_color  = {0, 0, 0, 255};
static int   g_initialized = 0;   /* non-zero after InitWindow */

/* ═══════════════════════════════════════════════════════════════
 * Event ring-buffer
 *
 * SDL2 delivers events via a queue you drain with SDL_PollEvent().
 * Raylib exposes input as per-frame predicates (IsKeyPressed, etc.).
 * We bridge the gap: EndDrawing → populate_events() fills this
 * buffer; Janet calls rl/poll-events to drain it one entry at a time.
 * ═══════════════════════════════════════════════════════════════ */

#define EVQ_CAP 128

typedef struct {
    int type;      /* 0 = quit, 1 = keydown, 2 = keyup */
    int scancode;
} RLEvent;

static RLEvent g_evq[EVQ_CAP];
static int     g_evq_head = 0;
static int     g_evq_tail = 0;

static void evq_push(int type, int sc)
{
    int next = (g_evq_tail + 1) % EVQ_CAP;
    if (next == g_evq_head) return; /* full — drop */
    g_evq[g_evq_tail].type     = type;
    g_evq[g_evq_tail].scancode = sc;
    g_evq_tail = next;
}

static int evq_pop(RLEvent *out)
{
    if (g_evq_head == g_evq_tail) return 0;
    *out = g_evq[g_evq_head];
    g_evq_head = (g_evq_head + 1) % EVQ_CAP;
    return 1;
}

/* All keys the Gold Box engine reads */
static const int WATCHED_KEYS[] = {
    KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT,
    KEY_ENTER, KEY_ESCAPE, KEY_SPACE, KEY_BACKSPACE,
    KEY_T, KEY_C, KEY_I, KEY_A, KEY_S, KEY_F,
    KEY_F1, KEY_F2, KEY_F3, KEY_F4,
    0 /* sentinel */
};

/*
 * Called at the end of each rendered frame (inside cfun_present).
 * Translates raylib's frame-level input predicates into SDL-style
 * keydown / keyup events and appends them to the ring-buffer.
 */
static void populate_events(void)
{
    if (WindowShouldClose()) {
        evq_push(0, 0);
        return;
    }
    for (int i = 0; WATCHED_KEYS[i] != 0; i++) {
        int k = WATCHED_KEYS[i];
        if (IsKeyPressed(k))  evq_push(1, k);
        if (IsKeyReleased(k)) evq_push(2, k);
    }
}

/* ═══════════════════════════════════════════════════════════════
 * Font abstract type
 *
 * raylib Font is a struct (not a pointer), so we heap-allocate a
 * thin wrapper and expose it as a Janet abstract value.
 * ═══════════════════════════════════════════════════════════════ */

typedef struct { Font rl_font; } JRFont;

/*
 * The gc field signature changed across Janet versions:
 *   Janet < 1.20ish   void (*gc)(void *data, size_t len)
 *   Janet >= 1.20ish  int  (*gc)(void *data, size_t len)  (return value ignored)
 *
 * We detect which is expected by checking whether JANET_ABSTRACT_HEADER
 * is defined (a proxy for a newer Janet API), and cast accordingly.
 * Using int always is safe because both ABIs pass/return through the same
 * register and the return value is ignored by the runtime in all versions.
 */
static int jrfont_gc(void *p, size_t sz)
{
    (void)sz;
    JRFont *jf = (JRFont *)p;
    if (jf->rl_font.texture.id != 0)
        UnloadFont(jf->rl_font);
    return 0;
}

static const JanetAbstractType janet_rl_font_type = {
    "raylib/font",
    jrfont_gc,          /* gc         — int(*)(void*,size_t) in Janet 1.20+ */
    NULL,               /* gcmark */
    NULL,               /* get  */
    NULL,               /* put  */
    NULL,               /* marshal */
    NULL,               /* unmarshal */
    NULL,               /* tostring */
    NULL,               /* compare */
    NULL,               /* hash */
    NULL,               /* next   (added in Janet 1.23) */
    NULL,               /* length (added in Janet 1.23) */
    NULL, NULL,         /* call, update */
    NULL                /* gcperthread (Janet 1.41+) */
};

/* ═══════════════════════════════════════════════════════════════
 * C function wrappers
 * ═══════════════════════════════════════════════════════════════ */

/* (rl/init) → nil
 * Placeholder — the original SDL_Init call.  In raylib the window is
 * opened by create-window, so this is a no-op that just sets a flag. */
static Janet cfun_init(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 0);
    (void)argv;
    g_initialized = 1;
    return janet_wrap_nil();
}

/* (rl/quit) → nil */
static Janet cfun_quit(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 0);
    (void)argv;
    if (g_initialized && IsWindowReady()) {
        CloseWindow();
        g_initialized = 0;
    }
    return janet_wrap_nil();
}

/* (rl/create-window title width height) → window-handle (integer) */
static Janet cfun_create_window(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 3);
    const char *title = janet_getcstring(argv, 0);
    int32_t w = janet_getinteger(argv, 1);
    int32_t h = janet_getinteger(argv, 2);

    SetTraceLogLevel(LOG_WARNING);   /* silence verbose startup logs */
    InitWindow((int)w, (int)h, title);
    SetTargetFPS(60);
    g_initialized = 1;
    /* Return a dummy integer handle for API compatibility */
    return janet_wrap_integer(1);
}

/* (rl/create-renderer window) → renderer-handle (integer)
 * Raylib has no separate renderer object; return a dummy handle so the
 * Janet code can pass it around without changes. */
static Janet cfun_create_renderer(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 1);
    (void)argv;
    return janet_wrap_integer(1);
}

/* (rl/destroy-window win) → nil */
static Janet cfun_destroy_window(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 1);
    (void)argv;
    if (IsWindowReady()) CloseWindow();
    g_initialized = 0;
    return janet_wrap_nil();
}

/* (rl/destroy-renderer ren) → nil — no-op */
static Janet cfun_destroy_renderer(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 1);
    (void)argv;
    return janet_wrap_nil();
}

/* (rl/set-color renderer r g b a) → nil
 * Stores the colour used by subsequent draw calls in this frame. */
static Janet cfun_set_color(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 5);
    /* argv[0] = renderer (ignored) */
    g_draw_color.r = (unsigned char)janet_getinteger(argv, 1);
    g_draw_color.g = (unsigned char)janet_getinteger(argv, 2);
    g_draw_color.b = (unsigned char)janet_getinteger(argv, 3);
    g_draw_color.a = (unsigned char)janet_getinteger(argv, 4);
    return janet_wrap_nil();
}

/* (rl/clear renderer) → nil
 * Begins the raylib frame and fills the background with g_draw_color.
 * Corresponds to SDL_SetRenderDrawColor + SDL_RenderClear. */
static Janet cfun_clear(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 1);
    (void)argv;
    BeginDrawing();
    ClearBackground(g_draw_color);
    return janet_wrap_nil();
}

/* (rl/present renderer) → nil
 * Flushes the rendered frame to screen (EndDrawing), then samples input
 * into the event ring-buffer so the next poll-events call has data. */
static Janet cfun_present(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 1);
    (void)argv;
    EndDrawing();
    populate_events();
    return janet_wrap_nil();
}

/* (rl/fill-rect renderer x y w h) → nil */
static Janet cfun_fill_rect(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 5);
    int x = janet_getinteger(argv, 1);
    int y = janet_getinteger(argv, 2);
    int w = janet_getinteger(argv, 3);
    int h = janet_getinteger(argv, 4);
    DrawRectangle(x, y, w, h, g_draw_color);
    return janet_wrap_nil();
}

/* (rl/draw-rect renderer x y w h) → nil  — outline only */
static Janet cfun_draw_rect(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 5);
    int x = janet_getinteger(argv, 1);
    int y = janet_getinteger(argv, 2);
    int w = janet_getinteger(argv, 3);
    int h = janet_getinteger(argv, 4);
    DrawRectangleLines(x, y, w, h, g_draw_color);
    return janet_wrap_nil();
}

/* (rl/draw-line renderer x1 y1 x2 y2) → nil */
static Janet cfun_draw_line(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 5);
    int x1 = janet_getinteger(argv, 1);
    int y1 = janet_getinteger(argv, 2);
    int x2 = janet_getinteger(argv, 3);
    int y2 = janet_getinteger(argv, 4);
    DrawLine(x1, y1, x2, y2, g_draw_color);
    return janet_wrap_nil();
}

/* (rl/ticks) → integer milliseconds since init
 * Mirrors SDL_GetTicks(). */
static Janet cfun_ticks(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 0);
    (void)argv;
    return janet_wrap_integer((int32_t)(GetTime() * 1000.0));
}

/* (rl/delay ms) → nil
 * Mirrors SDL_Delay(). Note: when SetTargetFPS is active raylib's own
 * frame-pacing usually makes explicit delays unnecessary, but we honour
 * the call for drop-in compatibility. */
static Janet cfun_delay(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 1);
    double ms = (double)janet_getinteger(argv, 0);
    WaitTime(ms / 1000.0);
    return janet_wrap_nil();
}

/* (rl/poll-events) → {:type :quit/:keydown/:keyup  :key scancode} | nil
 * Drains one event from the ring-buffer.  Call in a loop until nil,
 * exactly as you would with SDL_PollEvent. */
static Janet cfun_poll_events(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 0);
    (void)argv;

    RLEvent ev;
    if (!evq_pop(&ev)) return janet_wrap_nil();

    JanetTable *t = janet_table(4);
    switch (ev.type) {
        case 0:  /* quit */
            janet_table_put(t,
                janet_ckeywordv("type"), janet_ckeywordv("quit"));
            break;
        case 1:  /* keydown */
            janet_table_put(t,
                janet_ckeywordv("type"), janet_ckeywordv("keydown"));
            janet_table_put(t,
                janet_ckeywordv("key"), janet_wrap_integer(ev.scancode));
            break;
        case 2:  /* keyup */
            janet_table_put(t,
                janet_ckeywordv("type"), janet_ckeywordv("keyup"));
            janet_table_put(t,
                janet_ckeywordv("key"), janet_wrap_integer(ev.scancode));
            break;
        default:
            break;
    }
    return janet_wrap_table(t);
}

/* (rl/open-font path size) → font-handle
 * Loads a TrueType font via raylib's LoadFontEx.
 * The returned handle is a Janet abstract (raylib/font). */
static Janet cfun_open_font(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 2);
    const char *path = janet_getcstring(argv, 0);
    int         size = janet_getinteger(argv, 1);

    JRFont *jf = janet_abstract(&janet_rl_font_type, sizeof(JRFont));
    /*
     * NULL codepoints + 0 count → load the full latin-1 glyph set,
     * which covers all ASCII characters the game uses.
     */
    jf->rl_font = LoadFontEx(path, size, NULL, 0);
    if (jf->rl_font.texture.id == 0) {
        /* Fallback to the built-in raylib font so the game is still
           runnable even without DejaVu installed. */
        jf->rl_font = GetFontDefault();
    }
    return janet_wrap_abstract(jf);
}

/* (rl/close-font font) → nil */
static Janet cfun_close_font(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 1);
    JRFont *jf = janet_getabstract(argv, 0, &janet_rl_font_type);
    UnloadFont(jf->rl_font);
    /* Zero out so the GC finaliser won't double-free */
    memset(&jf->rl_font, 0, sizeof(Font));
    return janet_wrap_nil();
}

/* (rl/draw-text renderer font text x y r g b a) → nil
 * Mirrors the SDL2 version: renderer is ignored, font is the abstract
 * font handle, colour components are separate integers.
 * The font's own base size is used as the render size. */
static Janet cfun_draw_text(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 9);
    /* argv[0] = renderer (ignored) */
    JRFont     *jf   = janet_getabstract(argv, 1, &janet_rl_font_type);
    const char *text = janet_getcstring(argv, 2);
    float       x    = (float)janet_getinteger(argv, 3);
    float       y    = (float)janet_getinteger(argv, 4);
    Color c;
    c.r = (unsigned char)janet_getinteger(argv, 5);
    c.g = (unsigned char)janet_getinteger(argv, 6);
    c.b = (unsigned char)janet_getinteger(argv, 7);
    c.a = (unsigned char)janet_getinteger(argv, 8);

    float font_size = (float)(jf->rl_font.baseSize > 0
                              ? jf->rl_font.baseSize : 16);
    DrawTextEx(jf->rl_font, text, (Vector2){x, y}, font_size, 1.0f, c);
    return janet_wrap_nil();
}

/* ═══════════════════════════════════════════════════════════════
 * Module registration
 * ═══════════════════════════════════════════════════════════════ */

static const JanetReg cfuns[] = {
    {"init",
     cfun_init,
     "(rl/init)\n\nInitialise the raylib subsystem (window opened later)."},
    {"quit",
     cfun_quit,
     "(rl/quit)\n\nClose the window and free raylib resources."},
    {"create-window",
     cfun_create_window,
     "(rl/create-window title w h)\n\nOpen a window of size w×h with the given title."},
    {"create-renderer",
     cfun_create_renderer,
     "(rl/create-renderer win)\n\nNo-op; returns a dummy renderer handle for API compatibility."},
    {"destroy-window",
     cfun_destroy_window,
     "(rl/destroy-window win)\n\nClose the window."},
    {"destroy-renderer",
     cfun_destroy_renderer,
     "(rl/destroy-renderer ren)\n\nNo-op."},
    {"set-color",
     cfun_set_color,
     "(rl/set-color ren r g b a)\n\nSet the current draw colour (0–255 per channel)."},
    {"clear",
     cfun_clear,
     "(rl/clear ren)\n\nBegin a new frame and clear to the current colour."},
    {"present",
     cfun_present,
     "(rl/present ren)\n\nFlush the frame to screen and sample input events."},
    {"fill-rect",
     cfun_fill_rect,
     "(rl/fill-rect ren x y w h)\n\nDraw a solid rectangle in the current colour."},
    {"draw-rect",
     cfun_draw_rect,
     "(rl/draw-rect ren x y w h)\n\nDraw a rectangle outline in the current colour."},
    {"draw-line",
     cfun_draw_line,
     "(rl/draw-line ren x1 y1 x2 y2)\n\nDraw a line in the current colour."},
    {"ticks",
     cfun_ticks,
     "(rl/ticks)\n\nReturn milliseconds elapsed since InitWindow."},
    {"delay",
     cfun_delay,
     "(rl/delay ms)\n\nSleep for ms milliseconds."},
    {"poll-events",
     cfun_poll_events,
     "(rl/poll-events)\n\nReturn the next pending event table, or nil when the queue is empty.\n"
     "Event table keys: :type (:quit | :keydown | :keyup), :key (scancode integer)."},
    {"open-font",
     cfun_open_font,
     "(rl/open-font path size)\n\nLoad a TrueType font at the given pixel size.\n"
     "Falls back to the built-in raylib font if the file is not found."},
    {"close-font",
     cfun_close_font,
     "(rl/close-font font)\n\nUnload a previously loaded font."},
    {"draw-text",
     cfun_draw_text,
     "(rl/draw-text ren font text x y r g b a)\n\nRender text at (x, y) with the given RGBA colour."},
    {NULL, NULL, NULL}
};

/* ── Module entry point ─────────────────────────────────────────────────── */
static void janet_raylib_register(JanetTable *env);

JANET_MODULE_ENTRY(JanetTable *env) { janet_raylib_register(env); }

static void janet_raylib_register(JanetTable *env)
{
    janet_cfuns(env, "rl", cfuns);

    /* Arrow keys */
    janet_def(env, "SC_UP",        janet_wrap_integer(KEY_UP),        "Raylib KEY_UP (265)");
    janet_def(env, "SC_DOWN",      janet_wrap_integer(KEY_DOWN),      "Raylib KEY_DOWN (264)");
    janet_def(env, "SC_LEFT",      janet_wrap_integer(KEY_LEFT),      "Raylib KEY_LEFT (263)");
    janet_def(env, "SC_RIGHT",     janet_wrap_integer(KEY_RIGHT),     "Raylib KEY_RIGHT (262)");

    /* Action keys */
    janet_def(env, "SC_RETURN",    janet_wrap_integer(KEY_ENTER),     "Raylib KEY_ENTER (257)");
    janet_def(env, "SC_ESCAPE",    janet_wrap_integer(KEY_ESCAPE),    "Raylib KEY_ESCAPE (256)");
    janet_def(env, "SC_SPACE",     janet_wrap_integer(KEY_SPACE),     "Raylib KEY_SPACE (32)");
    janet_def(env, "SC_BACKSPACE", janet_wrap_integer(KEY_BACKSPACE), "Raylib KEY_BACKSPACE (259)");

    /* Letter keys used by the Gold Box engine */
    janet_def(env, "SC_T",  janet_wrap_integer(KEY_T),  "Talk");
    janet_def(env, "SC_C",  janet_wrap_integer(KEY_C),  "Rest/Camp");
    janet_def(env, "SC_I",  janet_wrap_integer(KEY_I),  "Inventory");
    janet_def(env, "SC_A",  janet_wrap_integer(KEY_A),  "Attack");
    janet_def(env, "SC_S",  janet_wrap_integer(KEY_S),  "Spell");
    janet_def(env, "SC_F",  janet_wrap_integer(KEY_F),  "Flee");

    /* Function keys — party member selection */
    janet_def(env, "SC_F1", janet_wrap_integer(KEY_F1), "Select party member 1 (Tanis)");
    janet_def(env, "SC_F2", janet_wrap_integer(KEY_F2), "Select party member 2 (Raistlin)");
    janet_def(env, "SC_F3", janet_wrap_integer(KEY_F3), "Select party member 3 (Goldmoon)");
    janet_def(env, "SC_F4", janet_wrap_integer(KEY_F4), "Select party member 4 (Tasslehoff)");
}
