import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../theme/app_tokens.dart';

/// Indicador de contexto Super Admin / empresa.
/// Não é seletor: a troca de tenant continua em Clientes.
/// Visível apenas para Super Admin (cliente final já está preso à própria empresa).
class TenantContextBadge extends StatelessWidget {
  const TenantContextBadge({super.key, this.compact = false});

  final bool compact;

  static bool get isSystemContext {
    if (!authService.isSuperadmin) return false;
    final active = authService.tenantId?.trim() ?? '';
    final home = authService.homeTenantId?.trim() ?? '';
    return active.isEmpty || active == home;
  }

  static String get label {
    if (isSystemContext) return 'Sistema';
    final friendly = authService.activeTenantDisplayName?.trim() ?? '';
    if (friendly.isNotEmpty) return 'Empresa: $friendly';
    final id = authService.tenantId?.trim() ?? '';
    if (id.isEmpty) return 'Empresa';
    return 'Empresa: $id';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: authService,
      builder: (context, _) {
        if (!authService.isSuperadmin) {
          return const SizedBox.shrink();
        }

        final system = isSystemContext;
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: compact ? 168 : 260),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 10,
              vertical: compact ? 5 : 6,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: AppRadius.pill,
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: system ? AppColors.primary : AppColors.accentSecondary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      color: AppColors.textMuted,
                      fontSize: compact ? 11 : 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
