#!/bin/bash
# Copyright (c) 2020, Johns Hopkins University (Jan "Yenda" Trmal<jtrmal@gmail.com>)
# License: Apache 2.0

# Begin configuration section.
# End configuration section
set -e -o pipefail
set -o nounset                              # Treat unset variables as an error
. ./utils/parse_options.sh

if ! command -v flac ; then
  echo >&2 "Flac must be installed! "
  exit 1
fi

if ! command -v phonetisaurus-align ; then
  echo >&2 "Phonetisaurus must be installed -- go to toos/extras/install_phonetisaurus.sh "
  exit 1
fi

if ! command -v ngram-count  ; then
  echo >&2 "Srilm must be installed"
  exit 1
fi



exit 0
