"""Exports the Romanian card texts for the AI-notes server.

Reads lib/l10n/her_insights_ro.dart and writes content/her-insights-ro.json:
the cards (title and body), the opening lines and the words that fill them
in. The server writes Romanian notes from this file
(server/her-notes.js); test/her_insights_ro_json_test.dart checks it still
matches the app.

Run after changing her_insights_ro.dart:
  python tool/export_ro_cards.py
"""
import io
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, 'lib', 'l10n', 'her_insights_ro.dart')
TARGET = os.path.join(ROOT, 'content', 'her-insights-ro.json')

STR = r"""(?:'(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*")"""


def unq(lit):
    body = lit[1:-1]
    out, i = [], 0
    while i < len(body):
        if body[i] == '\\' and i + 1 < len(body):
            out.append({'n': '\n'}.get(body[i + 1], body[i + 1]))
            i += 2
        else:
            out.append(body[i])
            i += 1
    return ''.join(out)


def section(src, name, end='\n  },'):
    i = src.index(f'  {name}: ')
    return src[i:src.index(end, i)]


def string_map(src, name, key=r"'([^']+)'"):
    return {m.group(1): unq(m.group(2))
            for m in re.finditer(rf'^    {key}: ({STR}),', section(src, name), re.M)}


def main():
    src = io.open(SOURCE, encoding='utf-8').read()
    cards = {}
    for m in re.finditer(r"'(\w+)': InsightText\((.*?)\n    \),", section(src, 'cards'), re.S):
        fields = {}
        for field in ('title', 'body'):
            f = re.search(rf'\b{field}: ({STR})', m.group(2))
            fields[field] = unq(f.group(1))
        cards[m.group(1)] = fields

    def word_list(name):
        i = src.index(f'  {name}: [')
        return [unq(s) for s in re.findall(STR, src[i:src.index('\n  ],', i)])]

    data = {
        'language': 'ro',
        'cards': cards,
        'openings': string_map(src, 'openings', r"'(P\w+)'"),
        'loggedPhrase': string_map(src, 'loggedPhrase'),
        'patternPhrase': string_map(src, 'patternPhrase'),
        'windowPhrase': string_map(src, 'windowPhrase', r'CyclePhase\.(\w+)'),
        'weekdaysMondayFirst': word_list('weekdays'),
        'months': word_list('months'),
        'ui': string_map(src, 'ui'),
    }
    with io.open(TARGET, 'w', encoding='utf-8', newline='\n') as f:
        f.write(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    print(f'{TARGET}: {len(cards)} cards, {len(data["openings"])} opening lines')


if __name__ == '__main__':
    main()
