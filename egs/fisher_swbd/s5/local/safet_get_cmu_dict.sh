#!/usr/bin/env bash
#

# To be run from one directory above this script.

## The input is some directory containing the switchboard-1 release 2
## corpus (LDC97S62).  Note: we don't make many assumptions about how
## you unpacked this.  We are just doing a "find" command to locate
## the .sph files.

# for example /mnt/matylda2/data/SWITCHBOARD_1R2

. ./path.sh

# The parts of the output of this that will be needed are
# [in data/local/dict/ ]
# lexicon.txt
# extra_questions.txt
# nonsilence_phones.txt
# optional_silence.txt
# silence_phones.txt


#check existing directories
[ $# != 0 ] && echo "Usage: local/fisher_prepare_dict.sh" && exit 1;

dir=data/local/dict_nosp
mkdir -p $dir
echo "Getting CMU dictionary"
svn co  https://svn.code.sf.net/p/cmusphinx/code/trunk/cmudict  $dir/cmudict

# silence phones, one per line.
for w in sil laughter noise oov; do echo $w; done > $dir/silence_phones.txt
echo sil > $dir/optional_silence.txt

# For this setup we're discarding stress.
cat $dir/cmudict/cmudict.0.7a.symbols | sed s/[0-9]//g | \
 tr '[A-Z]' '[a-z]' | perl -ane 's:\r::; print;' | sort | uniq > $dir/nonsilence_phones.txt

# An extra question will be added by including the silence phones in one class.
cat $dir/silence_phones.txt| awk '{printf("%s ", $1);} END{printf "\n";}' > $dir/extra_questions.txt || exit 1;

grep -v ';;;' $dir/cmudict/cmudict.0.7a |  tr '[A-Z]' '[a-z]' | \
 perl -ane 'if(!m:^;;;:){ s:(\S+)\(\d+\) :$1 :; s:  : :; print; }' | \
   sed s/[0-9]//g | sort | uniq > $dir/lexicon1_raw_nosil.txt || exit 1;

# Add prons for laughter, noise, oov
for w in `grep -v sil $dir/silence_phones.txt`; do
  echo "[$w] $w"
done | cat - $dir/lexicon1_raw_nosil.txt  > $dir/lexicon2_raw.txt || exit 1;


# This is just for diagnostics:
cat data/train_fisher/text  | \
  awk '{for (n=2;n<=NF;n++){ count[$n]++; } } END { for(n in count) { print count[n], n; }}' | \
  sort -nr > $dir/word_counts

# between lexicon2_raw and lexicon3_expand we limit it to the words seen in
# the Fisher data, and also expand the vocab for acronyms like c._n._n. and other
# underscore-containing things.
cat $dir/lexicon2_raw.txt | \
  perl -e 'while(<STDIN>) { @A=split; $w = shift @A; $pron{$w} = join(" ", @A); }
     ($w) = @ARGV;  open(W, "<$w") || die "Error opening word-counts from $w";
     while(<W>) { # reading in words we saw in training data..
       ($c, $w) = split;
       if (defined $pron{$w}) { 
         print "$w $pron{$w}\n";
       } else {
         @A = split("_", $w);
         if (@A > 1) {
           $this_pron = "";
           $pron_ok = 1;
           foreach $a (@A) { 
             if (defined($pron{$a})) { $this_pron = $this_pron . "$pron{$a} "; }
             else { $pron_ok = 0; print STDERR "Not handling word $w, count is $c\n"; last; } 
           }
           if ($pron_ok) { $this_pron =~ s/\s+$//; $new_pron{$w} = $this_pron;  } }}}
    foreach $w (keys %new_pron) { print "$w $new_pron{$w}\n"; } ' \
   $dir/word_counts > $dir/lexicon3_expand_v1.txt || exit 1;

cat $dir/word_counts | awk '{print $2}' > $dir/fisher_word_list
filter_scp.pl $dir/fisher_word_list $dir/lexicon2_raw.txt > $dir/lexicon3_expand_v2.txt

cat $dir/lexicon3_expand_v1.txt $dir/lexicon3_expand_v2.txt | sort -u > $dir/lexicon3_expand.txt

cat $dir/lexicon3_expand.txt  \
   <( echo "mm m"
      echo "<unk> oov" ) > $dir/lexicon4_extra.txt

cp $dir/lexicon4_extra.txt $dir/lexicon_fisher.txt

awk '{print $1}' $dir/lexicon_fisher.txt | \
  perl -e '($word_counts)=@ARGV;
   open(W, "<$word_counts")||die "opening word-counts $word_counts";
   while(<STDIN>) { chop; $seen{$_}=1; }
   while(<W>) {
     ($c,$w) = split;
     if (!defined $seen{$w}) { print; }
   } ' $dir/word_counts > $dir/oov_counts.txt

echo "*Highest-count OOVs are:"
head -n 20 $dir/oov_counts.txt



# Preparing SWBD acronymns from its dictionary
srcdir=data/local/train_swbd # This is where we downloaded some stuff..
dir=data/local/dict_nosp
mkdir -p $dir
srcdict=$srcdir/swb_ms98_transcriptions/sw-ms98-dict.text

# assume swbd_p1_data_prep.sh was done already.
[ ! -f "$srcdict" ] && echo "No such file $srcdict" && exit 1;

rm $dir/lexicon0.txt 2>/dev/null
cp $srcdict $dir/lexicon0.txt || exit 1;
chmod +w $srcdict $dir/lexicon0.txt

# Use absolute path in case patch reports the "Invalid file name" error (a bug with patch)
patch <local/dict.patch `pwd`/$dir/lexicon0.txt || exit 1;

#(2a) Dictionary preparation:
# Pre-processing (remove comments)
grep -v '^#' $dir/lexicon0.txt | awk 'NF>0' | sort > $dir/lexicon1_swbd.txt || exit 1;

cat $dir/lexicon1_swbd.txt | awk '{ for(n=2;n<=NF;n++){ phones[$n] = 1; }} END{for (p in phones) print p;}' | \
  grep -v SIL > $dir/nonsilence_phones_msu.txt  || exit 1;


local/swbd1_map_words.pl -f 1 $dir/lexicon1_swbd.txt | sort | uniq \
   > $dir/lexicon2_swbd.txt || exit 1;

cp conf/MSU_single_letter.txt $dir/MSU_single_letter.txt
python local/format_acronyms_dict.py -i $dir/lexicon2_swbd.txt \
  -o1 $dir/acronyms_lex_swbd.txt -o2 $dir/acronyms_lex_swbd_ori.txt \
  -L $dir/MSU_single_letter.txt -M $dir/acronyms_raw.map
cat $dir/acronyms_raw.map | sort -u > $dir/acronyms_swbd.map

cat $dir/acronyms_lex_swbd.txt |\
  sed 's/ ax/ ah/g' |\
  sed 's/ en/ ah n/g' |\
  sed 's/ el/ ah l/g' \
  > $dir/acronyms_lex_swbd_cmuphones.txt


cat $dir/acronyms_lex_swbd_cmuphones.txt $dir/lexicon_fisher.txt | sort -u > $dir/lexicon.txt

echo "Prepared input dictionary and phone-sets for Switchboard phase 1."
utils/validate_dict_dir.pl $dir
OUTPUT=data/local
mkdir -p $OUTPUT

[ -f data/cmudict-0.7b ] || \
  curl http://svn.code.sf.net/p/cmusphinx/code/trunk/cmudict/cmudict-0.7b > $OUTPUT/cmudict-0.7b

# add cmu dict words in lowercase in the lexicon
uconv -f iso-8859-1 -t utf-8 $OUTPUT/cmudict-0.7b| grep -v ';;' | sed 's/([0-9])//g' | \
  perl -ne '($a, $b) = split " ", $_, 2; $b =~ s/[0-9]//g; $a = lc $a; print "$a $b";' > $OUTPUT/safet_lexicon.txt

# add SIL, <UNK>, %uh, {breath}, {lipsmack}, {laugh}, {cough}, <noise> words in the lexicon 
# <UNK> word is mapped to <unk> phone
# {breath}, {lipsmack}, {laugh}, {cough}, <noise> are mapped to <noise>
mkdir -p $OUTPUT/dict_nosp
echo -e "SIL <sil>\n<UNK> <unk>" |  cat - local/safet_hesitations.txt $OUTPUT/safet_lexicon.txt | sort -u > $OUTPUT/dict_nosp/safet_lexicon1.txt


# add some specific words, those are only with 100 missing occurences or more
# add mm hmm mm-hmm  words in the lexicon
( echo "mm M"; \
  echo "hmm HH M"; \
  echo "mm-hmm M HH M" ) | cat - $OUTPUT/dict_nosp/safet_lexicon1.txt \
     | sort -u > $OUTPUT/dict_nosp/safet_lexicon2.txt

# Add prons for laughter, noise, oov as phones in the silence phones
for w in laughter noise oov; do echo $w; done > $OUTPUT/dict_nosp/safet_silence_phones.txt

# add [laughter], [noise], [oov] words in the lexicon
for w in `grep -v sil $OUTPUT/dict_nosp/safet_silence_phones.txt`; do
  echo "[$w] $w"
done | cat - $OUTPUT/dict_nosp/safet_lexicon2.txt > $OUTPUT/dict_nosp/safet_lexicon.txt


# Add <sil>, <unk>, <noise>, <hes> as phones in the silence phones
echo -e "SIL <sil>\n<UNK> <unk>" |  cat - local/safet_hesitations.txt | cut -d ' ' -f 2- | sed 's/ /\n/g' | \
  sort -u | sed '/^ *$/d' >> $OUTPUT/dict_nosp/safet_silence_phones.txt

echo '<UNK>' > $OUTPUT/dict_nosp/safet_oov.txt

echo '<sil>' > $OUTPUT/dict_nosp/safet_optional_silence.txt


cat $OUTPUT/safet_lexicon.txt | cut -d ' ' -f 2- | sed 's/ /\n/g' | \
  sort -u | sed '/^ *$/d' > $OUTPUT/dict_nosp/safet_nonsilence_phones.txt

