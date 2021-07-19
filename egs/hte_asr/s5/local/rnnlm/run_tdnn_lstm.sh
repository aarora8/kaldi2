#!/usr/bin/env bash
# This script trains LSTM based LMs on transcription and perform lattice rescoring
# on 1st pass decoding results.
# Begin configuration section.
dir=exp/rnnlm_lstm_1b
embedding_dim=512
lstm_rpd=128
lstm_nrpd=128
embedding_l2=0.003 # embedding layer l2 regularize
comp_l2=0.003 # component-level l2 regularize
output_l2=0.001 # output-layer l2 regularize
stage=-10
train_stage=-10
score_stage=0
run_lat_rescore=true
run_nbest_rescore=true
run_backward_rnnlm=false
ac_model_dir=exp/chain_1a/cnn_tdnn_1a/
decode_dir_suffix=rnnlm_1b
ngram_order=4 # approximate the lattice-rescoring by limiting the max-ngram-order
              # if it's set, it merges histories in the lattice if they share
              # the same ngram history and this prevents the lattice from 
              # exploding exponentially
pruned_rescore=true

. ./cmd.sh
. ./utils/parse_options.sh

train_text=data/train_English_final/text
dev_text=data/dev_English_jhu_ho_spk/text
text_dir=data/rnnlm/text
mkdir -p $dir/config
set -e

for f in $text; do
  [ ! -f $f ] && \
    echo "$0: expected file $f to exist; search for local/wsj_extend_dict.sh in run.sh" && exit 1
done

if [ $stage -le 0 ]; then
  mkdir -p $text_dir
  cat $train_text | cut -d ' ' -f2- > $text_dir/train.txt
  cat $dev_text | cut -d ' ' -f2- > $text_dir/dev.txt
fi

if [ $stage -le 1 ]; then
  cp data/lang_nosp_test/words.txt $dir/config/
  n=`cat $dir/config/words.txt | wc -l`
  echo "<brk> $n" >> $dir/config/words.txt

  # words that are not present in words.txt but are in the training or dev data, will be
  # mapped to <unk> during training.
  echo "<UNK>" >$dir/config/oov.txt

  cat > $dir/config/data_weights.txt <<EOF
train   1   1.0
EOF

  rnnlm/get_unigram_probs.py --vocab-file=$dir/config/words.txt \
                             --unk-word="<UNK>" \
                             --data-weights-file=$dir/config/data_weights.txt \
                             $text_dir | awk 'NF==2' >$dir/config/unigram_probs.txt

  # choose features
  rnnlm/choose_features.py --unigram-probs=$dir/config/unigram_probs.txt \
                           --use-constant-feature=true \
                           --special-words='<s>,</s>,<brk>,<UNK>,<Noise/>' \
                           $dir/config/words.txt > $dir/config/features.txt

lstm_opts="l2-regularize=$comp_l2"
tdnn_opts="l2-regularize=$comp_l2"
output_opts="l2-regularize=$output_l2"

  cat >$dir/config/xconfig <<EOF
input dim=$embedding_dim name=input
relu-renorm-layer name=tdnn1 dim=$embedding_dim $tdnn_opts input=Append(0, IfDefined(-1))
fast-lstmp-layer name=lstm1 cell-dim=$embedding_dim recurrent-projection-dim=$lstm_rpd non-recurrent-projection-dim=$lstm_nrpd $lstm_opts
relu-renorm-layer name=tdnn2 dim=$embedding_dim $tdnn_opts input=Append(0, IfDefined(-3))
fast-lstmp-layer name=lstm2 cell-dim=$embedding_dim recurrent-projection-dim=$lstm_rpd non-recurrent-projection-dim=$lstm_nrpd $lstm_opts
relu-renorm-layer name=tdnn3 dim=$embedding_dim $tdnn_opts input=Append(0, IfDefined(-3))
output-layer name=output $output_opts include-log-softmax=false dim=$embedding_dim
EOF
  rnnlm/validate_config_dir.sh $text_dir $dir/config
fi

if [ $stage -le 2 ]; then
  rnnlm/prepare_rnnlm_dir.sh $text_dir $dir/config $dir
fi

if [ $stage -le 3 ]; then
  rnnlm/train_rnnlm.sh --num-jobs-initial 1 --num-jobs-final 1 \
                       --embedding_l2 $embedding_l2 \
                       --stage $train_stage --num-epochs 60 --cmd "$gpu_cmd" $dir
fi
if [ $stage -le 4 ] && $run_lat_rescore; then
  echo "$0: Perform lattice-rescoring on $ac_model_dir"
  pruned=
  if $pruned_rescore; then
    pruned=_pruned
  fi
  for decode_set in dev_English_jhu_ho_spk; do
    decode_dir=${ac_model_dir}/decode_${decode_set}

    # Lattice rescoring
    rnnlm/lmrescore$pruned.sh \
      --cmd "$decode_cmd --mem 4G" \
      --acwt 0.1 \
      --weight 0.4 --max-ngram-order $ngram_order \
      data/lang_nosp_test $dir \
      data/${decode_set}_hires ${decode_dir} \
      ${decode_dir}_${decode_dir_suffix}_0.4
  done
fi

if [ $stage -le 5 ] && $run_lat_rescore; then
  echo "$0: Perform lattice-rescoring on $ac_model_dir"
  pruned=
  if $pruned_rescore; then
    pruned=_pruned
  fi
  for decode_set in dev_English_hires; do
    decode_dir=${ac_model_dir}/decode_${decode_set}

    # Lattice rescoring
    rnnlm/lmrescore$pruned.sh \
      --cmd "$decode_cmd --mem 4G" \
      --acwt 0.1 \
      --weight 0.4 --max-ngram-order $ngram_order \
      data/lang_nosp_test $dir \
      data/${decode_set} ${decode_dir} \
      ${decode_dir}_${decode_dir_suffix}_0.4
  done
fi
exit 0
