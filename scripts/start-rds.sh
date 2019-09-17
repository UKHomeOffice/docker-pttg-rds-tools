#!/usr/bin/env bash

source common.sh

abortIfNoAwsAccess
startRdsInstanceIfStopped
rds_status=$(getRdsStatus)
if [[ "$rds_status" == "starting" ]] || [[ "$rds_status" == "rebooting" ]]; then
    waitForInstanceAvailable
fi
