import argparse
from collections import defaultdict

global words
global stopwords

def parse_opts():
    parser = argparse.ArgumentParser(
        description='',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument('--debug', default=False, action='store_true',
                        help='Debug info - e.g. showing the lines that were stripped')

    # parser.add_argument('words', type=str, help='vocabulary')
    parser.add_argument('word', type=str, help='word')
    parser.add_argument('count', type=str, help='count')
    parser.add_argument('output', type=str, help='output')
    opts = parser.parse_args()
    global debug
    debug = opts.debug
    return opts


if __name__ == '__main__':
    opts = parse_opts()

    # words = dict()
    # with open(opts.words, 'r', encoding="utf-8") as fin:
    #     for l in fin:
    #         ll = l.strip().split()
    #         words[ll[0]] = [0, 0]  # (tf, df)
    # print("len(words)=%d" % len(words))

    set1 = set()
    with open(opts.word, 'r', encoding="utf-8") as fin:
        for l in fin.readlines():
            ll = l.strip()
            set1.add(ll)
    print("len(set1)=%d" % len(set1))

    counts = dict()
    with open(opts.count, 'r', encoding="utf-8") as fin:
        for l in fin.readlines():
            ll = l.strip().split()
            counts[ll[1]] = int(ll[0])
    print("len(counts)=%d" % len(counts))

    counts2 = dict()
    for w in set1:
        counts2[w] = counts[w]

    with open(opts.output, 'w', encoding="utf-8") as fout:
        n = 100
        for k, v in sorted(counts2.items(), reverse=True, key=lambda item: item[1]):
            print(k, file=fout)
            n -= 1
            if n == 0:
                break


