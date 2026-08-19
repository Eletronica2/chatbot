import 'package:flutter/material.dart';

import '../screens/backoffice_lead_proposal_flow.dart';
import '../screens/backoffice_screen.dart';
import '../screens/signup_dialog.dart';
import '../services/auth_service.dart';
import '../services/lead_service.dart';
import 'coexistence_wizard.dart';

/// Compile-time capture helper. Invisible in normal builds (`UI_AUDIT` unset).
const bool kUiAudit = bool.fromEnvironment('UI_AUDIT');

class UiAuditOverlay extends StatelessWidget {
  const UiAuditOverlay({super.key});

  static const Color _mark = Color(0xFFE11D48);

  Lead get _sampleLead => Lead(
        id: 'ui-audit',
        name: 'Lead de auditoria',
        company: 'Empresa Demo Audit',
        email: 'lead.audit@teste.local',
        whatsapp: '+55 11 90000-0000',
        objective: 'Captura visual do dialog de proposta, sem gravar dados.',
        segment: 'alimentacao',
        status: 'new',
      );

  @override
  Widget build(BuildContext context) {
    final tenantId = authService.tenantId ?? '';
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: _mark,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _btn(context, 'W1', () {
              if (tenantId.isEmpty) return;
              showCoexistenceWizard(
                context: context,
                tenantId: tenantId,
                initialStep: 0,
                onConnected: () async {},
              );
            }),
            _btn(context, 'W2', () {
              if (tenantId.isEmpty) return;
              showCoexistenceWizard(
                context: context,
                tenantId: tenantId,
                initialStep: 1,
                onConnected: () async {},
              );
            }),
            _btn(context, 'W3', () {
              if (tenantId.isEmpty) return;
              showCoexistenceWizard(
                context: context,
                tenantId: tenantId,
                initialStep: 2,
                onConnected: () async {},
              );
            }),
            _btn(context, 'PR', () {
              showLeadProposalDialog(context, _sampleLead, onChanged: () {});
            }),
            _btn(context, 'CV', () {
              showConvertLeadDialog(context, _sampleLead, onConverted: () {});
            }),
            _btn(context, 'SG', () {
              showDialog<void>(
                context: context,
                builder: (_) => const SignupDialog(),
              );
            }),
            _btn(context, 'LD', () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BackofficeScreen(
                    onLogout: () {},
                    initialAdminView: 'leads',
                  ),
                ),
              );
            }),
            _btn(context, 'NE', () {
              BackofficeScreen.showCreateTenantDialog(context);
            }),
          ],
        ),
      ),
    );
  }

  Widget _btn(BuildContext context, String id, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Semantics(
        button: true,
        label: 'audit-$id',
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: 28,
            height: 22,
            alignment: Alignment.center,
            color: const Color(0xFF7F1D1D),
            child: Text(
              id,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
