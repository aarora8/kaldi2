#!/usr/bin/env bash
set -e -o pipefail
stage=0

nj=96
xent_regularize=0.1
dropout_schedule='0,0@0.20,0.5@0.50,0'

train_set=train_cleaned
gmm=tri5b
num_threads_ubm=8
nnet3_affix=_org_1d  # cleanup affix for nnet3 and chain dirs, e.g. _cleaned

online_cmvn=true

train_stage=-10
tree_affix=  # affix for tree directory, e.g. "a" or "b", in case we change the configuration.
tdnn_affix=1g  #affix for TDNN directory, e.g. "a" or "b", in case we change the configuration.
common_egs_dir=  # you can set this to use previously dumped egs.
remove_egs=true
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


gmm_dir=exp/$gmm
ali_dir=exp/${gmm}_ali_${train_set}_sp
tree_dir=exp/chain${nnet3_affix}/tree_bi${tree_affix}
lat_dir=exp/chain${nnet3_affix}/${gmm}_${train_set}_sp_lats
dir=exp/chain${nnet3_affix}/tdnn${tdnn_affix}_sp
train_data_dir=data/${train_set}_sp_hires
lores_train_data_dir=data/${train_set}_sp
train_ivector_dir=exp/nnet3${nnet3_affix}/ivectors_${train_set}_sp_hires
lang=data/lang_chain

num_epochs=6
chunk_width=140,100,160
xent_regularize=0.1
dropout_schedule='0,0@0.20,0.5@0.50,0'
srand=0

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
    cp -r data/lang_sp_test data/lang_chain
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
    data/lang_sp_test $gmm_dir $lat_dir
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
  input dim=100 name=ivector
  input dim=40 name=input
  # this takes the MFCCs and generates filterbank coefficients.  The MFCCs
  # are more compressible so we prefer to dump the MFCCs to disk rather
  # than filterbanks.
  idct-layer name=idct input=input dim=40 cepstral-lifter=22 affine-transform-file=$dir/configs/idct.mat
  linear-component name=ivector-linear $ivector_affine_opts dim=200 input=ReplaceIndex(ivector, t, 0)
  batchnorm-component name=ivector-batchnorm target-rms=0.025
  batchnorm-component name=idct-batchnorm input=idct
  spec-augment-layer name=idct-spec-augment freq-max-proportion=0.5 time-zeroed-proportion=0.2 time-mask-max-frames=20
  batchnorm-component name=idct-spec-augment-batchnorm input=idct-spec-augment
  combine-feature-maps-layer name=combine_inputs input=Append(idct-spec-augment-batchnorm, ivector-batchnorm) num-filters1=1 num-filters2=5 height=40
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
  tdnnf-layer name=tdnnf16 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf17 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf18 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf19 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf20 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf21 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf22 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
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
    --feat.online-ivector-dir=$train_ivector_dir \
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

two_stage_decoding=true
if [ $two_stage_decoding ]; then stage=21; fi

if [ $stage -le 20 ]; then
  if [ $two_stage_decoding ]; then
    local/decode.sh \
      --ivector-dir exp/nnet3${nnet3_affix}/ \
      data/safe_t_dev1 data/lang_test \
      $dir/graph $dir
  else
    steps/nnet3/decode.sh --num-threads 4 --nj 20 --cmd "$decode_cmd" \
      --acwt 1.0 --post-decode-acwt 10.0 \
      --online-ivector-dir exp/nnet3${nnet3_affix}/ivectors_safe_t_dev1_hires \
      --scoring-opts "--min-lmwt 5 " \
      $dir/graph data/safe_t_dev1_hires $dir/decode_safe_t_dev1 || exit 1;
  fi
fi

exit 0
