// A run's program output, measured. The known line is what the host greps for, so a run that reports
// the program's output and a run that loses it are told apart by the file, not by the verdict.
#import <Foundation/Foundation.h>
#import <unistd.h>

int main(int argc, char** argv) {
    fprintf(stdout, "charon-emulate-output: stdout reached the host\n");
    fflush(stdout);
    fprintf(stderr, "charon-emulate-output: stderr reached the host\n");
    fflush(stderr);
    // Asked to outlive the deadline: a program killed with SIGKILL flushes no buffer, so what it
    // printed before is what the host must still have.
    if (argc > 1 && strcmp(argv[1], "--hang") == 0) {
        fprintf(stdout, "charon-emulate-output: hanging past the deadline\n");
        fflush(stdout);
        for (;;) {
            sleep(1);
        }
    }
    return 0;
}
