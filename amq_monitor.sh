#!/bin/ksh
# amq_monitor.ksh
# Checks to make sure Karaf is running correctly:
#       1. if karaf is not running, it starts karaf
#       2. if karaf has been running for 7 days, it will restart karaf if the time is during the 4am hour
#
# 20140821 jcdavie - added restart after 7 days
# 20140822 b0sheph - added start if not running
#                  - modified 7day restart to only happen during the 4am hour
#############################################################################
#Setup environment for java and fuse
#export JAVA_HOME=/mqseries/java/active
#export FUSE_HOME=/mqseries/fuse/active
export AMQ_TOOLS=/mqseries/tools/active/bin
#export PATH=$PATH:$JAVA_HOME/bin:$FUSE_HOME/bin:$AMQ_TOOLS

logdir=/u/users/mqm/logs
logfile=managekaraf.log
echo "log: grep amq_monitor $logdir/$logfile"

########## FUNCTIONS ###########
MAINTENANCE_CHECK(){
        ## check to see if the server is currently under maintenance
        curRunLevel=`who -r`
        #echo $curRunLevel
        if [[ `who -r | grep -Po '(?<=run-level.)3'` -eq 3 ]]; then # if server is in run level 3
                echo "Server Normal Operation"
        else
                echo "Server Maintenance Occuring. Disregard monitor alerts" 
                log_it "WARN" "amq_monitor: $curRunLevel"
                log_it "WARN" "amq_monitor: Monitor has been disabled while the server is down for maintenance"
                exit 1
        fi

        ## check to see if someone has created the maintenance file, to disable alerting
        if [[ -e /u/spool/07/amq.maint || -e /u/spool/01/amq.maint ]]; then
                echo "AMQ under maintenance"
                log_it "WARN" "amq_monitor: Maintenance flag has been created. remove /u/spool/07/amqUnderMaint once maintenance is complete "  
                log_it "WARN" "amq_monitor: Monitor has been disabled while the server is down for maintenance"
                exit 1
        fi
}       

log_it(){
        echo "`date +%F-%T` $1 - $2" >> $logdir/$logfile 2>&1
}

RESTART_KARAF(){ #called in KARAF_UPTIME
    if [[ -x $AMQ_TOOLS/managekaraf.sh ]]; then 
        $AMQ_TOOLS/managekaraf.sh restart
        log_it "INFO" "amq_monitor: Attempting start using managekaraf.sh"
    elif [[ -x /u/bin/karaf-service ]]; then
        /u/bin/karaf-service restart
        log_it "WARN" "amq_monitor: NOT CURRENT KARAF PACKAGE - Missing $AMQ_TOOLS/managekaraf.sh - Attempting start using karaf-service"
    else
        log_it "ERROR" "amq_monitor: NOT CURRENT KARAF PACKAGE - Missing $AMQ_TOOLS/managekaraf.sh & /u/bin/karaf-service"
    fi

    #check to make sure that karaf started
    KARAFUP="$(ps -eo etime,cmd | grep -E '.*java.*(org.apache.karaf).*\.Main.*' | grep -v grep | sed -e 's/^[ \t]*//' | wc -l)"
    if [[ $KARAFUP -eq 1 ]]; then
        echo "karaf started successfully"
        log_it "INFO" "amq_monitor: karaf started successfully"
        
        exit 0
    else
        echo "karaf failed to start"
        log_it "ERROR" "amq_monitor: karaf failed to start (KARAFUP=$KARAFUP)"
        #echo "karaf failed to start (KARAFUP=$KARAFUP)"
        ####
        #### need to add functionality to create ticket
        ####
        exit 1
    fi
}

KARAF_UPTIME(){
###############################################################################
## make sure karaf is running and restarts karaf if it has been running more than 7 days
## 1) List process uptime and command
##        ps -eo etime,cmd
## 2) grep for the Karaf process
##        grep -E '.*java.*(org.apache.karaf).*\.Main.*'
##        Look for "java", preceded by zero or more of any character, 
##        followed by zero or more of any character, 
##        followed by org.apache.karaf, 
##        followed by zero or more of any character, 
##        followed by ".Main" and zero or more of any character
## 3) Exclude the grep process from the grep output
##        grep -v grep
## 4) Search for the first space, and discard everything after
##        awk -F" " '{ print $1 }'
## 5) Get rid of any whitespace
##        sed -e 's/^[ \t]*//')
##

UPTIMESTR="$(ps -eo etime,cmd | grep -E '.*java.*(org.apache.karaf).*\.Main.*' | grep -v grep | awk -F" " '{ print $1 }' | sed -e 's/^[ \t]*//')"

#UPTIMESTR="" # for testing
#UPTIMESTR="26-19:41:00" #for testing karaf running over 7 days

#echo "UPTIME: $UPTIMESTR"
###############################################################################

if [[ -z $UPTIMESTR ]]; then
    ## if UPTIMESTR is null or empty then set the number of days to zero
    log_it "WARN" "amq_monitor: Karaf is not running, Restarting Karaf Now"
    echo "Karaf is not running, starting Karaf"  
    RESTART_KARAF
else
    ## Look for a dash (-), which follows the days of uptime (if running 1 or more days) 
    ## and grab everything before the dash, if it's there 
    DAYS=${UPTIMESTR%%-*}
fi

if [[ "$DAYS" = +(*:*) ]]; then
    ## If the uptime string contains a colon (:), then the pattern matching above did 
    ## not find a dash (-), meaning the process has been running for less than a day 
    DAYS=0
    #echo "Karaf has been running less than a day"
elif (( $DAYS >= 7 )); then
    ## If Karaf has been running for more than 7 days, restart it
    ## this prevents issues from any memory leaks from the karaf java process 
    CurHour=`date +%H`
    #CurHour="04" #used for testing
    if [[ $CurHour -eq 04 ]]; then #wait, if nessesary and only restart during the 4am hour. (requested by Jim Stierle to avoid possible pages during the night)
        log_it "INFO" "amq_monitor: Karaf has been running for more than 7 days, Restarting Karaf Now" 
        echo "Karaf has been running more than 7 days, restarting karaf"
        RESTART_KARAF
    else
            echo "Karaf has been running for more than 7 days, waiting until 4am hour to restart karaf (Current hour: $CurHour)"
    fi
fi
}

###### - MAIN - ######
MAINTENANCE_CHECK
KARAF_UPTIME

echo "currently No Issues"
exit 0
