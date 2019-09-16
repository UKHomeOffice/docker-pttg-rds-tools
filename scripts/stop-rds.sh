#!/usr/bin/env bash

function stopRdsInstance() {
    if [[ "$STOP_RDS" != "true" ]]; then
        echo "Not stopping RDS instance - STOP_RDS=${STOP_RDS}"
    fi

    for attempt in {1..10}
    do
        stopping_status=$(aws rds stop-db-instance --db-instance-identifier ${RDS_INSTANCE} | jq -r '.[].DBInstanceStatus')
        if [[ ${stopping_status} == "stopping" ]]; then
            break
        fi
        sleep 1
    done
    echo ${stopping_status}
}

stopRdsInstance
