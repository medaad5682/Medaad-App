import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

// ════════════════════════════════════════════════════════════════════════════
//  MASTER SWITCH  (change this ONE line)
//
//    true  → the "Stylus sim" overlay is shown (debug AND release builds)
//    false → nothing is shown, nothing runs
//
//  ⚠️  Set to false before building a release for real users.
// ════════════════════════════════════════════════════════════════════════════
const bool kEnableStylusSimulator = true;

/// Sentences written by buttons 6-8, in block capitals. Edit freely.
/// Supported characters: A-Z 0-9 space . , ! ? - ' : ( )
/// (lowercase is converted to uppercase; other characters are skipped)
const List<String> kStylusSimSentences = <String>[
  'THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG.',
  'PALM REJECTION TEST: 1234567890!',
  'FINGERS MUST NOT SCROLL WHILE I WRITE.',
];

/// Average pen speed while writing, in logical pixels per second.
const double kStylusSimPenSpeed = 320.0;

/// How long the pen hovers (in range, not touching) before it touches down in
/// the "hover then stroke / sentence" buttons. During this time you put your
/// palm / fingers on the screen to check they are ignored.
const int kStylusSimHoverMs = 5000;

/// Injects synthetic *stylus* pointer events into GestureBinding so palm
/// rejection can be tested with no stylus and no mouse. Your real fingers still
/// produce real touch events, so you play the "palm" yourself.
///
/// What the fake pen does like a real one:
///  • enters range (PointerAdded), hovers before touching, hovers between
///    strokes while "lifted", lingers after the last stroke, then leaves range
///  • every stroke is a new pointer: down → ~125 moves/s → up
///  • pressure rises and falls, speed eases in/out, tiny hand tremor
///  • sentences: each letter is a few strokes with pen lifts between them,
///    longer pauses between words and lines, slight slant / wobble per letter
class StylusSimulator extends StatefulWidget {
  const StylusSimulator({super.key});

  @override
  State<StylusSimulator> createState() => _StylusSimulatorState();
}

class _StylusSimulatorState extends State<StylusSimulator> {
  static const int _device = 9001; // arbitrary id, distinct from real touch
  static int _nextPointer = 90000; // real touch ids are small integers
  static const int _dtMs = 8; // ≈125 events per second

  final Stopwatch _clock = Stopwatch()..start();
  final math.Random _rnd = math.Random(3);

  bool _open = true;
  bool _busy = false;
  bool _abort = false;
  String _status = 'idle';
  int _sentence = 0;

  Offset _pos = Offset.zero; // last pen position we reported
  int? _downPointer; // pointer id while the pen tip is touching
  PointerDeviceKind _kind = PointerDeviceKind.stylus;

  Duration get _now => _clock.elapsed;

  @override
  void dispose() {
    _abort = true;
    super.dispose();
  }

  void _send(PointerEvent e) => GestureBinding.instance.handlePointerEvent(e);

  Size get _size => MediaQuery.of(context).size;
  Offset _center() => Offset(_size.width * 0.5, _size.height * 0.5);

  // ───────────────────────── running a test ─────────────────────────

  Future<void> _run(String label, Future<void> Function() body,
      {int countdown = 0}) async {
    if (_busy) return;
    final bool wasOpen = _open;
    setState(() {
      _busy = true;
      _abort = false;
      _open = false; // collapse so the overlay never blocks the page
    });
    try {
      for (var i = countdown; i > 0 && !_abort; i--) {
        if (!mounted) return;
        setState(() => _status = '$label: starts in $i s');
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (_abort || !mounted) return;
      setState(() => _status = '$label: running');
      await WidgetsBinding.instance.endOfFrame;
      if (_abort || !mounted) return;
      await body();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _open = wasOpen;
          _status = _abort ? 'stopped' : 'idle';
        });
      }
    }
  }

  // ───────────────────────── pen playback ─────────────────────────

  /// Plays [strokes] as one pen session: range-in, hover, strokes with
  /// hovering pen-up travel between them, linger, range-out.
  ///
  /// [approachMs] is how long the pen hovers before the first touch-down.
  /// Long values (> 600 ms) make the pen wander above the page first, like a
  /// hand that is deciding where to write.
  Future<void> _perform(List<_Stroke> strokes,
      {PointerDeviceKind kind = PointerDeviceKind.stylus,
      int approachMs = 320}) async {
    if (strokes.isEmpty) return;
    _kind = kind;
    final Offset first = strokes.first.pts.first;
    _pos = first + const Offset(46, -34);
    _send(PointerAddedEvent(
        timeStamp: _now, kind: kind, device: _device, position: _pos));
    try {
      if (approachMs > 600) {
        await _hover(first + const Offset(-26, -16), (approachMs * 0.6).round(),
            arc: 14);
        await _hover(first, (approachMs * 0.4).round(), arc: 4);
      } else if (approachMs > 0) {
        await _hover(first, approachMs);
      }
      for (final _Stroke s in strokes) {
        if (_abort || !mounted) break;
        await _hover(s.pts.first, s.pauseMs); // pen lifted, travelling
        if (_abort || !mounted) break;
        await _play(s);
      }
      if (!_abort && mounted) {
        await _hover(_pos + const Offset(18, -22), 320); // lingers
      }
    } finally {
      final int? id = _downPointer;
      if (id != null) {
        _send(PointerUpEvent(
            timeStamp: _now,
            kind: kind,
            device: _device,
            pointer: id,
            position: _pos));
        _downPointer = null;
      }
      _send(PointerRemovedEvent(
          timeStamp: _now, kind: kind, device: _device, position: _pos));
    }
  }

  /// Stylus in range but not touching, drifting slowly, for [ms].
  Future<void> _hoverOnly(Offset at, int ms) async {
    _kind = PointerDeviceKind.stylus;
    _pos = at;
    _send(PointerAddedEvent(
        timeStamp: _now, kind: _kind, device: _device, position: at));
    try {
      await _hover(at + const Offset(60, 18), ms, arc: 0);
    } finally {
      _send(PointerRemovedEvent(
          timeStamp: _now, kind: _kind, device: _device, position: _pos));
    }
  }

  /// Hover events moving from the current position to [to] over [ms].
  Future<void> _hover(Offset to, int ms, {double arc = 5}) async {
    final Offset from = _pos;
    final int steps = math.max(1, (ms / _dtMs).round());
    final Stopwatch sw = Stopwatch()..start();
    for (var k = 1; k <= steps; k++) {
      if (_abort || !mounted) return;
      final double u = k / steps;
      final Offset p = Offset.lerp(from, to, u)! +
          Offset(0, -math.sin(math.pi * u) * arc);
      _send(PointerHoverEvent(
          timeStamp: _now,
          kind: _kind,
          device: _device,
          position: p,
          delta: p - _pos));
      _pos = p;
      final int wait = k * _dtMs - sw.elapsedMilliseconds;
      if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
    }
  }

  /// One pen-down stroke: down → moves paced over s.durMs → up.
  Future<void> _play(_Stroke s) async {
    List<Offset> pts = s.pts;
    if (pts.length < 2) {
      pts = <Offset>[pts.first, pts.first + const Offset(0.6, 0)];
    }
    final List<double> cum = <double>[0.0];
    for (var i = 1; i < pts.length; i++) {
      cum.add(cum.last + (pts[i] - pts[i - 1]).distance);
    }
    final double total = cum.last;

    final int id = _nextPointer++;
    _downPointer = id;
    _pos = pts.first;
    _send(PointerDownEvent(
        timeStamp: _now,
        kind: _kind,
        device: _device,
        pointer: id,
        position: _pos,
        pressure: _pressure(0),
        pressureMin: 0,
        pressureMax: 1));

    final int steps = math.max(2, (s.durMs / _dtMs).round());
    final Stopwatch sw = Stopwatch()..start();
    var seg = 0;
    for (var k = 1; k <= steps; k++) {
      if (_abort || !mounted) break;
      final double u = k / steps;
      final double target = total * _ease(u);
      while (seg < cum.length - 2 && cum[seg + 1] < target) {
        seg++;
      }
      final double len = cum[seg + 1] - cum[seg];
      final double t =
          len <= 0 ? 1.0 : ((target - cum[seg]) / len).clamp(0.0, 1.0).toDouble();
      Offset p = Offset.lerp(pts[seg], pts[seg + 1], t)!;
      if (k < steps) {
        // hand tremor
        p += Offset((_rnd.nextDouble() - 0.5) * 0.5,
            (_rnd.nextDouble() - 0.5) * 0.5);
      }
      _send(PointerMoveEvent(
          timeStamp: _now,
          kind: _kind,
          device: _device,
          pointer: id,
          position: p,
          delta: p - _pos,
          pressure: _pressure(u),
          pressureMin: 0,
          pressureMax: 1));
      _pos = p;
      final int wait = k * _dtMs - sw.elapsedMilliseconds;
      if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
    }
    _send(PointerUpEvent(
        timeStamp: _now,
        kind: _kind,
        device: _device,
        pointer: id,
        position: _pos));
    _downPointer = null;
  }

  /// Slow at the ends of a stroke, fastest in the middle.
  double _ease(double u) {
    final double smooth = u * u * (3 - 2 * u);
    return 0.6 * u + 0.4 * smooth;
  }

  /// Pressure rises, peaks mid-stroke, falls.
  double _pressure(double u) {
    final double x = u.clamp(0.04, 0.96).toDouble();
    return 0.22 + 0.55 * math.pow(math.sin(math.pi * x), 0.6).toDouble();
  }

  // ───────────────────────── stroke sources ─────────────────────────

  /// The test wave: starts a bit left of centre, 260 px wide.
  List<Offset> _wave() {
    final Offset a = Offset(_size.width * 0.5 - 130, _size.height * 0.5);
    const int n = 60;
    return <Offset>[
      for (var i = 0; i <= n; i++)
        a +
            Offset(i / n * 260, math.sin(i / n * math.pi * 3) * 40),
    ];
  }

  /// Turns [text] into pen strokes laid out in the upper-middle of the screen,
  /// wrapped to the screen width.
  List<_Stroke> _layoutText(String text) {
    final Size size = _size;
    final double unit =
        2.4 * (size.shortestSide / 390).clamp(0.8, 2.0).toDouble();
    const double gap = 1.6; // between letters (glyph units)
    const double spaceW = 3.2; // extra space between words
    const double lineH = 15.0; // line pitch (glyph units)
    final Offset origin = Offset(size.width * 0.08, size.height * 0.26);
    final double maxW = size.width * 0.84 / unit;
    final int maxLines = math.max(
        1, ((size.height * 0.80 - origin.dy) / (lineH * unit)).floor());
    final math.Random rnd = math.Random(7);

    double adv(String ch) => (_font[ch]?.w ?? 0.0) + gap;

    final List<String> words = text
        .toUpperCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    final List<_Stroke> out = <_Stroke>[];
    var line = 0;
    var x = 0.0;
    var firstEver = true;
    var firstOfLine = true;

    for (final String word in words) {
      final List<String> chars =
          word.split('').where((c) => _font.containsKey(c)).toList();
      if (chars.isEmpty) continue;
      final double ww = chars.fold<double>(0.0, (s, c) => s + adv(c)) - gap;
      if (x > 0 && x + ww > maxW) {
        line++;
        x = 0;
        firstOfLine = true;
      }
      if (line >= maxLines) break;
      var firstOfWord = true;

      for (final String c in chars) {
        final _G g = _font[c]!;
        final List<List<Offset>> strokes = _glyphStrokes(g);
        // per-letter handwriting variation
        final double rot = (rnd.nextDouble() - 0.5) * 0.10; // ±0.05 rad
        final double dy = (rnd.nextDouble() - 0.5) * 0.9; // baseline wobble
        final double sc = 0.95 + rnd.nextDouble() * 0.10;
        const double slant = 0.14;
        final double cx = g.w / 2;
        const double cy = 5.0;

        for (var si = 0; si < strokes.length; si++) {
          final List<Offset> pts = <Offset>[];
          for (final Offset p in strokes[si]) {
            final double gx0 = (p.dx - cx) * sc;
            final double gy0 = (p.dy - cy) * sc;
            final double rx = gx0 * math.cos(rot) - gy0 * math.sin(rot);
            final double ry = gx0 * math.sin(rot) + gy0 * math.cos(rot);
            final double gx = rx + cx + (ry + cy) * slant;
            final double gy = ry + cy + dy;
            pts.add(Offset(
              origin.dx + (x + gx) * unit,
              origin.dy + line * lineH * unit + (10 - gy) * unit,
            ));
          }

          int pause;
          if (si > 0) {
            pause = 10 + rnd.nextInt(25); // lift inside a letter
          } else if (firstEver) {
            pause = 0;
          } else if (firstOfLine) {
            pause = 350 + rnd.nextInt(200); // new line
          } else if (firstOfWord) {
            pause = 140 + rnd.nextInt(120); // new word
          } else {
            pause = 25 + rnd.nextInt(45); // next letter
          }

          double len = 0;
          for (var i = 1; i < pts.length; i++) {
            len += (pts[i] - pts[i - 1]).distance;
          }
          final double speed = kStylusSimPenSpeed * (0.8 + rnd.nextDouble() * 0.4);
          out.add(_Stroke(pts, pause, math.max(60, (len / speed * 1000).round())));
          firstEver = false;
          firstOfLine = false;
          firstOfWord = false;
        }
        x += g.w + gap;
      }
      x += spaceW;
    }
    return out;
  }

  // ───────────────────────── UI ─────────────────────────

  Widget _btn(String label, VoidCallback onTap) => TextButton(
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.centerLeft,
        ),
        onPressed: _busy ? null : onTap,
        child: Text(label, style: const TextStyle(fontSize: 12)),
      );

  void _nextSentence() {
    if (mounted) {
      setState(() => _sentence = (_sentence + 1) % kStylusSimSentences.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kEnableStylusSimulator) return const SizedBox.shrink();
    final int n = _sentence + 1;
    return Material(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _open = !_open),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text('Stylus sim: $_status',
                        style: const TextStyle(
                            color: Colors.amber, fontSize: 11)),
                  ),
                ),
                if (_busy) ...[
                  const SizedBox(width: 10),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _abort = true,
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Text('■ STOP',
                          style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ],
            ),
            if (_open) ...[
              _btn(
                '1  Stylus stroke (fast)',
                () => _run(
                    'stylus stroke',
                    () => _perform(<_Stroke>[_Stroke(_wave(), 0, 800)])),
              ),
              _btn(
                '2  Slow stroke 6 s: add finger/palm',
                () => _run(
                    'slow stroke',
                    () => _perform(<_Stroke>[_Stroke(_wave(), 0, 6000)])),
              ),
              _btn(
                '3  Palm first (4 s), then stroke',
                () => _run(
                    'palm first',
                    () => _perform(<_Stroke>[_Stroke(_wave(), 0, 1500)]),
                    countdown: 4),
              ),
              _btn(
                '4  Hover 6 s: swipe/pinch with fingers',
                () => _run('hover', () => _hoverOnly(_center(), 6000)),
              ),
              _btn(
                '5  Eraser end (inverted stylus)',
                () => _run(
                    'eraser end',
                    () => _perform(<_Stroke>[_Stroke(_wave(), 0, 800)],
                        kind: PointerDeviceKind.invertedStylus)),
              ),
              _btn(
                '6  Write sentence #$n',
                () => _run('sentence #$n', () async {
                  await _perform(_layoutText(kStylusSimSentences[_sentence]));
                  _nextSentence();
                }),
              ),
              _btn(
                '7  Write paragraph (all sentences)',
                () => _run(
                    'paragraph',
                    () => _perform(
                        _layoutText(kStylusSimSentences.join(' ')))),
              ),
              _btn(
                '8  Palm first (4 s), then sentence #$n',
                () => _run('palm + sentence #$n',
                    () => _perform(_layoutText(kStylusSimSentences[_sentence])),
                    countdown: 4),
              ),
              _btn(
                '9  Hover ${kStylusSimHoverMs ~/ 1000} s, then stylus stroke',
                () => _run(
                    'hover → stroke',
                    () => _perform(<_Stroke>[_Stroke(_wave(), 0, 1200)],
                        approachMs: kStylusSimHoverMs)),
              ),
              _btn(
                '10  Hover ${kStylusSimHoverMs ~/ 1000} s, then sentence #$n',
                () => _run('hover → sentence #$n', () async {
                  await _perform(_layoutText(kStylusSimSentences[_sentence]),
                      approachMs: kStylusSimHoverMs);
                  _nextSentence();
                }),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════ stroke data ═══════════════════════════

class _Stroke {
  _Stroke(this.pts, this.pauseMs, this.durMs);

  final List<Offset> pts; // screen coordinates
  final int pauseMs; // pen-up time before this stroke
  final int durMs; // how long the pen is down
}

/// One drawn piece of a glyph. Points are x0,y0,x1,y1,… in glyph units
/// (x → right, y → up, baseline 0, capital height 10).
class _S {
  const _S(this.p, {this.smooth = false, this.cont = false});

  final List<double> p;

  /// Round the polyline with a Catmull-Rom spline (for curves).
  final bool smooth;

  /// Continue the previous stroke without lifting the pen.
  final bool cont;
}

class _G {
  const _G(this.w, this.s);

  final double w; // advance width in glyph units
  final List<_S> s;
}

List<List<Offset>> _glyphStrokes(_G g) {
  final List<List<Offset>> out = <List<Offset>>[];
  for (final _S s in g.s) {
    final List<Offset> pts = <Offset>[];
    for (var i = 0; i + 1 < s.p.length; i += 2) {
      pts.add(Offset(s.p[i], s.p[i + 1]));
    }
    final List<Offset> dense = s.smooth ? _catmullRom(pts) : pts;
    if (s.cont && out.isNotEmpty) {
      out.last.addAll(dense.skip(1));
    } else {
      out.add(List<Offset>.of(dense));
    }
  }
  return out;
}

List<Offset> _catmullRom(List<Offset> p, {int samples = 6}) {
  if (p.length < 3) return p;
  final List<Offset> out = <Offset>[p.first];
  for (var i = 0; i < p.length - 1; i++) {
    final Offset p0 = i == 0 ? p[i] : p[i - 1];
    final Offset p1 = p[i];
    final Offset p2 = p[i + 1];
    final Offset p3 = i + 2 < p.length ? p[i + 2] : p[i + 1];
    for (var s = 1; s <= samples; s++) {
      final double t = s / samples;
      final double t2 = t * t;
      final double t3 = t2 * t;
      out.add((p1 * 2.0 +
              (p2 - p0) * t +
              (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * t2 +
              (p1 * 3.0 - p0 - p2 * 3.0 + p3) * t3) *
          0.5);
    }
  }
  return out;
}

const Map<String, _G> _font = <String, _G>{
  'A': _G(6, [
    _S([0, 0, 3, 10, 6, 0]),
    _S([1.2, 3.6, 4.8, 3.6]),
  ]),
  'B': _G(5.6, [
    _S([0, 0, 0, 10]),
    _S([0, 10, 3.6, 10, 5.2, 8.9, 5.2, 6.6, 3.6, 5.3, 0, 5.3], smooth: true),
    _S([0, 5.3, 3.8, 5.3, 5.6, 4.1, 5.6, 1.4, 3.8, 0, 0, 0], smooth: true),
  ]),
  'C': _G(5.6, [
    _S([5.6, 8.2, 4.4, 9.8, 2.8, 10, 1, 9, 0, 6.5, 0, 3.5, 1, 1, 2.8, 0, 4.4, 0.2, 5.6, 1.8], smooth: true),
  ]),
  'D': _G(5.8, [
    _S([0, 0, 0, 10]),
    _S([0, 10, 2.8, 10, 5, 8.4, 5.8, 5, 5, 1.6, 2.8, 0, 0, 0], smooth: true),
  ]),
  'E': _G(5.5, [
    _S([5.5, 10, 0, 10, 0, 0, 5.5, 0]),
    _S([0, 5.2, 4.4, 5.2]),
  ]),
  'F': _G(5.5, [
    _S([5.5, 10, 0, 10, 0, 0]),
    _S([0, 5.2, 4.4, 5.2]),
  ]),
  'G': _G(5.8, [
    _S([5.6, 8.2, 4.4, 9.8, 2.8, 10, 1, 9, 0, 6.5, 0, 3.5, 1, 1, 2.8, 0, 4.6, 0.4, 5.8, 2, 5.8, 4.5], smooth: true),
    _S([5.8, 4.5, 3.4, 4.5], cont: true),
  ]),
  'H': _G(6, [
    _S([0, 0, 0, 10]),
    _S([6, 0, 6, 10]),
    _S([0, 5.2, 6, 5.2]),
  ]),
  'I': _G(2, [
    _S([1, 0, 1, 10]),
  ]),
  'J': _G(5, [
    _S([5, 10, 5, 4, 4.6, 1.6, 3.2, 0.1, 1.6, 0.2, 0.5, 1.6], smooth: true),
  ]),
  'K': _G(5.8, [
    _S([0, 0, 0, 10]),
    _S([5.6, 10, 0.2, 4.6]),
    _S([1.6, 5.9, 5.8, 0]),
  ]),
  'L': _G(5, [
    _S([0, 10, 0, 0, 5, 0]),
  ]),
  'M': _G(6.4, [
    _S([0, 0, 0, 10, 3.2, 3.5, 6.4, 10, 6.4, 0]),
  ]),
  'N': _G(6, [
    _S([0, 0, 0, 10, 6, 0, 6, 10]),
  ]),
  'O': _G(6, [
    _S([3, 10, 1, 9, 0, 6.5, 0, 3.5, 1, 1, 3, 0, 5, 1, 6, 3.5, 6, 6.5, 5, 9, 3, 10, 1, 9], smooth: true),
  ]),
  'P': _G(5.4, [
    _S([0, 0, 0, 10]),
    _S([0, 10, 3.6, 10, 5.4, 8.8, 5.4, 6.6, 3.6, 5.2, 0, 5.2], smooth: true),
  ]),
  'Q': _G(6.2, [
    _S([3, 10, 1, 9, 0, 6.5, 0, 3.5, 1, 1, 3, 0, 5, 1, 6, 3.5, 6, 6.5, 5, 9, 3, 10, 1, 9], smooth: true),
    _S([3.6, 2.4, 6.2, -1]),
  ]),
  'R': _G(5.8, [
    _S([0, 0, 0, 10]),
    _S([0, 10, 3.6, 10, 5.4, 8.8, 5.4, 6.6, 3.6, 5.2, 0, 5.2], smooth: true),
    _S([2.8, 5.2, 5.8, 0]),
  ]),
  'S': _G(5.4, [
    _S([5.4, 8.6, 4, 9.9, 2.2, 10, 0.6, 9, 0.4, 7.2, 1.6, 5.9, 3.5, 5.1, 5.2, 4.1, 5.6, 2.6, 4.6, 0.9, 3, 0, 1.2, 0.2, 0, 1.4], smooth: true),
  ]),
  'T': _G(6, [
    _S([0, 10, 6, 10]),
    _S([3, 10, 3, 0]),
  ]),
  'U': _G(6, [
    _S([0, 10, 0, 3, 0.8, 0.9, 3, 0, 5.2, 0.9, 6, 3, 6, 10], smooth: true),
  ]),
  'V': _G(6, [
    _S([0, 10, 3, 0, 6, 10]),
  ]),
  'W': _G(6.4, [
    _S([0, 10, 1.6, 0, 3.2, 6.5, 4.8, 0, 6.4, 10]),
  ]),
  'X': _G(6, [
    _S([0, 10, 6, 0]),
    _S([6, 10, 0, 0]),
  ]),
  'Y': _G(6, [
    _S([0, 10, 3, 5.2, 6, 10]),
    _S([3, 5.2, 3, 0]),
  ]),
  'Z': _G(6, [
    _S([0, 10, 6, 10, 0, 0, 6, 0]),
  ]),
  '0': _G(5, [
    _S([2.5, 10, 0.8, 9, 0, 6.5, 0, 3.5, 0.8, 1, 2.5, 0, 4.2, 1, 5, 3.5, 5, 6.5, 4.2, 9, 2.5, 10, 0.8, 9], smooth: true),
  ]),
  '1': _G(3, [
    _S([0.2, 8, 2.5, 10, 2.5, 0]),
  ]),
  '2': _G(5.2, [
    _S([0.2, 7.8, 0.9, 9.4, 2.6, 10, 4.3, 9.4, 5, 7.6, 4.3, 5.8, 0, 0], smooth: true),
    _S([0, 0, 5.2, 0], cont: true),
  ]),
  '3': _G(5.2, [
    _S([0.2, 8.6, 1.2, 9.8, 2.8, 10, 4.4, 9.2, 4.6, 7.4, 3.4, 5.9, 2, 5.4, 3.6, 5, 5, 3.8, 5.2, 2, 4.2, 0.6, 2.6, 0, 1, 0.3, 0, 1.4], smooth: true),
  ]),
  '4': _G(5.5, [
    _S([4, 0, 4, 10, 0, 3.2, 5.5, 3.2]),
  ]),
  '5': _G(5.2, [
    _S([5, 10, 0.8, 10, 0.4, 5.6]),
    _S([0.4, 5.6, 1.8, 6.2, 3.4, 6.1, 4.8, 4.9, 5.2, 3, 4.4, 1, 2.8, 0, 1.2, 0.3, 0, 1.5], smooth: true, cont: true),
  ]),
  '6': _G(5, [
    _S([4.6, 9.2, 3.2, 10, 1.6, 9, 0.4, 6.5, 0, 3.5, 0.6, 1, 2.4, 0, 4.4, 1, 5, 3, 4.2, 5, 2.4, 5.6, 0.8, 4.8, 0.1, 3.4], smooth: true),
  ]),
  '7': _G(5.4, [
    _S([0, 10, 5.4, 10, 2, 0]),
  ]),
  '8': _G(5.2, [
    _S([2.6, 5.3, 1, 6.2, 0.6, 8, 1.4, 9.6, 2.6, 10, 3.8, 9.6, 4.6, 8, 4.2, 6.2, 2.6, 5.3, 0.8, 4.2, 0, 2.4, 0.6, 0.7, 2.6, 0, 4.6, 0.7, 5.2, 2.4, 4.4, 4.2, 2.6, 5.3], smooth: true),
  ]),
  '9': _G(5, [
    _S([0.4, 0.8, 1.8, 0, 3.4, 1, 4.6, 3.5, 5, 6.5, 4.4, 9, 2.6, 10, 0.6, 9, 0, 7, 0.8, 5, 2.6, 4.4, 4.2, 5.2, 4.9, 6.6], smooth: true),
  ]),
  '.': _G(1.4, [
    _S([0.7, 0.1, 0.8, 0.7]),
  ]),
  ',': _G(1.4, [
    _S([1, 0.8, 0.8, 0, 0.3, -1.4]),
  ]),
  '!': _G(2, [
    _S([1, 10, 1, 3]),
    _S([1, 0.1, 1, 0.7]),
  ]),
  '?': _G(5, [
    _S([0.3, 8.2, 1, 9.7, 2.6, 10, 4.2, 9.3, 4.5, 7.6, 3.6, 6.2, 2.4, 5.2, 2.3, 3.6], smooth: true),
    _S([2.3, 0.1, 2.3, 0.7]),
  ]),
  '-': _G(3.6, [
    _S([0.3, 4.6, 3.3, 4.6]),
  ]),
  "'": _G(1.4, [
    _S([1, 10, 0.8, 7.6]),
  ]),
  ':': _G(2, [
    _S([1, 6.2, 1, 6.8]),
    _S([1, 0.1, 1, 0.7]),
  ]),
  '(': _G(3.4, [
    _S([3, 10, 1.2, 7.5, 0.8, 5, 1.2, 2.5, 3, 0], smooth: true),
  ]),
  ')': _G(3.4, [
    _S([0.4, 10, 2.2, 7.5, 2.6, 5, 2.2, 2.5, 0.4, 0], smooth: true),
  ]),
};
