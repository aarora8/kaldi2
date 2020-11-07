#!/usr/bin/env bash
# Copyright (c) 2018, Johns Hopkins University (Yenda Trmal <jtrmal@gmail.com>)
# License: Apache 2.0

# Begin configuration section.
flen=0.01
stage=0
cmd=run.pl
data=data/safe_t_dev1_norm
lang=data/lang_nosp_test_3
keywords=local/kws/example/opensat_dev.words.keywords.txt
#keywords=local/kws/example/keywords_opensat2019.txt
output=data/safe_t_dev1_norm/kws
# End configuration section

. ./utils/parse_options.sh
. ./path.sh

set -e -o pipefail
set -o nounset                              # Treat unset variables as an error

mkdir -p $output
if [ $stage -le -1 ] ; then
  echo "generating normalized data/safe_t_dev1 ..."
  utils/copy_data_dir.sh data/safe_t_dev1 data/safe_t_dev1_norm
  local/safet_cleanup_transcripts.py --no-unk-replace data/local/lexicon.txt \
      data/safe_t_dev1/transcripts data/safe_t_dev1_norm/transcripts.clean > /dev/null

  cat data/safe_t_dev1_norm/transcripts.clean | \
      awk '{printf $1""FS;for(i=6; i<=NF; ++i) printf "%s",$i""FS; print""}' | \
      sort > data/safe_t_dev1_norm/text
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

  #steps/align_fmllr.sh --nj 5 --cmd "$cmd" \
  #  $data $lang exp/tri3_train_all exp/tri3_ali_safe_t_dev1_norm

  local/kws/create_hitlist.sh data/safe_t_dev1_norm data/lang_nosp_test data/local/lang_nosp \
    exp/tri3_ali_safe_t_dev1_norm $output

  #cp /export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5/meta_dexp/safet_hub4_bugfixed/data/safe_t_dev1_norm/kws/hitlist data/safe_t_dev1_norm/kws_givenhlist/hitlist

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
