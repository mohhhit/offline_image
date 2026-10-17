import 'package:flutter/material.dart';

class PromptInputBar extends StatefulWidget {
  final bool isGenerating;
  final VoidCallback? onStop;
  final Function({
    required String prompt,
    String? negativePrompt,
    double cfgScale,
    int steps,
    int seed,
  }) onSubmit;

  const PromptInputBar({
    super.key,
    required this.isGenerating,
    required this.onSubmit,
    this.onStop,
  });

  @override
  State<PromptInputBar> createState() => _PromptInputBarState();
}

class _PromptInputBarState extends State<PromptInputBar> {
  final _promptController = TextEditingController();
  final _negativePromptController = TextEditingController();

  bool _showSettings = false;
  double _cfgScale = 7.0;
  int _steps = 20;

  @override
  void dispose() {
    _promptController.dispose();
    _negativePromptController.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _promptController.text.trim();
    if (text.isEmpty || widget.isGenerating) return;

    final negative = _negativePromptController.text.trim();

    widget.onSubmit(
      prompt: text,
      negativePrompt: negative.isNotEmpty ? negative : null,
      cfgScale: _cfgScale,
      steps: _steps,
      seed: -1, // randomized seed
    );

    _promptController.clear();
    setState(() {
      _showSettings = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_showSettings) _buildSettingsPanel(theme),
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    _showSettings ? Icons.tune_rounded : Icons.tune_outlined,
                    color: _showSettings
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  tooltip: 'Inference Parameters',
                  onPressed: () {
                    setState(() {
                      _showSettings = !_showSettings;
                    });
                  },
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: _promptController,
                      enabled: !widget.isGenerating,
                      maxLines: 4,
                      minLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _handleSend(),
                      decoration: const InputDecoration(
                        hintText: 'Describe an image to generate offline...',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: widget.isGenerating
                      ? IconButton.styleFrom(
                          backgroundColor: theme.colorScheme.error,
                          foregroundColor: theme.colorScheme.onError,
                        )
                      : null,
                  tooltip: widget.isGenerating ? 'Stop Generation' : 'Generate Image',
                  onPressed: widget.isGenerating ? widget.onStop : _handleSend,
                  icon: widget.isGenerating
                      ? const Icon(Icons.stop_rounded, size: 22)
                      : const Icon(Icons.arrow_upward_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsPanel(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Negative Prompt',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _negativePromptController,
            decoration: InputDecoration(
              hintText: 'blurry, low quality, distorted, extra limbs...',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 320;
              if (isNarrow) {
                return Column(
                  children: [
                    _buildStepSlider(theme),
                    const SizedBox(height: 8),
                    _buildCfgSlider(theme),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: _buildStepSlider(theme)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildCfgSlider(theme)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStepSlider(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Steps: $_steps',
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: _steps.toDouble(),
            min: 10,
            max: 30,
            divisions: 20,
            onChanged: (val) {
              setState(() {
                _steps = val.toInt();
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCfgSlider(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CFG Scale: ${_cfgScale.toStringAsFixed(1)}',
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: _cfgScale,
            min: 1.0,
            max: 15.0,
            divisions: 28,
            onChanged: (val) {
              setState(() {
                _cfgScale = val;
              });
            },
          ),
        ),
      ],
    );
  }
}

