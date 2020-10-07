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
ICSI_TRANS=/export/corpora3/LDC/LDC2004T04/icsi_mr_transcr
ICSI_DIR=/export/corpora5/LDC/LDC2004S02/meeting_speech/speech
PROCESSED_ICSI_DIR=$ICSI_DIR

if [ $stage -le 0 ]; then
  local/safet_data_prep.sh ${SAFE_T_AUDIO_R11} ${SAFE_T_TEXTS_R11} data/safe_t_r11
  local/safet_data_prep.sh ${SAFE_T_AUDIO_R20} ${SAFE_T_TEXTS_R20} data/safe_t_r20
  local/safet_data_prep.sh ${SAFE_T_AUDIO_DEV1} ${SAFE_T_TEXTS_DEV1} data/safe_t_dev1
  local/safet_data_prep.sh ${SAFE_T_AUDIO_EVAL1} data/safe_t_eval1
fi

if [ $stage -le 1 ]; then
  rm -rf data/lang_nosp data/local/lang_nosp data/local/dict_nosp
  local/safet_get_cmu_dict.sh
  utils/prepare_lang.sh data/local/dict_nosp '<UNK>' data/local/lang_nosp data/lang_nosp
  utils/validate_lang.pl data/lang_nosp
  cp -r data/lang_nosp data/lang
fi
exit
if [ $stage -le 2 ]; then
  #prepare annotations, note: dict is assumed to exist when this is called
  local/icsi_text_prep.sh $ICSI_TRANS data/local/annotations
  local/icsi_${base_mic}_data_prep.sh $PROCESSED_ICSI_DIR $mic
  local/icsi_${base_mic}_scoring_data_prep.sh $PROCESSED_ICSI_DIR $mic dev
  local/icsi_${base_mic}_scoring_data_prep.sh $PROCESSED_ICSI_DIR $mic eval
fi

if [ $stage -le 3 ]; then
  for dset in train dev eval; do
    seconds_per_spk_max=30
    [ "$mic" == "ihm" ] && seconds_per_spk_max=120  # speaker info for ihm is real,
                                                    # so organize into much bigger chunks.
    utils/data/modify_speaker_info.sh --seconds-per-spk-max 30 \
      data/$mic/${dset}_orig data/$mic/$dset
  done
fi

if [ $stage -le 4 ]; then
  utils/data/get_reco2dur.sh data/ihm/train
  utils/data/get_utt2dur.sh data/ihm/train

  for dset in train dev eval; do
    cat data/$mic/$dset/text | awk '{printf $1""FS;for(i=2; i<=NF; ++i) printf "%s",tolower($i)""FS; print""}'  > data/$mic/$dset/texttmp
    mv data/$mic/$dset/text data/$mic/$dset/textupper
    mv data/$mic/$dset/texttmp data/$mic/$dset/text
  done
fi

if [ $stage -le 5 ]; then
  mkdir -p exp/cleanup_stage_1
  (
    local/safet_cleanup_transcripts.py data/local/lexicon.txt data/safe_t_r11/transcripts data/safe_t_r11/transcripts.clean
    local/safet_cleanup_transcripts.py data/local/lexicon.txt data/safe_t_r20/transcripts data/safe_t_r20/transcripts.clean
  ) | sort > exp/cleanup_stage_1/oovs

  local/safet_cleanup_transcripts.py --no-unk-replace  data/local/lexicon.txt \
    data/safe_t_dev1/transcripts data/safe_t_dev1/transcripts.clean > exp/cleanup_stage_1/oovs.dev1
  local/safet_build_data_dir.sh data/safe_t_r11/ data/safe_t_r11/transcripts.clean
  local/safet_build_data_dir.sh data/safe_t_r20/ data/safe_t_r20/transcripts.clean
  local/safet_build_data_dir.sh data/safe_t_dev1/ data/safe_t_dev1/transcripts
  utils/data/combine_data.sh data/train data/safe_t_r20 data/safe_t_r11
fi

if [ $stage -le 6 ] ; then
  local/safet_train_lms_srilm.sh \
    --train_text data/train/text --dev_text data/safe_t_dev1/text  \
    data/ data/local/srilm
  utils/format_lm.sh  data/lang_nosp/ data/local/srilm/lm.gz\
    data/local/lexicon.txt  data/lang_nosp_test
fi

if [ $stage -le 7 ] ; then

#mkdir -p data/train/wav_files
utils/copy_data_dir.sh data/train data/train_safet

#while read -r line;
#  do
#    wav_id=$(echo "$line" | cut -d" " -f 1)
#    wav_path=$(echo "$line" | cut -d" " -f 6)
#    echo $wav_id
#    echo $wav_path
#    flac -s -c -d $wav_path | sox - -b 16 -t wav -r 16000 -c 1 data/train/wav_files/${wav_id}.wav
#done < data/train/wav.scp
#
#rm data/train_safet/wav.scp
#for wav_name in /export/c02/aarora8/kaldi2/egs/icsisafet/s5/data/train/wav_files/*.wav; do
#  recording_id=$(echo "$wav_name" | cut -d"/" -f 12)
#  wav_id=$(echo "$recording_id" | cut -d"." -f 1)
#  echo $wav_id $wav_name >> data/train_safet/wav.scp
#done
fi

if [ $stage -le 8 ]; then
  echo "$0: preparing directory for low-resolution speed-perturbed data (for alignment)"
  utils/data/perturb_data_dir_speed_3way.sh data/train_safet data/train_safet_sp
fi

if [ $stage -le 9 ]; then
  utils/copy_data_dir.sh /export/c02/aarora8/kaldi/egs/ami/s5b/data/ihm/train data/ihm/train_ami
  utils/data/get_reco2dur.sh data/ihm/train_ami
  utils/data/get_utt2dur.sh data/ihm/train_ami
  cat data/$mic/train_ami/text | awk '{printf $1""FS;for(i=2; i<=NF; ++i) printf "%s",tolower($i)""FS; print""}'  > data/$mic/train_ami/texttmp
  mv data/$mic/train_ami/text data/$mic/train_ami/textupper
  mv data/$mic/train_ami/texttmp data/$mic/train_ami/text
fi

if [ $stage -le 10 ] ; then
  utils/data/combine_data.sh data/ihm/train_isa data/train_safet_sp data/ihm/train data/ihm/train_ami
fi

# Feature extraction,
if [ $stage -le 11 ]; then
  for dset in train_isa dev eval; do
    steps/make_mfcc.sh --nj 75 --cmd "$train_cmd" data/$mic/$dset
    steps/compute_cmvn_stats.sh data/$mic/$dset
    utils/fix_data_dir.sh data/$mic/$dset
  done
fi

# monophone training
if [ $stage -le 12 ]; then
  # Full set 77h, reduced set 10.8h,
  utils/subset_data_dir.sh data/$mic/train_isa 15000 data/$mic/train_15k
  steps/train_mono.sh --nj $nj --cmd "$train_cmd" \
    data/$mic/train_15k data/lang exp/$mic/mono
  steps/align_si.sh --nj $nj --cmd "$train_cmd" \
    data/$mic/train_isa data/lang exp/$mic/mono exp/$mic/mono_ali
fi

# context-dep. training with delta features.
if [ $stage -le 13 ]; then
  steps/train_deltas.sh --cmd "$train_cmd" \
    5000 80000 data/$mic/train_isa data/lang exp/$mic/mono_ali exp/$mic/tri1
  steps/align_si.sh --nj $nj --cmd "$train_cmd" \
    data/$mic/train_isa data/lang exp/$mic/tri1 exp/$mic/tri1_ali
fi

if [ $stage -le 14 ]; then
  # LDA_MLLT
  steps/train_lda_mllt.sh --cmd "$train_cmd" \
    --splice-opts "--left-context=3 --right-context=3" \
    5000 80000 data/$mic/train_isa data/lang exp/$mic/tri1_ali exp/$mic/tri2
  steps/align_fmllr.sh --nj $nj --cmd "$train_cmd" \
    data/$mic/train_isa data/lang exp/$mic/tri2 exp/$mic/tri2_ali
fi


if [ $stage -le 15 ]; then
  # LDA+MLLT+SAT
  steps/train_sat.sh --cmd "$train_cmd" \
    5000 80000 data/$mic/train_isa data/lang exp/$mic/tri2_ali exp/$mic/tri3
  steps/align_fmllr.sh --nj $nj --cmd "$train_cmd" \
    data/$mic/train_isa data/lang exp/$mic/tri3 exp/$mic/tri3_ali
fi

LM=data/local/srilm/lm.gz
if [ $stage -le 16 ]; then
  # Now we compute the pronunciation and silence probabilities from training data,
  # and re-create the lang directory.
  steps/get_prons.sh --cmd "$train_cmd" data/$mic/train_isa data/lang_nosp exp/$mic/tri3
  utils/dict_dir_add_pronprobs.sh --max-normalize true \
    data/local/dict_nosp exp/$mic//tri3/pron_counts_nowb.txt \
    exp/$mic/tri3/sil_counts_nowb.txt \
    exp/$mic/tri3/pron_bigram_counts_nowb.txt data/local/dict

  echo "$0:  prepare new lang with pronunciation and silence modeling..."
  utils/prepare_lang.sh data/local/dict "<UNK>" data/local/lang data/lang_tmp
  utils/format_lm.sh \
    data/lang_tmp $LM data/local/dict/lexicon.txt data/lang_test
fi


if [ $stage -le 17 ]; then
  ### Triphone + LDA and MLLT + SAT and FMLLR
  echo "Starting SAT+FMLLR training."
  steps/train_sat.sh --cmd "$train_cmd" 5000 80000 \
      data/$mic/train_isa data/lang_test exp/$mic/tri3_ali exp/$mic/tri4
  echo "SAT+FMLLR training done."
fi

if [ $stage -le 18 ]; then
  echo "For ICSI we do not clean segmentations, as those are manual by default, so should be OK."
  utils/data/combine_data.sh data/ihm/train_icsiami data/ihm/train data/ihm/train_ami

  utils/copy_data_dir.sh /export/c12/aarora8/OpenSAT/safet_noise_wavfile/ data/safet_noise_wavfile
  steps/make_mfcc.sh --cmd "$train_cmd" --nj 80 data/safet_noise_wavfile
  steps/compute_cmvn_stats.sh data/safet_noise_wavfile
  sid/compute_vad_decision.sh --nj 40 --cmd "$train_cmd" data/safet_noise_wavfile
  copy-vector --binary=false scp:data/safet_noise_wavfile/vad.scp ark,t:data/safet_noise_wavfile/vad.txt
  local/get_percent_overlap.py data/safet_noise_wavfile > data/safet_noise_wavfile/percentage_speech
  #rm data/safet_noise_wavfile/filtered_noises
  while read -r line;
  do
    percentage_speech=$(echo "$line" | cut -d" " -f 2)
    uttid=$(echo "$line" | cut -d" " -f 1)
    if [ "$percentage_speech" -gt 80 ]; then
      echo $uttid >> data/safet_noise_wavfile/filtered_noises
    fi
done < data/safet_noise_wavfile/percentage_speech
#sort -k2 -n data/safet_noise_wavfile/filtered_noises > data/safet_noise_wavfile/sorted_filtered_noises
utils/copy_data_dir.sh data/safet_noise_wavfile data/safet_noise_filtered
for f in utt2spk wav.scp feats.scp spk2utt reco2dur cmvn.scp utt2dur utt2num_frames vad.scp; do
  utils/filter_scp.pl data/safet_noise_wavfile/filtered_noises data/safet_noise_wavfile/$f > data/safet_noise_filtered/$f
done
fi

train_set=train_icsiami
aug_list="noise_low noise_high clean"
if [ $stage -le 19 ]; then
  utils/data/get_reco2dur.sh data/ihm/${train_set}
  steps/data/augment_data_dir.py --utt-prefix "noise_low" --modify-spk-id "true" \
    --bg-snrs "10:12:14:16:18" --num-bg-noises "1" --bg-noise-dir "data/safet_noise_filtered" \
    data/$mic/${train_set} data/$mic/${train_set}_noise_low

  steps/data/augment_data_dir.py --utt-prefix "noise_high" --modify-spk-id "true" \
    --bg-snrs "0:2:4:6:8" --num-bg-noises "1" --bg-noise-dir "data/safet_noise_filtered" \
    data/$mic/${train_set} data/$mic/${train_set}_noise_high

  utils/combine_data.sh data/$mic/train_aug data/$mic/${train_set}_noise_low data/$mic/${train_set}_noise_high data/$mic/train_isa
fi


if [ $stage -le 20 ]; then
  # obtain the alignment of augmented data from clean data
  include_original=false
  prefixes=""
  for n in $aug_list; do
    if [ "$n" != "clean" ]; then
      prefixes="$prefixes "$n
    else
      # The original train directory will not have any prefix
      # include_original flag will take care of copying the original alignments
      include_original=true
    fi
  done

  echo "Starting SAT+FMLLR training."
  steps/align_si.sh --nj 30 --cmd "$train_cmd" \
      --use-graphs true data/$mic/train_isa data/lang exp/$mic/tri4 exp/$mic/tri4_train_ali

  echo "$0: Creating alignments of aug data by copying alignments of clean data"
  steps/copy_ali_dir.sh --nj 30 --cmd "$train_cmd" \
    --include-original "$include_original" --prefixes "$prefixes" \
    data/$mic/train_aug exp/$mic/tri4_train_ali exp/$mic/tri4_train_ali_aug
fi

if [ $stage -le 19 ]; then
   for f in data/$mic/${train_set}_noise_low data/$mic/${train_set}_noise_high ; do
    steps/make_mfcc.sh --cmd "$train_cmd" --nj 80 $f
    steps/compute_cmvn_stats.sh $f
  done

  utils/data/combine_data.sh data/$mic/train_aug data/$mic/${train_set}_noise_low data/$mic/${train_set}_noise_high data/$mic/train_isa
  steps/compute_cmvn_stats.sh data/$mic/train_aug
fi

if [ $stage -le 20 ]; then
  for dataset in train_aug; do
    echo "$0: Creating hi resolution MFCCs for dir data/$dataset"
    utils/copy_data_dir.sh data/$mic/$dataset data/$mic/${dataset}_hires
    utils/data/perturb_data_dir_volume.sh data/$mic/${dataset}_hires

    steps/make_mfcc.sh --nj 80 --mfcc-config conf/mfcc_hires.conf \
        --cmd "$train_cmd" data/$mic/${dataset}_hires
    steps/compute_cmvn_stats.sh data/$mic/${dataset}_hires
    utils/fix_data_dir.sh data/$mic/${dataset}_hires;
  done
fi

if [ $stage -le 21 ]; then
  for dataset in safe_t_dev1; do
    echo "$0: Creating hi resolution MFCCs for dir data/$dataset"
    utils/copy_data_dir.sh data/$dataset data/${dataset}_hires
    utils/data/perturb_data_dir_volume.sh data/${dataset}_hires

    steps/make_mfcc.sh --nj 80 --mfcc-config conf/mfcc_hires.conf \
        --cmd "$train_cmd" data/${dataset}_hires
    steps/compute_cmvn_stats.sh data/${dataset}_hires
    utils/fix_data_dir.sh data/${dataset}_hires;
  done
fi
#if [ $stage -le 11 ]; then
#  local/chain/run_tdnn.sh
#fi
exit 0
