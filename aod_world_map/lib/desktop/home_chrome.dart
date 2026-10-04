part of 'home_page.dart';

class _TitleBar extends StatelessWidget {
  const _TitleBar({
    required this.t,
    required this.shell,
    required this.sidebarOpen,
    required this.onToggleSidebar,
    required this.notes,
    required this.onOpenNotes,
  });
  final _T t;
  final ShellController shell;
  final bool sidebarOpen;
  final VoidCallback onToggleSidebar;
  final NotesService notes;
  final VoidCallback onOpenNotes;

  @override
  Widget build(BuildContext context) => DragToMoveArea(
        child: Container(
          height: 40,
          padding: const EdgeInsets.only(left: 8, right: 6),
          decoration: BoxDecoration(
            color: t.side,
            border: Border(bottom: BorderSide(color: t.line)),
          ),
          child: Row(children: [
            _WinBtn(t, Icons.view_sidebar_outlined, sidebarOpen ? 'Hide sidebar (Ctrl+B)' : 'Show sidebar (Ctrl+B)',
                onToggleSidebar),
            if (notes.recording) ...[
              const SizedBox(width: 8),
              _RecPill(t: t, notes: notes, onTap: onOpenNotes),
            ],
            const Spacer(),
            _WinBtn(t, Icons.public, 'Screensaver map', shell.showMap),
            _WinBtn(t, Icons.picture_in_picture_alt_outlined, 'Minimize to island', () => shell.enterIsland()),
            _WinBtn(t, Icons.crop_square_rounded, 'Maximize', () => shell.toggleMaximize()),
            _WinBtn(t, Icons.close_rounded, 'Quit', () => shell.quit()),
          ]),
        ),
      );
}

class _WinBtn extends StatelessWidget {
  const _WinBtn(this.t, this.icon, this.tip, this.onTap);
  final _T t;
  final IconData icon;
  final String tip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tip,
        child: _Tap(
          t: t,
          onTap: onTap,
          radius: 8,
          child: SizedBox(width: 36, height: 28, child: Icon(icon, size: 16, color: t.sub)),
        ),
      );
}
