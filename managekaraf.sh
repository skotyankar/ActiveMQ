#!/bin/bash
#version_managekaraf=1.0.0

#This script will try to gracefully stop the karaf container
#and the wrapper so that we don't get into unstable situations


#Setup environment for java and smx
export JAVA_HOME=/mqseries/java/active
export SMX_HOME=/mqseries/smx/active
export PATH=$PATH:$JAVA_HOME/bin:$SMX_HOME/bin


#Script specfic variables
ent_store_register_completion=/tmp/ent_store_register_completion
logdir=/u/users/mqm/logs/
logfile=managekaraf.log
loglimit=2000000
backupdir=/u/spool/30
valid=mqm
uid=`id -nu`
input=$@
ent_store_register_cmd=/mqseries/tools/active/bin/ent_store_register.sh
amq_configure_cmd=/mqseries/tools/active/bin/smx_configure.sh
maint_status=/mqseries/tools/active/etc/maint.status


check_user(){

if [ $uid != $valid ] && [ $uid != "root" ]; then

        log_it "WARN" "Running as $uid. Run This Script As \"$valid\" or \"root\". Exiting - `date +%F-%T`"
        rm $maint_status
        exit 1

fi

if [ $uid == "root" ]; then

        log_it "INFO" "Running as root, exiting and restarting as mqm - `date +%F-%T`"
            echo "Running as root, exiting and restarting as mqm."
        `su -m $valid -c "$0 $input > /dev/null"`
        rm $maint_status
        exit 0
fi

}



log_it(){
        echo "$1 - $2" >> $logdir/$logfile 2>&1
}


check_log_file () {
    #Make sure the log is there and doesn't go crazy big 
    if [ ! -d $logdir ]; then
        mkdir -p $logdir
    fi
    log_it "" "" 
    logsize=`wc -c < $logdir/$logfile`
    if [ $logsize -gt $loglimit ]; then
        cp -p  $logdir/$logfile $logdir/$logfile.old
        truncate --size 0 $logdir/$logfile
    fi
}



if [[ ! -f $maint_status ]]; then
   touch  $maint_status
   # maint_status file does not exist, continue with process.
else
   log_it "WARN" "maint_status file exist Check if file older than five minutes.- `date +%F-%T`"
   fileage=`echo $(($(date +%s) - $(date +%s -r "$maint_status")))`
 
   # Check if file is older than 5 minutes.
   if  (( $fileage > 300 )) ; then
        log_it "WARN" "maint_status file exist and older than five minutes.- `date +%F-%T`"
   else
        log_it "WARN" "Its under execution. Exiting - `date +%F-%T`"  
        exit 1
   fi
fi

validate_karaf(){
    log_it "INFO" "Validating Karaf instance. - `date +%F-%T`"
    java_pid3=`ps -ef | grep java | grep karaf | grep -v grep | wc -l`
    
        if [[ $java_pid3 -gt 1 ]]; then

       
             log_it "ERROR" "Multiple Karaf instances started - `date +%F-%T`"
             
             cleanup_processes
             log_it "INFO" "Executing Cleanup process.  - `date +%F-%T`"
     
            sleep 10
            log_it "INFO" "Starting Karaf instances once again - `date +%F-%T`"
             start_karaf


        elif [[ $java_pid3 -eq 1 ]]; then
             log_it "INFO" "Karaf instance started and validated successfully. - `date +%F-%T`"
        fi

}
shutdown_karaf(){
 
 
   log_it "INFO" "Trying to stop using karaf stop."
   $SMX_HOME/bin/stop   
   sleep 60
   
   karafpids1=`ps -ef | grep java | grep karaf | grep -v grep | wc -l`
    
   if [[ $karafpids1 -gt 0 ]]; then

        log_it "INFO" "Karaf did not go down, waiting additional time - `date +%F-%T`"
        sleep 60
            karafpids2=`ps -ef | grep java | grep karaf | grep -v grep | wc -l`
   
            if [[ $karafpids2 -gt 0 ]]; then
   
                log_it "INFO" "Karaf inatnce did not go down, killing the instance process - `date +%F-%T`"
                cleanup_processes
            else
                
                    log_it "INFO" "Karaf instance stopped"
            fi
   else
         
            log_it "INFO" "Karaf instance stopped"
   fi
    
    }
    

try_shutdown(){
        #make sure karaf is even installed and up
        if [[ -d $SMX_HOME/bin ]]; then
          karafstat=`ps -ef | grep java | grep karaf | grep -v grep | wc -l`
          #Check to see if the karaf installation is running 
          if [[ $karafstat -gt 0 ]]; then
               shutdown_karaf
          else
       
                   log_it "INFO" "Karaf is not currently running."
          fi
    else
          log_it "ERROR" "Karaf is not installed"
    fi
}

cleanup_processes(){
    extra_pids=`ps -ef | grep java | grep karaf | grep -v grep|awk '{print $2}' $1`

    log_it "INFO" "Killing additional karaf leftover PIDs"
    log_it "INFO"  ${extra_pids[@]}
    for pid in $extra_pids ; do
            kill -9 $pid
    done
    
}

check_status(){

        jvm_pids=`ps -ef | grep java | grep karaf | grep -v grep | wc -l`

    if [[ $jvm_pids -eq 1 ]]; then
             log_it "INFO" "One or more karaf java processes running. Exiting without starting."
         rm $maint_status
             exit 1     
        elif [[ $jvm_pids -gt 0 ]]; then
            log_it "ERROR" "Multiple Karaf instances running - `date +%F-%T`"
             
        cleanup_processes
        
        log_it "INFO" "Executing Cleanup process.  - `date +%F-%T`"


        else
             
             log_it "INFO" "No karaf java processes Running, Proceeding with startup."
        fi      
}

start_karaf(){
    
        log_it "INFO" "Running Enterprise Gateway registration script before Karaf start up - `date +%F-%T`"
    ${ent_store_register_cmd}

        secs=60  
    SECONDS=0   
    while (( SECONDS < secs )); do   
        if [[ -f $ent_store_register_completion  ]] ; then
          log_it "INFO" "Successfully Completed Enterprise Gateway registration in $SECONDS seconds. - `date +%F-%T`" 
          break
        fi
    done
        
        
        log_it "INFO" "Running karaf configure before start up - `date +%F-%T`"
        ${amq_configure_cmd}
        if [[ $? != 0 ]];
        then

                log_it "WARN" "RMQ Configuration did not complete successfully.  Not starting Karaf. Check logs. - `date +%F-%T`"
                exit 1
        fi

        echo "Reaching smx_home bin start"
        $SMX_HOME/bin/start    
         sleep 30
        java_pid1=`ps -ef | grep java | grep karaf | grep -v grep | wc -l`
        if [[ $java_pid1 -eq 1 ]]; then

             log_it "INFO" "Karaf instance started - `date +%F-%T`"
             
        else
    
                 log_it "INFO" "Giving Additional time to start up - `date +%F-%T`"
                 sleep 30
                 java_pid2=`ps -ef | grep java | grep karaf | grep -v grep | wc -l`
                 if [[ $java_pid2 -eq 1 ]]; then
                 log_it "INFO" "Karaf instance started - `date +%F-%T`"
                 else   
                     log_it "INFO" "Karaf instance did not start up.  - `date +%F-%T`"
             fi
                fi
}



check_log_file
log_it "INFO" "Karaf management script started - `date +%F-%T`"
check_user


case "$1" in

    'start')
        log_it "INFO" "Requested to Start - `date +%F-%T`"
        check_status
        start_karaf
        validate_karaf
        ;;

    'stop')
        log_it "INFO" "Requested to Stop - `date +%F-%T`"
        try_shutdown
        ;;

    'restart')
        log_it "INFO" "Requested to Restart - `date +%F-%T`"
        try_shutdown
        log_it "INFO" "Restarting karaf - `date +%F-%T`"
        start_karaf
        validate_karaf
        ;;
  
    *)
        echo "Usage: $0 { start | stop | restart }"
        rm $maint_status
        exit 1
        ;;
esac

rm $maint_status

exit 0
