import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../utils/wa_text_editing.dart';

enum WaTemplateFieldMode { headerPlain, body, footerPlain }

class WaTemplateTextField extends StatefulWidget {
  const WaTemplateTextField({
    super.key,
    required this.controller,
    required this.labelText,
    this.helperText,
    this.mode = WaTemplateFieldMode.footerPlain,
    this.minLines = 1,
    this.maxLines = 4,
    this.errorText,
    this.maxLength,
  });

  final TextEditingController controller;
  final String labelText;
  final String? helperText;
  final String? errorText;
  final int? maxLength;
  final WaTemplateFieldMode mode;
  final int minLines;
  final int maxLines;

  @override
  State<WaTemplateTextField> createState() => _WaTemplateTextFieldState();
}

class _WaTemplateTextFieldState extends State<WaTemplateTextField> {
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  OverlayEntry? _emojiOverlay;

  @override
  void dispose() {
    _removeEmojiOverlay();
    _focusNode.dispose();
    super.dispose();
  }

  void _removeEmojiOverlay() {
    _emojiOverlay?.remove();
    _emojiOverlay = null;
  }

  void _toggleEmojiPicker() {
    if (_emojiOverlay != null) {
      _removeEmojiOverlay();
      setState(() {});
      return;
    }
    _focusNode.requestFocus();
    final overlay = Overlay.of(context);
    _emojiOverlay = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                _removeEmojiOverlay();
                setState(() {});
              },
              behavior: HitTestBehavior.translucent,
            ),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, 44),
            child: Material(
              elevation: 8,
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 320,
                height: 280,
                child: EmojiPicker(
                  onEmojiSelected: (category, emoji) {
                    WaTextEditing.insertAtSelection(widget.controller, emoji.emoji);
                  },
                  config: Config(
                    height: 280,
                    checkPlatformCompatibility: true,
                    emojiViewConfig: EmojiViewConfig(
                      backgroundColor: AppColors.surfaceAlt,
                      columns: 8,
                      emojiSizeMax: 28 * (defaultTargetPlatform == TargetPlatform.iOS ? 1.2 : 1),
                    ),
                    searchViewConfig: SearchViewConfig(
                      backgroundColor: AppColors.surface,
                      hintText: 'Buscar emoji',
                    ),
                    categoryViewConfig: CategoryViewConfig(
                      backgroundColor: AppColors.surface,
                      indicatorColor: AppColors.primary,
                      iconColor: AppColors.textSoft,
                      iconColorSelected: AppColors.primary,
                    ),
                    bottomActionBarConfig: const BottomActionBarConfig(enabled: false),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_emojiOverlay!);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isBody = widget.mode == WaTemplateFieldMode.body;
    final child = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isBody)
          _BodyFormatBar(
            controller: widget.controller,
            onEmoji: _toggleEmojiPicker,
          ),
        TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          maxLength: widget.maxLength,
          decoration: InputDecoration(
            labelText: widget.labelText,
            helperText: widget.helperText,
            errorText: widget.errorText,
            counterText: widget.maxLength != null ? null : '',
          ),
        ),
      ],
    );
    if (!isBody) return child;
    return CompositedTransformTarget(link: _layerLink, child: child);
  }
}

class _BodyFormatBar extends StatelessWidget {
  const _BodyFormatBar({required this.controller, required this.onEmoji});

  final TextEditingController controller;
  final VoidCallback onEmoji;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        spacing: 4,
        children: [
          _FmtBtn(label: 'B', tooltip: 'Negrito', onPressed: () => WaTextEditing.toggleWrap(controller, '*', '*')),
          _FmtBtn(label: 'I', tooltip: 'Itálico', onPressed: () => WaTextEditing.toggleWrap(controller, '_', '_')),
          _FmtBtn(label: 'S', tooltip: 'Riscado', onPressed: () => WaTextEditing.toggleWrap(controller, '~', '~')),
          _FmtBtn(label: '{}', tooltip: 'Monoespaçado', onPressed: () => WaTextEditing.toggleWrap(controller, '```', '```')),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Emoji',
            onPressed: onEmoji,
            icon: const Text('😀', style: TextStyle(fontSize: 18)),
          ),
          TextButton.icon(
            onPressed: () => WaTextEditing.insertVariable(controller),
            icon: const Icon(Icons.data_object_outlined, size: 16),
            label: const Text('Variável', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _FmtBtn extends StatelessWidget {
  const _FmtBtn({required this.label, required this.tooltip, required this.onPressed});

  final String label;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(36, 32),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          visualDensity: VisualDensity.compact,
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
      ),
    );
  }
}