#define _GNU_SOURCE

#include "cwhip/RuntimeGc.h"

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>
#include "values.h"

extern const CwhipClassMeta cwhip_string_class_meta __attribute__((weak));

enum { READ_LIMIT = 64 * 1024 };

typedef struct CwhipDebugTerminal {
    int master_fd;
    int slave_fd;
    int closed;
    char *path;
    char error[512];
} CwhipDebugTerminal;

static void set_error(CwhipDebugTerminal *terminal, const char *operation, int error_number) {
    if (terminal == NULL || terminal->error[0] != '\0') return;
    (void)snprintf(terminal->error, sizeof(terminal->error), "%s: %s", operation,
                   strerror(error_number));
}

static void close_descriptor(CwhipDebugTerminal *terminal, int *descriptor) {
    if (*descriptor < 0) return;
    int fd = *descriptor;
    *descriptor = -1;
    if (close(fd) != 0) set_error(terminal, "close PTY descriptor", errno);
}

static void *make_string(const char *text) {
    if (&cwhip_string_class_meta == NULL) return NULL;
    return cwhip_string_new(&cwhip_string_class_meta, text, (uint64_t)strlen(text));
}

void *cwhip_cdbg_values_script(void *self) {
    (void)self;
    return make_string(cdbg_values_script);
}

static void *make_buffer(const unsigned char *bytes, size_t length) {
    CwhipBuffer *buffer = (CwhipBuffer *)cwhip_buffer_new(
        (int64_t)length, __FILE__, sizeof(__FILE__) - 1, 0, 0);
    if (length > 0) memcpy(buffer->data, bytes, length);
    return buffer;
}

void *cwhip_cdbg_terminal_open(void *self) {
    (void)self;
    CwhipDebugTerminal *terminal = (CwhipDebugTerminal *)calloc(1, sizeof(*terminal));
    if (terminal == NULL) return NULL;
    terminal->master_fd = -1;
    terminal->slave_fd = -1;

    terminal->master_fd = posix_openpt(O_RDWR | O_NOCTTY | O_NONBLOCK | O_CLOEXEC);
    if (terminal->master_fd < 0) {
        set_error(terminal, "open PTY master", errno);
        return terminal;
    }
    if (grantpt(terminal->master_fd) != 0 || unlockpt(terminal->master_fd) != 0) {
        set_error(terminal, "prepare PTY master", errno);
        close_descriptor(terminal, &terminal->master_fd);
        return terminal;
    }

    char path[256];
    int status = ptsname_r(terminal->master_fd, path, sizeof(path));
    if (status != 0) {
        set_error(terminal, "get PTY slave path", status);
        close_descriptor(terminal, &terminal->master_fd);
        return terminal;
    }
    terminal->path = strdup(path);
    if (terminal->path == NULL) {
        set_error(terminal, "allocate PTY slave path", ENOMEM);
        close_descriptor(terminal, &terminal->master_fd);
        return terminal;
    }

    terminal->slave_fd = open(terminal->path, O_RDWR | O_NOCTTY | O_CLOEXEC);
    if (terminal->slave_fd < 0) {
        set_error(terminal, "open PTY slave", errno);
        close_descriptor(terminal, &terminal->master_fd);
        return terminal;
    }
    struct termios settings;
    if (tcgetattr(terminal->slave_fd, &settings) != 0) {
        set_error(terminal, "read PTY settings", errno);
        close_descriptor(terminal, &terminal->slave_fd);
        close_descriptor(terminal, &terminal->master_fd);
        return terminal;
    }
    settings.c_lflag &= (tcflag_t)~(ECHO | ECHONL);
    settings.c_oflag &= (tcflag_t)~(OPOST | ONLCR);
    if (tcsetattr(terminal->slave_fd, TCSANOW, &settings) != 0) {
        set_error(terminal, "disable PTY echo", errno);
        close_descriptor(terminal, &terminal->slave_fd);
        close_descriptor(terminal, &terminal->master_fd);
    }
    return terminal;
}

void *cwhip_cdbg_terminal_path(void *self, void *opaque) {
    (void)self;
    CwhipDebugTerminal *terminal = (CwhipDebugTerminal *)opaque;
    if (terminal == NULL || terminal->path == NULL) return make_string("");
    return make_string(terminal->path);
}

void *cwhip_cdbg_terminal_read(void *self, void *opaque) {
    (void)self;
    CwhipDebugTerminal *terminal = (CwhipDebugTerminal *)opaque;
    if (terminal == NULL || terminal->closed || terminal->master_fd < 0)
        return make_buffer(NULL, 0);

    unsigned char bytes[READ_LIMIT];
    ssize_t count;
    do {
        count = read(terminal->master_fd, bytes, sizeof(bytes));
    } while (count < 0 && errno == EINTR);

    if (count > 0) return make_buffer(bytes, (size_t)count);
    if (count == 0 || errno == EAGAIN || errno == EWOULDBLOCK || errno == EIO)
        return make_buffer(NULL, 0);
    set_error(terminal, "read PTY output", errno);
    return make_buffer(NULL, 0);
}

void cwhip_cdbg_terminal_close(void *self, void *opaque) {
    (void)self;
    CwhipDebugTerminal *terminal = (CwhipDebugTerminal *)opaque;
    if (terminal == NULL || terminal->closed) return;
    terminal->closed = 1;
    close_descriptor(terminal, &terminal->master_fd);
    close_descriptor(terminal, &terminal->slave_fd);
}

void *cwhip_cdbg_terminal_error(void *self, void *opaque) {
    (void)self;
    CwhipDebugTerminal *terminal = (CwhipDebugTerminal *)opaque;
    if (terminal == NULL) return make_string("unable to allocate PTY transport");
    return make_string(terminal->error);
}

void cwhip_cdbg_terminal_destroy(void *self, void *opaque) {
    (void)self;
    CwhipDebugTerminal *terminal = (CwhipDebugTerminal *)opaque;
    if (terminal == NULL) return;
    cwhip_cdbg_terminal_close(NULL, terminal);
    free(terminal->path);
    free(terminal);
}
