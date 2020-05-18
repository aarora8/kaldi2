#!/usr/bin/env bash

set -e -o pipefail
stage=0
nj=96
min_seg_len=3
train_set=train   # you might set this to e.g. train.
gmm=tri5b          # This specifies a GMM-dir from the features of the type you're training the system on;
                          # it should contain alignments for 'train_set'.
online_cmvn_extractor=false
num_threads_ubm=8
nnet3_affix=_org     # affix for exp/nnet3 directory to put iVector stuff in, so it
                         # becomes exp/nnet3_cleaned or whatever.
. ./cmd.sh
. ./path.sh
. utils/parse_options.sh

gmm_dir=exp/${gmm}
ali_dir=exp/${gmm}_ali_${train_set}_sp_comb

for f in data/${train_set}/feats.scp ${gmm_dir}/final.mdl; do
  if [ ! -f $f ]; then
    echo "$0: expected file $f to exist"
    exit 1
  fi
done

# lowres features, alignments
if [ -f data/${train_set}_sp/feats.scp ] && [ $stage -le 2 ]; then
  echo "$0: data/${train_set}_sp/feats.scp already exists.  Refusing to overwrite the features "
  echo " to avoid wasting time.  Please remove the file and continue if you really mean this."
  exit 1;
fi

if [ $stage -le 1 ]; then
  echo "$0: preparing directory for low-resolution speed-perturbed data (for alignment)"
  utils/data/perturb_data_dir_speed_3way.sh \
    data/${train_set} data/${train_set}_sp
  for datadir in ${train_set}_sp safe_t_dev1; do
    utils/copy_data_dir.sh data/$datadir data/${datadir}_hires
  done
fi

if [ $stage -le 2 ]; then
  echo "$0: making MFCC features for low-resolution speed-perturbed data"
  steps/make_mfcc.sh --nj $nj \
    --cmd "$train_cmd" data/${train_set}_sp
  steps/compute_cmvn_stats.sh data/${train_set}_sp
  echo "$0: fixing input data-dir to remove nonexistent features, in case some "
  echo ".. speed-perturbed segments were too short."
  utils/fix_data_dir.sh data/${train_set}_sp
fi


if [ $stage -le 3 ]; then
  echo "$0: creating high-resolution MFCC features"
  mfccdir=data/${train_set}_sp_hires/data
  if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $mfccdir/storage ]; then
    utils/create_split_dir.pl /export/b0{5,6,7,8}/$USER/kaldi-data/mfcc/tedlium-$(date +'%m_%d_%H_%M')/s5/$mfccdir/storage $mfccdir/storage
  fi
  utils/data/perturb_data_dir_volume.sh data/${train_set}_sp_hires
  for datadir in ${train_set}_sp safe_t_dev1; do
    steps/make_mfcc.sh --nj $nj --mfcc-config conf/mfcc_hires.conf \
      --cmd "$train_cmd" data/${datadir}_hires
    steps/compute_cmvn_stats.sh data/${datadir}_hires
    utils/fix_data_dir.sh data/${datadir}_hires
  done
fi

if [ $stage -le 4 ]; then
  echo "$0: combining short segments of low-resolution speed-perturbed  MFCC data"
  src=data/${train_set}_sp
  dest=data/${train_set}_sp_comb
  utils/data/combine_short_segments.sh $src $min_seg_len $dest
  # re-use the CMVN stats from the source directory, since it seems to be slow to
  # re-compute them after concatenating short segments.
  cp $src/cmvn.scp $dest/
  utils/fix_data_dir.sh $dest
fi

if [ $stage -le 5 ]; then
  echo "$0: combining short segments of speed-perturbed high-resolution MFCC training data"
  # we have to combine short segments or we won't be able to train chain models
  # on those segments.
  utils/data/combine_short_segments.sh \
     data/${train_set}_sp_hires $min_seg_len data/${train_set}_sp_hires_comb

  # just copy over the CMVN to avoid having to recompute it.
  cp data/${train_set}_sp_hires/cmvn.scp data/${train_set}_sp_hires_comb/
  utils/fix_data_dir.sh data/${train_set}_sp_hires_comb/
fi

if [ $stage -le 6 ]; then
  if [ -f $ali_dir/ali.1.gz ]; then
    echo "$0: alignments in $ali_dir appear to already exist.  Please either remove them "
    echo " ... or use a later --stage option."
    exit 1
  fi
  echo "$0: aligning with the perturbed, short-segment-combined low-resolution data"
  steps/align_fmllr.sh --nj $nj --cmd "$train_cmd" \
         data/${train_set}_sp_comb data/lang_test $gmm_dir $ali_dir
fi

if [ $stage -le 7 ]; then
  echo "$0: computing a subset of data to train the diagonal UBM."

  mkdir -p exp/nnet3${nnet3_affix}/diag_ubm
  temp_data_root=exp/nnet3${nnet3_affix}/diag_ubm

  # train a diagonal UBM using a subset of about a quarter of the data
  num_utts_total=$(wc -l <data/${train_set}_sp_hires/utt2spk)
  num_utts=$[$num_utts_total/4]
  utils/data/subset_data_dir.sh data/${train_set}_sp_hires \
    $num_utts ${temp_data_root}/${train_set}_sp_hires_subset

  echo "$0: computing a PCA transform from the hires data."
  steps/online/nnet2/get_pca_transform.sh --cmd "$train_cmd" \
    --splice-opts "--left-context=3 --right-context=3" \
    --max-utts 10000 --subsample 2 \
    ${temp_data_root}/${train_set}_sp_hires_subset \
    exp/nnet3${nnet3_affix}/pca_transform

  echo "$0: training the diagonal UBM."
  # Use 512 Gaussians in the UBM.
  steps/online/nnet2/train_diag_ubm.sh --cmd "$train_cmd" --nj 30 \
    --num-frames 700000 \
    --num-threads $num_threads_ubm \
    ${temp_data_root}/${train_set}_sp_hires_subset 512 \
    exp/nnet3${nnet3_affix}/pca_transform exp/nnet3${nnet3_affix}/diag_ubm
fi

if [ $stage -le 8 ]; then
  # Train the iVector extractor. µUse all of the speed-perturbed data since iVector extractors
  # can be sensitive to the amount of data. The script defaults to an iVector dimension of 100.
  echo "$0: training the iVector extractor"
  steps/online/nnet2/train_ivector_extractor.sh --cmd "$train_cmd" --nj 20 \
    --num-threads 4 --num-processes 2 \
    --online-cmvn-iextractor $online_cmvn_extractor \
    data/${train_set}_sp_hires exp/nnet3${nnet3_affix}/diag_ubm \
    exp/nnet3${nnet3_affix}/extractor || exit 1;
fi


if [ $stage -le 9 ]; then
  # note, we don't encode the 'max2' in the name of the ivectordir even though
  # that's the data we extract the ivectors from, as it's still going to be
  # valid for the non-'max2' data, the utterance list is the same.
  ivectordir=exp/nnet3${nnet3_affix}/ivectors_${train_set}_sp_hires_comb
  if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $ivectordir/storage ]; then
    utils/create_split_dir.pl /export/b0{5,6,7,8}/$USER/kaldi-data/ivectors/sprakbanken-$(date +'%m_%d_%H_%M')/s5/$ivectordir/storage $ivectordir/storage
  fi
  # We extract iVectors on the speed-perturbed training data after combining
  # short segments, which will be what we train the system on.  With
  # --utts-per-spk-max 2, the script pairs the utterances into twos, and treats
  # each of these pairs as one speaker; this gives more diversity in iVectors..
  # Note that these are extracted 'online'.

  # having a larger number of speakers is helpful for generalization, and to
  # handle per-utterance decoding well (iVector starts at zero).
  temp_data_root=${ivectordir}
  utils/data/modify_speaker_info.sh --utts-per-spk-max 2 \
    data/${train_set}_sp_hires_comb ${temp_data_root}/${train_set}_sp_hires_comb_max2

  steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj $nj \
    ${temp_data_root}/${train_set}_sp_hires_comb_max2 \
    exp/nnet3${nnet3_affix}/extractor $ivectordir

  # Also extract iVectors for the test data, but in this case we don't need the speed
  # perturbation (sp) or small-segment concatenation (comb).
  for data in safe_t_dev1; do
    steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj 20 \
      data/${data}_hires exp/nnet3${nnet3_affix}/extractor \
      exp/nnet3${nnet3_affix}/ivectors_${data}_hires
  done
fi

exit 0;
