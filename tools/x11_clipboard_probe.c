#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>

static Atom atom(Display *dpy, const char *name) {
    return XInternAtom(dpy, name, False);
}

static void print_atom_name(Display *dpy, Atom atom) {
    char *name = XGetAtomName(dpy, atom);
    if (name) {
        puts(name);
        XFree(name);
    } else {
        printf("%lu\n", atom);
    }
}

static char *get_text_property(Display *dpy, Window win, Atom property) {
    Atom actual_type = None;
    int actual_format = 0;
    unsigned long nitems = 0;
    unsigned long bytes_after = 0;
    unsigned char *data = NULL;
    int rc = XGetWindowProperty(dpy, win, property, 0, 1024, False, AnyPropertyType,
                                &actual_type, &actual_format, &nitems, &bytes_after, &data);
    if (rc != Success || !data)
        return NULL;

    char *text = NULL;
    if (actual_format == 8 && nitems > 0)
        text = strndup((char *)data, nitems);
    XFree(data);
    return text;
}

static unsigned long get_cardinal_property(Display *dpy, Window win, Atom property) {
    Atom actual_type = None;
    int actual_format = 0;
    unsigned long nitems = 0;
    unsigned long bytes_after = 0;
    unsigned char *data = NULL;
    int rc = XGetWindowProperty(dpy, win, property, 0, 1, False, XA_CARDINAL,
                                &actual_type, &actual_format, &nitems, &bytes_after, &data);
    if (rc != Success || !data)
        return 0;

    unsigned long value = 0;
    if (actual_format == 32 && nitems > 0)
        value = *(unsigned long *)data;
    XFree(data);
    return value;
}

static void print_window_info(Display *dpy, Window win, int depth) {
    XWindowAttributes attrs;
    if (!XGetWindowAttributes(dpy, win, &attrs))
        return;

    Atom net_wm_pid = atom(dpy, "_NET_WM_PID");
    Atom net_wm_name = atom(dpy, "_NET_WM_NAME");
    unsigned long pid = get_cardinal_property(dpy, win, net_wm_pid);
    char *name = get_text_property(dpy, win, net_wm_name);
    if (!name)
        XFetchName(dpy, win, &name);

    XClassHint class_hint = {0};
    XGetClassHint(dpy, win, &class_hint);

    printf("%*s0x%lx map=%d pid=%lu class=%s instance=%s title=%s\n",
           depth * 2, "", win, attrs.map_state, pid,
           class_hint.res_class ? class_hint.res_class : "",
           class_hint.res_name ? class_hint.res_name : "",
           name ? name : "");

    if (class_hint.res_name)
        XFree(class_hint.res_name);
    if (class_hint.res_class)
        XFree(class_hint.res_class);
    if (name)
        XFree(name);
}

static void list_windows(Display *dpy, Window win, int depth) {
    Window root = 0, parent = 0, *children = NULL;
    unsigned int nchildren = 0;
    if (!XQueryTree(dpy, win, &root, &parent, &children, &nchildren))
        return;

    for (unsigned int i = 0; i < nchildren; i++) {
        print_window_info(dpy, children[i], depth);
        list_windows(dpy, children[i], depth + 1);
    }

    if (children)
        XFree(children);
}

static int print_owner(Display *dpy, Atom selection) {
    Window owner = XGetSelectionOwner(dpy, selection);
    printf("owner=0x%lx\n", owner);
    if (owner != None)
        print_window_info(dpy, owner, 0);
    return owner == None ? 1 : 0;
}

static int read_selection(Display *dpy, Window win, Atom selection, Atom target, int list_atoms) {
    Atom property = atom(dpy, "X11_CLIPBOARD_PROBE");
    XConvertSelection(dpy, selection, target, property, win, CurrentTime);
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
                if (list_atoms && actual_format == 32) {
                    Atom *atoms = (Atom *)data;
                    for (unsigned long i = 0; i < nitems; i++)
                        print_atom_name(dpy, atoms[i]);
                } else {
                    fwrite(data, 1, nitems * (actual_format / 8), stdout);
                }
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
        fprintf(stderr, "usage: %s read [target]|targets|owner|windows|own [text]\n", argv[0]);
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
        return read_selection(dpy, win, clipboard,
                              atom(dpy, argc >= 3 ? argv[2] : "UTF8_STRING"), 0);
    if (strcmp(argv[1], "targets") == 0)
        return read_selection(dpy, win, clipboard, atom(dpy, "TARGETS"), 1);
    if (strcmp(argv[1], "owner") == 0)
        return print_owner(dpy, clipboard);
    if (strcmp(argv[1], "windows") == 0) {
        list_windows(dpy, DefaultRootWindow(dpy), 0);
        return 0;
    }
    if (strcmp(argv[1], "own") == 0)
        return own_selection(dpy, win, clipboard, argc >= 3 ? argv[2] : "x11-probe");

    fprintf(stderr, "unknown mode: %s\n", argv[1]);
    return 64;
}
