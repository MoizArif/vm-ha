#!/bin/bash
LOGDIR="/var/log/vm-ha"
LOGFILE="${LOGDIR}/vm-ha.log"
HOST_NAME=`hostname`
LOGTAG="cleanup script"

# Function for printing logs into the LOGFILE
log_info () {
        if [ ! -e ${LOGDIR} ]; then
                mkdir -p ${LOGDIR}
        fi
        log_output "$1"
}

# Function for appending date time ** lxc name -- script name -- before log_info
log_output () {
        echo "`date +'%Y-%m-%d %H:%M:%S'` **  ${HOST_NAME} -- ${LOGTAG}: --  $1" >> $LOGFILE
}

log_info "Cleanup script started !!"
pcs resource cleanup $1
log_info "Pacemaker Resource cleanup up for remote node: $1 "
log_info "Cleanup script stopped !!"
