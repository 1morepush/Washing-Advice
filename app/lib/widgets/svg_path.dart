import 'dart:ui';

/// Parses SVG path data (the `d` attribute) into a Flutter [Path].
///
/// Supports every path command: `M L H V C S Q T A Z`, absolute and relative,
/// with implicit repetition (`M0 0 10 10` draws a line), compact numbers
/// (`.5`, `-1.2e1`, and `1.5.5` is two numbers) and the compact arc flag form
/// (`a1 1 0 01.5.5`). The vector art for garments and care symbols is stored as
/// path strings rather than as a package dependency or an asset, so this is
/// the whole of the SVG that the app needs.
///
/// Throws [FormatException] for anything malformed: an unknown command, a
/// missing number, or data that does not start with a move.
Path parseSvgPath(String d) {
  final reader = _Reader(d);
  final path = Path();

  var x = 0.0, y = 0.0; // current point
  var startX = 0.0, startY = 0.0; // start of the current subpath
  // Last control point, for S and T reflection. Null when the previous
  // command was not a curve of the matching kind.
  double? cubicX, cubicY, quadX, quadY;

  String? command;
  var first = true;

  reader.skipSeparators();
  while (!reader.atEnd) {
    final c = reader.peekCommand();
    if (c != null) {
      command = c;
      reader.advance();
    } else if (command == null) {
      throw FormatException('Path data must start with a command', d);
    } else if (command == 'z' || command == 'Z') {
      throw FormatException('Unexpected number after close path', d);
    }
    // Otherwise the previous command repeats. A repeated move becomes a line.
    final cmd = command;
    if (first && cmd != 'M' && cmd != 'm') {
      throw FormatException('Path data must start with a move', d);
    }
    first = false;

    final rel = cmd == cmd.toLowerCase();

    switch (cmd.toUpperCase()) {
      case 'M':
        final nx = reader.number() + (rel ? x : 0);
        final ny = reader.number() + (rel ? y : 0);
        path.moveTo(nx, ny);
        x = startX = nx;
        y = startY = ny;
        command = rel ? 'l' : 'L';
        cubicX = cubicY = quadX = quadY = null;
      case 'L':
        final nx = reader.number() + (rel ? x : 0);
        final ny = reader.number() + (rel ? y : 0);
        path.lineTo(nx, ny);
        x = nx;
        y = ny;
        cubicX = cubicY = quadX = quadY = null;
      case 'H':
        final nx = reader.number() + (rel ? x : 0);
        path.lineTo(nx, y);
        x = nx;
        cubicX = cubicY = quadX = quadY = null;
      case 'V':
        final ny = reader.number() + (rel ? y : 0);
        path.lineTo(x, ny);
        y = ny;
        cubicX = cubicY = quadX = quadY = null;
      case 'C':
        final ox = rel ? x : 0.0, oy = rel ? y : 0.0;
        final x1 = reader.number() + ox, y1 = reader.number() + oy;
        final x2 = reader.number() + ox, y2 = reader.number() + oy;
        final nx = reader.number() + ox, ny = reader.number() + oy;
        path.cubicTo(x1, y1, x2, y2, nx, ny);
        cubicX = x2;
        cubicY = y2;
        quadX = quadY = null;
        x = nx;
        y = ny;
      case 'S':
        final ox = rel ? x : 0.0, oy = rel ? y : 0.0;
        final x1 = cubicX == null ? x : 2 * x - cubicX;
        final y1 = cubicY == null ? y : 2 * y - cubicY;
        final x2 = reader.number() + ox, y2 = reader.number() + oy;
        final nx = reader.number() + ox, ny = reader.number() + oy;
        path.cubicTo(x1, y1, x2, y2, nx, ny);
        cubicX = x2;
        cubicY = y2;
        quadX = quadY = null;
        x = nx;
        y = ny;
      case 'Q':
        final ox = rel ? x : 0.0, oy = rel ? y : 0.0;
        final x1 = reader.number() + ox, y1 = reader.number() + oy;
        final nx = reader.number() + ox, ny = reader.number() + oy;
        path.quadraticBezierTo(x1, y1, nx, ny);
        quadX = x1;
        quadY = y1;
        cubicX = cubicY = null;
        x = nx;
        y = ny;
      case 'T':
        final ox = rel ? x : 0.0, oy = rel ? y : 0.0;
        final x1 = quadX == null ? x : 2 * x - quadX;
        final y1 = quadY == null ? y : 2 * y - quadY;
        final nx = reader.number() + ox, ny = reader.number() + oy;
        path.quadraticBezierTo(x1, y1, nx, ny);
        quadX = x1;
        quadY = y1;
        cubicX = cubicY = null;
        x = nx;
        y = ny;
      case 'A':
        final rx = reader.number().abs(), ry = reader.number().abs();
        final rotation = reader.number();
        final large = reader.flag();
        final sweep = reader.flag();
        final nx = reader.number() + (rel ? x : 0);
        final ny = reader.number() + (rel ? y : 0);
        if (rx == 0 || ry == 0) {
          path.lineTo(nx, ny);
        } else {
          path.arcToPoint(
            Offset(nx, ny),
            radius: Radius.elliptical(rx, ry),
            rotation: rotation,
            largeArc: large,
            clockwise: sweep,
          );
        }
        cubicX = cubicY = quadX = quadY = null;
        x = nx;
        y = ny;
      case 'Z':
        path.close();
        x = startX;
        y = startY;
        cubicX = cubicY = quadX = quadY = null;
        // A close takes no numbers; the next token must be a command.
        reader.skipSeparators();
        if (!reader.atEnd && reader.peekCommand() == null) {
          throw FormatException('Unexpected number after close path', d);
        }
      default:
        throw FormatException('Unknown path command "$cmd"', d);
    }
    reader.skipSeparators();
  }
  return path;
}

class _Reader {
  _Reader(this.s);

  final String s;
  int i = 0;

  bool get atEnd => i >= s.length;

  static const _commands = 'MmLlHhVvCcSsQqTtAaZz';

  void skipSeparators() {
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      // space, tab, newline, carriage return, comma
      if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x2C) {
        i++;
      } else {
        break;
      }
    }
  }

  String? peekCommand() {
    final ch = s[i];
    return _commands.contains(ch) ? ch : null;
  }

  void advance() {
    i++;
    skipSeparators();
  }

  /// Reads one arc flag, which is a single `0` or `1` and may be written with
  /// no separator after it.
  bool flag() {
    skipSeparators();
    if (atEnd) throw FormatException('Expected an arc flag', s, i);
    final ch = s[i];
    if (ch != '0' && ch != '1') {
      throw FormatException('Arc flag must be 0 or 1', s, i);
    }
    i++;
    skipSeparators();
    return ch == '1';
  }

  double number() {
    skipSeparators();
    final start = i;
    if (i < s.length && (s[i] == '-' || s[i] == '+')) i++;
    var digits = 0;
    while (i < s.length && _isDigit(s.codeUnitAt(i))) {
      i++;
      digits++;
    }
    if (i < s.length && s[i] == '.') {
      i++;
      while (i < s.length && _isDigit(s.codeUnitAt(i))) {
        i++;
        digits++;
      }
    }
    if (digits == 0) {
      throw FormatException('Expected a number', s, start);
    }
    if (i < s.length && (s[i] == 'e' || s[i] == 'E')) {
      final mark = i;
      i++;
      if (i < s.length && (s[i] == '-' || s[i] == '+')) i++;
      var expDigits = 0;
      while (i < s.length && _isDigit(s.codeUnitAt(i))) {
        i++;
        expDigits++;
      }
      // Not an exponent after all; leave the 'e' for the caller to reject.
      if (expDigits == 0) i = mark;
    }
    final value = double.parse(s.substring(start, i));
    skipSeparators();
    return value;
  }

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
}
