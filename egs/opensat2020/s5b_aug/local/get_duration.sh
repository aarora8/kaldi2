#!/usr/bin/env bash

#5. This script also reads a flac file and converts into into wav file but do it in a proper way.
#while read -r line;
#  do
#    wav_id=$(echo "$line" | cut -d" " -f 1)
#    wav_path=$(echo "$line" | cut -d" " -f 6)
#    echo $wav_id
#    echo $wav_path
#    flac -s -c -d $wav_path | sox - -b 16 -t wav -r 16000 -c 1  /export/c02/aarora8/kaldi2/egs/opensat2020/s5b_aug/data/safe_t_dev1/wav_files/${wav_id}.wav
#done <  /export/c02/aarora8/kaldi2/egs/opensat2020/s5b_aug/data/safe_t_dev1/wav.scp


#2. This part creates wav.scp, utt2spk and spk2utt for the noise extracted and converted to 16khz
for wav_name in /export/c02/aarora8/kaldi2/egs/opensat2020/s5b_aug/data/safe_t_dev1/wav_files/*.wav; do
  recording_id=$(echo "$wav_name" | cut -d"/" -f 12)
  wav_id=$(echo "$recording_id" | cut -d"." -f 1)
  echo $wav_id $wav_name >> /export/c02/aarora8/kaldi2/egs/opensat2020/s5b_aug/data/safe_t_dev1/wav_files/wav.scp
  #echo $wav_id $wav_id >> noise/utt2spk
  #echo $wav_id $wav_id >> noise/spk2utt
done

