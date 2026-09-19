#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <objc/runtime.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/time.h>
#include <sys/utsname.h>
#include <sys/wait.h>
#include <syslog.h>
#include <time.h>
#include <unistd.h>

extern char** environ;

static const char* verdict_directory = "/private/var/charon";

static double now(void)
{
    struct timeval value;
    gettimeofday(&value, NULL);
    return value.tv_sec + value.tv_usec / 1e6;
}

static void json_string(FILE* file, const char* text)
{
    fputc('"', file);
    for (const char* c = text ? text : ""; *c; ++c) {
        if (*c == '"' || *c == '\\')
            fputc('\\', file);
        if ((unsigned char)*c < 0x20)
            fprintf(file, "\\u%04x", *c);
        else
            fputc(*c, file);
    }
    fputc('"', file);
}

static void system_version(char* version, size_t size)
{
    snprintf(version, size, "unknown");
    CFURLRef url = CFURLCreateWithFileSystemPath(NULL, CFSTR("/System/Library/CoreServices/SystemVersion.plist"), kCFURLPOSIXPathStyle, false);
    CFReadStreamRef stream = CFReadStreamCreateWithFile(NULL, url);
    if (stream && CFReadStreamOpen(stream)) {
        CFPropertyListRef list = CFPropertyListCreateWithStream(NULL, stream, 0, kCFPropertyListImmutable, NULL, NULL);
        if (list && CFGetTypeID(list) == CFDictionaryGetTypeID()) {
            CFStringRef product = CFDictionaryGetValue(list, CFSTR("ProductVersion"));
            CFStringRef build = CFDictionaryGetValue(list, CFSTR("ProductBuildVersion"));
            char p[32] = "?", b[32] = "?";
            if (product)
                CFStringGetCString(product, p, sizeof p, kCFStringEncodingUTF8);
            if (build)
                CFStringGetCString(build, b, sizeof b, kCFStringEncodingUTF8);
            snprintf(version, size, "%s (%s)", p, b);
        }
        if (list)
            CFRelease(list);
        CFReadStreamClose(stream);
    }
    if (stream)
        CFRelease(stream);
    CFRelease(url);
}

// On iOS 6.1 and earlier the runner is started from launchd.conf, which gives
// it no output of its own and splits its line on whitespace with no quoting;
// so the runner keeps its own output next to its verdict, and takes its job -
// the deadline, the program and its arguments - as NUL-separated words from
// the file named after --job.
static void keep_own_output(void)
{
    int out = open("/private/var/charon/runner.stdout", O_WRONLY | O_CREAT | O_TRUNC, 0644);
    int err = open("/private/var/charon/runner.stderr", O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (out >= 0) {
        dup2(out, STDOUT_FILENO);
        close(out);
    }
    if (err >= 0) {
        dup2(err, STDERR_FILENO);
        close(err);
    }
}

static char** read_job(const char* file, char* self, int* count)
{
    static char words[65536];
    static char* job[256];
    FILE* stream = fopen(file, "rb");
    if (!stream)
        return NULL;
    size_t length = fread(words, 1, sizeof words - 1, stream);
    fclose(stream);
    words[length] = '\0';
    int found = 0;
    job[found++] = self;
    for (size_t at = 0; at < length && found < 255; at += strlen(words + at) + 1)
        job[found++] = words + at;
    job[found] = NULL;
    *count = found;
    return job;
}

int main(int argc, char** argv)
{
    keep_own_output();
    if (argc == 3 && strcmp(argv[1], "--job") == 0) {
        int count = 0;
        char** job = read_job(argv[2], argv[0], &count);
        if (!job) {
            printf("charon-runner: cannot read the job %s: %s\n", argv[2], strerror(errno));
            return 1;
        }
        argc = count;
        argv = job;
    }
    double started = now();
    printf("charon-runner: started pid=%d uid=%d\n", getpid(), getuid());
    fflush(stdout);
    openlog("charon-runner", LOG_PID, LOG_USER);
    syslog(LOG_NOTICE, "charon-runner started pid=%d", getpid());

    struct utsname name;
    uname(&name);
    char machine[64] = "";
    size_t length = sizeof machine;
    sysctlbyname("hw.machine", machine, &length, NULL, 0);
    char version[80];
    system_version(version, sizeof version);

    int uikit = dlopen("/System/Library/Frameworks/UIKit.framework/UIKit", RTLD_LAZY) != NULL;
    int ui_application = objc_getClass("UIApplication") != NULL;
    int deadline = argc > 1 ? atoi(argv[1]) : 30;
    int status = -1, spawned = 0, spawn_error = 0, timed_out = 0;
    double duration = 0;
    if (argc > 2) {
        fflush(stdout);
        fflush(stderr);
        int saved_out = dup(STDOUT_FILENO), saved_err = dup(STDERR_FILENO);
        int out = open("/private/var/charon/test.stdout", O_WRONLY | O_CREAT | O_TRUNC, 0644);
        int err = open("/private/var/charon/test.stderr", O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (out >= 0)
            dup2(out, STDOUT_FILENO);
        if (err >= 0)
            dup2(err, STDERR_FILENO);
        pid_t child;
        double spawned_at = now();
        spawn_error = posix_spawn(&child, argv[2], NULL, NULL, argv + 2, environ);
        dup2(saved_out, STDOUT_FILENO);
        dup2(saved_err, STDERR_FILENO);
        close(saved_out);
        close(saved_err);
        if (out >= 0)
            close(out);
        if (err >= 0)
            close(err);
        if (spawn_error == 0) {
            spawned = 1;
            for (;;) {
                pid_t done = waitpid(child, &status, WNOHANG);
                if (done == child)
                    break;
                if (now() - spawned_at > deadline) {
                    timed_out = 1;
                    kill(child, SIGKILL);
                    waitpid(child, &status, 0);
                    break;
                }
                usleep(100000);
            }
            duration = now() - spawned_at;
        }
    }

    mkdir(verdict_directory, 0755);
    char partial[256], final[256];
    snprintf(partial, sizeof partial, "%s/verdict.json.partial", verdict_directory);
    snprintf(final, sizeof final, "%s/verdict.json", verdict_directory);
    FILE* file = fopen(partial, "w");
    if (!file) {
        syslog(LOG_ERR, "charon-runner cannot write %s: %s", partial, strerror(errno));
        return 1;
    }
    fprintf(file, "{\"machine\":");
    json_string(file, machine);
    fprintf(file, ",\"kernel\":");
    json_string(file, name.version);
    fprintf(file, ",\"system\":");
    json_string(file, version);
    fprintf(file, ",\"uikit\":%d,\"UIApplication\":%d,\"runner_seconds\":%.3f", uikit, ui_application, now() - started);
    if (argc > 2) {
        fprintf(file, ",\"test\":{\"path\":");
        json_string(file, argv[2]);
        fprintf(file, ",\"spawned\":%d,\"spawn_error\":%d,\"timed_out\":%d,\"seconds\":%.3f", spawned, spawn_error, timed_out, duration);
        if (spawned && WIFEXITED(status))
            fprintf(file, ",\"exit\":%d", WEXITSTATUS(status));
        if (spawned && WIFSIGNALED(status))
            fprintf(file, ",\"signal\":%d", WTERMSIG(status));
        fprintf(file, "}");
    }
    fprintf(file, "}\n");
    fclose(file);
    rename(partial, final);
    printf("charon-runner: verdict written\n");
    syslog(LOG_NOTICE, "charon-runner verdict written");
    return 0;
}
