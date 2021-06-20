#!/usr/bin/env python3

import os
import argparse
parser = argparse.ArgumentParser(description="""get text from transcripts""")
parser.add_argument('text_file', type=str, help='File name of a file that contains the'
                    'text. Each line must be: <uttid> <word1> <word2> ...')
parser.add_argument('output_transcript', type=str, help='Output file that contains transcript')
def main():

    args = parser.parse_args()
    output_transcript_handle = open(args.output_transcript, 'w', encoding='utf8')
    text_file_handle = open(args.text_file, 'r', encoding='utf8')
    text_file_data = text_file_handle.read().strip().split("\n")
    for line in text_file_data:
        parts = line.strip().split()
        output_transcript_handle.write(" ".join(parts) + '\n')


if __name__ == '__main__':
    main()
