#!/usr/bin/env python3

import os
import argparse
parser = argparse.ArgumentParser(description="""get text from transcripts""")
parser.add_argument('text_file', type=str, help='File name of a file that contains the'
                    'text. Each line must be: <uttid> <word1> <word2> ...')
parser.add_argument('vocabulary', type=str, help='words in the lexicon')
parser.add_argument('output_oov_word', type=str, help='Output file that contains transcript')
def main():

    args = parser.parse_args()
    output_oov_word_handle = open(args.output_oov_word, 'w', encoding='utf8')
    text_file_handle = open(args.text_file, 'r', encoding='utf8')
    vocabulary_handle = open(args.vocabulary, 'r', encoding='utf8')
    oov_words = dict()
    vocab = dict()
    vocabulary_data = vocabulary_handle.read().strip().split("\n")
    for word in vocabulary_data:
        vocab[word] = word
    text_file_data = text_file_handle.read().strip().split("\n")
    for line in text_file_data:
        parts = line.strip().split()
        words = parts[1:]
        for word in words:
            if word not in vocab:
                oov_words[word] = word

    for word in oov_words:
        output_oov_word_handle.write(word + " " + '\n')


if __name__ == '__main__':
    main()
