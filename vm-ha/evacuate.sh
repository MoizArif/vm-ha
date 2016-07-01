#!/bin/bash
###### Virtual Machine Evacuation script
SCRIPT_CONF_FILE="/etc/vm-ha/vm-ha.conf"
LOGDIR="/var/log/vm-ha"
LOGFILE="${LOGDIR}/vm-ha.log"
HOST_NAME=`hostname`
LOGTAG="evacuate script"
TMP_DIR="/var/tmp"
TMP_FILE="$TMP_DIR/evacuated_host.tmp"

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

# Function that reads configuration parameters from the SCRIPT_CONF_FILE
set_conf_value () {
        source $SCRIPT_CONF_FILE > /dev/null 2>&1
        compute_nodes=${COMPUTE_NODES}
        username=${OS_USERNAME}
        password=${OS_PASSWORD}
        tenant_name=${OS_TENANT_NAME}
        auth_url=${OS_AUTH_URL}
	region_name=${OS_REGION_NAME}
	evac_host=${EVACUATION_TARGET}
        return 0
}

# Function that initializes the TMP_FILE if it doesn't exsist already
tmp_dir () {
        if [ ! -e ${TMP_DIR} ]; then
                mkdir -p ${LOGDIR}
	else
		touch  $TMP_FILE
        fi
}

# Pre-start configurations
log_info "vm-ha service STARTED!!!"
evac_host_var=0 # Variable for iterating # of reserved nodes in the conf file. Used while calling nova evac APIs
set_conf_value
evac_list1=( $evac_host ) # Array containing list of target nodes (nodes where evacuated VMs goto)
evac_list=${#evac_list1[@]} # Length of the above array # of reserved nodes for evacuations

# Main While loop for the entire script
while true; do
	set_conf_value
	evac=0	# Evacuation variable. evacuate node (YES) = 0, evacuate node (NO) = 1
	tmp_dir
	IPMI_RAS=`crm configure show | grep "^primitive.*stonith:fence_ipmilan" | awk '{print $2}'`
	offline_remotes=`crm_mon -A -1 | grep '^RemoteOFFLINE' | sed -e 's/\s\{1,\}/ /g' | sed -e 's/ \]$//g' | cut -d" " -f3-`
	IPMI_REMOTES=( $offline_remotes )
#	log_info "offline remote: ${offline_remotes}"
	sleep 1
	text=`cat $TMP_FILE`
	a=0
	z=0
	# for loop for removing compute node names from TMP_FILE once they come back online after Fencing
	for i in $text	# text = contents of TMP_FILE --> list of compute nodes that have been fenced & evacuated
	do
	        name[$a]=$i
		online_remotes=`crm_mon -A -1 | grep '^RemoteOnline' | sed -e 's/\s\{1,\}/ /g' | sed -e 's/ \]$//g' | cut -d" " -f3-`
		IFS=', ' read -r -a array <<< "$online_remotes"
	        for element in "${array[@]}"
        	do
		    nodes[$z]=$element
	            if [ "${nodes[$z]}" == "${name[$a]}" ]
		    then
			log_info "Node ${name[$a]} is back online. removing it from evacuated nodes lists"
			sed -i /"${nodes[$z]}"/d $TMP_FILE
		    fi
		    let z=z+1
	        done
	        let a=a+1
	done

	g=0
	for f in $text
	do
		name2[$g]=$f
		let g=g+1
	done

	# If any remote node is detected as offline. Decides whether to evacuate or not (by setting evac variable)
	if [ "${offline_remotes}" != "" ]
        then
	    for offline_remotes1 in ${IPMI_REMOTES[@]}
	    do
		new_down=$offline_remotes1
	        for w in ${name2[*]} # Array name contains fenced compute nodes
		do
			#log_info "value of w from name: ${w}"
		        if [ $offline_remotes1 == $w ]
		        then
		                evac=1
				break
			else
				evac=0
				new_down=$offline_remotes1
		        fi
		done
		if [ $evac == 0 ]
		then
			break
		fi
	    done
	    unset name
	    unset name2

	    # This runs when we have detected a new offline remote node that has not been fenced before
	    if [ $evac != 1 ]
	    then
	            log_info "offline node is: ${offline_remotes}"
		    sleep 1
		    log_info "IPMI_REMOTE: ${IPMI_REMOTES[@]}"
		    # Loop that runs for the numbers of IPMI resource agents configured in the pcs cluster 
		    for IPMI_RA in ${IPMI_RAS}
		    do
			IPMI_HOST=`crm resource param ${IPMI_RA} show pcmk_host_list`
			# Loop that runs for the number of IPMI remote nodes detected by pacemaker
			for IPMI_REMOTE in ${IPMI_REMOTES[@]}
			do
			 # If the the down compute node matches its RA. Done in order to get IPMI credentials for fencing
			 if [ "$new_down" == "$IPMI_HOST" ]
			 then
				IPMI_REMOTE=$new_down
				sleep 1
				userid=`crm resource param ${IPMI_RA} show login`
				log_info "Initiating fencing ..."
				passwd=`crm resource param ${IPMI_RA} show passwd`
				ipaddr=`crm resource param ${IPMI_RA} show ipaddr`
				log_info "Powering off remote node: ${IPMI_RA}"
				ipmitool -I lanplus -H ${ipaddr} -U ${userid} -P ${passwd} chassis power off
				log_info "running ipmitool to fence"
				#log_info "Sleeping for 1 second"
				sleep 1
				# Loop that runs for as long as the nova compute service for the recently fenced node is not DOWN
				while true; do
					nova_compute_status=`nova --os-username ${username} --os-password ${password} --os-project-name ${tenant_name} --os-auth-url ${auth_url} --os-region-name ${region_name} service-list | grep $IPMI_REMOTE | sed -e 's/\s\{1,\}/ /g' | sed -e 's/ \]$//g' | cut -d " " -f 12`
					# when nova detect its compute node as down then start the evacuation process 
					if [ "${nova_compute_status}" == "down" ]
					then
						sleep 1
						log_info "Compute node status: ${nova_compute_status}"
						log_info "Calling nova evacuate API for host: ${IPMI_REMOTE}"
						# If no target host has been configured in the SCRIPT_CONF_FILE file then we leverage nova-scheduler for scheduling the evacuated VMs
						if [ $evac_list == 0 ]
						then
						        log_info "Using N-to-N evacuation model"
						        log_info "Run evacuation command here without setting any target host"
						        sleep 10
							nova --os-username ${username} --os-password ${password} --os-project-name ${tenant_name} --os-auth-url ${auth_url} --os-region-name ${region_name} host-evacuate $IPMI_REMOTE --on-shared-storage
						fi

						# If only one target node is configured in the SCRIPT_CONF_FILE. then we use N+1 model for evacuations
						# Note: This will run only ONCE. When the single target node has been used for evacuation. The model Shifts to N-to-N
						if [ $evac_list == 1 ]
						then
						        log_info "Using N+1 evacuation model with host: ${evac_list1[$evac_host_var]}"
						        log_info "Run evacuation here with target ${evac_list1[$evac_host_var]}"
							nova --os-username ${username} --os-password ${password} --os-project-name ${tenant_name} --os-auth-url ${auth_url} --os-region-name ${region_name} host-evacuate $IPMI_REMOTE --target ${evac_list1[$evac_host_var]} --on-shared-storage
							nova --os-username ${username} --os-password ${password} --os-project-name ${tenant_name} --os-auth-url ${auth_url} --os-region-name ${region_name} service-enable ${evac_list1[$evac_host_var]} nova-compute
							let evac_host_var=evac_host_var+1
							# if only single node has been used tell the script to move to N-to-N model from now on because no target nodes are left now
							if [ $evac_list == $evac_host_var  ]
                                                        then
                                                                evac_list=0
                                                        fi
						fi

						# If more than 1 target nodes have been configured then we use N+M model
						# Note: this wil only run for the number of configured target nodes (M times). Then it will shift to N-to-N model
						if [ $evac_list -gt 1 ]
						then
						        log_info "Using N+M evacuation mode with hosts: ${evac_list1[$evac_host_var]}"
						        log_info "Implementing logic to choose which compute node as target"
							nova --os-username ${username} --os-password ${password} --os-project-name ${tenant_name} --os-auth-url ${auth_url} --os-region-name ${region_name} host-evacuate $IPMI_REMOTE --target ${evac_list1[$evac_host_var]} --on-shared-storage
							nova --os-username ${username} --os-password ${password} --os-project-name ${tenant_name} --os-auth-url ${auth_url} --os-region-name ${region_name} service-enable ${evac_list1[$evac_host_var]} nova-compute
							let evac_host_var=evac_host_var+1
							# If M nodes have been used then tell the script to move to N-to-N model from now on
							if [ $evac_list == $evac_host_var  ]
							then
								evac_list=0
							fi
						fi
						echo "${IPMI_REMOTE}" >> $TMP_FILE
						break
					else
						sleep 1
						log_info "Nova Compute service is still active on the node: ${IPMI_REMOTE}"
					fi
				done
				break
			 fi
			break
			done
		    done
	    fi
	fi
done
