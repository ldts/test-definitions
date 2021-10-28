#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2021 Foundries.io Ltd.

# shellcheck disable=SC1091
. ./sh-lib
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
export RESULT_FILE
TYPE="kernel"
UBOOT_VAR_TOOL=fw_printenv
export UBOOT_VAR_TOOL
UBOOT_VAR_SET_TOOL=fw_setenv
export UBOOT_VAR_SET_TOOL

usage() {
	echo "\
	Usage: $0
		     [-type <kernel|uboot>]

	-t <kernel|uboot>
		This determines type of corruption test
        performed:
        kernel: corrupt OTA updated kernel binary
        uboot: corrupt OTA updated u-boot binary
    -u <u-boot variable read tool>
        Set the name of the tool to read u-boot variables
        On the unsecured systems it will usually be
        fw_printenv. On secured systems it might be
        fiovb_printenv
    -s <u-boot variable set tool>
        Set the name of the tool to set u-boot variables
        On the unsecured systems it will usually be
        fw_setenv. On secured systems it might be
        fiovb_setenv
	"
}

while getopts "t:u:s:h" opts; do
	case "$opts" in
		t) TYPE="${OPTARG}";;
        u) UBOOT_VAR_TOOL="${OPTARG}";;
        s) UBOOT_VAR_SET_TOOL="${OPTARG}";;
		h|*) usage ; exit 1 ;;
	esac
done

# the script works only on builds with aktualizr-lite
# and lmp-device-auto-register

! check_root && error_msg "You need to be root to run this script."
create_out_dir "${OUTPUT}"

ref_bootcount_before_download=0
ref_rollback_before_download=0
ref_bootupgrade_available_before_download=0
ref_upgrade_available_before_download=0
ref_fiovb_is_secondary_boot_before_download=0
ref_bootcount_after_download=0
ref_rollback_after_download=0
ref_bootupgrade_available_after_download=0
ref_upgrade_available_after_download=1
ref_fiovb_is_secondary_boot_after_download=0
if [ "${TYPE}" = "uboot" ]; then
    ref_bootupgrade_available_after_download=1
fi

# check u-boot variables to ensure we're on freshly flashed device
bootcount_before_download=$(uboot_variable_value bootcount)
compare_test_value "${TYPE}_bootcount_before_download" "${ref_bootcount_before_download}" "${bootcount_before_download}"
rollback_before_download=$(uboot_variable_value rollback)
compare_test_value "${TYPE}_rollback_before_download" "${ref_rollback_before_download}" "${rollback_before_download}"
bootupgrade_available_before_download=$(uboot_variable_value bootupgrade_available)
compare_test_value "${TYPE}_bootupgrade_available_before_download" "${ref_bootupgrade_available_before_download}" "${bootupgrade_available_before_download}"
upgrade_available_before_download=$(uboot_variable_value upgrade_available)
compare_test_value "${TYPE}_upgrade_available_before_download" "${ref_upgrade_available_before_download}" "${upgrade_available_before_download}"

. /usr/lib/firmware/version.txt
bootfirmware_version_before_download=$(uboot_variable_value bootfirmware_version)
# shellcheck disable=SC2154
compare_test_value "${TYPE}_bootfirmware_version_before_download" "${bootfirmware_version}" "${bootfirmware_version_before_download}"
fiovb_is_secondary_boot_before_download=$(uboot_variable_value fiovb.is_secondary_boot)
compare_test_value "${TYPE}_fiovb_is_secondary_boot_before_download" "${ref_fiovb_is_secondary_boot_before_download}" "${fiovb_is_secondary_boot_before_download}"

if [ "${TYPE}" = "uboot" ]; then
    # manually set boot firmware version to 0
    "${UBOOT_VAR_SET_TOOL}" bootfirmware_version 0
fi

# configure aklite callback
cp aklite-callback.sh /var/sota/
chmod 755 /var/sota/aklite-callback.sh

mkdir -p /etc/sota/conf.d
cp z-99-aklite-callback.toml /etc/sota/conf.d/
report_pass "${TYPE}-create-aklite-callback"
# create signal files
touch /var/sota/ota.signal
touch /var/sota/ota.result
report_pass "${TYPE}-create-signal-files"

#systemctl mask aktualizr-lite
# enabling lmp-device-auto-register will fail because aklite is masked
systemctl enable --now lmp-device-auto-register || error_fatal "Unable to register device"
# aktualizr-lite update
# TODO: check if there is an update to download
# if there isn't, terminate the job
# use "${upgrade_available_after_download}" for now. Find a better solution later

# wait for 'install-post' signal
SIGNAL=$(</var/sota/ota.signal)
while [ ! "${SIGNAL}" = "install-post" ]
do
	echo "Sleeping 1s"
	sleep 1
	cat /var/sota/ota.signal
	SIGNAL=$(</var/sota/ota.signal)
	echo "SIGNAL: ${SIGNAL}."
done
report_pass "${TYPE}-install-post-received"

# check variables after download is completed
bootcount_after_download=$(uboot_variable_value bootcount)
compare_test_value "${TYPE}_bootcount_after_download" "${ref_bootcount_after_download}" "${bootcount_after_download}"
rollback_after_download=$(uboot_variable_value rollback)
compare_test_value "${TYPE}_rollback_after_download" "${ref_rollback_after_download}" "${rollback_after_download}"
bootupgrade_available_after_download=$(uboot_variable_value bootupgrade_available)
compare_test_value "${TYPE}_bootupgrade_available_after_download" "${ref_bootupgrade_available_after_download}" "${bootupgrade_available_after_download}"
upgrade_available_after_download=$(uboot_variable_value upgrade_available)
compare_test_value "${TYPE}_upgrade_available_after_download" "${ref_upgrade_available_after_download}" "${upgrade_available_after_download}"

. /usr/lib/firmware/version.txt
# shellcheck disable=SC2154
ref_bootfirmware_version_after_download="${bootfirmware_version}"
if [ "${TYPE}" = "uboot" ]; then
    ref_bootfirmware_version_after_download=0
fi
bootfirmware_version_after_download=$(uboot_variable_value bootfirmware_version)
# shellcheck disable=SC2154
compare_test_value "${TYPE}_bootfirmware_version_after_download" "${ref_bootfirmware_version_after_download}" "${bootfirmware_version_after_download}"
fiovb_is_secondary_boot_after_download=$(uboot_variable_value fiovb.is_secondary_boot)
compare_test_value "${TYPE}_fiovb_is_secondary_boot_after_download" "${ref_fiovb_is_secondary_boot_after_download}" "${fiovb_is_secondary_boot_after_download}"

UPGRADE_AVAILABLE="${upgrade_available_after_download}"
if [ "${TYPE}" = "uboot" ]; then
    UPGRADE_AVAILABLE="${bootupgrade_available_after_download}"
fi

if [ "${UPGRADE_AVAILABLE}" -eq 1 ]; then
    if [ "${TYPE}" = "uboot" ]; then
        # add debug print to understand which file is corrupted
        ostree admin status
        for DIRECTORY in /ostree/boot.0/lmp/*
        do
            echo "$DIRECTORY/0 ->"
            readlink "$DIRECTORY/0"
        done

        # obtain new deployment hash
        DEPLOYMENT_HASH=$(ostree admin status | grep pending | awk -F' ' '{print $2}')
        echo "Corrupting u-boot.itb in /sysroot/ostree/deploy/lmp/deploy/${DEPLOYMENT_HASH}/usr/lib/firmware/"
        # corrupt u-boot.itb
        echo bad > "/sysroot/ostree/deploy/lmp/deploy/${DEPLOYMENT_HASH}/usr/lib/firmware/u-boot.itb"
    fi
    if [ "${TYPE}" = "kernel" ]; then
        cat /etc/os-release
        cat /boot/loader/uEnv.txt
        . /boot/loader/uEnv.txt
        # shellcheck disable=SC2154
        echo "Corrupting kernel image ${kernel_image}"
        # shellcheck disable=SC2154
        echo bad > "${kernel_image}"
    fi
else
    lava-test-raise "No-update-available-${TYPE}"
fi