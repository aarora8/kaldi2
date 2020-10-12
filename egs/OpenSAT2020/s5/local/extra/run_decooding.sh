#!/usr/bin/env bash
stage=0
cmd=queue.pl
. ./utils/parse_options.sh
. ./cmd.sh
. ./path.sh
set -e -o pipefail
set -o nounset                              # Treat unset variables as an error

dataset=safe_t_dev1_segmented
dir=exp/ihm/chain_1a/tdnn_b_bigger_2_aug
nj=$(cat data/${dataset}/spk2utt | wc -l)
if [ $stage -le 0 ] ; then
  #cat data/$dataset/wav.scp | awk '{print $1 " " $1}' > data/$dataset/utt2spk
  #utils/fix_data_dir.sh data/$dataset
  #steps/make_mfcc.sh --cmd "$train_cmd" --nj 20 data/$dataset
  #steps/compute_cmvn_stats.sh data/$dataset
  #utils/fix_data_dir.sh data/${dataset}
  nj=$(cat data/${dataset}/spk2utt | wc -l)
  utils/copy_data_dir.sh data/$dataset data/${dataset}_hires
  steps/make_mfcc.sh --nj $nj --mfcc-config conf/mfcc_hires.conf \
    --cmd "$train_cmd" data/${dataset}_hires
  steps/compute_cmvn_stats.sh data/${dataset}_hires
  utils/fix_data_dir.sh data/${dataset}_hires

  steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd --max-jobs-run 64" --nj $nj \
    data/${dataset}_hires exp/ihm/nnet3_1b/extractor \
    exp/ihm/nnet3_1b/ivectors_${dataset}_hires
fi

if [ $stage -le 1 ] ; then
  # decode
  steps/nnet3/decode.sh --num-threads 4 --nj $nj --cmd "$decode_cmd --max-jobs-run 64" \
    --acwt 1.0 --post-decode-acwt 10.0 \
    --online-ivector-dir exp/ihm/nnet3_1b/ivectors_${dataset}_hires \
    $dir/graph_3 data/${dataset}_hires $dir/decode_${dataset} || exit 1;
fi
echo "Done"
