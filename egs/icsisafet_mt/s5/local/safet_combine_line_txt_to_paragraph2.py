#!/usr/bin/env python3

""" This script creates paragraph level text file. It reads 
    the line level text file and combines them to get
    paragraph level file.
  Eg. cat $decode_dir/scoring_kaldi/penalty_$wip/$LMWT.txt | \
          local/combine_line_txt_to_paragraph.py > $decode_dir/para/penalty_$wip/$LMWT.txt
  Eg. Input:  000001_0003897_0004367_0001_20190118_163117_part1_AB_xxxxx the fire is spreading to bravo four romeo five
              000001_0003938_0004443_0001_20190110_200708_part1_D_xxxxxx rolling for spreading the fire bravo seven romeo four
              000001_0003963_0004316_0001_20190110_200708_part1_C_xxxxxx spreading the fire bravo six
              spk_sttime_endtime_wavid
"""

import argparse
import os
import io
import sys
### main ###
infile = io.TextIOWrapper(sys.stdin.buffer, encoding='utf-8')
output = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

paragraph_txt_dict = dict()
#for line in infile:
#  parts = line.strip().split(' ')
#  starttime = parts[0].split('_')[1]
#  endtime = parts[0].split('_')[2]
#  time = starttime_endtime
#  line_text = " ".join(line_vect[1:])
#  paragraph_txt_dict[time] = line_text
#
#para_txt=" "
#for line_id in sorted(paragraph_txt_dict):
#    text = paragraph_txt_dict[line_id]
#    para_txt = para_txt + " " + text
#
#utt_id = 'utt'
#output.write(utt_id + ' ' + para_txt + '\n')


for line in infile:
  parts = line.strip().split(' ')
  starttime = parts[0].split('_')[1]
  endtime = parts[0].split('_')[2]
  time = starttime+ '_' + endtime
  paragraph_id = parts[0].split('_')[3:]
  paragraph_id = "_".join(paragraph_id)
  line_text = " ".join(parts[1:])
  if paragraph_id not in paragraph_txt_dict.keys():
      paragraph_txt_dict[paragraph_id] = dict()
  paragraph_txt_dict[paragraph_id][time] = line_text

para_txt_dict = dict()
for para_id in sorted(paragraph_txt_dict.keys()):
    para_txt = ""
    for line_id in sorted(paragraph_txt_dict[para_id]):
        text = paragraph_txt_dict[para_id][line_id]
        para_txt = para_txt + " " + text
    para_txt_dict[para_id] = para_txt
    utt_id = 'writer' + str(para_id)
    output.write(utt_id + ' ' + para_txt + '\n')
