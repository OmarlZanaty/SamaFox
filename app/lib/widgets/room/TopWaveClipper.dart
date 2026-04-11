import 'package:flutter/material.dart';

class TopWaveClipper extends CustomClipper<Path> {
  final double depth;

  TopWaveClipper({this.depth = 30});

  @override
  Path getClip(Size size) {
    final path = Path();

    path.lineTo(0, depth);

    path.quadraticBezierTo(
      size.width / 2,
      0,
      size.width,
      depth,
    );

    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}