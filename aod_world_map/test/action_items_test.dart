import 'package:meridian/desktop/action_items.dart';
import 'package:meridian/desktop/notes_model.dart';
import 'package:flutter_test/flutter_test.dart';

MeetingNote _note({String text = '', List<String> said = const []}) => MeetingNote(
      id: '1',
      title: 'Zoom meeting',
      app: 'Zoom',
      startedAt: DateTime(2026, 10, 7, 10),
      text: text,
      segments: [for (var i = 0; i < said.length; i++) NoteSegment(i * 10, said[i])],
    );

void main() {
  test('commitments in the transcript become to-dos', () {
    final items = extractActionItems(_note(said: [
      'Thanks everyone for joining. So I\'ll send the deck to Sarah by Friday.',
      'We need to update the pricing page before launch. Sounds good to me.',
      'Can you book the venue for the offsite? Great.',
    ]));
    expect(items, [
      'Send the deck to Sarah by Friday',
      'Update the pricing page before launch',
      'Book the venue for the offsite',
    ]);
  });

  test('lines marked in your own notes come first', () {
    final items = extractActionItems(_note(
      text: 'Notes from sync\n- [ ] email the contract to legal\nTODO: renew the domain\nsome thought\naction item - draft the agenda',
      said: ['I will review the budget numbers tonight.'],
    ));
    expect(items, [
      'Email the contract to legal',
      'Renew the domain',
      'Draft the agenda',
      'Review the budget numbers tonight',
    ]);
  });

  test('explicit action items in the transcript are picked up', () {
    final items = extractActionItems(_note(said: ['Okay one action item: migrate the old dashboards to the new tool.']));
    expect(items, ['Migrate the old dashboards to the new tool']);
  });

  test('chatter and fragments are skipped, duplicates collapse', () {
    final items = extractActionItems(_note(said: [
      'Let me share my screen. I\'ll be honest with you all.',
      'I will.',
      'We should ship the beta next week. We should ship the beta next week!',
      'Can you hear me okay?',
    ]));
    expect(items, ['Ship the beta next week']);
  });

  test('long items are trimmed and the count is capped', () {
    final long = 'I\'ll ${List.filled(25, 'word').join(' ')}.';
    final items = extractActionItems(_note(said: [long, for (var i = 0; i < 12; i++) 'We need to fix bug number $i today.']));
    expect(items.first.length, lessThanOrEqualTo(91));
    expect(items.first.endsWith('…'), isTrue);
    expect(items, hasLength(8));
  });
}
