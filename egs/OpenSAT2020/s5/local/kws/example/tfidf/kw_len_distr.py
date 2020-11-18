#!/usr/bin/env python3

import sys
from collections import Counter

filename = sys.argv[1]   # keywords.txt

kwlens = list()

with open(filename, 'r', encoding="utf-8") as fin:
    for line in fin:
        line = line.strip().split()
        kw_id = line[0]
        kw = line[1:]
        kwlens.append(len(kw))

counter = Counter(kwlens)
print(len(kwlens))
print(counter)
for k, c in counter.most_common():
    print(k, c/len(kwlens))
