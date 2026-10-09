/* 2Xtreme in-game menu (pause + settings).
 *
 * Model: recomp-ui's runtime menu (sections, navigation, values, save
 * callbacks), shared with every recomp-ui host. Presentation: drawn here in
 * 2Xtreme's own style (docs/DESIGN_PRINCIPLES.md §4) over the frozen frame.
 *
 * Doors: Esc, the controller's Guide button or Select+Start, ⌘, (also from
 * the macOS menu bar) and, from M4, the game's own Options item. All of them
 * reach this one menu.
 *
 * The game is paused while the menu is open: psxrecomp calls
 * psx_host_overlay_present() before each swap, and while the menu is open we
 * stay inside it, redrawing the frozen frame, until the player resumes.
 */
#include <SDL3/SDL.h>
#include <OpenGL/gl3.h>

#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>

#include "imgui.h"
#include "imgui_impl_opengl3.h"
#include "imgui_impl_sdl3.h"

extern "C" {
#include "recomp_runtime_ui.h"
#include "recomp_runtime_ui_internal.h"
#include "gpu_render.h"
#include "host_osd.h"
}
#include "config_loader.h"
#include "twox_overlay.h"

namespace fs = std::filesystem;

namespace {

/* ---------- Tokens (shared with the setup screen in launcher/main.m) ---------- */
const ImU32 kYellow = IM_COL32(245, 217, 46, 255);
const ImU32 kGreen  = IM_COL32(79, 204, 125, 255);
const ImU32 kInk    = IM_COL32(10, 8, 8, 255);
const ImU32 kText   = IM_COL32(219, 214, 204, 255);
const ImU32 kMuted  = IM_COL32(219, 214, 204, 150);

enum Device { DEV_KEYBOARD, DEV_XBOX, DEV_PLAYSTATION };

struct State {
    bool ready = false;
    SDL_Window *win = nullptr;
    ImGuiContext *ctx = nullptr;
    ImFont *block = nullptr;
    ImFont *body = nullptr;
    RecompRuntimeUi *ui = nullptr;
    GLuint frame_tex = 0;
    int frame_w = 0, frame_h = 0;
    Device device = DEV_KEYBOARD;
    bool quit_after_close = false;
    /* Current values (applied live, persisted on change). */
    int sharpness = 4;   /* internal scale 1..4 */
    int smoothing = 0;   /* 0 sharp pixels, 1 smooth */
    int fullscreen = 0;
    int volume = 100;
    fs::path settings_path, prefs_path;
} S;

std::atomic<int> g_open_requested{0};

/* ---------- Menu model ---------- */

const char *const kSharpness[] = {"Original", "2x", "3x", "4x"};
const char *const kSmoothing[] = {"Sharp pixels", "Smooth"};

const RecompRuntimeUiItem kItems[] = {
    {"twox.resume", "Resume", "Resume", "Back to the game.", RECOMP_RUNTIME_UI_ACTION, 0, 0, 0, nullptr, 0, nullptr},
    {"twox.sharpness", "Picture", "Sharpness",
     "How finely the 3D world is drawn. Higher looks sharper and needs a faster Mac. Shows when you resume.",
     RECOMP_RUNTIME_UI_CHOICE, 1, 4, 1, kSharpness, 4, nullptr},
    {"twox.smoothing", "Picture", "Textures",
     "Sharp pixels keeps the original look. Smooth blends texture pixels. Shows when you resume.",
     RECOMP_RUNTIME_UI_CHOICE, 0, 1, 1, kSmoothing, 2, nullptr},
    {"twox.fullscreen", "Picture", "Full screen", "Fill the whole display.",
     RECOMP_RUNTIME_UI_BOOL, 0, 1, 1, nullptr, 0, nullptr},
    {"twox.volume", "Sound", "Volume", "Music and sound effects.",
     RECOMP_RUNTIME_UI_INT, 0, 100, 10, nullptr, 0, nullptr},
    {"twox.quit", "Quit game", "Quit game", "Close 2Xtreme. Your memory card saves are kept.",
     RECOMP_RUNTIME_UI_ACTION, 0, 0, 0, nullptr, 0, nullptr},
};

bool key_is(const RecompRuntimeUiItem *item, const char *key) { return std::strcmp(item->key, key) == 0; }

int cb_get(void *, const RecompRuntimeUiItem *item, int *out) {
    if (key_is(item, "twox.sharpness")) *out = S.sharpness;
    else if (key_is(item, "twox.smoothing")) *out = S.smoothing;
    else if (key_is(item, "twox.fullscreen")) *out = S.fullscreen;
    else if (key_is(item, "twox.volume")) *out = S.volume;
    else return 0;
    return 1;
}

int cb_set(void *, const RecompRuntimeUiItem *item, int v) {
    if (key_is(item, "twox.sharpness")) { S.sharpness = v; gr_set_scale(v); }
    else if (key_is(item, "twox.smoothing")) { S.smoothing = v; gr_set_texture_filter(v); }
    else if (key_is(item, "twox.fullscreen")) { S.fullscreen = v; SDL_SetWindowFullscreen(S.win, v != 0); }
    else if (key_is(item, "twox.volume")) { S.volume = v; host_volume_set(v); }
    else return 0;
    return 1;
}

int cb_action(void *, const RecompRuntimeUiItem *item) {
    if (key_is(item, "twox.resume")) { recomp_runtime_ui_close(S.ui); return 1; }
    if (key_is(item, "twox.quit")) { S.quit_after_close = true; recomp_runtime_ui_close(S.ui); return 1; }
    return 0;
}

int cb_enabled(void *, const RecompRuntimeUiItem *) { return 1; }

void cb_save(void *) {
    PSXRecompV4::UserSettings s = PSXRecompV4::load_user_settings(S.settings_path);
    s.has_internal_resolution = true; s.internal_resolution = 240 * S.sharpness;
    s.has_supersampling = true;       s.supersampling = S.sharpness;
    s.has_texture_filter = true;      s.texture_filter = S.smoothing;
    s.has_fullscreen = true;          s.fullscreen = S.fullscreen ? 1 : 0;
    PSXRecompV4::save_user_settings(S.settings_path, s);
    std::ofstream(S.prefs_path) << "volume=" << S.volume << "\n";
}

void load_values() {
    PSXRecompV4::UserSettings s = PSXRecompV4::load_user_settings(S.settings_path);
    if (s.has_internal_resolution && s.internal_resolution > 0)
        S.sharpness = std::max(1, std::min(4, (int)std::lround(s.internal_resolution / 240.0)));
    else if (s.has_supersampling)
        S.sharpness = std::max(1, std::min(4, s.supersampling));
    if (s.has_texture_filter) S.smoothing = s.texture_filter ? 1 : 0;
    S.fullscreen = (SDL_GetWindowFlags(S.win) & SDL_WINDOW_FULLSCREEN) ? 1 : 0;
    std::ifstream in(S.prefs_path);
    std::string line;
    while (std::getline(in, line))
        if (line.rfind("volume=", 0) == 0) S.volume = std::max(0, std::min(100, std::atoi(line.c_str() + 7)));
    host_volume_set(S.volume);
}

/* ---------- Doors: Esc, Guide, Select+Start, ⌘, ---------- */

bool held(SDL_JoystickID id, SDL_GamepadButton b) {
    SDL_Gamepad *g = SDL_GetGamepadFromID(id);
    return g && SDL_GetGamepadButton(g, b);
}

Device device_for(SDL_JoystickID id) {
    SDL_Gamepad *g = SDL_GetGamepadFromID(id);
    switch (g ? SDL_GetGamepadType(g) : SDL_GAMEPAD_TYPE_UNKNOWN) {
        case SDL_GAMEPAD_TYPE_PS3: case SDL_GAMEPAD_TYPE_PS4: case SDL_GAMEPAD_TYPE_PS5: return DEV_PLAYSTATION;
        default: return DEV_XBOX;
    }
}

bool SDLCALL event_filter(void *, SDL_Event *e) {
    if (S.ui && recomp_runtime_ui_is_open(S.ui)) return true;   /* the menu polls them itself */
    if (e->type == SDL_EVENT_KEY_DOWN || e->type == SDL_EVENT_KEY_UP) {
        const bool cmd_comma = e->key.key == SDLK_COMMA && (e->key.mod & SDL_KMOD_GUI);
        if (e->key.key == SDLK_ESCAPE || cmd_comma) {
            if (e->type == SDL_EVENT_KEY_DOWN && !e->key.repeat) { S.device = DEV_KEYBOARD; g_open_requested = 1; }
            return false;
        }
    }
    if (e->type == SDL_EVENT_GAMEPAD_BUTTON_DOWN) {
        const SDL_JoystickID id = e->gbutton.which;
        const int b = e->gbutton.button;
        const bool chord = (b == SDL_GAMEPAD_BUTTON_START && held(id, SDL_GAMEPAD_BUTTON_BACK)) ||
                           (b == SDL_GAMEPAD_BUTTON_BACK && held(id, SDL_GAMEPAD_BUTTON_START));
        if (b == SDL_GAMEPAD_BUTTON_GUIDE || chord) {
            S.device = device_for(id);
            g_open_requested = 1;
            return false;
        }
    }
    return true;
}

/* ---------- Drawing ---------- */

float g_u = 1.0f;  /* layout unit: 1/720 of the display height */

ImVec2 text_size(ImFont *f, float size, const char *t) { return f->CalcTextSizeA(size, FLT_MAX, 0.0f, t); }

/* Extruded block capitals, like 2Xtreme's menu lettering. */
void block_text(ImDrawList *dl, const char *t, ImVec2 center, float size, ImU32 face, bool left = false) {
    ImVec2 sz = text_size(S.block, size, t);
    ImVec2 p(left ? center.x : std::round(center.x - sz.x / 2), std::round(center.y - sz.y / 2));
    int steps = std::max(2, (int)(size / 14));
    for (int i = steps; i > 0; i--) dl->AddText(S.block, size, ImVec2(p.x + i, p.y + i), kInk, t);
    dl->AddText(S.block, size, p, face, t);
}

void body_text(ImDrawList *dl, const char *t, ImVec2 center, float size, ImU32 col) {
    ImVec2 sz = text_size(S.body, size, t);
    dl->AddText(S.body, size, ImVec2(std::round(center.x - sz.x / 2), std::round(center.y - sz.y / 2)), col, t);
}

/* Button glyphs drawn as shapes, matched to the device in use. */
float prompt(ImDrawList *dl, float x, float y, int accept, const char *label) {
    const float r = 13 * g_u;
    ImVec2 c(x + r, y);
    if (S.device == DEV_PLAYSTATION) {
        dl->AddCircleFilled(c, r, IM_COL32(30, 30, 34, 255));
        if (accept) {
            const float k = r * 0.45f;
            dl->AddLine(ImVec2(c.x - k, c.y - k), ImVec2(c.x + k, c.y + k), IM_COL32(120, 160, 230, 255), 3 * g_u);
            dl->AddLine(ImVec2(c.x - k, c.y + k), ImVec2(c.x + k, c.y - k), IM_COL32(120, 160, 230, 255), 3 * g_u);
        } else {
            dl->AddCircle(c, r * 0.5f, IM_COL32(230, 110, 110, 255), 0, 2.6f * g_u);
        }
    } else if (S.device == DEV_XBOX) {
        dl->AddCircleFilled(c, r, accept ? IM_COL32(70, 170, 70, 255) : IM_COL32(200, 60, 50, 255));
        const char *l = accept ? "A" : "B";
        ImVec2 ls = text_size(S.block, 20 * g_u, l);
        dl->AddText(S.block, 20 * g_u, ImVec2(c.x - ls.x / 2, c.y - ls.y / 2), kInk, l);
    } else {
        const char *k = accept ? "Return" : "Esc";
        ImVec2 ks = text_size(S.body, 17 * g_u, k);
        ImVec2 a(x, y - r), b(x + ks.x + 16 * g_u, y + r);
        dl->AddRectFilled(a, b, IM_COL32(40, 40, 44, 255), 5 * g_u);
        dl->AddText(S.body, 17 * g_u, ImVec2(x + 8 * g_u, y - ks.y / 2), kText, k);
        c.x = b.x - r;
    }
    ImVec2 ts = text_size(S.block, 24 * g_u, label);
    dl->AddText(S.block, 24 * g_u, ImVec2(c.x + r + 10 * g_u, y - ts.y / 2), kText, label);
    return c.x + r + 10 * g_u + ts.x + 26 * g_u;
}

void arrow(ImDrawList *dl, ImVec2 c, float s, int dir, ImU32 col) {
    dl->AddTriangleFilled(ImVec2(c.x + dir * s, c.y), ImVec2(c.x - dir * s, c.y - s), ImVec2(c.x - dir * s, c.y + s), col);
}

std::string upper(const char *s) {
    std::string u(s);
    for (char &ch : u) ch = (char)std::toupper((unsigned char)ch);
    return u;
}

std::string value_text(const RecompRuntimeUiItem *item) {
    int v = 0;
    if (!recomp_runtime_ui_current_value(S.ui, item, &v)) return "";
    switch (item->type) {
        case RECOMP_RUNTIME_UI_BOOL: return v ? "On" : "Off";
        case RECOMP_RUNTIME_UI_CHOICE: {
            int idx = v - item->minimum;
            return (idx >= 0 && (size_t)idx < item->choice_count) ? item->choices[idx] : "";
        }
        case RECOMP_RUNTIME_UI_INT: {
            char b[16]; std::snprintf(b, sizeof b, "%d%%", v); return b;
        }
        default: return "";
    }
}

bool section_is_action(size_t section) {
    return recomp_runtime_ui_section_item_count(S.ui, section) == 1 &&
           recomp_runtime_ui_section_item(S.ui, section, 0)->type == RECOMP_RUNTIME_UI_ACTION;
}

void draw_menu(float W, float H) {
    ImDrawList *dl = ImGui::GetForegroundDrawList();
    g_u = H / 720.0f;
    /* The frozen game, dimmed, with the original menu's vignette. */
    dl->AddImage((ImTextureID)(intptr_t)S.frame_tex, ImVec2(0, 0), ImVec2(W, H), ImVec2(0, 1), ImVec2(1, 0));
    dl->AddRectFilled(ImVec2(0, 0), ImVec2(W, H), IM_COL32(0, 0, 0, 130));
    /* A soft darker band behind the menu column, so our items stay readable
     * over the game's own lettering while the scene shows at the sides. */
    {
        const float bw = 330 * g_u, fade = 150 * g_u, cxb = W / 2;
        const ImU32 band = IM_COL32(0, 0, 0, 120), clear = IM_COL32(0, 0, 0, 0);
        dl->AddRectFilledMultiColor(ImVec2(cxb - bw - fade, 0), ImVec2(cxb - bw, H), clear, band, band, clear);
        dl->AddRectFilled(ImVec2(cxb - bw, 0), ImVec2(cxb + bw, H), band);
        dl->AddRectFilledMultiColor(ImVec2(cxb + bw, 0), ImVec2(cxb + bw + fade, H), band, clear, clear, band);
    }
    dl->AddRectFilledMultiColor(ImVec2(0, 0), ImVec2(W, H * 0.25f), IM_COL32(0, 0, 0, 120), IM_COL32(0, 0, 0, 120),
                                IM_COL32(0, 0, 0, 0), IM_COL32(0, 0, 0, 0));
    dl->AddRectFilledMultiColor(ImVec2(0, H * 0.75f), ImVec2(W, H), IM_COL32(0, 0, 0, 0), IM_COL32(0, 0, 0, 0),
                                IM_COL32(0, 0, 0, 140), IM_COL32(0, 0, 0, 140));
    RecompRuntimeUi *ui = S.ui;
    const float cx = W / 2;

    if (!ui->in_section) {
        block_text(dl, "PAUSED", ImVec2(cx, 150 * g_u), 76 * g_u, kYellow);
        const float top = 290 * g_u, step = 76 * g_u;
        for (size_t i = 0; i < ui->section_count; i++) {
            const bool sel = i == ui->section_index;
            block_text(dl, upper(ui->sections[i]).c_str(), ImVec2(cx, top + step * i),
                       (sel ? 60 : 46) * g_u, sel ? kYellow : kGreen);
        }
    } else {
        const size_t sec = ui->section_index;
        block_text(dl, upper(ui->sections[sec]).c_str(), ImVec2(cx, 130 * g_u), 64 * g_u, kYellow);
        const size_t n = recomp_runtime_ui_section_item_count(ui, sec);
        const float top = 250 * g_u, step = 72 * g_u, half = 360 * g_u;
        for (size_t r = 0; r < n; r++) {
            const RecompRuntimeUiItem *item = recomp_runtime_ui_section_item(ui, sec, r);
            const bool sel = r == ui->row_index;
            const float y = top + step * r;
            if (sel) dl->AddRectFilled(ImVec2(cx - half - 24 * g_u, y - 30 * g_u), ImVec2(cx + half + 24 * g_u, y + 30 * g_u),
                                       IM_COL32(0, 0, 0, 140));
            block_text(dl, upper(item->label).c_str(), ImVec2(cx - half, y), (sel ? 44 : 38) * g_u, sel ? kYellow : kGreen, true);
            std::string v = value_text(item);
            if (!v.empty()) {
                const float vs = 30 * g_u;
                ImVec2 sz = text_size(S.block, vs, v.c_str());
                ImVec2 p(cx + half - sz.x, y - sz.y / 2);
                dl->AddText(S.block, vs, p, sel ? kYellow : kText, v.c_str());
                if (sel) {
                    arrow(dl, ImVec2(p.x - 22 * g_u, y), 9 * g_u, -1, kYellow);
                    arrow(dl, ImVec2(cx + half + 14 * g_u, y), 9 * g_u, 1, kYellow);
                }
            }
        }
        const RecompRuntimeUiItem *cur = recomp_runtime_ui_section_item(ui, sec, ui->row_index);
        if (cur && cur->description) body_text(dl, cur->description, ImVec2(cx, top + step * n + 30 * g_u), 22 * g_u, kMuted);
    }
    /* Prompt strip, bottom left, like the original's D-pad / ✕ Select. */
    const float py = H - 46 * g_u;
    dl->AddRectFilled(ImVec2(24 * g_u, py - 26 * g_u), ImVec2(24 * g_u + 420 * g_u, py + 26 * g_u), IM_COL32(0, 0, 0, 150));
    float x = prompt(dl, 40 * g_u, py, 1, "Select");
    prompt(dl, x, py, 0, ui->in_section ? "Back" : "Resume");
}

/* ---------- Frame capture ---------- */

void capture_frame() {
    int w = 0, h = 0;
    SDL_GetWindowSizeInPixels(S.win, &w, &h);
    GLint prev_tex = 0, prev_read = 0;
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &prev_tex);
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &prev_read);
    if (!S.frame_tex) glGenTextures(1, &S.frame_tex);
    glBindTexture(GL_TEXTURE_2D, S.frame_tex);
    if (w != S.frame_w || h != S.frame_h) {
        /* RGB, not RGBA: the game's frame carries alpha 0 almost everywhere,
         * so an RGBA copy drew as black under ImGui's blending. */
        GLint prev_unpack = 0;
        glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &prev_unpack);
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB8, w, h, 0, GL_RGB, GL_UNSIGNED_BYTE, nullptr);
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, (GLuint)prev_unpack);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        S.frame_w = w; S.frame_h = h;
    }
    glBindFramebuffer(GL_READ_FRAMEBUFFER, 0);
    glReadBuffer(GL_BACK);
    glCopyTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 0, 0, w, h);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, (GLuint)prev_read);
    glBindTexture(GL_TEXTURE_2D, (GLuint)prev_tex);
}

void render_frame(bool with_menu) {
    ImGui_ImplOpenGL3_NewFrame();
    ImGui_ImplSDL3_NewFrame();
    ImGui::NewFrame();
    ImGuiIO &io = ImGui::GetIO();
    if (with_menu) draw_menu(io.DisplaySize.x, io.DisplaySize.y);
    else ImGui::GetForegroundDrawList()->AddImage((ImTextureID)(intptr_t)S.frame_tex, ImVec2(0, 0), io.DisplaySize,
                                                  ImVec2(0, 1), ImVec2(1, 0));
    ImGui::Render();
    int w = 0, h = 0;
    SDL_GetWindowSizeInPixels(S.win, &w, &h);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glViewport(0, 0, w, h);
    glClearColor(0, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
}

/* ---------- Input while open ---------- */

void send(RecompRuntimeUiInput in, bool repeat) {
    RecompRuntimeUi *ui = S.ui;
    if (in == RECOMP_RUNTIME_UI_INPUT_ACCEPT && !ui->in_section && section_is_action(ui->section_index)) {
        if (!repeat) cb_action(nullptr, recomp_runtime_ui_section_item(ui, ui->section_index, 0));
        return;
    }
    recomp_runtime_ui_handle_input(ui, in, 1, repeat ? 1 : 0);
}

void handle_event(const SDL_Event &e) {
    if (e.type == SDL_EVENT_QUIT || e.type == SDL_EVENT_WINDOW_CLOSE_REQUESTED) {
        S.quit_after_close = true;
        recomp_runtime_ui_close(S.ui);
        return;
    }
    if (e.type == SDL_EVENT_KEY_DOWN) {
        S.device = DEV_KEYBOARD;
        const bool rep = e.key.repeat;
        switch (e.key.key) {
            case SDLK_UP: case SDLK_W: send(RECOMP_RUNTIME_UI_INPUT_UP, rep); break;
            case SDLK_DOWN: case SDLK_S: send(RECOMP_RUNTIME_UI_INPUT_DOWN, rep); break;
            case SDLK_LEFT: case SDLK_A: send(RECOMP_RUNTIME_UI_INPUT_LEFT, rep); break;
            case SDLK_RIGHT: case SDLK_D: send(RECOMP_RUNTIME_UI_INPUT_RIGHT, rep); break;
            case SDLK_RETURN: case SDLK_KP_ENTER: case SDLK_SPACE: send(RECOMP_RUNTIME_UI_INPUT_ACCEPT, rep); break;
            case SDLK_ESCAPE: case SDLK_BACKSPACE: send(RECOMP_RUNTIME_UI_INPUT_BACK, rep); break;
            case SDLK_COMMA: if (e.key.mod & SDL_KMOD_GUI) recomp_runtime_ui_close(S.ui); break;
            default: break;
        }
    } else if (e.type == SDL_EVENT_GAMEPAD_BUTTON_DOWN) {
        S.device = device_for(e.gbutton.which);
        switch (e.gbutton.button) {
            case SDL_GAMEPAD_BUTTON_DPAD_UP: send(RECOMP_RUNTIME_UI_INPUT_UP, false); break;
            case SDL_GAMEPAD_BUTTON_DPAD_DOWN: send(RECOMP_RUNTIME_UI_INPUT_DOWN, false); break;
            case SDL_GAMEPAD_BUTTON_DPAD_LEFT: send(RECOMP_RUNTIME_UI_INPUT_LEFT, false); break;
            case SDL_GAMEPAD_BUTTON_DPAD_RIGHT: send(RECOMP_RUNTIME_UI_INPUT_RIGHT, false); break;
            case SDL_GAMEPAD_BUTTON_SOUTH: send(RECOMP_RUNTIME_UI_INPUT_ACCEPT, false); break;
            case SDL_GAMEPAD_BUTTON_EAST: send(RECOMP_RUNTIME_UI_INPUT_BACK, false); break;
            case SDL_GAMEPAD_BUTTON_START: case SDL_GAMEPAD_BUTTON_GUIDE: recomp_runtime_ui_close(S.ui); break;
            default: break;
        }
    }
}

/* Developer/test hook: TWOXTREME_TEST_SCRIPT="down,accept,right,back" feeds
 * menu inputs one step every 1.5 s, so journeys can be screenshotted and
 * tested without anyone at the keyboard. */
void run_test_step(const char *step) {
    S.device = DEV_KEYBOARD;
    if (!std::strcmp(step, "up")) send(RECOMP_RUNTIME_UI_INPUT_UP, false);
    else if (!std::strcmp(step, "down")) send(RECOMP_RUNTIME_UI_INPUT_DOWN, false);
    else if (!std::strcmp(step, "left")) send(RECOMP_RUNTIME_UI_INPUT_LEFT, false);
    else if (!std::strcmp(step, "right")) send(RECOMP_RUNTIME_UI_INPUT_RIGHT, false);
    else if (!std::strcmp(step, "accept")) send(RECOMP_RUNTIME_UI_INPUT_ACCEPT, false);
    else if (!std::strcmp(step, "back")) send(RECOMP_RUNTIME_UI_INPUT_BACK, false);
    else if (!std::strcmp(step, "xbox")) S.device = DEV_XBOX;
    else if (!std::strcmp(step, "ps")) S.device = DEV_PLAYSTATION;
    std::fprintf(stderr, "2Xtreme menu test: %s -> open=%d in_section=%d section=%zu row=%zu\n", step,
                 recomp_runtime_ui_is_open(S.ui), S.ui->in_section, S.ui->section_index, S.ui->row_index);
}

/* Nothing may leak into the game: wait until every key and button is up. */
void wait_for_release() {
    const Uint64 until = SDL_GetTicks() + 1000;
    while (SDL_GetTicks() < until) {
        SDL_PumpEvents();
        int n = 0;
        const bool *keys = SDL_GetKeyboardState(&n);
        bool any = false;
        for (int i = 0; i < n && !any; i++) any = keys[i];
        int count = 0;
        SDL_JoystickID *ids = SDL_GetGamepads(&count);
        for (int i = 0; i < count && !any; i++) {
            SDL_Gamepad *g = SDL_GetGamepadFromID(ids[i]);
            for (int b = 0; g && b < SDL_GAMEPAD_BUTTON_COUNT && !any; b++)
                any = SDL_GetGamepadButton(g, (SDL_GamepadButton)b);
        }
        SDL_free(ids);
        if (!any) break;
        render_frame(false);
        SDL_GL_SwapWindow(S.win);
    }
    SDL_FlushEvents(SDL_EVENT_KEY_DOWN, SDL_EVENT_KEY_UP);
    SDL_FlushEvents(SDL_EVENT_GAMEPAD_AXIS_MOTION, SDL_EVENT_GAMEPAD_BUTTON_UP);
}

/* ---------- Lifetime ---------- */

void init(SDL_Window *win) {
    S.win = win;
    const char *base = SDL_GetBasePath();
    fs::path dir = base ? fs::path(base) : fs::current_path();
    S.settings_path = dir / "settings.toml";
    S.prefs_path = dir / "2xtreme_prefs.ini";

    ImGuiContext *prev = ImGui::GetCurrentContext();
    S.ctx = ImGui::CreateContext();
    ImGui::SetCurrentContext(S.ctx);
    ImGuiIO &io = ImGui::GetIO();
    io.IniFilename = nullptr;
    io.ConfigFlags |= ImGuiConfigFlags_NoMouseCursorChange;
    float px = 2.0f;  /* load glyphs at device resolution for crisp text */
    int w = 0, h = 0, pw = 0, ph = 0;
    SDL_GetWindowSize(win, &w, &h);
    SDL_GetWindowSizeInPixels(win, &pw, &ph);
    if (w > 0) px = std::max(1.0f, (float)pw / (float)w);
    ImFontConfig cfg;
    cfg.FontNo = 4;  /* Futura Condensed ExtraBold */
    const char *futura = "/System/Library/Fonts/Supplemental/Futura.ttc";
    S.block = io.Fonts->AddFontFromFileTTF(futura, 96.0f * px, &cfg);
    ImFontConfig body;
    body.FontNo = 0;  /* Futura Medium */
    S.body = io.Fonts->AddFontFromFileTTF(futura, 30.0f * px, &body);
    if (!S.block) S.block = io.Fonts->AddFontDefault();
    if (!S.body) S.body = S.block;
    ImGui_ImplSDL3_InitForOpenGL(win, SDL_GL_GetCurrentContext());
    ImGui_ImplOpenGL3_Init("#version 150");
    ImGui::SetCurrentContext(prev);

    RecompRuntimeUiConfig cfgui{};
    cfgui.title = "2Xtreme";
    cfgui.items = kItems;
    cfgui.item_count = sizeof(kItems) / sizeof(kItems[0]);
    cfgui.callbacks.get_value = cb_get;
    cfgui.callbacks.set_value = cb_set;
    cfgui.callbacks.run_action = cb_action;
    cfgui.callbacks.is_enabled = cb_enabled;
    cfgui.callbacks.save = cb_save;
    S.ui = recomp_runtime_ui_create(&cfgui);
    load_values();
    SDL_SetEventFilter(event_filter, nullptr);
    S.ready = true;
}

void run_menu() {
    if (getenv("TWOXTREME_TEST_SCRIPT")) std::fprintf(stderr, "2Xtreme menu test: OPEN\n");
    ImGuiContext *prev = ImGui::GetCurrentContext();
    ImGui::SetCurrentContext(S.ctx);
    capture_frame();
    S.quit_after_close = false;
    recomp_runtime_ui_open(S.ui);
    S.ui->in_section = 0;
    S.ui->section_index = 0;
    std::string script;
    if (const char *t = getenv("TWOXTREME_TEST_SCRIPT")) script = t;
    size_t script_pos = 0;
    Uint64 next_step = SDL_GetTicks() + 1500;
    while (recomp_runtime_ui_is_open(S.ui)) {
        if (!script.empty() && script_pos < script.size() && SDL_GetTicks() >= next_step) {
            size_t end = script.find(',', script_pos);
            if (end == std::string::npos) end = script.size();
            run_test_step(script.substr(script_pos, end - script_pos).c_str());
            script_pos = end + 1;
            next_step = SDL_GetTicks() + 1500;
        }
        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            ImGui_ImplSDL3_ProcessEvent(&e);
            handle_event(e);
        }
        if (!recomp_runtime_ui_is_open(S.ui)) break;
        render_frame(true);
        SDL_GL_SwapWindow(S.win);
    }
    if (getenv("TWOXTREME_TEST_SCRIPT")) std::fprintf(stderr, "2Xtreme menu test: CLOSED quit=%d\n", S.quit_after_close);
    wait_for_release();
    render_frame(false);   /* leave the frozen frame in the back buffer for psxrecomp's swap */
    ImGui::SetCurrentContext(prev);
    if (S.quit_after_close) {
        SDL_Event q{};
        q.type = SDL_EVENT_QUIT;
        SDL_PushEvent(&q);
    }
}

}  // namespace

extern "C" void twox_overlay_request_open(void) { g_open_requested = 1; }

extern "C" int twox_overlay_is_open(void) { return S.ui && recomp_runtime_ui_is_open(S.ui); }

/* Called by psxrecomp (gpu_gl_renderer.c) just before each swap. */
extern "C" void psx_host_overlay_present(SDL_Window *win) {
    if (!S.ready) init(win);
    if (const char *t = getenv("TWOXTREME_TEST_OPEN_AFTER_S")) {   /* developer/test hook */
        static Uint64 at = SDL_GetTicks() + (Uint64)(atof(t) * 1000);
        static bool done = false;
        if (!done && SDL_GetTicks() >= at) { done = true; g_open_requested = 1; }
    }
    if (g_open_requested.exchange(0)) run_menu();
}
