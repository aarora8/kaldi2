#!/usr/bin/env python

import os
import argparse
parser = argparse.ArgumentParser(description="""creates left bi-phone lexicon from monophone lexicon""")
parser.add_argument('lexicon', type=str, help='File name of a file that contains the'
                    'lexicon with monophones. Each line must be: <word> <phone1> <phone2> ...')
parser.add_argument('output_nonsilence_phones', type=str, help='Output file that contains'
                    'non-silence phones')
parser.add_argument('output_lexicon', type=str, help='Output file that contains'
                    'non-silence phones')
def main():

    args = parser.parse_args()
    phonesdict = dict()
    output_nonsilphones_handle = open(args.output_nonsilence_phones, 'w', encoding='utf8')
    output_lexicon_handle = open(args.output_lexicon, 'w', encoding='utf8')
    lexicon_handle = open(args.lexicon, 'r', encoding='utf8')
    lexicon_data = lexicon_handle.read().strip().split("\n")
    for line in lexicon_data:
        parts = line.strip().split()
        word = parts[0]
        if '<Noise/>' in word:
            continue
        if '(2)' in word or '(3)' in word or '(4)' in word or '(5)' in word:
            word = word[:-3]
            output_lexicon_handle.write(word + ' ' + ' '.join(parts[1:]) + '\n')
        else:
            output_lexicon_handle.write(word + ' ' + ' '.join(parts[1:]) + '\n')
        for phone in parts[1:]:
            phonesdict[phone] = phone
    for phone in sorted(phonesdict):
        if 'SIL' in phone:
            continue
        output_nonsilphones_handle.write(phone + '\n')


if __name__ == '__main__':
    main()
