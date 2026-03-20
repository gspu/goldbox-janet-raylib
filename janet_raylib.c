#include <janet.h>
#include <raylib.h>
#include <string.h>

/* ═══════════════════════════════════════════════════════════════
 * Global render state
 * ═══════════════════════════════════════════════════════════════ */

static Color g_draw_color = {0, 0, 0, 255};

/* ═══════════════════════════════════════════════════════════════
 * Event ring-buffer
 *
 * Raylib exposes input as per-frame predicates (IsKeyPressed etc.).
 * We bridge them to a poll-based queue: EndDrawing → populate_events()
 * fills this ring-buffer; Janet drains it one entry at a time via
 * (rl/poll-events).
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
    KEY_ENTER, KEY_ESCAPE, KEY_SPACE, KEY_BACKSPACE, KEY_DELETE,
    KEY_T, KEY_C, KEY_I, KEY_A, KEY_S, KEY_F, KEY_L,
    /* All letters for save-game name input */
    KEY_B, KEY_D, KEY_E, KEY_G, KEY_H, KEY_J, KEY_K,
    KEY_M, KEY_N, KEY_O, KEY_P, KEY_Q, KEY_R, KEY_U,
    KEY_V, KEY_W, KEY_X, KEY_Y, KEY_Z,
    /* Digits and punctuation */
    KEY_ZERO, KEY_ONE, KEY_TWO, KEY_THREE, KEY_FOUR,
    KEY_FIVE, KEY_SIX, KEY_SEVEN, KEY_EIGHT, KEY_NINE,
    KEY_MINUS, KEY_PERIOD, KEY_APOSTROPHE,
    /* Function keys */
    KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F10,
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

/* (rl/open-window title w h) → nil */
static Janet cfun_open_window(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 3);
    const char *title = janet_getcstring(argv, 0);
    int32_t w = janet_getinteger(argv, 1);
    int32_t h = janet_getinteger(argv, 2);
    SetTraceLogLevel(LOG_NONE);
    InitWindow((int)w, (int)h, title);
    SetTargetFPS(60);
    SetExitKey(0);  /* ESC handled in Janet */
    return janet_wrap_nil();
}

/* (rl/close-window) → nil */
static Janet cfun_close_window(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 0); (void)argv;
    if (IsWindowReady()) CloseWindow();
    return janet_wrap_nil();
}

/* (rl/set-color r g b a) → nil */
static Janet cfun_set_color(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 4);
    g_draw_color.r = (unsigned char)janet_getinteger(argv, 0);
    g_draw_color.g = (unsigned char)janet_getinteger(argv, 1);
    g_draw_color.b = (unsigned char)janet_getinteger(argv, 2);
    g_draw_color.a = (unsigned char)janet_getinteger(argv, 3);
    return janet_wrap_nil();
}

/* (rl/clear) → nil — begin frame and clear to current colour */
static Janet cfun_clear(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 0); (void)argv;
    BeginDrawing();
    ClearBackground(g_draw_color);
    return janet_wrap_nil();
}

/* (rl/present) → nil — flush frame, sample input into ring-buffer */
static Janet cfun_present(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 0); (void)argv;
    EndDrawing();
    populate_events();
    return janet_wrap_nil();
}

/* (rl/fill-rect x y w h) → nil */
static Janet cfun_fill_rect(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 4);
    DrawRectangle(janet_getinteger(argv, 0), janet_getinteger(argv, 1),
                  janet_getinteger(argv, 2), janet_getinteger(argv, 3),
                  g_draw_color);
    return janet_wrap_nil();
}

/* (rl/draw-rect x y w h) → nil — outline only */
static Janet cfun_draw_rect(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 4);
    DrawRectangleLines(janet_getinteger(argv, 0), janet_getinteger(argv, 1),
                       janet_getinteger(argv, 2), janet_getinteger(argv, 3),
                       g_draw_color);
    return janet_wrap_nil();
}

/* (rl/draw-line x1 y1 x2 y2) → nil */
static Janet cfun_draw_line(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 4);
    DrawLine(janet_getinteger(argv, 0), janet_getinteger(argv, 1),
             janet_getinteger(argv, 2), janet_getinteger(argv, 3),
             g_draw_color);
    return janet_wrap_nil();
}

/* (rl/poll-events) → {:type :quit/:keydown/:keyup  :key scancode} | nil */
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

/* (rl/open-font path size) → font-handle */
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

/* (rl/close-font font) → nil */
static Janet cfun_close_font(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 1);
    JRFont *jf = janet_getabstract(argv, 0, &janet_rl_font_type);
    UnloadFont(jf->rl_font);
    memset(&jf->rl_font, 0, sizeof(Font));
    return janet_wrap_nil();
}

/* (rl/draw-text font text x y r g b a) → nil */
static Janet cfun_draw_text(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 8);
    JRFont     *jf   = janet_getabstract(argv, 0, &janet_rl_font_type);
    const char *text = janet_getcstring(argv, 1);
    float       x    = (float)janet_getinteger(argv, 2);
    float       y    = (float)janet_getinteger(argv, 3);
    Color c;
    c.r = (unsigned char)janet_getinteger(argv, 4);
    c.g = (unsigned char)janet_getinteger(argv, 5);
    c.b = (unsigned char)janet_getinteger(argv, 6);
    c.a = (unsigned char)janet_getinteger(argv, 7);
    float font_size = (float)(jf->rl_font.baseSize > 0 ? jf->rl_font.baseSize : 16);
    DrawTextEx(jf->rl_font, text, (Vector2){x, y}, font_size, 1.0f, c);
    return janet_wrap_nil();
}

/* ═══════════════════════════════════════════════════════════════
 * Module registration
 * ═══════════════════════════════════════════════════════════════ */

static const JanetReg cfuns[] = {
    {"open-window",  cfun_open_window,  "(rl/open-window title w h)"},
    {"close-window", cfun_close_window, "(rl/close-window)"},
    {"set-color",    cfun_set_color,    "(rl/set-color r g b a)"},
    {"clear",        cfun_clear,        "(rl/clear)"},
    {"present",      cfun_present,      "(rl/present)"},
    {"fill-rect",    cfun_fill_rect,    "(rl/fill-rect x y w h)"},
    {"draw-rect",    cfun_draw_rect,    "(rl/draw-rect x y w h)"},
    {"draw-line",    cfun_draw_line,    "(rl/draw-line x1 y1 x2 y2)"},
    {"poll-events",  cfun_poll_events,  "(rl/poll-events)"},
    {"open-font",    cfun_open_font,    "(rl/open-font path size)"},
    {"close-font",   cfun_close_font,   "(rl/close-font font)"},
    {"draw-text",    cfun_draw_text,    "(rl/draw-text font text x y r g b a)"},
    {NULL, NULL, NULL}
};

/* ── Module entry point ─────────────────────────────────────────────────── */
static void janet_raylib_register(JanetTable *env);

JANET_MODULE_ENTRY(JanetTable *env) { janet_raylib_register(env); }

static void janet_raylib_register(JanetTable *env)
{
    janet_cfuns(env, "rl", cfuns);

    janet_def(env, "SC_UP",        janet_wrap_integer(KEY_UP),        "up arrow");
    janet_def(env, "SC_DOWN",      janet_wrap_integer(KEY_DOWN),      "down arrow");
    janet_def(env, "SC_LEFT",      janet_wrap_integer(KEY_LEFT),      "left arrow");
    janet_def(env, "SC_RIGHT",     janet_wrap_integer(KEY_RIGHT),     "right arrow");
    janet_def(env, "SC_RETURN",    janet_wrap_integer(KEY_ENTER),     "enter");
    janet_def(env, "SC_ESCAPE",    janet_wrap_integer(KEY_ESCAPE),    "escape");
    janet_def(env, "SC_SPACE",     janet_wrap_integer(KEY_SPACE),     "space");
    janet_def(env, "SC_BACKSPACE", janet_wrap_integer(KEY_BACKSPACE), "backspace");
    janet_def(env, "SC_DELETE",    janet_wrap_integer(KEY_DELETE),    "delete");
    janet_def(env, "SC_T",         janet_wrap_integer(KEY_T),         "talk");
    janet_def(env, "SC_C",         janet_wrap_integer(KEY_C),         "rest");
    janet_def(env, "SC_I",         janet_wrap_integer(KEY_I),         "inventory");
    janet_def(env, "SC_A",         janet_wrap_integer(KEY_A),         "attack");
    janet_def(env, "SC_S",         janet_wrap_integer(KEY_S),         "spell/save");
    janet_def(env, "SC_F",         janet_wrap_integer(KEY_F),         "flee");
    janet_def(env, "SC_L",         janet_wrap_integer(KEY_L),         "load");
    janet_def(env, "SC_F1",        janet_wrap_integer(KEY_F1),        "party member 1");
    janet_def(env, "SC_F2",        janet_wrap_integer(KEY_F2),        "party member 2");
    janet_def(env, "SC_F3",        janet_wrap_integer(KEY_F3),        "party member 3");
    janet_def(env, "SC_F4",        janet_wrap_integer(KEY_F4),        "party member 4");
    janet_def(env, "SC_F10",       janet_wrap_integer(KEY_F10),       "save/load menu");
}
