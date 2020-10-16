#!/usr/bin/env bash


# 1. oracle segmentation: decode_safe_t_dev1
# bash score_sclite.sh --stage 1  \ 
# --stm /export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5/tmp/stm \
# --ctm-dir tmp1 \
# --data-dir /export/c03/aarora8/kaldi2/egs/OpenSAT2020/s5/other/data_exp_for_report/data/safe_t_dev1_hires/ \
# --decode-dir /export/c03/aarora8/kaldi2/egs/OpenSAT2020/s5/other/data_exp_for_report/exp/ihm/chain_1a/tdnn_b_bigger_2_aug/decode_safe_t_dev1 \
# --graph-dir /export/c03/aarora8/kaldi2/egs/OpenSAT2020/s5/other/data_exp_for_report/exp/ihm/chain_1a/tdnn_b_bigger_2_aug/graph_3

# 2. paragraph revel: decode_safe_t_dev1_whole
# bash score_sclite.sh --stage 1  \ 
# --stm /export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5/tmp/stm \
# --ctm-dir tmp2 \
# --data-dir /export/c03/aarora8/kaldi2/egs/OpenSAT2020/s5/other/data_exp_for_report/data/safe_t_dev1_whole/ \
# --decode-dir /export/c03/aarora8/kaldi2/egs/OpenSAT2020/s5/other/data_exp_for_report/exp/ihm/chain_1a/tdnn_b_bigger_2_aug/decode_safe_t_dev1_whole \
# --graph-dir /export/c03/aarora8/kaldi2/egs/OpenSAT2020/s5/other/data_exp_for_report/exp/ihm/chain_1a/tdnn_b_bigger_2_aug/graph_3

# 3. uniform segmentation: decode_safe_t_dev1_segmented
# bash score_sclite.sh --stage 1  \ 
# --stm /export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5/tmp/stm \
# --ctm-dir tmp3 \
# --data-dir /export/c03/aarora8/kaldi2/egs/OpenSAT2020/s5/other/data_exp_for_report/data/safe_t_dev1_segmented/ \
# --decode-dir /export/c03/aarora8/kaldi2/egs/OpenSAT2020/s5/other/data_exp_for_report/exp/ihm/chain_1a/tdnn_b_bigger_2_aug/decode_safe_t_dev1_segmented \
# --graph-dir /export/c03/aarora8/kaldi2/egs/OpenSAT2020/s5/other/data_exp_for_report/exp/ihm/chain_1a/tdnn_b_bigger_2_aug/graph_3

# 4. asr resegmentation: decode_safe_t_dev1_segmented_reseg 
# bash score_sclite.sh --stage 1  \ 
# --stm /export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5/tmp/stm \
# --ctm-dir tmp4 \
# --data-dir /export/c03/aarora8/kaldi2/egs/OpenSAT2020/s5/other/data_exp_for_report/data/safe_t_dev1_segmented_reseg_hires/ \
# --decode-dir /export/c03/aarora8/kaldi2/egs/OpenSAT2020/s5/other/data_exp_for_report/exp/ihm/chain_1a/tdnn_b_bigger_2_aug/decode_safe_t_dev1_segmented_reseg \
# --graph-dir /export/c03/aarora8/kaldi2/egs/OpenSAT2020/s5/other/data_exp_for_report/exp/ihm/chain_1a/tdnn_b_bigger_2_aug/graph_3


KALDI_ROOT=/export/fs04/a12/rhuang/kaldi/
sclite="$KALDI_ROOT/tools/sctk/bin/sclite"

stm=
ctm_dir=

data_dir=
decode_dir=
graph_dir=

. ./path.sh
. ./cmd.sh
. utils/parse_options.sh

text=${datadir}/text
segments=${datadir}/segments

# should fix this later
reco2file_and_channel=/export/fs04/a12/rhuang/kaldi/egs/opensat2020/s5/data/safe_t_dev1_seg_segmented_hires/reco2file_and_channel

mkdir -p ${ctm_dir}

## get stm file
if [ $stage -le 0 ]; then
  ./local/get_stm.py ${text} ${segments} ${stm}
fi

# get ctm file
if [ $stage -le 1 ]; then
  steps/get_ctm_fast.sh --lmwt 8 --cmd "$train_cmd" --frame-shift 0.03 ${data_dir} ${graph_dir} ${decode_dir} ${ctm_dir}
  utils/ctm/resolve_ctm_overlaps.py ${segments} ${ctm_dir}/ctm  - | \
  	utils/convert_ctm.pl ${segments} ${reco2file_and_channel} | \
  	grep -v "<UNK>" - | \
  	sort -k1,1 -k3,3n - > tmp/tmp$n/ctm.filtered

fi

# sclite scoring
#
# [reference]
# http://my.fit.edu/~vkepuska/ece5527/sctk-2.3-rc1/doc/
if [ $stage -le 2 ]; then
	$sclite -r tmp/stm $stm -h ${ctm_dir}/ctm.filtered ctm -o dtl sum prf
fi


