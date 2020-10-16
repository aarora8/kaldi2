#!/usr/bin/env bash
stage=0
cmd=queue.pl
. ./utils/parse_options.sh
. ./cmd.sh
. ./path.sh
set -e -o pipefail
set -o nounset                              # Treat unset variables as an error

dataset=safe_t_dev1
whole_data_dir=${dataset}_whole
datadev=data/safe_t_dev1

segmentation_opts="--silence-proportion 0.2 --max-segment-length 15 --frame-shift 0.03"
datadir=$datadev
data=$(basename $datadir)
dir=exp/ihm/chain_1a/tdnn_b_bigger_2_aug/
nspk=$(wc -l <data/${data}_segmented_reseg_hires/spk2utt)
decode_dir=${dir}/decode_${data}_segmented_reseg

chunk_width=140,100,160
frames_per_chunk=$(echo $chunk_width | cut -d, -f1)
tree_dir=exp/ihm/chain_1a/tree_bi
graph=exp/ihm/chain_1a/tdnn_b_bigger_2_aug/graph_3


lang=data/lang_nosp_test_3/
nj=100
max_count=75 # parameter for extract_ivectors.sh
silence_weight=0.00001
sub_speaker_frames=600

if [ $stage -le 0 ]; then
  nj_ali=`cat ${dir}/decode_${data}_segmented/num_jobs`
  $cmd JOB=1:${nj_ali} ${dir}/decode_${data}_segmented/log/generate_alignments.JOB.log \
      lattice-best-path --acoustic-scale=0.2 \
      "ark:gunzip -c ${dir}/decode_${data}_segmented/lat.JOB.gz |" \
      ark:/dev/null "ark:|gzip -c >${dir}/decode_${data}_segmented/ali.JOB.gz" || exit 1;
fi

if [ $stage -le 1 ]; then
  cp $lang/phones.txt ${dir}/decode_${data}_segmented/ || exit 1;

  steps/resegment_data.sh --segmentation-opts "$segmentation_opts" ${datadir}_segmented_hires $lang \
      ${dir}/decode_${data}_segmented ${datadir}_segmented_reseg_hires_tmp exp/resegment_${data}_segmented

  utils/data/subsegment_data_dir.sh ${datadir}_segmented_hires ${datadir}_segmented_reseg_hires_tmp/segments \
      ${datadir}_segmented_reseg_hires

  rm -rf ${datadir}_segmented_reseg_hires_tmp 2>/dev/null || true
fi

if [ $stage -le 2 ]; then

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
    ${datadir}_segmented_reseg_hires $lang exp/ihm/nnet3_1b/extractor \
    exp/ihm/nnet3_1b/ivectors_${data}_segmented_reseg_hires;
fi

if [ $stage -le 3 ]; then

  steps/nnet3/decode.sh \
    --acwt 1.0 --post-decode-acwt 10.0 \
    --frames-per-chunk $frames_per_chunk \
    --skip-scoring true \
    --nj $nspk --cmd "$decode_cmd"  --num-threads 4 \
    --online-ivector-dir exp/ihm/nnet3_1b/ivectors_${data}_segmented_reseg_hires \
    $graph ${datadir}_segmented_reseg_hires ${decode_dir} || exit 1
fi


# resolve ctm overlaping regions, and compute wer
#utils/data/get_utt2dur.sh --nj 4 --cmd "$train_cmd" data/safe_t_dev1_whole

#utils/data/get_segments_for_data.sh data/safe_t_dev1_whole > data/safe_t_dev1_whole/segments

#utils/data/get_uniform_subsegments.py --max-segment-duration=30 --overlap-duration=5 \
#  --max-remaining-duration=15 ${datadev}_whole/segments > ${datadev}_whole/uniform_sub_segments

steps/get_ctm_fast.sh --lmwt 8 --cmd "$train_cmd" --frame-shift 0.03   ${datadir}_segmented_reseg_hires  $graph $decode_dir $decode_dir/score_10_0.0

awk '{print $1" "$1" 1"}' ${datadir}_segmented_reseg_hires/wav.scp > ${datadir}_segmented_reseg_hires/reco2file_and_channel

utils/ctm/resolve_ctm_overlaps.py ${datadir}_segmented_reseg_hires/segments \
    ${decode_dir}/score_10_0.0/ctm \
    - | utils/convert_ctm.pl ${datadir}_segmented_reseg_hires/segments ${datadir}_segmented_reseg_hires/reco2file_and_channel > \
    ${decode_dir}/score_10_0.0/${data}_hires.ctm


awk '{a[$1]=a[$1]" "$5;}END{for(i in a)print i""a[i];}' ${decode_dir}/score_10_0.0/${data}_hires.ctm > tmpconcat

cat tmpconcat > ${decode_dir}/score_10_0.0/ctm_out.concat

cat ${decode_dir}/score_10_0.0/ctm_out.concat | local/wer_output_filter > ${decode_dir}/score_10_0.0/hyp.txt

compute-wer --text --mode=present ark:exp/ihm/chain_1a/tdnn_b_bigger_2_aug/decode_safe_t_dev1_whole/scoring_kaldi/test_filt.txt  ark:${decode_dir}/score_10_0.0/hyp.txt
