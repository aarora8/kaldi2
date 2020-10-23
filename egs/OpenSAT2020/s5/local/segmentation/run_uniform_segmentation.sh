#!/usr/bin/env bash
# This script performs decoding on whole directory, uniform segmentation

dataset=safe_t_dev1
dir=exp/chain_all/tdnn_all
extractor=exp/nnet3_all
nj=$(cat data/${dataset}/spk2utt | wc -l)

stage=0
cmd=queue.pl
. ./utils/parse_options.sh
. ./cmd.sh
. ./path.sh
set -e -o pipefail
set -o nounset

whole_data_dir=${dataset}_whole
uni_segmented_data_dir=${dataset}_segmented

if [ $stage -le 0 ]; then
  local/run_decooding.sh --dataset $dataset
fi

if [ $stage -le 1 ]; then
  utils/data/convert_data_dir_to_whole.sh data/$dataset data/$whole_data_dir
  local/run_decooding.sh --dataset $whole_data_dir
fi


if [ $stage -le 2 ]; then
  # create uniform segmentation
  utils/data/convert_data_dir_to_whole.sh data/$dataset data/$whole_data_dir

  utils/data/get_utt2dur.sh --nj 4 --cmd "$train_cmd" data/$whole_data_dir

  utils/data/get_segments_for_data.sh data/$whole_data_dir > data/$whole_data_dir/segments

  utils/data/get_uniform_subsegments.py --max-segment-duration=30 --overlap-duration=5 \
    --max-remaining-duration=15 data/$whole_data_dir/segments > data/$whole_data_dir/uniform_sub_segments

  utils/data/subsegment_data_dir.sh data/$whole_data_dir \
      data/$whole_data_dir/uniform_sub_segments data/$uni_segmented_data_dir

  local/run_decooding.sh --dataset $uni_segmented_data_dir
fi

if [ $stage -le 3 ]; then
  # score uniform segmentation
  #local/segmentation/postprocess_test.sh $uni_segmented_data_dir ${dir}/graph_3 $dir/decode_$uni_segmented_data_dir

  steps/get_ctm_fast.sh --cmd "$train_cmd" --frame-shift 0.03 data/${uni_segmented_data_dir}_hires \
    $dir/graph_3 $dir/decode_$uni_segmented_data_dir $dir/decode_$uni_segmented_data_dir/score_10_0.0

  awk '{print $1" "$1" 1"}' data/${uni_segmented_data_dir}_hires/wav.scp > data/${uni_segmented_data_dir}_hires/reco2file_and_channel

  utils/ctm/resolve_ctm_overlaps.py data/${uni_segmented_data_dir}_hires/segments \
    $dir/decode_$uni_segmented_data_dir/score_10_0.0/ctm \
    - | utils/convert_ctm.pl data/${uni_segmented_data_dir}_hires/segments \
    data/${uni_segmented_data_dir}_hires/reco2file_and_channel > \
    $dir/decode_$uni_segmented_data_dir/score_10_0.0/${dataset}_hires.ctm

  awk '{a[$1]=a[$1]" "$5;}END{for(i in a)print i""a[i];}'     $dir/decode_$uni_segmented_data_dir/score_10_0.0/${dataset}_hires.ctm > tmpconcat

  cat tmpconcat > $dir/decode_$uni_segmented_data_dir/score_10_0.0/ctm_out.concat

  cat $dir/decode_$uni_segmented_data_dir/score_10_0.0/ctm_out.concat | local/wer_output_filter > $dir/decode_$uni_segmented_data_dir/score_10_0.0/hyp.txt

  compute-wer --text --mode=present ark:$dir/decode_$whole_data_dir/scoring_kaldi/test_filt.txt  ark:$dir/decode_$uni_segmented_data_dir/score_10_0.0/hyp.txt
fi
