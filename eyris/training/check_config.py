#!/usr/bin/env python3
"""Check that the app's Dart configuration (labels per model and thresholds)
is the one that was measured (app_models.json).

    python check_config.py <path to lib/services/detection_models.dart>
    python check_config.py --dart     # print the maps to paste into that file
"""
import json
import os
import re
import sys

config = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'app_models.json')))


def dart_map(values, indent='    '):
    return '\n'.join(f"{indent}'{key}': {value:.2f}," for key, value in values.items())


def print_dart():
    for model in config['models']:
        print(f"// --- {model['tag']} ---\n  names: {{")
        print('\n'.join(f"    '{name}': '{label}'," for name, label in model['names'].items()))
        print('  },')
        unreported = [n for n in model['names_wide'] if n not in model['names']]
        if model['listed_only'] and unreported:
            print('  alsoCompete: {' + ', '.join(f"'{n}'" for n in unreported) + '},')
        print('  thresholds: {\n' + dart_map(model['thresholds']) + '\n  },')
        print('  backedThresholds: {\n' + dart_map(model.get('backed', {})) + '\n  },')


def section(block, name):
    """The body of `name: {...}` inside one DetectorSpec(...)."""
    match = re.search(r'(?<![A-Za-z])%s: \{(.*?)\}' % name, block, re.S)
    return match.group(1) if match else ''


def check(path):
    source = open(path, encoding='utf8').read()
    in_step = True
    for model in config['models']:
        block = source[source.index("tag: '%s'" % model['tag']):]
        block = block[:block.index(');')]
        names = dict(re.findall(r"'([^']+)': '([^']+)'", section(block, 'names')))
        found = {key: {k: float(v) for k, v in re.findall(r"'([^']+)': ([0-9.]+)", section(block, key))}
                 for key in ('thresholds', 'backedThresholds')}
        compete = set(re.findall(r"'([^']+)'", section(block, 'alsoCompete')))
        wanted = {'thresholds': model['thresholds'], 'backedThresholds': model.get('backed', {})}
        same = names == model['names'] and found == wanted
        if model['listed_only']:
            # Prompts that take part without being reported.
            same &= compete == set(model['names_wide']) - set(model['names'])
        in_step &= same
        print(model['tag'], 'OK' if same else 'DIFFERENT')
        if not same:
            print('  names only in dart:', set(names.items()) - set(model['names'].items()))
            print('  names only in json:', set(model['names'].items()) - set(names.items()))
            for key in found:
                print(f'  {key} only in dart:', set(found[key].items()) - set(wanted[key].items()))
                print(f'  {key} only in json:', set(wanted[key].items()) - set(found[key].items()))
            if model['listed_only']:
                print('  alsoCompete differs by:', compete ^ (set(model['names_wide']) - set(model['names'])))
    print('IN STEP' if in_step else 'MISMATCH')
    return 0 if in_step else 1


if __name__ == '__main__':
    if sys.argv[1] == '--dart':
        print_dart()
    else:
        sys.exit(check(sys.argv[1]))
