#!/bin/bash
#ROOT=$1 #/export/common/data/corpora/ASR/IITM_Indian_ASR_Challenge_2021/Indian_Language_Database
language=

#mkdir data
#cd data
#cp -r ${ROOT}/${language}/transcription/{train,dev}_${language} .
#cd ..
#for d in train dev; do
#  mv data/${d}_${language}/wav.scp data/${d}_${language}/wav.scp.bk && \
#    awk -v var=${ROOT}/${language} '{print $1,var"/"$2}' data/${d}_${language}/wav.scp.bk \
#    > data/${d}_${language}/wav.scp
#  sed 's/\t */ /' data/${d}_${language}/text > data/${d}_${language}/text.tmp
#  awk '(NF > 1)' data/${d}_${language}/text.tmp > data/${d}_${language}/text
#  ./utils/fix_data_dir.sh data/${d}_${language}
#done

./local/identify_seen_utts.pl data/train${language}/text data/dev${language}/text |\
  ./local/identify_seen_convs.pl |\
  awk '($2<80){print $1}' > data/dev${language}/convs_nodup
./local/identify_seen_utts.pl data/train${language}/text data/dev${language}/text |\
  ./local/identify_seen_convs.pl |\
  awk '($2>=80){print $1}' > data/dev${language}/convs_dup

./utils/copy_data_dir.sh data/dev${language} data/dev${language}_nodup
./utils/copy_data_dir.sh data/dev${language} data/dev${language}_dup 
awk '(NR==FNR){a[$1]=1;next} ($2 in a){print $0}' data/dev${language}/convs_nodup data/dev${language}/segments > data/dev${language}_nodup/segments
awk '(NR==FNR){a[$1]=1;next} ($2 in a){print $0}' data/dev${language}/convs_dup data/dev${language}/segments > data/dev${language}_dup/segments

./utils/fix_data_dir.sh data/dev${language}_nodup
./utils/fix_data_dir.sh data/dev${language}_dup
