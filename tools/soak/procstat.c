// One read of one process for the soak sampler: footprint, CPU, threads and open fds, as one JSON line.
//   procstat <pid>    exits 1 when the pid is gone or cannot be read
// It reads with proc_pid_rusage and proc_pidinfo only. It never signals the process.
#include <libproc.h>
#include <mach/mach_time.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/proc_info.h>
#include <sys/resource.h>

int main(int argc, char **argv) {
    if (argc != 2) { fprintf(stderr, "usage: procstat <pid>\n"); return 2; }
    int pid = atoi(argv[1]);
    if (pid <= 1) { fprintf(stderr, "procstat: no such pid\n"); return 2; }
    struct rusage_info_v4 ri;
    if (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&ri) != 0) return 1;
    struct proc_taskinfo ti;
    if (proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, sizeof ti) != (int)sizeof ti) return 1;
    int bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
    if (bytes <= 0) return 1;
    struct proc_fdinfo *fds = malloc((size_t)bytes);
    bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fds, bytes);
    free(fds);
    if (bytes <= 0) return 1;
    mach_timebase_info_data_t tb;
    mach_timebase_info(&tb);
    double ns = (double)(ri.ri_user_time + ri.ri_system_time) * tb.numer / tb.denom;
    printf("{\"pid\": %d, \"footprintBytes\": %llu, \"peakFootprintBytes\": %llu, \"residentBytes\": %llu, "
           "\"cpuNs\": %.0f, \"threads\": %d, \"fds\": %d}\n",
           pid, (unsigned long long)ri.ri_phys_footprint, (unsigned long long)ri.ri_lifetime_max_phys_footprint,
           (unsigned long long)ri.ri_resident_size, ns, ti.pti_threadnum, bytes / (int)sizeof(struct proc_fdinfo));
    return 0;
}
