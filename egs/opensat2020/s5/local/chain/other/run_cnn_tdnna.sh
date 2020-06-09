#!/usr/bin/env bash
set -e -o pipefail
stage=0

nj=96
xent_regularize=0.1
dropout_schedule='0,0@0.20,0.5@0.50,0'

train_set=train_cleaned
gmm=tri5b  # the gmm for the target data
num_threads_ubm=8
nnet3_affix=_org_1d  # cleanup affix for nnet3 and chain dirs, e.g. _cleaned

online_cmvn=true

train_stage=-10
tree_affix=  # affix for tree directory, e.g. "a" or "b", in case we change the configuration.
tdnn_affix=1i_ep15_noise  #affix for TDNN directory, e.g. "a" or "b", in case we change the configuration.
#common_egs_dir="/exp/aarora/kaldisat/egs/opensat2020/s5/exp/chain_org_1d/tdnn1i_sp/egs"  # you can set this to use previously dumped egs.
common_egs_dir=
remove_egs=false
get_egs_stage=-10

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

local/nnet3/run_ivector_common.sh --stage $stage \
                                  --nj $nj \
                                  --train-set $train_set \
                                  --gmm $gmm \
                                  --online-cmvn-extractor $online_cmvn \
                                  --num-threads-ubm $num_threads_ubm \
                                  --nnet3-affix "$nnet3_affix"


# The following script handles stages 9 to 14
local/nnet3/extract_noise_vectors.sh \
  --stage $stage --nj $nj \
  --train-set ${train_set} --gmm ${gmm}_cleaned \

#exit
gmm_dir=exp/$gmm
ali_dir=exp/${gmm}_ali_${train_set}_sp_comb
tree_dir=exp/chain${nnet3_affix}/tree_bi${tree_affix}
lat_dir=exp/chain${nnet3_affix}/${gmm}_${train_set}_sp_comb_lats
dir=exp/chain${nnet3_affix}/tdnn${tdnn_affix}_sp
train_data_dir=data/${train_set}_sp_hires_comb
lores_train_data_dir=data/${train_set}_sp_comb
train_ivector_dir=exp/nnet3${nnet3_affix}/ivectors_${train_set}_sp_hires_comb
lang=data/lang_chain

num_epochs=15
chunk_width=140,100,160
xent_regularize=0.1
dropout_schedule='0,0@0.20,0.5@0.50,0'
srand=0

for f in $gmm_dir/final.mdl $train_data_dir/feats.scp $train_ivector_dir/ivector_online.scp \
    $lores_train_data_dir/feats.scp $ali_dir/ali.1.gz $gmm_dir/final.mdl; do
  [ ! -f $f ] && echo "$0: expected file $f to exist" && exit 1
done



# Concat ivectors with noise vectors for training set
if [ $stage -le 15 ]; then
  noise_vec_dir=exp/nnet3/noise_${train_set}_sp_hires_comb
  mkdir -p ${train_ivector_dir}_noise
  echo ${train_ivector_dir}/ivector_online.scp
  echo ${noise_vec_dir}/ivector_online.scp
  paste-feats scp:${train_ivector_dir}/ivector_online.scp scp:${noise_vec_dir}/ivector_online.scp \
    ark,scp:${train_ivector_dir}_noise/ivector_online.ark,${train_ivector_dir}_noise/ivector_online.scp
  echo 10 > ${train_ivector_dir}_noise/ivector_period
fi

# Concat ivectors with noise vectors for test set
if [ $stage -le 16 ]; then
  for test_dir in safe_t_dev1; do
    noise_vec_dir=exp/nnet3/noise_${test_dir}_hires
    ivector_dir=exp/nnet3${nnet3_affix}/ivectors_${test_dir}_hires
    mkdir -p ${ivector_dir}_noise
    echo ${ivector_dir}/ivector_online.scp
    echo ${noise_vec_dir}/ivector_online.scp
    paste-feats scp:${ivector_dir}/ivector_online.scp scp:${noise_vec_dir}/ivector_online.scp \
      ark,scp:${ivector_dir}_noise/ivector_online.ark,${ivector_dir}_noise/ivector_online.scp
    echo 10 > ${ivector_dir}_noise/ivector_period
  done
fi


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

if [ $stage -le 15 ]; then
  # Get the alignments as lattices (gives the chain training more freedom).
  # use the same num-jobs as the alignments
  steps/align_fmllr_lats.sh --nj 96 --cmd "$train_cmd" ${lores_train_data_dir} \
    data/lang_test $gmm_dir $lat_dir
  rm $lat_dir/fsts.*.gz # save space
fi

if [ $stage -le 16 ]; then
  # Build a tree using our new topology.  We know we have alignments for the
  # speed-perturbed data (local/nnet3/run_ivector_common.sh made them), so use
  # those.  The num-leaves is always somewhat less than the num-leaves from
  # the GMM baseline.
  if [ -f $tree_dir/final.mdl ]; then
     echo "$0: $tree_dir/final.mdl already exists, refusing to overwrite it."
     exit 1;
  fi
  steps/nnet3/chain/build_tree.sh \
    --frame-subsampling-factor 3 \
    --context-opts "--context-width=2 --central-position=1" \
    --cmd "$train_cmd" 4500 ${lores_train_data_dir} \
    data/lang_chain $ali_dir $tree_dir
fi

if [ $stage -le 17 ]; then
  mkdir -p $dir
  echo "$0: creating neural net configs using the xconfig parser";

  num_targets=$(tree-info $tree_dir/tree |grep num-pdfs|awk '{print $2}')
  learning_rate_factor=$(echo "print(0.5/$xent_regularize)" | python)
  
  cnn_opts="l2-regularize=0.03"
  ivector_affine_opts="l2-regularize=0.03"
  tdnnf_first_opts="l2-regularize=0.03 dropout-proportion=0.0 bypass-scale=0.0"
  tdnnf_opts="l2-regularize=0.03 dropout-proportion=0.0 bypass-scale=0.66"
  linear_opts="l2-regularize=0.03 orthonormal-constraint=-1.0"
  prefinal_opts="l2-regularize=0.04"
  output_opts="l2-regularize=0.04"

  mkdir -p $dir/configs
  cat <<EOF > $dir/configs/network.xconfig
  input dim=180 name=ivector
  input dim=40 name=input
  fixed-affine-layer name=lda input=Append(-1,0,1,ReplaceIndex(ivector, t, 0)) affine-transform-file=$dir/configs/lda.mat
  # the first splicing is moved before the lda layer, so no splicing here
  relu-batchnorm-dropout-layer name=tdnn1 $affine_opts dim=1536
  tdnnf-layer name=tdnnf2 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=1
  tdnnf-layer name=tdnnf3 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=1
  tdnnf-layer name=tdnnf4 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=1
  tdnnf-layer name=tdnnf5 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=1
  tdnnf-layer name=tdnnf6 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=0
  tdnnf-layer name=tdnnfs3_7 $tdnnf_opts input=tdnnf6 dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnfs3_8 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnfs3_9 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnfs3_10 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnfs3_11 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnfs3_12 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnfs3_13 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnfs3_14 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnfs3_15 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  relu-batchnorm-dropout-layer name=tdnn9 dim=1536 $opts
  linear-component name=prefinal-l dim=256 $linear_opts
  prefinal-layer name=prefinal-chain input=prefinal-l $prefinal_opts big-dim=1536 small-dim=256
  output-layer name=output include-log-softmax=false dim=$num_targets $output_opts
  prefinal-layer name=prefinal-xent input=prefinal-l $prefinal_opts big-dim=1536 small-dim=256
  output-layer name=output-xent dim=$num_targets learning-rate-factor=$learning_rate_factor $output_opts
EOF
  steps/nnet3/xconfig_to_configs.py --xconfig-file $dir/configs/network.xconfig --config-dir $dir/configs/
fi

if [ $stage -le 18 ]; then
  if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $dir/egs/storage ]; then
    utils/create_split_dir.pl \
     /export/b0{3,4,5,6}/$USER/kaldi-data/egs/chime5-$(date +'%m_%d_%H_%M')/s5/$dir/egs/storage $dir/egs/storage
  fi

  steps/nnet3/chain/train.py --stage $train_stage \
    --cmd "$train_cmd --mem 4G" \
    --feat.online-ivector-dir=${train_ivector_dir}_noise \
    --feat.cmvn-opts="--config=conf/online_cmvn.conf" \
    --chain.xent-regularize $xent_regularize \
    --chain.leaky-hmm-coefficient 0.1 \
    --chain.l2-regularize 0.0 \
    --chain.apply-deriv-weights false \
    --chain.lm-opts="--num-extra-lm-states=2000" \
    --trainer.dropout-schedule "$dropout_schedule" \
    --trainer.add-option="--optimization.memory-compression-level=2" \
    --egs.dir "$common_egs_dir" \
    --egs.stage $get_egs_stage \
    --egs.opts "--frames-overlap-per-eg 0 --constrained false --online-cmvn $online_cmvn" \
    --egs.chunk-width $chunk_width \
    --trainer.num-chunk-per-minibatch 64 \
    --trainer.frames-per-iter 1500000 \
    --trainer.num-epochs $num_epochs \
    --trainer.optimization.num-jobs-initial 3 \
    --trainer.optimization.num-jobs-final 16 \
    --trainer.optimization.initial-effective-lrate 0.00025 \
    --trainer.optimization.final-effective-lrate 0.000025 \
    --trainer.max-param-change 2.0 \
    --cleanup.remove-egs $remove_egs \
    --feat-dir=$train_data_dir \
    --tree-dir=$tree_dir \
    --lat-dir=$lat_dir \
    --dir $dir  || exit 1;

fi

if [ $stage -le 19 ]; then
  # Note: it might appear that this data/lang_chain directory is mismatched, and it is as
  # far as the 'topo' is concerned, but this script doesn't read the 'topo' from
  # the lang directory.
  utils/mkgraph.sh --self-loop-scale 1.0 data/lang_test $dir $dir/graph
fi

if [ $stage -le 20 ]; then
  for dset in safe_t_dev1; do
      steps/nnet3/decode.sh --num-threads 4 --nj 20 --cmd "$decode_cmd" \
          --acwt 1.0 --post-decode-acwt 10.0 \
          --online-ivector-dir exp/nnet3${nnet3_affix}/ivectors_${dset}_hires_noise \
         $dir/graph data/${dset}_hires $dir/decode_${dset} || exit 1;
  done
fi
exit 0
