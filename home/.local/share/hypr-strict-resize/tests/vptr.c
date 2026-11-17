// usage: vptr W H cmd...   cmds: m X Y | d (press left) | u (release) | s MS (sleep)
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wayland-client.h>
#include "wlr-virtual-pointer-unstable-v1.h"
static struct zwlr_virtual_pointer_manager_v1* mgr; static struct wl_seat* seat;
static void g(void* d, struct wl_registry* r, uint32_t n, const char* i, uint32_t v) {
    if (!strcmp(i, zwlr_virtual_pointer_manager_v1_interface.name)) mgr = wl_registry_bind(r, n, &zwlr_virtual_pointer_manager_v1_interface, 1);
    else if (!strcmp(i, wl_seat_interface.name)) seat = wl_registry_bind(r, n, &wl_seat_interface, 1);
}
static void gr(void* d, struct wl_registry* r, uint32_t n) {}
static const struct wl_registry_listener L = {g, gr};
int main(int c, char** v) {
    struct wl_display* dpy = wl_display_connect(NULL); if (!dpy) return 1;
    struct wl_registry* reg = wl_display_get_registry(dpy); wl_registry_add_listener(reg, &L, NULL); wl_display_roundtrip(dpy);
    if (!mgr) { fprintf(stderr, "no virtual pointer manager\n"); return 2; }
    struct zwlr_virtual_pointer_v1* p = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(mgr, seat);
    int W = atoi(v[1]), H = atoi(v[2]); uint32_t t = 1000;
    for (int i = 3; i < c; i++) {
        if (!strcmp(v[i], "m")) { zwlr_virtual_pointer_v1_motion_absolute(p, t, atoi(v[i+1]), atoi(v[i+2]), W, H); i += 2; }
        else if (!strcmp(v[i], "d")) zwlr_virtual_pointer_v1_button(p, t, 0x110, 1);
        else if (!strcmp(v[i], "u")) zwlr_virtual_pointer_v1_button(p, t, 0x110, 0);
        else if (!strcmp(v[i], "D")) zwlr_virtual_pointer_v1_button(p, t, 0x111, 1);
        else if (!strcmp(v[i], "U")) zwlr_virtual_pointer_v1_button(p, t, 0x111, 0);
        else if (!strcmp(v[i], "w")) { int n = atoi(v[i+1]); i++;   /* wheel: n notches, + = down */
            zwlr_virtual_pointer_v1_axis_source(p, 0);
            zwlr_virtual_pointer_v1_axis_discrete(p, t, 0, wl_fixed_from_int(15 * n), n); }
        else if (!strcmp(v[i], "s")) { wl_display_roundtrip(dpy); usleep(atoi(v[i+1]) * 1000); i++; continue; }
        zwlr_virtual_pointer_v1_frame(p); t += 20; wl_display_roundtrip(dpy); usleep(30000);
    }
    wl_display_roundtrip(dpy); return 0;
}
