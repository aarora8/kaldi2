#!/bin/bash
# Copyright (c) 2020, Johns Hopkins University (Jan "Yenda" Trmal<jtrmal@gmail.com>)
# License: Apache 2.0

# Begin configuration section.
stage=0
# End configuration section
. ./utils/parse_options.sh
set -e -o pipefail
set -o nounset                              # Treat unset variables as an error

. ./cmd.sh
. ./path.sh

SAFE_T_AUDIO_R20=/export/corpora/LDC/LDC2020E10
SAFE_T_TEXTS_R20=/export/corpora/LDC/LDC2020E09

SAFE_T_AUDIO_R11=/export/corpora/LDC/LDC2019E37
SAFE_T_TEXTS_R11=/export/corpora/LDC/LDC2019E36

SAFE_T_AUDIO_DEV1=/export/corpora/LDC/LDC2019E53
SAFE_T_TEXTS_DEV1=/export/corpora/LDC/LDC2019E53

SAFE_T_AUDIO_EVAL1=/export/corpora/LDC/LDC2020E07

SSSF_AUDIO=/export/corpora/LDC/LDC2020E08
SSSF_TEXTS=/export/corpora/LDC/LDC2020E08


UNK='<UNK>'
nj=32

local/check_tools.sh || exit 1

if [ $stage -le 0 ]; then
  local/safe_t_data_prep.sh ${SAFE_T_AUDIO_R11} ${SAFE_T_TEXTS_R11} data/safe_t_r11
  local/safe_t_data_prep.sh ${SAFE_T_AUDIO_R20} ${SAFE_T_TEXTS_R20} data/safe_t_r20

  #local/safe_t_data_prep.sh ${SSSF_AUDIO} ${SSSF_TEXTS} data/sssf

  local/safe_t_data_prep.sh ${SAFE_T_AUDIO_DEV1} ${SAFE_T_TEXTS_DEV1} data/safe_t_dev1

  local/safe_t_data_prep.sh ${SAFE_T_AUDIO_EVAL1} data/safe_t_eval1

  #local/safe_t_data_prep.sh ${SAFE_T_EVAL2_AUDIO} data/safe_t_eval2


  # we will need dev and test splits -- apparently they won't be provided
  # lexicon is cmudict
  # LM from SAFE_T + some additional?
fi

if [ $stage -le 1 ]; then
  rm -rf data/lang data/local/lang data/local/dict
  local/get_cmu_dict.sh
  utils/prepare_lang.sh data/local/dict '<UNK>' data/local/lang data/lang
  utils/validate_lang.pl data/lang
  #true
fi

if [ $stage -le 2 ]; then
  mkdir -p exp/cleanup_stage_1
  (
    local/cleanup_transcripts.py data/local/lexicon.txt data/safe_t_r11/transcripts data/safe_t_r11/transcripts.clean
    local/cleanup_transcripts.py data/local/lexicon.txt data/safe_t_r20/transcripts data/safe_t_r20/transcripts.clean
  ) | sort > exp/cleanup_stage_1/oovs

  # avoid adding the dev OOVs to lexicon!
  local/cleanup_transcripts.py  --no-unk-replace  data/local/lexicon.txt \
    data/safe_t_dev1/transcripts data/safe_t_dev1/transcripts.clean > exp/cleanup_stage_1/oovs.dev1

  local/build_data_dir.sh data/safe_t_r11/ data/safe_t_r11/transcripts.clean
  local/build_data_dir.sh data/safe_t_r20/ data/safe_t_r20/transcripts.clean
  local/build_data_dir.sh data/safe_t_dev1/ data/safe_t_dev1/transcripts
fi

if [ $stage -le 3 ]; then
  for f in data/safe_t_dev1 data/safe_t_r20 data/safe_t_r11 ; do
    steps/make_mfcc.sh --cmd "$train_cmd" --nj $nj $f
    steps/compute_cmvn_stats.sh $f
  done
  cp -r data/safe_t_dev1 data/dev
fi

if [ $stage -le 4 ] ; then
  utils/data/combine_data.sh data/train data/safe_t_r20 data/safe_t_r11
  steps/compute_cmvn_stats.sh data/train
fi

if [ $stage -le 5 ]; then
  local/train_lms_srilm.sh \
    --train_text data/train/text --dev_text data/safe_t_dev1/text  \
    data/ data/local/srilm

  utils/format_lm.sh  data/lang_nosp/ data/local/srilm/lm.gz\
    data/local/lexicon.txt  data/lang_test
fi

if [ $stage -le 6 ] ; then
	utils/subset_data_dir.sh --shortest  data/train 1000 data/train_sub1
fi

if [ $stage -le 7 ] ; then
  echo "Starting triphone training."
  steps/train_mono.sh --nj $nj --cmd "$cmd" data/train_sub1 data/lang exp/mono
  echo "Monophone training done."
fi

nj=32
dev_nj=16
if [ $stage -le 8 ]; then
  ### Triphone
  echo "Starting triphone training."
  steps/align_si.sh --nj $nj --cmd "$cmd" \
      data/train data/lang exp/mono exp/mono_ali
  steps/train_deltas.sh --boost-silence 1.25 --cmd "$cmd"  \
      3200 30000 data/train data/lang exp/mono_ali exp/tri1
  echo "Triphone training done."

  (
    echo "Decoding the dev set using triphone models."
    utils/mkgraph.sh data/lang_test  exp/tri1 exp/tri1/graph
    steps/decode.sh --nj $dev_nj --cmd "$cmd" \
        exp/tri1/graph  data/safe_t_dev1 exp/tri1/decode_dev
    echo "Triphone decoding done."
  ) &
fi

if [ $stage -le 9 ]; then
  ## Triphones + delta delta
  # Training
  echo "Starting (larger) triphone training."
  steps/align_si.sh --nj $nj --cmd "$cmd" --use-graphs true \
       data/train data/lang exp/tri1 exp/tri1_ali
  steps/train_deltas.sh --cmd "$cmd"  \
      4200 40000 data/train data/lang exp/tri1_ali exp/tri2a
  echo "Triphone (large) training done."

  (
    echo "Decoding the dev set using triphone(large) models."
    utils/mkgraph.sh data/lang_test exp/tri2a exp/tri2a/graph
    steps/decode.sh --nj $dev_nj --cmd "$cmd" \
        exp/tri2a/graph data/safe_t_dev1 exp/tri2a/decode_dev
  ) &
fi

if [ $stage -le 10 ]; then
  ### Triphone + LDA and MLLT
  # Training
  echo "Starting LDA+MLLT training."
  steps/align_si.sh --nj $nj --cmd "$cmd"  \
      data/train data/lang exp/tri2a exp/tri2a_ali

  steps/train_lda_mllt.sh --cmd "$cmd"  \
    --splice-opts "--left-context=3 --right-context=3" \
    4200 40000 data/train data/lang exp/tri2a_ali exp/tri2b
  echo "LDA+MLLT training done."

  (
    echo "Decoding the dev set using LDA+MLLT models."
    utils/mkgraph.sh data/lang_test exp/tri2b exp/tri2b/graph
    steps/decode.sh --nj $dev_nj --cmd "$cmd" \
        exp/tri2b/graph data/safe_t_dev1 exp/tri2b/decode_dev
  ) &
fi


if [ $stage -le 11 ]; then
  ### Triphone + LDA and MLLT + SAT and FMLLR
  # Training
  echo "Starting SAT+FMLLR training."
  steps/align_si.sh --nj $nj --cmd "$cmd" \
      --use-graphs true data/train data/lang exp/tri2b exp/tri2b_ali
  steps/train_sat.sh --cmd "$cmd" 4200 40000 \
      data/train data/lang exp/tri2b_ali exp/tri3b
  echo "SAT+FMLLR training done."

  (
    echo "Decoding the dev set using SAT+FMLLR models."
    utils/mkgraph.sh data/lang_test  exp/tri3b exp/tri3b/graph
    steps/decode_fmllr.sh --nj $dev_nj --cmd "$cmd" \
        exp/tri3b/graph  data/safe_t_dev1 exp/tri3b/decode_dev

    echo "SAT+FMLLR decoding done."
  ) &
fi

if [ $stage -le 12 ]; then
  ### Triphone + LDA and MLLT + SAT and FMLLR
  # Training
  echo "Starting SAT+FMLLR training."
  steps/align_si.sh --nj $nj --cmd "$cmd" \
      --use-graphs true data/train data/lang exp/tri3b exp/tri3b_ali
  steps/train_sat.sh --cmd "$cmd" 4500 50000 \
      data/train data/lang exp/tri3b_ali exp/tri4b
  echo "SAT+FMLLR training done."

  (
    echo "Decoding the dev set using SAT+FMLLR models."
    utils/mkgraph.sh data/lang_test  exp/tri4b exp/tri4b/graph
    steps/decode_fmllr.sh --nj $dev_nj --cmd "$cmd" \
        exp/tri4b/graph  data/safe_t_dev1 exp/tri4b/decode_dev

    echo "SAT+FMLLR decoding done."
  ) &
fi

LM=data/local/srilm/lm.gz
if [ $stage -le 12 ]; then
  # Now we compute the pronunciation and silence probabilities from training data,
  # and re-create the lang directory.
  steps/get_prons.sh --cmd "$train_cmd" data/train data/lang exp/tri4b
  utils/dict_dir_add_pronprobs.sh --max-normalize true \
    data/local/dict exp/tri4b/pron_counts_nowb.txt \
    exp/tri4b/sil_counts_nowb.txt \
    exp/tri4b/pron_bigram_counts_nowb.txt data/local/dict_sp

  echo "$0:  prepare new lang with pronunciation and silence modeling..."
  utils/prepare_lang.sh data/local/dict_sp "<unk>" data/local/lang_sp data/lang_tmp
  utils/format_lm.sh \
    data/lang_tmp $LM data/local/dict_nosp/lexicon.txt data/lang_sp_test
fi

if [ $stage -le 12 ]; then
  ### Triphone + LDA and MLLT + SAT and FMLLR
  # Training
  echo "Starting SAT+FMLLR training."
  steps/align_si.sh --nj $nj --cmd "$cmd" \
      --use-graphs true data/train data/lang_sp_test exp/tri4b exp/tri4b_ali
  steps/train_sat.sh --cmd "$cmd" 4500 50000 \
      data/train data/lang_sp_test exp/tri4b_ali exp/tri5b
  echo "SAT+FMLLR training done."

  (
    echo "Decoding the dev set using SAT+FMLLR models."
    utils/mkgraph.sh data/lang_sp_test  exp/tri5b exp/tri5b/graph
    steps/decode_fmllr.sh --nj $dev_nj --cmd "$cmd" \
        exp/tri5b/graph  data/safe_t_dev1 exp/tri5b/decode_dev

    echo "SAT+FMLLR decoding done."
  ) &
fi

if [ $stage -le 13 ]; then
  # this does some data-cleaning.  It actually degrades the GMM-level results
  # slightly, but the cleaned data should be useful when we add the neural net and chain
  # systems.  If not we'll remove this stage.
  local/run_cleanup_segmentation.sh
fi

if [ $stage -le 14 ]; then
  local/chain/run_tdnna.sh --stage 20
fi