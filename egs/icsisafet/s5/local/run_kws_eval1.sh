#!/usr/bin/env bash
# Copyright (c) 2018, Johns Hopkins University (Yenda Trmal <jtrmal@gmail.com>)
# License: Apache 2.0

# Begin configuration section.
flen=0.01
stage=0
cmd=run.pl
# End configuration section

. ./utils/parse_options.sh
. ./cmd.sh
. ./path.sh

set -e -o pipefail
set -o nounset                              # Treat unset variables as an error

if [ $stage -le 0 ] ; then
  #cut -d"/" -f 8 data/safe_t_eval1/wav.scp | cut -d"." -f 1 | awk '{print $1 " " $1}'  > data/safe_t_eval1/utt2spk
  cat data/safe_t_eval1/wav.scp | awk '{print $1 " " $1}' > data/safe_t_eval1/utt2spk
  utils/fix_data_dir.sh data/safe_t_eval1
  steps/make_mfcc.sh --cmd "$train_cmd" --nj 20 data/safe_t_eval1/
  steps/compute_cmvn_stats.sh data/safe_t_eval1

  # extract ivector for eval1
  utils/copy_data_dir.sh data/safe_t_eval1 data/safe_t_eval1_hires
  steps/make_mfcc.sh --nj 20 --mfcc-config conf/mfcc_hires.conf \
            --cmd "$train_cmd" data/safe_t_eval1_hires 
  steps/compute_cmvn_stats.sh data/safe_t_eval1_hires
  utils/fix_data_dir.sh data/safe_t_eval1_hires

  nspk=$(wc -l <data/safe_t_eval1_hires/spk2utt)
  nnet3_affix="_1a"
  steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj 20 \
        data/safe_t_eval1_hires exp/ihm/nnet3${nnet3_affix}/extractor \
        exp/ihm/nnet3${nnet3_affix}/ivectors_safe_t_eval1_hires

 # decode
  dir=exp/ihm/chain_1a/tdnn_b_aug
  steps/nnet3/decode.sh --num-threads 4 --nj 20 --cmd "$decode_cmd" \
     --acwt 1.0 --post-decode-acwt 10.0 \
     --online-ivector-dir exp/ihm/nnet3_1a/ivectors_safe_t_eval1_hires \
     $dir/graph data/safe_t_eval1_hires $dir/decode_safe_t_eval1 || exit 1;

  echo "Done decoding."
  steps/get_ctm_conf.sh --cmd "$train_cmd"  --use-segments false data/safe_t_eval1_hires/ \
    data/lang_nosp_test $dir/decode_safe_t_eval1/
fi
exit
data=data/safe_t_eval1_hires
output=data/safe_t_eval1/kws_1306system
lang=data/lang_nosp_test
keywords=local/kws/example/keywords_opensat2020.txt
system=exp/ihm/chain_1a/tdnn_b_bigger_aug/decode_safe_t_eval1
mkdir -p $output
if [ $stage -le 1 ] ; then
  ## generate the auxiliary data files
  ## utt.map
  ## wav.map
  ## trials
  ## frame_length
  ## keywords.int

  ## For simplicity, we do not generate the following files
  ## categories

  ## We will generate the following files later
  ## hitlist
  ## keywords.fsts

  [ ! -f $data/utt2dur ] &&
    utils/data/get_utt2dur.sh $data

  duration=$(cat $data/utt2dur | awk '{sum += $2} END{print sum}' )

  echo $duration > $output/trials
  echo $flen > $output/frame_length

  echo "Number of trials: $(cat $output/trials)"
  echo "Frame lengths: $(cat $output/frame_length)"

  echo "Generating map files"
  cat $data/utt2dur | awk 'BEGIN{i=1}; {print $1, i; i+=1;}' > $output/utt.map
  cat $data/wav.scp | awk 'BEGIN{i=1}; {print $1, i; i+=1;}' > $output/wav.map

  cp $lang/words.txt $output/words.txt
  cp $keywords $output/keywords.txt
  cat $output/keywords.txt | \
    local/kws/keywords_to_indices.pl --map-oov 0  $output/words.txt | \
    sort -u > $output/keywords.int
fi

#model_dir=exp/ihm/tri3
#ali_output_dir=exp/ihm/tri3ali_safe_t_eval1_hires
#if [ $stage -le 2 ] ; then
#  ## this step generates the file hitlist
#
#  ## in many cases, when the reference hits are given, the followin two steps \
#  ## are not needed
#  ## we create the alignments of the data directory
#  ## this is only so that we can obtain the hitlist
#  steps/align_fmllr.sh --nj 5 --cmd "$cmd" \
#    $data data/lang $model_dir $ali_output_dir 
#
#  local/kws/create_hitlist.sh $data $lang data/local/lang \
#    $ali_output_dir $output
#fi


if [ $stage -le 3 ] ; then
  ## this steps generates the file keywords.fsts

  ## compile the keywords (it's done via tmp work dirs, so that
  ## you can use the keywords filtering and then just run fsts-union
  local/kws/compile_keywords.sh $output $lang  $output/tmp.2
  cp $output/tmp.2/keywords.fsts $output/keywords.fsts
  # for example
  #    fsts-union scp:<(sort data/$dir/kwset_${set}/tmp*/keywords.scp) \
  #      ark,t:"|gzip -c >data/$dir/kwset_${set}/keywords.fsts.gz"
  ##
fi

if [ $stage -le 4 ]; then
  ## this is not exactly necessary for a single system and single keyword set
  ## but if you have multiple keyword sets, then it avoids having to recompute
  ## the indices unnecesarily every time (see --indices-dir and --skip-indexing
  ## parameters to the search script bellow).
  for lmwt in `seq 8 14` ; do
    steps/make_index.sh --cmd "$cmd" --lmwt $lmwt --acwt 1.0 \
      --frame-subsampling-factor 3\
      $output $lang $system $system/kws_indices_$lmwt
  done
fi

if [ $stage -le 5 ]; then
  ## find the hits, normalize and score
  local/kws/search.sh --cmd "$cmd" --min-lmwt 8 --max-lmwt 14  \
    --indices-dir $system/kws_indices --skip-indexing true --skip-scoring true\
    $lang $data $system
fi

echo "Done"


