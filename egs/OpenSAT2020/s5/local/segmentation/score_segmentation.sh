#!/usr/bin/env bash
# This script performs scoring on segmentation outputs

#safe_t_dev1_segmented_reseg_hires
segmented_data_set=safe_t_dev1
if [ $stage -le 1 ]; then
    awk '{print $2" "$2" 1"}' $sad_work_dir/safe_t_dev1_seg/segments | \
      sort -u > $sad_work_dir/safe_t_dev1_seg/reco2file_and_channel

    awk '{print $2" "$2" 1"}' data/safe_t_dev1/segments | \
      sort -u > data/safe_t_dev1/reco2file_and_channel

    steps/segmentation/convert_utt2spk_and_segments_to_rttm.py \
      --reco2file-and-channel=data/safe_t_dev1/reco2file_and_channel \
      data/safe_t_dev1/{utt2spk,segments,ref.rttm} || exit 1

    steps/segmentation/convert_utt2spk_and_segments_to_rttm.py \
      --reco2file-and-channel=${sad_work_dir}/${segmented_data_set}_seg/reco2file_and_channel \
      ${sad_work_dir}/${segmented_data_set}_seg/{utt2spk,segments,sys.rttm} || exit 1

    export PATH=$PATH:$KALDI_ROOT/tools/sctk/bin
    md-eval.pl -c 0.25 -r data/safe_t_dev1/ref.rttm \
      -s ${sad_work_dir}/${segmented_data_set}_seg/sys.rttm > \
      ${sad_work_dir}/${segmented_data_set}_seg/md_eval.log
fi
