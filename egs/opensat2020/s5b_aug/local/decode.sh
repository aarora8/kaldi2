#!/usr/bin/env bash

# Copyright 2016 Johns Hopkins University (Author: Daniel Povey, Vijayaditya Peddinti)
#           2019 Vimal Manohar 
# Apache 2.0.

# This script does 2-stage decoding where the first stage is used to get 
# reliable frames for i-vector extraction.

set -e

# general opts
stage=0
nj=20

# ivector opts
max_count=75  # parameter for extract_ivectors.sh
sub_speaker_frames=6000
get_weights_from_ctm=true
weights_file=   # use weights from this archive (must be compressed using gunzip)
silence_weight=0.00001   # apply this weight to silence frames during i-vector extraction
ivector_dir=exp/nnet3_org_1d
graph_affix=
score_opts="--min-lmwt 6 --max-lmwt 13"

. ./cmd.sh
[ -f ./path.sh ] && . ./path.sh
. utils/parse_options.sh || exit 1;

if [ $# -ne 4 ]; then
  echo "Usage: $0 [options] <data-dir> <lang-dir> <graph-dir> <model-dir>"
  echo " Options:"
  echo "    --stage (0|1|2)   # start scoring script from part-way through."
  echo "e.g.:"
  echo "$0 data/dev data/lang exp/tri5a/graph_pp exp/nnet3/tdnn"
  exit 1;
fi

data=$1 # data directory 
lang=$2 # data/lang
graph=$3 #exp/tri5a/graph_pp
dir=$4 # exp/nnet3/tdnn

model_affix=`basename $dir`
data_set=$(basename $data)

if [ $stage -le 1 ]; then
  echo "Extracting i-vectors, stage 1"
  steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj 20 \
    --max-count $max_count \
    ${data}_hires $ivector_dir/extractor \
    $ivector_dir/ivectors_${data_set}_stage1;

  ivector_scale_affix=_scale0.75
  echo "$0: Scaling iVectors, stage 1"
  srcdir=$ivector_dir/ivectors_${data_set}_stage1
  outdir=$ivector_dir/ivectors_${data_set}${ivector_scale_affix}_stage1
  mkdir -p $outdir
  $train_cmd $outdir/log/scale_ivectors.log \
    copy-matrix --scale=0.75 scp:$srcdir/ivector_online.scp ark:- \| \
    copy-feats --compress=true ark:-  ark,scp:$outdir/ivector_online.ark,$outdir/ivector_online.scp;
  cp $srcdir/ivector_period $outdir/ivector_period
fi

decode_dir=$dir/decode_${data_set}${affix}
if [ $stage -le 2 ]; then
  echo "Generating lattices, stage 1"
  steps/nnet3/decode.sh --nj $nj --cmd "$decode_cmd" \
    --acwt 1.0 --post-decode-acwt 10.0 \
    --online-ivector-dir $ivector_dir/ivectors_${data_set}${ivector_scale_affix}_stage1 \
    $graph ${data}_hires ${decode_dir}_stage1;
fi

if [ $stage -le 3 ]; then
  if $get_weights_from_ctm; then
    if [ ! -z $weights_file ]; then
      echo "$0: Using provided vad weights file $weights_file"
      ivector_extractor_weights=$weights_file
    else
      echo "$0 : Generating vad weights file"
      ivector_extractor_weights=${decode_dir}_stage1/weights${affix}.gz
      local/extract_vad_weights.sh --silence-weight $silence_weight \
        --cmd "$decode_cmd" ${iter:+--iter $iter} \
        ${data}_hires $lang \
        ${decode_dir}_stage1 $ivector_extractor_weights
    fi
  else
    # get weights from best path decoding
    ivector_extractor_weights=${decode_dir}_stage1
  fi
fi

if [ $stage -le 4 ]; then
  echo "Extracting i-vectors, stage 2 with weights from $ivector_extractor_weights"
  steps/online/nnet2/extract_ivectors.sh --cmd "$train_cmd" --nj 20 \
    --silence-weight $silence_weight \
    --sub-speaker-frames $sub_speaker_frames --max-count $max_count \
    ${data}_hires $lang $ivector_dir/extractor \
    $ivector_extractor_weights $ivector_dir/ivectors_${data_set};
fi

if [ $stage -le 5 ]; then
  echo "Generating lattices, stage 2 with --acwt $acwt"
  rm -f ${decode_dir}/.error
  steps/nnet3/decode.sh --nj $nj --cmd "$decode_cmd" \
      --acwt 1.0 --post-decode-acwt 10.0 \
      --online-ivector-dir $ivector_dir/ivectors_${data_set}${ivector_affix} \
     $graph ${data}_hires ${decode_dir}
fi
exit 0
