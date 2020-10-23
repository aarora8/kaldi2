#!/usr/bin/env bash
# This script performs decoding on whole directory, uniform segmentation
# asr resegmentation
dataset=safe_t_dev1
dir=exp/chain_all/tdnn_all
extractor=exp/nnet3_all
lang=data/lang_nosp_test_3
segmentation_opts="--silence-proportion 0.2 --max-segment-length 15 --frame-shift 0.03"
chunk_width=140,100,160
frames_per_chunk=$(echo $chunk_width | cut -d, -f1)
nj=$(cat data/${dataset}/spk2utt | wc -l)
max_count=75 # parameter for extract_ivectors.sh
silence_weight=0.00001
sub_speaker_frames=600
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

##############################################################################################################
if [ $stage -le 4 ]; then
  nj_ali=`cat $dir/decode_$uni_segmented_data_dir/num_jobs`
  $cmd JOB=1:${nj_ali} $dir/decode_$uni_segmented_data_dir/log/generate_alignments.JOB.log \
      lattice-best-path --acoustic-scale=0.2 \
      "ark:gunzip -c $dir/decode_$uni_segmented_data_dir/lat.JOB.gz |" \
      ark:/dev/null "ark:|gzip -c >$dir/decode_$uni_segmented_data_dir/ali.JOB.gz" || exit 1;
fi

if [ $stage -le 5 ]; then
  cp $lang/phones.txt $dir/decode_$uni_segmented_data_dir || exit 1;
  steps/resegment_data.sh --segmentation-opts "$segmentation_opts" data/${uni_segmented_data_dir}_hires $lang \
      $dir/decode_$uni_segmented_data_dir data/${uni_segmented_data_dir}_reseg_hires_tmp exp/resegment_$uni_segmented_data_dir
  utils/data/subsegment_data_dir.sh data/${uni_segmented_data_dir}_hires data/${uni_segmented_data_dir}_reseg_hires_tmp/segments \
      data/${uni_segmented_data_dir}_reseg_hires

  rm -rf data/${uni_segmented_data_dir}_reseg_hires_tmp 2>/dev/null || true
fi

nspk=$(wc -l <data/${uni_segmented_data_dir}_reseg_hires/spk2utt)
if [ $stage -le 6 ]; then

  echo "Extracting i-vectors, stage 2"
  # this does offline decoding, except we estimate the iVectors per
  # speaker, excluding silence (based on alignments from a DNN decoding), with a
  # different script.  This is just to demonstrate that script.
  # the --sub-speaker-frames is optional; if provided, it will divide each speaker
  # up into "sub-speakers" of at least that many frames... can be useful if
  # acoustic conditions drift over time within the speaker's data.
  steps/online/nnet2/extract_ivectors.sh --cmd "$train_cmd" --nj $nj \
    --silence-weight $silence_weight \
    --sub-speaker-frames $sub_speaker_frames --max-count $max_count \
    data/${uni_segmented_data_dir}_reseg_hires $lang $extractor/extractor \
    $extractor/ivectors_${uni_segmented_data_dir}_reseg_hires
fi


if [ $stage -le 7 ]; then

  steps/nnet3/decode.sh \
    --acwt 1.0 --post-decode-acwt 10.0 \
    --frames-per-chunk $frames_per_chunk \
    --skip-scoring true \
    --nj $nspk --cmd "$decode_cmd"  --num-threads 4 \
    --online-ivector-dir $extractor/ivectors_${uni_segmented_data_dir}_reseg_hires \
    $dir/graph_3 data/${uni_segmented_data_dir}_reseg_hires $dir/decode_${uni_segmented_data_dir}_reseg || exit 1
fi

if [ $stage -le 8 ]; then
  steps/get_ctm_fast.sh --cmd "$train_cmd" --frame-shift 0.03 data/${uni_segmented_data_dir}_reseg_hires \
    $dir/graph_3 $dir/decode_${uni_segmented_data_dir}_reseg $dir/decode_${uni_segmented_data_dir}_reseg/score_10_0.0

  awk '{print $1" "$1" 1"}' data/${uni_segmented_data_dir}_reseg_hires/wav.scp > data/${uni_segmented_data_dir}_reseg_hires/reco2file_and_channel

  utils/ctm/resolve_ctm_overlaps.py data/${uni_segmented_data_dir}_reseg_hires/segments \
    $dir/decode_${uni_segmented_data_dir}_reseg/score_10_0.0/ctm \
    - | utils/convert_ctm.pl data/${uni_segmented_data_dir}_reseg_hires/segments \
    data/${uni_segmented_data_dir}_reseg_hires/reco2file_and_channel > \
    $dir/decode_${uni_segmented_data_dir}_reseg/score_10_0.0/ctm.resolved_overlap

  awk '{a[$1]=a[$1]" "$5;}END{for(i in a)print i""a[i];}'     $dir/decode_${uni_segmented_data_dir}_reseg/score_10_0.0/ctm.resolved_overlap > tmpconcat

  cat tmpconcat > $dir/decode_${uni_segmented_data_dir}_reseg/score_10_0.0/ctm.concat.final

  cat $dir/decode_${uni_segmented_data_dir}_reseg/score_10_0.0/ctm.concat.final | local/wer_output_filter > $dir/decode_${uni_segmented_data_dir}_reseg/score_10_0.0/hyp.txt

  compute-wer --text --mode=present ark:$dir/decode_$whole_data_dir/scoring_kaldi/test_filt.txt  ark:$dir/decode_${uni_segmented_data_dir}_reseg/score_10_0.0/hyp.txt
fi
