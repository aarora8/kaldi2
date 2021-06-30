#!/usr/bin/env bash

dev=exp/chain_1a/cnn_tdnn_1a/decode_dev_nodup
conditions="_long_ 104_eng_ IE_vy 02_Balancing 104_hin_ BH_hi_IN_02042021_ 104_tam_"
echo "$0 $@"
. ./path.sh
. parse_options.sh

# get language model weight and word insertion penalty from the dev set
best_lmwt=`cat $dev/scoring_kaldi/wer_details/lmwt`
best_wip=`cat $dev/scoring_kaldi/wer_details/wip`
echo "best LM weight: $best_lmwt"
echo "insertion penalty weight: $best_wip"
score_result=$dev/scoring_kaldi/wer_details/per_utt

for cond in $conditions; do
  nerr=`grep "\#csid" $score_result | grep $cond | awk '{sum+=$4+$5+$6} END {print sum}'`
  nwrd=`grep "\#csid" $score_result | grep $cond | awk '{sum+=$3+$4+$6} END {print sum}'`
  wer=`echo "100 * $nerr / $nwrd" | bc`  
  # report the results
  echo -n "Condition $cond: "
  echo -n "#words $nwrd, "
  echo -n "#errors $nerr, "
  echo "wer $wer %"
done

echo -n "overall: "
nerr=`grep "\#csid" $score_result | awk '{sum+=$4+$5+$6} END {print sum}'`
nwrd=`grep "\#csid" $score_result | awk '{sum+=$3+$4+$6} END {print sum}'`
wer=`echo "100 * $nerr / $nwrd" | bc`
echo -n "#words $nwrd, "
echo -n "#errors $nerr, "
echo "wer $wer %"
