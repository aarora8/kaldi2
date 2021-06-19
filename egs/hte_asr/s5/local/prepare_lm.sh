#!/usr/bin/env bash
export LC_ALL=C
echo "$0 $@"
[ -f path.sh ]  && . ./path.sh

echo "-------------------------------------"
echo "Building an SRILM language model     "
echo "-------------------------------------"


tgtdir=data/local/lm
train_text=data/local/lm_train_text
dev_text=data/local/lm_dev_text
words_file=data/lang_nosp/words.txt
oov_symbol="<UNK>"
##End of configuration

cat data/train/text | cut -d " " -f 2-  > $train_text
cat data/dev_clean/text | cut -d " " -f 2-  > $dev_text

mkdir -p $tgtdir
for f in $words_file $train_text $dev_text; do
  [ ! -s $f ] && echo "No such file $f" && exit 1;
done

echo "Using train text: $train_text"
echo "Using dev text  : $dev_text"

# Extract the word list from the training dictionary; exclude special symbols
sort $words_file | awk '{print $1}' | grep -v '\#0' | grep -v '<eps>' | grep -v -F "$oov_symbol" > $tgtdir/vocab
echo vocab contains `cat $tgtdir/vocab | perl -ne 'BEGIN{$l=$w=0;}{split; $w+=$#_; $w++; $l++;}END{print "$l lines, $w words\n";}'`

cat $train_text > $tgtdir/train.txt
echo $train_text contains `cat $train_text | perl -ane 'BEGIN{$w=$s=0;}{$w+=@F; $w--; $s++;}END{print "$w words, $s sentences\n";}'`
echo train.txt contains `cat $tgtdir/train.txt | perl -ane 'BEGIN{$w=$s=0;}{$w+=@F; $s++;}END{print "$w words, $s sentences\n";}'`

cat $dev_text  > $tgtdir/dev.txt
echo $dev_text contains `cat $dev_text | perl -ane 'BEGIN{$w=$s=0;}{$w+=@F; $w--; $s++;}END{print "$w words, $s sentences\n";}'`
echo $tgtdir/dev.txt contains `cat $tgtdir/dev.txt | perl -ane 'BEGIN{$w=$s=0;}{$w+=@F;  $s++;}END{print "$w words, $s sentences\n";}'`

ngram-count -lm $tgtdir/lm.gz -kndiscount1 -gt1min 0 -kndiscount2 -gt2min 1 -kndiscount3 -gt3min 2 -order 3 -text $tgtdir/train.txt -vocab $tgtdir/vocab -unk -sort -map-unk "$oov_symbol"

ngram -order 3 -lm $tgtdir/lm.gz -unk -map-unk "<UNK>" -ppl $dev_text
#file exp/data/lm_dev_text: 2100 sentences, 21134 words, 0 OOVs
#0 zeroprobs, logprob= -33550.65 ppl= 27.79922 ppl1= 38.68301
