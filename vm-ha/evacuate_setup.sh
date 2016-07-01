#!/bin/bash
SCRIPT_CONF_FILE="/etc/vm-ha/vm-ha.conf"
LOGDIR="/var/log/vm-ha"
LOGFILE="${LOGDIR}/vm-ha.log"
HOST_NAME=`hostname`
LOGTAG="SETUP_SCRIPT"
i=0

log_info () {
	if [ ! -e ${LOGDIR} ]; then
	        mkdir -p ${LOGDIR}
	fi
	log_output "$1"
}

log_output () {
	echo "`date +'%Y-%m-%d %H:%M:%S'` **  ${HOST_NAME} -- ${LOGTAG}: --  $1" >> $LOGFILE
}

set_conf_value () {
	while read line
	do
	  IFS=' ' read -r -a array <<< "$line"
	  if [ ${#array[@]} -ne 4 ]
	  then
	         if [ ${#array[@]} -eq 0 ]
	         then
	                continue
	         else
	                IFS='=' read -ra spil <<< "${array[0]}"
	                if [ ${spil[0]} = "OS_USERNAME" ] ; then
	                        username=${spil[1]}
	                elif [ ${spil[0]} = "OS_PASSWORD" ] ; then
	                        password=${spil[1]}
	                elif [ ${spil[0]} = "OS_TENANT_NAME" ] ; then
	                        tenant=${spil[1]}
	                elif [ ${spil[0]} = "OS_AUTH_URL" ] ; then
	                        auth_url=${spil[1]}
	                else
	                        continue
	                fi
	         fi
	  else
		if [ ${array[0]} = "#" ]; then
			continue
		else
			ipmi_host[$i]=${array[0]}
			ipmi_ip[$i]=${array[1]}
			ipmi_user[$i]=${array[2]}
			ipmi_pass[$i]=${array[3]}
			i=$((i+1))
		fi
	  fi
	done < $SCRIPT_CONF_FILE
        return 0
}

mid1=$1
mid2=$2
mid3=$3
######### add here
log_info "START - Adding location constraints for Nova LXC services"
log_info "pcs constraint location cl_ping prefers juju-machine-$mid1-lxc-3"
pcs constraint location cl_ping prefers juju-machine-"$mid1"-lxc-3
log_info "pcs constraint location cl_ping prefers juju-machine-$mid2-lxc-3"
pcs constraint location cl_ping prefers juju-machine-"$mid2"-lxc-3
log_info "pcs constraint location cl_ping prefers juju-machine-$mid3-lxc-3"
pcs constraint location cl_ping prefers juju-machine-"$mid3"-lxc-3
log_info "pcs constraint location res_nova_consoleauth prefers juju-machine-$mid1-lxc-3"
pcs constraint location res_nova_consoleauth prefers juju-machine-"$mid1"-lxc-3
log_info "pcs constraint location res_nova_consoleauth prefers juju-machine-$mid2-lxc-3"
pcs constraint location res_nova_consoleauth prefers juju-machine-"$mid2"-lxc-3
log_info "pcs constraint location res_nova_consoleauth prefers juju-machine-$mid3-lxc-3"
pcs constraint location res_nova_consoleauth prefers juju-machine-"$mid2"-lxc-3
log_info "pcs constraint location grp_nova_vips prefers juju-machine-$mid1-lxc-3"
pcs constraint location grp_nova_vips prefers juju-machine-"$mid1"-lxc-3
log_info "pcs constraint location grp_nova_vips prefers juju-machine-$mid2-lxc-3"
pcs constraint location grp_nova_vips prefers juju-machine-"$mid2"-lxc-3
log_info "pcs constraint location grp_nova_vips prefers juju-machine-$mid3-lxc-3"
pcs constraint location grp_nova_vips prefers juju-machine-"$mid3"-lxc-3
log_info "pcs constraint location cl_nova_haproxy prefers juju-machine-$mid1-lxc-3"
pcs constraint location cl_nova_haproxy prefers juju-machine-"$mid1"-lxc-3
log_info "pcs constraint location cl_nova_haproxy prefers juju-machine-$mid2-lxc-3"
pcs constraint location cl_nova_haproxy prefers juju-machine-"$mid2"-lxc-3
log_info "pcs constraint location cl_nova_haproxy prefers juju-machine-$mid3-lxc-3"
pcs constraint location cl_nova_haproxy prefers juju-machine-"$mid3"-lxc-3
log_info "END - Adding location constraints for Nova LXC services"

while true
do
	set_conf_value
	log_info "conf file imported"
	len=${#ipmi_host[@]}
	a=0
	while [ $a -lt $len ]; do
		log_info "Creating pacemaker remote resource for host: ${ipmi_host[$a]}"
		pcs resource create ${ipmi_host[$a]} ocf:pacemaker:remote op monitor interval=20
		log_info "pcs resource create ${ipmi_host[$a]} ocf:pacemaker:remote op monitor interval=20"
		log_info "Creating fence-ipmilan resource for host: ${ipmi_host[$a]}"
		pcs stonith create ipmilan-${ipmi_host[$a]} fence_ipmilan pcmk_host_list=${ipmi_host[$a]} ipaddr=${ipmi_ip[$a]} login=${ipmi_user[$a]} passwd=${ipmi_pass[$a]} lanplus=1 cipher=1 op monitor interval=60s
		log_info "pcs stonith create ipmilan-${ipmi_host[$a]} fence_ipmilan pcmk_host_list=${ipmi_host[$a]} ipaddr=${ipmi_ip[$a]} login=${ipmi_user[$a]} passwd=${ipmi_pass[$a]} lanplus=1 cipher=1 op monitor interval=60s"
		log_info "Adding location constraints for remote nodes"
		log_info "pcs constraint location cl_ping avoids ${ipmi_host[$a]}"
		pcs constraint location cl_ping avoids ${ipmi_host[$a]}
		log_info "pcs constraint location res_nova_consoleauth avoids ${ipmi_host[$a]}"
		pcs constraint location res_nova_consoleauth avoids ${ipmi_host[$a]}
		log_info "pcs constraint location grp_nova_vips avoids ${ipmi_host[$a]}"
		pcs constraint location grp_nova_vips avoids ${ipmi_host[$a]}
		log_info "pcs constraint location cl_nova_haproxy avoids ${ipmi_host[$a]}"
		pcs constraint location cl_nova_haproxy avoids ${ipmi_host[$a]}

		log_info "pcs constraint location ${ipmi_host[$a]} prefers juju-machine-$mid1-lxc-3"
		pcs constraint location ${ipmi_host[$a]} prefers juju-machine-"$mid1"-lxc-3
		log_info "pcs constraint location ${ipmi_host[$a]} prefers juju-machine-$mid2-lxc-3"
		pcs constraint location ${ipmi_host[$a]} prefers juju-machine-"$mid2"-lxc-3
		log_info "pcs constraint location ${ipmi_host[$a]} prefers juju-machine-$mid3-lxc-3"
		pcs constraint location ${ipmi_host[$a]} prefers juju-machine-"$mid3"-lxc-3

		log_info "pcs constraint location ipmilan-${ipmi_host[$a]} prefers juju-machine-$mid1-lxc-3"
		pcs constraint location ipmilan-${ipmi_host[$a]} prefers juju-machine-"$mid1"-lxc-3
		log_info "pcs constraint location ipmilan-${ipmi_host[$a]} prefers juju-machine-$mid2-lxc-3"
		pcs constraint location ipmilan-${ipmi_host[$a]} prefers juju-machine-"$mid2"-lxc-3
		log_info "pcs constraint location ipmilan-${ipmi_host[$a]} prefers juju-machine-$mid3-lxc-3"
		pcs constraint location ipmilan-${ipmi_host[$a]} prefers juju-machine-"$mid3"-lxc-3
		let a=a+1
		sleep 1
	done
	break
done

source $SCRIPT_CONF_FILE > /dev/null 2>&1
username=${OS_USERNAME}
password=${OS_PASSWORD}
tenant_name=${OS_TENANT_NAME}
auth_url=${OS_AUTH_URL}
region_name=${OS_REGION_NAME}
evac_host=${EVACUATION_TARGET}
evac_list1=( $evac_host )
evac_list=${#evac_list1[@]}

for i in "${evac_list1[@]}"
do
        nova --os-username ${username} --os-password ${password} --os-project-name ${tenant_name} --os-auth-url ${auth_url} --os-region-name ${region_name} service-disable --reason "reserved target node" $i nova-compute
done

