#!/bin/bash
language=Hindi

./utils/copy_data_dir.sh data/train_Hindi data/dev
./utils/copy_data_dir.sh data/train_Hindi data/train

grep -e 'ahd_00026' -e 'ahd_00027' -e 'ahd_00028' \
     -e 'bbs_00431' -e 'bbs_00432' -e 'bbs_00433' \
     -e 'cdg_00151' -e 'cdg_00152' -e 'cdg_00153' \
     -e 'dli_00371' -e 'dli_00372' -e 'dli_00373' \
     -e 'hyd_00178' -e 'hyd_00179' -e 'hyd_00180' \
     -e 'idr_00100' -e 'idr_00101' -e 'idr_00102' \
     -e 'kol_00216' -e 'kol_00217' -e 'kol_00218' \
     -e 'lnw_00116' -e 'lnw_00117' -e 'lnw_00118' \
     -e 'mum_00301' -e 'mum_00302' -e 'mum_00303' \
     -e 'pue_00001' -e 'pue_00010' -e 'pue_00011' \
     data/train_Hindi/text > data/dev/text

grep -v -e 'ahd_00026' -e 'ahd_00027' -e 'ahd_00028' \
     -e 'bbs_00431' -e 'bbs_00432' -e 'bbs_00433' \
     -e 'cdg_00151' -e 'cdg_00152' -e 'cdg_00153' \
     -e 'dli_00371' -e 'dli_00372' -e 'dli_00373' \
     -e 'hyd_00178' -e 'hyd_00179' -e 'hyd_00180' \
     -e 'idr_00100' -e 'idr_00101' -e 'idr_00102' \
     -e 'kol_00216' -e 'kol_00217' -e 'kol_00218' \
     -e 'lnw_00116' -e 'lnw_00117' -e 'lnw_00118' \
     -e 'mum_00301' -e 'mum_00302' -e 'mum_00303' \
     -e 'pue_00001' -e 'pue_00010' -e 'pue_00011' \
     data/train_Hindi/text > data/train/text

./utils/fix_data_dir.sh data/train
./utils/fix_data_dir.sh data/dev
