#!/usr/bin/env bash
# 2020 Dongji Gao

stage=0

[ -f ./path.sh ] && . ./path.sh
. ./parse_options.sh
. ./cmd.sh

sclite="$KALDI_ROOT/tools/sctk/bin/sclite"

text="data/safe_t_dev1/text"
segments="data/safe_t_dev1/segments"
stm="tmp/stm"

# get stm file
if [ $stage -le 0 ]; then
  ./local/get_stm.py ${text} ${segments} ${stm}
fi

# sclite scoring
if [ $stage -le 1 ]; then
    ${sclite} -f 0 -s -m hyp -r tmp/stm stm -h tmp/ctm_2 ctm > tmp/sclite_scoring_result_orig
fi
