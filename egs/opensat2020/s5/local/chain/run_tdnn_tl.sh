#!/usr/bin/env bash
set -e -o pipefail
stage=0

nj=96
xent_regularize=0.1
dropout_schedule='0,0@0.20,0.5@0.50,0'

train_set=train_cleaned
gmm=tri5b  # the gmm for the target data
num_threads_ubm=8
nnet3_affix=  # cleanup affix for nnet3 and chain dirs, e.g. _cleaned
online_cmvn=false

train_stage=-10
tree_affix=  # affix for tree directory, e.g. "a" or "b", in case we change the configuration.
tdnn_affix=1a_lr0005_tl  #affix for TDNN directory, e.g. "a" or "b", in case we change the configuration.
common_egs_dir=  # you can set this to use previously dumped egs.
remove_egs=false
srand=0




# configs for transfer learning
src_mdl=/export/c01/aarora8/kaldi/egs/ami/s5b/exp/ihm/chain_cleaned/tdnn1i_sp_bi/final.mdl # Input chain model
                                                   # trained on source dataset (wsj).
                                                   # This model is transfered to the target domain.

src_mfcc_config=/export/c01/aarora8/kaldi/egs/ami/s5b/conf/mfcc_hires.conf # mfcc config used to extract higher dim
                                                  # mfcc features for ivector and DNN training
                                                  # in the source domain.
src_ivec_extractor_dir=/export/c01/aarora8/kaldi/egs/ami/s5b/exp/ihm/nnet3_cleaned/extractor # Source ivector extractor dir used to extract ivector for
                         # source data. The ivector for target data is extracted using this extractor.
                         # It should be nonempty, if ivector is used in the source model training.

common_egs_dir=
primary_lr_factor=0.25 # The learning-rate factor for transferred layers from source
                       # model. e.g. if 0, the paramters transferred from source model
                       # are fixed.
                       # The learning-rate factor for new added layers is 1.0.

nnet_affix=
# End configuration section.

# End configuration section.
echo "$0 $@"  # Print the command line for logging

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

required_files="$src_mfcc_config $src_mdl"
use_ivector=false
ivector_dim=$(nnet3-am-info --print-args=false $src_mdl | grep "ivector-dim" | cut -d" " -f2)
if [ -z $ivector_dim ]; then ivector_dim=0 ; fi

if [ ! -z $src_ivec_extractor_dir ]; then
  if [ $ivector_dim -eq 0 ]; then
    echo "$0: Source ivector extractor dir '$src_ivec_extractor_dir' is specified "
    echo "but ivector is not used in training the source model '$src_mdl'."
  else
    required_files="$required_files $src_ivec_extractor_dir/final.dubm $src_ivec_extractor_dir/final.mat $src_ivec_extractor_dir/final.ie"
    use_ivector=true
  fi
else
  if [ $ivector_dim -gt 0 ]; then
    echo "$0: ivector is used in training the source model '$src_mdl' but no "
    echo " --src-ivec-extractor-dir option as ivector dir for source model is specified." && exit 1;
  fi
fi

#local/nnet3/run_ivector_common.sh --stage $stage \
#                                  --nj $nj \
#                                  --train-set $train_set \
#                                  --gmm $gmm \
#                                  --online-cmvn-extractor $online_cmvn \
#                                  --num-threads-ubm $num_threads_ubm \
#                                  --nnet3-affix "$nnet3_affix"

gmm_dir=exp/$gmm
ali_dir=exp/${gmm}_ali_${train_set}_sp
tree_dir=exp/chain${nnet3_affix}/tree_bi${tree_affix}
lat_dir=exp/chain${nnet3_affix}/${gmm}_${train_set}_sp_lats
dir=exp/chain${nnet3_affix}/tdnn${tdnn_affix}_sp
train_data_dir=data/${train_set}_sp_hires
lores_train_data_dir=data/${train_set}_sp
train_ivector_dir=exp/nnet3${nnet3_affix}/ivectors_${train_set}_sp_hires
lang=data/lang_chain

for f in $gmm_dir/final.mdl $train_data_dir/feats.scp $train_ivector_dir/ivector_online.scp \
    $lores_train_data_dir/feats.scp $ali_dir/ali.1.gz $gmm_dir/final.mdl; do
  [ ! -f $f ] && echo "$0: expected file $f to exist" && exit 1
done

if [ $stage -le 14 ]; then
  echo "$0: creating lang directory with one state per phone."
  # Create a version of the lang/ directory that has one state per phone in the
  # topo file. [note, it really has two states.. the first one is only repeated
  # once, the second one has zero or more repeats.]
  if [ -d data/lang_chain ]; then
    if [ data/lang_chain/L.fst -nt data/lang/L.fst ]; then
      echo "$0: data/lang_chain already exists, not overwriting it; continuing"
    else
      echo "$0: data/lang_chain already exists and seems to be older than data/lang..."
      echo " ... not sure what to do.  Exiting."
      exit 1;
    fi
  else
    cp -r data/lang_test data/lang_chain
    silphonelist=$(cat data/lang_chain/phones/silence.csl) || exit 1;
    nonsilphonelist=$(cat data/lang_chain/phones/nonsilence.csl) || exit 1;
    # Use our special topology... note that later on may have to tune this
    # topology.
    steps/nnet3/chain/gen_topo.py $nonsilphonelist $silphonelist >data/lang_chain/topo
  fi
fi

#if [ $stage -le 15 ]; then
#  steps/align_fmllr_lats.sh --nj 96 --cmd "$train_cmd" ${lores_train_data_dir} \
#    data/lang_test $gmm_dir $lat_dir
#  rm $lat_dir/fsts.*.gz # save space
#fi

if [ $stage -le 16 ]; then
  steps/nnet3/chain/build_tree.sh --frame-subsampling-factor 3 \
      --context-opts "--context-width=2 --central-position=1" \
      --cmd "$train_cmd" 3000 ${lores_train_data_dir} data/lang_chain $ali_dir $tree_dir
fi

if [ $stage -le 17 ]; then
  mkdir -p $dir

  echo "$0: creating neural net configs using the xconfig parser";

  num_targets=$(tree-info $tree_dir/tree |grep num-pdfs|awk '{print $2}')
  learning_rate_factor=$(echo "print 0.5/$xent_regularize" | python)

  mkdir -p $dir/configs
  cat <<EOF > $dir/configs/network.xconfig
  relu-batchnorm-layer name=tdnn10 input=tdnn9.batchnorm dim=450
  relu-batchnorm-layer name=prefinal-chain input=tdnn10 dim=450 target-rms=0.5 $output_opts
  output-layer name=output include-log-softmax=false dim=$num_targets max-change=1.5 $output_opts
  relu-batchnorm-layer name=prefinal-xent input=tdnn10 dim=450 target-rms=0.5 $output_opts
  output-layer name=output-xent dim=$num_targets learning-rate-factor=$learning_rate_factor max-change=1.5 $output_opts

EOF
  steps/nnet3/xconfig_to_configs.py --existing-model $src_mdl \
    --xconfig-file  $dir/configs/network.xconfig  \
    --config-dir $dir/configs/

  # Set the learning-rate-factor to be primary_lr_factor for transferred layers "
  # and adding new layers to them.
  $train_cmd $dir/log/generate_input_mdl.log \
    nnet3-copy --edits="set-learning-rate-factor name=* learning-rate-factor=$primary_lr_factor" $src_mdl - \| \
      nnet3-init --srand=1 - $dir/configs/final.config $dir/input.raw  || exit 1;
fi

if [ $stage -le 18 ]; then
  if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $dir/egs/storage ]; then
    utils/create_split_dir.pl \
     /export/b0{5,6,7,8}/$USER/kaldi-data/egs/ami-$(date +'%m_%d_%H_%M')/s5/$dir/egs/storage $dir/egs/storage
  fi

steps/nnet3/chain/train.py --stage=$train_stage \
    --cmd="$decode_cmd" \
    --feat.online-ivector-dir=$train_ivector_dir \
    --feat.cmvn-opts="--norm-means=false --norm-vars=false" \
    --chain.xent-regularize $xent_regularize \
    --chain.leaky-hmm-coefficient=0.1 \
    --chain.l2-regularize=0.0 \
    --chain.apply-deriv-weights=false \
    --chain.lm-opts="--num-extra-lm-states=2000" \
    --trainer.dropout-schedule $dropout_schedule \
    --trainer.add-option="--optimization.memory-compression-level=2" \
    --trainer.input-model $dir/input.raw \
    --trainer.srand=$srand \
    --trainer.max-param-change 2.0 \
    --trainer.num-epochs 2 \
    --trainer.frames-per-iter 3000000 \
    --trainer.optimization.num-jobs-initial 2 \
    --trainer.optimization.num-jobs-final 5 \
    --trainer.optimization.initial-effective-lrate 0.0005 \
    --trainer.optimization.final-effective-lrate 0.00005 \
    --trainer.num-chunk-per-minibatch 64 \
    --egs.chunk-width 140,100,160 \
    --egs.dir="$common_egs_dir" \
    --egs.opts="--frames-overlap-per-eg 0" \
    --cleanup.remove-egs=$remove_egs \
    --use-gpu=true \
    --feat-dir=$train_data_dir \
    --tree-dir=$tree_dir \
    --lat-dir=$lat_dir \
    --dir=$dir  || exit 1;
fi


if [ $stage -le 19 ]; then
  utils/mkgraph.sh --self-loop-scale 1.0 data/lang_test $dir $dir/graph
fi

if [ $stage -le 20 ]; then
    steps/nnet3/decode.sh --num-threads 4 --nj 20 --cmd run.pl \
        --acwt 1.0 --post-decode-acwt 10.0 \
        --online-ivector-dir exp/nnet3${nnet3_affix}/ivectors_safe_t_dev1_hires \
       $dir/graph data/safe_t_dev1_hires $dir/decode_safe_t_dev1 || exit 1;
fi
exit 0
