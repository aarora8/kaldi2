#!/usr/bin/env bash
#
# Based mostly on the TED-LIUM and Switchboard recipe
#
# Copyright  2017  Johns Hopkins University (Author: Shinji Watanabe and Yenda Trmal)
# Apache 2.0
#

# Begin configuration section.
nj=96
decode_nj=20
stage=0
nnet_stage=-10
decode_stage=1
decode_only=false
num_data_reps=4
foreground_snrs="20:10:15:5:0"
background_snrs="20:10:15:5:0"
enhancement=gss # gss or beamformit
gss_nj=50

# End configuration section
. ./utils/parse_options.sh

. ./cmd.sh
. ./path.sh

if [ $decode_only == "true" ]; then
  stage=16
fi

set -e # exit on error

# chime5 main directory path
# please change the path accordingly
chime5_corpus=/export/corpora5/CHiME5
# chime6 data directories, which are generated from ${chime5_corpus},
# to synchronize audio files across arrays and modify the annotation (JSON) file accordingly
chime6_corpus=${PWD}/CHiME6
json_dir=${chime6_corpus}/transcriptions
audio_dir=${chime6_corpus}/audio
enhanced_dir=enhanced
enhanced_dir=${enhanced_dir}_multiarray
enhancement=${enhancement}

test_sets="eval_${enhancement}"
train_set=train_worn_simu_u400k
ICSI_DIR=/export/corpora5/LDC/LDC2004S02/meeting_speech/speech
AMI_DIR=/export/corpora5/amicorpus/
if [ $stage -le 1 ]; then
  echo "$0:  prepare data..."
  for dataset in train dev; do
    for mictype in worn; do
      local/prepare_data.sh --mictype ${mictype} \
			    ${audio_dir}/${dataset} ${json_dir}/${dataset} \
			    data/${dataset}_${mictype}
    done
  done
fi

if [ $stage -le 2 ]; then
  utils/copy_data_dir.sh data/train_worn data/train_worn_org
  grep -v -e "^P11_S03" -e "^P52_S19" -e "^P53_S24" -e "^P54_S24" data/train_worn_org/text > data/train_worn/text
  utils/fix_data_dir.sh data/train_worn
fi

if [ $stage -le 3 ]; then
  local/prepare_data.sh --mictype gss ${enhanced_dir}/audio/train ${json_dir}/train data/train_${enhancement}
fi

if [ $stage -le 4 ]; then
  utils/combine_data.sh data/${train_set} data/train_worn data/train_gss
  for dset in train dev; do
    utils/copy_data_dir.sh data/${dset}_worn data/${dset}_worn_stereo
    grep "\.L-" data/${dset}_worn_stereo/text > data/${dset}_worn/text
    utils/fix_data_dir.sh data/${dset}_worn
  done
fi

if [ $stage -le 5 ]; then
  echo "$0:  train lm ..."
  local/prepare_dict.sh data/local/dict_nosp

  utils/prepare_lang.sh \
    data/local/dict_nosp "<unk>" data/local/lang_nosp data/lang_nosp

  local/train_lms_srilm.sh \
    --train-text data/train_worn/text --dev-text data/dev_worn/text \
    --oov-symbol "<unk>" --words-file data/lang_nosp/words.txt \
    data/ data/srilm
fi

if [ $stage -le 6 ]; then
  for dset in ${train_set}; do
    utils/copy_data_dir.sh data/${dset} data/${dset}_nosplit
    utils/data/modify_speaker_info.sh --seconds-per-spk-max 180 data/${dset}_nosplit data/${dset}
  done
fi

if [ $stage -le 7 ]; then
  #local/icsi_run_prepare_shared.sh
  local/icsi_ihm_data_prep.sh $ICSI_DIR
  local/icsi_ihm_scoring_data_prep.sh $ICSI_DIR dev
  local/icsi_ihm_scoring_data_prep.sh $ICSI_DIR eval
fi

if [ $stage -le 8 ]; then
  local/ami_text_prep.sh data/local/download
  local/ami_ihm_data_prep.sh $AMI_DIR
  local/ami_ihm_scoring_data_prep.sh $AMI_DIR dev
  local/ami_ihm_scoring_data_prep.sh $AMI_DIR eval
fi

if [ $stage -le 9 ]; then
  for dset in train dev eval; do
    utils/data/modify_speaker_info.sh --seconds-per-spk-max 30 \
      data/AMI/${dset}_orig data/AMI/$dset
    utils/data/modify_speaker_info.sh --seconds-per-spk-max 30 \
      data/ICSI/${dset}_orig data/ICSI/$dset
  done
fi

if [ $stage -le 10 ]; then
  utils/data/get_reco2dur.sh data/AMI/train
  utils/data/get_reco2dur.sh data/AMI/train

  utils/data/get_utt2dur.sh data/ICSI/train
  utils/data/get_utt2dur.sh data/ICSI/train

  for dataset in AMI ICSI; do
    for split in train dev eval; do
      cat data/$dataset/$split/text | awk '{printf $1""FS;for(i=2; i<=NF; ++i) printf "%s",tolower($i)""FS; print""}'  > data/$dataset/$split/texttmp
      mv data/$dataset/$split/text data/$dataset/$split/textupper
      mv data/$dataset/$split/texttmp data/$dataset/$split/text
    done
  done
fi

if [ $stage -le 11 ] ; then
  utils/data/combine_data.sh data/train_all data/${train_set} data/AMI/train data/ICSI/train
fi
exit
# Feature extraction,
if [ $stage -le 13 ]; then
  steps/make_mfcc.sh --nj 75 --cmd "$train_cmd" data/train_all
  steps/compute_cmvn_stats.sh data/train_all
  utils/fix_data_dir.sh data/train_all
fi

if [ $stage -le 14 ]; then
  # Now make MFCC features.
  # mfccdir should be some place with a largish disk where you
  # want to store MFCC features.
  echo "$0:  make features..."
  for x in ${train_set}; do
    steps/make_mfcc.sh --nj 20 --cmd "$train_cmd" data/$x
    steps/compute_cmvn_stats.sh data/$x
    utils/fix_data_dir.sh data/$x
  done
fi

###################################################################################
# Stages 8 to 13 train monophone and triphone models. They will be used for
# generating lattices for training the chain model
###################################################################################

if [ $stage -le 8 ]; then
  # make a subset for monophone training
  utils/subset_data_dir.sh --shortest data/${train_set} 100000 data/${train_set}_100kshort
  utils/subset_data_dir.sh data/${train_set}_100kshort 30000 data/${train_set}_30kshort
fi

if [ $stage -le 9 ]; then
  # Starting basic training on MFCC features
  steps/train_mono.sh --nj $nj --cmd "$train_cmd" \
		      data/${train_set}_30kshort data/lang_nosp exp/mono
fi

if [ $stage -le 10 ]; then
  steps/align_si.sh --nj $nj --cmd "$train_cmd" \
		    data/${train_set} data/lang_nosp exp/mono exp/mono_ali

  steps/train_deltas.sh --cmd "$train_cmd" \
			2500 30000 data/${train_set} data/lang_nosp exp/mono_ali exp/tri1
fi

if [ $stage -le 11 ]; then
  steps/align_si.sh --nj $nj --cmd "$train_cmd" \
		    data/${train_set} data/lang_nosp exp/tri1 exp/tri1_ali

  steps/train_lda_mllt.sh --cmd "$train_cmd" \
			  4000 50000 data/${train_set} data/lang_nosp exp/tri1_ali exp/tri2
fi

LM=data/srilm/best_3gram.gz
if [ $stage -le 12 ]; then
  # Now we compute the pronunciation and silence probabilities from training data,
  # and re-create the lang directory.
  steps/get_prons.sh --cmd "$train_cmd" data/${train_set} data/lang_nosp exp/tri2
  utils/dict_dir_add_pronprobs.sh --max-normalize true \
    data/local/dict_nosp exp/tri2/pron_counts_nowb.txt \
    exp/tri2/sil_counts_nowb.txt \
    exp/tri2/pron_bigram_counts_nowb.txt data/local/dict

  echo "$0:  prepare new lang with pronunciation and silence modeling..."
  utils/prepare_lang.sh data/local/dict "<unk>" data/local/lang data/lang_tmp
  # Compiles G for chime6 trigram LM (since we use data/lang for decoding also,
  # we need to generate G.fst in data/lang)
  utils/format_lm.sh \
		data/lang_tmp $LM data/local/dict_nosp/lexicon.txt data/lang
fi

if [ $stage -le 13 ]; then
  steps/align_si.sh --nj $nj --cmd "$train_cmd" \
		    data/${train_set} data/lang exp/tri2 exp/tri2_ali

  steps/train_sat.sh --cmd "$train_cmd" \
		     5000 100000 data/${train_set} data/lang exp/tri2_ali exp/tri3
fi

#######################################################################
# Perform data cleanup for training data.
#######################################################################

if [ $stage -le 14 ]; then
  # The following script cleans the data and produces cleaned data
  steps/cleanup/clean_and_segment_data.sh --nj ${nj} --cmd "$train_cmd" \
    --segmentation-opts "--min-segment-length 0.3 --min-new-segment-length 0.6" \
    data/${train_set} data/lang exp/tri3 exp/tri3_cleaned data/${train_set}_cleaned
fi

##########################################################################
# CHAIN MODEL TRAINING
# skipping decoding here and performing it in step 16
##########################################################################

if [ $stage -le 15 ]; then
  # chain TDNN
  local/chain/run_cnn_tdnn.sh --nj ${nj} \
    --stage 13  --train_stage 11 \
    --train-set ${train_set}_cleaned \
    --test-sets "$test_sets" \
    --gmm tri3_cleaned --nnet3-affix _${train_set}_cleaned_rvb
fi

##########################################################################
# DECODING is done in the local/decode.sh script. This script performs
# enhancement, fixes test sets performs feature extraction and 2 stage decoding
##########################################################################

if [ $stage -le 16 ]; then
  local/decode_small.sh --stage $decode_stage \
    --enhancement $enhancement \
    --train_set "$train_set"
fi

exit 0;
