#!/bin/bash

EUE_API_PROJECT_DIR=${EUE_API_PROJECT_DIR:-../eue-api-project}
declare -a script_names
declare -a files_to_clean_up_in_tear_down
declare -a mocked_commands_to_clean_up_in_tear_down

oneTimeSetUp() {
    echo Running One Time Set Up

    echo Copying vault scripts to current directory

    cp "${EUE_API_PROJECT_DIR}/templates/_vault-scripts.tpl" .

    echo Splitting into files

    splitIntoFiles

    makeFilesExecutable

    mkdir -p ./mnt/{secrets,certs}

    export PATH=${PATH}:`pwd`
}

oneTimeTearDown() {
    echo Running One Time Tear Down

    rm -f ${script_names[@]} _vault-scripts.tpl
}

setUp() {
    files_to_clean_up_in_tear_down=()
}

tearDown() {
    rm -f "${files_to_clean_up_in_tear_down[@]}"
    unset -f "${mocked_commands_to_clean_up_in_tear_down[@]}"
}

##################
# Tests
##################

testNotifyInit() {
    expected_output='Initialised secret'
	if ! grep "$expected_output" <(./notify-init.sh) >/dev/null ; then
        fail "Did not see '$expected_output' in output"
    fi
}

testAddCredentialsToHtpasswd() {
    some_credentials=someuser:somepass

    # Create a .htpasswd file for testing
    touch .htpasswd_1
    # Assert credentials not in file
    assertFalse 'Username and password unexpectedly in .htpasswd file' 'htpasswd -vb .htpasswd_1 someuser somepass'

    # Run the addCredentialsToHtpasswd script
    ./addCredentialsToHtpasswd "${some_credentials}"
    # Assert that the credentials are in the file
    assertTrue 'Username and password not in .htpasswd file' 'htpasswd -vb .htpasswd_1 someuser somepass'

    rm .htpasswd_1
}

testCredentialsHaveChanged_fileDoesNotExist_noChange() {
    ./credentialsHaveChanged someNonExistantFile.new
    assertEquals 'Expected credentialsHaveChanged to have exit code 1 (no change)' 1 $?
    tearDownCredentialsHaveChangedTest someNonExistantFile
}

testCredentialsHaveChanged_currentFileButNoNewFile_change() {
    echo 'someuser:somepass' > someCredentials.current

    ./credentialsHaveChanged someCredentials.new
    assertEquals 'Expected credentialsHaveChanged to have exit code 0 (change)' 0 $?

    tearDownCredentialsHaveChangedTest someCredentials
}

testCredentialsHaveChanged_newFileButNoCurrentFile_change() {
    echo 'someuser:somepass' > someCredentials.new

    ./credentialsHaveChanged someCredentials.new
    assertEquals 'Expected credentialsHaveChanged to have exit code 0 (change)' 0 $?

    tearDownCredentialsHaveChangedTest someCredentials
}

testCredentialsHaveChanged_filesTheSame_noChange() {
    echo 'someuser:somepass' > someCredentials.new
    echo 'someuser:somepass' > someCredentials.current

    ./credentialsHaveChanged someCredentials.new
    assertEquals 'Expected credentialsHaveChanged to have exit code 1 (no change)' 1 $?

    tearDownCredentialsHaveChangedTest someCredentials
}

testCredentialsHaveChanged_filesDifferent_change() {
    echo 'someuser:somepass' > someCredentials.new
    echo 'somenewuser:somenewpass' > someCredentials.current

    ./credentialsHaveChanged someCredentials.new
    assertEquals 'Expected credentialsHaveChanged to have exit code 0 (change)' 0 $?

    tearDownCredentialsHaveChangedTest someCredentials
}

testcertsExpireInThisOrder_noCerts_notChanged() {
    ./certsExpireInThisOrder doesnt_exist.pem doesnt_exist.pem
    assertEquals 'No certificates should return exit code 1 (unchanged)' 1 $?
}

testcertsExpireInThisOrder_noNewerCert_notChanged() {
    createTestCert cert.pem 2
    ./certsExpireInThisOrder cert.pem doesnt_exist.pem
    assertEquals 'No newer certificate should return exit code 1 (unchanged)' 1 $?
}

testcertsExpireInThisOrder_noOlderCert_changed() {
    createTestCert cert.pem 2
    ./certsExpireInThisOrder doesnt_exist.pem cert.pem
    assertEquals 'No older certificate should return exit code 0 (changed)' 0 $?
}

testcertsExpireInThisOrder_newerCert_changed() {
    createTestCert older_cert.pem 2
    createTestCert newer_cert.pem 3

    ./certsExpireInThisOrder older_cert.pem newer_cert.pem
    assertEquals 'Newer certificate should return exit code 0 (changed)' 0 $?
}

testcertsExpireInThisOrder_olderCert_notChanged() {
    createTestCert older_cert.pem 2
    createTestCert newer_cert.pem 3

    ./certsExpireInThisOrder newer_cert.pem older_cert.pem
    assertEquals 'Older certificate should return exit code 1 (unchanged)' 1 $?
}

testcertsExpireInThisOrder_sameCert_notChanged() {
    createTestCert cert.pem 2

    ./certsExpireInThisOrder cert.pem cert.pem
    assertEquals 'Same certificate shoudl return exit code 1 (unchanged)' 1 $?
}

testCertExpirySysdigNotification_anyParams_correctEventName() {
    mockWget

    ./certExpirySysdigNotification anyCertName anyDate

    #post_data=$(cat wgetcapturedargs | grep -zoE 'post-data={.*}' | removeNullBytes | tail -c +11)
    post_data=$(awk '{ if (on == 1) { print }; if ($1 ~/\}$/) { if (on == 1) { on=0 ; printf "}\n" } }; if ($1 ~/--post-data/) { on=1 ; print "{" } }' < wgetcapturedargs)

    event_name=$(echo "${post_data}" | jq --raw-output .event.name | tail -1)
    assertEquals 'Sysdig Event did not have expected name' 'EUE-API Certificate expiry imminent' "${event_name}"
}

testCertExpirySysdigNotification_givenParams_correctedDescription() {
    mockWget

    ./certExpirySysdigNotification 'mycert.crt' 'Jun  8 16:00:33 2019 GMT'

    #post_data=$(cat wgetcapturedargs | grep -zoE 'post-data={.*}' | removeNullBytes | tail -c +11)
    post_data=$(awk '{ if (on == 1) { print }; if ($1 ~/\}$/) { if (on == 1) { on=0 ; printf "}\n" } }; if ($1 ~/--post-data/) { on=1 ; print "{" } }' < wgetcapturedargs)

    event_description=$(echo "${post_data}" | jq --raw-output .event.description | tail -1)
    expected_description='Certificate mycert.crt will expire on Jun  8 16:00:33 2019 GMT'
    assertEquals 'Sysdig Event did not have expected description' "${expected_description}" "${event_description}"
}

testCertExpirySysdigNotification_anyParams_sendSysdigToken() {
    mockWget

    some_token=841b9fbf-3c3c-4c21-8578-40fdcbde84a5
    export SYSDIG_TOKEN="${some_token}"

    ./certExpirySysdigNotification anyCertName anyDate

    auth_token=$(cat wgetcapturedargs | grep -zoEe '--header=Authorization: Bearer [^ ]*' | removeNullBytes |  cut -d ' ' -f 3 | tail -1)
    assertEquals 'Sysdig API call did not use expected token' "${some_token}" "${auth_token}"
}


testCertExpirySysdigNotification_anyParams_callExpectedUrl() {
    mockWget

    some_url='https://some.sydig-url.com'
    export SYSDIG_URL="${some_url}"

    ./certExpirySysdigNotification anyCertName anyDate

    actual_url=$(cat wgetcapturedargs | grep -zoEe 'https://.*' | removeNullBytes)
    assertEquals 'Sysdig API call not on expected URL' "${some_url}/api/events" "${actual_url}"
}

testCheckImminentCertExpiry_certExpiringSoon_certNamePassedToCollaborator() {

    mockCertExpirySysdigNotification

    export WARN_WHEN_EXPIRY_LESS_THAN_DAYS=3
    createTestCert someCert.crt 3
    cert_expiry_date=$(getCertExpiryDate someCert.crt)
    cert_expiry_time_stamp=$(getTimestampFromDate "${cert_expiry_date}")

    ./checkImminentCertExpiry someCert.crt "${cert_expiry_time_stamp}" "${cert_expiry_date}"

    cert_passed_to_collaborator=$(cat certexpirycapturedargs | cut -d ' ' -f 1)
    assertEquals 'Did not pass certificate name to certExpirySysdigNotification' someCert.crt "${cert_passed_to_collaborator}"
}

testCheckImminentCertExpiry_certExpiringSoon_expiryDatePassedToCollaborator() {
    mockCertExpirySysdigNotification

    export WARN_WHEN_EXPIRY_LESS_THAN_DAYS=3
    createTestCert someCert.crt 3
    cert_expiry_date=$(getCertExpiryDate someCert.crt)
    cert_expiry_time_stamp=$(getTimestampFromDate "${cert_expiry_date}")

    ./checkImminentCertExpiry anyCert.crt "${cert_expiry_time_stamp}" "${cert_expiry_date}"

    expiry_date_passed_to_collaborator=$(cat certexpirycapturedargs | cut -d ' ' -f 2- | tail -1)
    assertEquals 'Did not pass expiry date to certExpirySysdigNotification' "${cert_expiry_date}" "${expiry_date_passed_to_collaborator}"
}

testCheckImminentCertExpiry_certNotExpiringSoon_doesNotCallCollaborator() {
    mockCertExpirySysdigNotification

    export WARN_WHEN_EXPIRY_LESS_THAN_DAYS=3
    createTestCert someImminentCert.crt 4
    cert_expiry_date=$(getCertExpiryDate someImminentCert.crt)
    cert_expiry_time_stamp=$(getTimestampFromDate "${cert_expiry_date}")

    ./checkImminentCertExpiry someImminentCert.crt "${cert_expiry_time_stamp}" "${cert_expiry_date}"

    assertFalse 'Did not expect certExpirySysdigNotification to be called' '[ -e certexpirycapturedargs ]'
}

testCheckImminentCertExpiry_certNotExpiringSoon_echoNotExpiring() {
    export WARN_WHEN_EXPIRY_LESS_THAN_DAYS=3
    createTestCert someCert.crt 4
    cert_expiry_date=$(getCertExpiryDate someCert.crt)
    cert_expiry_time_stamp=$(getTimestampFromDate "${cert_expiry_date}")

    expected_output='The certificate someCert.crt is not close to expiry'
    command_output=$(./checkImminentCertExpiry someCert.crt "${cert_expiry_time_stamp}" "${cert_expiry_date}")
    assertEquals 'Did not print out that certificate expiriy date is not soon' "${expected_output}" "${command_output}"
}

testCertReloadScript_givenCertNames_moveToCertsDir() {
    mockMv
    createTestCert local_someCert.crt.new 4
    createTestCert local_someOtherCert.crt.new 5

    export CERT_NAMES='someCert.crt someOtherCert.crt'
    ./cert-reload-script.sh


    if ! grep --line-regexp 'local_someCert.crt.new local_someCert.crt' ./mnt/certs/mvcapturedargs ; then
        fail 'Did not move someCert.crt as expected'
    fi
    if ! grep --line-regexp 'local_someOtherCert.crt.new local_someOtherCert.crt' ./mnt/certs/mvcapturedargs ; then
        fail 'Did not move someOtherCert.crt as expected'
    fi
}

testCertReloadScript_givenCertNames_callCollaborator() {
    mockMv
    mockcertsExpireInThisOrder

    export CERT_NAMES='someCert.crt someOtherCert.crt'
    ./cert-reload-script.sh

    if ! grep --line-regexp 'local_someCert.crt local_someCert.crt.new' certsExpireInThisOrdercapturedargs ; then
        fail 'Did not pass someCert.crt to certsExpireInThisOrder as expected'
    fi
    if ! grep --line-regexp 'local_someOtherCert.crt local_someOtherCert.crt.new' certsExpireInThisOrdercapturedargs ; then
        fail 'Did not pass someOtherCert.crt to certsExpireInThisOrder as expected'
    fi
}

testCertReloadScript_certsExpireInThisOrder_overwriteOldOne() {
    mockMv
    mockWget
    mockcertsExpireInThisOrder 0

    export CERT_NAMES='someCert.crt someOtherCert.crt'
    ./cert-reload-script.sh

    if ! grep --line-regexp 'local_someCert.crt.new local_someCert.crt' ./mnt/certs/mvcapturedargs ; then
        fail 'Did not overwrite someCert.crt as expected'
    fi
    if ! grep --line-regexp 'local_someOtherCert.crt.new local_someOtherCert.crt' ./mnt/certs/mvcapturedargs ; then
        fail 'Did not overwrite someOtherCert.crt as expected'
    fi
}

testCertReloadScript_certsExpireInThisOrder_callReload() {
    mockMv
    mockWget
    mockcertsExpireInThisOrder 0

    export CERT_NAMES='someCert.crt'
    ./cert-reload-script.sh

    if ! grep 'localhost:10080/reload' wgetcapturedargs ; then
        fail 'Did not call the reload endpoint as expected'
    fi
}

testCertReloadScript_certificateIsNotNewer_doesNotOverwriteOldOne() {
    mockMv
    mockWget
    mockcertsExpireInThisOrder 1

    export CERT_NAMES='someCert.crt someOtherCert.crt'
    ./cert-reload-script.sh

    if grep --line-regexp 'local_someCert.crt.new local_someCert.crt' mvcapturedargs ; then
        fail 'Unexpectedly overwrote someCert.crt'
    fi
    if grep --line-regexp 'local_someOtherCert.crt.new local_someOtherCert.crt' mvcapturedargs ; then
        fail 'Unexpectedly overwrote someOtherCert.crt'
    fi
}

testCertReloadScript_certificateIsNotNewer_doesNotCallReload() {
    mockMv
    mockWget
    mockcertsExpireInThisOrder 1

    export CERT_NAMES='someCert.crt'
    ./cert-reload-script.sh

    if grep 'localhost:10080/reload' ./mnt/certs/wgetcapturedargs ; then
        fail 'Unexpectedly called the reload endpoint'
    fi
}

testCertReloadScript_expiringCertificateCheckDisabled_doesNotCallCollaborator(){
    mockCheckImminentCertExpiry
    export EXPIRING_CERTIFICATES_CHECK_ENABLED=false

    export CERT_NAMES='someCert.crt'
    ./cert-reload-script.sh

    assertFalse 'Did not expect checkImminentCertExpiry to be called' '[ -e checkimminentcertexpirycapturedargs ]'
}

testCertReloadScript_expiringCertificateCheckDisabled_echoSkipMessage(){
    mockCheckImminentCertExpiry
    export EXPIRING_CERTIFICATES_CHECK_ENABLED=false

    export CERT_NAMES='someCert.crt'
    captured_output=$(./cert-reload-script.sh)

    echo "Output: ${captured_output}"
    if ! grep --line-regexp 'Sysdig notifications for expiring certificates not enabled - skipping' <(echo "${captured_output}") ; then
        fail 'Did not print out that certificate check was skipped'
    fi
}

testCertReloadScript_expiringCertificateCheckEnabled_callsCollaborator(){
    mockCheckImminentCertExpiry
    export EXPIRING_CERTIFICATES_CHECK_ENABLED=true

    rm local_someCert.crt 2>/dev/null
    export CERT_NAMES='someCert.crt'
    createTestCert local_someCert.crt.new 4
    cert_expiry_date=$(getCertExpiryDate local_someCert.crt.new)
    cert_expiry_time_stamp=$(getTimestampFromDate "${cert_expiry_date}")

    ./cert-reload-script.sh

    captured_params=$(cat ./mnt/certs/checkimminentcertexpirycapturedargs)
    message='Did not call checkImminentCertExpiry with expected parameters'
    assertEquals "${message}" "local_someCert.crt ${cert_expiry_time_stamp} ${cert_expiry_date}" "${captured_params}"
}

test_installCertAndKey_succeeds() {
      mockCp
      mockWget

    ./installCertAndKey replacementCert replacementKey destination

    if ! grep --line-regexp 'replacementCert destination' cpcapturedargs ; then
      fail "Should have installed certificate at 'destination'"
    fi

    if ! grep --line-regexp 'replacementKey destination' cpcapturedargs ; then
      fail "Should have installed key at 'destination'"
    fi

    if ! grep 'localhost:10080/reload' wgetcapturedargs ; then
      fail "Should have triggerd nginx reload"
    fi
}

testCertPKISplitScript_createsCertChainAndKey(){
    cp ../../shelltests/corrupted_server.pki ./mnt/secrets/server.pki

    pkiHash=$(md5sum ./mnt/secrets/server.pki)
    message="Ensure corrupted_server.pki hasnt changed or subsequent MD5 hashes will fail for no good reason"
    assertEquals "${message}" "dd51908db03c6526eafb38a0fd33dd27  ./mnt/secrets/server.pki" "${pkiHash}"

    ./cert-pki-split-script.sh

    assertTrue 'Created local_certchain.pem.new' '[ -s ./mnt/secrets/local_certchain.pem.new ]'
    assertTrue 'Created local_key.pem.new' '[ -s ./mnt/secrets/local_key.pem.new ]'

    keyHash=$(md5sum ./mnt/secrets/local_key.pem.new)
    assertEquals "Check MD5 hash of key" "c30b947b0bfd3fade390a987556a7a48  ./mnt/secrets/local_key.pem.new" "${keyHash}"

    certHash=$(md5sum ./mnt/secrets/local_certchain.pem.new)
    assertEquals "Check MD5 hash of certchain" "bd03ec5ebd287e29128a1fdaab5a453a  ./mnt/secrets/local_certchain.pem.new" "${certHash}"
}

####################
# Helper functions
####################


splitIntoFiles() {
    while IFS= read -r line ; do
        # If line looks like "some-script-name: |"
        if [[ "${line}" == *:\ \|* ]] ; then
          file_name=$(echo ${line} | awk -F ":" '{print $1}')
          script_names+=($file_name)
		# If line starts with "{{" and ends with "}}" it is part of the template and we don't want to copy it.
	    elif [[ "${line}" != \{\{*}} ]] ; then
		    if [ -n "${file_name}" ] ; then
              echo $line | sed -e "s?/mnt/?./mnt/?g" >> ${file_name}
		    fi
        fi
    done <_vault-scripts.tpl
}

makeFilesExecutable() {
	for script in ${script_names[@]} ; do
		chmod +x $script
	done
}

tearDownCredentialsHaveChangedTest() {
    files_to_clean_up_in_tear_down+=("${1}.current")
    files_to_clean_up_in_tear_down+=("${1}.new")
}

createTestCert() {
    openssl req -nodes -x509 -subj '/CN=localhost' -newkey rsa:4096 -keyout key.pem -out "${1}" -days "${2}" &> /dev/null
    cp ${1} ./mnt/secrets/${1}
    cp key.pem ./mnt/secrets/key.pem
    files_to_clean_up_in_tear_down+=("${1}")
    files_to_clean_up_in_tear_down+=("./mnt/secrets/${1}")
    files_to_clean_up_in_tear_down+=("key.pem")
    files_to_clean_up_in_tear_down+=("./mnt/secrets/key.pem")
}

getCertExpiryDate() {
    openssl x509 -noout -enddate -in $1 | cut -d '=' -f 2
}

getTimestampFromDate() {
    date -d "${1}" +%s
}

mockCertExpirySysdigNotification() {
    certExpirySysdigNotification() {
        echo "${@}" >> certexpirycapturedargs
    }
    export -f certExpirySysdigNotification
    mocked_commands_to_clean_up_in_tear_down+=('certExpirySysdigNotification')
    files_to_clean_up_in_tear_down+=('certexpirycapturedargs')
}

mockcertsExpireInThisOrder() {
    export __mock_return=$1
    certsExpireInThisOrder() {
        echo "${@}" >> certsExpireInThisOrdercapturedargs
        return "${__mock_return}"
    }
    export -f certsExpireInThisOrder
    mocked_commands_to_clean_up_in_tear_down+=('certsExpireInThisOrder')
    files_to_clean_up_in_tear_down+=('certsExpireInThisOrdercapturedargs')
}

mockCheckImminentCertExpiry() {
    checkImminentCertExpiry() {
        echo "${@}" >> checkimminentcertexpirycapturedargs
    }
    export -f checkImminentCertExpiry
    mocked_commands_to_clean_up_in_tear_down+=('checkImminentCertExpiry')
    files_to_clean_up_in_tear_down+=('checkimminentcertexpirycapturedargs')
}

mockCp() {

    commandToMock='cp'

    echo "mock the '${commandToMock}' command"

    cp() {
        echo "${@}" >> cpcapturedargs
    }

    export -f cp

    mocked_commands_to_clean_up_in_tear_down+=("${commandToMock}")
    files_to_clean_up_in_tear_down+=("cpcapturedargs")
}

mockMv() {

    commandToMock='mv'

    echo "mock the '${commandToMock}' command"

    mv() {
        echo "${@}" >> mvcapturedargs
    }

    export -f mv

    mocked_commands_to_clean_up_in_tear_down+=("${commandToMock}")
    files_to_clean_up_in_tear_down+=('mvcapturedargs')
}

mockWget() {

    commandToMock='wget'

    echo "mock the '${commandToMock}' command"

    wget() {
        echo "${@}" >> wgetcapturedargs
    }

    export -f wget

    mocked_commands_to_clean_up_in_tear_down+=("${commandToMock}")
    files_to_clean_up_in_tear_down+=('wgetcapturedargs')
}

removeNullBytes() {
    # Sometimes trying to capture the output of a command such as grep using a subshell "$(...)" makes Bash output the warning
    # "warning: command substitution: ignored null byte in input". It doesn't cause an issue but without this function the message
    #  is seen a lot, making the test output messy.
    cat - | tr -d '\0'
}

. shunit2/shunit2
