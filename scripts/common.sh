#!/usr/bin/env bash

STATUS_WAIT_TIME_SECONDS=60
START_WAIT_TIME_SECONDS=1
STOP_WAIT_TIME_SECONDS=1

function getRdsStatus() {
    for attempt in {1..10}
    do
        rds_status=$(aws rds describe-db-instances --db-instance-identifier ${RDS_INSTANCE} --query 'DBInstances[0].DBInstanceStatus' --output text)
        if [[ -n ${rds_status} ]]; then
            break
        fi
    done
    echo ${rds_status}
}

function waitForInstanceAvailable() {
    for attempt in {1..10}
    do
        current_status=$(getRdsStatus)
        if [[ "$current_status" == "available" ]]; then
            echo "${RDS_INSTANCE} is now available"
            break
        elif [[ "$current_status" != "starting" ]] && [[ "$current_status" != "rebooting" ]]; then
            echo "${RDS_INSTANCE} is at status $current_status. Aborting as this will not become available."
            break
        else
            echo  "${RDS_INSTANCE} is still starting. Waiting until available."
        fi

        sleep ${STATUS_WAIT_TIME_SECONDS}
    done
}

function startRdsInstance() {
    for attempt in {1..10}
    do
        starting_status=$(aws rds start-db-instance --db-instance-identifier ${RDS_INSTANCE} | jq -r '.[].DBInstanceStatus')
        if [[ ${starting_status} == "starting" ]]; then
            break
        fi
        sleep ${START_WAIT_TIME_SECONDS}
    done
    echo ${starting_status}
}

function startRdsInstanceIfStopped() {
    instance_status=$(getRdsStatus)
    if [[ "$instance_status" == "stopped" ]]; then
        echo "RDS instance status = $instance_status.  Starting RDS instance ${RDS_INSTANCE}"
        start_status=$(startRdsInstance)
        if [[ ${start_status} == "starting" ]]; then
            echo "RDS instance ${RDS_INSTANCE} start requested."
        else
            echo "Failed to start RDS instance ${RDS_INSTANCE}"
        fi
    else
        echo "RDS instance ${RDS_INSTANCE} is in state $instance_status - cannot start instance."
    fi
}

function abortIfNoAwsAccess() {
    if [[ -z ${AWS_ACCESS_KEY_ID} ]] || [[ -z ${AWS_SECRET_ACCESS_KEY} ]]; then
        echo "AWS access key unavailable - aborting.  (This is deliberate in production)."
        exit 0
    fi
}

function stopRdsInstance() {
    if [[ ${STOP_RDS} != "true" ]]; then
        echo "Not stopping RDS instance - STOP_RDS=${STOP_RDS}-"
        exit 0
    fi

    for attempt in {1..10}
    do
        stopping_status=$(aws rds stop-db-instance --db-instance-identifier ${RDS_INSTANCE} | jq -r '.[].DBInstanceStatus')
        if [[ ${stopping_status} == "stopping" ]]; then
            break
        fi
        sleep ${STOP_WAIT_TIME_SECONDS}
    done
    echo ${stopping_status}
}

