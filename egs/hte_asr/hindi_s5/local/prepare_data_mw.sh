#!/bin/bash
ROOT=/export/common/data/corpora/ASR/IITM_Indian_ASR_Challenge_2021/Indian_Language_Database
language=Hindi

mkdir data
cd data
cp -r ${ROOT}/${language}/transcription/{train}_${language} .
cd ..
for d in train; do
  mv data/${d}_${language}/wav.scp data/${d}_${language}/wav.scp.bk && \
    awk -v var=${ROOT}/${language} '{print $1,var"/"$2}' data/${d}_${language}/wav.scp.bk \
    > data/${d}_${language}/wav.scp
  sed 's/\t */ /' data/${d}_${language}/text > data/${d}_${language}/text.tmp
  awk '(NF > 1)' data/${d}_${language}/text.tmp > data/${d}_${language}/text
  ./utils/fix_data_dir.sh data/${d}_${language}
done
