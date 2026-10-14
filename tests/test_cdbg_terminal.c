#define _GNU_SOURCE

#include "cwhip/RuntimeGc.h"

#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

const CwhipClassMeta cwhip_string_class_meta = {0};

void *cwhip_string_new(const CwhipClassMeta *metadata, const char *bytes, uint64_t length) {
    (void)metadata;
    char *text = (char *)calloc((size_t)length + 1, 1);
    assert(text != NULL);
    memcpy(text, bytes, (size_t)length);
    return text;
}

void *cwhip_buffer_new(int64_t length, const char *file, uint64_t file_length,
                       uint64_t line, uint64_t column) {
    (void)file;
    (void)file_length;
    (void)line;
    (void)column;
    CwhipBuffer *buffer = (CwhipBuffer *)calloc(1, sizeof(*buffer));
    assert(buffer != NULL);
    buffer->length = buffer->capacity = (uint64_t)length;
    buffer->data = (uint8_t *)calloc((size_t)length == 0 ? 1 : (size_t)length, 1);
    assert(buffer->data != NULL);
    return buffer;
}

extern void *cwhip_cdbg_terminal_open(void *self);
extern void *cwhip_cdbg_terminal_path(void *self, void *terminal);
extern void *cwhip_cdbg_terminal_read(void *self, void *terminal);
extern void cwhip_cdbg_terminal_close(void *self, void *terminal);
extern void *cwhip_cdbg_terminal_error(void *self, void *terminal);
extern void cwhip_cdbg_terminal_destroy(void *self, void *terminal);

static int64_t monotonic_milliseconds(void) {
    struct timespec now;
    assert(clock_gettime(CLOCK_MONOTONIC, &now) == 0);
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

static void release_buffer(CwhipBuffer *buffer) {
    free(buffer->data);
    free(buffer);
}

int main(void) {
    void *terminal = cwhip_cdbg_terminal_open(NULL);
    assert(terminal != NULL);
    assert(((char *)cwhip_cdbg_terminal_error(NULL, terminal))[0] == '\0');

    char *path = (char *)cwhip_cdbg_terminal_path(NULL, terminal);
    assert(path[0] != '\0');
    int slave = open(path, O_RDWR | O_NOCTTY | O_CLOEXEC);
    assert(slave >= 0);
    struct termios settings;
    assert(tcgetattr(slave, &settings) == 0);
    assert((settings.c_lflag & ECHO) == 0);
    assert((fcntl(slave, F_GETFD) & FD_CLOEXEC) != 0);

    CwhipBuffer *chunk = (CwhipBuffer *)cwhip_cdbg_terminal_read(NULL, terminal);
    assert(chunk->length == 0);
    release_buffer(chunk);

    pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        int output = open(path, O_WRONLY | O_NOCTTY);
        if (output < 0 || dup2(output, STDOUT_FILENO) < 0 ||
            dup2(output, STDERR_FILENO) < 0) _exit(10);
        if (output > STDERR_FILENO) close(output);
        static const char stdout_text[] = "inferior-stdout\n";
        static const char stdout_utf8[] = "\xc3\xa9";
        static const char stderr_text[] = "|inferior-stderr\n";
        if (write(STDOUT_FILENO, stdout_text, sizeof(stdout_text) - 1) !=
                (ssize_t)(sizeof(stdout_text) - 1) ||
            write(STDOUT_FILENO, stdout_utf8, sizeof(stdout_utf8) - 1) !=
                (ssize_t)(sizeof(stdout_utf8) - 1) ||
            write(STDERR_FILENO, stderr_text, sizeof(stderr_text) - 1) !=
                (ssize_t)(sizeof(stderr_text) - 1)) _exit(11);
        _exit(0);
    }

    close(slave);
    char output[64] = {0};
    size_t received = 0;
    const int64_t deadline = monotonic_milliseconds() + 2000;
    int child_status = 0;
    int child_reaped = 0;
    static const char expected[] = "inferior-stdout\n\xc3\xa9|inferior-stderr\n";
    while (received < sizeof(expected) - 1 ||
           !child_reaped) {
        chunk = (CwhipBuffer *)cwhip_cdbg_terminal_read(NULL, terminal);
        assert(chunk != NULL && chunk->length <= sizeof(output) - received - 1);
        if (chunk->length > 0) {
            memcpy(output + received, chunk->data, (size_t)chunk->length);
            received += (size_t)chunk->length;
        }
        release_buffer(chunk);

        if (!child_reaped) {
            pid_t waited = waitpid(child, &child_status, WNOHANG);
            assert(waited >= 0 || errno == EINTR);
            if (waited == child) child_reaped = 1;
        }
        if (received >= sizeof(expected) - 1 && child_reaped)
            break;
        assert(monotonic_milliseconds() < deadline);
        struct timespec pause = {.tv_sec = 0, .tv_nsec = 1000000};
        (void)nanosleep(&pause, NULL);
    }
    assert(WIFEXITED(child_status) && WEXITSTATUS(child_status) == 0);
    assert(received == sizeof(expected) - 1);
    assert(memcmp(output, expected, received) == 0);
    assert(((char *)cwhip_cdbg_terminal_error(NULL, terminal))[0] == '\0');

    cwhip_cdbg_terminal_close(NULL, terminal);
    cwhip_cdbg_terminal_close(NULL, terminal);
    chunk = (CwhipBuffer *)cwhip_cdbg_terminal_read(NULL, terminal);
    assert(chunk->length == 0);
    release_buffer(chunk);
    cwhip_cdbg_terminal_destroy(NULL, terminal);
    free(path);
    puts("cdbg PTY transport passed");
    return 0;
}
