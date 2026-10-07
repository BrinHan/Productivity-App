import 'notes_model.dart';

/// Pulls likely to-dos out of a meeting note, on this computer: lines you
/// marked in your own notes ("[ ] ...", "todo ...", "action: ..."), then
/// sentences in the transcript where someone commits to or asks for
/// something ("I'll send...", "we need to...", "can you..."). It reads
/// patterns, not meaning, so it suggests and you pick.
List<String> extractActionItems(MeetingNote note, {int max = 8}) {
  final out = <String>[];
  final seen = <String>{};
  void add(String raw) {
    final s = _tidy(raw);
    final key = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '');
    if (s.split(' ').length < 2 || !seen.add(key)) return;
    out.add(s);
  }

  for (final line in note.text.split('\n')) {
    final m = _marked.firstMatch(line);
    if (m != null) add(line.substring(m.end));
  }
  for (final s in _sentences(note.transcript)) {
    if (out.length >= max) break;
    final words = s.split(' ').length;
    if (words < 4 || words > 30 || _chatter.hasMatch(s)) continue;
    final lead = _commit.firstMatch(s);
    if (lead != null) {
      add(s.substring(lead.end));
    } else if (_explicit.hasMatch(s)) {
      add(s.replaceFirst(_explicit, ''));
    }
  }
  return out.take(max).toList();
}

/// A line you marked as a to-do: a checkbox, or a "todo"/"action" label.
final _marked = RegExp(
  r'^\s*(?:[-*•]\s*)?(?:\[\s?\]|todo\b|to do\b|to-do\b|action(?: item)?\b|ai\b|next step\b|follow[ -]up\b)\s*[:\-–]?\s*',
  caseSensitive: false,
);

/// "So I'll ...", "we need to ...", "can you ...": the part after it is the to-do.
final _commit = RegExp(
  r"^(?:(?:so|and|okay|ok|yeah|yes|um|uh|alright|all right|right|then)[, ]+)*"
  r"(?:i'll|i will|i'm going to|i am going to|i need to|i have to|i can|"
  r"we'll|we will|we need to|we should|we have to|we're going to|"
  r"let's|let us|can you|could you|would you|will you|please|you need to|you should|"
  r"someone needs to|somebody needs to)\s+",
  caseSensitive: false,
);

/// A sentence that says outright it is a to-do.
final _explicit = RegExp(
  r'^.*?\b(?:action item|to-do|todo|follow up on|follow-up on|next step is to|next steps are to)\b[:,]?\s*',
  caseSensitive: false,
);

/// Things people say that sound like commitments but aren't.
final _chatter = RegExp(
  r"\b(?:share my screen|be honest|be right back|let you go|let you know|talk to you|see you|"
  r"get started|kick off|go ahead|hear me|see my screen|wrap up|jump in|take a look at this)\b",
  caseSensitive: false,
);

Iterable<String> _sentences(String text) =>
    text.split(RegExp(r'(?<=[.!?])\s+')).map((s) => s.trim()).where((s) => s.isNotEmpty);

/// Capitalised, no trailing punctuation, at most 90 characters.
String _tidy(String raw) {
  var s = raw.trim().replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'[.!?,;:]+$'), '');
  if (s.isEmpty) return s;
  s = s[0].toUpperCase() + s.substring(1);
  if (s.length > 90) {
    final cut = s.lastIndexOf(' ', 88);
    s = '${s.substring(0, cut > 40 ? cut : 88)}…';
  }
  return s;
}
