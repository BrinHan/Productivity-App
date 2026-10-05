import 'package:flutter/material.dart';

/// The island's fully opaque black surface.
class HeightFade extends StatelessWidget {
  const HeightFade({super.key, required this.height, required this.child});
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(color: Colors.black, child: child);
}
