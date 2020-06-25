#!/usr/bin/env bash

#/export/c12/aarora8/OpenSAT/16khz_OpenSAT_noise

#for wav_path_name in /export/c12/aarora8/OpenSAT/OpenSAT_noise/*.wav; do
#  wav_id=$(echo "$wav_path_name" | cut -f7 -d "/")
#  echo $wav_id
#  sox $wav_path_name -r 16000 -c 1 -b 16 /export/c12/aarora8/OpenSAT/16khz_OpenSAT_noise/$wav_id
#done

#for wav_name in /export/c12/aarora8/OpenSAT/16khz_OpenSAT_noise/*.wav; do
#  recording_id=$(echo "$wav_name" | cut -d"/" -f 7)
#  wav_id=$(echo "$recording_id" | cut -d"." -f 1)
#  echo $wav_id $wav_name >> noise/wav.scp
#  echo $wav_id $wav_id >> noise/utt2spk
#  echo $wav_id $wav_id >> noise/spk2utt
#done

#while read -r line;
#  do
#    wav_id=$(echo "$line" | cut -d" " -f 1)
#    grep $wav_id /export/c02/aarora8/kaldi2/egs/opensat2020/s5b_aug/data/train/segments | awk '{print $3 " " $4}' >> data/train/time_stamp/$wav_id
#done < /export/c02/aarora8/kaldi2/egs/opensat2020/s5b_aug/data/train/wav.scp

#for wav_path_name in /export/c02/aarora8/kaldi2/egs/opensat2020/s5b_aug/data/train/time_stamp/*; do
#  wav_name=$(echo "$wav_path_name" | cut -f12 -d "/")
#  wav_id=$(echo "$wav_name" | cut -d"." -f 1)
#  wav_id2=$(echo "$wav_id" | cut -c1-33)
#  wav_id3=${wav_id2}mixed
#  echo $wav_id3
#  flac -s -c -d /export/corpora5/opensat_corpora/LDC2019E37/LDC2019E37_SAFE-T_Corpus_Speech_Recording_Audio_Training_Data_R1_V1.1/data/audio/${wav_id3}.flac | sox - -b 16 -t wav -r 16000 -c 1 /export/c02/aarora8/kaldi2/egs/opensat2020/s5b_aug/data/train/wav_files/${wav_id}.wav
#done


#while read -r line;
#  do
#    wav_id=$(echo "$line" | cut -d" " -f 1)
#    wav_path=$(echo "$line" | cut -d" " -f 6)
#    echo $wav_id
#    echo $wav_path
#    flac -s -c -d $wav_path | sox - -b 16 -t wav -r 16000 -c 1 /export/c02/aarora8/kaldi2/egs/opensat2020/s5b_aug/data/train/wav_files2/${wav_id}.wav
#done < /export/c02/aarora8/kaldi2/egs/opensat2020/s5b_aug/data/train/wav.scp


for wav_name in /export/c12/aarora8/OpenSAT/combined_noise/*.wav; do
  recording_id=$(echo "$wav_name" | cut -d"/" -f 7)
  wav_id=$(echo "$recording_id" | cut -d"." -f 1)
  echo $wav_id $wav_name >> /export/c12/aarora8/OpenSAT/combined_noise_wavfile/wav.scp
  echo $wav_id $wav_id >> /export/c12/aarora8/OpenSAT/combined_noise_wavfile/utt2spk
  echo $wav_id $wav_id >> /export/c12/aarora8/OpenSAT/combined_noise_wavfile/spk2utt
done
