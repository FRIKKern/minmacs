// Do .ips crash reports name the dispatch queue? A command-line tool, so a crash shows no dialog.
// It parks one block on a second labeled queue, then traps inside a block on the first one.
// ReportCrash writes the report to ~/Library/Logs/DiagnosticReports/mm-ips-probe-*.ips.
// Build: clang -O0 -Wall crash.c -o mm-ips-probe     Run: ./mm-ips-probe; then read.py
#include <dispatch/dispatch.h>
#include <stdio.h>
#include <unistd.h>

int main(void) {
    dispatch_queue_t idle = dispatch_queue_create("no.guerrilla.minmacs.settle.idle", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_t work = dispatch_queue_create("no.guerrilla.minmacs.settle.crash", DISPATCH_QUEUE_SERIAL);
    dispatch_async(idle, ^{ sleep(30); });
    usleep(200000);   // let the idle block start on its own thread
    dispatch_sync(work, ^{
        fprintf(stderr, "trapping on %s\n", dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL));
        __builtin_trap();
    });
    return 0;
}
