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

if [ $stage -le 0 ]; then
  utils/data/convert_data_dir_to_whole.sh data/$dataset data/$whole_data_dir
fi


utils/data/get_utt2dur.sh --nj 4 --cmd "$train_cmd" data/safe_t_dev1_whole

utils/data/get_segments_for_data.sh data/safe_t_dev1_whole > data/safe_t_dev1_whole/segments

utils/data/get_uniform_subsegments.py --max-segment-duration=30 --overlap-duration=5 \
  --max-remaining-duration=15 ${datadev}_whole/segments > ${datadev}_whole/uniform_sub_segments

local/run_decooding.sh


local/postprocess_test.sh ${data}_segmented ${tree_dir}/graph${graph_affix} ${decode_dir}

steps/get_ctm_fast.sh --cmd "$train_cmd" --frame-shift 0.03 data/safe_t_dev1_segmented_hires  exp/ihm/chain_1a/tdnn_b_bigger_2_aug/graph_3 exp/ihm/chain_1a/tdnn_b_bigger_2_aug/decode_safe_t_dev1_segmented exp/ihm/chain_1a/tdnn_b_bigger_2_aug/decode_safe_t_dev1_segmented/score_10_0.0

utils/ctm/resolve_ctm_overlaps.py data/${data}_hires/segments \
    ${decode_dir}/score_10_0.0/ctm \
    - | utils/convert_ctm.pl data/${data}_hires/segments data/${data}_hires/reco2file_and_channel > \
    ${decode_dir}/score_10_0.0/${data}_hires.ctm


awk '{print $1" "$1" 1"}' data/safe_t_dev1_segmented_hires/wav.scp > data/safe_t_dev1_segmented_hires/reco2file_and_channel

utils/ctm/resolve_ctm_overlaps.py data/safe_t_dev1_segmented_hires/segments  exp/ihm/chain_1a/tdnn_b_bigger_2_aug/decode_safe_t_dev1_segmented/score_10_0.0/ctm \
    - | utils/convert_ctm.pl data/safe_t_dev1_segmented_hires/segments data/safe_t_dev1_segmented_hires/reco2file_and_channel > \
    exp/ihm/chain_1a/tdnn_b_bigger_2_aug/decode_safe_t_dev1_segmented/score_10_0.0/safe_t_dev1_segmented_hires.ctm


awk '{a[$1]=a[$1]" "$5;}END{for(i in a)print i""a[i];}'     exp/ihm/chain_1a/tdnn_b_bigger_2_aug/decode_safe_t_dev1_segmented/score_10_0.0/safe_t_dev1_segmented_hires.ctm > tmpconcat

cat tmpconcat > exp/ihm/chain_1a/tdnn_b_bigger_2_aug/decode_safe_t_dev1_segmented/score_10_0.0/ctm_out.concat

cat exp/ihm/chain_1a/tdnn_b_bigger_2_aug/decode_safe_t_dev1_segmented/score_10_0.0/ctm_out.concat | local/wer_output_filter >exp/ihm/chain_1a/tdnn_b_bigger_2_aug/decode_safe_t_dev1_segmented/score_10_0.0/hyp.txt

compute-wer --text --mode=present ark:exp/ihm/chain_1a/tdnn_b_bigger_2_aug/decode_safe_t_dev1_whole/scoring_kaldi/test_filt.txt  ark:exp/ihm/chain_1a/tdnn_b_bigger_2_aug/decode_safe_t_dev1_segmented/score_10_0.0/hyp.txt


