#!/usr/bin/env bash
# Begin configuration section.
nj=8
stage=0
sad_stage=0
score_sad=true
diarizer_stage=0
decode_diarize_stage=0
score_stage=0

enhancement=beamformit

# training data
train_set=train_worn_simu_u400k
test_sets="dev_${enhancement}_dereverb eval_${enhancement}_dereverb"

. ./utils/parse_options.sh

. ./cmd.sh
. ./path.sh
. ./conf/sad.conf

# This script also needs the phonetisaurus g2p, srilm, beamformit
./local/check_tools.sh || exit 1


#######################################################################
# Perform SAD on the dev/eval data
#######################################################################
dir=exp/segmentation${affix}
sad_work_dir=exp/sad${affix}_${nnet_type}/
sad_nnet_dir=$dir/tdnn_${nnet_type}_sad_1a

if [ $stage -le 3 ]; then
  for datadir in ${test_sets}; do
    test_set=data/${datadir}
    if [ ! -f ${test_set}/wav.scp ]; then
      echo "$0: Not performing SAD on ${test_set}"
      exit 0
    fi
    # Perform segmentation
    local/segmentation/detect_speech_activity.sh --nj $nj --stage $sad_stage \
      $test_set $sad_nnet_dir mfcc $sad_work_dir \
      data/${datadir} || exit 1

    test_dir=data/${datadir}_${nnet_type}_seg
    mv data/${datadir}_seg ${test_dir}/
    cp data/${datadir}/{segments.bak,utt2spk.bak} ${test_dir}/
    # Generate RTTM file from segmentation performed by SAD. This can
    # be used to evaluate the performance of the SAD as an intermediate
    # step.
    steps/segmentation/convert_utt2spk_and_segments_to_rttm.py \
      ${test_dir}/utt2spk ${test_dir}/segments ${test_dir}/rttm

    if [ $score_sad == "true" ]; then
      echo "Scoring $datadir.."
      # We first generate the reference RTTM from the backed up utt2spk and segments
      # files.
      ref_rttm=${test_dir}/ref_rttm
      steps/segmentation/convert_utt2spk_and_segments_to_rttm.py ${test_dir}/utt2spk.bak \
        ${test_dir}/segments.bak ${test_dir}/ref_rttm

      # To score, we select just U06 segments from the hypothesis RTTM.
      hyp_rttm=${test_dir}/rttm.U06
      grep 'U06' ${test_dir}/rttm > ${test_dir}/rttm.U06
      echo "Array U06 selected for scoring.."
      
      if $use_new_rttm_reference == "true"; then
        echo "Use the new RTTM reference."
        mode="$(cut -d'_' -f1 <<<"$datadir")"
        ref_rttm=./chime6_rttm/${mode}_rttm
      fi

      sed 's/_U0[1-6].ENH//g' $ref_rttm > $ref_rttm.scoring
      sed 's/_U0[1-6].ENH//g' $hyp_rttm > $hyp_rttm.scoring
      cat ./local/uem_file | grep 'U06' | sed 's/_U0[1-6]//g' > ./local/uem_file.tmp
      md-eval.pl -1 -c 0.25 -u ./local/uem_file.tmp -r $ref_rttm.scoring -s $hyp_rttm.scoring |\
        awk 'or(/MISSED SPEECH/,/FALARM SPEECH/)'
    fi
  done
fi

exit 0;
