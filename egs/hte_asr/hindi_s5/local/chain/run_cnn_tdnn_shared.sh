#!/usr/bin/env bash

set -e -o pipefail
stage=0
nj=60
train_set=train
gmm=tri3
num_epochs=10

# The rest are configs specific to this script.  Most of the parameters
# are just hardcoded at this level, in the commands below.
train_stage=-10
xent_regularize=0.1
get_egs_stage=-10
tree_affix=_1a
tdnn_affix=_1a
nnet3_affix=_1a
common_egs_dir= 
dropout_schedule='0,0@0.20,0.5@0.50,0'
remove_egs=true
chunk_width=140,100,160
# End configuration section.
echo "$0 $@"

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

if ! cuda-compiled; then
  cat <<EOF && exit 1
This script is intended to be used with GPUs but you have not compiled Kaldi with CUDA
If you want to use GPUs (and have them), go to src/, and configure and make on a machine
where "nvcc" is installed.
EOF
fi

local/nnet3/run_ivector_common.sh --stage $stage \
                                  --nj $nj \
                                  --train-set $train_set \
                                  --gmm $gmm \
                                  --nnet3-affix "$nnet3_affix"

gmm_dir=exp/${gmm}_${train_set}
ali_dir=exp/${gmm}_${train_set}_ali_sp
lores_train_data_dir=data/${train_set}_sp
train_data_dir=data/${train_set}_sp_hires
lang_dir=data/lang_nosp_test
tree_dir=exp/chain${nnet3_affix}/tree${tree_affix}
lat_dir=exp/tri3_${train_set}_lats_sp
dir=exp/chain${nnet3_affix}/cnn_tdnn${tdnn_affix}
train_ivector_dir=exp/nnet3${nnet3_affix}/ivectors_${train_set}_sp_hires

for f in $gmm_dir/final.mdl $lores_train_data_dir/feats.scp \
   $train_data_dir/feats.scp $train_ivector_dir/ivector_online.scp; do
  [ ! -f $f ] && echo "$0: expected file $f to exist" && exit 1
done


if [ $stage -le 11 ]; then
  nj=$(cat $ali_dir/num_jobs) || exit 1;
  steps/align_fmllr_lats.sh --nj $nj --cmd "$train_cmd" $lores_train_data_dir \
    $lang_dir $gmm_dir $lat_dir
  rm $lat_dir/fsts.*.gz
fi

if [ $stage -le 12 ]; then
  echo "$0: creating lang directory with one state per phone."
  # Create a version of the lang/ directory that has one state per phone in the
  # topo file. [note, it really has two states.. the first one is only repeated
  # once, the second one has zero or more repeats.]
  if [ -d data/lang_chain ]; then
    if [ data/lang_chain/L.fst -nt $lang_dir/L.fst ]; then
      echo "$0: data/lang_chain already exists, not overwriting it; continuing"
    else
      echo "$0: data/lang_chain already exists and seems to be older than data/lang..."
      echo " ... not sure what to do.  Exiting."
      exit 1;
    fi
  else
    cp -r $lang_dir data/lang_chain
    silphonelist=$(cat data/lang_chain/phones/silence.csl) || exit 1;
    nonsilphonelist=$(cat data/lang_chain/phones/nonsilence.csl) || exit 1;
    # Use our special topology... note that later on may have to tune this topology.
    steps/nnet3/chain/gen_topo.py $nonsilphonelist $silphonelist >data/lang_chain/topo
  fi
fi

if [ $stage -le 14 ]; then
  steps/nnet3/chain/build_tree.sh --frame-subsampling-factor 3 \
      --context-opts "--context-width=2 --central-position=1" \
      --cmd "$train_cmd" 5000 ${lores_train_data_dir} data/lang_chain $ali_dir $tree_dir
fi

if [ $stage -le 15 ]; then
  mkdir -p $dir
  echo "$0: creating neural net configs using the xconfig parser";

  num_targets=$(tree-info $tree_dir/tree |grep num-pdfs|awk '{print $2}')
  learning_rate_factor=$(echo "print (0.5/$xent_regularize)" | python)

  cnn_opts="l2-regularize=0.01"
  ivector_affine_opts="l2-regularize=0.01"
  tdnnf_first_opts="l2-regularize=0.01 dropout-proportion=0.0 bypass-scale=0.0"
  tdnnf_opts="l2-regularize=0.01 dropout-proportion=0.0 bypass-scale=0.66"
  linear_opts="l2-regularize=0.01 orthonormal-constraint=-1.0"
  prefinal_opts="l2-regularize=0.01"
  output_opts="l2-regularize=0.002"

  mkdir -p $dir/configs
  cat <<EOF > $dir/configs/network.xconfig
  input dim=100 name=ivector
  input dim=40 name=input
  idct-layer name=idct input=input dim=40 cepstral-lifter=22 affine-transform-file=$dir/configs/idct.mat
  linear-component name=ivector-linear $ivector_affine_opts dim=200 input=ReplaceIndex(ivector, t, 0)
  batchnorm-component name=ivector-batchnorm target-rms=0.025
  batchnorm-component name=idct-batchnorm input=idct
  spec-augment-layer name=idct-spec-augment freq-max-proportion=0.5 time-zeroed-proportion=0.2 time-mask-max-frames=20
  combine-feature-maps-layer name=combine_inputs input=Append(idct-spec-augment, ivector-batchnorm) num-filters1=1 num-filters2=5 height=40
  conv-relu-batchnorm-layer name=cnn1 $cnn_opts height-in=40 height-out=40 time-offsets=-1,0,1 height-offsets=-1,0,1 num-filters-out=64
  conv-relu-batchnorm-layer name=cnn2 $cnn_opts height-in=40 height-out=40 time-offsets=-1,0,1 height-offsets=-1,0,1 num-filters-out=64
  conv-relu-batchnorm-layer name=cnn3 $cnn_opts height-in=40 height-out=20 height-subsample-out=2 time-offsets=-1,0,1 height-offsets=-1,0,1 num-filters-out=128
  conv-relu-batchnorm-layer name=cnn4 $cnn_opts height-in=20 height-out=20 time-offsets=-1,0,1 height-offsets=-1,0,1 num-filters-out=128
  conv-relu-batchnorm-layer name=cnn5 $cnn_opts height-in=20 height-out=10 height-subsample-out=2 time-offsets=-1,0,1 height-offsets=-1,0,1 num-filters-out=256
  conv-relu-batchnorm-layer name=cnn6 $cnn_opts height-in=10 height-out=10  time-offsets=-1,0,1 height-offsets=-1,0,1 num-filters-out=256
  # the first TDNN-F layer has no bypass (since dims don't match), and a larger bottleneck so the
  # information bottleneck doesn't become a problem.  (we use time-stride=0 so no splicing, to
  # limit the num-parameters).

  tdnnf-layer name=tdnnf7 $tdnnf_first_opts dim=1536 bottleneck-dim=256 time-stride=0
  tdnnf-layer name=tdnnf8 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf9 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf10 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf11 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf12 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf13 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf14 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf15 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  linear-component name=prefinal-l dim=256 $linear_opts

  ## adding the layers for chain branch
  prefinal-layer name=prefinal-chain input=prefinal-l $prefinal_opts small-dim=256 big-dim=1536
  output-layer name=output include-log-softmax=false dim=$num_targets $output_opts
  # adding the layers for xent branch
  prefinal-layer name=prefinal-xent input=prefinal-l $prefinal_opts small-dim=256 big-dim=1536
  output-layer name=output-xent dim=$num_targets learning-rate-factor=$learning_rate_factor $output_opts
EOF
  steps/nnet3/xconfig_to_configs.py --xconfig-file $dir/configs/network.xconfig --config-dir $dir/configs/

fi


if [ $stage -le 16 ]; then
  if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $dir/egs/storage ]; then
    utils/create_split_dir.pl \
     /export/b0{3,4,5,6}/$USER/kaldi-data/egs/hte-$(date +'%m_%d_%H_%M')/s5/$dir/egs/storage $dir/egs/storage
  fi

steps/nnet3/chain/train.py --stage $train_stage \
    --cmd "$gpu_cmd" \
    --feat.online-ivector-dir $train_ivector_dir \
    --feat.cmvn-opts "--norm-means=false --norm-vars=false" \
    --chain.xent-regularize $xent_regularize \
    --chain.leaky-hmm-coefficient=0.1 \
    --chain.l2-regularize=0.0 \
    --chain.apply-deriv-weights=false \
    --chain.lm-opts="--num-extra-lm-states=2000" \
    --trainer.dropout-schedule $dropout_schedule \
    --trainer.add-option="--optimization.memory-compression-level=2" \
    --egs.dir "$common_egs_dir" \
    --egs.opts "--frames-overlap-per-eg 0 --constrained false" \
    --egs.chunk-width 140,100,160 \
    --trainer.num-chunk-per-minibatch 64 \
    --trainer.frames-per-iter 3000000 \
    --trainer.num-epochs 10 \
    --trainer.optimization.num-jobs-initial 3 \
    --trainer.optimization.num-jobs-final 5 \
    --trainer.optimization.initial-effective-lrate 0.00025 \
    --trainer.optimization.final-effective-lrate 0.000025 \
    --trainer.max-param-change 2.0 \
    --cleanup.remove-egs $remove_egs \
    --feat-dir $train_data_dir \
    --tree-dir $tree_dir \
    --lat-dir $lat_dir \
    --dir $dir  || exit 1;
fi

if [ $stage -le 17 ]; then

  for datadir in dev_Hindi_jhu_ho_spk; do
    utils/copy_data_dir.sh data/$datadir data/${datadir}_hires
    steps/make_mfcc.sh --nj $nj --mfcc-config conf/mfcc_hires.conf \
      --cmd "$train_cmd" data/${datadir}_hires || exit 1
  done

  steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj 7 \
    data/dev_Hindi_jhu_ho_spk_hires exp/nnet3${nnet3_affix}/extractor \
    exp/nnet3${nnet3_affix}/ivectors_dev_Hindi_jhu_ho_spk_hires

  utils/mkgraph.sh --self-loop-scale 1.0 data/lang_nosp_test $dir $dir/graph
fi

if [ $stage -le 18 ]; then
  steps/nnet3/decode.sh --nj 7 --cmd "$decode_cmd" \
      --acwt 1.0 --post-decode-acwt 10.0 \
      --online-ivector-dir exp/nnet3${nnet3_affix}/ivectors_dev_Hindi_jhu_ho_spk_hires \
     $dir/graph data/dev_Hindi_jhu_ho_spk_hires $dir/decode_dev_Hindi_jhu_ho_spk || exit 1;
fi

eval_set=eval_Hindi
if [ $stage -le 19 ]; then
#  utils/copy_data_dir.sh data/$eval_set data/${eval_set}_hires
#  steps/make_mfcc.sh --nj 10 --mfcc-config conf/mfcc_hires.conf \
#    --cmd "$train_cmd" data/${eval_set}_hires || exit 1
#
#  steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj 10 \
#    data/${eval_set}_hires exp/nnet3${nnet3_affix}/extractor \
#    exp/nnet3${nnet3_affix}/ivectors_${eval_set}_hires

  utils/mkgraph.sh --self-loop-scale 1.0 data/lang_nosp_test_5grm $dir $dir/graph_5grm
fi

if [ $stage -le 20 ]; then
  steps/nnet3/decode.sh --stage 3 --nj 10 --cmd "$decode_cmd" \
      --acwt 1.0 --post-decode-acwt 10.0 \
      --online-ivector-dir exp/nnet3${nnet3_affix}/ivectors_${eval_set}_hires \
     $dir/graph_5grm data/${eval_set}_hires $dir/decode_${eval_set}_5grm || exit 1;
fi
eval_set=dev_Hindi
if [ $stage -le 21 ]; then
  utils/copy_data_dir.sh data/$eval_set data/${eval_set}_hires
  steps/make_mfcc.sh --nj 10 --mfcc-config conf/mfcc_hires.conf \
    --cmd "$train_cmd" data/${eval_set}_hires || exit 1

  steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj 10 \
    data/${eval_set}_hires exp/nnet3${nnet3_affix}/extractor \
    exp/nnet3${nnet3_affix}/ivectors_${eval_set}_hires

  utils/mkgraph.sh --self-loop-scale 1.0 data/lang_nosp_test $dir $dir/graph
fi

if [ $stage -le 22 ]; then
  steps/nnet3/decode.sh --nj 10 --cmd "$decode_cmd" \
      --acwt 1.0 --post-decode-acwt 10.0 \
      --online-ivector-dir exp/nnet3${nnet3_affix}/ivectors_${eval_set}_hires \
     $dir/graph_5grm data/${eval_set}_hires $dir/decode_${eval_set}_5grm || exit 1;
fi
exit 0