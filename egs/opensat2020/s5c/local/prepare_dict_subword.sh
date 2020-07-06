#!/usr/bin/env bash

# Copyright 2017 QCRI (author: Ahmed Ali)
#           2019 Dongji Gao
# Apache 2.0
# This script prepares the subword dictionary.

set -e
dir=data/local/dict
num_merges=100
stage=0
. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh || exit 1;
mkdir -p $dir data/local/lexicon_data

if [ $stage -le 0 ]; then
  echo "$0: Downloading text for lexicon... $(date)."
  cat data/train/text | cut -d ' ' -f 2- | tr -s " " "\n" | sort -u | grep -v '<UNK>' >> data/local/lexicon_data/processed_lexicon
  cut -d' ' -f2- data/train/text | \
python3 <(
cat << "END"
import os, sys, io;
infile = io.TextIOWrapper(sys.stdin.buffer, encoding='utf-8');
output = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8');
phone_dict = dict();
for line in infile:
    line_vect = line.strip().split();
    for word in line_vect:
        for phone in word:
            phone_dict[phone] = phone;
for phone in phone_dict.keys():
      output.write(phone+ '\n');
END
   ) > data/local/phones.txt

fi


if [ $stage -le 0 ]; then
  echo "$0: processing lexicon text and creating lexicon... $(date)."
  local/prepare_lexicon.py
fi

cut -d' ' -f2- $dir/lexicon.txt | sed 's/SIL//g' | tr ' ' '\n' | sort -u | sed '/^$/d' >$dir/nonsilence_phones.txt || exit 1;

#echo UNK >> $dir/nonsilence_phones.txt

#echo SIL > $dir/silence_phones.txt

#echo SIL >$dir/optional_silence.txt

echo -n "" >$dir/extra_questions.txt

# Make a subword lexicon based on current word lexicon
glossaries="<UNK> <sil>"
if [ $stage -le 0 ]; then
  echo "$0: making subword lexicon... $(date)."
  cut -d' ' -f2- data/train/text > data/local/train_data.txt
  # get pair_code file
  cat data/local/phones.txt data/local/train_data.txt | sed 's/<sil>//g;s/<UNK>//g' | utils/lang/bpe/learn_bpe.py -s $num_merges > data/local/pair_code.txt
  mv $dir/lexicon.txt $dir/lexicon_word.txt
  # get words
  cut -d ' ' -f1 $dir/lexicon_word.txt > $dir/words.txt
  utils/lang/bpe/apply_bpe.py -c data/local/pair_code.txt --glossaries $glossaries < $dir/words.txt | \
  sed 's/ /\n/g' | sort -u > $dir/subwords.txt
  sed 's/./& /g' $dir/subwords.txt | sed 's/@ @ //g' | sed 's/*/V/g' | paste -d ' ' $dir/subwords.txt - > $dir/lexicon.txt
fi

sed -i '1i<UNK> <unk>' $dir/lexicon.txt

echo 'SIL <sil>' >> $dir/lexicon.txt

echo -e "SIL <sil>\n<UNK> <unk>" |  cat - local/hesitations.txt | cut -d ' ' -f 2- | sed 's/ /\n/g' | \
  sort -u | sed '/^ *$/d' > $dir/silence_phones.txt

echo '<sil>' > $dir/optional_silence.txt
echo "$0: Dictionary preparation succeeded"
