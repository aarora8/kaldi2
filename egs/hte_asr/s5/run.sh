#!/bin/bash

. ./cmd.sh
. ./path.sh

# Train systems,
nj=30 # number of parallel jobs,
stage=0
. utils/parse_options.sh
set -euo pipefail

if [ $stage -le 1 ]; then
  mkdir -p data/local
  cp -r /export/common/data/corpora/ASR/IITM_Indian_ASR_Challenge_2021/Indian_Language_Database/English/dictionary/English_lexicon.txt data/local/lexicon.txt
  local/prepare_data.sh
  mv data/train_English_final_hybrid data/train
  mv data/dev_English_jhu data/dev
  local/prepare_dict.sh
  utils/prepare_lang.sh data/local/dict_nosp '<UNK>' data/local/lang_nosp data/lang_nosp_test
  utils/validate_lang.pl data/lang_nosp_test
fi

if [ $stage -le 3 ] ; then
  local/prepare_lm.sh
  utils/format_lm.sh  data/lang_nosp_test data/local/lm/lm.gz \
    data/local/lexicon2.txt  data/lang_nosp_test
fi

# Feature extraction,
if [ $stage -le 4 ]; then
  steps/make_mfcc.sh --nj 75 --cmd "$train_cmd" data/train
  steps/compute_cmvn_stats.sh data/train
  utils/fix_data_dir.sh data/train
fi

# monophone training
if [ $stage -le 5 ]; then
  utils/subset_data_dir.sh data/train 15000 data/train_15k
  steps/train_mono.sh --nj $nj --cmd "$train_cmd" \
    data/train data/lang_nosp_test exp/mono_train
  steps/align_si.sh --nj $nj --cmd "$train_cmd" \
    data/train data/lang_nosp_test exp/mono_train exp/mono_train_ali
fi

# context-dep. training with delta features.
if [ $stage -le 6 ]; then
  steps/train_deltas.sh --cmd "$train_cmd" \
    5000 80000 data/train data/lang_nosp_test exp/mono_train_ali exp/tri1_train
  steps/align_si.sh --nj $nj --cmd "$train_cmd" \
    data/train data/lang_nosp_test exp/tri1_train exp/tri1_train_ali
fi

if [ $stage -le 7 ]; then
  steps/train_lda_mllt.sh --cmd "$train_cmd" \
    --splice-opts "--left-context=3 --right-context=3" \
    5000 80000 data/train data/lang_nosp_test exp/tri1_train_ali exp/tri2_train
  steps/align_fmllr.sh --nj $nj --cmd "$train_cmd" \
    data/train data/lang_nosp_test exp/tri2_train exp/tri2_train_ali
fi

if [ $stage -le 8 ]; then
  steps/train_sat.sh --cmd "$train_cmd" \
    5000 80000 data/train data/lang_nosp_test exp/tri2_train_ali exp/tri3_train
  steps/align_fmllr.sh --nj $nj --cmd "$train_cmd" \
    data/train data/lang_nosp_test exp/tri3_train exp/tri3_train_ali
fi

if [ $stage -le 10 ]; then
  echo ============================================================================
  echo "              augmentation, i-vector extraction, and chain model training"
  echo ============================================================================
  local/chain/run_cnn_tdnn_shared.sh
fi

if [ $stage -le 11 ]; then
  local/rnnlm/run_tdnn_lstm_1a.sh
fi
