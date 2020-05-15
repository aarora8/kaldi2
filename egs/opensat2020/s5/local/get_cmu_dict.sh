#!/bin/bash
# Copyright (c) 2020, Johns Hopkins University (Jan "Yenda" Trmal<jtrmal@gmail.com>)
# License: Apache 2.0

# Begin configuration section.
lm_order=6
# End configuration section
. ./utils/parse_options.sh
set -e -o pipefail
set -o nounset                              # Treat unset variables as an error
. ./path.sh

OUTPUT=data/local
mkdir -p $OUTPUT

[ -f data/cmudict-0.7b ] || \
  curl http://svn.code.sf.net/p/cmusphinx/code/trunk/cmudict/cmudict-0.7b > $OUTPUT/cmudict-0.7b

uconv -f iso-8859-1 -t utf-8 data/cmudict-0.7b| grep -v ';;' | sed 's/([0-9])//g' | \
  perl -ne '($a, $b) = split " ", $_, 2; $b =~ s/[0-9]//g; $a = lc $a; print "$a $b";' > $OUTPUT/lexicon.txt

mkdir -p $OUTPUT/g2p
if false; then
phonetisaurus-align  --input=$OUTPUT/lexicon.txt --ofile=$OUTPUT/g2p/corpus
#I did run this to figure out the optimal LM weight
#bash -x local/train_lms_srilm.sh --words_file auto --train_text data/local/g2p/corpus data/ data/local/g2p/srilm
ngram-count -lm $OUTPUT/g2p/corpus.arpa -order 6 -text $OUTPUT/g2p/corpus \
  -sort -maxent -maxent-convert-to-arpa

ngram -order 6 -lm $OUTPUT/g2p/corpus.arpa  -ppl $OUTPUT/g2p/corpus | paste -s

phonetisaurus-arpa2wfst  --lm=$OUTPUT/g2p/corpus.arpa  --ofile=$OUTPUT/g2p/corpus.g2p
fi

mkdir -p $OUTPUT/dict_nosp
echo -e "SIL <sil>\n<UNK> <unk>" |  cat - local/hesitations.txt $OUTPUT/lexicon.txt | sort -u > $OUTPUT/dict_nosp/lexicon.txt
echo '<UNK>' > $OUTPUT/dict/oov.txt
#echo ''  > $OUTPUT/dict/extra_questions.txt
echo '<sil>' > $OUTPUT/dict_nosp/optional_silence.txt
cat $OUTPUT/lexicon.txt | cut -d ' ' -f 2- | sed 's/ /\n/g' | \
  sort -u | sed '/^ *$/d' > $OUTPUT/dict_nosp/nonsilence_phones.txt
echo -e "SIL <sil>\n<UNK> <unk>" |  cat - local/hesitations.txt | cut -d ' ' -f 2- | sed 's/ /\n/g' | \
  sort -u | sed '/^ *$/d' > $OUTPUT/dict_nosp/silence_phones.txt



