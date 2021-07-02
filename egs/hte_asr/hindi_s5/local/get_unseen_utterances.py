#!/usr/bin/env python3

import os
import argparse
parser = argparse.ArgumentParser(description="""get unseen utterances from seen utterances""")
parser.add_argument('input_text', type=str, help='text file with seen counts')
parser.add_argument('output_text', type=str, help='Output file that contains transcript')
def main():

    args = parser.parse_args()
    output_transcript_handle = open(args.output_text, 'w')
    text_file_handle = open(args.input_text, 'r')
    text_file_data = text_file_handle.read().strip().split("\n")
    for line in text_file_data:
        parts = line.strip().split()
        if int(parts[0]) != 0:
            continue
        output_transcript_handle.write(" ".join(parts[1:]) + '\n')


if __name__ == '__main__':
    main()
