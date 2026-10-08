import 'package:meridian/desktop/agenda_service.dart';
import 'package:meridian/desktop/island_extras.dart';
import 'package:meridian/desktop/island_services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseCapture', () {
    test('a plain line is a 30 minute task for today', () {
      final p = parseCapture('  buy milk ');
      expect(p.title, 'buy milk');
      expect(p.minutes, 30);
      expect(p.days, 0);
    });

    test('a length and a day come out of the title', () {
      final p = parseCapture('email Sam 15m tomorrow');
      expect(p.title, 'email Sam');
      expect(p.minutes, 15);
      expect(p.days, 1);
    });

    test('hours count, and words that only start with a number stay', () {
      final p = parseCapture('read 2h chapter 3');
      expect(p.title, 'read chapter 3');
      expect(p.minutes, 120);
      expect(parseCapture('ship v2m release').title, 'ship v2m release');
    });
  });

  group('joinLink', () {
    test('finds Zoom, Meet and Teams links in event text', () {
      expect(joinLink('Join: https://us02web.zoom.us/j/123456789?pwd=abc thanks'),
          'https://us02web.zoom.us/j/123456789?pwd=abc');
      expect(joinLink('https://meet.google.com/abc-defg-hij'), 'https://meet.google.com/abc-defg-hij');
      expect(joinLink('<https://teams.microsoft.com/l/meetup-join/19%3ameeting_x>'),
          'https://teams.microsoft.com/l/meetup-join/19%3ameeting_x');
      expect(meetingAppOf('https://meet.google.com/abc-defg-hij'), 'Meet');
    });

    test('ignores other links', () {
      expect(joinLink('Room 4, see https://example.com/agenda'), '');
    });
  });

  test('the timer counts down, pauses and rings once', () async {
    final m = TimerModel()..setPick(const Duration(milliseconds: 1200));
    var rang = 0;
    m.onDone = () => rang++;
    m.start();
    expect(m.running, isTrue);
    m.togglePause();
    final paused = m.remaining;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(m.remaining, paused);
    m.togglePause();
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    expect(rang, 1);
    expect(m.running, isFalse);
    m.dispose();
  });

  test('Pip dresses for the weather and the hour', () {
    Weather w(int code, double feels) => Weather(
          place: '',
          temp: feels,
          feels: feels,
          code: code,
          day: true,
          hi: feels,
          lo: feels,
          sunrise: DateTime(2026, 10, 7, 7, 10),
          sunset: DateTime(2026, 10, 7, 18, 40),
          at: DateTime(2026, 10, 7),
        );
    final noon = DateTime(2026, 10, 7, 12), late = DateTime(2026, 10, 7, 22);
    expect(lookFor(w(0, 20), noon), const PipLook(sky: PipSky.clear));
    expect(lookFor(w(63, 20), noon).sky, PipSky.rain);
    expect(lookFor(w(73, -2), noon), const PipLook(sky: PipSky.snow, cold: true));
    expect(lookFor(w(0, 20), late).night, isTrue);
    expect(lookFor(null, late), const PipLook(night: true));
  });
}
