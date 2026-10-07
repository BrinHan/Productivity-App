import 'dart:io';

import 'package:aod_world_map/desktop/island_controller.dart';
import 'package:aod_world_map/desktop/island_live.dart';
import 'package:aod_world_map/desktop/notes_model.dart';
import 'package:aod_world_map/desktop/planner_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late PlannerModel p;
  late IslandController c;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('island_test');
    p = PlannerModel(file: File('${dir.path}${Platform.pathSeparator}planner.json'));
    c = IslandController()..planner = p;
  });

  // Ends the session and lets the planner's save timer fire, so no timer
  // is left pending when the test ends.
  Future<void> settle(WidgetTester tester) async {
    p.resetFocus();
    c.reset();
    await tester.pump(const Duration(seconds: 2));
    c.dispose();
    p.dispose();
    dir.deleteSync(recursive: true);
  }

  testWidgets('a focus session stays on the island while the cursor is away', (tester) async {
    expect(c.state, IslandState.hidden);
    p.startFocus();
    expect(c.state, IslandState.focus);

    c.setNear(true);
    c.setNear(false);
    await tester.pump(const Duration(seconds: 1));
    expect(c.state, IslandState.focus, reason: 'moving away does not hide it');

    c.open(c.restingPage);
    expect(c.page, IslandPage.today);
    c.close();
    expect(c.state, IslandState.focus);

    p.pauseFocus();
    expect(c.state, IslandState.focus, reason: 'a paused session is still shown');
    p.resetFocus();
    expect(c.state, IslandState.hidden);
    await settle(tester);
  });

  testWidgets('with the cursor near, ending a session leaves the idle pill', (tester) async {
    c.setNear(true);
    await tester.pump(IslandController.kRevealDwell + const Duration(milliseconds: 50));
    expect(c.state, IslandState.idle);
    p.startFocus();
    expect(c.state, IslandState.focus);
    p.completeFocus();
    expect(c.state, IslandState.idle);
    await settle(tester);
  });

  testWidgets('quiet in Chrome folds the focus pill into the notch', (tester) async {
    p.startFocus();
    c.setChromeMode(true);
    expect(c.state, IslandState.notch);
    c.setChromeMode(false);
    expect(c.state, IslandState.focus);
    await settle(tester);
  });

  testWidgets('a music preview hands back to the focus pill', (tester) async {
    p.startFocus();
    c.setNowPlaying(const NowPlaying('Song', 'Artist', true));
    expect(c.state, IslandState.music);
    await tester.pump(const Duration(seconds: 7));
    expect(c.state, IslandState.focus);
    await settle(tester);
  });

  testWidgets('after a call the island offers its to-dos', (tester) async {
    var opened = false;
    c.openNotes = () => opened = true;
    final note = MeetingNote(
      id: 'n',
      title: 'Zoom meeting',
      app: 'Zoom',
      startedAt: DateTime(2026, 10, 7),
      segments: const [NoteSegment(0, "I'll send the deck to Sarah. We need to fix the login bug.")],
      taken: ['Fix the login bug'],
    );
    c.offerActions(note);
    expect(c.state, IslandState.actions);
    expect(c.actionOffer!.items, ['Send the deck to Sarah'], reason: 'items already added are left out');

    c.reviewActions();
    expect(opened, isTrue);
    expect(c.state, IslandState.hidden);

    c.offerActions(note);
    await tester.pump(const Duration(seconds: 31));
    expect(c.state, IslandState.hidden, reason: 'the offer times out');

    c.offerActions(MeetingNote(id: 'm', title: 'Meet', app: 'Meet', startedAt: DateTime(2026)));
    expect(c.state, IslandState.hidden, reason: 'nothing found, nothing offered');
    await settle(tester);
  });

  testWidgets('the focus pill shows the task and time, and its buttons work', (tester) async {
    final task = p.add(DateTime.now(), 'Write the quarterly report');
    p.pickFocusTask(task);
    p.startFocus();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: SizedBox(width: 340, height: 60, child: IslandFocusContent(planner: p))),
      ),
    ));
    expect(find.text('Write the quarterly report'), findsWidgets); // the marquee draws a second copy to scroll
    expect(find.text('Focusing'), findsOneWidget);
    expect(find.text('25:00'), findsOneWidget);

    // Time left is read off the wall clock (so the island and the planner
    // agree), which the test's fake time doesn't move; it still ticks.
    await tester.pump(const Duration(seconds: 3));
    expect(find.textContaining(RegExp(r'^2[45]:\d\d$')), findsOneWidget);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();
    expect(p.focusRunning, isFalse);
    expect(find.text('Paused'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget, reason: 'stop shows while paused');

    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pump();
    expect(task.done, isTrue);
    expect(p.focusActive, isFalse);
    await settle(tester);
  });
}
