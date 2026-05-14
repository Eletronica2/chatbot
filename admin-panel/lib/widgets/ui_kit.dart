import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_tokens.dart';

class AppPanelCard extends StatelessWidget {
  const AppPanelCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.backgroundColor,
    this.borderRadius = AppRadius.lg,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.surface,
        borderRadius: borderRadius,
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: child,
    );
  }
}

class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (action != null) ...[
          const SizedBox(width: AppSpacing.md),
          action!,
        ],
      ],
    );
  }
}

class AppStatusChip extends StatelessWidget {
  const AppStatusChip({
    super.key,
    required this.label,
    this.icon,
    this.backgroundColor = const Color(0xFF1C2740),
    this.foregroundColor = AppColors.text,
  });

  final String label;
  final IconData? icon;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: AppRadius.pill,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foregroundColor),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: foregroundColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class AppMetricCard extends StatefulWidget {
  const AppMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.helper,
    required this.icon,
    this.accent = AppColors.primary,
  });

  final String label;
  final String value;
  final String helper;
  final IconData icon;
  final Color accent;

  @override
  State<AppMetricCard> createState() => _AppMetricCardState();
}

class _AppMetricCardState extends State<AppMetricCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.01 : 1,
        duration: const Duration(milliseconds: 160),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 250,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.surfaceAlt : AppColors.surface,
            borderRadius: AppRadius.lg,
            border: Border.all(
              color: _hovered ? widget.accent.withValues(alpha: 0.5) : AppColors.border,
            ),
            boxShadow: _hovered ? AppShadows.hover : AppShadows.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: widget.accent.withValues(alpha: 0.14),
                  borderRadius: AppRadius.md,
                ),
                child: Icon(widget.icon, color: widget.accent, size: 20),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                widget.label,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                widget.value,
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                widget.helper,
                style: const TextStyle(
                  color: AppColors.textSoft,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: AppRadius.lg,
                  border: Border.all(color: AppColors.border),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: AppColors.textMuted, size: 30),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              if (action != null) ...[
                const SizedBox(height: AppSpacing.lg),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
