import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dynamic_island.dart';
import 'island_controller.dart';
import 'island_pages.dart';

/// Draws the dynamic island inside the normal app window (map / planner), so
/// it is available even while the app is open. Uses the same controller as
/// the minimized island window, so there is no second engine or window.
class IslandOverlay extends StatelessWidget {
  const IslandOverlay({
    super.key,
    required this.island,
    required this.onShortcut,
    required this.child,
  });
  final IslandController island;
  final void Function(IslandShortcut) onShortcut;
  final Widget child;

  void _gaze(Offset p, double width) {
    if (!island.visible) return;
    final seat = homeSeatCenter(kOpenHome);
    final seated = island.state == IslandState.open && island.page == IslandPage.home;
    final eye = seated
        ? Offset((width - kOpenHome.width) / 2 + seat.dx, seat.dy)
        : Offset(width / 2, island.idleSize.height / 2);
    island.gaze.value = Offset(
      ((p.dx - eye.dx) / 240).clamp(-1.0, 1.0).toDouble(),
      ((p.dy - eye.dy) / 120).clamp(-1.0, 1.0).toDouble(),
    );
  }

  Size _zone() {
    if (!island.visible) return const Size(340, 10); // very top edge only
    if (island.state == IslandState.open) {
      final o = openSizeFor(island.page);
      return Size(o.width + 120, o.height + 50);
    }
    return const Size(520, 110);
  }

  @override
  Widget build(BuildContext context) => Focus(
        autofocus: true,
        onKeyEvent: (node, e) {
          if (e is KeyDownEvent &&
              e.logicalKey == LogicalKeyboardKey.escape &&
              island.state == IslandState.open) {
            island.close();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: LayoutBuilder(
          builder: (context, c) => Listener(
            behavior: HitTestBehavior.translucent,
            onPointerHover: (e) => _gaze(e.localPosition, c.maxWidth),
            child: Stack(
              fit: StackFit.expand,
              children: [
                child,
                ListenableBuilder(
                  listenable: island,
                  builder: (context, _) {
                    final z = _zone();
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        // click outside the open island closes it
                        if (island.state == IslandState.open && !island.openOnHover)
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: island.close,
                            ),
                          ),
                        Align(
                          alignment: Alignment.topCenter,
                          child: MouseRegion(
                            opaque: false,
                            cursor: SystemMouseCursors.basic,
                            onEnter: (_) => island.setNear(true),
                            onExit: (_) => island.setNear(false),
                            child: SizedBox(
                              width: z.width,
                              height: z.height,
                              child: OverflowBox(
                                alignment: Alignment.topCenter,
                                minWidth: 0,
                                minHeight: 0,
                                maxWidth: double.infinity,
                                maxHeight: double.infinity,
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: MouseRegion(
                                    onEnter: (_) => island.setOverPill(true),
                                    onExit: (_) => island.setOverPill(false),
                                    child: DynamicIsland(
                                      controller: island,
                                      onShortcut: onShortcut,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
}
