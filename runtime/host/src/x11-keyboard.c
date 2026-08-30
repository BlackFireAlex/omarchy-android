#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <X11/XKBlib.h>
#include <X11/Xlib.h>

static void usage(const char *name) {
    fprintf(stderr, "usage: %s query | off | on [delay-ms interval-ms]\n", name);
}

int main(int argc, char **argv) {
    Display *display;
    unsigned int delay = 0;
    unsigned int interval = 0;

    if (argc < 2) {
        usage(argv[0]);
        return 2;
    }

    display = XOpenDisplay(NULL);
    if (!display) {
        fprintf(stderr, "cannot open X display\n");
        return 1;
    }

    if (strcmp(argv[1], "query") == 0) {
        if (!XkbGetAutoRepeatRate(display, XkbUseCoreKbd, &delay, &interval)) {
            fprintf(stderr, "server does not expose an XKB repeat rate\n");
            XCloseDisplay(display);
            return 1;
        }
        printf("delay=%u interval=%u\n", delay, interval);
    } else if (strcmp(argv[1], "off") == 0) {
        XAutoRepeatOff(display);
        XSync(display, False);
        puts("repeat=off");
    } else if (strcmp(argv[1], "on") == 0) {
        delay = argc > 2 ? (unsigned int)strtoul(argv[2], NULL, 10) : 650;
        interval = argc > 3 ? (unsigned int)strtoul(argv[3], NULL, 10) : 55;
        if (delay < 100 || interval < 10) {
            fprintf(stderr, "refusing an unsafe repeat rate\n");
            XCloseDisplay(display);
            return 2;
        }
        if (!XkbSetAutoRepeatRate(display, XkbUseCoreKbd, delay, interval)) {
            fprintf(stderr, "failed to set XKB repeat rate\n");
            XCloseDisplay(display);
            return 1;
        }
        XAutoRepeatOn(display);
        XSync(display, False);
        printf("repeat=on delay=%u interval=%u\n", delay, interval);
    } else {
        usage(argv[0]);
        XCloseDisplay(display);
        return 2;
    }

    XCloseDisplay(display);
    return 0;
}
