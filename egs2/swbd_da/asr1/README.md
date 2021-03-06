<!-- Generated by scripts/utils/show_asr_result.sh -->
# RESULTS

## Using Conformer encoder with Hubert pre-encoder, SpecAugment, speed perturbation and 3 context utterances

- ASR config: [conf/tuning/train_asr_conformer_hubert.yaml](conf/tuning/train_asr_conformer_hubert.yaml)
- Pretrained model:
  - Zenodo: https://zenodo.org/record/5817199#.YdQ9_YTMKkA
  - Hugging Face Hub: https://huggingface.co/espnet/akreal_swbd_da_hubert_conformer

|Dataset|Snt|Dialogue Act Classification (%)|
|---|---|---|
|decode_asr_asr_model_valid.loss.ave/test|2379|66.3|
|decode_asr_asr_model_valid.loss.ave/valid|8117|69.5|

## Using Conformer encoder, SpecAugment and speed perturbation

- ASR config: [conf/tuning/train_asr_conformer.yaml](conf/tuning/train_asr_conformer.yaml)

|Dataset|Snt|Dialogue Act Classification (%)|
|---|---|---|
|decode_asr_asr_model_valid.loss.ave/test|2379|52.9|
|decode_asr_asr_model_valid.loss.ave/valid|8117|56.1|

## Using Transformer based encoder-decoder and word token type

- ASR config: [conf/tuning/train_asr_transformer.yaml](conf/tuning/train_asr_transformer.yaml)

|Dataset|Snt|Dialogue Act Classification (%)|
|---|---|---|
|decode_asr_asr_model_valid.acc.best/test|2379|51.9|
|decode_asr_asr_model_valid.acc.best/valid|8117|56.8|

## Using Transformer based encoder-decoder with `bert-base-cased` NLU post-encoder and word token type

- ASR config: [conf/tuning/train_asr_transformer_postencoder.yaml](conf/tuning/train_asr_transformer_postencoder.yaml)

|Dataset|Snt|Dialogue Act Classification (%)|
|---|---|---|
|decode_asr_asr_model_valid.acc.best/test|2379|35.9|
|decode_asr_asr_model_valid.acc.best/valid|8117|39.4|
