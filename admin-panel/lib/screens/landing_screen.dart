import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/commercial_contact.dart';
import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import '../widgets/brand_mark.dart';
import '../widgets/public_surface.dart';
import 'signup_dialog.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({
    super.key,
    required this.onLoginTap,
    this.onSignupTap,
  });

  final VoidCallback onLoginTap;
  final VoidCallback? onSignupTap;

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final _scroll = ScrollController();
  final _howKey = GlobalKey();
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final next = _scroll.offset > 12;
      if (next != _scrolled) setState(() => _scrolled = next);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _openSignup() {
    if (widget.onSignupTap != null) {
      widget.onSignupTap!();
      return;
    }
    showAppDialog(
      context: context,
      builder: (_) => const SignupDialog(),
    );
  }

  Future<void> _openCommercialWhatsApp() async {
    if (!isCommercialWhatsAppConfigured) {
      _openSignup();
      return;
    }
    final uri = commercialWhatsAppUri(
      prefilledMessage: 'Olá! Quero saber mais sobre o Atenda Ai.',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o WhatsApp.')),
      );
    }
  }

  void _scrollToHow() {
    final ctx = _howKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: AppMotion.pageOf(context),
      curve: AppMotion.pageCurve,
      alignment: 0.08,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(child: PublicAtmosphere(vivid: true)),
          SafeArea(
            child: Column(
              children: [
                _Header(
                  elevated: _scrolled,
                  onLogin: widget.onLoginTap,
                  onStart: _openSignup,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scroll,
                    child: Column(
                      children: [
                        _Hero(
                          onStart: _openSignup,
                          onSecondary: _scrollToHow,
                        ),
                        const _ProductPreview(),
                        const _Benefits(),
                        KeyedSubtree(key: _howKey, child: const _HowItWorks()),
                        const _Handoff(),
                        _FinalCta(
                          onStart: _openSignup,
                          onWhatsApp: isCommercialWhatsAppConfigured
                              ? _openCommercialWhatsApp
                              : null,
                        ),
                        _Footer(onLogin: widget.onLoginTap, onStart: _openSignup),
                      ],
                    ),
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

class _Header extends StatelessWidget {
  const _Header({
    required this.elevated,
    required this.onLogin,
    required this.onStart,
  });

  final bool elevated;
  final VoidCallback onLogin;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    return AnimatedContainer(
      duration: AppMotion.hoverOf(context),
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 24),
      decoration: BoxDecoration(
        color: elevated
            ? AppColors.surface.withValues(alpha: 0.92)
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: elevated ? AppColors.border : Colors.transparent,
          ),
        ),
      ),
      child: Row(
        children: [
          const BrandLockup(),
          const Spacer(),
          TextButton(
            onPressed: onLogin,
            child: Text(
              'Entrar',
              style: GoogleFonts.manrope(
                color: AppColors.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          PublicPrimaryButton(
            label: compact ? 'Começar' : 'Começar agora',
            onTap: onStart,
            height: 40,
            icon: compact ? null : Icons.arrow_forward_rounded,
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.onStart, required this.onSecondary});

  final VoidCallback onStart;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final tight = width < 720;
    final headlineSize = width < 400
        ? 28.0
        : width < 800
            ? 36.0
            : 52.0;

    return PublicFadeIn(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          tight ? 20 : 24,
          tight ? 28 : 48,
          tight ? 20 : 24,
          8,
        ),
        child: Center(
          child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  'Atendimento · Automação · WhatsApp',
                  style: GoogleFonts.manrope(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text.rich(
                TextSpan(
                  style: GoogleFonts.manrope(
                    color: AppColors.text,
                    fontSize: headlineSize,
                    fontWeight: FontWeight.w700,
                    height: 1.12,
                    letterSpacing: -1.2,
                  ),
                  children: [
                    const TextSpan(
                      text: 'Transforme seu WhatsApp em atendimento que ',
                    ),
                    TextSpan(
                      text: 'trabalha por você.',
                      style: GoogleFonts.manrope(
                        fontSize: headlineSize,
                        fontWeight: FontWeight.w700,
                        height: 1.12,
                        letterSpacing: -1.2,
                        foreground: Paint()
                          ..shader = const LinearGradient(
                            colors: [Color(0xFFA4E6FF), Color(0xFFCFBDFF)],
                          ).createShader(const Rect.fromLTWH(0, 0, 520, 80)),
                      ),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Text(
                  'Organize conversas, automatize o que se repete e passe para um humano quando a situação pedir. Tudo no WhatsApp da sua empresa.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    color: AppColors.textMuted,
                    fontSize: tight ? 14 : 16,
                    height: 1.55,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  PublicPrimaryButton(
                    label: 'Começar agora',
                    onTap: onStart,
                    expand: tight,
                  ),
                  PublicGhostButton(
                    label: 'Como funciona',
                    onTap: onSecondary,
                    expand: tight,
                  ),
                ],
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

class _ProductPreview extends StatelessWidget {
  const _ProductPreview();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final showInbox = width >= 800;
    return Padding(
      padding: EdgeInsets.fromLTRB(width < 720 ? 16 : 32, 40, width < 720 ? 16 : 32, 24),
      child: Center(
        child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 40,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: width < 720 ? 420 : 480,
              child: Column(
                children: [
                  Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: const BoxDecoration(
                      color: AppColors.backgroundElevated,
                      border: Border(bottom: BorderSide(color: AppColors.border)),
                    ),
                    child: Row(
                      children: [
                        _dot(const Color(0xFF3C494E)),
                        const SizedBox(width: 6),
                        _dot(const Color(0xFF3C494E)),
                        const SizedBox(width: 6),
                        _dot(const Color(0xFF3C494E)),
                        const SizedBox(width: 12),
                        Text(
                          'Conversas',
                          style: GoogleFonts.manrope(
                            color: AppColors.textSoft,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        if (showInbox) const SizedBox(width: 260, child: _MockInbox()),
                        if (showInbox)
                          const VerticalDivider(width: 1, color: AppColors.border),
                        const Expanded(child: _MockChat()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  static Widget _dot(Color color) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class _MockInbox extends StatelessWidget {
  const _MockInbox();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.sidebar,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Caixa de entrada',
              style: GoogleFonts.manrope(
                color: AppColors.text,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            const _MockRow(
              initials: '14',
              title: '1778815214',
              preview: 'Qual o horário de funcionamento?',
              selected: true,
              status: 'IA ativa',
              statusColor: AppColors.accentSecondary,
            ),
            const _MockRow(
              initials: '47',
              title: '+55 34 99266-5547',
              preview: 'Quero fazer um pedido',
              status: 'Aguardando humano',
              statusColor: AppColors.warning,
            ),
            const _MockRow(
              initials: 'og',
              title: 'Cliente',
              preview: 'Olá, ainda estão abertos?',
              status: 'IA ativa',
              statusColor: AppColors.accentSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _MockRow extends StatelessWidget {
  const _MockRow({
    required this.initials,
    required this.title,
    required this.preview,
    required this.status,
    required this.statusColor,
    this.selected = false,
  });

  final String initials;
  final String title;
  final String preview;
  final String status;
  final Color statusColor;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: selected ? AppColors.primary.withValues(alpha: 0.10) : null,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            width: 2,
            color: selected ? AppColors.primary : Colors.transparent,
          ),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: AppColors.primary.withValues(alpha: 0.16),
            child: Text(
              initials,
              style: GoogleFonts.manrope(
                color: AppColors.primarySoft,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    color: AppColors.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  preview,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
                Text(
                  status,
                  style: GoogleFonts.manrope(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
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

class _MockChat extends StatelessWidget {
  const _MockChat();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Column(
        children: [
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.18),
                  child: Text(
                    '14',
                    style: GoogleFonts.manrope(
                      color: AppColors.primarySoft,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '1778815214',
                      style: GoogleFonts.manrope(
                        color: AppColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'IA ativa',
                      style: GoogleFonts.manrope(
                        color: AppColors.accentSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _bubble(
                      'Boa noite, qual horário de funcionamento?',
                      inbound: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _bubble(
                      'Funcionamos de segunda a sábado, das 18h às 23h. Posso ajudar com o cardápio?',
                      inbound: false,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Digite uma resposta para enviar ao cliente...',
                      style: GoogleFonts.manrope(
                        color: AppColors.textSoft,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Enviar',
                      style: GoogleFonts.manrope(
                        color: AppColors.onPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(String text, {required bool inbound}) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: inbound ? AppColors.surface : AppColors.surfaceAlt,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(inbound ? 4 : 14),
            bottomRight: Radius.circular(inbound ? 14 : 4),
          ),
          border: Border.all(
            color: inbound
                ? AppColors.border
                : AppColors.primary.withValues(alpha: 0.28),
          ),
        ),
        child: Text(
          text,
          style: GoogleFonts.manrope(
            color: AppColors.text,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class _Benefits extends StatelessWidget {
  const _Benefits();

  @override
  Widget build(BuildContext context) {
    final tight = MediaQuery.sizeOf(context).width < 800;
    const items = [
      (
        Icons.forum_outlined,
        'Tudo em um só lugar',
        'A equipe vê as conversas do WhatsApp em uma caixa de entrada, com histórico e status de cada atendimento.',
      ),
      (
        Icons.auto_awesome_outlined,
        'O que se repete, automático',
        'Automações respondem, encaminham e seguem o fluxo da empresa — inclusive fora do horário comercial.',
      ),
      (
        Icons.support_agent_outlined,
        'Humano na hora certa',
        'Quando o cliente precisa de alguém, a conversa passa para a equipe sem perder o que já foi dito.',
      ),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(tight ? 20 : 32, 56, tight ? 20 : 32, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: Column(
          children: [
            Text(
              'Feito para a operação, não para impressionar.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                color: AppColors.text,
                fontSize: tight ? 24 : 32,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Menos filas perdidas. Mais conversas resolvidas no WhatsApp.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                color: AppColors.textMuted,
                fontSize: 15,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            if (tight)
              Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    _BenefitCard(
                      icon: items[i].$1,
                      title: items[i].$2,
                      body: items[i].$3,
                    ),
                  ],
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const SizedBox(width: 16),
                    Expanded(
                      child: _BenefitCard(
                        icon: items[i].$1,
                        title: items[i].$2,
                        body: items[i].$3,
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _BenefitCard extends StatelessWidget {
  const _BenefitCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primarySoft, size: 22),
          const SizedBox(height: 14),
          Text(
            title,
            style: GoogleFonts.manrope(
              color: AppColors.text,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: GoogleFonts.manrope(
              color: AppColors.textMuted,
              fontSize: 14,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    final tight = MediaQuery.sizeOf(context).width < 800;
    const steps = [
      (
        '1',
        'Conte o que sua empresa precisa',
        'O cadastro leva poucos minutos. O time usa essas informações para montar o atendimento.',
      ),
      (
        '2',
        'Conecte o WhatsApp da empresa',
        'A conta entra pelo modelo oficial da Meta — sem sessão improvisada no celular.',
      ),
      (
        '3',
        'Automatize e atenda no painel',
        'Fluxos, templates e a caixa de entrada ficam prontos para o dia a dia da equipe.',
      ),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(tight ? 20 : 32, 56, tight ? 20 : 32, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: Column(
          children: [
            Text(
              'Do interesse à operação.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                color: AppColors.text,
                fontSize: tight ? 24 : 32,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: 32),
            Builder(
              builder: (context) {
                Widget stepCol(int i) {
                  return Column(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.4),
                          ),
                          color: AppColors.surface,
                        ),
                        child: Text(
                          steps[i].$1,
                          style: GoogleFonts.manrope(
                            color: AppColors.primarySoft,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        steps[i].$2,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(
                          color: AppColors.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        steps[i].$3,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(
                          color: AppColors.textMuted,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ],
                  );
                }

                if (tight) {
                  return Column(
                    children: [
                      for (var i = 0; i < steps.length; i++) ...[
                        if (i > 0) const SizedBox(height: 20),
                        stepCol(i),
                      ],
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < steps.length; i++) ...[
                      if (i > 0) const SizedBox(width: 20),
                      Expanded(child: stepCol(i)),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Handoff extends StatelessWidget {
  const _Handoff();

  @override
  Widget build(BuildContext context) {
    final tight = MediaQuery.sizeOf(context).width < 800;
    final copy = Column(
      crossAxisAlignment:
          tight ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          'IA quando cabe. Humano quando importa.',
          textAlign: tight ? TextAlign.center : TextAlign.start,
          style: GoogleFonts.manrope(
            color: AppColors.text,
            fontSize: tight ? 24 : 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Automações e IA cobrem o volume do dia a dia. Se o cliente precisa de alguém, a conversa vai para a equipe — no mesmo histórico.',
          textAlign: tight ? TextAlign.center : TextAlign.start,
          style: GoogleFonts.manrope(
            color: AppColors.textMuted,
            fontSize: 15,
            height: 1.55,
          ),
        ),
      ],
    );

    final visual = Column(
      children: [
        _handoffTile(
          icon: Icons.auto_awesome_rounded,
          color: AppColors.accentSecondary,
          title: 'Automação e IA',
          body: 'Respostas, horários, cardápio e encaminhamento.',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Icon(Icons.south_rounded, color: AppColors.textSoft, size: 18),
        ),
        _handoffTile(
          icon: Icons.support_agent_rounded,
          color: AppColors.warning,
          title: 'Atendimento humano',
          body: 'A equipe assume com o contexto da conversa.',
          highlight: true,
        ),
      ],
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(tight ? 20 : 32, 56, tight ? 20 : 32, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: tight
            ? Column(children: [copy, const SizedBox(height: 24), visual])
            : Row(
                children: [
                  Expanded(child: copy),
                  const SizedBox(width: 40),
                  Expanded(child: visual),
                ],
              ),
      ),
    );
  }

  Widget _handoffTile({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
    bool highlight = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.primary.withValues(alpha: 0.08)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight
              ? AppColors.primary.withValues(alpha: 0.28)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.16),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.manrope(
                    color: AppColors.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                Text(
                  body,
                  style: GoogleFonts.manrope(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    height: 1.4,
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

class _FinalCta extends StatelessWidget {
  const _FinalCta({required this.onStart, this.onWhatsApp});

  final VoidCallback onStart;
  final VoidCallback? onWhatsApp;

  @override
  Widget build(BuildContext context) {
    final tight = MediaQuery.sizeOf(context).width < 720;
    return Padding(
      padding: EdgeInsets.fromLTRB(tight ? 20 : 32, 48, tight ? 20 : 32, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: tight ? 20 : 40,
            vertical: tight ? 32 : 40,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Text(
                'Pronto para organizar o WhatsApp da sua empresa?',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  color: AppColors.text,
                  fontSize: tight ? 22 : 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Fale com a gente e comece pelo atendimento que você já tem hoje.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  color: AppColors.textMuted,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              PublicPrimaryButton(
                label: 'Começar agora',
                onTap: onStart,
                expand: tight,
              ),
              if (onWhatsApp != null) ...[
                const SizedBox(height: 12),
                PublicGhostButton(
                  label: 'Falar no WhatsApp',
                  onTap: onWhatsApp!,
                  expand: tight,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.onLogin, required this.onStart});

  final VoidCallback onLogin;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final tight = MediaQuery.sizeOf(context).width < 720;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(tight ? 20 : 32, 28, tight ? 20 : 32, 32),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: Flex(
          direction: tight ? Axis.vertical : Axis.horizontal,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandMark(size: 22),
                const SizedBox(width: 8),
                Text(
                  '© 2026 Atenda Ai',
                  style: GoogleFonts.manrope(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            if (tight) const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: onLogin,
                  child: Text(
                    'Entrar',
                    style: GoogleFonts.manrope(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onStart,
                  child: Text(
                    'Começar agora',
                    style: GoogleFonts.manrope(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
