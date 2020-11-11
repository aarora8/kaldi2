#!/usr/bin/env bash
# Copyright (c) 2018, Johns Hopkins University (Yenda Trmal <jtrmal@gmail.com>)
# License: Apache 2.0

# Begin configuration section.
flen=0.01
stage=0
cmd=run.pl
lexicon=data/local/lexicon_3.txt
lexicomp=data/local/lang_nosp_3
lang=data/lang_nosp_test_3
ali=exp/tri3_ali_safe_t_dev1_norm_3
data=data/safe_t_dev1_norm
output=data/safe_t_dev1_norm/kws
keywords=local/kws/example/kwlist/query2350.keywords.txt
# End configuration section

. ./utils/parse_options.sh
. ./path.sh

set -e -o pipefail
set -o nounset                              # Treat unset variables as an error

mkdir -p $output
if [ $stage -le 0 ] ; then
  echo "generating normalized data/safe_t_dev1 ..."
  utils/copy_data_dir.sh data/safe_t_dev1 $data
  local/safet_cleanup_transcripts.py --no-unk-replace $lexicon \
      data/safe_t_dev1/transcripts $data/transcripts.clean > /dev/null

  cat $data/transcripts.clean | \
      awk '{printf $1""FS;for(i=6; i<=NF; ++i) printf "%s",$i""FS; print""}' | \
      sort > $data/text
fi 

# default_kws=${output%s*}s  # https://stackoverflow.com/questions/27658675/how-to-remove-last-n-characters-from-a-string-in-bash

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
    local/kws/keywords_to_indices.pl --map-oov $(( $( wc -l ${lang}/words.txt | cut -d' ' -f1 )+1 )) \
    $output/words.txt | \
    sort -u > $output/keywords.int
fi

if [ $stage -le 2 ] ; then
  ## this step generates the file hitlist
  ## we create the alignments of the data directory
  ## this is only so that we can obtain the hitlist

  # gmm alignment file is not available for large lexicon
  steps/align_fmllr.sh --nj 5 --cmd "$cmd" \
    $data $lang exp/tri3_train_all $ali

  local/kws/create_hitlist.sh data/safe_t_dev1_norm $lang $lexicomp \
    $ali $output
fi

if [ $stage -le 3 ] ; then
  ## this steps generates the file keywords.fsts
  local/kws/compile_keywords.sh $output $lang  $output/tmp.2
  cp $output/tmp.2/keywords.fsts $output/keywords.fsts
fi

system=exp/chain_all/tdnn_all/decode_safe_t_dev1/
if [ $stage -le 4 ]; then
  for lmwt in `seq 8 14` ; do
    steps/make_index.sh --cmd "$cmd" --lmwt $lmwt --acwt 1.0 \
      --frame-subsampling-factor 3 \
      $output $lang $system $system/kws_indices_$lmwt
  done
fi

if [ $stage -le 5 ]; then
  ## find the hits, normalize and score
  local/kws/search.sh --cmd "$cmd" --min-lmwt 8 --max-lmwt 14  \
    --indices-dir $system/kws_indices --skip-indexing true \
    $lang $data $system
fi
echo "Done"
