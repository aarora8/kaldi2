#!/usr/bin/env bash
# Author: Ashish Arora
# Apache 2.0

nj=65
stage=0

. ./cmd.sh
. ./path.sh
. utils/parse_options.sh

if [ $# != 1 ]; then
   echo "Wrong #arguments ($#, expected 1)"
   echo "Usage: local/safet_extract_noises.sh [options] <indir>"
   echo "This script extract noises and use it for augmentation"
   exit 1;
fi

indir=$1
#outdir=$2

# it creates a text file which have all the time stamps belonging to that wav file
# which have transcription. The $indir/time_stamp/ directory will contain list of
# time segments (where the transcription is present) for wavfile
if [ $stage -le 0 ]; then
  mkdir -p $indir/time_stamp/
  while read -r line;
    do
      wav_id=$(echo "$line" | cut -d" " -f 1)
      grep $wav_id $indir/segments | awk '{print $3 " " $4}' >> $indir/time_stamp/$wav_id
  done < $indir/wav.scp
fi

## it reads a flac file and converts into into wav file
if [ $stage -le 1 ]; then
  mkdir -p $indir/wav_files/
  while read -r line;
    do
      wav_id=$(echo "$line" | cut -d" " -f 1)
      wav_path=$(echo "$line" | cut -d" " -f 6)
      echo $wav_id
      echo $wav_path
      flac -s -c -d $wav_path | sox - -b 16 -t wav -r 16000 -c 1 $indir/wav_files/${wav_id}.wav
  done < $indir/wav.scp
fi

## it reads a $indir/wav.scp file and creates audio_list
if [ $stage -le 2 ]; then
  while read -r line;
    do
      wav_id=$(echo "$line" | cut -d" " -f 1)
      echo $wav_id >> data/local/audio_list
  done < $indir/wav.scp
fi

## it reads a audio wav files, wav time stamps and audio list file and creates noises
if [ $stage -le 3 ]; then
  local/safet_extract_noises.py $indir/wav_files $indir/time_stamp data/local/audio_list distant_noises
fi

# it will give to 10050 noise wav files, its total duration is 55hrs
#if [ $stage -le 4 ]; then
#  for wav_name in distant_noises/*.wav; do
#    soxi -D $wav_name >> data/local/audio_list/
#  done
#fi

# it will give to 10050 noise wav files, its total duration is 55hrs
# utt2spk: <utterance-id> <speaker-id>: noise1 noise1
# wav.scp <recording-id> <wav-path> : noise1 distant_noises/noise1.wav
# segments:  <utterance-id> <recording-id> <segment-begin> <segment-end> segments: noise1 noise1 0 20
if [ $stage -le 5 ]; then
  mkdir -p noise/
  for wav_name in distant_noises/*.wav; do
    recording_id=$(echo "$wav_name" | cut -d"/" -f 2)
    utt_id=$(echo "$recording_id" | cut -d"." -f 1)
    echo $utt_id $wav_name >> noise/wav.scp
    echo $utt_id $utt_id >> noise/utt2spk
    echo $utt_id $utt_id >> noise/spk2utt
    echo $utt_id $utt_id 0 20 >> noise/segments
  done
  awk '{ sum += $4 - $3 } END { print sum/3600 }' noise/segments
fi

