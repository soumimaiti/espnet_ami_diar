#!/usr/bin/env bash

# Set bash to 'debug' mode, it will exit on :
# -e 'error', -u 'undefined variable', -o ... 'error in pipeline', -x 'print commands',
#set -evx
set -u
set -o pipefail

log() {
    local fname=${BASH_SOURCE[1]##*/}
    echo -e "$(date '+%Y-%m-%dT%H:%M:%S') (${fname}:${BASH_LINENO[0]}:${FUNCNAME[1]}) $*"
}
stage=0
stop_stage=10
SECONDS=0 #TODO: NEEDED?

# You may set 'mic' to:
#  ihm [individual headset mic- the default which gives best results]
#  sdm1 [single distant microphone- the current script allows you only to select
#        the 1st of 8 microphones]
#  mdm8 [multiple distant microphones-- currently we only support averaging over
#       the 8 source microphones].
# ... by calling run.sh as, for example,
# ./run.sh --mic sdm1
# ./run.sh --mic mdm8
mic=sdm1

log "$0 $*"
. utils/parse_options.sh

. ./path.sh || exit 1;
. ./cmd.sh || exit 1;
. ./db.sh || exit 1;

if [ -z "${AMI}" ]; then
    echo $AMI
    log "Fill the value of 'AMI' of db.sh"
    exit 1
fi

base_mic=${mic//[0-9]/} # sdm, ihm or mdm
nmics=${mic//[a-z]/} # e.g. 8 for mdm8.

log "data preparation started"

if [ ${stage} -le 1 ] && [ ${stop_stage} -ge 1 ]; then
    log "data stage 1: Data Download"
    if [ -d ${AMI} ] && ! touch ${AMI}/.foo 2>/dev/null; then
        log "$0: directory $AMI seems to exist and not be owned by you."
        log " ... Assuming the data does not need to be downloaded.  Please use --stage 2."
        exit 1
    fi

    if [ -e data/local/downloads/wget_${mic}.sh ]; then
        log "data/local/downloads/wget_$mic.sh already exists, better quit than re-download... (use --stage N)"
        #exit 1
    fi
    
    if [ ! -d data/local/downloads ]; then
        local/ami_download.sh ${mic} ${AMI}
    fi
fi

if [ ${stage} -le 2 ] && [ ${stop_stage} -ge 2 ]; then
    ### Task dependent. You have to make data the following preparation part by yourself.
    ### But you can utilize Kaldi recipes in most cases
    log "data stage 2: Data preparation"
    
    if [ ! -f data/local/annotations/train.txt ]; then
        local/ami_text_prep.sh data/local/downloads ${AMI} ${base_mic}
    fi
    
    # beamforming
    if [ "$base_mic" == "mdm" ]; then
        PROCESSED_AMI_DIR=${PWD}/beamformed
        ! hash BeamformIt && log "Missing BeamformIt, run 'cd ../../../tools; installers/install_beamformit.sh; cd -;'" && exit 1
        local/ami_beamform.sh --cmd "${train_cmd}" --nj 20 ${nmics} ${AMI} ${PROCESSED_AMI_DIR}
    else
        PROCESSED_AMI_DIR=${AMI}
    fi

    
    local/ami_${base_mic}_data_prep.sh ${AMI} ${mic}
    
    
    local/ami_${base_mic}_scoring_data_prep.sh ${PROCESSED_AMI_DIR} ${mic} dev
    
    local/ami_${base_mic}_scoring_data_prep.sh ${PROCESSED_AMI_DIR} ${mic} eval
    for dset in train dev eval; do
        utils/copy_data_dir.sh data/${mic}/${dset}_orig data/${mic}_${dset}
        rm -r data/${mic}/${dset}_orig
    done
fi

log "Successfully finished. [elapsed=${SECONDS}s]"
