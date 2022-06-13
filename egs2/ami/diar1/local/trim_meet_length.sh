#!/usr/bin/env bash
set -eu  # Exit on error

# if [ $# -ne 2 ]; then
#   echo "Usage: $0 <annotation_download_dir> <ami-dir>"
#   echo " where <ami-dir> is download space."
#   echo "e.g.: $0 /foo/bar/AMI"
#   echo "Note: this script won't actually re-download things if called twice,"
#   echo "because we use the --continue flag to 'wget'."
#   exit 1;
# fi
wdir=$1
adir=$2
base_mic=$3

[ ! -f $wdir/transcripts2 ] && echo "$0: File $wdir/transcripts2 not found." && exit 1;

transcript="${wdir}/transcripts2"
transcript_new="${wdir}/transcripts2_trim"
transcript_old="${wdir}/transcripts2_full"
# trim meetings and update transcript
local/trim_meeting.py --dir $adir --transcript $transcript --trim_subdir "trim" --out_transcript $transcript_new --base_mic $base_mic

mv $transcript $transcript_old
mv $transcript_new $transcript