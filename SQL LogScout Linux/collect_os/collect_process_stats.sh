#!/bin/bash


# include helper functions
source ./support/sqllogscout_support_functions.sh

#if inside container exit 0 
sqllogscout_inside_container_get_instance_status
if [ "${is_instance_inside_container_active}" == "YES" ]; then
    exit 0
fi

OS_COUNTERS_INTERVAL=$1
working_dir="$PWD"
mkdir -p $PWD/output
outputdir=$PWD/output
if [ "$EUID" -eq 0 ]; then
  ORIGINAL_USERNAME=$(logname 2>/dev/null) || ORIGINAL_USERNAME=""
  ORIGINAL_GROUP=$(id -gn "$ORIGINAL_USERNAME" 2>/dev/null) || ORIGINAL_GROUP=""
  chown "$ORIGINAL_USERNAME:$ORIGINAL_GROUP" "$outputdir" -R
else
	chown $(id -u):$(id -g) "$outputdir" -R
fi

# Use -H on newer sysstat (11.5+) so timestamps are always displayed in seconds since the epoch.
PIDSTAT_OPTS="-d -h -I -u -w -r"
if pidstat -H 1 1 >/dev/null 2>&1; then
    PIDSTAT_OPTS="-d -H -h -I -u -w -r"
fi

# Do not prepend 'date' before pidstat output (SQL Nexus LinuxPerfImporter expects the '# Time...'
# header at line index 2), and normalize the metric columns to the 16 columns expected by SQL Nexus
# across sysstat 10.x (RHEL 7), 11.2.x (Ubuntu 16.04), and 11.5+ (RHEL 8/9).
LC_TIME=en_US.UTF-8 pidstat $PIDSTAT_OPTS $OS_COUNTERS_INTERVAL > >(awk '
BEGIN {
    split("%usr %system %guest %CPU CPU minflt/s majflt/s VSZ RSS %MEM kB_rd/s kB_wr/s kB_ccwr/s iodelay cswch/s nvcswch/s", target_cols, " ")
}
/^#/ {
    delete col_map
    for (i = 5; i < NF; i++) {
        col_map[$i] = i - 1
    }
    print "#      Time   UID       PID    %usr %system  %guest    %CPU   CPU  minflt/s  majflt/s     VSZ     RSS   %MEM   kB_rd/s   kB_wr/s kB_ccwr/s iodelay   cswch/s nvcswch/s  Command"
    fflush()
    next
}
/^ *[0-9]/ {
    printf " %10s %5s %9s", $1, $2, $3
    for (m = 1; m <= 16; m++) {
        cname = target_cols[m]
        idx = col_map[cname]
        val = (idx > 0 && idx < NF) ? $idx : (cname == "iodelay" ? "0" : "0.00")
        printf " %7s", val
    }
    printf "  %s\n", $NF
    fflush()
    next
}
{
    print
    fflush()
}
' > "$outputdir/${HOSTNAME}_os_process_pidstat.perf") &
printf "%s\n" "$!" >> $outputdir/sqllogscout_stoppids_os_collectors.log

exit 0
