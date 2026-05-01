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

LC_TIME=en_US.UTF-8 sar -n DEV $OS_COUNTERS_INTERVAL >> $outputdir/${HOSTNAME}_os_network_stats.perf &
printf "%s\n" "$!" >> $outputdir/sqllogscout_stoppids_os_collectors.log

exit 0



