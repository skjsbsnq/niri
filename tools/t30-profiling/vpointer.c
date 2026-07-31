/*
 * vpointer.c — zwlr_virtual_pointer_v1 driver for T-30 profiling scenarios.
 *
 * Drives the compositor's virtual pointer protocol (implemented by the niri
 * fork, niri/src/protocols/virtual_pointer.rs) so profiling runs are
 * reproducible without physical input. Connects to the Wayland display named
 * by WAYLAND_DISPLAY and emits the requested motion sequences.
 *
 * Commands are read from stdin, one per line (tokens split on whitespace):
 *   m <dx> <dy>          relative motion (compositor logical px, may be float)
 *   a <x> <y> [w] [h]    absolute motion (defaults extent 2048x1280)
 *   b <button> <state>   button event (state 1=press 0=release)
 *   circle <cx> <cy> <r> <steps> <total_ms>
 *                        relative-motion circle; per-step frame events
 *   line <x0> <y0> <x1> <y1> <steps> <total_ms>
 *                        relative-motion line sweep; per-step frame events
 *   sleep <ms>           pause (no events)
 *   quit                 exit
 *
 * Example: printf 'line 200 1200 1800 1200 130 10000\n' | ./vpointer
 */
#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#include <wayland-client.h>

#include "wlr-virtual-pointer-unstable-v1-client.h"

static struct wl_display *display;
static struct wl_registry *registry;
static struct wl_seat *seat;
static struct zwlr_virtual_pointer_manager_v1 *manager;
static struct zwlr_virtual_pointer_v1 *vpointer;

static uint32_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32_t)(ts.tv_sec * 1000u + ts.tv_nsec / 1000000u);
}

static void registry_handle_global(void *data, struct wl_registry *reg, uint32_t name,
                                   const char *interface, uint32_t version) {
    (void)data;
    if (strcmp(interface, wl_seat_interface.name) == 0 && seat == NULL) {
        seat = wl_registry_bind(reg, name, &wl_seat_interface, 1);
    } else if (strcmp(interface, zwlr_virtual_pointer_manager_v1_interface.name) == 0) {
        manager = wl_registry_bind(reg, name, &zwlr_virtual_pointer_manager_v1_interface,
                                   version < 2 ? version : 2);
    }
}

static void registry_handle_global_remove(void *data, struct wl_registry *reg, uint32_t name) {
    (void)data;
    (void)reg;
    (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_handle_global,
    .global_remove = registry_handle_global_remove,
};

static void die(const char *msg) {
    fprintf(stderr, "vpointer: %s\n", msg);
    exit(1);
}

static double parse_double(const char *s, const char *what) {
    char *end = NULL;
    errno = 0;
    double v = strtod(s, &end);
    if (errno != 0 || end == s || *end != '\0') die(what);
    return v;
}

static long parse_long(const char *s, const char *what) {
    char *end = NULL;
    errno = 0;
    long v = strtol(s, &end, 10);
    if (errno != 0 || end == s || *end != '\0') die(what);
    return v;
}

static void do_motion(double dx, double dy) {
    zwlr_virtual_pointer_v1_motion(vpointer, now_ms(), wl_fixed_from_double(dx),
                                   wl_fixed_from_double(dy));
    zwlr_virtual_pointer_v1_frame(vpointer);
    wl_display_flush(display);
}

static void do_absolute(double x, double y, uint32_t ex, uint32_t ey) {
    zwlr_virtual_pointer_v1_motion_absolute(vpointer, now_ms(), (uint32_t)x, (uint32_t)y, ex, ey);
    zwlr_virtual_pointer_v1_frame(vpointer);
    wl_display_flush(display);
}

static void do_button(uint32_t button, uint32_t state) {
    zwlr_virtual_pointer_v1_button(vpointer, now_ms(), button, state);
    zwlr_virtual_pointer_v1_frame(vpointer);
    wl_display_flush(display);
}

static void sleep_ms(long ms) {
    struct timespec ts = { .tv_sec = ms / 1000, .tv_nsec = (ms % 1000) * 1000000L };
    while (nanosleep(&ts, &ts) != 0 && errno == EINTR) {
    }
}

int main(void) {
    display = wl_display_connect(NULL);
    if (display == NULL) die("cannot connect to WAYLAND_DISPLAY");

    registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);

    if (manager == NULL) die("compositor does not advertise zwlr_virtual_pointer_manager_v1");
    if (seat == NULL) die("compositor does not advertise wl_seat");

    vpointer = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(manager, seat);
    wl_display_roundtrip(display);
    if (vpointer == NULL) die("failed to create virtual pointer");

    fprintf(stderr, "vpointer: ready (seat=%p)\n", (void *)seat);

    char *line = NULL;
    size_t cap = 0;
    while (getline(&line, &cap, stdin) != -1) {
        char *save = NULL;
        char *tok = strtok_r(line, " \t\r\n", &save);
        if (tok == NULL || *tok == '#') continue;

        if (strcmp(tok, "quit") == 0) break;
        if (strcmp(tok, "sleep") == 0) {
            char *ms = strtok_r(NULL, " \t\r\n", &save);
            if (ms == NULL) die("sleep needs ms");
            sleep_ms(parse_long(ms, "sleep ms"));
        } else if (strcmp(tok, "m") == 0) {
            char *dx = strtok_r(NULL, " \t\r\n", &save);
            char *dy = strtok_r(NULL, " \t\r\n", &save);
            if (dx == NULL || dy == NULL) die("m needs dx dy");
            do_motion(parse_double(dx, "dx"), parse_double(dy, "dy"));
        } else if (strcmp(tok, "a") == 0) {
            char *x = strtok_r(NULL, " \t\r\n", &save);
            char *y = strtok_r(NULL, " \t\r\n", &save);
            char *ex = strtok_r(NULL, " \t\r\n", &save);
            char *ey = strtok_r(NULL, " \t\r\n", &save);
            if (x == NULL || y == NULL) die("a needs x y [w h]");
            do_absolute(parse_double(x, "x"), parse_double(y, "y"),
                        ex ? (uint32_t)parse_long(ex, "extent") : 2048u,
                        ey ? (uint32_t)parse_long(ey, "extent") : 1280u);
        } else if (strcmp(tok, "b") == 0) {
            char *btn = strtok_r(NULL, " \t\r\n", &save);
            char *st = strtok_r(NULL, " \t\r\n", &save);
            if (btn == NULL || st == NULL) die("b needs button state");
            do_button((uint32_t)parse_long(btn, "button"), (uint32_t)parse_long(st, "state"));
        } else if (strcmp(tok, "circle") == 0) {
            char *cx = strtok_r(NULL, " \t\r\n", &save);
            char *cy = strtok_r(NULL, " \t\r\n", &save);
            char *r = strtok_r(NULL, " \t\r\n", &save);
            char *steps = strtok_r(NULL, " \t\r\n", &save);
            char *total = strtok_r(NULL, " \t\r\n", &save);
            if (cx == NULL || cy == NULL || r == NULL || steps == NULL || total == NULL)
                die("circle needs cx cy r steps total_ms");
            double cxv = parse_double(cx, "cx"), cyv = parse_double(cy, "cy");
            double rv = parse_double(r, "r");
            long n = parse_long(steps, "steps"), ms = parse_long(total, "total_ms");
            long step_delay = ms / (n > 0 ? n : 1);
            for (long i = 0; i < n; i++) {
                double ang = 2.0 * M_PI * (double)i / (double)n;
                double dx = (cos(ang + 2.0 * M_PI / n) - cos(ang)) * rv;
                double dy = (sin(ang + 2.0 * M_PI / n) - sin(ang)) * rv;
                (void)cxv;
                (void)cyv;
                do_motion(dx, dy);
                sleep_ms(step_delay);
            }
        } else if (strcmp(tok, "line") == 0) {
            char *x0 = strtok_r(NULL, " \t\r\n", &save);
            char *y0 = strtok_r(NULL, " \t\r\n", &save);
            char *x1 = strtok_r(NULL, " \t\r\n", &save);
            char *y1 = strtok_r(NULL, " \t\r\n", &save);
            char *steps = strtok_r(NULL, " \t\r\n", &save);
            char *total = strtok_r(NULL, " \t\r\n", &save);
            if (x0 == NULL || y0 == NULL || x1 == NULL || y1 == NULL || steps == NULL ||
                total == NULL)
                die("line needs x0 y0 x1 y1 steps total_ms");
            double x0v = parse_double(x0, "x0"), y0v = parse_double(y0, "y0");
            double x1v = parse_double(x1, "x1"), y1v = parse_double(y1, "y1");
            long n = parse_long(steps, "steps"), ms = parse_long(total, "total_ms");
            long step_delay = ms / (n > 0 ? n : 1);
            for (long i = 0; i < n; i++) {
                double t0 = (double)i / (double)n, t1 = (double)(i + 1) / (double)n;
                do_motion((x1v - x0v) * (t1 - t0), (y1v - y0v) * (t1 - t0));
                sleep_ms(step_delay);
            }
        } else {
            fprintf(stderr, "vpointer: unknown command '%s'\n", tok);
        }
    }

    free(line);
    zwlr_virtual_pointer_v1_destroy(vpointer);
    zwlr_virtual_pointer_manager_v1_destroy(manager);
    wl_seat_destroy(seat);
    wl_display_disconnect(display);
    return 0;
}
