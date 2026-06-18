#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <X11/Xatom.h>
#include <X11/Xlib.h>

static Atom atom(Display *dpy, const char *name) {
    return XInternAtom(dpy, name, False);
}

static int read_selection(Display *dpy, Window win, Atom selection) {
    Atom utf8 = atom(dpy, "UTF8_STRING");
    Atom property = atom(dpy, "X11_CLIPBOARD_PROBE");
    XConvertSelection(dpy, selection, utf8, property, win, CurrentTime);
    XFlush(dpy);

    time_t deadline = time(NULL) + 3;
    for (;;) {
        while (XPending(dpy)) {
            XEvent ev;
            XNextEvent(dpy, &ev);
            if (ev.type != SelectionNotify)
                continue;
            if (ev.xselection.property == None)
                return 2;

            Atom actual_type = None;
            int actual_format = 0;
            unsigned long nitems = 0;
            unsigned long bytes_after = 0;
            unsigned char *data = NULL;
            int rc = XGetWindowProperty(
                dpy, win, property, 0, 1024 * 1024, False, AnyPropertyType,
                &actual_type, &actual_format, &nitems, &bytes_after, &data);
            if (rc != Success)
                return 3;
            if (data) {
                fwrite(data, 1, nitems * (actual_format / 8), stdout);
                XFree(data);
            }
            return 0;
        }
        if (time(NULL) >= deadline)
            return 4;
        usleep(10000);
    }
}

static int own_selection(Display *dpy, Window win, Atom selection, const char *text) {
    Atom targets = atom(dpy, "TARGETS");
    Atom utf8 = atom(dpy, "UTF8_STRING");
    Atom text_atom = atom(dpy, "TEXT");
    Atom string_atom = XA_STRING;

    XSetSelectionOwner(dpy, selection, win, CurrentTime);
    XFlush(dpy);
    if (XGetSelectionOwner(dpy, selection) != win)
        return 2;

    time_t deadline = time(NULL) + 10;
    for (;;) {
        while (XPending(dpy)) {
            XEvent ev;
            XNextEvent(dpy, &ev);
            if (ev.type != SelectionRequest)
                continue;

            XSelectionRequestEvent *req = &ev.xselectionrequest;
            XSelectionEvent reply = {0};
            reply.type = SelectionNotify;
            reply.display = req->display;
            reply.requestor = req->requestor;
            reply.selection = req->selection;
            reply.target = req->target;
            reply.time = req->time;
            reply.property = req->property;

            if (req->property == None) {
                reply.property = None;
            } else if (req->target == targets) {
                Atom values[] = { targets, utf8, text_atom, string_atom };
                XChangeProperty(dpy, req->requestor, req->property, XA_ATOM, 32,
                                PropModeReplace, (unsigned char *)values,
                                sizeof(values) / sizeof(values[0]));
            } else if (req->target == utf8 || req->target == text_atom || req->target == string_atom) {
                Atom type = req->target == string_atom ? string_atom : utf8;
                XChangeProperty(dpy, req->requestor, req->property, type, 8,
                                PropModeReplace, (const unsigned char *)text,
                                strlen(text));
            } else {
                reply.property = None;
            }

            XSendEvent(dpy, req->requestor, False, 0, (XEvent *)&reply);
            XFlush(dpy);
        }
        if (time(NULL) >= deadline)
            return 0;
        usleep(10000);
    }
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s read|own [text]\n", argv[0]);
        return 64;
    }

    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) {
        fprintf(stderr, "cannot open X display\n");
        return 69;
    }

    Window win = XCreateSimpleWindow(dpy, DefaultRootWindow(dpy), 0, 0, 1, 1, 0, 0, 0);
    Atom clipboard = atom(dpy, "CLIPBOARD");

    if (strcmp(argv[1], "read") == 0)
        return read_selection(dpy, win, clipboard);
    if (strcmp(argv[1], "own") == 0)
        return own_selection(dpy, win, clipboard, argc >= 3 ? argv[2] : "x11-probe");

    fprintf(stderr, "unknown mode: %s\n", argv[1]);
    return 64;
}
