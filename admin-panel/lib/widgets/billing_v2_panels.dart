import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/billing_v2_service.dart';
import '../services/proposal_service.dart' show apiErrorText, billingModeLabel, kBillingModeCustomerDirect, kBillingModeSolutionPartner;
import '../theme/app_tokens.dart';

const _kText = Color(0xFFF5F7FF);
const _kMuted = Color(0xFF98A4C0);
const _kSubtle = Color(0xFF6E7B99);
const _kPanel = Color(0xFF0E1219);
const _kEdge = Color(0xFF2E3A52);

String _brl(dynamic raw) {
  final v = raw is num ? raw.toDouble() : double.tryParse('${raw ?? ''}');
  if (v == null) return '—';
  final negative = v < 0;
  final parts = v.abs().toStringAsFixed(2).split('.');
  final intPart = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return '${negative ? '-' : ''}R\$ $intPart,${parts[1]}';
}

String _int(dynamic raw) {
  final v = raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}') ?? 0;
  return '$v'.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
}

int _toInt(dynamic raw) => raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}') ?? 0;

Map<String, dynamic> _m(dynamic raw) => raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

String _date(dynamic raw) {
  final d = raw == null ? null : DateTime.tryParse('$raw');
  if (d == null) return '—';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

Color _statusColor(String? status) {
  switch (status) {
    case 'red':
      return AppColors.danger;
    case 'yellow':
      return AppColors.warning;
    case 'green':
      return AppColors.success;
    default:
      return _kMuted;
  }
}

Color _levelColor(String? level) {
  switch (level) {
    case 'warning':
      return AppColors.warning;
    case 'alert':
    case 'exhausted':
      return AppColors.danger;
    default:
      return AppColors.success;
  }
}

String _levelLabel(String? level) {
  switch (level) {
    case 'warning':
      return '80% da franquia usada';
    case 'alert':
      return '90% da franquia usada';
    case 'exhausted':
      return 'Franquia esgotada';
    default:
      return 'Dentro da franquia';
  }
}

const _kLedgerLabels = {
  'GRANT': 'Crédito concedido',
  'RESERVE': 'Reserva',
  'COMMIT': 'Consumo (entregue)',
  'RELEASE': 'Estorno (falha)',
  'EXPIRE': 'Expiração',
  'ADJUST': 'Ajuste',
};

Widget _box({required Widget child, Color? border}) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border ?? _kEdge),
      ),
      child: child,
    );

Widget _title(String text, {String? subtitle}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: const TextStyle(color: _kText, fontSize: 15, fontWeight: FontWeight.w800)),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: _kMuted, fontSize: 12, height: 1.4)),
        ],
      ],
    );

Widget _metric(String label, String value, {Color? color}) => Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF151B27),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kEdge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: _kSubtle, fontSize: 11)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: color ?? _kText, fontSize: 14, fontWeight: FontWeight.w700)),
        ],
      ),
    );

Widget _notice(String text, {Color color = _kMuted, IconData icon = Icons.info_outline_rounded}) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: _kText, fontSize: 12, height: 1.4))),
        ],
      ),
    );

Widget _usageBar(int used, int allowance, String? level) {
  final ratio = allowance <= 0 ? 0.0 : (used / allowance).clamp(0.0, 1.0);
  return ClipRRect(
    borderRadius: BorderRadius.circular(999),
    child: LinearProgressIndicator(
      value: ratio,
      minHeight: 8,
      backgroundColor: const Color(0xFF1E2636),
      valueColor: AlwaysStoppedAnimation(_levelColor(level)),
    ),
  );
}

Future<String?> _askReason(BuildContext context, {required String title, required String message, String confirm = 'Confirmar'}) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title, style: const TextStyle(color: _kText, fontSize: 16)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message, style: const TextStyle(color: _kMuted, fontSize: 13, height: 1.4)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLines: 2,
                onChanged: (_) => setLocal(() {}),
                style: const TextStyle(color: _kText),
                decoration: const InputDecoration(
                  labelText: 'Motivo (obrigatório, registrado em auditoria)',
                  labelStyle: TextStyle(color: _kMuted),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
          FilledButton(
            onPressed: ctrl.text.trim().length < 5 ? null : () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: Text(confirm),
          ),
        ],
      ),
    ),
  );
}

void _snack(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), backgroundColor: error ? AppColors.danger : AppColors.success),
  );
}

// =====================================================================
// Tenant: Créditos e consumo
// =====================================================================
class TenantBillingV2Card extends StatefulWidget {
  const TenantBillingV2Card({super.key, this.tenantId});

  final String? tenantId;

  @override
  State<TenantBillingV2Card> createState() => _TenantBillingV2CardState();
}

class _TenantBillingV2CardState extends State<TenantBillingV2Card> {
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _topups;
  List<Map<String, dynamic>> _ledger = const [];
  String? _error;
  bool _loading = true;
  String? _buying;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        billingV2Service.summary(tenantId: widget.tenantId),
        billingV2Service.topups(tenantId: widget.tenantId),
        billingV2Service.ledger(tenantId: widget.tenantId),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as Map<String, dynamic>;
        _topups = results[1] as Map<String, dynamic>;
        _ledger = results[2] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = apiErrorText(e);
      });
    }
  }

  Future<void> _buy(String itemCode, {int? units, required String label}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Comprar pacote?', style: TextStyle(color: _kText)),
        content: Text(
          '$label\nO saldo é liberado somente após a confirmação do pagamento (ambiente de teste do Stripe).',
          style: const TextStyle(color: _kMuted, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Continuar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _buying = '$itemCode:$units');
    try {
      final res = await billingV2Service.createTopupCheckout(itemCode: itemCode, units: units, tenantId: widget.tenantId);
      final url = _m(res['checkout'])['checkout_url']?.toString();
      if (url != null && url.isNotEmpty) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.platformDefault);
      } else if (mounted) {
        _snack(context, 'Compra registrada como pendente. O saldo será liberado após a confirmação do pagamento.');
      }
      await _load();
    } catch (e) {
      if (mounted) _snack(context, apiErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _buying = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _box(child: const SizedBox(height: 60, child: Center(child: CircularProgressIndicator())));
    }
    if (_error != null) {
      return _box(
        child: Row(
          children: [
            Expanded(child: Text('Créditos e consumo indisponíveis: $_error', style: const TextStyle(color: _kMuted, fontSize: 12))),
            TextButton(onPressed: _load, child: const Text('Tentar novamente')),
          ],
        ),
      );
    }
    final s = _summary ?? const {};
    final op = _m(s['operational']);
    final mk = _m(s['marketing']);
    final plan = _m(s['plan']);
    final mode = s['billing_mode']?.toString();
    final isV2 = s['is_v2_plan'] == true;
    final level = op['level']?.toString();
    final topups = _topups ?? const {};
    final opOffers = (topups['operational_offers'] as List?) ?? const [];
    final mkPacks = (topups['marketing_packs'] as List?) ?? const [];
    return _box(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _title('Créditos e consumo',
                    subtitle: 'Somente mensagens enviadas e entregues consomem franquia. Mensagens recebidas não consomem.'),
              ),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded, color: _kMuted)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _metric('Plano', isV2 ? '${plan['label'] ?? '—'} • ${_brl(s['monthly_price'])}' : 'Plano legado (sem franquia V2)'),
              _metric('Modo de cobrança Meta', billingModeLabel(mode)),
              if (s['cycle_end'] != null) _metric('Ciclo atual até', _date(s['cycle_end'])),
            ],
          ),
          if (isV2) ...[
            const SizedBox(height: 14),
            Text(
              'Mensagens operacionais: ${_int(op['used'])} de ${_int(op['allowance'])} • ${_levelLabel(level)}',
              style: TextStyle(color: _levelColor(level), fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            _usageBar(_toInt(op['used']), _toInt(op['allowance']), level),
            const SizedBox(height: 8),
            Text(
              'Disponível no plano: ${_int(op['plan_available'])} • Pacotes adicionais: ${_int(op['topup_available'])} • Em envio: ${_int(op['reserved'])}',
              style: const TextStyle(color: _kMuted, fontSize: 12),
            ),
            if (op['blocked'] == true) ...[
              const SizedBox(height: 8),
              _notice('Franquia esgotada. Envios (automáticos e manuais) estão pausados até a compra de um pacote adicional ou a renovação do ciclo. O recebimento de mensagens continua.',
                  color: AppColors.danger, icon: Icons.block_rounded),
            ],
            if (opOffers.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in opOffers.map(_m))
                    OutlinedButton.icon(
                      onPressed: _buying != null
                          ? null
                          : () => _buy(o['code'].toString(), label: '+${_int(o['operational_units'])} mensagens por ${_brl(o['price'])}'),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: Text('+${_int(o['operational_units'])} por ${_brl(o['price'])}'),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              const Text('Pacotes adicionais não expiram. Créditos do plano expiram no fim do ciclo.',
                  style: TextStyle(color: _kSubtle, fontSize: 11)),
            ],
          ],
          const SizedBox(height: 14),
          if (mode == kBillingModeSolutionPartner) ...[
            Text(
              'Créditos de campanha: ${_int(mk['available'])} disponíveis • ${_int(mk['consumed'])} consumidos • ${_int(mk['reserved'])} em envio',
              style: const TextStyle(color: _kText, fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text('Campanhas são pré-pagas (${_brl(mk['unit_price'])} por mensagem entregue).',
                style: const TextStyle(color: _kMuted, fontSize: 12)),
            if (_toInt(mk['available']) <= 0) ...[
              const SizedBox(height: 8),
              _notice('Saldo insuficiente de créditos de campanha.', color: AppColors.warning),
            ],
            if (mkPacks.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in mkPacks.map(_m))
                    OutlinedButton(
                      onPressed: _buying != null
                          ? null
                          : () => _buy((p['catalog_item_code'] ?? 'MARKETING_CREDIT_2026_10').toString(),
                              units: _toInt(p['units']), label: '${_int(p['units'])} créditos de campanha por ${_brl(p['price'])}'),
                      child: Text('${_int(p['units'])} créditos • ${_brl(p['price'])}'),
                    ),
                ],
              ),
            ],
          ] else
            _notice('Tarifas da Meta são cobradas diretamente pela Meta.'),
          if (_ledger.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Movimentações recentes', style: TextStyle(color: _kMuted, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            for (final e in _ledger.take(8))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${_date(e['created_at'])} • ${_kLedgerLabels[e['entry_type']] ?? e['entry_type']} • '
                  '${_int(e['units'])} ${e['unit_type'] == 'marketing' ? 'campanha' : 'operacional'}'
                  '${e['category'] != null ? ' • ${e['category']}' : ''}',
                  style: const TextStyle(color: _kSubtle, fontSize: 11),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// =====================================================================
// Superadmin: Assinatura e cobrança (por empresa)
// =====================================================================
class AdminTenantBillingV2Panel extends StatefulWidget {
  const AdminTenantBillingV2Panel({super.key, required this.tenantId});

  final String tenantId;

  @override
  State<AdminTenantBillingV2Panel> createState() => _AdminTenantBillingV2PanelState();
}

class _AdminTenantBillingV2PanelState extends State<AdminTenantBillingV2Panel> {
  Map<String, dynamic>? _config;
  Map<String, dynamic>? _dash;
  List<Map<String, dynamic>> _plans = const [];
  String? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AdminTenantBillingV2Panel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        billingV2Service.tenantConfig(widget.tenantId),
        billingV2Service.tenantDashboard(widget.tenantId),
        billingV2Service.catalog(),
      ]);
      if (!mounted) return;
      final catalog = results[2];
      setState(() {
        _config = results[0];
        _dash = results[1];
        _plans = ((catalog['items'] as List?) ?? const [])
            .map(_m)
            .where((i) => i['kind'] == 'plan' && i['status'] == 'active')
            .toList(growable: false);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = apiErrorText(e);
      });
    }
  }

  Future<void> _run(Future<void> Function() action, String ok) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) _snack(context, ok);
      await _load();
    } catch (e) {
      if (mounted) _snack(context, apiErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeMode(String? mode) async {
    final label = mode == null ? 'padrão global' : billingModeLabel(mode);
    final reason = await _askReason(
      context,
      title: 'Alterar modo de cobrança Meta',
      message: 'Novo modo: $label.\nMensagens já registradas mantêm o modo da época. '
          'Créditos de campanha existentes ficam guardados, mas só são usados no modo Atende Ai (créditos).',
      confirm: 'Alterar modo',
    );
    if (reason == null) return;
    await _run(() => billingV2Service.setBillingMode(widget.tenantId, mode: mode, reason: reason), 'Modo de cobrança atualizado.');
  }

  Future<void> _assignPlan() async {
    String? code = _m(_config?['config'])['plan_code']?.toString();
    code ??= _plans.isNotEmpty ? _plans.first['code'].toString() : null;
    final allowance = TextEditingController();
    final price = TextEditingController();
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final selected = _plans.where((p) => p['code'] == code).firstOrNull;
          final custom = selected?['is_custom'] == true || selected?['is_custom'] == 1;
          return AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text('Atribuir plano V2', style: TextStyle(color: _kText)),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: code,
                    dropdownColor: const Color(0xFF1A2030),
                    style: const TextStyle(color: _kText),
                    items: [
                      for (final p in _plans)
                        DropdownMenuItem(
                          value: p['code'].toString(),
                          child: Text(p['price'] == null
                              ? '${p['label']} (sob consulta)'
                              : '${p['label']} — ${_brl(p['price'])} — ${_int(p['operational_units'])} msgs'),
                        ),
                    ],
                    onChanged: (v) => setLocal(() => code = v),
                  ),
                  if (custom) ...[
                    TextField(
                      controller: allowance,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: _kText),
                      decoration: const InputDecoration(labelText: 'Franquia operacional / mês', labelStyle: TextStyle(color: _kMuted)),
                    ),
                    TextField(
                      controller: price,
                      style: const TextStyle(color: _kText),
                      decoration: const InputDecoration(labelText: 'Mensalidade (ex.: 1497.00)', labelStyle: TextStyle(color: _kMuted)),
                    ),
                  ],
                  TextField(
                    controller: reason,
                    onChanged: (_) => setLocal(() {}),
                    style: const TextStyle(color: _kText),
                    decoration: const InputDecoration(labelText: 'Motivo (obrigatório)', labelStyle: TextStyle(color: _kMuted)),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Clientes existentes não são migrados automaticamente; esta ação é explícita e auditada.',
                    style: TextStyle(color: _kSubtle, fontSize: 11),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
              FilledButton(
                onPressed: code == null || reason.text.trim().length < 5 ? null : () => Navigator.of(ctx).pop(true),
                child: const Text('Atribuir'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true || code == null) return;
    await _run(
      () => billingV2Service.assignPlan(
        widget.tenantId,
        planCode: code!,
        reason: reason.text.trim(),
        operationalAllowance: int.tryParse(allowance.text.trim()),
        monthlyPrice: price.text.trim().replaceAll(',', '.'),
      ),
      'Plano atribuído.',
    );
  }

  Future<void> _grant(String unitType) async {
    final units = TextEditingController();
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(unitType == 'marketing' ? 'Conceder créditos de campanha' : 'Conceder mensagens operacionais',
              style: const TextStyle(color: _kText)),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: units,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setLocal(() {}),
                  style: const TextStyle(color: _kText),
                  decoration: const InputDecoration(labelText: 'Quantidade', labelStyle: TextStyle(color: _kMuted)),
                ),
                TextField(
                  controller: reason,
                  onChanged: (_) => setLocal(() {}),
                  style: const TextStyle(color: _kText),
                  decoration: const InputDecoration(labelText: 'Motivo (obrigatório)', labelStyle: TextStyle(color: _kMuted)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: (int.tryParse(units.text.trim()) ?? 0) <= 0 || reason.text.trim().length < 5
                  ? null
                  : () => Navigator.of(ctx).pop(true),
              child: const Text('Conceder'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _run(
      () => billingV2Service.manualGrant(widget.tenantId,
          unitType: unitType, units: int.parse(units.text.trim()), reason: reason.text.trim()),
      'Créditos concedidos.',
    );
  }

  Future<void> _markPaid(String purchaseId) async {
    final reason = await _askReason(context,
        title: 'Marcar compra como paga', message: 'Libera o saldo desta compra (apenas uma vez).', confirm: 'Marcar como paga');
    if (reason == null) return;
    await _run(() => billingV2Service.markPurchasePaid(purchaseId, reason: reason), 'Compra liberada.');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _box(child: const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())));
    }
    if (_error != null) {
      return _box(
        child: Row(children: [
          Expanded(child: Text('Billing V2 indisponível: $_error', style: const TextStyle(color: _kMuted, fontSize: 12))),
          TextButton(onPressed: _load, child: const Text('Tentar novamente')),
        ]),
      );
    }
    final cfgEnvelope = _config ?? const {};
    final cfg = _m(cfgEnvelope['config']);
    final dash = _dash ?? const {};
    final summary = _m(dash['summary']);
    final op = _m(summary['operational']);
    final mk = _m(summary['marketing']);
    final revenue = _m(dash['revenue']);
    final costs = _m(dash['costs']);
    final messages = _m(dash['messages']);
    final status = dash['status']?.toString();
    final unknown = ((dash['unknown_components'] as List?) ?? const []).join(', ');
    final purchases = ((dash['purchases'] as List?) ?? const []).map(_m).toList();
    final effective = cfg['effective_mode']?.toString();
    final override = cfg['billing_mode']?.toString();

    return _box(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _title('Billing V2 — modo, plano e margem',
                    subtitle: cfgEnvelope['billing_v2_enabled'] == true
                        ? 'Billing V2 ativo. Unidade de cobrança: mensagem enviada e entregue.'
                        : 'Billing V2 desligado globalmente (somente leitura do novo modelo).'),
              ),
              IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh_rounded, color: _kMuted)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _metric('Modo efetivo', billingModeLabel(effective)),
              _metric('Origem do modo', override == null ? 'Padrão global (${cfgEnvelope['global_default_mode']})' : 'Definido para esta empresa'),
              _metric('Plano V2', cfg['plan_code']?.toString() ?? 'Legado (sem migração automática)'),
              _metric('Mensalidade', _brl(cfg['monthly_price'])),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _busy || effective == kBillingModeCustomerDirect && override != null
                    ? null
                    : () => _changeMode(kBillingModeCustomerDirect),
                child: const Text('Cliente paga a Meta'),
              ),
              OutlinedButton(
                onPressed: _busy || effective == kBillingModeSolutionPartner ? null : () => _changeMode(kBillingModeSolutionPartner),
                child: const Text('Atende Ai (créditos)'),
              ),
              if (override != null)
                TextButton(onPressed: _busy ? null : () => _changeMode(null), child: const Text('Voltar ao padrão global')),
              FilledButton.tonal(onPressed: _busy || _plans.isEmpty ? null : _assignPlan, child: const Text('Atribuir plano V2')),
              TextButton(onPressed: _busy ? null : () => _grant('operational'), child: const Text('+ Mensagens operacionais')),
              TextButton(onPressed: _busy ? null : () => _grant('marketing'), child: const Text('+ Créditos de campanha')),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Consumo do ciclo', style: TextStyle(color: _kMuted, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (summary['is_v2_plan'] == true) ...[
            Text('${_int(op['used'])} de ${_int(op['allowance'])} operacionais • ${_levelLabel(op['level']?.toString())}',
                style: TextStyle(color: _levelColor(op['level']?.toString()), fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            _usageBar(_toInt(op['used']), _toInt(op['allowance']), op['level']?.toString()),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _metric('Recebidas (não consomem)', _int(messages['inbound'])),
              _metric('Enviadas', _int(messages['outbound'])),
              _metric('Entregues (cobradas)', _int(messages['delivered'])),
              _metric('Falhas (estornadas)', _int(messages['failed'])),
              _metric('Pendentes', _int(messages['pending'])),
              _metric('Em reconciliação', _int(messages['pending_reconciliation']),
                  color: _toInt(messages['pending_reconciliation']) > 0 ? AppColors.warning : null),
              _metric('Pacotes adicionais', _int(op['topup_available'])),
              _metric('Créditos de campanha', '${_int(mk['available'])} disp. / ${_int(mk['consumed'])} usados'),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Receita e margem de contribuição (mês)', style: TextStyle(color: _kMuted, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _metric('Receita', _brl(revenue['total'])),
              _metric('Custo Meta (Atende Ai)', _brl(costs['meta_atende'])),
              _metric('Meta pago pelo cliente (estimativa)', _brl(costs['meta_customer_estimate'])),
              _metric('IA', costs['ai'] == null ? 'Desconhecido' : _brl(costs['ai'])),
              _metric('Taxa de pagamento', costs['payment'] == null ? 'Não configurada' : _brl(costs['payment'])),
              _metric('Impostos', costs['tax'] == null ? 'Não configurado' : _brl(costs['tax'])),
              _metric('Contribuição', _brl(dash['contribution']), color: _statusColor(status)),
              _metric('Margem', dash['margin_percent'] == null ? '—' : '${dash['margin_percent']}%', color: _statusColor(status)),
            ],
          ),
          const SizedBox(height: 8),
          _notice(
            '${dash['status_label'] ?? ''}${unknown.isNotEmpty ? ' — configure todos os custos ($unknown).' : ''}',
            color: _statusColor(status),
          ),
          if (purchases.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Compras de pacotes', style: TextStyle(color: _kMuted, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            for (final p in purchases)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_date(p['created_at'])} • ${p['catalog_item_code']} × ${_int(p['units'])} • ${_brl(p['total_amount'])} • ${p['status']}',
                        style: const TextStyle(color: _kSubtle, fontSize: 11),
                      ),
                    ),
                    if (p['status'] == 'pending')
                      TextButton(onPressed: _busy ? null : () => _markPaid(p['id'].toString()), child: const Text('Marcar paga')),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// =====================================================================
// Superadmin: Console Billing V2 (visão geral, rate cards, custos, reconciliação)
// =====================================================================
class AdminBillingV2Console extends StatefulWidget {
  const AdminBillingV2Console({super.key});

  @override
  State<AdminBillingV2Console> createState() => _AdminBillingV2ConsoleState();
}

class _AdminBillingV2ConsoleState extends State<AdminBillingV2Console> {
  String _tab = 'overview';

  @override
  Widget build(BuildContext context) {
    const tabs = [
      ('overview', 'Visão geral'),
      ('rates', 'Tarifas Meta'),
      ('costs', 'Custos e margem'),
      ('reconciliation', 'Reconciliação'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Wrap(
            spacing: 8,
            children: [
              for (final t in tabs)
                ChoiceChip(label: Text(t.$2), selected: _tab == t.$1, onSelected: (_) => setState(() => _tab = t.$1)),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: switch (_tab) {
              'rates' => const _RateCardsPanel(),
              'costs' => const _CostConfigPanel(),
              'reconciliation' => const _ReconciliationPanel(),
              _ => const _OverviewPanel(),
            },
          ),
        ),
      ],
    );
  }
}

abstract class _LoaderState<T extends StatefulWidget, D> extends State<T> {
  D? data;
  String? error;
  bool loading = true;

  Future<D> fetch();

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final d = await fetch();
      if (!mounted) return;
      setState(() {
        data = d;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = apiErrorText(e);
      });
    }
  }

  Widget guard(Widget Function(D data) builder) {
    if (loading) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    if (error != null) {
      return _box(child: Row(children: [
        Expanded(child: Text(error!, style: const TextStyle(color: _kMuted, fontSize: 12))),
        TextButton(onPressed: reload, child: const Text('Tentar novamente')),
      ]));
    }
    return builder(data as D);
  }
}

class _OverviewPanel extends StatefulWidget {
  const _OverviewPanel();

  @override
  State<_OverviewPanel> createState() => _OverviewPanelState();
}

class _OverviewPanelState extends _LoaderState<_OverviewPanel, List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> fetch() => billingV2Service.overview();

  @override
  Widget build(BuildContext context) {
    return guard((rows) => _box(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: _title('Empresas — consumo e margem do mês', subtitle: 'Receita, consumo entregue e margem de contribuição por empresa.')),
                IconButton(onPressed: reload, icon: const Icon(Icons.refresh_rounded, color: _kMuted)),
              ]),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingTextStyle: const TextStyle(color: _kMuted, fontSize: 12, fontWeight: FontWeight.w700),
                  dataTextStyle: const TextStyle(color: _kText, fontSize: 12),
                  columns: const [
                    DataColumn(label: Text('Empresa')),
                    DataColumn(label: Text('Modo')),
                    DataColumn(label: Text('Plano')),
                    DataColumn(label: Text('Operacional')),
                    DataColumn(label: Text('Campanha')),
                    DataColumn(label: Text('Receita')),
                    DataColumn(label: Text('Margem')),
                  ],
                  rows: [
                    for (final r in rows)
                      DataRow(cells: [
                        DataCell(Text('${r['name'] ?? r['tenant_id']}')),
                        DataCell(Text(r['error'] != null ? 'erro' : (r['billing_mode'] == kBillingModeSolutionPartner ? 'Créditos' : 'Meta direto'))),
                        DataCell(Text(r['is_v2_plan'] == true ? '${r['plan'] ?? '—'}' : 'Legado')),
                        DataCell(Text(r['is_v2_plan'] == true
                            ? '${_int(_m(r['operational'])['used'])}/${_int(_m(r['operational'])['allowance'])}'
                            : '—')),
                        DataCell(Text(_int(_m(r['marketing'])['available']))),
                        DataCell(Text(_brl(r['revenue']))),
                        DataCell(Text(r['margin_percent'] == null ? '${r['status_label'] ?? '—'}' : '${r['margin_percent']}%',
                            style: TextStyle(color: _statusColor(r['status']?.toString())))),
                      ]),
                  ],
                ),
              ),
            ],
          ),
        ));
  }
}

class _RateCardsPanel extends StatefulWidget {
  const _RateCardsPanel();

  @override
  State<_RateCardsPanel> createState() => _RateCardsPanelState();
}

class _RateCardsPanelState extends _LoaderState<_RateCardsPanel, List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> fetch() => billingV2Service.rateCards();

  Future<void> _newVersion() async {
    final version = TextEditingController();
    final from = TextEditingController();
    final source = TextEditingController();
    final reason = TextEditingController();
    final prices = {
      for (final c in const ['MARKETING', 'UTILITY', 'AUTHENTICATION', 'SERVICE']) c: TextEditingController(),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final valid = version.text.trim().length >= 3 &&
              DateTime.tryParse(from.text.trim()) != null &&
              reason.text.trim().length >= 5 &&
              prices.values.every((c) => double.tryParse(c.text.trim().replaceAll(',', '.')) != null);
          InputDecoration dec(String l) => InputDecoration(labelText: l, labelStyle: const TextStyle(color: _kMuted));
          return AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text('Nova vigência de tarifas Meta', style: TextStyle(color: _kText)),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Tarifas antigas nunca são editadas: cada mudança cria uma nova vigência.',
                        style: TextStyle(color: _kSubtle, fontSize: 11)),
                    TextField(controller: version, onChanged: (_) => setLocal(() {}), style: const TextStyle(color: _kText), decoration: dec('Código da versão (ex.: RATE_BR_2027_01_01)')),
                    TextField(controller: from, onChanged: (_) => setLocal(() {}), style: const TextStyle(color: _kText), decoration: dec('Vigente a partir de (AAAA-MM-DD)')),
                    for (final e in prices.entries)
                      TextField(
                        controller: e.value,
                        onChanged: (_) => setLocal(() {}),
                        style: const TextStyle(color: _kText),
                        decoration: dec('${e.key} — R\$ por mensagem entregue'),
                      ),
                    TextField(controller: source, style: const TextStyle(color: _kText), decoration: dec('Fonte oficial (URL)')),
                    TextField(controller: reason, onChanged: (_) => setLocal(() {}), style: const TextStyle(color: _kText), decoration: dec('Motivo (obrigatório)')),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
              FilledButton(onPressed: valid ? () => Navigator.of(ctx).pop(true) : null, child: const Text('Criar vigência')),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    try {
      await billingV2Service.createRateVersion({
        'version_code': version.text.trim(),
        'market': 'BR',
        'currency': 'BRL',
        'effective_from': from.text.trim(),
        if (source.text.trim().isNotEmpty) 'source_reference': source.text.trim(),
        'needs_review': true,
        'reason': reason.text.trim(),
        'rates': [
          for (final e in prices.entries) {'category': e.key, 'unit_price': e.value.text.trim().replaceAll(',', '.')},
        ],
      });
      if (mounted) _snack(context, 'Nova vigência criada.');
      await reload();
    } catch (e) {
      if (mounted) _snack(context, apiErrorText(e), error: true);
    }
  }

  Future<void> _markReviewed(Map<String, dynamic> card) async {
    final reason = await _askReason(context,
        title: 'Marcar tarifa como revisada',
        message: '${card['category']} • ${card['version_code']}: confirme que o valor foi conferido na fonte oficial da Meta.',
        confirm: 'Marcar revisada');
    if (reason == null) return;
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      await billingV2Service.markRateReviewed(_toInt(card['id']), sourceCheckedAt: today, reason: reason);
      if (mounted) _snack(context, 'Tarifa marcada como revisada.');
      await reload();
    } catch (e) {
      if (mounted) _snack(context, apiErrorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return guard((cards) {
      final pending = cards.where((c) => c['needs_review'] == true || c['needs_review'] == 1).length;
      return _box(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: _title('Tarifas Meta (rate cards)',
                    subtitle: 'Versionadas por vigência. Custo calculado sobre mensagem entregue.'),
              ),
              FilledButton.tonal(onPressed: _newVersion, child: const Text('Nova vigência')),
            ]),
            if (pending > 0) ...[
              const SizedBox(height: 10),
              _notice('$pending tarifa(s) aguardando revisão contra a fonte oficial da Meta.', color: AppColors.warning),
            ],
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingTextStyle: const TextStyle(color: _kMuted, fontSize: 12, fontWeight: FontWeight.w700),
                dataTextStyle: const TextStyle(color: _kText, fontSize: 12),
                columns: const [
                  DataColumn(label: Text('Versão')),
                  DataColumn(label: Text('Categoria')),
                  DataColumn(label: Text('R\$/entregue')),
                  DataColumn(label: Text('Vigência')),
                  DataColumn(label: Text('Situação')),
                  DataColumn(label: Text('')),
                ],
                rows: [
                  for (final c in cards)
                    DataRow(cells: [
                      DataCell(Text('${c['version_code'] ?? '—'}')),
                      DataCell(Text('${c['category']}')),
                      DataCell(Text('${c['unit_price']}')),
                      DataCell(Text('${c['effective_from']}${c['current'] == true ? ' (vigente)' : ''}')),
                      DataCell(Text(c['needs_review'] == true || c['needs_review'] == 1 ? 'Revisar' : 'Revisada',
                          style: TextStyle(
                              color: c['needs_review'] == true || c['needs_review'] == 1 ? AppColors.warning : AppColors.success))),
                      DataCell(c['needs_review'] == true || c['needs_review'] == 1
                          ? TextButton(onPressed: () => _markReviewed(c), child: const Text('Marcar revisada'))
                          : const SizedBox.shrink()),
                    ]),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

const _kCostLabels = {
  'target_margin': 'Margem alvo (fração, ex.: 0.30)',
  'payment_fee_percent': 'Taxa de pagamento (fração, ex.: 0.0399)',
  'payment_fee_fixed': 'Taxa fixa por cobrança (R\$)',
  'tax_rate': 'Impostos sobre receita (fração)',
  'ai_cost_per_operational_message': 'Custo de IA por mensagem operacional (R\$)',
  'allocated_platform_cost_per_tenant': 'Custo de plataforma por empresa/mês (R\$)',
};

class _CostConfigPanel extends StatefulWidget {
  const _CostConfigPanel();

  @override
  State<_CostConfigPanel> createState() => _CostConfigPanelState();
}

class _CostConfigPanelState extends _LoaderState<_CostConfigPanel, List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> fetch() => billingV2Service.costConfig();

  Future<void> _edit(Map<String, dynamic> row) async {
    final key = row['key'].toString();
    final value = TextEditingController(text: row['value']?.toString() ?? '');
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(_kCostLabels[key] ?? key, style: const TextStyle(color: _kText, fontSize: 15)),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: value,
                style: const TextStyle(color: _kText),
                decoration: const InputDecoration(labelText: 'Valor (vazio = desconhecido)', labelStyle: TextStyle(color: _kMuted)),
              ),
              TextField(
                controller: reason,
                onChanged: (_) => setLocal(() {}),
                style: const TextStyle(color: _kText),
                decoration: const InputDecoration(labelText: 'Motivo (obrigatório)', labelStyle: TextStyle(color: _kMuted)),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: reason.text.trim().length < 5 ? null : () => Navigator.of(ctx).pop(true),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      final raw = value.text.trim().replaceAll(',', '.');
      await billingV2Service.updateCostConfig(key, value: raw.isEmpty ? null : raw, reason: reason.text.trim());
      if (mounted) _snack(context, 'Custo atualizado.');
      await reload();
    } catch (e) {
      if (mounted) _snack(context, apiErrorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return guard((rows) {
      final unknown = rows.where((r) => r['value'] == null).length;
      return _box(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('Custos e Margin Guard',
                subtitle: 'Margem de contribuição = (preço − custos variáveis) ÷ preço. Verde só com todos os custos configurados.'),
            if (unknown > 0) ...[
              const SizedBox(height: 10),
              _notice('$unknown custo(s) desconhecido(s): margens aparecem como “Estimativa parcial”.', color: AppColors.warning),
            ],
            const SizedBox(height: 12),
            for (final r in rows)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(_kCostLabels[r['key']] ?? '${r['key']}', style: const TextStyle(color: _kText, fontSize: 13)),
                subtitle: Text(r['value'] == null ? 'Desconhecido' : '${r['value']}',
                    style: TextStyle(color: r['value'] == null ? AppColors.warning : _kMuted, fontSize: 12)),
                trailing: TextButton(onPressed: () => _edit(r), child: const Text('Editar')),
              ),
          ],
        ),
      );
    });
  }
}

class _ReconciliationPanel extends StatefulWidget {
  const _ReconciliationPanel();

  @override
  State<_ReconciliationPanel> createState() => _ReconciliationPanelState();
}

class _ReconciliationPanelState extends _LoaderState<_ReconciliationPanel, List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> fetch() => billingV2Service.reconciliation();

  Future<void> _resolve(Map<String, dynamic> row, String action) async {
    const labels = {'commit': 'Confirmar consumo', 'release': 'Estornar', 'acknowledge': 'Marcar como verificado'};
    final reason = await _askReason(context,
        title: labels[action]!, message: 'Reserva ${row['id']} (${row['tenant_id']}) — status ${row['status']}.', confirm: labels[action]!);
    if (reason == null) return;
    try {
      await billingV2Service.resolveReconciliation(row['id'].toString(),
          tenantId: row['tenant_id'].toString(), action: action, reason: reason);
      if (mounted) _snack(context, 'Reconciliação registrada.');
      await reload();
    } catch (e) {
      if (mounted) _snack(context, apiErrorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return guard((rows) => _box(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: _title('Reconciliação',
                      subtitle: 'Reservas sem status final da Meta ou com divergência. Nada é estornado automaticamente.'),
                ),
                IconButton(onPressed: reload, icon: const Icon(Icons.refresh_rounded, color: _kMuted)),
              ]),
              const SizedBox(height: 12),
              if (rows.isEmpty) const Text('Nenhuma pendência.', style: TextStyle(color: _kMuted, fontSize: 12)),
              for (final r in rows)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: _kEdge)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${r['tenant_id']} • ${r['category']} • ${r['status']} • ${_date(r['created_at'])}',
                          style: const TextStyle(color: _kText, fontSize: 12, fontWeight: FontWeight.w700)),
                      Text('${r['reconciliation_note'] ?? ''}', style: const TextStyle(color: _kMuted, fontSize: 11)),
                      Wrap(spacing: 6, children: [
                        if (r['status'] == 'pending_reconciliation' || r['status'] == 'reserved' || r['status'] == 'accepted') ...[
                          TextButton(onPressed: () => _resolve(r, 'commit'), child: const Text('Confirmar consumo')),
                          TextButton(onPressed: () => _resolve(r, 'release'), child: const Text('Estornar')),
                        ],
                        TextButton(onPressed: () => _resolve(r, 'acknowledge'), child: const Text('Verificado')),
                      ]),
                    ],
                  ),
                ),
            ],
          ),
        ));
  }
}
