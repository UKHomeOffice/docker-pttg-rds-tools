#!/usr/bin/env bash

pushd ./scripts
source ./common.sh
popd

abortIfNoAwsAccess
stopRdsInstance
