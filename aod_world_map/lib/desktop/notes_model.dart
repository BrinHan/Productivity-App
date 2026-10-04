class NoteSegment {
  const NoteSegment(this.at, this.text);
  final int at; // seconds from the start of the recording
  final String text;

  Map<String, dynamic> toJson() => {'at': at, 'text': text};

  static NoteSegment fromJson(Map<String, dynamic> j) =>
      NoteSegment((j['at'] as num?)?.toInt() ?? 0, (j['text'] as String?) ?? '');
}

class MeetingNote {
  MeetingNote({
    required this.id,
    required this.title,
    required this.app,
    required this.startedAt,
    this.endedAt,
    List<NoteSegment>? segments,
    this.text = '',
  }) : segments = segments ?? [];

  final String id;
  String title;
  final String app;
  final DateTime startedAt;
  DateTime? endedAt;
  final List<NoteSegment> segments;
  String text; // the user's own notes

  Duration get length => (endedAt ?? DateTime.now()).difference(startedAt);
  String get transcript => segments.map((s) => s.text).join(' ');

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'app': app,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt?.toIso8601String(),
        'text': text,
        'segments': [for (final s in segments) s.toJson()],
      };

  static MeetingNote fromJson(Map<String, dynamic> j) => MeetingNote(
        id: (j['id'] as String?) ?? DateTime.now().microsecondsSinceEpoch.toString(),
        title: (j['title'] as String?) ?? 'Meeting',
        app: (j['app'] as String?) ?? '',
        startedAt: DateTime.tryParse((j['startedAt'] as String?) ?? '') ?? DateTime.now(),
        endedAt: DateTime.tryParse((j['endedAt'] as String?) ?? ''),
        text: (j['text'] as String?) ?? '',
        segments: [
          for (final s in ((j['segments'] as List?) ?? const []))
            if (s is Map<String, dynamic>) NoteSegment.fromJson(s),
        ],
      );
}
