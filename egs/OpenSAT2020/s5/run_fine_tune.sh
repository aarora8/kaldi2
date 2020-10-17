#!/bin/bash

. ./cmd.sh
. ./path.sh

# Train systems,
nj=30 # number of parallel jobs,
stage=0
. utils/parse_options.sh

base_mic=$(echo $mic | sed 's/[0-9]//g') # sdm, ihm or mdm
nmics=$(echo $mic | sed 's/[a-z]//g') # e.g. 8 for mdm8.

set -euo pipefail
opensat_corpora=/export/corpora5/opensat_corpora
SAFE_T_AUDIO_R20=/export/corpora5/opensat_corpora/LDC2020E10
SAFE_T_TEXTS_R20=/export/corpora5/opensat_corpora/LDC2020E09
SAFE_T_AUDIO_R11=/export/corpora5/opensat_corpora/LDC2019E37
SAFE_T_TEXTS_R11=/export/corpora5/opensat_corpora/LDC2019E36
SAFE_T_AUDIO_DEV1=/export/corpora5/opensat_corpora/LDC2019E53
SAFE_T_TEXTS_DEV1=/export/corpora5/opensat_corpora/LDC2019E53
SAFE_T_AUDIO_EVAL1=/export/corpora5/opensat_corpora/LDC2020E07
ICSI_DIR=/export/corpora5/LDC/LDC2004S02/meeting_speech/speech
AMI_DIR=/export/corpora5/amicorpus/

if [ $stage -le 0 ]; then
  local/safet_data_prep.sh ${SAFE_T_AUDIO_R11} ${SAFE_T_TEXTS_R11} data/safe_t_r11
  local/safet_data_prep.sh ${SAFE_T_AUDIO_R20} ${SAFE_T_TEXTS_R20} data/safe_t_r20
  local/safet_data_prep.sh ${SAFE_T_AUDIO_DEV1} ${SAFE_T_TEXTS_DEV1} data/safe_t_dev1
  local/safet_data_prep.sh ${SAFE_T_AUDIO_EVAL1} data/safe_t_eval1
fi

if [ $stage -le 1 ]; then
  local/safet_get_cmu_dict.sh
  utils/prepare_lang.sh data/local/dict_nosp '<UNK>' data/local/lang_nosp data/lang_nosp
  utils/validate_lang.pl data/lang_nosp
fi

if [ $stage -le 2 ]; then
  #prepare annotations, note: dict is assumed to exist when this is called
  local/icsi_run_prepare_shared.sh
  local/icsi_ihm_data_prep.sh $ICSI_DIR
  local/icsi_ihm_scoring_data_prep.sh $ICSI_DIR dev
  local/icsi_ihm_scoring_data_prep.sh $ICSI_DIR eval
fi

if [ $stage -le 3 ]; then
  local/ami_text_prep.sh data/local/download
  local/ami_ihm_data_prep.sh $AMI_DIR
  local/ami_ihm_scoring_data_prep.sh $AMI_DIR dev
  local/ami_ihm_scoring_data_prep.sh $AMI_DIR eval
fi

#if [ $stage -le 4 ]; then
#  local/spine_data_prep.sh /export/corpora5/LDC/LDC2000S96  /export/corpora5/LDC/LDC2000T54 data/spine_eval
#  local/spine_data_prep.sh /export/corpora5/LDC/LDC2000S87  /export/corpora5/LDC/LDC2000T49 data/spine_train
#
#  local/spine_data_prep.sh /export/corpora5/LDC/LDC2001S04  /export/corpora5/LDC/LDC2001T05 data/spine2_train1
#  local/spine_data_prep.sh /export/corpora5/LDC/LDC2001S06  /export/corpora5/LDC/LDC2001T07 data/spine2_train2
#  local/spine_data_prep.sh /export/corpora5/LDC/LDC2001S08  /export/corpora5/LDC/LDC2001T09 data/spine2_train3
#
#fi

if [ $stage -le 4 ]; then
  for dset in train dev eval; do
    utils/data/modify_speaker_info.sh --seconds-per-spk-max 30 \
      data/AMI/${dset}_orig data/AMI/$dset
    utils/data/modify_speaker_info.sh --seconds-per-spk-max 30 \
      data/ICSI/${dset}_orig data/ICSI/$dset
  done
fi

if [ $stage -le 5 ]; then
  utils/data/get_reco2dur.sh data/AMI/train
  utils/data/get_reco2dur.sh data/ICSI/train

  utils/data/get_utt2dur.sh data/AMI/train
  utils/data/get_utt2dur.sh data/ICSI/train

  for dataset in AMI ICSI; do
    for split in train dev eval; do
      cat data/$dataset/$split/text | awk '{printf $1""FS;for(i=2; i<=NF; ++i) printf "%s",tolower($i)""FS; print""}'  > data/$dataset/$split/texttmp
      mv data/$dataset/$split/text data/$dataset/$split/textupper
      mv data/$dataset/$split/texttmp data/$dataset/$split/text
    done
  done
fi

if [ $stage -le 6 ]; then
  mkdir -p exp/cleanup_stage_1
  (
    local/safet_cleanup_transcripts.py data/local/lexicon.txt data/safe_t_r11/transcripts data/safe_t_r11/transcripts.clean
    local/safet_cleanup_transcripts.py data/local/lexicon.txt data/safe_t_r20/transcripts data/safe_t_r20/transcripts.clean

    local/safet_cleanup_transcripts.py data/local/lexicon.txt data/spine2_train1/transcripts data/spine2_train1/transcripts.clean
    local/safet_cleanup_transcripts.py data/local/lexicon.txt data/spine2_train2/transcripts data/spine2_train2/transcripts.clean
    local/safet_cleanup_transcripts.py data/local/lexicon.txt data/spine2_train3/transcripts data/spine2_train3/transcripts.clean
    local/safet_cleanup_transcripts.py data/local/lexicon.txt data/spine_train/transcripts   data/spine_train//transcripts.clean
  ) | sort > exp/cleanup_stage_1/oovs

  local/safet_cleanup_transcripts.py --no-unk-replace  data/local/lexicon.txt \
    data/safe_t_dev1/transcripts data/safe_t_dev1/transcripts.clean > exp/cleanup_stage_1/oovs.dev1
  local/safet_cleanup_transcripts.py  --no-unk-replace  data/local/lexicon.txt \
    data/spine_eval/transcripts data/spine_eval/transcripts.clean > exp/cleanup_stage_1/oovs.spine_eval

  local/safet_build_data_dir.sh data/safe_t_r11/ data/safe_t_r11/transcripts.clean
  local/safet_build_data_dir.sh data/safe_t_r20/ data/safe_t_r20/transcripts.clean
  local/safet_build_data_dir.sh data/safe_t_dev1/ data/safe_t_dev1/transcripts

  local/safet_build_data_dir.sh data/spine2_train1/ data/spine2_train1/transcripts.clean
  local/safet_build_data_dir.sh data/spine2_train2/ data/spine2_train2/transcripts.clean
  local/safet_build_data_dir.sh data/spine2_train3/ data/spine2_train3/transcripts.clean
  local/safet_build_data_dir.sh data/spine_train/ data/spine_train/transcripts.clean
  local/safet_build_data_dir.sh data/spine_eval/ data/spine_eval/transcripts.clean

  utils/data/combine_data.sh data/train_safet data/safe_t_r20 data/safe_t_r11
fi

if [ $stage -le 7 ] ; then
  local/safet_train_lms_srilm.sh \
    --train_text data/train/text --dev_text data/safe_t_dev1/text  \
    data/ data/local/srilm
  utils/format_lm.sh  data/lang_nosp/ data/local/srilm/lm.gz\
    data/local/lexicon.txt  data/lang_nosp_test
fi

suffix=icsiami
if [ $stage -le 8 ] ; then
  utils/data/combine_data.sh data/train_$suffix data/AMI/train data/ICSI/train
fi
# Feature extraction,
if [ $stage -le 9 ]; then
  steps/make_mfcc.sh --nj 200 --cmd "$train_cmd" data/train_$suffix
  steps/compute_cmvn_stats.sh data/train_$suffix
  utils/fix_data_dir.sh data/train_$suffix
fi

# monophone training
if [ $stage -le 10 ]; then
  utils/subset_data_dir.sh data/train_$suffix 15000 data/train_15k
  steps/train_mono.sh --nj $nj --cmd "$train_cmd" \
    data/train_15k data/lang_nosp_test exp/mono
  steps/align_si.sh --nj $nj --cmd "$train_cmd" \
    data/train_$suffix data/lang_nosp_test exp/mono exp/mono_ali
fi

# context-dep. training with delta features.
if [ $stage -le 11 ]; then
  steps/train_deltas.sh --cmd "$train_cmd" \
    5000 80000 data/train_$suffix data/lang_nosp_test exp/mono_ali exp/tri1
  steps/align_si.sh --nj $nj --cmd "$train_cmd" \
    data/train_$suffix data/lang_nosp_test exp/tri1 exp/tri1_ali
fi

if [ $stage -le 12 ]; then
  steps/train_lda_mllt.sh --cmd "$train_cmd" \
    --splice-opts "--left-context=3 --right-context=3" \
    5000 80000 data/train_$suffix data/lang_nosp_test exp/tri1_ali exp/tri2
  steps/align_fmllr.sh --nj $nj --cmd "$train_cmd" \
    data/train_$suffix data/lang_nosp_test exp/tri2 exp/tri2_ali
fi

if [ $stage -le 13 ]; then
  steps/train_sat.sh --cmd "$train_cmd" \
    5000 80000 data/train_$suffix data/lang_nosp_test exp/tri2_ali exp/tri3
  steps/align_fmllr.sh --nj $nj --cmd "$train_cmd" \
    data/train_$suffix data/lang_nosp_test exp/tri3 exp/tri3_ali
fi

if [ $stage -le 14 ]; then
  local/nnet3/run_ivector_common.sh
fi

exit 0
