// usage: vkbd cmd...   d CODE (press evdev code) | u CODE (release) | t CODE (tap) | s MS (sleep)
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>
#include "virtual-keyboard-unstable-v1.h"
static struct zwp_virtual_keyboard_manager_v1* mgr; static struct wl_seat* seat;
static void g(void* d, struct wl_registry* r, uint32_t n, const char* i, uint32_t v) {
    if (!strcmp(i, zwp_virtual_keyboard_manager_v1_interface.name)) mgr = wl_registry_bind(r, n, &zwp_virtual_keyboard_manager_v1_interface, 1);
    else if (!strcmp(i, wl_seat_interface.name)) seat = wl_registry_bind(r, n, &wl_seat_interface, 1);
}
static void gr(void* d, struct wl_registry* r, uint32_t n) {}
static const struct wl_registry_listener L = {g, gr};
int main(int c, char** v) {
    struct wl_display* dpy = wl_display_connect(NULL); if (!dpy) { fprintf(stderr, "no display\n"); return 1; }
    struct wl_registry* reg = wl_display_get_registry(dpy); wl_registry_add_listener(reg, &L, NULL); wl_display_roundtrip(dpy);
    if (!mgr || !seat) { fprintf(stderr, "no virtual keyboard manager\n"); return 2; }
    struct xkb_context* ctx = xkb_context_new(0);
    struct xkb_rule_names names = { .layout = "us" };
    struct xkb_keymap* km = xkb_keymap_new_from_names(ctx, &names, 0);
    struct xkb_state* st = xkb_state_new(km);
    char* s = xkb_keymap_get_as_string(km, XKB_KEYMAP_FORMAT_TEXT_V1); size_t len = strlen(s) + 1;
    int fd = memfd_create("keymap", 0); write(fd, s, len);
    struct zwp_virtual_keyboard_v1* kb = zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(mgr, seat);
    zwp_virtual_keyboard_v1_keymap(kb, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd, len);
    wl_display_roundtrip(dpy); usleep(100000);
    uint32_t t = 1;
    for (int i = 1; i < c; i++) {
        if (!strcmp(v[i], "s")) { wl_display_roundtrip(dpy); usleep(atoi(v[++i]) * 1000); continue; }
        int code = atoi(v[i + 1]); int down = !strcmp(v[i], "d"), up = !strcmp(v[i], "u"), tap = !strcmp(v[i], "t"); i++;
        for (int phase = 0; phase < (tap ? 2 : 1); phase++) {
            int press = tap ? (phase == 0) : down;
            zwp_virtual_keyboard_v1_key(kb, t += 10, code, press ? 1 : 0);
            xkb_state_update_key(st, code + 8, press ? XKB_KEY_DOWN : XKB_KEY_UP);
            zwp_virtual_keyboard_v1_modifiers(kb, xkb_state_serialize_mods(st, XKB_STATE_MODS_DEPRESSED), xkb_state_serialize_mods(st, XKB_STATE_MODS_LATCHED),
                                              xkb_state_serialize_mods(st, XKB_STATE_MODS_LOCKED), xkb_state_serialize_layout(st, XKB_STATE_LAYOUT_EFFECTIVE));
            wl_display_roundtrip(dpy); usleep(40000);
        }
        (void)up;
    }
    wl_display_roundtrip(dpy); return 0;
}
