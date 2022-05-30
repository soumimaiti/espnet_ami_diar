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
dir=$1
mkdir -p $dir

adir=$2

echo "Downloading annotations..."

amiurl=http://groups.inf.ed.ac.uk/ami
annotver=ami_public_manual_1.6.1
annot="$dir/$annotver"

logdir=data/local/downloads; mkdir -p $logdir/log
[ ! -f $annot.zip ] && wget -nv -O $annot.zip $amiurl/AMICorpusAnnotations/$annotver.zip &> $logdir/log/download_ami_annot.log

if [ ! -d $dir/annotations ]; then
  mkdir -p $dir/annotations
  unzip -o -d $dir/annotations $annot.zip &> /dev/null
fi

[ ! -f "$dir/annotations/AMI-metadata.xml" ] && echo "$0: File AMI-Metadata.xml not found under $dir/annotations." && exit 1;

# extract text from AMI XML annotations,
local/ami_xml2text.sh $dir

wdir=data/local/annotations
[ ! -f $wdir/transcripts1 ] && echo "$0: File $wdir/transcripts1 not found." && exit 1;

transcript="${wdir}/transcripts1"
transcript_sort="${wdir}/transcripts1_sort"
split_transcript="${wdir}/transcripts1_split"
long_transcript="${wdir}/transcripts1_long"
#copy transcript and sort

sort -k1,1 -k6,6n  < $transcript > $transcript_sort
local/ami_split_meetings.py --dir $adir --transcript $transcript --sort_transcript $transcript_sort --out_transcript $split_transcript

rm "${transcript_sort}"
mv "${transcript}" "${long_transcript}"
mv "${split_transcript}" "${transcript}"