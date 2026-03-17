import 'package:flutter/material.dart';

import '../models/flow_state.dart';

class FlowStateCard extends StatelessWidget {
  const FlowStateCard({super.key, required this.flowState});

  final FlowStateModel flowState;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.account_tree_outlined,
                size: 14, color: Color(0xFF64748B)),
            const SizedBox(width: 6),
            const Text(
              'Fluxo ativo',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Chip(
                    label: flowState.flowName,
                    bg: const Color(0xFFEEF2FF),
                    fg: const Color(0xFF4F46E5),
                  ),
                  const Spacer(),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                        color: Color(0xFF10B981), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Ativo',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(color: Color(0xFFE2E8F0), height: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text(
                    'Estado  ',
                    style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500),
                  ),
                  Flexible(
                    child: _Chip(
                      label: flowState.currentState,
                      bg: const Color(0xFFF0FDF4),
                      fg: const Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
              if (flowState.stateData.isNotEmpty) ...[  
                const SizedBox(height: 12),
                const Text(
                  'VARIÁVEIS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF94A3B8),
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 6),
                ...flowState.stateData.entries
                    .take(12)
                    .map((e) => _VarRow(k: e.key, v: e.value?.toString() ?? '')),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.bg, required this.fg});
  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(5)),
      child: Text(
        label,
        style: TextStyle(
            color: fg, fontSize: 12, fontWeight: FontWeight.w600),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _VarRow extends StatelessWidget {
  const _VarRow({required this.k, required this.v});
  final String k;
  final String v;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              k,
              style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}