#define _POSIX_C_SOURCE 200809L

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

static volatile sig_atomic_t running = 1;

static void stop_guard(int signal_number) {
    (void)signal_number;
    running = 0;
}

static bool numeric_name(const char *name) {
    if (!*name)
        return false;
    for (; *name; ++name)
        if (!isdigit((unsigned char)*name))
            return false;
    return true;
}

static int count_uid_processes(uid_t wanted_uid) {
    DIR *proc = opendir("/proc");
    if (!proc)
        return -1;

    int count = 0;
    struct dirent *entry;
    while ((entry = readdir(proc))) {
        if (!numeric_name(entry->d_name))
            continue;

        char path[128];
        snprintf(path, sizeof(path), "/proc/%s/status", entry->d_name);
        FILE *status = fopen(path, "r");
        if (!status)
            continue;

        char line[256];
        bool zombie = false;
        while (fgets(line, sizeof(line), status)) {
            char state;
            if (sscanf(line, "State:\t%c", &state) == 1)
                zombie = state == 'Z';
            unsigned real_uid;
            if (sscanf(line, "Uid:\t%u", &real_uid) == 1) {
                if ((uid_t)real_uid == wanted_uid && !zombie)
                    ++count;
                break;
            }
        }
        fclose(status);
    }
    closedir(proc);
    return count;
}

static pid_t read_pid(const char *state_dir, const char *file_name) {
    char path[512];
    snprintf(path, sizeof(path), "%s/%s", state_dir, file_name);
    FILE *file = fopen(path, "r");
    if (!file)
        return -1;

    long value = -1;
    if (fscanf(file, "%ld", &value) != 1 || value <= 1)
        value = -1;
    fclose(file);
    return (pid_t)value;
}

static bool command_contains(pid_t pid, const char *marker) {
    char path[128];
    snprintf(path, sizeof(path), "/proc/%ld/cmdline", (long)pid);
    FILE *file = fopen(path, "r");
    if (!file)
        return false;

    char command[8192];
    size_t length = fread(command, 1, sizeof(command) - 1, file);
    fclose(file);
    for (size_t i = 0; i < length; ++i)
        if (command[i] == '\0')
            command[i] = ' ';
    command[length] = '\0';
    return strstr(command, marker) != NULL;
}

static void signal_target(const char *state_dir, const char *pid_file,
                          const char *marker, int signal_number) {
    pid_t pid = read_pid(state_dir, pid_file);
    if (pid <= 1 || !command_contains(pid, marker))
        return;

    if (getpgid(pid) == pid)
        kill(-pid, signal_number);
    else
        kill(pid, signal_number);
}

static void write_log(const char *log_path, int count, int limit) {
    FILE *log = fopen(log_path, "a");
    if (!log)
        return;

    time_t now = time(NULL);
    struct tm local;
    localtime_r(&now, &local);
    char stamp[64];
    strftime(stamp, sizeof(stamp), "%Y-%m-%d %H:%M:%S", &local);
    fprintf(log,
            "%s safety stop: %d Termux processes reached guard limit %d\n",
            stamp, count, limit);

    DIR *proc = opendir("/proc");
    if (proc) {
        struct dirent *entry;
        const uid_t wanted_uid = getuid();
        while ((entry = readdir(proc))) {
            if (!numeric_name(entry->d_name))
                continue;

            char status_path[128];
            snprintf(status_path, sizeof(status_path), "/proc/%s/status", entry->d_name);
            FILE *status = fopen(status_path, "r");
            if (!status)
                continue;

            bool owned = false;
            char line[256];
            while (fgets(line, sizeof(line), status)) {
                unsigned real_uid;
                if (sscanf(line, "Uid:\t%u", &real_uid) == 1) {
                    owned = (uid_t)real_uid == wanted_uid;
                    break;
                }
            }
            fclose(status);
            if (!owned)
                continue;

            char command_path[128];
            snprintf(command_path, sizeof(command_path), "/proc/%s/cmdline", entry->d_name);
            FILE *command_file = fopen(command_path, "r");
            if (!command_file)
                continue;
            char command[512];
            size_t length = fread(command, 1, sizeof(command) - 1, command_file);
            fclose(command_file);
            for (size_t i = 0; i < length; ++i)
                if (command[i] == '\0')
                    command[i] = ' ';
            command[length] = '\0';
            fprintf(log, "  pid=%s %s\n", entry->d_name, command);
        }
        closedir(proc);
    }
    fclose(log);
}

static void stop_omarchy(const char *state_dir, const char *container,
                         int signal_number) {
    signal_target(state_dir, "proot.pid", container, signal_number);
    signal_target(state_dir, "virgl.pid", ".virgl-omarchy", signal_number);
    signal_target(state_dir, "weston.pid", "wayland-omarchy", signal_number);
}

int main(int argc, char **argv) {
    if (argc != 6) {
        fprintf(stderr, "usage: %s UID LIMIT STATE_DIR LOG_FILE CONTAINER\n", argv[0]);
        return 2;
    }

    uid_t watched_uid = (uid_t)strtoul(argv[1], NULL, 10);
    int limit = atoi(argv[2]);
    const char *state_dir = argv[3];
    const char *log_path = argv[4];
    const char *container = argv[5];
    if (limit < 1)
        return 2;

    signal(SIGTERM, stop_guard);
    signal(SIGINT, stop_guard);
    signal(SIGHUP, stop_guard);

    const struct timespec interval = {.tv_sec = 0, .tv_nsec = 100000000L};
    while (running) {
        int count = count_uid_processes(watched_uid);
        if (count >= limit) {
            write_log(log_path, count, limit);
            stop_omarchy(state_dir, container, SIGTERM);
            struct timespec grace = {.tv_sec = 0, .tv_nsec = 500000000L};
            nanosleep(&grace, NULL);
            stop_omarchy(state_dir, container, SIGKILL);
            return 3;
        }
        nanosleep(&interval, NULL);
    }
    return 0;
}
