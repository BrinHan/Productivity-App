part of 'home_page.dart';

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.t, required this.shell});
  final _T t;
  final ShellController shell;

  @override
  Widget build(BuildContext context) => DragToMoveArea(
        child: Container(
          height: 40,
          padding: const EdgeInsets.only(left: 16, right: 6),
          decoration: BoxDecoration(
            color: t.side,
            border: Border(bottom: BorderSide(color: t.line)),
          ),
          child: Row(children: [
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
