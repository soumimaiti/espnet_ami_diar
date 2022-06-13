#!/usr/bin/env bash

# Copyright 2014, University of Edinburgh (Author: Pawel Swietojanski)
#           2016  Johns Hopkins University (Author: Daniel Povey)
# AMI Corpus dev/eval data preparation
# Apache 2.0

# Note: this is called by ../run.sh.

. ./path.sh
#set -vx

#check existing directories
if [ $# != 3 ]; then
  echo "Usage: $0  <path/to/AMI> <mic-id> <set-name>"
  echo "e.g. $0 /foo/bar/AMI sdm1 dev"
  exit 1;
fi

AMI_DIR=$1
MICNUM=$(echo $2 | sed s/[a-z]//g)
SET=$3
DSET="sdm$MICNUM"

if [ "$DSET" != "$2" ]; then
  echo "$0: bad 2nd argument: $*"
  exit 1
fi

SEGS=data/local/annotations/$SET.txt
tmpdir=data/local/$DSET/$SET
dir=data/$DSET/${SET}_orig

mkdir -p $tmpdir

# Audio data directory check
if [ ! -d $AMI_DIR ]; then
  echo "Error: run.sh requires a directory argument"
  exit 1;
fi

# And transcripts check
if [ ! -f $SEGS ]; then
  echo "Error: File $SEGS no found (run ami_text_prep.sh)."
  exit 1;
fi

# find headset wav audio files only, here we again get all
# the files in the corpora and filter only specific sessions
# while building segments

find $AMI_DIR -iname "*.Array1-0$MICNUM.wav" | grep -v "long_audio\|trim" | sort -u > $tmpdir/wav.flist

n=`cat $tmpdir/wav.flist | wc -l`
echo "In total, $n files were found."

# (1a) Transcriptions preparation
# here we start with normalised transcripts

#awk '{meeting=$1; channel="SDM"; speaker=$3; stime=$4; etime=$5;
# printf("AMI_%s_%s_%s_%07.0f_%07.0f", meeting, channel, speaker, int(100*stime+0.5), int(100*etime+0.5));
# for(i=6;i<=NF;i++) printf(" %s", $i); printf "\n"}' $SEGS | sort -u | uniq > $tmpdir/text
awk '{meeting=$1; channel="SDM"; speaker=$3; stime=$4; etime=$5;
 printf("AMI_%s_%s_%s_%07.0f_%07.0f", speaker, meeting, channel, int(100*stime+0.5), int(100*etime+0.5));
 for(i=6;i<=NF;i++) printf(" %s", $i); printf "\n"}' $SEGS | sort -u | uniq > $tmpdir/text

# (1c) Make segment files from transcript
#segments file format is: utt-id side-id start-time end-time, e.g.:
#AMI_ES2011a_H00_FEE041_0003415_0003484
awk '{
       segment=$1;
       split(segment,S,"[_]");
       audioname=S[1]"_"S[3]"_"S[4]"_"S[5]; startf=S[6]; endf=S[7];
       print segment " " audioname " " startf/100 " " endf/100 " "
}' < $tmpdir/text > $tmpdir/segments

#EN2001a.Array1-01.wav
#sed -e 's?.*/??' -e 's?.sph??' $dir/wav.flist | paste - $dir/wav.flist \
#  > $dir/wav.scp

sed -e 's?.*/??' -e 's?.wav??' $tmpdir/wav.flist | \
 perl -ne 'split; $_ =~ m/(.*)\..*/; print "AMI_$1_SDM\n"' | \
  paste - $tmpdir/wav.flist | sort -u > $tmpdir/wav1.scp

#Keep only devset part of waves
#awk '{print $2}' $tmpdir/segments | sort -u | join - $tmpdir/wav1.scp > $tmpdir/wav2.scp
grep -f local/split_"${SET}".orig $tmpdir/wav1.scp  > $tmpdir/wav2.scp


#replace path with an appropriate sox command that select single channel only
awk '{print $1" sox -c 1 -t wavpcm -e signed-integer "$2" -t wavpcm - |"}' $tmpdir/wav2.scp > $tmpdir/wav.scp

#prep reco2file_and_channel
cat $tmpdir/wav.scp | \
  perl -ane '$_ =~ m:^(\S+SDM).*\/([IETB].*)\.wav.*$: || die "bad label $_";
       print "$1 $2 A\n"; '\
  > $tmpdir/reco2file_and_channel || exit 1;

# we assume we adapt to the session only
awk '{print $1}' $tmpdir/segments | \
  perl -ane 'chop; @A = split("_", $_); $spkid = join("_", @A[1]); print "$_ $spkid\n";' \
        > $tmpdir/utt2spk || exit 1;

# sort -k 2 $tmpdir/utt2spk | utils/utt2spk_to_spk2utt.pl > $tmpdir/spk2utt || exit 1; TODO: Do we need this?
utils/utt2spk_to_spk2utt.pl $tmpdir/utt2spk > $tmpdir/spk2utt || exit 1;

# Copy stuff into its final locations [this has been moved from the format_data
# script]
mkdir -p $dir
#for f in spk2utt utt2spk utt2spk_stm wav.scp text segments reco2file_and_channel; do
for f in spk2utt utt2spk wav.scp text segments reco2file_and_channel; do
  cp $tmpdir/$f $dir/$f || exit 1;
done

#local/convert2stm.pl $dir utt2spk_stm > $dir/stm
#cp local/english.glm $dir/glm

utils/validate_data_dir.sh --no-feats $dir

echo AMI $DSET scenario and $SET set data preparation succeeded.

