import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Dados espelhando o payload do wizard (sem duplicar lógica de envio).
class TemplatePhonePreviewData {
  TemplatePhonePreviewData({
    required this.businessName,
    this.headerFormat = 'NONE',
    this.headerText = '',
    this.bodyResolved = '',
    this.footerText = '',
    this.buttons = const [],
    this.timeLabel = '12:00',
  });

  final String businessName;
  final String headerFormat;
  final String headerText;
  final String bodyResolved;
  final String footerText;
  final List<TemplatePreviewButton> buttons;
  final String timeLabel;
}

class TemplatePreviewButton {
  TemplatePreviewButton({required this.type, required this.label});

  final String type;
  final String label;
}

class WhatsAppTemplatePhonePreviewFrame extends StatelessWidget {
  const WhatsAppTemplatePhonePreviewFrame({
    super.key,
    required this.data,
    this.onExpand,
    this.minScale = 0.72,
    this.maxScale = 1.18,
  });

  final TemplatePhonePreviewData data;
  final VoidCallback? onExpand;
  final double minScale;
  final double maxScale;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite ? constraints.maxWidth : WhatsAppTemplatePhonePreview.designWidth;
        final maxH = constraints.maxHeight.isFinite ? constraints.maxHeight : WhatsAppTemplatePhonePreview.designHeight;
        final scale = math
            .min(maxW / WhatsAppTemplatePhonePreview.designWidth, maxH / WhatsAppTemplatePhonePreview.designHeight)
            .clamp(minScale, maxScale);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: WhatsAppTemplatePhonePreview.designWidth * scale,
                height: WhatsAppTemplatePhonePreview.designHeight * scale,
                child: FittedBox(
                  fit: BoxFit.fill,
                  alignment: Alignment.topCenter,
                  child: WhatsAppTemplatePhonePreview(data: data),
                ),
              ),
            ),
            if (onExpand != null)
              Positioned(
                right: 0,
                top: 0,
                child: IconButton(
                  tooltip: 'Ampliar preview',
                  visualDensity: VisualDensity.compact,
                  onPressed: onExpand,
                  icon: Icon(Icons.open_in_full_rounded, color: AppColors.textSoft, size: 20),
                ),
              ),
          ],
        );
      },
    );
  }
}

class WhatsAppTemplatePhonePreview extends StatelessWidget {
  const WhatsAppTemplatePhonePreview({
    super.key,
    required this.data,
  });

  final TemplatePhonePreviewData data;

  static const double designWidth = 312;
  static const double designHeight = designWidth * 2.05;

  static const _waBg = Color(0xFFECE5DD);
  static const _waBubble = Color(0xFFFFFFFF);
  static const _waHeader = Color(0xFF075E54);
  static const _waSub = Color(0xFF667781);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: designWidth,
      height: designHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            width: 3,
            color: AppColors.primary.withValues(alpha: 0.65),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.accentSecondary.withValues(alpha: 0.22),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(29),
          child: ColoredBox(
            color: Colors.black,
            child: Column(
              children: [
                _StatusBar(time: data.timeLabel),
                _ChatAppBar(name: data.businessName),
                Expanded(child: _ChatArea(data: data)),
                _InputBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.time});
  final String time;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Text(time, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          const Spacer(),
          Icon(Icons.signal_cellular_alt_rounded, color: AppColors.primarySoft, size: 15),
          const SizedBox(width: 4),
          Icon(Icons.wifi_rounded, color: AppColors.primarySoft, size: 15),
          const SizedBox(width: 4),
          Icon(Icons.battery_full_rounded, color: AppColors.primarySoft, size: 15),
        ],
      ),
    );
  }
}

class _ChatAppBar extends StatelessWidget {
  const _ChatAppBar({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: WhatsAppTemplatePhonePreview._waHeader,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Row(
        children: [
          const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 17),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 19,
            backgroundColor: AppColors.primary,
            child: Text(
              name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'A',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isNotEmpty ? name : 'Sua empresa',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'conta comercial',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12),
                ),
              ],
            ),
          ),
          Icon(Icons.videocam_rounded, color: Colors.white.withValues(alpha: 0.9), size: 21),
          const SizedBox(width: 14),
          Icon(Icons.call_rounded, color: Colors.white.withValues(alpha: 0.9), size: 19),
        ],
      ),
    );
  }
}

class _ChatArea extends StatelessWidget {
  const _ChatArea({required this.data});
  final TemplatePhonePreviewData data;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: WhatsAppTemplatePhonePreview._waBg)),
        Positioned.fill(child: CustomPaint(painter: _WaDoodlePainter())),
        ListView(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: WhatsAppTemplatePhonePreview.designWidth * 0.9),
                child: _IncomingBubble(data: data),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _WaDoodlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFCDC5BD)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    const step = 36.0;
    for (var x = 0.0; x < size.width; x += step) {
      for (var y = 0.0; y < size.height; y += step) {
        canvas.drawCircle(Offset(x + step / 2, y + step / 2), 1.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _IncomingBubble extends StatelessWidget {
  const _IncomingBubble({required this.data});
  final TemplatePhonePreviewData data;

  @override
  Widget build(BuildContext context) {
    final hasHeader = data.headerFormat == 'TEXT' && data.headerText.trim().isNotEmpty;
    final hasFooter = data.footerText.trim().isNotEmpty;
    final validButtons = data.buttons.where((b) => b.label.trim().isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: WhatsAppTemplatePhonePreview._waBubble,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1))],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(11, 9, 11, 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasHeader)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      data.headerText.trim(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111B21),
                      ),
                    ),
                  ),
                _WaFormattedText(
                  text: data.bodyResolved.isNotEmpty
                      ? data.bodyResolved
                      : 'Digite o corpo da mensagem…',
                  muted: data.bodyResolved.isEmpty,
                ),
                if (hasFooter) ...[
                  const SizedBox(height: 8),
                  Text(
                    data.footerText.trim(),
                    style: const TextStyle(fontSize: 13, color: WhatsAppTemplatePhonePreview._waSub),
                  ),
                ],
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    data.timeLabel,
                    style: const TextStyle(fontSize: 11, color: WhatsAppTemplatePhonePreview._waSub),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (validButtons.isNotEmpty) ...[
          const SizedBox(height: 4),
          DecoratedBox(
            decoration: BoxDecoration(
              color: WhatsAppTemplatePhonePreview._waBubble,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                for (var i = 0; i < validButtons.length; i++) ...[
                  if (i > 0) const Divider(height: 1, thickness: 0.6, color: Color(0xFFE9EDEF)),
                  _PreviewButtonRow(button: validButtons[i]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PreviewButtonRow extends StatelessWidget {
  const _PreviewButtonRow({required this.button});
  final TemplatePreviewButton button;

  IconData get _icon {
    switch (button.type) {
      case 'URL':
        return Icons.open_in_new_rounded;
      case 'PHONE_NUMBER':
        return Icons.call_rounded;
      case 'COPY_CODE':
        return Icons.content_copy_rounded;
      default:
        return Icons.reply_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_icon, size: 17, color: const Color(0xFF00A884)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              button.label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF00A884),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WaFormattedText extends StatelessWidget {
  const _WaFormattedText({required this.text, this.muted = false});

  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontSize: 15.5,
      height: 1.38,
      color: muted ? WhatsAppTemplatePhonePreview._waSub : const Color(0xFF111B21),
    );
    return Text.rich(
      TextSpan(children: _spans(text, base)),
      style: base,
    );
  }

  static List<InlineSpan> _spans(String raw, TextStyle base) {
    final spans = <InlineSpan>[];
    final re = RegExp(r'\*([^*]+)\*|_([^_]+)_|~([^~]+)~|```([^`]+)```');
    var start = 0;
    for (final m in re.allMatches(raw)) {
      if (m.start > start) spans.add(TextSpan(text: raw.substring(start, m.start)));
      if (m.group(1) != null) {
        spans.add(TextSpan(text: m.group(1), style: base.copyWith(fontWeight: FontWeight.w700)));
      } else if (m.group(2) != null) {
        spans.add(TextSpan(text: m.group(2), style: base.copyWith(fontStyle: FontStyle.italic)));
      } else if (m.group(3) != null) {
        spans.add(TextSpan(text: m.group(3), style: base.copyWith(decoration: TextDecoration.lineThrough)));
      } else if (m.group(4) != null) {
        spans.add(TextSpan(
          text: m.group(4),
          style: base.copyWith(fontFamily: 'monospace', backgroundColor: const Color(0xFFF0F2F5)),
        ));
      }
      start = m.end;
    }
    if (start < raw.length) spans.add(TextSpan(text: raw.substring(start)));
    return spans.isEmpty ? [TextSpan(text: raw)] : spans;
  }
}

class _InputBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF0F2F5),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: Row(
        children: [
          const Icon(Icons.emoji_emotions_outlined, color: WhatsAppTemplatePhonePreview._waSub, size: 23),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Text('Mensagem', style: TextStyle(color: WhatsAppTemplatePhonePreview._waSub, fontSize: 14)),
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.mic_rounded, color: WhatsAppTemplatePhonePreview._waSub, size: 23),
        ],
      ),
    );
  }
}