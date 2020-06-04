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
fi

if [ $stage -le 4 ] ; then
  utils/data/combine_data.sh data/train data/safe_t_r20 data/safe_t_r11
  steps/compute_cmvn_stats.sh data/train
fi

if [ $stage -le 5 ]; then
  local/train_lms_srilm.sh \
    --train_text data/train/text --dev_text data/safe_t_dev1/text  \
    data/ data/local/srilm

  utils/format_lm.sh  data/lang/ data/local/srilm/lm.gz\
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
    steps/decode.sh --nj $dev_nj --cmd "$cmd"  --stage 2 \
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
  steps/train_deltas.sh --cmd "$cmd"  --stage 2 \
      4200 40000 data/train data/lang exp/tri1_ali exp/tri2a
  echo "Triphone (large) training done."

  (
    echo "Decoding the dev set using triphone(large) models."
    utils/mkgraph.sh data/lang_test exp/tri2a exp/tri2a/graph
    steps/decode.sh --nj $dev_nj --cmd "$cmd" --stage 2 \
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
    steps/decode.sh --nj $dev_nj --cmd "$cmd" --stage 2 \
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
    steps/decode_fmllr.sh --nj $dev_nj --cmd "$cmd" --stage 6 \
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
    steps/decode_fmllr.sh --nj $dev_nj --cmd "$cmd" --stage 6 \
        exp/tri4b/graph  data/safe_t_dev1 exp/tri4b/decode_dev

    echo "SAT+FMLLR decoding done."
  ) &
fi

#NB: This does not add more complexity or fanciness... But my personal finding
# in Fearless Steps was that repeating the training helps with getting better
# alignments for DNNs

if [ $stage -le 12 ]; then
  ### Triphone + LDA and MLLT + SAT and FMLLR
  # Training
  echo "Starting SAT+FMLLR training."
  steps/align_si.sh --nj $nj --cmd "$cmd" \
      --use-graphs true data/train data/lang exp/tri4b exp/tri4b_ali
  steps/train_sat.sh --cmd "$cmd" 4500 50000 \
      data/train data/lang exp/tri4b_ali exp/tri5b
  echo "SAT+FMLLR training done."

  (
    echo "Decoding the dev set using SAT+FMLLR models."
    utils/mkgraph.sh data/lang_test  exp/tri5b exp/tri5b/graph
    steps/decode_fmllr.sh --nj $dev_nj --cmd "$cmd" --stage 6 \
        exp/tri5b/graph  data/safe_t_dev1 exp/tri5b/decode_dev

    echo "SAT+FMLLR decoding done."
  ) &
fi

if [ $stage -le 13 ]; then
  ### Triphone + LDA and MLLT + SAT and FMLLR
  # Training
  echo "Starting SAT+FMLLR training."
  steps/align_si.sh --nj $nj --cmd "$cmd" \
      --use-graphs true data/train data/lang exp/tri5b exp/tri5b_ali
fi

train_set=train_sub1
num_reverb_copies=1
aug_list="reverb music noise babble clean"  #clean refers to the original train dir
# Alignment directories
clean_ali=tri5b_${train_set}_ali

if [ $stage -le 14 ]; then
  # Adding simulated RIRs to the original data directory
  echo "$0: Preparing data/${train_set}_reverb directory"

  if [ ! -d "RIRS_NOISES" ]; then
    unzip rirs_noises.zip
  fi

  if [ ! -f data/$train_set/reco2dur ]; then
    utils/data/get_reco2dur.sh --nj 6 --cmd "$train_cmd" data/$train_set || exit 1;
  fi

  # Make a version with reverberated speech
  rvb_opts=()
  rvb_opts+=(--rir-set-parameters "0.5, RIRS_NOISES/simulated_rirs/smallroom/rir_list")
  rvb_opts+=(--rir-set-parameters "0.5, RIRS_NOISES/simulated_rirs/mediumroom/rir_list")

  # Make a reverberated version of the SWBD train_nodup.
  # Note that we don't add any additive noise here.
  steps/data/reverberate_data_dir.py \
    "${rvb_opts[@]}" \
    --speech-rvb-probability 1 \
    --prefix "reverb" \
    --pointsource-noise-addition-probability 0 \
    --isotropic-noise-addition-probability 0 \
    --num-replications $num_reverb_copies \
    --source-sampling-rate 48000 \
    data/$train_set data/${train_set}_reverb
fi

if [ $stage -le 15 ]; then
  # Prepare the MUSAN corpus, which consists of music, speech, and noise
  # We will use them as additive noises for data augmentation.
  steps/data/make_musan.sh --sampling-rate 48000 --use-vocals "true" \
        /export/corpora/JHU/musan data

  # Augment with musan_noise
  steps/data/augment_data_dir.py --utt-prefix "noise" --modify-spk-id "true" \
    --fg-interval 1 --fg-snrs "15:10:5:0" --fg-noise-dir "data/musan_noise" \
    data/${train_set} data/${train_set}_noise

  # Augment with musan_music
  steps/data/augment_data_dir.py --utt-prefix "music" --modify-spk-id "true" \
    --bg-snrs "15:10:8:5" --num-bg-noises "1" --bg-noise-dir "data/musan_music" \
    data/${train_set} data/${train_set}_music

  # Augment with musan_speech
  steps/data/augment_data_dir.py --utt-prefix "babble" --modify-spk-id "true" \
    --bg-snrs "20:17:15:13" --num-bg-noises "3:4:5:6:7" \
    --bg-noise-dir "data/musan_speech" \
    data/${train_set} data/${train_set}_babble

  # Combine all the augmentation dirs
  # This part can be simplified once we know what noise types we will add
  combine_str=""
  for n in $aug_list; do
    if [ "$n" == "clean" ]; then
      # clean refers to original of training directory
      combine_str+="data/$train_set "
    else
      combine_str+="data/${train_set}_${n} "
    fi
  done
  utils/combine_data.sh data/${train_set}_aug $combine_str
fi

if [ $stage -le 16 ]; then
  # Extract low-resolution MFCCs for the augmented data
  # To be used later to generate alignments for augmented data
  echo "$0: Extracting low-resolution MFCCs for the augmented data. Useful for generating alignments"
  if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $mfccdir/storage ]; then
    date=$(date +'%m_%d_%H_%M')
    utils/create_split_dir.pl /export/b0{1,2,3,4}/$USER/kaldi-data/mfcc/swbd-$date/s5c/$mfccdir/storage $mfccdir/storage
  fi
  steps/make_mfcc.sh --cmd "$train_cmd" --nj 50 data/${train_set}_aug
  steps/compute_cmvn_stats.sh data/${train_set}_aug
  utils/fix_data_dir.sh data/${train_set}_aug
fi

if [ $stage -le 17 ]; then
  # obtain the alignment of augmented data from clean data
  include_original=false
  prefixes=""
  for n in $aug_list; do
    if [ "$n" == "reverb" ]; then
      for i in `seq 1 $num_reverb_copies`; do
        prefixes="$prefixes "reverb$i
      done
    elif [ "$n" != "clean" ]; then
      prefixes="$prefixes "$n
    else
      # The original train directory will not have any prefix
      # include_original flag will take care of copying the original alignments
      include_original=true
    fi
  done

  steps/align_si.sh --nj $nj --cmd "$cmd"  \
      data/train data/lang exp/tri2a exp/tri2b_${train_set}_ali

  steps/train_lda_mllt.sh --cmd "$cmd"  \
    --splice-opts "--left-context=3 --right-context=3" \
    4200 40000 data/train data/lang exp/tri2a_ali exp/tri2b
  echo "LDA+MLLT training done."

  echo "Starting SAT+FMLLR training."
  steps/align_si.sh --nj $nj --cmd "$cmd" \
      --use-graphs true data/${train_set} data/lang exp/tri5b exp/tri5b_${train_set}_ali

  echo "$0: Creating alignments of aug data by copying alignments of clean data"
  steps/copy_ali_dir.sh --nj 40 --cmd "$train_cmd" \
    --include-original "$include_original" --prefixes "$prefixes" \
    data/${train_set}_aug exp/${clean_ali} exp/${clean_ali}_aug
fi

if [ $stage -le 18 ]; then
  for dataset in ${train_set}_aug; do
    echo "$0: Creating hi resolution MFCCs for dir data/$dataset"
    utils/copy_data_dir.sh data/$dataset data/${dataset}_hires
    utils/data/perturb_data_dir_volume.sh data/${dataset}_hires

    steps/make_mfcc.sh --nj 70 --mfcc-config conf/mfcc_hires.conf \
        --cmd "$train_cmd" data/${dataset}_hires
    steps/compute_cmvn_stats.sh data/${dataset}_hires
    utils/fix_data_dir.sh data/${dataset}_hires;
  done
fi

if [ $stage -le 19 ]; then
  local/chain/run_tdnn.sh --stage 20
fi

exit
if [ $stage -le 19 ]; then
  local/chain/multi_condition/run_tdnn_aug_1a.sh 
fi

