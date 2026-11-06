"""Rebuild PicoSnap's original, offline sound effects (Python stdlib only)."""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
ROOT = Path(__file__).resolve().parents[1] / 'assets' / 'audio'
ROOT.mkdir(parents=True, exist_ok=True)


def render(name, length, voice):
    rng = random.Random(418)
    samples = []
    low = 0.0
    for i in range(round(RATE * length)):
        t = i / RATE
        raw = rng.uniform(-1, 1)
        low += (raw - low) * .14
        # Fade both ends so starting/stopping never introduces a hard click.
        edge = min(1, t / .004, (length - t) / .025)
        value = max(-.88, min(.88, voice(t, raw - low, low) * edge))
        samples.append(round(value * 32767))
    with wave.open(str(ROOT / f'{name}.wav'), 'wb') as f:
        f.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        f.writeframes(struct.pack('<' + 'h' * len(samples), *samples))


def note(t, frequency, length):
    if not 0 <= t < length:
        return 0
    envelope = (1 - math.exp(-t * 650)) * math.exp(-t * 22)
    return envelope * (math.sin(2 * math.pi * frequency * t) + .12 * math.sin(4 * math.pi * frequency * t))


render('tick', .13, lambda t, n, low: .36 * note(t, 660, .13))
render('ready', .19, lambda t, n, low: .40 * note(t, 880, .19))


def shutter(t, n, low):
    total = 0
    for start, gain, pitch in [(0, .72, 165), (.055, .48, 230)]:
        x = t - start
        if x >= 0:
            total += gain * math.exp(-x * 90) * (.65 * n + .35 * math.sin(2 * math.pi * pitch * x))
    return total


render('shutter', .20, shutter)


def feed(t, n, low):
    envelope = min(1, t / .14, (1.85 - t) / .18)
    flutter = .75 + .25 * math.sin(2 * math.pi * 23 * t)
    motor = math.sin(2 * math.pi * (112 * t + 1.8 * math.sin(2 * math.pi * 1.4 * t)))
    return envelope * (.13 * motor * flutter + .24 * low + .035 * n)


render('feed', 1.85, feed)


def peel(t, n, low):
    envelope = math.sin(math.pi * t / .65) ** .8
    crackle = .20 + .8 * abs(math.sin(2 * math.pi * (13 * t + 12 * t * t))) ** 8
    return envelope * (.42 * n * crackle + .32 * low)


render('peel', .65, peel)
render('stamp', .17, lambda t, n, low: math.exp(-t * 38) *
       (.42 * math.sin(2 * math.pi * (105 * t - 65 * t * t)) + .23 * n + .25 * low))
render('complete', .52, lambda t, n, low: sum(
    .25 * note(t - start, hz, .30) for start, hz in [(0, 523.25), (.105, 659.25), (.21, 783.99)]))
def sweep(f0, f1, length):
    """A sine gliding from f0 to f1 Hz over length seconds, phase-continuous."""
    k = (f1 - f0) / length
    return lambda t: math.sin(2 * math.pi * (f0 * t + .5 * k * t * t))


def blip(t, start, f0, f1, length, decay):
    x = t - start
    if not 0 <= x < length:
        return 0
    return (1 - math.exp(-x * 900)) * math.exp(-x * decay) * sweep(f0, f1, length)(x)


# pop: choosing something to make, a bubble that rises.
render('pop', .14, lambda t, n, low: .5 * blip(t, 0, 380, 980, .14, 30))
# select: a light tap for picking an option (filter, film, tool, tab).
render('select', .10, lambda t, n, low: .30 * note(t, 1320, .10) * math.exp(-t * 30) + .05 * n * math.exp(-t * 160))


def snip(t, n, low):
    total = 0
    for start in (0, .1):
        x = t - start
        if x >= 0:
            total += math.exp(-x * 75) * (.45 * n + .22 * math.sin(2 * math.pi * 3150 * x) + .12 * math.sin(2 * math.pi * 4700 * x))
    return total


# snip: two scissor closes, for a finished cut-out.
render('snip', .26, snip)

_bells = [(s, f) for s, f in [(0, 1568), (.07, 2093), (.15, 2637), (.22, 1976), (.31, 3136), (.39, 2349)]]


def sparkle(t, n, low):
    total = 0
    for start, hz in _bells:
        x = t - start
        if x >= 0:
            total += .17 * (1 - math.exp(-x * 900)) * math.exp(-x * 16) * (math.sin(2 * math.pi * hz * x) + .3 * math.sin(2 * math.pi * hz * 2.76 * x))
    return total + .03 * n * math.exp(-t * 6)


# sparkle: a shiny finish or effect landing on a sticker.
render('sparkle', .62, sparkle)
# undo / redo: two quick notes going back down / forward up.
render('undo', .2, lambda t, n, low: .3 * (note(t, 698.46, .1) + note(t - .075, 523.25, .125)))
render('redo', .2, lambda t, n, low: .3 * (note(t, 523.25, .1) + note(t - .075, 698.46, .125)))


def trash(t, n, low):
    # Paper crumpling: bursts of rustle, then a soft drop.
    rustle = abs(math.sin(2 * math.pi * (17 * t + 30 * t * t))) ** 6
    body = math.sin(math.pi * min(1, t / .3)) if t < .3 else 0
    drop = math.exp(-(t - .3) * 40) * math.sin(2 * math.pi * 95 * (t - .3)) if t >= .3 else 0
    return .5 * n * rustle * body + .15 * low * body + .35 * drop


# trash: crumpling something up after 刪除.
render('trash', .45, trash)


class Swish:
    """Noise through a low-pass whose corner opens then closes: air moving."""
    def __init__(self, length, peak, gain):
        self.length, self.peak, self.gain, self.y = length, peak, gain, 0.0

    def __call__(self, t, n, low):
        x = t / self.length
        corner = .02 + .5 * math.sin(math.pi * min(1, x / self.peak * .5)) ** 2 if x < self.peak else .02 + .5 * math.cos(math.pi * .5 * (x - self.peak) / (1 - self.peak)) ** 2
        self.y += (n - self.y) * corner
        envelope = math.sin(math.pi * x) ** 1.5
        return self.gain * self.y * envelope


# whoosh: sending a piece off to share.
render('whoosh', .45, Swish(.45, .55, 1.1))
# flip: turning a page (日記 months, 貼紙本 pages).
render('flip', .24, Swish(.24, .3, .9))
# oops: something didn't work - soft and low, never alarming.
render('oops', .32, lambda t, n, low: .32 * (note(t, 392, .15) + note(t - .12, 329.63, .2)))

print(f'Generated {len(list(ROOT.glob("*.wav")))} original sound effects:', sum(f.stat().st_size for f in ROOT.glob('*.wav')), 'bytes')
