#include <janet.h>
#include <raylib.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* ═══════════════════════════════════════════════════════════════
 * Global render state
 * ═══════════════════════════════════════════════════════════════ */

static Color g_draw_color  = {0, 0, 0, 255};
static int   g_initialized = 0;

/* ═══════════════════════════════════════════════════════════════
 * Event ring-buffer
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
    if (next == g_evq_head) return;
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

static const int WATCHED_KEYS[] = {
    KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT,
    KEY_ENTER, KEY_ESCAPE, KEY_SPACE, KEY_BACKSPACE,
    KEY_T, KEY_C, KEY_I, KEY_A, KEY_S, KEY_F, KEY_L,
    /* All letters for name input */
    KEY_B, KEY_D, KEY_E, KEY_G, KEY_H, KEY_J, KEY_K,
    KEY_M, KEY_N, KEY_O, KEY_P, KEY_Q, KEY_R, KEY_U,
    KEY_V, KEY_W, KEY_X, KEY_Y, KEY_Z,
    /* Digits and punctuation for name input */
    KEY_ZERO, KEY_ONE, KEY_TWO, KEY_THREE, KEY_FOUR,
    KEY_FIVE, KEY_SIX, KEY_SEVEN, KEY_EIGHT, KEY_NINE,
    KEY_SPACE, KEY_MINUS, KEY_PERIOD, KEY_APOSTROPHE,
    KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F10,
    KEY_DELETE,
    0
};

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
 * ═══════════════════════════════════════════════════════════════ */

typedef struct { Font rl_font; } JRFont;

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
    jrfont_gc,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    NULL   /* gcperthread (Janet 1.41+) */
};

/* ═══════════════════════════════════════════════════════════════
 * C function wrappers
 * ═══════════════════════════════════════════════════════════════ */

static Janet cfun_init(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 0); (void)argv;
    g_initialized = 1;
    return janet_wrap_nil();
}

static Janet cfun_quit(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 0); (void)argv;
    if (g_initialized && IsWindowReady()) { CloseWindow(); g_initialized = 0; }
    return janet_wrap_nil();
}

static Janet cfun_create_window(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 3);
    const char *title = janet_getcstring(argv, 0);
    int32_t w = janet_getinteger(argv, 1);
    int32_t h = janet_getinteger(argv, 2);
    SetTraceLogLevel(LOG_WARNING);
    InitWindow((int)w, (int)h, title);
    SetTargetFPS(60);
    SetExitKey(0);  /* disable ESC closing the window — handled in Janet */
    /* KEY_F10 is used for the save menu — F12 is avoided because
     * raylib intercepts it internally to save screenshot000.png. */
    SetTraceLogLevel(LOG_NONE);
    g_initialized = 1;
    return janet_wrap_integer(1);
}

static Janet cfun_create_renderer(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 1); (void)argv;
    return janet_wrap_integer(1);
}

static Janet cfun_destroy_window(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 1); (void)argv;
    if (IsWindowReady()) CloseWindow();
    g_initialized = 0;
    return janet_wrap_nil();
}

static Janet cfun_destroy_renderer(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 1); (void)argv;
    return janet_wrap_nil();
}

static Janet cfun_set_color(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 5);
    g_draw_color.r = (unsigned char)janet_getinteger(argv, 1);
    g_draw_color.g = (unsigned char)janet_getinteger(argv, 2);
    g_draw_color.b = (unsigned char)janet_getinteger(argv, 3);
    g_draw_color.a = (unsigned char)janet_getinteger(argv, 4);
    return janet_wrap_nil();
}

static Janet cfun_clear(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 1); (void)argv;
    BeginDrawing();
    ClearBackground(g_draw_color);
    return janet_wrap_nil();
}

static Janet cfun_present(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 1); (void)argv;
    EndDrawing();
    populate_events();
    return janet_wrap_nil();
}

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

static Janet cfun_ticks(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 0); (void)argv;
    return janet_wrap_integer((int32_t)(GetTime() * 1000.0));
}

static Janet cfun_delay(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 1);
    WaitTime((double)janet_getinteger(argv, 0) / 1000.0);
    return janet_wrap_nil();
}

static Janet cfun_poll_events(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 0); (void)argv;
    RLEvent ev;
    if (!evq_pop(&ev)) return janet_wrap_nil();
    JanetTable *t = janet_table(4);
    switch (ev.type) {
        case 0:
            janet_table_put(t, janet_ckeywordv("type"), janet_ckeywordv("quit"));
            break;
        case 1:
            janet_table_put(t, janet_ckeywordv("type"), janet_ckeywordv("keydown"));
            janet_table_put(t, janet_ckeywordv("key"),  janet_wrap_integer(ev.scancode));
            break;
        case 2:
            janet_table_put(t, janet_ckeywordv("type"), janet_ckeywordv("keyup"));
            janet_table_put(t, janet_ckeywordv("key"),  janet_wrap_integer(ev.scancode));
            break;
    }
    return janet_wrap_table(t);
}

static Janet cfun_open_font(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 2);
    const char *path = janet_getcstring(argv, 0);
    int         size = janet_getinteger(argv, 1);
    JRFont *jf = janet_abstract(&janet_rl_font_type, sizeof(JRFont));
    jf->rl_font = LoadFontEx(path, size, NULL, 0);
    if (jf->rl_font.texture.id == 0)
        jf->rl_font = GetFontDefault();
    return janet_wrap_abstract(jf);
}

static Janet cfun_close_font(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 1);
    JRFont *jf = janet_getabstract(argv, 0, &janet_rl_font_type);
    UnloadFont(jf->rl_font);
    memset(&jf->rl_font, 0, sizeof(Font));
    return janet_wrap_nil();
}

static Janet cfun_draw_text(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 9);
    JRFont     *jf   = janet_getabstract(argv, 1, &janet_rl_font_type);
    const char *text = janet_getcstring(argv, 2);
    float       x    = (float)janet_getinteger(argv, 3);
    float       y    = (float)janet_getinteger(argv, 4);
    Color c;
    c.r = (unsigned char)janet_getinteger(argv, 5);
    c.g = (unsigned char)janet_getinteger(argv, 6);
    c.b = (unsigned char)janet_getinteger(argv, 7);
    c.a = (unsigned char)janet_getinteger(argv, 8);
    float font_size = (float)(jf->rl_font.baseSize > 0 ? jf->rl_font.baseSize : 16);
    DrawTextEx(jf->rl_font, text, (Vector2){x, y}, font_size, 1.0f, c);
    return janet_wrap_nil();
}

/* ═══════════════════════════════════════════════════════════════
 * Module registration
 * ═══════════════════════════════════════════════════════════════ */

static const JanetReg cfuns[] = {
    {"init",            cfun_init,            "(rl/init)"},
    {"quit",            cfun_quit,            "(rl/quit)"},
    {"create-window",   cfun_create_window,   "(rl/create-window title w h)"},
    {"create-renderer", cfun_create_renderer, "(rl/create-renderer win)"},
    {"destroy-window",  cfun_destroy_window,  "(rl/destroy-window win)"},
    {"destroy-renderer",cfun_destroy_renderer,"(rl/destroy-renderer ren)"},
    {"set-color",       cfun_set_color,       "(rl/set-color ren r g b a)"},
    {"clear",           cfun_clear,           "(rl/clear ren)"},
    {"present",         cfun_present,         "(rl/present ren)"},
    {"fill-rect",       cfun_fill_rect,       "(rl/fill-rect ren x y w h)"},
    {"draw-rect",       cfun_draw_rect,       "(rl/draw-rect ren x y w h)"},
    {"draw-line",       cfun_draw_line,       "(rl/draw-line ren x1 y1 x2 y2)"},
    {"ticks",           cfun_ticks,           "(rl/ticks)"},
    {"delay",           cfun_delay,           "(rl/delay ms)"},
    {"poll-events",     cfun_poll_events,     "(rl/poll-events)"},
    {"open-font",       cfun_open_font,       "(rl/open-font path size)"},
    {"close-font",      cfun_close_font,      "(rl/close-font font)"},
    {"draw-text",       cfun_draw_text,       "(rl/draw-text ren font text x y r g b a)"},
    {NULL, NULL, NULL}
};

/* ── Module entry points ─────────────────────────────────────────────────── */
static void janet_raylib_register(JanetTable *env);

/*
 * JANET_MODULE_ENTRY is the only entry point needed.
 *
 * For dynamic loading (make run):
 *   jpm compiles without -DJANET_ENTRY_NAME, so JANET_MODULE_ENTRY
 *   expands to _janet_init (the standard dlopen symbol).
 *
 * For static embedding (make exe):
 *   jpm passes -DJANET_ENTRY_NAME=janet_module_entry_janet_raylib on
 *   the command line, so JANET_MODULE_ENTRY expands to that mangled
 *   name automatically — no extra alias needed or allowed.
 */
JANET_MODULE_ENTRY(JanetTable *env) { janet_raylib_register(env); }

static void janet_raylib_register(JanetTable *env)
{
    janet_cfuns(env, "rl", cfuns);

    /* Arrow keys */
    janet_def(env, "SC_UP",        janet_wrap_integer(KEY_UP),        "KEY_UP");
    janet_def(env, "SC_DOWN",      janet_wrap_integer(KEY_DOWN),      "KEY_DOWN");
    janet_def(env, "SC_LEFT",      janet_wrap_integer(KEY_LEFT),      "KEY_LEFT");
    janet_def(env, "SC_RIGHT",     janet_wrap_integer(KEY_RIGHT),     "KEY_RIGHT");

    /* Action keys */
    janet_def(env, "SC_RETURN",    janet_wrap_integer(KEY_ENTER),     "KEY_ENTER");
    janet_def(env, "SC_ESCAPE",    janet_wrap_integer(KEY_ESCAPE),    "KEY_ESCAPE");
    janet_def(env, "SC_SPACE",     janet_wrap_integer(KEY_SPACE),     "KEY_SPACE");
    janet_def(env, "SC_BACKSPACE", janet_wrap_integer(KEY_BACKSPACE), "KEY_BACKSPACE");
    janet_def(env, "SC_DELETE",    janet_wrap_integer(KEY_DELETE),    "Delete save slot");

    /* Letter keys */
    janet_def(env, "SC_T",  janet_wrap_integer(KEY_T),  "Talk");
    janet_def(env, "SC_C",  janet_wrap_integer(KEY_C),  "Rest/Camp");
    janet_def(env, "SC_I",  janet_wrap_integer(KEY_I),  "Inventory");
    janet_def(env, "SC_A",  janet_wrap_integer(KEY_A),  "Attack");
    janet_def(env, "SC_S",  janet_wrap_integer(KEY_S),  "Spell");
    janet_def(env, "SC_F",  janet_wrap_integer(KEY_F),  "Flee");
    janet_def(env, "SC_L",  janet_wrap_integer(KEY_L),  "Load game");

    /* Function keys */
    janet_def(env, "SC_F1", janet_wrap_integer(KEY_F1), "Party member 1");
    janet_def(env, "SC_F2", janet_wrap_integer(KEY_F2), "Party member 2");
    janet_def(env, "SC_F3", janet_wrap_integer(KEY_F3), "Party member 3");
    janet_def(env, "SC_F4",  janet_wrap_integer(KEY_F4),  "Party member 4");
    janet_def(env, "SC_F10", janet_wrap_integer(KEY_F10), "Save/Load menu");
}
