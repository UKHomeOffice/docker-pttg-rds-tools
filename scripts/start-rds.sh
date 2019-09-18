#!/usr/bin/env bash

pushd ./scripts
source ./common.sh
popd

abortIfNoAwsAccess
startRdsInstanceIfStopped
rds_status=$(getRdsStatus)
if [[ "$rds_status" == "starting" ]] || [[ "$rds_status" == "rebooting" ]]; then
    waitForInstanceAvailable
fi
