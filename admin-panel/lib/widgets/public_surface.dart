import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import 'atenda_logo.dart';

/// Gradiente de CTA das superfícies públicas (Landing/Auth).
/// Cyan → violet, alinhado à Landing V2 — não altera o painel operacional.
const LinearGradient kPublicCtaGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [Color(0xFF00D1FF), Color(0xFF6D28D9)],
);

/// Rede animada sutil para login — respeita reduced motion.
class LoginNetworkBackdrop extends StatefulWidget {
  const LoginNetworkBackdrop({super.key});

  @override
  State<LoginNetworkBackdrop> createState() => _LoginNetworkBackdropState();
}

class _LoginNetworkBackdropState extends State<LoginNetworkBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = AppMotion.reduce(context);
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const PublicAtmosphere(vivid: true),
          if (reduce)
            CustomPaint(painter: _NetworkPainter(t: 0))
          else
            AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                return CustomPaint(painter: _NetworkPainter(t: _ctrl.value));
              },
            ),
        ],
      ),
    );
  }
}

class _NetworkPainter extends CustomPainter {
  _NetworkPainter({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final nodes = <Offset>[
      for (var i = 0; i < 14; i++)
        Offset(
          size.width * ((0.08 + (i * 0.17) % 0.84) + 0.02 * _wave(t + i * 0.07)),
          size.height *
              ((0.12 + (i * 0.23) % 0.76) + 0.025 * _wave(t * 1.3 + i * 0.11)),
        ),
    ];

    final line = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.10)
      ..strokeWidth = 1
      ..isAntiAlias = true;
    for (var i = 0; i < nodes.length; i++) {
      for (var j = i + 1; j < nodes.length; j++) {
        final a = nodes[i];
        final b = nodes[j];
        final d = (a - b).distance;
        if (d < size.shortestSide * 0.28) {
          canvas.drawLine(a, b, line);
        }
      }
    }

    final nodePaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.35)
      ..isAntiAlias = true;
    for (final n in nodes) {
      canvas.drawCircle(n, 2.2, nodePaint);
    }
  }

  double _wave(double x) => (x % 1.0) < 0.5
      ? (x % 1.0) * 4 - 1
      : 3 - (x % 1.0) * 4;

  @override
  bool shouldRepaint(covariant _NetworkPainter oldDelegate) =>
      oldDelegate.t != t;
}

/// Atmosfera estática: grid discreto + glows radiais. Sem animação contínua.
class PublicAtmosphere extends StatelessWidget {
  const PublicAtmosphere({super.key, this.vivid = false});

  final bool vivid;

  @override
  Widget build(BuildContext context) {
    final cyanOpacity = vivid ? 0.16 : 0.10;
    final violetOpacity = vivid ? 0.14 : 0.09;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: AppColors.background),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.85, -0.9),
                radius: 1.15,
                colors: [
                  AppColors.primary.withValues(alpha: cyanOpacity),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.95, 1.05),
                radius: 1.2,
                colors: [
                  AppColors.accentSecondary.withValues(alpha: violetOpacity),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          CustomPaint(painter: _PublicGridPainter()),
        ],
      ),
    );
  }
}

class _PublicGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF252B3A).withValues(alpha: 0.28)
      ..strokeWidth = 1;
    const step = 64.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class BrandLockup extends StatelessWidget {
  const BrandLockup({
    super.key,
    this.markSize = 28,
    this.fontSize = 18,
    this.onTap,
    this.muted = false,
  });

  final double markSize;
  final double fontSize;
  final VoidCallback? onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final row = AtendaLogo(
      height: markSize,
      showWordmark: true,
      wordmarkColor: muted ? AppColors.textMuted : AppColors.text,
    );
    if (onTap == null) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: row),
    );
  }
}

class PublicPrimaryButton extends StatefulWidget {
  const PublicPrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon = Icons.arrow_forward_rounded,
    this.expand = false,
    this.loading = false,
    this.height = 48,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool expand;
  final bool loading;
  final double height;

  @override
  State<PublicPrimaryButton> createState() => _PublicPrimaryButtonState();
}

class _PublicPrimaryButtonState extends State<PublicPrimaryButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null && !widget.loading;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: AppMotion.hoverOf(context),
          curve: AppMotion.hoverCurve,
          height: widget.height,
          width: widget.expand ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            gradient: enabled ? kPublicCtaGradient : null,
            color: enabled ? null : AppColors.surfaceSoft,
            borderRadius: BorderRadius.circular(10),
            boxShadow: enabled && _hover
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.28),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.loading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.onPrimary,
                  ),
                )
              else ...[
                Text(
                  widget.label,
                  style: GoogleFonts.manrope(
                    color: enabled ? Colors.white : AppColors.textSoft,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (widget.icon != null) ...[
                  const SizedBox(width: 8),
                  Icon(widget.icon, size: 18, color: Colors.white),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class PublicGhostButton extends StatefulWidget {
  const PublicGhostButton({
    super.key,
    required this.label,
    required this.onTap,
    this.expand = false,
    this.height = 48,
  });

  final String label;
  final VoidCallback onTap;
  final bool expand;
  final double height;

  @override
  State<PublicGhostButton> createState() => _PublicGhostButtonState();
}

class _PublicGhostButtonState extends State<PublicGhostButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.hoverOf(context),
          height: widget.height,
          width: widget.expand ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: _hover ? Colors.white.withValues(alpha: 0.05) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: GoogleFonts.manrope(
              color: AppColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class PublicFadeIn extends StatelessWidget {
  const PublicFadeIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduce(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.page + delay,
      curve: AppMotion.pageCurve,
      builder: (context, value, child) {
        final t = delay == Duration.zero
            ? value
            : ((value - (delay.inMilliseconds / (AppMotion.page + delay).inMilliseconds))
                .clamp(0.0, 1.0));
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - t)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Banner de erro das superfícies públicas (login, cadastro, convite, reset).
class PublicErrorBanner extends StatelessWidget {
  const PublicErrorBanner({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.danger,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.manrope(
                  color: AppColors.danger,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

InputDecoration publicInputDecoration({
  required String hint,
  Widget? prefix,
  Widget? suffix,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.manrope(color: AppColors.textSoft, fontSize: 14),
    filled: true,
    fillColor: const Color(0xFF0B0E17),
    prefixIcon: prefix,
    suffixIcon: suffix,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.danger),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.danger, width: 1.4),
    ),
    errorStyle: GoogleFonts.manrope(color: AppColors.danger, fontSize: 12),
  );
}
