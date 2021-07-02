#!/usr/bin/env python3

import os
import argparse
parser = argparse.ArgumentParser(description="""get text from transcripts""")
parser.add_argument('input_text', type=str, help='File name of a file that contains the')
parser.add_argument('output_transcript', type=str, help='Output file that contains transcript')
def main():

    args = parser.parse_args()
    output_transcript_handle = open(args.output_transcript, 'w', encoding='utf8')
    text_file_handle = open(args.input_text, 'r', encoding='utf8')
    text_file_data = text_file_handle.read().strip().split("\n")
    for line in text_file_data:
        parts = line.strip().split()
        output_transcript_handle.write(" ".join(parts[1:]) + '\n')


if __name__ == '__main__':
    main()
