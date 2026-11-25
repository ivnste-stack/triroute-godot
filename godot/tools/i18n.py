#!/usr/bin/env python3
"""The game's English: the Ukrainian strings of the scripts and their translations.

    python3 tools/i18n.py extract     # assets/i18n/keys.txt: every Ukrainian string literal, one a line
    python3 tools/i18n.py missing     # the keys without a translation in assets/i18n/en.json
    python3 tools/i18n.py add FILE    # lines «ukrainian<TAB>english» merged into en.json

assets/i18n/en.json (Ukrainian → English) is the table the game reads.

Run from godot/. Name parts (first and last names, company and firm name pieces, the editor's syllables)
are left out: names are transliterated at run time (scripts/core/i18n.gd).
"""
import glob
import json
import re
import sys

CY = re.compile('[А-Яа-яІіЇїЄєҐґ]')
LIT = re.compile(r'"((?:[^"\\]|\\.)*)"')
SKIP_CONST = re.compile(r'^const (CO_NAMES_A|CO_NAMES_B|COMP_N|FIRST|LAST|NAME_A|NAME_M|NAME_B|NAME_V|STATE_A|STATE_B)\b')
IND_PARTS = re.compile(r'"(a|b|fixed)": \[[^\]]*\]')


def unescape(s):
    return s.encode('utf-8').decode('unicode_escape').encode('latin-1').decode('utf-8') if '\\' in s else s


def extract():
    keys = []
    seen = set()
    for f in sorted(glob.glob('scripts/**/*.gd', recursive=True)):
        if f.endswith('core/i18n.gd'):   # the translator's own tables and patterns
            continue
        for line in open(f, encoding='utf-8'):
            st = line.strip()
            if st.startswith('#') or st.startswith('##') or SKIP_CONST.match(st):
                continue
            line = IND_PARTS.sub('', line)
            for m in LIT.finditer(line):
                t = m.group(1)
                if not CY.search(t):
                    continue
                t = unescape(t)
                if t not in seen:
                    seen.add(t)
                    keys.append(t)
    with open('assets/i18n/keys.txt', 'w', encoding='utf-8') as o:
        for k in keys:
            o.write(k.replace('\n', '\\n') + '\n')
    print(len(keys), 'keys')


def load():
    try:
        return json.load(open('assets/i18n/en.json', encoding='utf-8'))
    except FileNotFoundError:
        return {}


def save(d):
    json.dump(d, open('assets/i18n/en.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=0, sort_keys=True)


def add():
    d = load()
    n = 0
    for l in open(sys.argv[2], encoding='utf-8'):
        l = l.rstrip('\n')
        if '\t' not in l:
            continue
        k, v = l.split('\t', 1)
        d[k.replace('\\n', '\n')] = v.replace('\\n', '\n')
        n += 1
    save(d)
    print(n, 'added,', len(d), 'in all')


def missing():
    d = load()
    for l in open('assets/i18n/keys.txt', encoding='utf-8'):
        k = l.rstrip('\n').replace('\\n', '\n')
        if k not in d:
            print(k.replace('\n', '\\n'))


{'extract': extract, 'missing': missing, 'add': add}[sys.argv[1]]()
