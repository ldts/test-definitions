#!/bin/sh -e

. ../../lib/sh-test-lib
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
export RESULT_FILE

REFERENCE_TEST_SUITE="JVT-AVC_V1"
SUMMARY_FILE="${OUTPUT}/summary.txt"
FULL_FILE="${OUTPUT}/full.txt"

usage() {
    echo "\
    Usage: $0 -t <Fluster test suite>
    "
}

while getopts "t:h" opts; do
    case "$opts" in
        t) REFERENCE_TEST_SUITE="${OPTARG}";;
        h|*) usage ; exit 1 ;;
    esac
done

create_out_dir "${OUTPUT}"

# Get fluster if not present
if [ ! -d "fluster" ]; then
	FLUSTER_VERSION="v1.6.0"
	FLUSTER_TARBALL="fluster-${FLUSTER_VERSION}.tar.gz"
	FLUSTER_URL="https://github.com/fluendo/fluster/archive/refs/tags/${FLUSTER_VERSION}.tar.gz"
	wget -O "${FLUSTER_TARBALL}" "${FLUSTER_URL}"
	tar -xzf "${FLUSTER_TARBALL}"
	mv "fluster-${FLUSTER_VERSION}" fluster
	rm "${FLUSTER_TARBALL}"
fi

cd fluster

info_msg "Download test suite resources for ${REFERENCE_TEST_SUITE}" 
./fluster.py download -ts "${REFERENCE_TEST_SUITE}" || exit 1

info_msg "Running test suite ${REFERENCE_TEST_SUITE}"
./fluster.py run -ts ${REFERENCE_TEST_SUITE} -s -so "${SUMMARY_FILE}" > "${FULL_FILE}" 2>&1

LOG="${FULL_FILE}"

{
	if ! command -v gst-launch-1.0 >/dev/null 2>&1; then
		echo "GStreamer not installed, skipping GStreamer-H.264-V4L2-Gst1.0 tests"
	else
		# Parse GStreamer-H.264-V4L2-Gst1.0 results
		total_gst=$(grep -E '^\[${REFERENCE_TEST_SUITE}\] \(GStreamer-H.264-V4L2-Gst1.0\)' "$LOG" | wc -l)
		failed_gst=$(grep -E '^\[${REFERENCE_TEST_SUITE}\] \(GStreamer-H.264-V4L2-Gst1.0\).*\.\.\. (Fail|Error|Timeout)' "$LOG" | wc -l)

		echo "GStreamer-H.264-V4L2-Gst1.0: $total_gst tests run, $failed_gst failed"
		grep -E '^\[${REFERENCE_TEST_SUITE}\] \(GStreamer-H.264-V4L2-Gst1.0\).*\.\.\. (Fail|Error|Timeout)' "$LOG" \
			| awk -F'\) ' '{print $2}' \
			| awk -F' ... ' '{print $1}' \
			| while read -r testname; do
				echo "FAILED (GStreamer-H.264-V4L2-Gst1.0): $testname"
			done
	fi

	if ! command -v ffmpeg >/dev/null 2>&1; then
		echo "FFmpeg not installed, skipping FFmpeg-H.264-v4l2m2m tests"
	else	
		total_ffmpeg=$(grep -E '^\[${REFERENCE_TEST_SUITE}\] \(FFmpeg-H.264-v4l2m2m\)' "$LOG" | wc -l)
		failed_ffmpeg=$(grep -E '^\[${REFERENCE_TEST_SUITE}\] \(FFmpeg-H.264-v4l2m2m\).*\.\.\. (Fail|Error|Timeout)' "$LOG" | wc -l)

		echo "FFmpeg-H.264-v4l2m2m: $total_ffmpeg tests run, $failed_ffmpeg failed"
		grep -E '^\[${REFERENCE_TEST_SUITE}\] \(FFmpeg-H.264-v4l2m2m\).*\.\.\. (Fail|Error|Timeout)' "$LOG" \
			| awk -F'\) ' '{print $2}' \
			| awk -F' ... ' '{print $1}' \
			| while read -r testname; do
				echo "FAILED (FFmpeg-H.264-v4l2m2m): $testname"
			done
	fi	  
} > "${RESULT_FILE}"
