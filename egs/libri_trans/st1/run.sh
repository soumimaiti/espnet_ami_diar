#!/usr/bin/env bash

# Copyright 2018 Kyoto University (Hirofumi Inaguma)
#  Apache 2.0  (http://www.apache.org/licenses/LICENSE-2.0)

. ./path.sh || exit 1;
. ./cmd.sh || exit 1;

# general configuration
backend=pytorch
stage=-1        # start from -1 if you need to start from data download
stop_stage=100
ngpu=1          # number of gpus during training ("0" uses cpu, otherwise use gpu)
dec_ngpu=0      # number of gpus during decoding ("0" uses cpu, otherwise use gpu)
nj=16           # number of parallel jobs for decoding
debugmode=1
dumpdir=dump    # directory to dump full features
N=0             # number of minibatches to be used (mainly for debugging). "0" uses all minibatches.
verbose=0       # verbose option
resume=         # Resume the training from snapshot
seed=1          # seed to generate random number
# feature configuration
do_delta=false

preprocess_config=conf/specaug.yaml
train_config=conf/train.yaml
decode_config=conf/decode.yaml

# decoding parameter
trans_model=model.acc.best # set a model to be used for decoding: 'model.acc.best' or 'model.loss.best'

# model average realted (only for transformer)
n_average=5                  # the number of ST models to be averaged
use_valbest_average=true     # if true, the validation `n_average`-best ST models will be averaged.
                             # if false, the last `n_average` ST models will be averaged.
metric=bleu                  # loss/acc/bleu
max_epoch=50                 # for checkpoint selection

# pre-training related
asr_model=
mt_model=

# preprocessing related
src_case=lc.rm
tgt_case=lc
# tc: truecase
# lc: lowercase
# lc.rm: lowercase with punctuation removal

# Set this to somewhere where you want to put your data, or where
# someone else has already put it.
datadir=/n/rd8/libri_trans/
# libri_trans
#  |_ train/
#  |_ other/
#  |_ dev/
#  |_ test/
# Download data from here:
# https://persyval-platform.univ-grenoble-alpes.fr/DS91/detaildataset

# bpemode (unigram or bpe)
nbpe=1000
bpemode=bpe
# NOTE: nbpe=97 means character-level ST (lc.rm)
# NOTE: nbpe=111 means character-level ST (lc)
# NOTE: nbpe=152 means character-level ST (tc)

# exp tag
tag="" # tag for managing experiments.

. utils/parse_options.sh || exit 1;

# Set bash to 'debug' mode, it will exit on :
# -e 'error', -u 'undefined variable', -o ... 'error in pipeline', -x 'print commands',
set -e
set -u
set -o pipefail

train_set=train_sp.fr
train_set_prefix=train_sp
train_dev=train_dev.fr
trans_set="dev.fr test.fr"

if [ ${stage} -le 0 ] && [ ${stop_stage} -ge 0 ]; then
    ### Task dependent. You have to make data the following preparation part by yourself.
    ### But you can utilize Kaldi recipes in most cases
    echo "stage 0: Data Preparation"
    for x in dev test train other; do
        local/data_prep.sh ${datadir}/${x} data/${x}
    done
fi

feat_tr_dir=${dumpdir}/${train_set}/delta${do_delta}; mkdir -p ${feat_tr_dir}
feat_dt_dir=${dumpdir}/${train_dev}/delta${do_delta}; mkdir -p ${feat_dt_dir}
if [ ${stage} -le 1 ] && [ ${stop_stage} -ge 1 ]; then
    ### Task dependent. You have to design training and dev sets by yourself.
    ### But you can utilize Kaldi recipes in most cases
    echo "stage 1: Feature Generation"
    fbankdir=fbank
    # Generate the fbank features; by default 80-dimensional fbanks with pitch on each frame
    for x in dev test; do
        steps/make_fbank_pitch.sh --cmd "$train_cmd" --nj 32 --write_utt2num_frames true \
            data/${x} exp/make_fbank/${x} ${fbankdir}
    done

    # speed perturbation
    speed_perturb.sh --cmd "$train_cmd" --cases "lc.rm lc tc" --langs "en fr fr.gtranslate" data/train data/train_sp ${fbankdir}

    # Divide into En Fr, Fr (google trans)
    for x in ${train_set_prefix} dev test; do
        divide_lang.sh ${x} "en fr fr.gtranslate"
    done

    for lang in en fr fr.gtranslate; do
        if [ -d data/train_dev.${lang} ];then
            rm -rf data/train_dev.${lang}
        fi
        cp -rf data/dev.${lang} data/train_dev.${lang}
    done

    # remove long and short utterances
    for x in ${train_set_prefix} train_dev; do
        clean_corpus.sh --maxframes 3000 --maxchars 400 --utt_extra_files "text.tc text.lc text.lc.rm" data/${x} "en fr fr.gtranslate"
    done

    # compute global CMVN
    compute-cmvn-stats scp:data/${train_set}/feats.scp data/${train_set}/cmvn.ark

    # dump features for training
    dump.sh --cmd "$train_cmd" --nj 80 --do_delta $do_delta \
        data/${train_set}/feats.scp data/${train_set}/cmvn.ark exp/dump_feats/${train_set} ${feat_tr_dir}
    for x in ${train_dev} ${trans_set}; do
        feat_trans_dir=${dumpdir}/${x}/delta${do_delta}; mkdir -p ${feat_trans_dir}
        dump.sh --cmd "$train_cmd" --nj 32 --do_delta $do_delta \
            data/${x}/feats.scp data/${train_set}/cmvn.ark exp/dump_feats/trans/${x} ${feat_trans_dir}
    done
fi

dict=data/lang_1spm/${train_set}_${bpemode}${nbpe}_units_${tgt_case}.txt
nlsyms=data/lang_1spm/${train_set}_non_lang_syms_${tgt_case}.txt
bpemodel=data/lang_1spm/${train_set}_${bpemode}${nbpe}_${tgt_case}
echo "dictionary: ${dict}"
if [ ${stage} -le 2 ] && [ ${stop_stage} -ge 2 ]; then
    ### Task dependent. You have to check non-linguistic symbols used in the corpus.
    echo "stage 2: Dictionary and Json Data Preparation"
    mkdir -p data/lang_1spm/

    echo "make a non-linguistic symbol list for all languages"
    grep sp1.0 data/${train_set_prefix}.*/text.${tgt_case} | cut -f 2- -d' ' | grep -o -P '&[^;]*;'| sort | uniq > ${nlsyms}
    cat ${nlsyms}

    echo "make a joint source and target dictionary"
    echo "<unk> 1" > ${dict} # <unk> must be 1, 0 will be used for "blank" in CTC
    offset=$(wc -l < ${dict})
    grep sp1.0 data/${train_set_prefix}.*/text.${tgt_case} | cut -f 2- -d' ' | grep -v -e '^\s*$' > data/lang_1spm/input_${src_case}_${tgt_case}.txt
    spm_train --user_defined_symbols="$(tr "\n" "," < ${nlsyms})" --input=data/lang_1spm/input_${src_case}_${tgt_case}.txt \
        --vocab_size=${nbpe} --model_type=${bpemode} --model_prefix=${bpemodel} --input_sentence_size=100000000 --character_coverage=1.0
    spm_encode --model=${bpemodel}.model --output_format=piece < data/lang_1spm/input_${src_case}_${tgt_case}.txt \
        | tr ' ' '\n' | sort | uniq | awk -v offset=${offset} '{print $0 " " NR+offset}' >> ${dict}
    wc -l ${dict}

    echo "make json files"
    for x in /${train_set} ${train_dev} ${trans_set}; do
        feat_trans_dir=${dumpdir}/${x}/delta${do_delta}
        data2json.sh --nj 16 --feat ${feat_trans_dir}/feats.scp --text data/${x}/text.${tgt_case} --bpecode ${bpemodel}.model --lang "fr" \
            data/${x} ${dict} > ${feat_trans_dir}/data_${bpemode}${nbpe}.${src_case}_${tgt_case}.json
    done
    data2json.sh --nj 16 --feat ${feat_tr_dir}/feats.scp --text data/${train_set_prefix}.fr.gtranslate/text.${tgt_case} --bpecode ${bpemodel}.model --lang "fr" \
        data/${train_set_prefix}.fr.gtranslate ${dict} > ${feat_tr_dir}/data_gtranslate${bpemode}${nbpe}.${src_case}_${tgt_case}.json

    # update json (add source references)
    update_json.sh --text data/"$(echo ${train_set} | cut -f 1 -d ".")".en/text.${src_case} --bpecode ${bpemodel}.model \
        ${feat_tr_dir}/data_${bpemode}${nbpe}.${src_case}_${tgt_case}.json data/"$(echo ${train_set} | cut -f 1 -d ".")".en ${dict}
    update_json.sh --text data/"$(echo ${train_set} | cut -f 1 -d ".")".en/text.${src_case} --bpecode ${bpemodel}.model \
        ${feat_tr_dir}/data_gtranslate${bpemode}${nbpe}.${src_case}_${tgt_case}.json data/"$(echo ${train_set} | cut -f 1 -d ".")".en ${dict}
    update_json.sh --text data/"$(echo ${train_dev} | cut -f 1 -d ".")".en/text.${src_case} --bpecode ${bpemodel}.model \
        ${feat_dt_dir}/data_${bpemode}${nbpe}.${src_case}_${tgt_case}.json data/"$(echo ${train_dev} | cut -f 1 -d ".")".en ${dict}

    # concatenate Fr and Fr (Google translation) jsons
    concat_json_multiref.py \
        ${feat_tr_dir}/data_${bpemode}${nbpe}.${src_case}_${tgt_case}.json \
        ${feat_tr_dir}/data_gtranslate${bpemode}${nbpe}.${src_case}_${tgt_case}.json \
        > ${feat_tr_dir}/data_2ref_${bpemode}${nbpe}.${src_case}_${tgt_case}.json
fi

# NOTE: skip stage 3: LM Preparation

if [ -z ${tag} ]; then
    expname=${train_set}_${tgt_case}_${backend}_$(basename ${train_config%.*})_${bpemode}${nbpe}
    if ${do_delta}; then
        expname=${expname}_delta
    fi
    if [ -n "${preprocess_config}" ]; then
        expname=${expname}_$(basename ${preprocess_config%.*})
    fi
    if [ -n "${asr_model}" ]; then
        expname=${expname}_asrtrans
    fi
    if [ -n "${mt_model}" ]; then
        expname=${expname}_mttrans
    fi
else
    expname=${train_set}_${tgt_case}_${backend}_${tag}
fi
expdir=exp/${expname}
mkdir -p ${expdir}

if [ ${stage} -le 4 ] && [ ${stop_stage} -ge 4 ]; then
    echo "stage 4: Network Training"

    ${cuda_cmd} --gpu ${ngpu} ${expdir}/train.log \
        st_train.py \
        --config ${train_config} \
        --preprocess-conf ${preprocess_config} \
        --ngpu ${ngpu} \
        --backend ${backend} \
        --outdir ${expdir}/results \
        --tensorboard-dir tensorboard/${expname} \
        --debugmode ${debugmode} \
        --dict ${dict} \
        --debugdir ${expdir} \
        --minibatches ${N} \
        --seed ${seed} \
        --verbose ${verbose} \
        --resume ${resume} \
        --train-json ${feat_tr_dir}/data_2ref_${bpemode}${nbpe}.${src_case}_${tgt_case}.json \
        --valid-json ${feat_dt_dir}/data_${bpemode}${nbpe}.${src_case}_${tgt_case}.json \
        --enc-init ${asr_model} \
        --dec-init ${mt_model} \
        --n-iter-processes 2
fi

if [ ${stage} -le 5 ] && [ ${stop_stage} -ge 5 ]; then
    echo "stage 5: Decoding"
    if [[ $(get_yaml.py ${train_config} model-module) = *transformer* ]] || \
       [[ $(get_yaml.py ${train_config} model-module) = *conformer* ]]; then
        # Average ST models
        if ${use_valbest_average}; then
            trans_model=model.val${n_average}.avg.best
            opt="--log ${expdir}/results/log --metric ${metric}"
        else
            trans_model=model.last${n_average}.avg.best
            opt="--log"
        fi
        average_checkpoints.py \
            ${opt} \
            --backend ${backend} \
            --snapshots ${expdir}/results/snapshot.ep.* \
            --out ${expdir}/results/${trans_model} \
            --num ${n_average} \
            --max-epoch ${max_epoch}
    fi

    if [ ${dec_ngpu} = 1 ]; then
        nj=1
    fi

    pids=() # initialize pids
    for x in ${trans_set}; do
    (
        decode_dir=decode_${x}_$(basename ${decode_config%.*})
        feat_trans_dir=${dumpdir}/${x}/delta${do_delta}

        # reset log for RTF calculation
        if [ -f ${expdir}/${decode_dir}/log/decode.1.log ]; then
            rm ${expdir}/${decode_dir}/log/decode.*.log
        fi

        # split data
        splitjson.py --parts ${nj} ${feat_trans_dir}/data_${bpemode}${nbpe}.${src_case}_${tgt_case}.json

        ${decode_cmd} JOB=1:${nj} ${expdir}/${decode_dir}/log/decode.JOB.log \
            st_trans.py \
            --config ${decode_config} \
            --ngpu ${dec_ngpu} \
            --backend ${backend} \
            --batchsize 0 \
            --trans-json ${feat_trans_dir}/split${nj}utt/data_${bpemode}${nbpe}.JOB.json \
            --result-label ${expdir}/${decode_dir}/data.JOB.json \
            --model ${expdir}/results/${trans_model}

        score_bleu.sh --case ${tgt_case} --bpemodel ${bpemodel}.model \
            ${expdir}/${decode_dir} "fr" ${dict}

        calculate_rtf.py --log-dir ${expdir}/${decode_dir}/log
    ) &
    pids+=($!) # store background pids
    done
    i=0; for pid in "${pids[@]}"; do wait ${pid} || ((++i)); done
    [ ${i} -gt 0 ] && echo "$0: ${i} background jobs are failed." && false
    echo "Finished"
fi
