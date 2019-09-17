#!/usr/bin/env bash

abortIfNoAwsAccess
startRdsInstanceIfStopped
rds_status=$(getRdsStatus)
if [[ "$rds_status" == "starting" ]] || [[ "$rds_status" == "rebooting" ]]; then
    waitForInstanceAvailable
fi
