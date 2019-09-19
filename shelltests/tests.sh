#!/bin/bash

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
    expectedRdStatus=''
    mockAws ''

    actualRdsStatus=$(getRdsStatus)

    assertEquals 'Should return blank if no response from aws' "${expectedRdsStatus}" "${actualRdsStatus}"
}

testGetRdsStatus_noResponse_attempted10Times() {
    mockAws ''

    getRdsStatus

    assertEquals 'Should make 10 attempts' 10 $(< awsnumbercalls)
}

testGetRdsStatus_response_responseReturned() {
    expectedRdStatus='available'
    mockAws ${expectedRdsStatus}

    actualRdsStatus=$(getRdsStatus)

    assertEquals 'Should return status returned from aws' "${expectedRdsStatus}" "${actualRdsStatus}"
}

testGetRdsStatus_response_attempted1Time() {
    mockAws 'available'

    getRdsStatus

    assertEquals 'Should make 1 attempt' 1 $(< awsnumbercalls)
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
    WAIT_TIME_SECONDS=1

    rds_status=$(waitForInstanceAvailable)

    assertContains 'Should report that the instance is available' "$rds_status" 'now available'
}

testWaitForInstanceAvailable_available_getsStatusOnce() {
    mockGetRdsStatus 'available'
    WAIT_TIME_SECONDS=1

    waitForInstanceAvailable

    assertEquals 'Should make 1 call to getRdsStatus' 1 $(< getrdsstatusnumbercalls)
}

testWaitForInstanceAvailable_starting_getsStatus10Times() {
    mockGetRdsStatus 'starting'
    WAIT_TIME_SECONDS=0

    waitForInstanceAvailable

    assertEquals 'Should make 10 calls to getRdsStatus' 10 $(< getrdsstatusnumbercalls)
}

testWaitForInstanceAvailable_stopping_reportsAborting() {
    mockGetRdsStatus 'stopping'
    WAIT_TIME_SECONDS=1

    rds_status=$(waitForInstanceAvailable)

    assertContains 'Should report that we are aborting' "$rds_status" 'Aborting'
}

testWaitForInstanceAvailable_stopping_getsStatusOnce() {
    mockGetRdsStatus 'stopping'
    WAIT_TIME_SECONDS=1

    waitForInstanceAvailable

    assertEquals 'Should make 1 call to getRdsStatus' 1 $(< getrdsstatusnumbercalls)
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

    commandToMock='aws'

    echo "mock the '${commandToMock}' command"

    return_data=$1

    aws() {
        echo "${@}" >> awscapturedargs
        incrementCallCount "awsnumbercalls"
        echo ${return_data}
    }

    export -f aws

    mocked_commands_to_clean_up_in_tear_down+=("${commandToMock}")
    files_to_clean_up_in_tear_down+=("awscapturedargs")
    files_to_clean_up_in_tear_down+=("awsnumbercalls")
}

mockGetRdsStatus() {

    commandToMock='getRdsStatus'

    echo "mock the '${commandToMock}' command"

    return_data=$1

    getRdsStatus() {
        incrementCallCount "getrdsstatusnumbercalls"
        echo ${return_data}
    }

    export -f getRdsStatus

    mocked_commands_to_clean_up_in_tear_down+=("${commandToMock}")
    files_to_clean_up_in_tear_down+=("getrdsstatusnumbercalls")
}

incrementCallCount() {
    countFile=$1

    if [[ ! -f ${countFile} ]]; then
        echo 0 > ${countFile}
    fi
    calls=$(< ${countFile})
    calls=$(expr $calls + 1)
    echo ${calls} > ${countFile}
}

. shunit2/shunit2
