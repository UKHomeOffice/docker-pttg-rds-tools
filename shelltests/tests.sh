#!/usr/bin/env bash

declare -a script_names
declare -a files_to_clean_up_in_tear_down
declare -a mocked_commands_to_clean_up_in_tear_down

oneTimeSetUp() {
    echo Running One Time Set Up

    echo Copying scripts to current directory
    copyScripts "../scripts"

    source common.sh

    export PATH=${PATH}:`pwd`
}

oneTimeTearDown() {
    echo Running One Time Tear Down

    rm -f ${script_names[@]}
}

setUp() {
    files_to_clean_up_in_tear_down=()
    RDS_INSTANCE='test-rds-instance'
}

tearDown() {
    rm -rf "${files_to_clean_up_in_tear_down[@]}"
    unset -f "${mocked_commands_to_clean_up_in_tear_down[@]}"
}

##################
# Tests
##################

##################
# getRdsStatus
##################

testGetRdsStatus_noResponse_nothingReturned() {
    expected_rds_status=''
    mockAws ''

    actual_rds_status=$(getRdsStatus)

    assertEquals 'Should return blank if no response from aws' "${expected_rds_status}" "${actual_rds_status}"
}

testGetRdsStatus_noResponse_attempted10Times() {
    mockAws ''

    getRdsStatus

    assertEquals 'Should make 10 attempts' 10 $(< aws-number-calls)
}

testGetRdsStatus_response_responseReturned() {
    expected_rds_status='available'
    mockAws "${expected_rds_status}"

    actual_rds_status=$(getRdsStatus)

    assertEquals 'Should return status returned from aws' "${expected_rds_status}" "${actual_rds_status}"
}

testGetRdsStatus_response_attempted1Time() {
    mockAws 'available'

    getRdsStatus

    assertEquals 'Should make 1 attempt' 1 $(< aws-number-calls)
}

testGetRdsStatus_rdsInstanceDefined_instanceSentToAws() {
    mockAws 'available'
    RDS_INSTANCE=someRdsInstance

    getRdsStatus

    actual_rds_instance=$(cat awscapturedargs | sed 's/.*--db-instance-identifier \(.*\) --query.*/\1/')

    assertEquals 'Should use rds instance from env var' "${actual_rds_instance}" "${RDS_INSTANCE}"
}

###########################
# waitForInstanceAvailable
###########################

testWaitForInstanceAvailable_available_reportsAvailable() {
    mockGetRdsStatus 'available'
    STATUS_WAIT_TIME_SECONDS=1

    rds_status=$(waitForInstanceAvailable)

    assertContains 'Should report that the instance is available' "$rds_status" 'now available'
}

testWaitForInstanceAvailable_available_getsStatusOnce() {
    mockGetRdsStatus 'available'
    STATUS_WAIT_TIME_SECONDS=1

    waitForInstanceAvailable

    assertEquals 'Should make 1 call to getRdsStatus' 1 $(< get-rds-status-number-calls)
}

testWaitForInstanceAvailable_starting_getsStatus10Times() {
    mockGetRdsStatus 'starting'
    STATUS_WAIT_TIME_SECONDS=0

    waitForInstanceAvailable

    assertEquals 'Should make 10 calls to getRdsStatus' 10 $(< get-rds-status-number-calls)
}

testWaitForInstanceAvailable_stopping_reportsAborting() {
    mockGetRdsStatus 'stopping'
    STATUS_WAIT_TIME_SECONDS=1

    rds_status=$(waitForInstanceAvailable)

    assertContains 'Should report that we are aborting' "$rds_status" 'Aborting'
}

testWaitForInstanceAvailable_stopping_getsStatusOnce() {
    mockGetRdsStatus 'stopping'
    STATUS_WAIT_TIME_SECONDS=1

    waitForInstanceAvailable

    assertEquals 'Should make 1 call to getRdsStatus' 1 $(< get-rds-status-number-calls)
}

###################
# startRdsInstance
###################

testStartRdsInstance_starting_returnsStatus() {
    mockAws '{ "DBInstance": { "DBInstanceStatus": "starting" }}'

    rds_status=$(startRdsInstance)

    assertEquals 'Should return status starting' "$rds_status" 'starting'
}

testStartRdsStatus_usesCorrectRdsInstance() {
    mockAws '{ "DBInstance": { "DBInstanceStatus": "starting" }}'
    RDS_INSTANCE='someRdsInstance'

    startRdsInstance

    actual_rds_instance=$(cat awscapturedargs | sed 's/.*--db-instance-identifier \(.*\)$/\1/')

    assertEquals 'Should use rds instance from env var' "${actual_rds_instance}" "someRdsInstance"
}

testStartRdsInstance_starting_callsOnce() {
    mockAws '{ "DBInstance": { "DBInstanceStatus": "starting" }}'

    startRdsInstance

    assertEquals 'Should call aws once' 1 $(< aws-number-calls)
}

testStartRdsInstance_notStarting_calls10Times() {
    mockAws '{ "DBInstance": { "DBInstanceStatus": "notstarting" }}'
    START_WAIT_TIME_SECONDS=0

    startRdsInstance

    assertEquals 'Should call aws ten times' 10 $(< aws-number-calls)
}

############################
# startRdsInstanceIfStopped
############################

testStartRdsInstanceIfStopped_notStopped_reportsCannotStart() {
    mockGetRdsStatus 'available'

    rds_status=$(startRdsInstanceIfStopped)

    assertContains 'Should report cannot start' "${rds_status}" 'cannot start instance'
}

testStartRdsInstanceIfStopped_stopped_attemptsToStart() {
    mockGetRdsStatus 'stopped'
    mockStartRdsInstance 'starting'

    startRdsInstanceIfStopped

    assertEquals 'Should call start rds instance' 1 $(< start-rds-instance-number-calls)
}

testStartRdsInstanceIfStopped_stoppedThenStarting_reportsStarting() {
    mockGetRdsStatus 'stopped'
    mockStartRdsInstance 'starting'

    rds_status=$(startRdsInstanceIfStopped)

    assertContains 'A start was requested' "${rds_status}" 'start requested'
}

testStartRdsInstanceIfStopped_stoppedStillStopped_reportsFailureToStart() {
    mockGetRdsStatus 'stopped'
    mockStartRdsInstance 'stopped'

    rds_status=$(startRdsInstanceIfStopped)

    assertContains 'A failure was reported' "${rds_status}" 'Failed to start'
}

#####################
# abortIfNoAwsAccess
#####################

testAbortIfNoAwsAccess_noKey_abort() {
    unset AWS_ACCESS_KEY_ID
    AWS_SECRET_ACCESS_KEY='secret'

    error_message=$(abortIfNoAwsAccess)

    assertContains 'Aborting' "${error_message}" 'aborting'
}

testAbortIfNoAwsAccess_emptyKey_abort() {
    AWS_ACCESS_KEY_ID=''
    AWS_SECRET_ACCESS_KEY='secret'

    error_message=$(abortIfNoAwsAccess)

    assertContains 'Aborting' "${error_message}" 'aborting'
}

testAbortIfNoAwsAccess_noSecret_abort() {
    AWS_ACCESS_KEY_ID='key'
    unset AWS_SECRET_ACCESS_KEY

    error_message=$(abortIfNoAwsAccess)

    assertContains 'Aborting' "${error_message}" 'aborting'
}

testAbortIfNoAwsAccess_emptySecret_abort() {
    AWS_ACCESS_KEY_ID='key'
    AWS_SECRET_ACCESS_KEY=''

    error_message=$(abortIfNoAwsAccess)

    assertContains 'Aborting' "${error_message}" 'aborting'
}

testAbortIfNoAwsAccess_keyAndSecret_dontAbort() {
    AWS_ACCESS_KEY_ID='key'
    AWS_SECRET_ACCESS_KEY='secret'

    error_message=$(abortIfNoAwsAccess)

    assertNotContains 'Not aborting' "${error_message}" 'aborting'
}

##################
# stopRdsInstance
##################

testStopRdsInstance_stopVarTrue_awsIsCalled() {
    mockAws '{ "DBInstance": { "DBInstanceStatus": "stopping" }}'

    stopRdsInstance

    assertEquals 'Should call aws once' 1 $(< aws-number-calls)
}

testStopRdsInstance_awsStopping_awsStatusReturned() {
    mockAws '{ "DBInstance": { "DBInstanceStatus": "stopping" }}'

    aws_status=$(stopRdsInstance)

    assertEquals 'Should return aws status' 'stopping' "${aws_status}"
}

testStopRdsStatus_usesCorrectRdsInstance() {
    mockAws '{ "DBInstance": { "DBInstanceStatus": "stopping" }}'
    RDS_INSTANCE='someRdsInstance'

    stopRdsInstance

    actual_rds_instance=$(cat awscapturedargs | sed 's/.*--db-instance-identifier \(.*\)$/\1/')

    assertEquals 'Should use rds instance from env var' "${actual_rds_instance}" "someRdsInstance"
}

testStopRdsInstance_awsNotStopping_tries10Times() {
    STOP_WAIT_TIME_SECONDS=0
    mockAws '{ "DBInstance": { "DBInstanceStatus": "any_status" }}'

    stopRdsInstance

    assertEquals 'Should call aws once' 10 $(< aws-number-calls)
}

####################
# Helper functions
####################

copyScripts() {
    scriptDir=$1
    for entry in "${scriptDir}"/*
    do
        entry=${entry#"$scriptDir"/}
        script_names+=("${entry}")
    done
    cp -r "${scriptDir}"/* .
}

mockAws() {

    command_to_mock='aws'
    aws_return_data=$1

    echo "mock the '${command_to_mock}' command with return data '${aws_return_data}'"

    aws() {
        echo "${@}" >> awscapturedargs
        incrementCallCount "aws-number-calls"
        echo ${aws_return_data}
    }

    export -f aws

    mocked_commands_to_clean_up_in_tear_down+=("${command_to_mock}")
    files_to_clean_up_in_tear_down+=("awscapturedargs")
    files_to_clean_up_in_tear_down+=("aws-number-calls")
}

mockGetRdsStatus() {

    command_to_mock='getRdsStatus'
    get_rds_status_return_data=$1

    echo "mock the '${command_to_mock}' command with return data '${get_rds_status_return_data}'"

    getRdsStatus() {
        incrementCallCount "get-rds-status-number-calls"
        echo ${get_rds_status_return_data}
    }

    export -f getRdsStatus

    mocked_commands_to_clean_up_in_tear_down+=("${command_to_mock}")
    files_to_clean_up_in_tear_down+=("get-rds-status-number-calls")
}

mockStartRdsInstance() {

    command_to_mock='startRdsInstance'
    start_rds_instance_return_data=$1

    echo "mock the '${command_to_mock}' command with return data '${start_rds_instance_return_data}'"

    startRdsInstance() {
        incrementCallCount "start-rds-instance-number-calls"
        echo ${start_rds_instance_return_data}
    }

    export -f startRdsInstance

    mocked_commands_to_clean_up_in_tear_down+=("${command_to_mock}")
    files_to_clean_up_in_tear_down+=("start-rds-instance-number-calls")
}

incrementCallCount() {
    count_file=$1

    if [[ ! -f ${count_file} ]]; then
        echo 0 > ${count_file}
    fi
    calls=$(< ${count_file})
    calls=$(expr $calls + 1)
    echo ${calls} > ${count_file}
}

. shunit2/shunit2
