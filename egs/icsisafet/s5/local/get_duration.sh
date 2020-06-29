#!/usr/bin/env bash

#/export/c12/aarora8/OpenSAT/16khz_OpenSAT_noise

#for wav_path_name in /export/c12/aarora8/OpenSAT/OpenSAT_noise/*.wav; do
#  wav_id=$(echo "$wav_path_name" | cut -f7 -d "/")
#  echo $wav_id
#  sox $wav_path_name -r 16000 -c 1 -b 16 /export/c12/aarora8/OpenSAT/16khz_OpenSAT_noise/$wav_id
#done

#for wav_name in ls /export/c12/aarora8/OpenSAT/16khz_OpenSAT_noise/*.wav; do
#  recording_id=$(echo "$wav_name" | cut -d"/" -f 7)
#  wav_id=$(echo "$recording_id" | cut -d"." -f 1)
#  echo $wav_id $wav_name >> noise/wav.scp
#  echo $wav_id $wav_id >> noise/utt2spk
#  echo $wav_id $wav_id >> noise/spk2utt
#done

# 000001_0000000_0000112_0001_20190122_200119_part1_train_xx /export/c02/aarora8/kaldi2/egs/icsisafet/s5/data/ihm/train_isa/data/raw_mfcc_train_isa.1.ark:59
#cut -d"/" -f 11 data/ihm/train_aug/feats.scp > data/ihm/train_aug/data_loca1
#cat data/ihm/train_aug/data_loca1 | sort | uniq | head
#while read -r line;
#  do
#    data_dir=$(echo "$line" | cut -d"/" -f 11)
#    echo $data_dir >> data/ihm/train_aug/data_loca
#done < data/ihm/train_aug/feats.scp
