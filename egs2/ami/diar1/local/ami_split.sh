#!/usr/bin/env bash
set -eu  # Exit on error

if [ $# -ne 3 ]; then
  echo "Usage: $0 <annotation_download_dir> <ami-dir> <base-mic>"
  echo " where <ami-dir> is download space."
  echo "e.g.: $0 /foo/bar/AMI"
  echo "Note: this script won't actually re-download things if called twice,"
  echo "because we use the --continue flag to 'wget'."
  exit 1;
fi
wdir=$1
adir=$2
base_mic=$3

[ ! -f $wdir/transcripts2 ] && echo "$0: File $wdir/transcripts2 not found." && exit 1;

transcript="${wdir}/transcripts2"
split_transcript="${wdir}/transcripts2_split"
long_transcript="${wdir}/transcripts2_long"

# split meeting and transcript
local/ami_split_meetings.py --dir $adir --transcript $transcript --out_transcript $split_transcript --base_mic $base_mic

mv "${transcript}" "${long_transcript}"
mv "${split_transcript}" "${transcript}"