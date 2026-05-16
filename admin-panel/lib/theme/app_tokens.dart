import 'package:flutter/material.dart';

/// Design tokens — dark premium (referência: Linear, Stripe, Vercel).
class AppColors {
  static const Color background = Color(0xFF07080D);
  static const Color backgroundElevated = Color(0xFF0C0E16);
  static const Color sidebar = Color(0xFF090A10);
  static const Color surface = Color(0xFF11141D);
  static const Color surfaceAlt = Color(0xFF161B27);
  static const Color surfaceSoft = Color(0xFF1C2230);
  static const Color glass = Color(0xCC11141D);
  static const Color border = Color(0xFF252B3A);
  static const Color borderSubtle = Color(0xFF1A1F2B);
  static const Color divider = Color(0xFF151A24);
  static const Color text = Color(0xFFF4F5F7);
  static const Color textMuted = Color(0xFF8B93A7);
  static const Color textSoft = Color(0xFF5C6478);
  static const Color primary = Color(0xFFF97316);
  static const Color primaryStrong = Color(0xFFEA580C);
  static const Color primarySoft = Color(0xFFFFB07A);
  static const Color primaryMuted = Color(0x26F97316);
  static const Color accentBlue = Color(0xFF60A5FA);
  static const Color accentBlueMuted = Color(0x2660A5FA);
  static const Color accentBlueDeep = Color(0xFF3B82F6);
  static const Color accentCyan = Color(0xFF5EC8D8);
  static const Color accentSecondary = Color(0xFF818CF8);
  static const Color accentPurple = Color(0xFF8B5CF6);
  static const Color accentPurpleDeep = Color(0xFF6D28D9);
  static const Color borderHighlight = Color(0x33FFFFFF);
  static const Color success = Color(0xFF34D399);
  static const Color warning = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFF87171);
  static const Color info = Color(0xFF38BDF8);
  static const Color whatsappBubble = Color(0xFF141A28);
  static const Color whatsappReply = Color(0xFF222A3C);
  static const Color whatsappPattern = Color(0xFF05060A);
}

class AppGradients {
  static const LinearGradient page = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0A0C14), Color(0xFF07080D), Color(0xFF080A12)],
    stops: [0.0, 0.55, 1.0],
  );

  static const LinearGradient meshTop = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [
      Color(0x184F46E5),
      Colors.transparent,
      Color(0x12F97316),
    ],
  );

  static const LinearGradient glassPanel = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF161B27), Color(0xFF11141D)],
  );

  static const LinearGradient accent = LinearGradient(
    colors: [Color(0xFFF97316), Color(0xFFEA580C)],
  );

  static const LinearGradient brandIcon = LinearGradient(
    colors: [Color(0xFF60A5FA), Color(0xFF818CF8)],
  );

  /// Fundo cinematográfico mais profundo, com tons navy e roxo discreto.
  static const LinearGradient heroBackdrop = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF05060B),
      Color(0xFF080A14),
      Color(0xFF0A0B18),
    ],
    stops: [0.0, 0.55, 1.0],
  );

  /// Glow roxo/azul para destaques sutis.
  static const LinearGradient violetGlow = LinearGradient(
    colors: [Color(0xFF6D28D9), Color(0xFF3B82F6)],
  );

  /// Gradiente alaranjado premium para CTAs e plano destacado.
  static const LinearGradient premiumOrange = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFB923C), Color(0xFFEA580C), Color(0xFFC2410C)],
    stops: [0.0, 0.6, 1.0],
  );
}

class AppSpacing {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 40;
  static const double section = 96;
}

class AppRadius {
  static const BorderRadius sm = BorderRadius.all(Radius.circular(10));
  static const BorderRadius md = BorderRadius.all(Radius.circular(14));
  static const BorderRadius lg = BorderRadius.all(Radius.circular(18));
  static const BorderRadius xl = BorderRadius.all(Radius.circular(22));
  static const BorderRadius xxl = BorderRadius.all(Radius.circular(26));
  static const BorderRadius xxxl = BorderRadius.all(Radius.circular(32));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

class AppDurations {
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 380);
}

class AppShadows {
  static const List<BoxShadow> panelHover = <BoxShadow>[
    BoxShadow(
      color: Color(0x1A60A5FA),
      blurRadius: 40,
      offset: Offset(0, 16),
    ),
    BoxShadow(
      color: Color(0x40000000),
      blurRadius: 32,
      offset: Offset(0, 12),
    ),
  ];

  static const List<BoxShadow> card = <BoxShadow>[
    BoxShadow(
      color: Color(0x50000000),
      blurRadius: 48,
      offset: Offset(0, 24),
    ),
    BoxShadow(
      color: Color(0x0AFFFFFF),
      blurRadius: 0,
      offset: Offset(0, 1),
    ),
  ];

  static const List<BoxShadow> hover = <BoxShadow>[
    BoxShadow(
      color: Color(0x1AF97316),
      blurRadius: 32,
      offset: Offset(0, 12),
    ),
    BoxShadow(
      color: Color(0x4060A5FA),
      blurRadius: 40,
      offset: Offset(0, 16),
    ),
  ];

  static const List<BoxShadow> glowOrange = <BoxShadow>[
    BoxShadow(
      color: Color(0x33F97316),
      blurRadius: 24,
      spreadRadius: -6,
    ),
  ];

  static const List<BoxShadow> glowBlue = <BoxShadow>[
    BoxShadow(
      color: Color(0x3360A5FA),
      blurRadius: 28,
      spreadRadius: -8,
    ),
  ];

  static const List<BoxShadow> navActive = <BoxShadow>[
    BoxShadow(
      color: Color(0x28F97316),
      blurRadius: 20,
      offset: Offset(0, 4),
    ),
  ];

  /// Glow violeta para hero/highlights premium.
  static const List<BoxShadow> glowViolet = <BoxShadow>[
    BoxShadow(
      color: Color(0x408B5CF6),
      blurRadius: 40,
      spreadRadius: -10,
    ),
  ];

  /// Sombra cinematográfica para painéis grandes (hero mockup, planos).
  static const List<BoxShadow> cinematic = <BoxShadow>[
    BoxShadow(
      color: Color(0x66000000),
      blurRadius: 60,
      offset: Offset(0, 28),
    ),
    BoxShadow(
      color: Color(0x33000000),
      blurRadius: 100,
      offset: Offset(0, 50),
    ),
    BoxShadow(
      color: Color(0x14FFFFFF),
      blurRadius: 0,
      offset: Offset(0, 1),
    ),
  ];
}
