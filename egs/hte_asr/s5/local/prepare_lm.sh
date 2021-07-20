#!/usr/bin/env bash
echo "$0 $@"
[ -f path.sh ]  && . ./path.sh

echo "-------------------------------------"
echo "Building an SRILM language model     "
echo "-------------------------------------"


tgtdir=data/local/lm
train_text=data/local/lm_train_text
dev_text=data/local/lm_dev_text
words_file=data/lang_nosp_test/words.txt
long_train_text=data/local/lm_long_train_text
long_dev_text=data/local/lm_long_dev_text
oov_symbol="<UNK>"

##End of configuration

#cat data/train/text | cut -d " " -f 2-  > $train_text
#cat data/dev/text | cut -d " " -f 2-  > $dev_text

local/get_text_from_transcript.py data/train_English_final/text $train_text
local/get_text_from_transcript.py data/dev_English_jhu_ho_spk/text $dev_text

local/get_long_text_from_transcript.py data/train_English_final/text $long_train_text
local/get_long_text_from_transcript.py data/dev_English_jhu_ho_spk/text $long_dev_text

mkdir -p $tgtdir
for f in $words_file $long_train_text $long_dev_text; do
  [ ! -s $f ] && echo "No such file $f" && exit 1;
done

echo "Using train text: $long_train_text"
echo "Using dev text  : $long_dev_text"

# Extract the word list from the training dictionary; exclude special symbols
sort $words_file | awk '{print $1}' | grep -v '\#0' | grep -v '<eps>' | grep -v -F "$oov_symbol" > $tgtdir/vocab
echo vocab contains `cat $tgtdir/vocab | perl -ne 'BEGIN{$l=$w=0;}{split; $w+=$#_; $w++; $l++;}END{print "$l lines, $w words\n";}'`

cat $long_train_text > $tgtdir/train.txt
echo $long_train_text contains `cat $long_train_text | perl -ane 'BEGIN{$w=$s=0;}{$w+=@F; $w--; $s++;}END{print "$w words, $s sentences\n";}'`
echo train.txt contains `cat $tgtdir/train.txt | perl -ane 'BEGIN{$w=$s=0;}{$w+=@F; $s++;}END{print "$w words, $s sentences\n";}'`

cat $long_dev_text  > $tgtdir/dev.txt
echo $long_dev_text contains `cat $long_dev_text | perl -ane 'BEGIN{$w=$s=0;}{$w+=@F; $w--; $s++;}END{print "$w words, $s sentences\n";}'`
echo $tgtdir/dev.txt contains `cat $tgtdir/dev.txt | perl -ane 'BEGIN{$w=$s=0;}{$w+=@F;  $s++;}END{print "$w words, $s sentences\n";}'`

ngram-count -lm $tgtdir/lm.gz -kndiscount1 -gt1min 0 -kndiscount2 -gt2min 1 -kndiscount3 -gt3min 2 -order 3 -text $tgtdir/train.txt -vocab $tgtdir/vocab -unk -sort -map-unk "$oov_symbol"
ngram -order 3 -lm $tgtdir/lm.gz -unk -map-unk "<UNK>" -ppl $long_dev_text

ngram-count -lm $tgtdir/lm5.gz -kndiscount1 -gt1min 0 -kndiscount2 -gt2min 1 -kndiscount3 -gt3min 2 -order 5 -text $tgtdir/train.txt -vocab $tgtdir/vocab -unk -sort -map-unk "$oov_symbol"
ngram -order 5 -lm $tgtdir/lm5.gz -unk -map-unk "<UNK>" -ppl $long_dev_text
