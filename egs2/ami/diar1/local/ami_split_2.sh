#!/usr/bin/env bash
set -eu  # Exit on error

if [ $# -ne 2 ]; then
  echo "Usage: $0 <annotation_download_dir> <ami-dir>"
  echo " where <ami-dir> is download space."
  echo "e.g.: $0 /foo/bar/AMI"
  echo "Note: this script won't actually re-download things if called twice,"
  echo "because we use the --continue flag to 'wget'."
  exit 1;
fi
wdir=$1
adir=$2

transcript="${wdir}/transcripts2"
transcript_sort="${wdir}/transcripts2_sort"
split_transcript="${wdir}/transcripts2_split"
long_transcript="${wdir}/transcripts2_long"

#copy transcript and sort
sort -k1,1 -k5,5n  < $transcript > $transcript_sort
local/ami_split_meetings_2.py --dir $adir --transcript $transcript --sort_transcript $transcript_sort --out_transcript $split_transcript

rm "${transcript_sort}"
mv "${transcript}" "${long_transcript}"
mv "${split_transcript}" "${transcript}"