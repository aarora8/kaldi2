#!/usr/bin/env bash

set -e -o pipefail
stage=0
nj=96
min_seg_len=3
train_set=train_cleaned_aug   # you might set this to e.g. train.
gmm=tri5b          # This specifies a GMM-dir from the features of the type you're training the system on;
                          # it should contain alignments for 'train_set'.
online_cmvn_extractor=false
num_threads_ubm=8
nnet3_affix=     # affix for exp/nnet3 directory to put iVector stuff in

. ./cmd.sh
. ./path.sh
. utils/parse_options.sh

for f in data/${train_set}/feats.scp; do
  if [ ! -f $f ]; then
    echo "$0: expected file $f to exist"
    exit 1
  fi
done

if [ $stage -le 1 ]; then
  echo "$0: computing a subset of data to train the diagonal UBM."

  mkdir -p exp/nnet3${nnet3_affix}/diag_ubm
  temp_data_root=exp/nnet3${nnet3_affix}/diag_ubm

  # train a diagonal UBM using a subset of about a quarter of the data
  num_utts_total=$(wc -l <data/${train_set}_hires/utt2spk)
  num_utts=$[$num_utts_total/4]
  utils/data/subset_data_dir.sh data/${train_set}_hires \
    $num_utts ${temp_data_root}/${train_set}_hires_subset

  echo "$0: computing a PCA transform from the hires data."
  steps/online/nnet2/get_pca_transform.sh --cmd "$train_cmd" \
    --splice-opts "--left-context=3 --right-context=3" \
    --max-utts 10000 --subsample 2 \
    ${temp_data_root}/${train_set}_hires_subset \
    exp/nnet3${nnet3_affix}/pca_transform

  echo "$0: training the diagonal UBM."
  # Use 512 Gaussians in the UBM.
  steps/online/nnet2/train_diag_ubm.sh --cmd "$train_cmd" --nj 30 \
    --num-frames 700000 \
    --num-threads $num_threads_ubm \
    ${temp_data_root}/${train_set}_hires_subset 512 \
    exp/nnet3${nnet3_affix}/pca_transform exp/nnet3${nnet3_affix}/diag_ubm
fi

if [ $stage -le 2 ]; then
  # Train the iVector extractor. µUse all of the speed-perturbed data since iVector extractors
  # can be sensitive to the amount of data. The script defaults to an iVector dimension of 100.
  echo "$0: training the iVector extractor"
  steps/online/nnet2/train_ivector_extractor.sh --cmd "$train_cmd" --nj 15 \
    --num-threads 4 --num-processes 2 \
    --online-cmvn-iextractor $online_cmvn_extractor \
    data/${train_set}_hires exp/nnet3${nnet3_affix}/diag_ubm \
    exp/nnet3${nnet3_affix}/extractor || exit 1;
fi

if [ $stage -le 3 ]; then
  # note, we don't encode the 'max2' in the name of the ivectordir even though
  # that's the data we extract the ivectors from, as it's still going to be
  # valid for the non-'max2' data, the utterance list is the same.
  ivectordir=exp/nnet3${nnet3_affix}/ivectors_${train_set}_hires
  if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $ivectordir/storage ]; then
    utils/create_split_dir.pl /export/b0{5,6,7,8}/$USER/kaldi-data/ivectors/tedlium-$(date +'%m_%d_%H_%M')/s5/$ivectordir/storage $ivectordir/storage
  fi
  # We now extract iVectors on the speed-perturbed training data .  With
  # --utts-per-spk-max 2, the script pairs the utterances into twos, and treats
  # each of these pairs as one speaker; this gives more diversity in iVectors..
  # Note that these are extracted 'online' (they vary within the utterance).

  # Having a larger number of speakers is helpful for generalization, and to
  # handle per-utterance decoding well (the iVector starts at zero at the beginning
  # of each pseudo-speaker).
  temp_data_root=${ivectordir}
  utils/data/modify_speaker_info.sh --utts-per-spk-max 2 \
    data/${train_set}_hires ${temp_data_root}/${train_set}_hires_max2

  steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj 20 \
    ${temp_data_root}/${train_set}_hires_max2 \
    exp/nnet3${nnet3_affix}/extractor $ivectordir

  for data in safe_t_dev1; do
    steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj 20 \
      data/${data}_hires exp/nnet3${nnet3_affix}/extractor \
      exp/nnet3${nnet3_affix}/ivectors_${data}_hires
  done
fi

exit 0;
