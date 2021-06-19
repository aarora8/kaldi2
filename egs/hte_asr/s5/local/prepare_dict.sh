#!/usr/bin/env bash

dst_dir=data/local/dict_nosp
silence_phones=$dst_dir/silence_phones.txt
optional_silence=$dst_dir/optional_silence.txt
nonsil_phones=$dst_dir/nonsilence_phones.txt
lexicon_raw_nosil=$dst_dir/lexicon/lexicon_raw_nosil.txt

mkdir -p $dst_dir
echo "Preparing phone lists"
echo SIL > $silence_phones
echo SIL > $optional_silence

local/get_phones_from_lexicon.py data/lexicon.txt $nonsil_phones

(echo '!SIL SIL'; echo '<UNK> SIL'; ) |\
cat - data/lexicon.txt | sort | uniq >$dst_dir/lexicon.txt
echo "Lexicon text file saved as: $dst_dir/lexicon.txt"

exit 0
