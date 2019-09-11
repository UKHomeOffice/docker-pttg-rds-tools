#!/usr/bin/env bash

PS4='$LINENO'
set -x

function getRdsStatus() {
    for attempt in {1..10}
    do
        rds_status=$(aws rds describe-db-instances --db-instance-identifier ${RDS_INSTANCE} --query 'DBInstances[0].DBInstanceStatus' --output text)
        if [ -z ${rds_status} ]; then
            break
        fi
    done
    echo $rds_status
}

function waitForInstanceAvailable() {
    for attempt in {1..10}
    do
        current_status=$(getRdsStatus)
        if [ "$current_status" == "available" ]; then
            echo "${RDS_INSTANCE} is now available"
            break
        elif [ "$current_status" != "starting" ] && [ "$current_status" != "rebooting" ]; then
            echo "${RDS_INSTANCE} is at status $current_status. Aborting as this will not become available."
            break
        else
            echo  "${RDS_INSTANCE} is still starting. Waiting until available."
        fi

        sleep 60
    done
}

function startRdsInstance() {
    for attempt in {1..10}
    do
        aws rds start-db-instance --db-instance-identifier ${RDS_INSTANCE}
        starting_status=$?
        if [ $starting_status -eq 0 ]; then
            break
        fi
        sleep 1
    done
    echo $starting_status
}

function startRdsInstanceIfStopped() {
    instance_status=$(getRdsStatus)
    if [ "$instance_status" == "stopped" ]; then
        echo "RDS instance status = $instance_status.  Starting RDS instance ${RDS_INSTANCE}"
        start_status=$(startRdsInstance)
        if [ $start_status -eq 0 ]; then
            echo "RDS instance ${RDS_INSTANCE} start requested."
        else
            echo "Failed to start RDS instance ${RDS_INSTANCE}"
        fi
    else
        echo "RDS instance ${RDS_INSTANCE} is in state $instance_status - cannot start instance."
    fi
}

startRdsInstanceIfStopped
rdsStatus=$(getRdsStatus)
if [ "$rdsStatus" == "starting" ]; then
    waitForInstanceAvailable
fi
