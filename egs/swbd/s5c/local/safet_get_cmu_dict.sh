#!/bin/bash
# Copyright (c) 2020, Johns Hopkins University (Jan "Yenda" Trmal<jtrmal@gmail.com>)
# License: Apache 2.0

# Begin configuration section.
# End configuration section
. ./utils/parse_options.sh
set -e -o pipefail
set -o nounset                              # Treat unset variables as an error
. ./path.sh

srcdir=data/local/train  # This is where we downloaded some stuff..
dir=data/local/dict_nosp
mkdir -p $dir
srcdict=$srcdir/swb_ms98_transcriptions/sw-ms98-dict.text
# assume swbd_p1_data_prep.sh was done already.
[ ! -f "$srcdict" ] && echo "$0: No such file $srcdict" && exit 1;
cp $srcdict $dir/lexicon0.txt || exit 1;
chmod +r $dir/lexicon0.txt  # fix a strange permission in the source.
patch <local/dict.patch $dir/lexicon0.txt || exit 1;

#(2a) Dictionary preparation:
# Pre-processing (remove comments)
grep -v '^#' $dir/lexicon0.txt | awk 'NF>0' | sort > $dir/lexicon1.txt || exit 1;
cat $dir/lexicon1.txt | awk '{ for(n=2;n<=NF;n++){ phones[$n] = 1; }} END{for (p in phones) print p;}' | \
  grep -v sil > $dir/nonsilence_phones.txt  || exit 1;

# removing silence phone (sil)
(echo spn; echo nsn; echo lau ) > $dir/silence_phones.txt

# commenting out this line
#echo sil > $dir/optional_silence.txt

# No "extra questions" in the input to this setup, as we don't
# have stress or tone.
echo -n >$dir/extra_questions.txt

cp local/MSU_single_letter.txt $dir/
# Add to the lexicon the silences, noises etc.
# Add single letter lexicon
# The original swbd lexicon does not have precise single letter lexicion
# e.g. it does not have entry of W

# removing !sil sil to be part of lexicon
# removing <unk> spn to be part of lexicon
( echo '[vocalized-noise] spn'; echo '[noise] nsn'; \
  echo '[laughter] lau'; ) \
  | cat - $dir/lexicon1.txt $dir/MSU_single_letter.txt  > $dir/lexicon2.txt || exit 1;

local/swbd1_map_words.pl -f 1 $dir/lexicon2.txt | sort -u \
  > $dir/lexicon3.txt || exit 1;

python local/format_acronyms_dict.py -i $dir/lexicon3.txt -o $dir/lexicon4.txt \
  -L $dir/MSU_single_letter.txt -M $dir/acronyms_raw.map
cat $dir/acronyms_raw.map | sort -u > $dir/acronyms.map

( echo 'i ay' )| cat - $dir/lexicon4.txt | tr '[A-Z]' '[a-z]' | sort -u > $dir/lexicon5.txt

#pushd $dir >&/dev/null
#ln -sf lexicon5.txt lexicon.txt # This is the final lexicon.
#popd >&/dev/null
#rm $dir/lexiconp.txt 2>/dev/null
echo Prepared input dictionary and phone-sets for Switchboard phase 1.


OUTPUT=data/local_safet
mkdir -p $OUTPUT

[ -f data/cmudict-0.7b ] || \
  curl http://svn.code.sf.net/p/cmusphinx/code/trunk/cmudict/cmudict-0.7b > $OUTPUT/cmudict-0.7b

# add cmu dict words in lowercase in the lexicon
uconv -f iso-8859-1 -t utf-8 $OUTPUT/cmudict-0.7b| grep -v ';;' | sed 's/([0-9])//g' | \
  perl -ne '($a, $b) = split " ", $_, 2; $b =~ s/[0-9]//g; $a = lc $a; $b = lc $b; print "$a $b";' > $OUTPUT/lexicon.txt

# add SIL, <UNK>, %uh, {breath}, {lipsmack}, {laugh}, {cough}, <noise> words in the lexicon 
# <UNK> word is mapped to <unk> phone
# {breath}, {lipsmack}, {laugh}, {cough}, <noise> are mapped to <noise>
mkdir -p $OUTPUT/dict_nosp
echo -e "SIL <sil>\n<UNK> <unk>" |  cat - local/safet_hesitations.txt $OUTPUT/lexicon.txt | sort -u > $OUTPUT/dict_nosp/lexicon1.txt


# add some specific words, those are only with 100 missing occurences or more
# add mm hmm mm-hmm  words in the lexicon
( echo "mm m"; \
  echo "hmm hh m"; \
  echo "mm-hmm m hh m" ) | cat - $OUTPUT/dict_nosp/lexicon1.txt \
     | sort -u > $OUTPUT/dict_nosp/lexicon2.txt

# Add prons for laughter, noise, oov as phones in the silence phones
for w in laughter noise oov; do echo $w; done > $OUTPUT/dict_nosp/silence_phones.txt

# add [laughter], [noise], [oov] words in the lexicon
for w in `grep -v sil $OUTPUT/dict_nosp/silence_phones.txt`; do
  echo "[$w] $w"
done | cat - $OUTPUT/dict_nosp/lexicon2.txt > $OUTPUT/dict_nosp/lexicon.txt


# Add <sil>, <unk>, <noise>, <hes> as phones in the silence phones
echo -e "SIL <sil>\n<UNK> <unk>" |  cat - local/safet_hesitations.txt | cut -d ' ' -f 2- | sed 's/ /\n/g' | \
  sort -u | sed '/^ *$/d' >> $OUTPUT/dict_nosp/silence_phones.txt

echo '<UNK>' > $OUTPUT/dict_nosp/oov.txt

echo '<sil>' > $OUTPUT/dict_nosp/optional_silence.txt

cat $OUTPUT/lexicon.txt | cut -d ' ' -f 2- | sed 's/ /\n/g' | \
  sort -u | sed '/^ *$/d' > $OUTPUT/dict_nosp/nonsilence_phones.txt


mkdir -p data/local/dict_nosp_final
cat $OUTPUT/dict_nosp/lexicon.txt $dir/lexicon5.txt | sort | uniq > data/local/dict_nosp_final/lexicon.txt
cat $OUTPUT/dict_nosp/silence_phones.txt $dir/silence_phones.txt | sort | uniq > data/local/dict_nosp_final/silence_phones.txt
cat $OUTPUT/dict_nosp/nonsilence_phones.txt $dir/nonsilence_phones.txt | sort | uniq > data/local/dict_nosp_final/nonsilence_phones.txt
cat $OUTPUT/dict_nosp/oov.txt > data/local/dict_nosp_final/oov.txt
cat $OUTPUT/dict_nosp/optional_silence.txt > data/local/dict_nosp_final/optional_silence.txt

echo Prepared input dictionary and phone-sets for Switchboard phase 1.
