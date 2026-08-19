import 'package:flutter/material.dart';

/// Premium Obsidian — Brand Board V2.1.
/// Cyan = primary · Violet = IA · Amber = warning semântico · Red = danger.
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

  static const Color primary = Color(0xFF22D3EE);
  static const Color primaryStrong = Color(0xFF06B6D4);
  static const Color primarySoft = Color(0xFF67E8F9);
  static const Color primaryMuted = Color(0x2622D3EE);
  static const Color onPrimary = Color(0xFF042F2E);

  static const Color accentBlue = Color(0xFF60A5FA);
  static const Color accentBlueMuted = Color(0x2660A5FA);
  static const Color accentBlueDeep = Color(0xFF3B82F6);
  static const Color accentCyan = Color(0xFF22D3EE);
  static const Color accentSecondary = Color(0xFF8B5CF6);
  static const Color accentPurple = Color(0xFF8B5CF6);
  static const Color accentPurpleDeep = Color(0xFF6D28D9);
  static const Color borderHighlight = Color(0x33FFFFFF);
  static const Color success = Color(0xFF2DD4BF);
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
      Color(0x1222D3EE),
    ],
  );

  static const LinearGradient glassPanel = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF161B27), Color(0xFF11141D)],
  );

  static const LinearGradient accent = LinearGradient(
    colors: [AppColors.primary, AppColors.primaryStrong],
  );

  static const LinearGradient brandIcon = LinearGradient(
    colors: [AppColors.primary, AppColors.accentSecondary],
  );

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

  static const LinearGradient violetGlow = LinearGradient(
    colors: [Color(0xFF6D28D9), Color(0xFF3B82F6)],
  );

  static const LinearGradient primaryCta = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF22D3EE), Color(0xFF06B6D4), Color(0xFF0E7490)],
    stops: [0.0, 0.6, 1.0],
  );

  /// Alias de migração V2 — NÃO é identidade.
  /// Dívida: após migrar consumidores, remover `premiumOrange` e usar só `primaryCta`.
  static const LinearGradient premiumOrange = primaryCta;
}

class AppBreakpoints {
  static const double compact = 720;
  static const double medium = 1100;
  static const double wide = 1440;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compact;

  static bool usePersistentSidebar(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= medium;

  static bool useInboxSplit(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= medium;
}

class AppLayout {
  static const double sidebarExpanded = 216;
  static const double sidebarCollapsed = 68;
  static const double inboxWidth = 310;
  static const double contextPanelWidth = 260;
  /// Viewport abaixo disso: contexto inicia fechado.
  static const double contextPanelMinViewport = 1200;
  /// Largura mínima da região chat+contexto para permitir o painel aberto.
  static const double contextPanelMinDetailWidth = 640;
}

class AppPageInsets {
  static EdgeInsets of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < AppBreakpoints.compact) {
      return const EdgeInsets.fromLTRB(12, 12, 12, 16);
    }
    if (width < AppBreakpoints.medium) {
      return const EdgeInsets.fromLTRB(16, 14, 16, 16);
    }
    return const EdgeInsets.fromLTRB(20, 16, 20, 16);
  }
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
  static const BorderRadius sm = BorderRadius.all(Radius.circular(6));
  static const BorderRadius md = BorderRadius.all(Radius.circular(8));
  static const BorderRadius lg = BorderRadius.all(Radius.circular(10));
  static const BorderRadius xl = BorderRadius.all(Radius.circular(12));
  static const BorderRadius xxl = BorderRadius.all(Radius.circular(14));
  static const BorderRadius xxxl = BorderRadius.all(Radius.circular(16));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

class AppDurations {
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration normal = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 240);
}

class AppShadows {
  static const List<BoxShadow> panelHover = <BoxShadow>[];
  static const List<BoxShadow> card = <BoxShadow>[
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 10,
      offset: Offset(0, 2),
    ),
  ];
  static const List<BoxShadow> hover = <BoxShadow>[
    BoxShadow(
      color: Color(0x18000000),
      blurRadius: 14,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> glowCyan = <BoxShadow>[
    BoxShadow(
      color: Color(0x2222D3EE),
      blurRadius: 16,
    ),
  ];

  static const List<BoxShadow> glowOrange = glowCyan;

  static const List<BoxShadow> glowBlue = <BoxShadow>[
    BoxShadow(
      color: Color(0x22000000),
      blurRadius: 18,
    ),
  ];

  static const List<BoxShadow> navActive = <BoxShadow>[
    BoxShadow(
      color: Color(0x18000000),
      blurRadius: 12,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> glowViolet = <BoxShadow>[
    BoxShadow(
      color: Color(0x228B5CF6),
      blurRadius: 16,
    ),
  ];

  static const List<BoxShadow> cinematic = <BoxShadow>[
    BoxShadow(
      color: Color(0x33000000),
      blurRadius: 24,
      offset: Offset(0, 12),
    ),
  ];
}
