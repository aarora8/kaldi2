#!/usr/bin/env python3

import argparse
import random
import re


def parse_opts():
    parser = argparse.ArgumentParser(
        description='',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument('--debug', default=False, action='store_true',
                        help='Debug info - e.g. showing the lines that were stripped')

    parser.add_argument('words', type=str, help='words file')
    parser.add_argument('counts', type=str, help='ngram counts')
    parser.add_argument('size', type=str, help='size of the samples for each order seperated by comma, -1 means all')
    parser.add_argument('output', type=str, help='output file')
    opts = parser.parse_args()
    global debug
    debug = opts.debug
    return opts


if __name__ == '__main__':
    opts = parse_opts()

    words = set()
    with open(opts.words, 'r', encoding="utf-8") as fin:
        for l in fin:
            words.add(l.strip())
    print("len(words)=%d" % len(words))

    words2 = set(words)
    word2 = words2.difference(["one", "two", "three", "four", "five", "six",
                               "seven", "eight", "nine", "okay", "bravo", "romeo", "yup"])

    order = 4
    ngram_counts = dict()
    for i in range(1, order + 1):
        ngram_counts[i] = dict()
    regexp = re.compile(r'[^a-z\-\'\s]')
    with open(opts.counts, 'r', encoding="utf-8") as fin:
        for l in fin:
            ll = l.strip().split("\t")
            if "s>" in ll[0]:
                continue
            if regexp.search(ll[0]):
                continue

            ws = ll[0].split()
            flag = True
            for w in ws:
                if len(w) <= 1 or w.endswith("-"):
                    flag = False
                    break
                if w not in word2:
                    flag = False
                    break
            if not flag:
                continue

            n = len(ws)
            ngram_counts[n][ll[0]] = int(ll[1])
    for i in range(1, order + 1):
        print("len(ngram_counts[%d])=%d" % (i, len(ngram_counts[i])))

    sizes = [int(s) for s in opts.size.split(",")]
    queries = []
    for i in range(1, order + 1):
        if i == 1:
            queries.append(list(words))
        else:
            queries.append(random.sample(ngram_counts[i].keys(), sizes[i-1]))

    with open(opts.output, 'w', encoding="utf-8") as fout:
        for l in queries:
            for ll in l:
                print(ll, file=fout)
