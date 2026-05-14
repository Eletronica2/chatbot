import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFF0B0F1A);
  static const Color sidebar = Color(0xFF0E1422);
  static const Color surface = Color(0xFF121826);
  static const Color surfaceAlt = Color(0xFF182133);
  static const Color surfaceSoft = Color(0xFF1D2740);
  static const Color border = Color(0xFF25304A);
  static const Color divider = Color(0xFF202A42);
  static const Color text = Color(0xFFF5F7FF);
  static const Color textMuted = Color(0xFF98A4C0);
  static const Color textSoft = Color(0xFF6E7B99);
  static const Color primary = Color(0xFF7C8CFF);
  static const Color primaryStrong = Color(0xFF5B6CFF);
  static const Color primarySoft = Color(0xFF9AA7FF);
  static const Color success = Color(0xFF19C37D);
  static const Color warning = Color(0xFFFFB84D);
  static const Color danger = Color(0xFFFF6B6B);
  static const Color info = Color(0xFF48C0FF);
  static const Color whatsappBubble = Color(0xFF1B2336);
  static const Color whatsappReply = Color(0xFF6D7FFF);
  static const Color whatsappPattern = Color(0xFF0A1220);
}

class AppSpacing {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

class AppRadius {
  static const BorderRadius sm = BorderRadius.all(Radius.circular(12));
  static const BorderRadius md = BorderRadius.all(Radius.circular(16));
  static const BorderRadius lg = BorderRadius.all(Radius.circular(20));
  static const BorderRadius xl = BorderRadius.all(Radius.circular(24));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

class AppShadows {
  static const List<BoxShadow> card = <BoxShadow>[
    BoxShadow(
      color: Color(0x22000000),
      blurRadius: 28,
      offset: Offset(0, 16),
    ),
  ];

  static const List<BoxShadow> hover = <BoxShadow>[
    BoxShadow(
      color: Color(0x18000000),
      blurRadius: 18,
      offset: Offset(0, 10),
    ),
  ];
}

