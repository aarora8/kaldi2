#!/usr/bin/env bash

dst_dir=data/local/dict_nosp
silence_phones=$dst_dir/silence_phones.txt
optional_silence=$dst_dir/optional_silence.txt
nonsil_phones=$dst_dir/nonsilence_phones.txt
lexicon_raw_nosil=$dst_dir/lexicon/lexicon_raw_nosil.txt
mkdir -p $dst_dir/lexicon

#Remove initial lines such as (grep -v ';;') such as
#    ;;; # CMUdict  --  Major Version: 0.07
#    ;;;
#    ;;; # $HeadURL$
#Remove (1)  (sed 's/([0-9])//g') such as
#    ABKHAZIAN(1)  AE0 B K AE1 Z IY0 AH0 N     
#    ABKHAZIAN   AE0 B K AE1 Z IY0 AH0 N
#Remove the first 70 lines which are for special symbols such as
#    "CLOSE-QUOTE  K L OW1 Z K W OW1 T
#    "DOUBLE-QUOTE  D AH1 B AH0 L K W OW1 T
curl http://svn.code.sf.net/p/cmusphinx/code/trunk/cmudict/cmudict-0.7b > $dst_dir/lexicon/cmudict-0.7b
uconv -f iso-8859-1 -t utf-8 $dst_dir/lexicon/cmudict-0.7b| grep -v ';;' | sed 's/([0-9])//g' | sed 1,70d  | \
  perl -ne '($a, $b) = split " ", $_, 2; $b =~ s/[0-9]//g; print "$a $b";' > $lexicon_raw_nosil

echo "Preparing phone lists"
(echo SIL; echo SPN;) > $silence_phones
echo SIL > $optional_silence

# nonsilence phones; on each line is a list of phones that correspond
# really to the same base phone.
awk '{for (i=2; i<=NF; ++i) { print $i; gsub(/[0-9]/, "", $i); print $i}}' $lexicon_raw_nosil |\
    sort -u |\
    perl -e 'while(<>){
      chop; m:^([^\d]+)(\d*)$: || die "Bad phone $_";
      $phones_of{$1} .= "$_ "; }
      foreach $list (values %phones_of) {print $list . "\n"; } ' | sort \
      > $nonsil_phones || exit 1;

(echo '!SIL SIL'; echo '<SPOKEN_NOISE> SPN'; echo '<UNK> SPN'; ) |\
cat - $lexicon_raw_nosil | sort | uniq >$dst_dir/lexicon.txt
echo "Lexicon text file saved as: $dst_dir/lexicon.txt"

exit 0
