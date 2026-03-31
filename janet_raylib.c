#include <janet.h>
#include <raylib.h>
#include <string.h>
#include <math.h>

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

/* (rl/open-font path size) -> font-handle */
static Janet cfun_open_font(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 2);
    const char *path = janet_getcstring(argv, 0);
    int         size = janet_getinteger(argv, 1);
    JRFont *jf = janet_abstract(&janet_rl_font_type, sizeof(JRFont));

    /* Build codepoint list: printable ASCII (32-126) plus arrow symbols
       used in UI hints.  Anything not in this list renders as '?'.
       Arrow codepoints: left=0x2190 up=0x2191 right=0x2192 down=0x2193 */
    int cp_extra[] = { 0x2190, 0x2191, 0x2192, 0x2193 };
    int ascii_count = 126 - 32 + 1;
    int extra_count = 4;
    int total = ascii_count + extra_count;
    int *codepoints = (int *)RL_MALLOC(total * sizeof(int));
    for (int i = 0; i < ascii_count; i++)
        codepoints[i] = 32 + i;
    for (int i = 0; i < extra_count; i++)
        codepoints[ascii_count + i] = cp_extra[i];

    jf->rl_font = LoadFontEx(path, size, codepoints, total);
    RL_FREE(codepoints);

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


/* ===================================================================
 * Texture type — GPU texture + CPU image (for floor/ceiling sampling)
 * =================================================================== */

typedef struct {
    Texture2D gpu_tex;
    Image     cpu_img;
} JRTexture;

static int rl_texture_gc(void *p, size_t s)
{
    (void)s;
    JRTexture *jt = (JRTexture *)p;
    if (jt->gpu_tex.id   != 0)    { UnloadTexture(jt->gpu_tex); jt->gpu_tex.id = 0; }
    if (jt->cpu_img.data != NULL) { UnloadImage(jt->cpu_img);  jt->cpu_img.data = NULL; }
    return 0;
}

static const JanetAbstractType janet_rl_texture_type = {
    "raylib/texture", rl_texture_gc, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL
};

/* (rl/load-texture path) -> texture-handle or nil on failure */
static Janet cfun_load_texture(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 1);
    const char *path = janet_getcstring(argv, 0);
    Image img = LoadImage(path);
    if (img.data == NULL) return janet_wrap_nil();
    ImageFormat(&img, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8);
    JRTexture *jt = janet_abstract(&janet_rl_texture_type, sizeof(JRTexture));
    jt->cpu_img = img;
    jt->gpu_tex = LoadTextureFromImage(img);
    return janet_wrap_abstract(jt);
}

/* (rl/unload-texture tex) -> nil  — explicit early unload */
static Janet cfun_unload_texture(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 1);
    JRTexture *jt = janet_getabstract(argv, 0, &janet_rl_texture_type);
    if (jt->gpu_tex.id   != 0)    { UnloadTexture(jt->gpu_tex); jt->gpu_tex.id = 0; }
    if (jt->cpu_img.data != NULL) { UnloadImage(jt->cpu_img);  jt->cpu_img.data = NULL; }
    return janet_wrap_nil();
}

/* (rl/texture-size tex) -> [w h] */
static Janet cfun_texture_size(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 1);
    JRTexture *jt = janet_getabstract(argv, 0, &janet_rl_texture_type);
    Janet *tup = janet_tuple_begin(2);
    tup[0] = janet_wrap_integer(jt->gpu_tex.width);
    tup[1] = janet_wrap_integer(jt->gpu_tex.height);
    return janet_wrap_tuple(janet_tuple_end(tup));
}

/* (rl/draw-texture-strip tex u dst-x dst-y dst-h r g b) -> nil
   Draws one pixel-wide vertical strip at texture column u [0,1) scaled
   to dst-h pixels on screen.  r/g/b are the distance shade (0-255). */
static Janet cfun_draw_texture_strip(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 8);
    JRTexture *jt = janet_getabstract(argv, 0, &janet_rl_texture_type);
    float u   = (float)janet_getnumber(argv, 1);
    int dst_x = janet_getinteger(argv, 2);
    int dst_y = janet_getinteger(argv, 3);
    int dst_h = janet_getinteger(argv, 4);
    int r     = janet_getinteger(argv, 5);
    int g     = janet_getinteger(argv, 6);
    int b     = janet_getinteger(argv, 7);

    if (jt->gpu_tex.id == 0 || dst_h <= 0) return janet_wrap_nil();

    float tw  = (float)jt->gpu_tex.width;
    float th  = (float)jt->gpu_tex.height;
    float sx  = u * tw;
    if (sx < 0.0f) sx = 0.0f;
    if (sx >= tw)  sx = tw - 1.0f;

    Rectangle src = { sx, 0.0f, 1.0f, th };
    Rectangle dst = { (float)dst_x, (float)dst_y, 1.0f, (float)dst_h };
    Color tint = { (unsigned char)r, (unsigned char)g, (unsigned char)b, 255 };
    DrawTexturePro(jt->gpu_tex, src, dst, (Vector2){0.0f,0.0f}, 0.0f, tint);
    return janet_wrap_nil();
}

/* (rl/draw-floor-ceiling floor-tex ceil-tex
       px py dir-x dir-y plane-x plane-y
       view-x view-y view-w view-h) -> nil
   Classic floor-casting scanline renderer.
   Pass nil for floor-tex or ceil-tex to skip that surface. */
static Janet cfun_draw_floor_ceiling(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 12);

    JRTexture *floor_tex = NULL;
    JRTexture *ceil_tex  = NULL;
    if (janet_checktype(argv[0], JANET_ABSTRACT))
        floor_tex = (JRTexture *)janet_getabstract(argv, 0, &janet_rl_texture_type);
    if (janet_checktype(argv[1], JANET_ABSTRACT))
        ceil_tex  = (JRTexture *)janet_getabstract(argv, 1, &janet_rl_texture_type);
    if (!floor_tex && !ceil_tex) return janet_wrap_nil();

    float px      = (float)janet_getnumber(argv, 2);
    float py      = (float)janet_getnumber(argv, 3);
    float dir_x   = (float)janet_getnumber(argv, 4);
    float dir_y   = (float)janet_getnumber(argv, 5);
    float plane_x = (float)janet_getnumber(argv, 6);
    float plane_y = (float)janet_getnumber(argv, 7);
    int view_x    = janet_getinteger(argv, 8);
    int view_y    = janet_getinteger(argv, 9);
    int view_w    = janet_getinteger(argv, 10);
    int view_h    = janet_getinteger(argv, 11);

    int halfH = view_h / 2;

    for (int y = 0; y < view_h; y++) {
        int rel_y  = y - halfH;
        if (rel_y == 0) continue;
        int is_floor = (rel_y > 0);
        JRTexture *tex = is_floor ? floor_tex : ceil_tex;
        if (!tex || !tex->cpu_img.data) continue;

        float absY   = (float)(rel_y < 0 ? -rel_y : rel_y);
        float rowDist = (float)halfH / absY;

        float stepX = rowDist * 2.0f * plane_x / (float)view_w;
        float stepY = rowDist * 2.0f * plane_y / (float)view_w;

        float floorX = px + rowDist * (dir_x - plane_x);
        float floorY = py + rowDist * (dir_y - plane_y);

        int tw = tex->cpu_img.width;
        int th = tex->cpu_img.height;

        float shade = 1.0f - rowDist / 12.0f;
        if (shade < 0.25f) shade = 0.25f;
        if (shade > 1.0f)  shade = 1.0f;

        for (int x = 0; x < view_w; x++, floorX += stepX, floorY += stepY) {
            int tx = (int)(floorX * (float)tw) % tw;
            int ty = (int)(floorY * (float)th) % th;
            if (tx < 0) tx += tw;
            if (ty < 0) ty += th;

            Color col = GetImageColor(tex->cpu_img, tx, ty);
            col.r = (unsigned char)((float)col.r * shade);
            col.g = (unsigned char)((float)col.g * shade);
            col.b = (unsigned char)((float)col.b * shade);
            DrawPixel(view_x + x, view_y + y, col);
        }
    }
    return janet_wrap_nil();
}

/* ═══════════════════════════════════════════════════════════════
 * Isometric diamond primitives
 * Used by the Gold Box-style tactical combat view.
 *
 * A diamond is drawn as four triangles meeting at the centre.
 * Raylib requires CCW winding in screen-space (y increases down),
 * so for each quadrant we go: centre → spoke_A → spoke_B.
 * ═══════════════════════════════════════════════════════════════ */

/* (rl/fill-diamond cx cy hw hh) — filled diamond centred at (cx,cy) */
static Janet cfun_fill_diamond(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 4);
    float cx = (float)janet_getinteger(argv, 0);
    float cy = (float)janet_getinteger(argv, 1);
    float hw = (float)janet_getinteger(argv, 2);   /* half-width  */
    float hh = (float)janet_getinteger(argv, 3);   /* half-height */

    Vector2 top    = {cx,      cy - hh};
    Vector2 right  = {cx + hw, cy};
    Vector2 bottom = {cx,      cy + hh};
    Vector2 left   = {cx - hw, cy};
    Vector2 center = {cx,      cy};

    /* CCW order (y-down screen space): centre → spokeCCW → spokeCW */
    DrawTriangle(center, top,    right,  g_draw_color);
    DrawTriangle(center, right,  bottom, g_draw_color);
    DrawTriangle(center, bottom, left,   g_draw_color);
    DrawTriangle(center, left,   top,    g_draw_color);
    return janet_wrap_nil();
}

/* (rl/draw-diamond-lines cx cy hw hh) — diamond outline */
static Janet cfun_draw_diamond_lines(int32_t argc, Janet *argv)
{
    janet_fixarity(argc, 4);
    int cx = janet_getinteger(argv, 0);
    int cy = janet_getinteger(argv, 1);
    int hw = janet_getinteger(argv, 2);
    int hh = janet_getinteger(argv, 3);

    DrawLine(cx,      cy - hh, cx + hw, cy,      g_draw_color);
    DrawLine(cx + hw, cy,      cx,      cy + hh, g_draw_color);
    DrawLine(cx,      cy + hh, cx - hw, cy,      g_draw_color);
    DrawLine(cx - hw, cy,      cx,      cy - hh, g_draw_color);
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
    {"load-texture",       cfun_load_texture,       "(rl/load-texture path)"},
    {"unload-texture",     cfun_unload_texture,     "(rl/unload-texture tex)"},
    {"texture-size",       cfun_texture_size,       "(rl/texture-size tex)"},
    {"draw-texture-strip", cfun_draw_texture_strip, "(rl/draw-texture-strip tex u x y h r g b)"},
    {"draw-floor-ceiling", cfun_draw_floor_ceiling, "(rl/draw-floor-ceiling ft ct px py dx dy plx ply vx vy vw vh)"},
    {"fill-diamond",       cfun_fill_diamond,       "(rl/fill-diamond cx cy hw hh)"},
    {"draw-diamond-lines", cfun_draw_diamond_lines, "(rl/draw-diamond-lines cx cy hw hh)"},
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
    janet_def(env, "SC_N",         janet_wrap_integer(KEY_N),         "new game");
    janet_def(env, "SC_F1",        janet_wrap_integer(KEY_F1),        "party member 1");
    janet_def(env, "SC_F2",        janet_wrap_integer(KEY_F2),        "party member 2");
    janet_def(env, "SC_F3",        janet_wrap_integer(KEY_F3),        "party member 3");
    janet_def(env, "SC_F4",        janet_wrap_integer(KEY_F4),        "party member 4");
    janet_def(env, "SC_1",         janet_wrap_integer(KEY_ONE),       "select party member 1");
    janet_def(env, "SC_2",         janet_wrap_integer(KEY_TWO),       "select party member 2");
    janet_def(env, "SC_3",         janet_wrap_integer(KEY_THREE),     "select party member 3");
    janet_def(env, "SC_4",         janet_wrap_integer(KEY_FOUR),      "select party member 4");
    janet_def(env, "SC_F10",       janet_wrap_integer(KEY_F10),       "save/load menu");
}
