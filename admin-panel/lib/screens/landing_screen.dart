import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/commercial_contact.dart';
import '../theme/app_tokens.dart';
import '../widgets/premium_ui.dart';
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
  final _scrollController = ScrollController();
  final _featuresKey = GlobalKey();
  final _solutionsKey = GlobalKey();
  final _pricingKey = GlobalKey();
  final _integrationsKey = GlobalKey();
  final _testimonialsKey = GlobalKey();
  final _contactKey = GlobalKey();
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    final shouldScroll = _scrollController.offset > 16;
    if (shouldScroll != _scrolled) {
      setState(() => _scrolled = shouldScroll);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      alignment: 0.05,
    );
  }

  void _openSignup() {
    if (widget.onSignupTap != null) {
      widget.onSignupTap!();
      return;
    }
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (_) => const SignupDialog(),
    );
  }

  Future<void> _openCommercialWhatsApp() async {
    if (!isCommercialWhatsAppConfigured) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Configure o número em lib/config/commercial_contact.dart',
            style: GoogleFonts.inter(fontSize: 13),
          ),
        ),
      );
      return;
    }
    final uri = commercialWhatsAppUri(
      prefilledMessage: 'Olá! Quero saber mais sobre o atendimento inteligente com IA.',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Não foi possível abrir o WhatsApp.',
            style: GoogleFonts.inter(fontSize: 13),
          ),
        ),
      );
    }
  }

  Future<void> _contactExpertOrSignup() async {
    if (isCommercialWhatsAppConfigured) {
      await _openCommercialWhatsApp();
      return;
    }
    _openSignup();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05060B),
      body: Stack(
        children: [
          const Positioned.fill(child: _CinematicBackdrop()),
          SafeArea(
            child: Column(
              children: [
                _LandingHeader(
                  scrolled: _scrolled,
                  onLoginTap: widget.onLoginTap,
                  onSignupTap: _openSignup,
                  onFeatures: () => _scrollTo(_featuresKey),
                  onSolutions: () => _scrollTo(_solutionsKey),
                  onPricing: () => _scrollTo(_pricingKey),
                  onIntegrations: () => _scrollTo(_integrationsKey),
                  onTestimonials: () => _scrollTo(_testimonialsKey),
                  onContact: () => _scrollTo(_contactKey),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _HeroSection(
                          onPrimary: _openSignup,
                          onSecondary: widget.onLoginTap,
                        ),
                        _MetricsStrip(),
                        const SizedBox(height: 80),
                        Padding(
                          key: _featuresKey,
                          padding: const EdgeInsets.symmetric(horizontal: 64),
                          child: const _FeaturesSection(),
                        ),
                        const SizedBox(height: 96),
                        Padding(
                          key: _solutionsKey,
                          padding: const EdgeInsets.symmetric(horizontal: 64),
                          child: const _GrowthShowcase(),
                        ),
                        const SizedBox(height: 96),
                        Padding(
                          key: _pricingKey,
                          padding: const EdgeInsets.symmetric(horizontal: 64),
                          child: _PlansSection(
                            onCta: _openSignup,
                            onExpertTap: _contactExpertOrSignup,
                          ),
                        ),
                        const SizedBox(height: 96),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 64),
                          child: _ImplantationSection(),
                        ),
                        const SizedBox(height: 96),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 64),
                          child: _DifferentiatorsSection(),
                        ),
                        const SizedBox(height: 96),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 64),
                          child: _ComparisonSection(),
                        ),
                        const SizedBox(height: 96),
                        Padding(
                          key: _integrationsKey,
                          padding: const EdgeInsets.symmetric(horizontal: 64),
                          child: const _IntegrationsBand(),
                        ),
                        const SizedBox(height: 96),
                        Padding(
                          key: _testimonialsKey,
                          padding: const EdgeInsets.symmetric(horizontal: 64),
                          child: const _TestimonialsSection(),
                        ),
                        const SizedBox(height: 96),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 64),
                          child: _FinalCta(
                            onRequestDemo: _openSignup,
                            onWhatsApp: _openCommercialWhatsApp,
                          ),
                        ),
                        const SizedBox(height: 80),
                        _LandingFooter(contactKey: _contactKey),
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

// ============================================================================
// BACKDROP CINEMATOGRÁFICO
// ============================================================================

class _CinematicBackdrop extends StatefulWidget {
  const _CinematicBackdrop();

  @override
  State<_CinematicBackdrop> createState() => _CinematicBackdropState();
}

class _CinematicBackdropState extends State<_CinematicBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 28),
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
        AnimatedAmbientLayer(
          controller: _ctrl,
          intensity: AmbientIntensity.vivid,
        ),
      ],
    );
  }
}

// ============================================================================
// HEADER FIXO
// ============================================================================

class _LandingHeader extends StatelessWidget {
  const _LandingHeader({
    required this.scrolled,
    required this.onLoginTap,
    required this.onSignupTap,
    required this.onFeatures,
    required this.onSolutions,
    required this.onPricing,
    required this.onIntegrations,
    required this.onTestimonials,
    required this.onContact,
  });

  final bool scrolled;
  final VoidCallback onLoginTap;
  final VoidCallback onSignupTap;
  final VoidCallback onFeatures;
  final VoidCallback onSolutions;
  final VoidCallback onPricing;
  final VoidCallback onIntegrations;
  final VoidCallback onTestimonials;
  final VoidCallback onContact;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.symmetric(
        horizontal: 64,
        vertical: scrolled ? 14 : 22,
      ),
      decoration: BoxDecoration(
        color: scrolled
            ? const Color(0xFF06080F).withValues(alpha: 0.82)
            : Colors.transparent,
        border: scrolled
            ? const Border(
                bottom: BorderSide(color: AppColors.borderSubtle, width: 1),
              )
            : null,
      ),
      child: Row(
        children: [
          const _BrandMark(),
          const SizedBox(width: 48),
          Expanded(
            child: Center(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  _NavLink(label: 'Recursos', onTap: onFeatures),
                  _NavLink(label: 'Soluções', onTap: onSolutions),
                  _NavLink(label: 'Preços', onTap: onPricing),
                  _NavLink(label: 'Integrações', onTap: onIntegrations),
                  _NavLink(label: 'Depoimentos', onTap: onTestimonials),
                  _NavLink(label: 'Contato', onTap: onContact),
                ],
              ),
            ),
          ),
          const SizedBox(width: 24),
          _GhostPill(label: 'Entrar', onTap: onLoginTap),
          const SizedBox(width: 12),
          _PrimaryPill(label: 'Cadastrar-se', onTap: onSignupTap),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: AppGradients.brandIcon,
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [
              BoxShadow(color: Color(0x3360A5FA), blurRadius: 18, spreadRadius: -2),
            ],
          ),
          child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 19),
        ),
        const SizedBox(width: 12),
        Text(
          'Chatbot Ops',
          style: GoogleFonts.inter(
            color: AppColors.text,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

class _NavLink extends StatefulWidget {
  const _NavLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
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
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _hovered
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            widget.label,
            style: GoogleFonts.inter(
              color: _hovered ? AppColors.text : AppColors.textMuted,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ),
    );
  }
}

class _GhostPill extends StatefulWidget {
  const _GhostPill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_GhostPill> createState() => _GhostPillState();
}

class _GhostPillState extends State<_GhostPill> {
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
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          decoration: BoxDecoration(
            color: _hovered
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: _hovered
                  ? Colors.white.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Text(
            widget.label,
            style: GoogleFonts.inter(
              color: AppColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryPill extends StatefulWidget {
  const _PrimaryPill({
    required this.label,
    required this.onTap,
    this.icon,
    this.big = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool big;

  @override
  State<_PrimaryPill> createState() => _PrimaryPillState();
}

class _PrimaryPillState extends State<_PrimaryPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final pad = widget.big
        ? const EdgeInsets.symmetric(horizontal: 26, vertical: 16)
        : const EdgeInsets.symmetric(horizontal: 22, vertical: 12);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: pad,
          decoration: BoxDecoration(
            gradient: AppGradients.premiumOrange,
            borderRadius: BorderRadius.circular(999),
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
                Icon(widget.icon, color: Colors.white, size: widget.big ? 18 : 16),
                const SizedBox(width: 8),
              ],
              Text(
                widget.label,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: widget.big ? 15 : 13,
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

// ============================================================================
// HERO
// ============================================================================

class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.onPrimary, required this.onSecondary});

  final VoidCallback onPrimary;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final compact = c.maxWidth < 1080;
        final left = _HeroCopy(onPrimary: onPrimary, onSecondary: onSecondary);
        final right = const _HeroMockup();

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 32 : 64,
            vertical: 64,
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    left,
                    const SizedBox(height: 60),
                    right,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 11, child: left),
                    const SizedBox(width: 48),
                    Expanded(flex: 12, child: right),
                  ],
                ),
        );
      },
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({required this.onPrimary, required this.onSecondary});

  final VoidCallback onPrimary;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _PillBadge(
          icon: Icons.bolt_rounded,
          label: 'IA • WhatsApp • Automação',
        ),
        const SizedBox(height: 28),
        RichText(
          text: TextSpan(
            style: GoogleFonts.inter(
              color: AppColors.text,
              fontSize: 64,
              fontWeight: FontWeight.w800,
              height: 1.02,
              letterSpacing: -2.4,
            ),
            children: [
              const TextSpan(text: 'Atendimento inteligente\n'),
              const TextSpan(text: 'que transforma\nconversas em '),
              TextSpan(
                text: 'resultados',
                style: GoogleFonts.inter(
                  fontSize: 64,
                  fontWeight: FontWeight.w800,
                  height: 1.02,
                  letterSpacing: -2.4,
                  foreground: Paint()
                    ..shader = const LinearGradient(
                      colors: [Color(0xFFFB923C), Color(0xFFEA580C)],
                    ).createShader(const Rect.fromLTWH(0, 0, 600, 80)),
                ),
              ),
              const TextSpan(text: '.'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: 520,
          child: Text(
            'Automatize respostas, organize atendimentos e aumente suas vendas com IA no WhatsApp oficial — tecnologia premium e simples de usar.',
            style: GoogleFonts.inter(
              color: AppColors.textMuted,
              fontSize: 16,
              height: 1.6,
              letterSpacing: -0.1,
            ),
          ),
        ),
        const SizedBox(height: 36),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _PrimaryPill(
              label: 'Começar agora',
              onTap: onPrimary,
              icon: Icons.arrow_forward_rounded,
              big: true,
            ),
            _SecondaryHeroBtn(label: 'Ver demonstração', onTap: onSecondary),
          ],
        ),
        const SizedBox(height: 32),
        Wrap(
          spacing: 22,
          runSpacing: 12,
          children: const [
            _Reassurance(icon: Icons.check_circle_outline, label: 'Setup em minutos'),
            _Reassurance(icon: Icons.credit_card_off_outlined, label: 'Sem cartão de crédito'),
            _Reassurance(icon: Icons.support_agent_outlined, label: 'Suporte especializado'),
          ],
        ),
      ],
    );
  }
}

class _PillBadge extends StatelessWidget {
  const _PillBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.accentBlue),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.inter(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _SecondaryHeroBtn extends StatefulWidget {
  const _SecondaryHeroBtn({
    required this.label,
    required this.onTap,
    this.icon = Icons.play_circle_outline,
  });

  final String label;
  final VoidCallback onTap;
  final IconData icon;

  @override
  State<_SecondaryHeroBtn> createState() => _SecondaryHeroBtnState();
}

class _SecondaryHeroBtnState extends State<_SecondaryHeroBtn> {
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
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: _hovered
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: _hovered
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 18, color: AppColors.text),
              const SizedBox(width: 10),
              Text(
                widget.label,
                style: GoogleFonts.inter(
                  color: AppColors.text,
                  fontSize: 15,
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

class _Reassurance extends StatelessWidget {
  const _Reassurance({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.success),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.inter(
            color: AppColors.textMuted,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _HeroMockup extends StatelessWidget {
  const _HeroMockup();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 520,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Sombra/glow lateral
          Positioned(
            top: 40,
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 30),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(40),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x666D28D9),
                      blurRadius: 120,
                      spreadRadius: -40,
                      offset: Offset(0, 40),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Painel principal
          Positioned.fill(
            child: _DashboardPanel(),
          ),
          // Avatar WhatsApp flutuante
          Positioned(
            top: -10,
            right: 24,
            child: _FloatingChip(
              icon: Icons.chat_rounded,
              gradient: const LinearGradient(
                colors: [Color(0xFF22C55E), Color(0xFF15803D)],
              ),
              size: 64,
              glow: const Color(0xFF22C55E),
            ),
          ),
          // Ícone "estrela" / IA roxo flutuante
          Positioned(
            top: 90,
            right: -12,
            child: _FloatingChip(
              icon: Icons.auto_awesome_rounded,
              gradient: const LinearGradient(
                colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
              ),
              size: 72,
              glow: const Color(0xFF8B5CF6),
            ),
          ),
          // Mini-card de gráfico flutuante
          Positioned(
            left: -10,
            bottom: 30,
            child: _FloatingChip(
              icon: Icons.bar_chart_rounded,
              gradient: const LinearGradient(
                colors: [Color(0xFFFB923C), Color(0xFFC2410C)],
              ),
              size: 56,
              glow: const Color(0xFFFB923C),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF11141D), Color(0xFF0A0C14)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: AppShadows.cinematic,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.04),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          gradient: AppGradients.brandIcon,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.auto_awesome_rounded,
                            color: Colors.white, size: 16),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Central de ação',
                        style: GoogleFonts.inter(
                          color: AppColors.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      _MockDot(color: AppColors.success),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Operação em tempo real',
                    style: GoogleFonts.inter(
                      color: AppColors.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: const [
                      Expanded(child: _MockKpi(label: 'Conversas ativas', value: '128', delta: '+12%', color: AppColors.accentBlue)),
                      SizedBox(width: 12),
                      Expanded(child: _MockKpi(label: 'IA respondendo', value: '94%', delta: 'estável', color: AppColors.success)),
                      SizedBox(width: 12),
                      Expanded(child: _MockKpi(label: 'Satisfação', value: '4.9/5', delta: 'excelente', color: AppColors.warning)),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Fluxo de atendimento',
                    style: GoogleFonts.inter(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _MockFlowSteps(),
                  const SizedBox(height: 18),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF080A12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(16),
                        child: _MiniChart(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MockDot extends StatelessWidget {
  const _MockDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'Live',
          style: GoogleFonts.inter(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _MockKpi extends StatelessWidget {
  const _MockKpi({required this.label, required this.value, required this.delta, required this.color});

  final String label;
  final String value;
  final String delta;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.inter(
              color: AppColors.text,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            delta,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MockFlowSteps extends StatelessWidget {
  const _MockFlowSteps();

  @override
  Widget build(BuildContext context) {
    final steps = [
      ('Nova mensagem', AppColors.accentBlue),
      ('IA atende', AppColors.accentPurple),
      ('Responde cliente', AppColors.success),
      ('Concluído', AppColors.primary),
    ];
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              decoration: BoxDecoration(
                color: steps[i].$2.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: steps[i].$2.withValues(alpha: 0.25)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: steps[i].$2, shape: BoxShape.circle),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    steps[i].$1,
                    style: GoogleFonts.inter(
                      color: AppColors.text,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          if (i != steps.length - 1)
            Container(
              width: 12,
              height: 1,
              color: Colors.white.withValues(alpha: 0.1),
            ),
        ],
      ],
    );
  }
}

class _MiniChart extends StatelessWidget {
  const _MiniChart();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ChartPainter(small: true),
      child: const SizedBox.expand(),
    );
  }
}

class _FloatingChip extends StatelessWidget {
  const _FloatingChip({
    required this.icon,
    required this.gradient,
    required this.size,
    required this.glow,
  });

  final IconData icon;
  final Gradient gradient;
  final double size;
  final Color glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(size / 4),
        boxShadow: [
          BoxShadow(color: glow.withValues(alpha: 0.55), blurRadius: 36, spreadRadius: -8),
          const BoxShadow(color: Color(0x55000000), blurRadius: 30, offset: Offset(0, 18)),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.42),
    );
  }
}

// ============================================================================
// MÉTRICAS
// ============================================================================

class _MetricsStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final items = const [
      ('+85%', 'de conversas resolvidas\ncom IA', AppColors.success),
      ('-70%', 'no tempo de resposta', AppColors.accentBlue),
      ('+45%', 'de aumento em vendas', AppColors.primary),
      ('24/7', 'Atendimento contínuo', AppColors.accentPurple),
      ('98%', 'de satisfação dos clientes', AppColors.accentCyan),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 64),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0B0D15), Color(0xFF080A12)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          boxShadow: const [
            BoxShadow(color: Color(0x40000000), blurRadius: 50, offset: Offset(0, 24)),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            final compact = c.maxWidth < 900;
            if (compact) {
              return Wrap(
                spacing: 24,
                runSpacing: 24,
                alignment: WrapAlignment.center,
                children: [
                  for (final item in items)
                    SizedBox(
                      width: 240,
                      child: _MetricCell(value: item.$1, label: item.$2, color: item.$3),
                    ),
                ],
              );
            }
            return Row(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  Expanded(
                    child: _MetricCell(value: items[i].$1, label: items[i].$2, color: items[i].$3),
                  ),
                  if (i != items.length - 1)
                    Container(
                      width: 1,
                      height: 60,
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.value, required this.label, required this.color});

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShaderMask(
          shaderCallback: (rect) => LinearGradient(
            colors: [color, color.withValues(alpha: 0.55)],
          ).createShader(rect),
          child: Text(
            value,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 44,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.6,
              height: 1,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: AppColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// FUNCIONALIDADES
// ============================================================================

class _FeaturesSection extends StatelessWidget {
  const _FeaturesSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _SectionEyebrow(text: 'RECURSOS', accent: AppColors.accentBlue),
        const SizedBox(height: 16),
        _SectionHeadline(
          first: 'Muito mais que um ',
          highlight: 'chatbot',
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: 620,
          child: Text(
            'Uma plataforma completa para organizar, automatizar e escalar seu atendimento — com a profundidade de um software enterprise.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: AppColors.textMuted,
              fontSize: 15,
              height: 1.6,
            ),
          ),
        ),
        const SizedBox(height: 48),
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 1280
                ? 5
                : c.maxWidth >= 1024
                    ? 3
                    : c.maxWidth >= 720
                        ? 2
                        : 1;
            const items = [
              _FeatureItem(
                icon: Icons.auto_awesome_rounded,
                color: AppColors.accentPurple,
                title: 'IA Avançada',
                description:
                    'Entende, aprende e responde como um humano. Com precisão e contexto enterprise.',
              ),
              _FeatureItem(
                icon: Icons.refresh_rounded,
                color: AppColors.accentBlue,
                title: 'Automação Total',
                description:
                    'Fluxos inteligentes, regras e respostas automáticas para qualquer cenário.',
              ),
              _FeatureItem(
                icon: Icons.hub_outlined,
                color: AppColors.success,
                title: 'Integração WhatsApp',
                description:
                    'Conecte seus números e atenda onde seus clientes já estão.',
              ),
              _FeatureItem(
                icon: Icons.insights_rounded,
                color: AppColors.primary,
                title: 'Gestão e Relatórios',
                description:
                    'Acompanhe métricas, desempenho e resultados em tempo real.',
              ),
              _FeatureItem(
                icon: Icons.support_agent_rounded,
                color: AppColors.accentCyan,
                title: 'Atendimento Humano',
                description:
                    'Transfira para atendentes quando a IA deve resolver com sensibilidade.',
              ),
            ];
            final spacing = 18.0;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final item in items)
                  SizedBox(
                    width: (c.maxWidth - spacing * (cols - 1)) / cols,
                    child: item,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _FeatureItem extends StatefulWidget {
  const _FeatureItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;

  @override
  State<_FeatureItem> createState() => _FeatureItemState();
}

class _FeatureItemState extends State<_FeatureItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()..translateByDouble(0.0, _hovered ? -4.0 : 0.0, 0.0, 1.0),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF11141D), Color(0xFF0B0D15)],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: _hovered
                ? widget.color.withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.05),
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.25),
                    blurRadius: 40,
                    spreadRadius: -10,
                    offset: const Offset(0, 18),
                  ),
                ]
              : const [
                  BoxShadow(color: Color(0x33000000), blurRadius: 30, offset: Offset(0, 14)),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: widget.color.withValues(alpha: 0.25)),
              ),
              child: Icon(widget.icon, color: widget.color, size: 22),
            ),
            const SizedBox(height: 18),
            Text(
              widget.title,
              style: GoogleFonts.inter(
                color: AppColors.text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.description,
              style: GoogleFonts.inter(
                color: AppColors.textMuted,
                fontSize: 13,
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// GROWTH SHOWCASE (gráficos + insights)
// ============================================================================

class _GrowthShowcase extends StatelessWidget {
  const _GrowthShowcase();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final compact = c.maxWidth < 1080;
        final left = const _GrowthCopy();
        final right = const _GrowthChartCard();
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: 28), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: left),
            const SizedBox(width: 36),
            Expanded(flex: 7, child: right),
          ],
        );
      },
    );
  }
}

class _GrowthCopy extends StatelessWidget {
  const _GrowthCopy();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SectionEyebrow(text: 'SOLUÇÕES', accent: AppColors.primary, alignStart: true),
        const SizedBox(height: 14),
        Text(
          'IA que impulsiona\nseu negócio',
          style: GoogleFonts.inter(
            color: AppColors.text,
            fontSize: 40,
            fontWeight: FontWeight.w800,
            height: 1.05,
            letterSpacing: -1.4,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Empresas que usam IA no WhatsApp vendem mais, atendem melhor e gastam menos com suporte. Aqui você vê o impacto real em poucas semanas.',
          style: GoogleFonts.inter(
            color: AppColors.textMuted,
            fontSize: 14.5,
            height: 1.7,
          ),
        ),
        const SizedBox(height: 22),
        ...const [
          'Mais conversas convertidas em vendas',
          'Clientes mais satisfeitos',
          'Menos trabalho manual',
          'Operação escalável',
        ].map(
          (txt) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded, size: 12, color: AppColors.success),
                ),
                const SizedBox(width: 12),
                Text(
                  txt,
                  style: GoogleFonts.inter(
                    color: AppColors.textMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GrowthChartCard extends StatelessWidget {
  const _GrowthChartCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF11141D), Color(0xFF0A0C14)],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: AppShadows.cinematic,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Conversas atendidas',
                style: GoogleFonts.inter(
                  color: AppColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.trending_up_rounded, size: 14, color: AppColors.success),
                    const SizedBox(width: 6),
                    Text(
                      '+85% no último mês',
                      style: GoogleFonts.inter(
                        color: AppColors.success,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 240,
            child: CustomPaint(
              painter: _ChartPainter(),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: const [
              Expanded(child: _ChartStat(
                label: 'Taxa de conversas com IA',
                value: '94%',
                color: AppColors.accentBlue,
                progress: 0.94,
                hint: '94% das conversas resolvidas',
              )),
              SizedBox(width: 14),
              Expanded(child: _ChartStat(
                label: 'Economia de tempo',
                value: '-70%',
                color: AppColors.primary,
                progress: 0.70,
                hint: 'menos tempo com atendimento',
              )),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChartStat extends StatelessWidget {
  const _ChartStat({
    required this.label,
    required this.value,
    required this.color,
    required this.progress,
    required this.hint,
  });

  final String label;
  final String value;
  final Color color;
  final double progress;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.inter(
              color: AppColors.text,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            style: GoogleFonts.inter(
              color: AppColors.textSoft,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({this.small = false});
  final bool small;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1;
    const horizontalLines = 4;
    for (var i = 0; i <= horizontalLines; i++) {
      final y = size.height * i / horizontalLines;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final points = <Offset>[];
    final rng = math.Random(7);
    const cols = 11;
    for (var i = 0; i < cols; i++) {
      final t = i / (cols - 1);
      final base = math.pow(t, 0.85).toDouble();
      final noise = (rng.nextDouble() - 0.5) * 0.08;
      final y = size.height * (1 - (base * 0.85 + 0.05 + noise).clamp(0.0, 0.95));
      final x = size.width * t;
      points.add(Offset(x, y));
    }

    final fillPath = Path()..moveTo(points.first.dx, size.height);
    for (final p in points) {
      fillPath.lineTo(p.dx, p.dy);
    }
    fillPath
      ..lineTo(points.last.dx, size.height)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF60A5FA).withValues(alpha: 0.35),
          const Color(0xFF60A5FA).withValues(alpha: 0.02),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF60A5FA), Color(0xFF818CF8), Color(0xFFFB923C)],
      ).createShader(Offset.zero & size)
      ..strokeWidth = small ? 2 : 2.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(linePath, linePaint);

    if (!small) {
      // Ponto de destaque
      final peak = points[points.length - 2];
      canvas.drawCircle(peak, 5.5, Paint()..color = const Color(0xFF60A5FA));
      canvas.drawCircle(peak, 10, Paint()
        ..color = const Color(0xFF60A5FA).withValues(alpha: 0.25));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ============================================================================
// PLANOS
// ============================================================================

class _PlansSection extends StatelessWidget {
  const _PlansSection({
    required this.onCta,
    required this.onExpertTap,
  });

  final VoidCallback onCta;
  final VoidCallback onExpertTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _SectionEyebrow(text: 'PLANOS', accent: AppColors.accentCyan),
        const SizedBox(height: 14),
        _SectionHeadline(first: 'Atendimento inteligente ', highlight: 'com IA'),
        const SizedBox(height: 14),
        SizedBox(
          width: 620,
          child: Text(
            'Veja o que está incluso, valores e implantação profissional. Sem jargão técnico — '
            'uma solução moderna para atender melhor e vender mais pelo WhatsApp.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: AppColors.textMuted,
              fontSize: 14.5,
              height: 1.55,
            ),
          ),
        ),
        const SizedBox(height: 40),
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 1100 ? 3 : 1;
            const items = [
              _PlanCardData(
                name: 'Start',
                tagline:
                    'Automatize seu WhatsApp com IA e agilize o atendimento do seu negócio.',
                price: 'R\$ 197',
                period: '/mês',
                features: [
                  '1 número WhatsApp',
                  'Atendimento automático inteligente',
                  'Fluxos personalizados',
                  'IA contextual básica',
                  'Painel administrativo',
                  'Até 1.000 conversas/mês',
                  'Suporte padrão',
                ],
                accent: AppColors.accentBlue,
                ctaLabel: 'Começar agora',
              ),
              _PlanCardData(
                name: 'Professional',
                tagline:
                    'Atendimento humanizado com IA avançada e automações completas para empresas em crescimento.',
                price: 'R\$ 397',
                period: '/mês',
                features: [
                  'Tudo do Start',
                  'IA contextual avançada',
                  'Smart reentry',
                  'Fluxos ilimitados',
                  'Transferência para atendente',
                  'Dashboard e métricas',
                  'Até 5.000 conversas/mês',
                  'Múltiplos atendentes',
                  'Prioridade no suporte',
                ],
                accent: AppColors.primary,
                highlighted: true,
                badge: 'Mais escolhido',
                ctaLabel: 'Quero automatizar meu atendimento',
              ),
              _PlanCardData(
                name: 'Business',
                tagline:
                    'Solução completa para operações maiores com IA avançada, integrações e atendimento escalável.',
                price: 'Sob consulta',
                period: '',
                features: [
                  'Tudo do Professional',
                  'Integrações personalizadas',
                  'Multiunidades',
                  'API',
                  'Webhooks',
                  'IA avançada personalizada',
                  'Alto volume de conversas',
                  'SLA prioritário',
                  'Suporte premium',
                ],
                accent: AppColors.accentCyan,
                expertContact: true,
                ctaLabel: 'Falar com especialista',
              ),
            ];
            const spacing = 20.0;
            if (cols == 1) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const SizedBox(height: spacing),
                    _PlanCard(
                      data: items[i],
                      onCta: onCta,
                      onExpertTap: onExpertTap,
                      stretchFeatureArea: false,
                    ),
                  ],
                ],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) SizedBox(width: spacing),
                    Expanded(
                      child: _PlanCard(
                        data: items[i],
                        onCta: onCta,
                        onExpertTap: onExpertTap,
                        stretchFeatureArea: true,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _PlanCardData {
  const _PlanCardData({
    required this.name,
    required this.tagline,
    required this.price,
    required this.period,
    required this.features,
    required this.accent,
    this.highlighted = false,
    this.badge,
    this.ctaLabel,
    this.expertContact = false,
  });

  final String name;
  final String tagline;
  final String price;
  final String period;
  final List<String> features;
  final Color accent;
  final bool highlighted;
  final String? badge;
  final String? ctaLabel;
  final bool expertContact;
}

class _PlanCard extends StatefulWidget {
  const _PlanCard({
    required this.data,
    required this.onCta,
    required this.onExpertTap,
    required this.stretchFeatureArea,
  });

  final _PlanCardData data;
  final VoidCallback onCta;
  final VoidCallback onExpertTap;
  /// Quando true (desktop em linha), o bloco de recursos ocupa espaço livre e alinha o CTA ao rodapé.
  final bool stretchFeatureArea;

  @override
  State<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<_PlanCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final highlight = widget.data.highlighted;
    final accent = widget.data.accent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()..translateByDouble(0.0, _hovered ? -6.0 : 0.0, 0.0, 1.0),
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: highlight
                ? [
                    accent.withValues(alpha: 0.22),
                    const Color(0xFF0B0D15),
                  ]
                : const [Color(0xFF11141D), Color(0xFF0B0D15)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: highlight
                ? accent.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.06),
            width: highlight ? 1.4 : 1,
          ),
          boxShadow: highlight
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.32),
                    blurRadius: 60,
                    spreadRadius: -10,
                    offset: const Offset(0, 24),
                  ),
                ]
              : (_hovered
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.22),
                        blurRadius: 36,
                        spreadRadius: -12,
                        offset: const Offset(0, 18),
                      ),
                    ]
                  : const [
                      BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 12)),
                    ]),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: widget.stretchFeatureArea ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  widget.data.name,
                  style: GoogleFonts.inter(
                    color: AppColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                if (widget.data.badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      gradient: AppGradients.premiumOrange,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.4),
                          blurRadius: 18,
                          spreadRadius: -4,
                        ),
                      ],
                    ),
                    child: Text(
                      widget.data.badge!,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              widget.data.tagline,
              style: GoogleFonts.inter(
                color: AppColors.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ShaderMask(
                  shaderCallback: (rect) => LinearGradient(
                    colors: highlight
                        ? const [Color(0xFFFB923C), Color(0xFFEA580C)]
                        : [AppColors.text, AppColors.text],
                  ).createShader(rect),
                  child: Text(
                    widget.data.price,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: widget.data.period.isEmpty ? 26 : 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.2,
                      height: 1,
                    ),
                  ),
                ),
                if (widget.data.period.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 4),
                    child: Text(
                      widget.data.period,
                      style: GoogleFonts.inter(
                        color: AppColors.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            Builder(
              builder: (context) {
                final featureColumn = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final f in widget.data.features)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.check_rounded, size: 16, color: accent),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                f,
                                style: GoogleFonts.inter(
                                  color: AppColors.textMuted,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
                if (!widget.stretchFeatureArea) return featureColumn;
                return Expanded(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: featureColumn,
                  ),
                );
              },
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: _PlanCta(
                label: widget.data.ctaLabel ?? 'Começar agora',
                highlighted: highlight,
                accent: accent,
                onTap: widget.data.expertContact ? widget.onExpertTap : widget.onCta,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCta extends StatefulWidget {
  const _PlanCta({
    required this.label,
    required this.highlighted,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool highlighted;
  final Color accent;
  final VoidCallback onTap;

  @override
  State<_PlanCta> createState() => _PlanCtaState();
}

class _PlanCtaState extends State<_PlanCta> {
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
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: widget.highlighted
                ? AppGradients.premiumOrange
                : LinearGradient(
                    colors: _hovered
                        ? [
                            widget.accent.withValues(alpha: 0.14),
                            widget.accent.withValues(alpha: 0.04),
                          ]
                        : const [Color(0x14FFFFFF), Color(0x08FFFFFF)],
                  ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.highlighted
                  ? Colors.transparent
                  : widget.accent.withValues(alpha: _hovered ? 0.5 : 0.2),
            ),
            boxShadow: widget.highlighted
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.5),
                      blurRadius: 24,
                      spreadRadius: -8,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: Text(
            widget.label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: widget.highlighted ? Colors.white : AppColors.text,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ),
    );
  }
}

class _ImplantationSection extends StatelessWidget {
  const _ImplantationSection();

  static const _items = [
    'Configuração oficial do WhatsApp',
    'Criação dos fluxos personalizados',
    'Ajuste das respostas automáticas',
    'Configuração da IA',
    'Testes completos',
    'Publicação do atendimento',
    'Treinamento inicial',
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final compact = c.maxWidth < 720;
        return ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF151A26).withValues(alpha: 0.92),
                        const Color(0xFF0C1018).withValues(alpha: 0.96),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: const SizedBox.expand(),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 28 : 40,
                  vertical: compact ? 32 : 40,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 48,
                      offset: Offset(0, 20),
                    ),
                  ],
                ),
                child: compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _bodyChildren(),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 5, child: _introColumn()),
                          const SizedBox(width: 36),
                          Expanded(flex: 6, child: _checklistColumn()),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _bodyChildren() => [
        _introColumn(),
        const SizedBox(height: 28),
        _checklistColumn(),
      ];

  Widget _introColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionEyebrow(text: 'IMPLANTAÇÃO', accent: AppColors.primary),
        const SizedBox(height: 12),
        Text(
          'Implantação personalizada',
          style: GoogleFonts.inter(
            color: AppColors.text,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1.15,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Antes da ativação do sistema, realizamos toda a configuração inicial do seu atendimento inteligente.',
          style: GoogleFonts.inter(
            color: AppColors.textMuted,
            fontSize: 14.5,
            height: 1.55,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'O investimento inicial é definido após entender seu cenário — complexidade e integrações influenciam o valor.',
          style: GoogleFonts.inter(
            color: AppColors.textSoft,
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _checklistColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'O que fazemos na entrega',
          style: GoogleFonts.inter(
            color: AppColors.text,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        for (final line in _items) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.check_circle_rounded, size: 18, color: AppColors.success),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  line,
                  style: GoogleFonts.inter(
                    color: AppColors.textMuted,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _DifferentiatorsSection extends StatelessWidget {
  const _DifferentiatorsSection();

  static final _tiles = [
    (Icons.schedule_rounded, 'Atendimento 24h'),
    (Icons.psychology_alt_outlined, 'IA humanizada'),
    (Icons.forum_outlined, 'Conversa natural'),
    (Icons.verified_outlined, 'WhatsApp oficial'),
    (Icons.support_agent_rounded, 'Transferência para humano'),
    (Icons.touch_app_outlined, 'Painel simples de usar'),
    (Icons.account_tree_outlined, 'Fluxos inteligentes'),
    (Icons.insights_outlined, 'Métricas em tempo real'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _SectionEyebrow(text: 'DIFERENCIAIS', accent: AppColors.accentBlue),
        const SizedBox(height: 14),
        _SectionHeadline(first: 'Por que escolher ', highlight: 'atendimento com IA'),
        const SizedBox(height: 14),
        Text(
          'Tecnologia moderna, linguagem natural e equipe por trás — sem parecer ferramenta amadora.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: AppColors.textMuted,
            fontSize: 14.5,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 28),
        LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final cols = w >= 1000 ? 4 : (w >= 560 ? 2 : 1);
            const gap = 12.0;
            final tileW = (w - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              alignment: WrapAlignment.center,
              children: [
                for (final t in _tiles)
                  SizedBox(
                    width: tileW,
                    child: _DiffCard(icon: t.$1, label: t.$2),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _DiffCard extends StatefulWidget {
  const _DiffCard({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  State<_DiffCard> createState() => _DiffCardState();
}

class _DiffCardState extends State<_DiffCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: _hover ? const Color(0xFF141926) : const Color(0xFF10141D),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _hover
                ? AppColors.primary.withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.06),
          ),
          boxShadow: _hover
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(widget.icon, size: 18, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.label,
                style: GoogleFonts.inter(
                  color: AppColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComparisonSection extends StatelessWidget {
  const _ComparisonSection();

  static const _traditional = [
    'Demora para responder',
    'Perde clientes na fila',
    'Respostas repetitivas e cansativas',
    'Depende totalmente do atendente online',
    'Pouca visibilidade do que está na fila ou nos pedidos',
    'Picos de demanda sobrecarregam a equipe',
  ];

  static const _withAi = [
    'Responde na hora com inteligência',
    'Atendimento 24 horas por dia',
    'Conversa natural e contextual',
    'Organiza filas e prioridades',
    'Reduz tempo médio de resposta',
    'Aumenta conversão e vendas',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _SectionEyebrow(text: 'COMPARATIVO', accent: AppColors.accentPurple),
        const SizedBox(height: 14),
        _SectionHeadline(first: 'Do tradicional ao ', highlight: 'inteligente'),
        const SizedBox(height: 36),
        LayoutBuilder(
          builder: (context, c) {
            final stack = c.maxWidth < 800;
            if (stack) {
              return Column(
                children: [
                  _CompareCard(
                    title: 'Atendimento tradicional',
                    negative: true,
                    lines: _traditional,
                    stretchBody: false,
                  ),
                  const SizedBox(height: 16),
                  _CompareCard(
                    title: 'Atendimento com IA',
                    negative: false,
                    lines: _withAi,
                    stretchBody: false,
                  ),
                ],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _CompareCard(
                      title: 'Atendimento tradicional',
                      negative: true,
                      lines: _traditional,
                      stretchBody: true,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: _CompareCard(
                      title: 'Atendimento com IA',
                      negative: false,
                      lines: _withAi,
                      stretchBody: true,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _CompareCard extends StatelessWidget {
  const _CompareCard({
    required this.title,
    required this.negative,
    required this.lines,
    required this.stretchBody,
  });

  final String title;
  final bool negative;
  final List<String> lines;
  final bool stretchBody;

  @override
  Widget build(BuildContext context) {
    final accent = negative ? const Color(0xFFEF4444) : AppColors.success;
    final linesBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  negative ? Icons.cancel_outlined : Icons.check_circle_rounded,
                  size: 17,
                  color: accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    line,
                    style: GoogleFonts.inter(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      height: 1.42,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: negative
              ? [const Color(0xFF1A1215), const Color(0xFF120E12)]
              : [const Color(0xFF101B17), const Color(0xFF0C1412)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: negative ? 0.35 : 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: stretchBody ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              color: AppColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          if (stretchBody)
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: linesBlock,
              ),
            )
          else
            linesBlock,
        ],
      ),
    );
  }
}

// ============================================================================
// INTEGRAÇÕES (faixa de logos)
// ============================================================================

class _IntegrationsBand extends StatelessWidget {
  const _IntegrationsBand();

  @override
  Widget build(BuildContext context) {
    final logos = const [
      'WhatsApp Business',
      'Stripe',
      'Hubspot',
      'Pipedrive',
      'Mercado Pago',
      'Notion',
      'Zapier',
      'Google Sheets',
    ];
    return Column(
      children: [
        Text(
          'Conecte às ferramentas que sua empresa já usa',
          style: GoogleFonts.inter(
            color: AppColors.textMuted,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 24,
          runSpacing: 24,
          alignment: WrapAlignment.center,
          children: [
            for (final name in logos)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.02),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.workspaces_outlined, size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 10),
                    Text(
                      name,
                      style: GoogleFonts.inter(
                        color: AppColors.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ============================================================================
// DEPOIMENTOS
// ============================================================================

class _TestimonialsSection extends StatelessWidget {
  const _TestimonialsSection();

  @override
  Widget build(BuildContext context) {
    final items = const [
      _Testimonial(
        text:
            'Reduzimos em 70% o tempo de atendimento e ainda aumentamos a conversão em pedidos pelo WhatsApp.',
        name: 'Marina Silva',
        role: 'COO • Bella Pizza',
        rating: 5,
      ),
      _Testimonial(
        text:
            'A IA realmente entende o cliente. Conseguimos atender 24/7 mantendo o tom da nossa marca.',
        name: 'Rafael Santos',
        role: 'Head de Operações • UtilLar',
        rating: 5,
      ),
      _Testimonial(
        text:
            'Migração simples, painel sofisticado e equipe que ajuda de verdade. Recomendo demais.',
        name: 'Camila Oliveira',
        role: 'CEO • Fábrica Fit',
        rating: 5,
      ),
    ];
    return Column(
      children: [
        const _SectionEyebrow(text: 'DEPOIMENTOS', accent: AppColors.accentSecondary),
        const SizedBox(height: 14),
        _SectionHeadline(first: 'Empresas que já transformam ', highlight: 'seu atendimento'),
        const SizedBox(height: 40),
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 1080 ? 3 : (c.maxWidth >= 720 ? 2 : 1);
            const spacing = 18.0;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              alignment: WrapAlignment.center,
              children: [
                for (final t in items)
                  SizedBox(
                    width: (c.maxWidth - spacing * (cols - 1)) / cols,
                    child: t,
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 36),
        Wrap(
          spacing: 36,
          runSpacing: 18,
          alignment: WrapAlignment.center,
          children: const [
            _LogoMark(label: 'Fábrica Fit'),
            _LogoMark(label: 'Santé'),
            _LogoMark(label: 'UtilLar'),
            _LogoMark(label: 'BellaPizza'),
            _LogoMark(label: 'Mazzeo'),
          ],
        ),
      ],
    );
  }
}

class _Testimonial extends StatelessWidget {
  const _Testimonial({
    required this.text,
    required this.name,
    required this.role,
    required this.rating,
  });

  final String text;
  final String name;
  final String role;
  final int rating;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF11141D), Color(0xFF0B0D15)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 32, offset: Offset(0, 16)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              for (var i = 0; i < rating; i++)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 18),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '"$text"',
            style: GoogleFonts.inter(
              color: AppColors.text,
              fontSize: 14,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: AppGradients.brandIcon,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    name.substring(0, 1),
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.inter(
                      color: AppColors.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    role,
                    style: GoogleFonts.inter(
                      color: AppColors.textMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.55,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.shield_moon_outlined, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.inter(
              color: AppColors.textMuted,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// CTA FINAL
// ============================================================================

class _FinalCta extends StatelessWidget {
  const _FinalCta({
    required this.onRequestDemo,
    required this.onWhatsApp,
  });

  final VoidCallback onRequestDemo;
  final VoidCallback onWhatsApp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 56),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF11141D), Color(0xFF0A0C14)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: const [
          BoxShadow(color: Color(0x666D28D9), blurRadius: 120, spreadRadius: -50, offset: Offset(0, 30)),
          BoxShadow(color: Color(0x55000000), blurRadius: 60, offset: Offset(0, 24)),
        ],
      ),
      child: Column(
        children: [
          ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              colors: [Color(0xFFF4F5F7), Color(0xFFBFC4D1)],
            ).createShader(rect),
            child: Text(
              'Transforme seu WhatsApp em um\natendimento inteligente',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w800,
                height: 1.12,
                letterSpacing: -1.1,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Automatize respostas, organize atendimentos e aumente suas vendas com IA.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: AppColors.textMuted,
              fontSize: 15,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            alignment: WrapAlignment.center,
            children: [
              _PrimaryPill(
                label: 'Solicitar demonstração',
                onTap: onRequestDemo,
                big: true,
                icon: Icons.calendar_month_rounded,
              ),
              _SecondaryHeroBtn(
                label: 'Falar no WhatsApp',
                icon: Icons.phone_android_rounded,
                onTap: onWhatsApp,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// FOOTER
// ============================================================================

class _LandingFooter extends StatelessWidget {
  const _LandingFooter({required this.contactKey});

  final GlobalKey contactKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: contactKey,
      padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 56),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final compact = c.maxWidth < 920;
              final brand = SizedBox(
                width: compact ? double.infinity : 320,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _BrandMark(),
                    const SizedBox(height: 14),
                    Text(
                      'Atendimento inteligente com IA para WhatsApp. Construído para profissionalizar sua operação e escalar resultados.',
                      style: GoogleFonts.inter(
                        color: AppColors.textMuted,
                        fontSize: 13,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _SocialBtn(icon: Icons.public_rounded),
                        const SizedBox(width: 10),
                        _SocialBtn(icon: Icons.alternate_email_rounded),
                        const SizedBox(width: 10),
                        _SocialBtn(icon: Icons.chat_bubble_outline_rounded),
                      ],
                    ),
                  ],
                ),
              );
              final cols = _footerColumns();
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    brand,
                    const SizedBox(height: 36),
                    Wrap(spacing: 40, runSpacing: 28, children: cols),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  brand,
                  const Spacer(),
                  ...cols.map((col) => Padding(
                        padding: const EdgeInsets.only(left: 56),
                        child: col,
                      )),
                ],
              );
            },
          ),
          const SizedBox(height: 48),
          const Divider(color: AppColors.borderSubtle, height: 1),
          const SizedBox(height: 22),
          Row(
            children: [
              Text(
                '© 2026 Chatbot Ops. Todos os direitos reservados.',
                style: GoogleFonts.inter(color: AppColors.textSoft, fontSize: 12),
              ),
              const Spacer(),
              Text(
                'Termos · Privacidade · LGPD',
                style: GoogleFonts.inter(color: AppColors.textSoft, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _footerColumns() {
    return [
      _FooterColumn(
        title: 'Produto',
        items: const ['Recursos', 'Integrações', 'Preços', 'Roadmap'],
      ),
      _FooterColumn(
        title: 'Empresa',
        items: const ['Sobre', 'Carreiras', 'Imprensa', 'Contato'],
      ),
      _FooterColumn(
        title: 'Recursos',
        items: const ['Blog', 'Documentação', 'Status', 'Suporte'],
      ),
    ];
  }
}

class _FooterColumn extends StatelessWidget {
  const _FooterColumn({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            color: AppColors.text,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 14),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              item,
              style: GoogleFonts.inter(
                color: AppColors.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

class _SocialBtn extends StatefulWidget {
  const _SocialBtn({required this.icon});
  final IconData icon;

  @override
  State<_SocialBtn> createState() => _SocialBtnState();
}

class _SocialBtnState extends State<_SocialBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: _hovered
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _hovered
                ? Colors.white.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Icon(widget.icon, size: 16, color: AppColors.textMuted),
      ),
    );
  }
}

// ============================================================================
// Componentes auxiliares de seção
// ============================================================================

class _SectionEyebrow extends StatelessWidget {
  const _SectionEyebrow({required this.text, required this.accent, this.alignStart = false});
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
          borderRadius: BorderRadius.circular(999),
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

class _SectionHeadline extends StatelessWidget {
  const _SectionHeadline({required this.first, required this.highlight});
  final String first;
  final String highlight;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: GoogleFonts.inter(
            color: AppColors.text,
            fontSize: 38,
            fontWeight: FontWeight.w800,
            height: 1.1,
            letterSpacing: -1.2,
          ),
          children: [
            TextSpan(text: first),
            TextSpan(
              text: highlight,
              style: GoogleFonts.inter(
                fontSize: 38,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.2,
                foreground: Paint()
                  ..shader = const LinearGradient(
                    colors: [Color(0xFFFB923C), Color(0xFFEA580C)],
                  ).createShader(const Rect.fromLTWH(0, 0, 400, 60)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
