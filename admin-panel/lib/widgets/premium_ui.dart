import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_tokens.dart';

/// Fundo premium animado (cinematográfico) usado em landing, login e telas internas.
class PremiumPageBackground extends StatefulWidget {
  const PremiumPageBackground({
    super.key,
    required this.child,
    this.intensity = AmbientIntensity.normal,
  });

  final Widget child;
  final AmbientIntensity intensity;

  @override
  State<PremiumPageBackground> createState() => _PremiumPageBackgroundState();
}

class _PremiumPageBackgroundState extends State<PremiumPageBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(gradient: AppGradients.heroBackdrop),
        ),
        AnimatedAmbientLayer(controller: _ctrl, intensity: widget.intensity),
        widget.child,
      ],
    );
  }
}

/// Quanto de movimento/orbs aplicar (mais discreto em telas internas).
enum AmbientIntensity { soft, normal, vivid }

/// Camada animada (orbs + partículas + grid) usada por landing/login/telas internas.
/// Recebe um [AnimationController] externo (em loop reverse).
class AnimatedAmbientLayer extends StatelessWidget {
  const AnimatedAmbientLayer({
    super.key,
    required this.controller,
    this.intensity = AmbientIntensity.normal,
    this.showGrid = true,
  });

  final AnimationController controller;
  final AmbientIntensity intensity;
  final bool showGrid;

  @override
  Widget build(BuildContext context) {
    final orbCount = switch (intensity) {
      AmbientIntensity.soft => 2,
      AmbientIntensity.normal => 3,
      AmbientIntensity.vivid => 4,
    };
    final orbs = _orbsFor(orbCount, intensity);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final t = controller.value;
          return Stack(
            fit: StackFit.expand,
            children: [
              for (final orb in orbs) _buildAnimatedOrb(orb, t),
              if (showGrid)
                const Positioned.fill(child: _GridOverlay()),
              Positioned.fill(
                child: CustomPaint(
                  painter: _ParticlesPainter(t),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAnimatedOrb(_OrbSpec orb, double t) {
    final phase = (t + orb.phaseOffset) % 1.0;
    final wave = math.sin(phase * math.pi * 2);
    final wave2 = math.cos(phase * math.pi * 2);
    final dx = orb.driftX * wave;
    final dy = orb.driftY * wave2;
    final scale = 1.0 + 0.05 * wave;
    final opacityFactor = 0.85 + 0.15 * ((wave + 1) / 2);
    return Positioned(
      top: orb.top != null ? orb.top! + dy : null,
      bottom: orb.bottom != null ? orb.bottom! - dy : null,
      left: orb.left != null ? orb.left! + dx : null,
      right: orb.right != null ? orb.right! - dx : null,
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: orb.size,
          height: orb.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                orb.color.withValues(alpha: orb.alpha * opacityFactor),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<_OrbSpec> _orbsFor(int count, AmbientIntensity intensity) {
    final base = <_OrbSpec>[
      _OrbSpec(
        color: AppColors.accentBlue,
        size: 560,
        top: -160,
        right: -120,
        driftX: 18,
        driftY: 14,
        alpha: intensity == AmbientIntensity.soft ? 0.08 : 0.14,
        phaseOffset: 0.0,
      ),
      _OrbSpec(
        color: AppColors.accentPurple,
        size: 480,
        top: 120,
        left: -160,
        driftX: 16,
        driftY: 18,
        alpha: intensity == AmbientIntensity.soft ? 0.10 : 0.16,
        phaseOffset: 0.33,
      ),
      _OrbSpec(
        color: AppColors.primary,
        size: 420,
        bottom: -120,
        right: -80,
        driftX: 14,
        driftY: 12,
        alpha: intensity == AmbientIntensity.soft ? 0.06 : 0.10,
        phaseOffset: 0.55,
      ),
      _OrbSpec(
        color: AppColors.accentBlueDeep,
        size: 520,
        bottom: -160,
        left: -100,
        driftX: 20,
        driftY: 16,
        alpha: intensity == AmbientIntensity.soft ? 0.08 : 0.13,
        phaseOffset: 0.78,
      ),
    ];
    return base.take(count).toList();
  }
}

class _OrbSpec {
  const _OrbSpec({
    required this.color,
    required this.size,
    required this.alpha,
    required this.phaseOffset,
    required this.driftX,
    required this.driftY,
    this.top,
    this.bottom,
    this.left,
    this.right,
  });

  final Color color;
  final double size;
  final double alpha;
  final double phaseOffset;
  final double driftX;
  final double driftY;
  final double? top;
  final double? bottom;
  final double? left;
  final double? right;
}

class _GridOverlay extends StatelessWidget {
  const _GridOverlay();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _GridPainter());
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.018)
      ..strokeWidth = 1;
    const spacing = 80.0;
    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ParticlesPainter extends CustomPainter {
  _ParticlesPainter(this.t);
  final double t;

  static const _seeds = <_ParticleSeed>[
    _ParticleSeed(0.10, 0.25, 60, 1.6),
    _ParticleSeed(0.22, 0.70, 90, 1.2),
    _ParticleSeed(0.38, 0.18, 50, 2.0),
    _ParticleSeed(0.55, 0.55, 110, 1.4),
    _ParticleSeed(0.68, 0.85, 70, 1.0),
    _ParticleSeed(0.78, 0.30, 80, 1.8),
    _ParticleSeed(0.88, 0.62, 60, 1.2),
    _ParticleSeed(0.45, 0.92, 90, 1.6),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.05);
    for (final s in _seeds) {
      final phase = (t * s.speed + s.x * 0.7) % 1.0;
      final wave = math.sin(phase * math.pi * 2);
      final dx = size.width * s.x + wave * s.amplitude;
      final dy = size.height * s.y + math.cos(phase * math.pi * 2) * (s.amplitude * 0.6);
      canvas.drawCircle(Offset(dx, dy), 1.6, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlesPainter oldDelegate) => oldDelegate.t != t;
}

class _ParticleSeed {
  const _ParticleSeed(this.x, this.y, this.amplitude, this.speed);
  final double x;
  final double y;
  final double amplitude;
  final double speed;
}

class PremiumGlassCard extends StatefulWidget {
  const PremiumGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.highlight = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  State<PremiumGlassCard> createState() => _PremiumGlassCardState();
}

class _PremiumGlassCardState extends State<PremiumGlassCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppDurations.normal,
          curve: Curves.easeOutCubic,
          padding: widget.padding,
          decoration: BoxDecoration(
            gradient: AppGradients.glassPanel,
            borderRadius: AppRadius.xxl,
            border: Border.all(
              color: _hovered || widget.highlight
                  ? AppColors.primary.withValues(alpha: 0.35)
                  : AppColors.borderSubtle,
            ),
            boxShadow: _hovered ? AppShadows.hover : AppShadows.card,
          ),
          clipBehavior: Clip.antiAlias,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Card compacto da faixa de status horizontal.
class PremiumStatusTile extends StatefulWidget {
  const PremiumStatusTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.hint,
    this.accent = AppColors.accentBlue,
    this.onTap,
    this.expand = false,
  });

  final String label;
  final String value;
  final String? hint;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;
  final bool expand;

  @override
  State<PremiumStatusTile> createState() => _PremiumStatusTileState();
}

class _PremiumStatusTileState extends State<PremiumStatusTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          width: widget.expand ? double.infinity : 220,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            gradient: AppGradients.glassPanel,
            borderRadius: AppRadius.xl,
            border: Border.all(
              color: _hovered
                  ? widget.accent.withValues(alpha: 0.45)
                  : AppColors.borderSubtle,
            ),
            boxShadow: _hovered ? AppShadows.glowBlue : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: widget.accent.withValues(alpha: 0.12),
                      borderRadius: AppRadius.md,
                    ),
                    child: Icon(widget.icon, size: 18, color: widget.accent),
                  ),
                  const Spacer(),
                  if (_hovered && widget.onTap != null)
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 16,
                      color: AppColors.textSoft,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                widget.label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSoft,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                  height: 1.15,
                ),
              ),
              if (widget.hint != null && widget.hint!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  widget.hint!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class PremiumPageHeader extends StatelessWidget {
  const PremiumPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.actions,
    this.badges,
  });

  final String title;
  final String subtitle;
  final List<Widget>? actions;
  final List<Widget>? badges;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: compact ? 28 : 32,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
                height: 1.1,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: AppColors.textMuted,
                height: 1.5,
              ),
            ),
            if (badges != null && badges!.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: badges!),
            ],
          ],
        );

        if (compact || actions == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleBlock,
              if (actions != null) ...[
                const SizedBox(height: AppSpacing.md),
                Wrap(spacing: 8, runSpacing: 8, children: actions!),
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: AppSpacing.lg),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: actions!,
            ),
          ],
        );
      },
    );
  }
}

class PremiumSection extends StatelessWidget {
  const PremiumSection({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.trailing,
    this.accentColor = AppColors.accentBlue,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return PremiumGlassCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg + 2,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 3,
                height: 34,
                margin: const EdgeInsets.only(right: 14, top: 2),
                decoration: BoxDecoration(
                  borderRadius: AppRadius.pill,
                  color: accentColor.withValues(alpha: 0.85),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppColors.textMuted,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    );
  }
}

class PremiumSwitchRow extends StatelessWidget {
  const PremiumSwitchRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.icon = Icons.auto_awesome_rounded,
    this.loading = false,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft.withValues(alpha: 0.45),
        borderRadius: AppRadius.lg,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: value
                  ? AppColors.success.withValues(alpha: 0.12)
                  : AppColors.warning.withValues(alpha: 0.1),
              borderRadius: AppRadius.md,
            ),
            child: Icon(
              icon,
              color: value ? AppColors.success : AppColors.warning,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (loading)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class PremiumField extends StatelessWidget {
  const PremiumField({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.backgroundElevated.withValues(alpha: 0.65),
        borderRadius: AppRadius.lg,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 16, color: AppColors.textSoft),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                    color: AppColors.textSoft,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PremiumBadge extends StatelessWidget {
  const PremiumBadge({
    super.key,
    required this.label,
    this.icon,
    this.color = AppColors.accentBlue,
  });

  final String label;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.pill,
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class PremiumTextButton extends StatefulWidget {
  const PremiumTextButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  State<PremiumTextButton> createState() => _PremiumTextButtonState();
}

class _PremiumTextButtonState extends State<PremiumTextButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: widget.primary ? AppGradients.accent : null,
            color: widget.primary
                ? null
                : (_hovered ? AppColors.surfaceAlt : AppColors.surfaceSoft),
            borderRadius: AppRadius.pill,
            border: widget.primary
                ? null
                : Border.all(
                    color: _hovered
                        ? AppColors.border
                        : AppColors.borderSubtle,
                  ),
            boxShadow: widget.primary && _hovered ? AppShadows.panelHover : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: widget.primary ? const Color(0xFF1C1008) : AppColors.text,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: widget.primary ? const Color(0xFF1C1008) : AppColors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PremiumFilterChip extends StatefulWidget {
  const PremiumFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  State<PremiumFilterChip> createState() => _PremiumFilterChipState();
}

class _PremiumFilterChipState extends State<PremiumFilterChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? AppColors.accentBlue.withValues(alpha: 0.14)
                : (_hovered
                    ? AppColors.surfaceAlt.withValues(alpha: 0.72)
                    : AppColors.background.withValues(alpha: 0.35)),
            borderRadius: AppRadius.pill,
            border: Border.all(
              color: active
                  ? AppColors.accentBlue.withValues(alpha: 0.34)
                  : AppColors.borderSubtle.withValues(alpha: 0.62),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: 13,
                  color: active ? AppColors.accentBlue : AppColors.textSoft,
                ),
                const SizedBox(width: 7),
              ],
              Text(
                widget.label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active ? AppColors.text : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PremiumEmptyPanel extends StatelessWidget {
  const PremiumEmptyPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.accent = AppColors.accentBlue,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        borderRadius: AppRadius.xl,
        border: Border.all(
          color: AppColors.borderSubtle.withValues(alpha: 0.6),
        ),
        color: AppColors.background.withValues(alpha: 0.35),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.1),
              border: Border.all(color: accent.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, size: 22, color: accent.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppColors.textMuted,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bloco visual sem lógica — para áreas ainda sem API dedicada.
class PremiumComingSoonStrip extends StatelessWidget {
  const PremiumComingSoonStrip({
    super.key,
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return PremiumEmptyPanel(
      icon: Icons.extension_outlined,
      title: title,
      description: description,
      accent: AppColors.accentSecondary,
    );
  }
}

// ============================================================================
// Pílulas premium (CTAs e nav)
// ============================================================================

/// Pílula primária com gradiente laranja premium + glow.
class PremiumPill extends StatefulWidget {
  const PremiumPill({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.size = PremiumPillSize.medium,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final PremiumPillSize size;

  @override
  State<PremiumPill> createState() => _PremiumPillState();
}

enum PremiumPillSize { small, medium, large }

class _PremiumPillState extends State<PremiumPill> {
  bool _hovered = false;

  EdgeInsets _padding() {
    switch (widget.size) {
      case PremiumPillSize.small:
        return const EdgeInsets.symmetric(horizontal: 16, vertical: 8);
      case PremiumPillSize.medium:
        return const EdgeInsets.symmetric(horizontal: 22, vertical: 12);
      case PremiumPillSize.large:
        return const EdgeInsets.symmetric(horizontal: 26, vertical: 16);
    }
  }

  double _fontSize() {
    switch (widget.size) {
      case PremiumPillSize.small:
        return 12;
      case PremiumPillSize.medium:
        return 13;
      case PremiumPillSize.large:
        return 15;
    }
  }

  double _iconSize() {
    switch (widget.size) {
      case PremiumPillSize.small:
        return 14;
      case PremiumPillSize.medium:
        return 16;
      case PremiumPillSize.large:
        return 18;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          padding: _padding(),
          decoration: BoxDecoration(
            gradient: AppGradients.premiumOrange,
            borderRadius: AppRadius.pill,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: _hovered ? 0.55 : 0.35),
                blurRadius: _hovered ? 32 : 22,
                spreadRadius: _hovered ? -4 : -8,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: Colors.white, size: _iconSize()),
                const SizedBox(width: 8),
              ],
              Text(
                widget.label,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: _fontSize(),
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pílula ghost (transparente com borda discreta).
class PremiumGhostPill extends StatefulWidget {
  const PremiumGhostPill({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  State<PremiumGhostPill> createState() => _PremiumGhostPillState();
}

class _PremiumGhostPillState extends State<PremiumGhostPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          decoration: BoxDecoration(
            color: _hovered
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.02),
            borderRadius: AppRadius.pill,
            border: Border.all(
              color: _hovered
                  ? Colors.white.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: AppColors.text, size: 14),
                const SizedBox(width: 8),
              ],
              Text(
                widget.label,
                style: GoogleFonts.inter(
                  color: AppColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Eyebrow (badge pequena acima de títulos de seção).
class PremiumSectionEyebrow extends StatelessWidget {
  const PremiumSectionEyebrow({
    super.key,
    required this.text,
    this.accent = AppColors.accentBlue,
    this.alignStart = false,
  });

  final String text;
  final Color accent;
  final bool alignStart;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignStart ? Alignment.centerLeft : Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.1),
          borderRadius: AppRadius.pill,
          border: Border.all(color: accent.withValues(alpha: 0.3)),
        ),
        child: Text(
          text,
          style: GoogleFonts.inter(
            color: accent,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
      ),
    );
  }
}

/// Botão de ação compacto com gradiente premium laranja (estilo "+ Adicionar etapa").
/// Usado em locais onde precisamos de um CTA de tamanho médio, com texto e ícone
/// brancos sobre fundo gradiente — substitui botões amarelos que tinham contraste fraco.
class PremiumAccentButton extends StatefulWidget {
  const PremiumAccentButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.dense = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Reduz padding vertical para uso em barras compactas.
  final bool dense;

  /// Quando true, expande horizontalmente até o pai (útil em columns).
  final bool expand;

  @override
  State<PremiumAccentButton> createState() => _PremiumAccentButtonState();
}

class _PremiumAccentButtonState extends State<PremiumAccentButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null;
    final paddingV = widget.dense ? 10.0 : 12.0;
    final paddingH = widget.dense ? 16.0 : 20.0;
    final child = AnimatedContainer(
      duration: AppDurations.fast,
      padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
      decoration: BoxDecoration(
        gradient: disabled
            ? const LinearGradient(
                colors: [Color(0xFF3A3F4D), Color(0xFF2A2F3B)],
              )
            : AppGradients.premiumOrange,
        borderRadius: BorderRadius.circular(12),
        boxShadow: disabled
            ? const []
            : [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: _hovered ? 0.55 : 0.32),
                  blurRadius: _hovered ? 28 : 18,
                  spreadRadius: _hovered ? -4 : -8,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Row(
        mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment:
            widget.expand ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          if (widget.icon != null) ...[
            Icon(
              widget.icon,
              color: Colors.white,
              size: widget.dense ? 14 : 16,
            ),
            const SizedBox(width: 8),
          ],
          Text(
            widget.label,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: widget.dense ? 12.5 : 13.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
    return MouseRegion(
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: disabled ? null : widget.onPressed,
        child: widget.expand ? SizedBox(width: double.infinity, child: child) : child,
      ),
    );
  }
}

/// Headline com palavra destacada em gradiente laranja.
class PremiumGradientHeadline extends StatelessWidget {
  const PremiumGradientHeadline({
    super.key,
    required this.before,
    required this.highlight,
    this.after = '',
    this.fontSize = 38,
    this.textAlign = TextAlign.center,
  });

  final String before;
  final String highlight;
  final String after;
  final double fontSize;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return RichText(
      textAlign: textAlign,
      text: TextSpan(
        style: GoogleFonts.inter(
          color: AppColors.text,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          height: 1.1,
          letterSpacing: -1.2,
        ),
        children: [
          TextSpan(text: before),
          TextSpan(
            text: highlight,
            style: GoogleFonts.inter(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.2,
              foreground: Paint()
                ..shader = const LinearGradient(
                  colors: [Color(0xFFFB923C), Color(0xFFEA580C)],
                ).createShader(const Rect.fromLTWH(0, 0, 400, 60)),
            ),
          ),
          if (after.isNotEmpty) TextSpan(text: after),
        ],
      ),
    );
  }
}
