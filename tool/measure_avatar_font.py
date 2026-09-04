#!/usr/bin/env python3
"""Read the real glyph metrics `MemberAvatar`'s fit bound depends on.

Backlog G-14: `flutter test` draws the Ahem-style `FlutterTest` font (~1 em
per glyph), so NO widget test in this repo can measure whether text
physically fits. Backlog G-16: the avatar's two-letter initials therefore
have to be checked against the real shipped font, offline.

This script is that measurement. It parses `assets/fonts/Inter-SemiBold.ttf`
(the face `FontWeight.w600` resolves to) straight out of its own sfnt tables
with `struct` -- no third-party font library, and no `flutter`/`dart`
invocation, so it never touches the shared SDK lock. It prints the constant
`test/features/members/member_avatar_test.dart` hard-codes, so anyone can
re-derive that constant instead of trusting it.

    python3 tool/measure_avatar_font.py

The model it computes: the initials are a single line drawn with
`height: null` and `letterSpacing: 0` (both pinned in `MemberAvatar`),
centred inside the ring by the `Container`'s decoration padding, so the ink's
farthest point from the avatar's centre is the corner of the ink bounding
box. What is reported is that corner distance, per unit of `fontSize`, for
the worst ordered pair of capitals the font can produce.
"""

import itertools
import math
import os
import struct



class Font:
    def __init__(self, path):
        self.d = open(path, 'rb').read()
        num_tables, = struct.unpack('>H', self.d[4:6])
        self.tables = {}
        for i in range(num_tables):
            off = 12 + 16 * i
            tag = self.d[off:off+4].decode('latin1')
            o, l = struct.unpack('>II', self.d[off+8:off+16])
            self.tables[tag] = (o, l)
        ho, _ = self.tables['head']
        self.units_per_em, = struct.unpack('>H', self.d[ho+18:ho+20])
        self.index_to_loc, = struct.unpack('>h', self.d[ho+50:ho+52])
        ao, _ = self.tables['hhea']
        self.ascender, self.descender, self.line_gap = struct.unpack('>hhh', self.d[ao+4:ao+10])
        self.num_h_metrics, = struct.unpack('>H', self.d[ao+34:ao+36])
        oo, _ = self.tables['OS/2']
        self.os2_version, = struct.unpack('>H', self.d[oo:oo+2])
        self.fs_selection, = struct.unpack('>H', self.d[oo+62:oo+64])
        self.win_ascent, self.win_descent = struct.unpack('>HH', self.d[oo+74:oo+78])
        self.typo_ascender, self.typo_descender, self.typo_line_gap = struct.unpack('>hhh', self.d[oo+68:oo+74])
        self.cap_height = None
        if self.os2_version >= 2:
            self.cap_height, = struct.unpack('>h', self.d[oo+88:oo+90])
        mo, _ = self.tables['maxp']
        self.num_glyphs, = struct.unpack('>H', self.d[mo+4:mo+6])
        self._loca()
        self._cmap()

    def _loca(self):
        lo, _ = self.tables['loca']
        n = self.num_glyphs + 1
        if self.index_to_loc == 0:
            self.loca = [2*v for v in struct.unpack('>%dH' % n, self.d[lo:lo+2*n])]
        else:
            self.loca = list(struct.unpack('>%dI' % n, self.d[lo:lo+4*n]))

    def _cmap(self):
        co, _ = self.tables['cmap']
        n, = struct.unpack('>H', self.d[co+2:co+4])
        best = None
        for i in range(n):
            pid, eid, off = struct.unpack('>HHI', self.d[co+4+8*i:co+12+8*i])
            if (pid, eid) in ((3, 10), (3, 1), (0, 3), (0, 4), (0, 6)):
                fmt, = struct.unpack('>H', self.d[co+off:co+off+2])
                if fmt in (4, 12):
                    best = (fmt, co + off)
                    if fmt == 12:
                        break
        fmt, so = best
        self.cmap = {}
        if fmt == 4:
            segx2, = struct.unpack('>H', self.d[so+6:so+8])
            seg = segx2 // 2
            ends = struct.unpack('>%dH' % seg, self.d[so+14:so+14+segx2])
            sb = so + 16 + segx2
            starts = struct.unpack('>%dH' % seg, self.d[sb:sb+segx2])
            db = sb + segx2
            deltas = struct.unpack('>%dh' % seg, self.d[db:db+segx2])
            rb = db + segx2
            ranges = struct.unpack('>%dH' % seg, self.d[rb:rb+segx2])
            for i in range(seg):
                for c in range(starts[i], min(ends[i], 0xFFFF) + 1):
                    if ranges[i] == 0:
                        g = (c + deltas[i]) & 0xFFFF
                    else:
                        gi = rb + 2*i + ranges[i] + 2*(c - starts[i])
                        if gi + 2 > len(self.d):
                            continue
                        g, = struct.unpack('>H', self.d[gi:gi+2])
                        if g:
                            g = (g + deltas[i]) & 0xFFFF
                    if g:
                        self.cmap[c] = g
        else:
            ngroups, = struct.unpack('>I', self.d[so+12:so+16])
            for i in range(ngroups):
                s, e, gs = struct.unpack('>III', self.d[so+16+12*i:so+28+12*i])
                for c in range(s, e+1):
                    self.cmap[c] = gs + (c - s)

    def hmtx(self, gid):
        ho, _ = self.tables['hmtx']
        if gid < self.num_h_metrics:
            aw, lsb = struct.unpack('>Hh', self.d[ho+4*gid:ho+4*gid+4])
        else:
            aw, = struct.unpack('>H', self.d[ho+4*(self.num_h_metrics-1):ho+4*(self.num_h_metrics-1)+2])
            off = ho + 4*self.num_h_metrics + 2*(gid - self.num_h_metrics)
            lsb, = struct.unpack('>h', self.d[off:off+2])
        return aw, lsb

    def bbox(self, gid):
        """Ink bounding box in font units, or None for an empty glyph."""
        go, _ = self.tables['glyf']
        s, e = self.loca[gid], self.loca[gid+1]
        if e <= s:
            return None
        nc, xmin, ymin, xmax, ymax = struct.unpack('>hhhhh', self.d[go+s:go+s+10])
        return xmin, ymin, xmax, ymax


def _main() -> None:
    path = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        'assets', 'fonts', 'Inter-SemiBold.ttf',
    )
    f = Font(path)
    upm = f.units_per_em
    # A paragraph with `height: null` is `ascent + descent` tall and its
    # centre sits `(ascent - descent) / 2` above the baseline.
    centre_y = (f.ascender + f.descender) / 2

    print('font                   ', os.path.relpath(path))
    print('unitsPerEm             ', upm)
    print('hhea asc/desc/lineGap  ', f.ascender, f.descender, f.line_gap)
    print('OS/2 sTypo asc/desc    ', f.typo_ascender, f.typo_descender)
    print('OS/2 usWinAsc/Desc     ', f.win_ascent, f.win_descent)
    print('OS/2 fsSelection       ', hex(f.fs_selection),
          'USE_TYPO_METRICS =', bool(f.fs_selection & (1 << 7)))
    print('OS/2 sCapHeight        ', f.cap_height)
    print('box centre above base  ', centre_y, 'units = %.5f em'
          % (centre_y / upm))
    print()

    pool = [chr(c) for c in range(ord('A'), ord('Z') + 1)]
    pool += [chr(c) for c in range(ord('0'), ord('9') + 1)]
    # Latin-1 / Latin Extended capitals a European family name can start
    # with. The app ships a German locale, so umlauts are not exotic.
    pool += list('ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖØÙÚÛÜÝÞŁŃŐŒŚŠŸŹŻŽĐĞİ')
    pool = [c for c in dict.fromkeys(pool) if ord(c) in f.cmap]

    def reach(first: str, second: str):
        """Corner distance from the run's centre, in em, and its parts."""
        gid1, gid2 = f.cmap[ord(first)], f.cmap[ord(second)]
        adv1, _ = f.hmtx(gid1)
        adv2, _ = f.hmtx(gid2)
        box1, box2 = f.bbox(gid1), f.bbox(gid2)
        centre_x = (adv1 + adv2) / 2
        # The ink is NOT centred in the advance run -- bearings differ -- so
        # take the farther of the two sides, not half the ink width.
        half_w = max(centre_x - box1[0], adv1 + box2[2] - centre_x)
        half_h = max(max(box1[3], box2[3]) - centre_y,
                     centre_y - min(box1[1], box2[1]))
        return math.hypot(half_w, half_h) / upm, half_w / upm, half_h / upm

    ranked = sorted(
        ((reach(a, b)[0], a + b) for a, b in itertools.product(pool, repeat=2)),
        reverse=True,
    )
    print('worst ordered pairs (corner reach per unit fontSize, em):')
    for value, pair in ranked[:6]:
        _, half_w, half_h = reach(pair[0], pair[1])
        print('  %-4s %.5f   half-width %.5f   half-height %.5f'
              % (pair, value, half_w, half_h))
    print()
    print('cornerReachPerFontSize = %.5f   (pair %r)'
          % (ranked[0][0], ranked[0][1]))
    print()

    # The shipped geometry, so the margins in the plan are re-derivable too.
    reach_per_font_size = ranked[0][0]

    def ring_width(scaled_radius):
        return min(max(scaled_radius / 8, 1.5), 3.0)

    def font_size(scaled_radius):
        return max(scaled_radius * 0.72, 11.0)

    print('%-8s %-6s %9s %8s %10s %10s %9s %8s'
          % ('radius', 'scale', 'fontSize', 'ringW', 'innerR', 'reach',
             'margin', '%inner'))
    for radius in (12, 14, 15, 16, 21, 33):
        for scale in (1.0, 1.6):
            scaled = radius * scale
            inner = scaled - ring_width(scaled)
            got = reach_per_font_size * font_size(scaled)
            print('%-8s %-6s %9.3f %8.3f %10.3f %10.3f %9.3f %7.1f%%'
                  % (radius, scale, font_size(scaled), ring_width(scaled),
                     inner, got, inner - got, 100 * (inner - got) / inner))


if __name__ == '__main__':
    _main()
