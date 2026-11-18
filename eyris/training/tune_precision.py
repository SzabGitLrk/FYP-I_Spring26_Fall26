#!/usr/bin/env python3
"""Choose, for every label, which models report it and at what confidence so
that a reported object is right at least TARGET of the time, through the
phone camera and through the ESP32 camera alike.

    python tune_precision.py               # measure and print, change nothing
    python tune_precision.py --write       # also write app_models.json
    python tune_precision.py --crosscheck  # thresholds picked on half of the
                                           # photos, judged on the other half

Works on the boxes cached by `app_sim.py collect` (once per camera, see
SIM_CAMERA there). Each model gets two confidences per label:

  alone   enough for the model to report the label on its own word
  backed  lower; enough when another model sees the same label in the same
          place (the app's confirmAcrossModels)

Two models agreeing at modest confidence are right more often than one model
at high confidence, so the second route finds far more objects at the same
share of mistakes.
"""
import hashlib
import itertools
import json
import os
import sys
from collections import defaultdict

import numpy as np

import app_sim as S

TARGET = 0.90
# Thresholds are picked on the same photos they are judged on, and the
# lowest passing one is always a little lucky. So it is not the measured
# share of right answers that must reach the target but its cautious
# estimate (lower_bound): 12 right out of 12 passes, 46 of 50 does not, 280
# of 300 does. --crosscheck shows what that leaves on photos not used.
FLOOR = 0.90
THIN_FLOOR = 0.80      # for labels with too few test objects to pass FLOOR
MIN_PER_SET = 6        # a test set judges a threshold from this many detections
ALONE_GRID = [round(0.15 + 0.01 * i, 2) for i in range(76)]      # 0.15 .. 0.90
BACKED_GRID = [0.08, 0.10, 0.12, 0.15, 0.18, 0.22, 0.26, 0.30, 0.35, 0.40, 0.50, 0.60]
NEVER = float('inf')
# The app uses one set of thresholds whatever the camera, so every threshold
# has to hold through each of them.
CAMERAS = ['phone', 'esp32']
CAMERA_NAMES = {'phone': 'Phone camera', 'esp32': 'ESP32 camera (imitated frames)'}
HERE = os.path.dirname(os.path.abspath(__file__))
_raw, _boxes = {}, {}


def raw(set_name, tag, camera):
    key = (set_name, tag, camera)
    if key not in _raw:
        _raw[key] = S.load_raw(set_name, tag, camera)
    return _raw[key]


def test_sets():
    held = S.ade_set(os.path.join(S.WORK, 'scene', 'test.txt'))
    return {'ade_heldout': held, 'ade_all': S.ade_set(), 'oi_val': S.oi_set()}


def sets_for(tags, camera):
    """The scene model was trained on most ADE photos: only the held-out ones
    may judge it. The other models never saw ADE. ESP32 frames were only
    imitated for the held-out ADE photos."""
    whole = 'scene' not in tags and camera == 'phone'
    return ['ade_all' if whole else 'ade_heldout', 'oi_val']


def fold_of(name):
    return int(hashlib.md5(name.encode()).hexdigest(), 16) % 2


class Boxes:
    """Every box of one label from some models on their test sets, through
    one camera, each judged on its own: right (it covers a labelled object),
    wrong, or not judged."""

    def __init__(self, sets, label, tags, camera):
        self.set_names = sets_for(tags, camera)
        rows, support = [], []
        for si, set_name in enumerate(self.set_names):
            for pi, (name, _path, truth, ignore, scored) in enumerate(sets[set_name]):
                fold = fold_of(name)
                per_model = []
                for tag in tags:
                    found = [d for d in raw(set_name, tag, camera).get(name, []) if d[1] == label][:3]
                    per_model.append(S.scene_rules(found))
                for mi, found in enumerate(per_model):
                    for det in found:
                        judged = S.score([det], truth, ignore, scored)
                        status, hit = -1, -1
                        if judged:
                            status = int(judged[0][2])
                            if status:
                                overlaps = [S.iou(det[2], o) for o in truth[label]]
                                hit = (si * 100000 + pi) * 1000 + int(np.argmax(overlaps))
                        rows.append((det[0], mi, si, status, hit, fold))
                        support.append([
                            max([o[0] for o in other if S.iou(det[2], o[2]) >= S.BACKING_IOU],
                                default=0.0) if oi != mi else 0.0
                            for oi, other in enumerate(per_model)])
        table = np.array(rows, dtype=float).reshape(-1, 6)
        self.score, self.model = table[:, 0], table[:, 1].astype(int)
        self.set, self.status = table[:, 2].astype(int), table[:, 3].astype(int)
        self.hit, self.fold = table[:, 4].astype(np.int64), table[:, 5].astype(int)
        self.support = np.array(support, dtype=float).reshape(-1, len(tags))

    def passing(self, alone, backed):
        alone, backed = np.asarray(alone, float), np.asarray(backed, float)
        agreed = (self.support >= np.minimum(alone, backed)[None, :]).any(axis=1)
        return (self.score >= alone[self.model]) | (
            (self.score >= backed[self.model]) & agreed)

    def tally(self, keep):
        """[(right, wrong)] per test set. An object found twice counts once."""
        out = []
        for si in range(len(self.set_names)):
            here = keep & (self.set == si)
            out.append((len(np.unique(self.hit[here & (self.status == 1)])),
                        int((here & (self.status == 0)).sum())))
        return out


class Evidence:
    """The boxes of one label from some models, as seen through every camera."""

    def __init__(self, sets, label, tags, fold=None):
        self.views = []
        for camera in CAMERAS:
            key = (label, tuple(tags), camera)
            if key not in _boxes:
                _boxes[key] = Boxes(sets, label, tags, camera)
            self.views.append(_boxes[key])
        self.masks = [np.ones(len(v.score), bool) if fold is None else v.fold == fold
                      for v in self.views]

    def tallies(self, alone, backed):
        """One tally per camera."""
        return [view.tally(mask & view.passing(alone, backed))
                for view, mask in zip(self.views, self.masks)]


def lower_bound(right, wrong, z=1.0):
    """Wilson lower bound of the share of right answers: what it is likely to
    be at least, given how few or many detections were seen."""
    n = right + wrong
    if not n:
        return 0.0
    p = right / n
    return (p + z * z / (2 * n) - z * np.sqrt(p * (1 - p) / n + z * z / (4 * n * n))) / (1 + z * z / n)


def good(tally, floor, nothing_is_fine=False):
    right, wrong = sum(t for t, _ in tally), sum(f for _, f in tally)
    if not right + wrong:
        return nothing_is_fine
    if lower_bound(right, wrong) < floor:
        return False
    return all(t / (t + f) >= TARGET for t, f in tally if t + f >= MIN_PER_SET)


def pick_alone(evidence, floor):
    """Lowest confidence at which the model is right often enough by itself
    through every camera, and still is a little higher up (not a lucky dip
    in the curve)."""
    def holds(threshold, higher_up=False):
        return all(good(tally, min(floor, THIN_FLOOR) if higher_up else floor, higher_up)
                   for tally in evidence.tallies([threshold], [NEVER]))
    for threshold in ALONE_GRID:
        if holds(threshold) and holds(threshold + 0.02, True) and holds(threshold + 0.04, True):
            return threshold
    return None


def tighten(evidence, alone):
    """The models were each picked on their own photos. Together, on the
    photos that may judge all of them, they must still reach the target:
    raise the least reliable model's confidence until they do."""
    alone = list(alone)
    nobody = [NEVER] * len(alone)

    def fine(tally):
        right, wrong = map(sum, zip(*tally))
        return right + wrong == 0 or (right / (right + wrong) >= TARGET and all(
            t / (t + f) >= TARGET for t, f in tally if t + f >= MIN_PER_SET))

    def share_right(m):
        only = [a if i == m else NEVER for i, a in enumerate(alone)]
        right = sum(t for tally in evidence.tallies(only, nobody) for t, _ in tally)
        wrong = sum(f for tally in evidence.tallies(only, nobody) for _, f in tally)
        return right / (right + wrong) if right + wrong else 1.0

    while not all(fine(tally) for tally in evidence.tallies(alone, nobody)):
        worst = min((m for m, a in enumerate(alone) if a != NEVER), key=share_right)
        alone[worst] = round(alone[worst] + 0.02, 2) if alone[worst] < 0.89 else NEVER
    return alone


def pick_label(sets, label, fold=None, floor=FLOOR):
    """{tag: (alone, backed)} for one label; empty when no model qualifies."""
    tags = [s['tag'] for s in S.CONFIG['models'] if label in s['names_wide'].values()]
    alone = [pick_alone(Evidence(sets, label, [tag], fold), floor) or NEVER for tag in tags]
    joint = Evidence(sets, label, tags, fold)
    alone = tighten(joint, alone)
    best, best_key = [NEVER] * len(tags), None
    if len(tags) > 1:
        options = [[NEVER] + [b for b in BACKED_GRID if b < a] for a in alone]
        for backed in itertools.product(*options):
            tallies = joint.tallies(alone, backed)
            if not all(good(tally, floor) for tally in tallies):
                continue
            # Most objects found; then the more cautious thresholds.
            key = (sum(t for tally in tallies for t, _ in tally), sum(min(b, 1) for b in backed))
            if best_key is None or key > best_key:
                best, best_key = list(backed), key
    out = {}
    for tag, a, b in zip(tags, alone, best):
        if a != NEVER or b != NEVER:
            out[tag] = (None if a == NEVER else a, None if b == NEVER else b)
    return out


def choose(sets, fold=None):
    """({tag: {label: (alone, backed)}}, labels resting on thin evidence)."""
    chosen = {s['tag']: {} for s in S.CONFIG['models']}
    thin = []
    for label in S.CONFIG['labels']:
        picked = pick_label(sets, label, fold)
        if not picked:
            picked = pick_label(sets, label, fold, THIN_FLOOR)
            if picked:
                thin.append(label)
        for tag, pair in picked.items():
            chosen[tag][label] = pair
    return chosen, thin


def with_manual(chosen):
    """Labels the boxed test photos cannot settle keep the thresholds
    written, with the reason, in manual_thresholds.json."""
    path = os.path.join(HERE, 'manual_thresholds.json')
    if os.path.exists(path):
        manual = {tag: labels for tag, labels in json.load(open(path)).items()
                  if not tag.startswith('_')}
        for label in {label for labels in manual.values() for label in labels}:
            for picked in chosen.values():
                picked.pop(label, None)
        for tag, labels in manual.items():
            for label, (alone, backed) in labels.items():
                chosen[tag][label] = (alone, backed)
    return chosen


def configured(chosen):
    """app_models.json content with `chosen` as the reported labels."""
    config = json.loads(json.dumps(S.CONFIG))
    for spec in config['models']:
        picked = chosen.get(spec['tag'], {})
        spec['names'] = {n: l for n, l in spec['names_wide'].items() if l in picked}
        spec['thresholds'] = {l: a for l, (a, _) in sorted(picked.items()) if a is not None}
        spec['backed'] = {l: b for l, (_, b) in sorted(picked.items()) if b is not None}
    return config


def pipeline(sets, config, set_name, camera, fold=None):
    """Per label (right, wrong, objects) of the whole app pipeline on one set."""
    specs = {s['tag']: s for s in config['models']}
    tp, fp, total = defaultdict(int), defaultdict(int), defaultdict(int)
    for name, _path, truth, ignore, scored in sets[set_name]:
        if fold is not None and fold_of(name) != fold:
            continue
        dets = S.app_detections(
            [(specs[tag], raw(set_name, tag, camera).get(name, [])) for tag in specs])
        for label, boxes in truth.items():
            total[label] += len(boxes)
        for label, _s, ok in S.score(dets, truth, ignore, scored):
            (tp if ok else fp)[label] += 1
    return tp, fp, total


def judged_on(config, label, camera):
    """Test sets that may judge `label` as the app reports it."""
    return sets_for([spec['tag'] for spec in config['models']
                     if label in spec['names'].values()], camera)


def table(sets, config, camera, thin=()):
    results = {s: pipeline(sets, config, s, camera) for s in ('ade_heldout', 'ade_all', 'oi_val')}
    print(f"\n{CAMERA_NAMES[camera]}\n{'label':14s} | {'models: alone/backed':46s} | "
          'rooms+streets: objects right wrong prec. recall | general photos: objects right wrong prec. recall | together')
    rows = {}
    for label in config['labels']:
        sources = ', '.join(
            f"{spec['tag']} {spec['thresholds'].get(label, 0) or '-'}/{spec['backed'].get(label, 0) or '-'}"
            for spec in config['models'] if label in spec['names'].values())
        cells, tp_all, fp_all = [], 0, 0
        rows[label] = {'sets': {}}
        for set_name in judged_on(config, label, camera):
            tp, fp, total = results[set_name]
            t, f, n = tp[label], fp[label], total[label]
            tp_all, fp_all = tp_all + t, fp_all + f
            p = t / (t + f) if t + f else None
            r = t / n if n else None
            cells.append(f"{n:5d} {t:4d} {f:3d}  {'  -' if p is None else format(p, '4.0%')} "
                         f"{'  -' if r is None else format(r, '4.0%')}")
            rows[label]['sets'][set_name] = dict(objects=n, right=t, wrong=f, precision=p, recall=r)
        together = tp_all / (tp_all + fp_all) if tp_all + fp_all else None
        rows[label].update(right=tp_all, wrong=fp_all, precision=together,
                           thin_evidence=label in thin)
        print(f'{label:14s} | {sources:46s} | ' + ' | '.join(cells) + ' | '
              + ('    -' if together is None else f'{together:5.0%}')
              + f' ({tp_all}/{tp_all + fp_all})' + ('  thin evidence' if label in thin else ''))
    tp_sum = sum(r['right'] for r in rows.values())
    fp_sum = sum(r['wrong'] for r in rows.values())
    print(f'all labels: {tp_sum} right, {fp_sum} wrong -> '
          f'{tp_sum / max(tp_sum + fp_sum, 1):.1%} of reported objects are right')
    rows['_all'] = dict(right=tp_sum, wrong=fp_sum, precision=tp_sum / max(tp_sum + fp_sum, 1))
    return rows


def crosscheck(sets):
    """Pick on one half of the photos, judge on the other, both ways round."""
    tallies = {camera: (defaultdict(int), defaultdict(int)) for camera in CAMERAS}
    for fold in (0, 1):
        config = configured(with_manual(choose(sets, fold)[0]))
        for camera in CAMERAS:
            for label in config['labels']:
                for set_name in judged_on(config, label, camera):
                    tp, fp, _ = pipeline(sets, config, set_name, camera, fold=1 - fold)
                    tallies[camera][0][label] += tp[label]
                    tallies[camera][1][label] += fp[label]
    print('\nThresholds picked on half of the photos, judged on the other half:')
    print(f"  {'label':14s} " + ' | '.join(f'{CAMERA_NAMES[c]:>34s}' for c in CAMERAS))
    for label in S.CONFIG['labels']:
        cells = []
        for camera in CAMERAS:
            right, wrong = tallies[camera][0][label], tallies[camera][1][label]
            cells.append(f'{right:4d} right {wrong:3d} wrong -> '
                         + (f'{right / (right + wrong):5.0%}' if right + wrong else '    -'))
        print(f'  {label:14s} ' + ' | '.join(f'{c:>34s}' for c in cells))
    for camera in CAMERAS:
        right, wrong = sum(tallies[camera][0].values()), sum(tallies[camera][1].values())
        print(f'  {CAMERA_NAMES[camera]}: {right} right, {wrong} wrong -> {right / max(right + wrong, 1):.1%}')


def main():
    sets = test_sets()
    if '--crosscheck' in sys.argv:
        crosscheck(sets)
        return
    chosen, thin = choose(sets)
    config = configured(with_manual(chosen))
    report = {camera: table(sets, config, camera, thin) for camera in CAMERAS}
    if '--write' in sys.argv:
        json.dump(config, open(os.path.join(HERE, 'app_models.json'), 'w'), indent=1)
        json.dump(report, open(os.path.join(HERE, 'accuracy_report.json'), 'w'), indent=1)
        print('wrote app_models.json and accuracy_report.json')


if __name__ == '__main__':
    main()
