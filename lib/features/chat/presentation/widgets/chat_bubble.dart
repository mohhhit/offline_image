import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/chat_message.dart';

/// Chat message component rendering user prompts, assistant generated images,
/// real-time pipeline stage stepper, and live Python-style inference console.
class ChatBubble extends StatefulWidget {
  final ChatMessage message;
  final VoidCallback? onRetry;
  final VoidCallback? onStop;

  const ChatBubble({
    super.key,
    required this.message,
    this.onRetry,
    this.onStop,
  });

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  bool _showTerminal = true;
  final ScrollController _terminalScrollController = ScrollController();
  int _lastLogCount = 0;

  @override
  void didUpdateWidget(covariant ChatBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.message.logs.length != _lastLogCount) {
      _lastLogCount = widget.message.logs.length;
      if (_showTerminal) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_terminalScrollController.hasClients) {
            _terminalScrollController.animateTo(
              _terminalScrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _terminalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeStr = DateFormat('hh:mm a').format(widget.message.createdAt);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. User Prompt Bubble (Right aligned)
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.85,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    widget.message.prompt,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (widget.message.negativePrompt != null &&
                      widget.message.negativePrompt!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Negative: ${widget.message.negativePrompt}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimary.withValues(alpha: 0.8),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    timeStr,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimary.withValues(alpha: 0.7),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 2. Generation Output (Left aligned card)
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.92,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: _buildOutputContent(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutputContent(BuildContext context) {
    if (widget.message.isGenerating) {
      return _buildGeneratingCard(context);
    }
    if (widget.message.isCompleted && widget.message.imagePath != null) {
      return _buildCompletedCard(context);
    }
    if (widget.message.isFailed) {
      return _buildFailedCard(context);
    }
    return const SizedBox.shrink();
  }

  /// Live Generating Card with Pipeline Stepper and Real-Time Terminal
  Widget _buildGeneratingCard(BuildContext context) {
    final theme = Theme.of(context);
    final msg = widget.message;
    final currentStage = msg.stage ?? (msg.stepProgress > 0 ? 'denoising' : 'loading_weights');

    String stageTitle;
    String stageDescription;
    bool isIndeterminate = false;

    switch (currentStage) {
      case 'loading_weights':
        stageTitle = 'Loading Weights (mmap)';
        stageDescription = msg.statusMessage ?? 'Mapping 2.18 GB GGUF model into memory...';
        isIndeterminate = true;
        break;
      case 'prompt_encoding':
        stageTitle = 'Prompt Text Conditioning';
        stageDescription = msg.statusMessage ?? 'Calculating CLIP text embeddings...';
        isIndeterminate = true;
        break;
      case 'denoising':
        stageTitle = 'Denoising Step ${msg.stepProgress}/${msg.totalSteps}';
        final speed = msg.formattedSpeed.isNotEmpty ? msg.formattedSpeed : '';
        final eta = msg.formattedEta.isNotEmpty ? ' • ETA ${msg.formattedEta}' : '';
        stageDescription = speed.isNotEmpty ? '$speed$eta' : 'Denoising latent space...';
        isIndeterminate = false;
        break;
      case 'decoding_vae':
        stageTitle = 'Tiled VAE Latent Decode';
        stageDescription = 'Decoding latents into 512x512 RGB pixels...';
        isIndeterminate = true;
        break;
      case 'saving_image':
        stageTitle = 'Exporting Image';
        stageDescription = 'Compressing PNG to local storage...';
        isIndeterminate = true;
        break;
      default:
        stageTitle = msg.stepProgress > 0
            ? 'Denoising Step ${msg.stepProgress}/${msg.totalSteps}'
            : 'Initializing Stable Diffusion';
        stageDescription = msg.statusMessage ?? 'Inference in progress...';
        isIndeterminate = msg.stepProgress == 0;
        break;
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A. Visual Pipeline Stepper
          _buildPipelineStepper(theme, currentStage),
          const SizedBox(height: 14),

          // B. Main Stage Header & Percentage
          Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  value: isIndeterminate ? null : msg.progressFraction,
                  valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stageTitle,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      stageDescription,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Text(
                isIndeterminate ? '...' : '${(msg.progressFraction * 100).toInt()}%',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // C. Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: isIndeterminate ? null : msg.progressFraction,
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
            ),
          ),
          const SizedBox(height: 14),

          // D. Live Terminal / Inference Console
          _buildTerminalWidget(theme, isGenerating: true),
          if (widget.onStop != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.onStop,
                icon: const Icon(Icons.stop_circle_rounded, size: 18, color: Colors.redAccent),
                label: const Text(
                  'Stop Generation',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),

          // E. Wakelock Active Notice
          Row(
            children: [
              Icon(
                Icons.bolt_rounded,
                size: 14,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  '100% offline mobile inference (Wakelock CPU keepalive active)',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Visual 4-Step Pipeline Indicator
  Widget _buildPipelineStepper(ThemeData theme, String stage) {
    int currentStepIndex = 0;
    switch (stage) {
      case 'loading_weights':
        currentStepIndex = 0;
        break;
      case 'prompt_encoding':
        currentStepIndex = 1;
        break;
      case 'denoising':
        currentStepIndex = 2;
        break;
      case 'decoding_vae':
      case 'saving_image':
        currentStepIndex = 3;
        break;
    }

    final steps = [
      ('Weights', Icons.memory_rounded),
      ('CLIP', Icons.psychology_rounded),
      ('Denoise', Icons.auto_awesome_rounded),
      ('VAE', Icons.photo_size_select_actual_rounded),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(steps.length, (index) {
        final isDone = index < currentStepIndex;
        final isCurrent = index == currentStepIndex;
        final color = isDone
            ? Colors.greenAccent
            : (isCurrent ? theme.colorScheme.primary : theme.colorScheme.outlineVariant);

        return Expanded(
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: isCurrent
                      ? theme.colorScheme.primary.withValues(alpha: 0.15)
                      : (isDone ? Colors.greenAccent.withValues(alpha: 0.1) : Colors.transparent),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: color.withValues(alpha: isCurrent ? 1.0 : 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isDone ? Icons.check_circle_rounded : steps[index].$2,
                      size: 13,
                      color: color,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      steps[index].$1,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: color,
                        fontSize: 10,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              if (index < steps.length - 1)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    color: isDone
                        ? Colors.greenAccent.withValues(alpha: 0.6)
                        : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  /// Retro-Modern Hacker / Python Terminal Console Box
  Widget _buildTerminalWidget(ThemeData theme, {required bool isGenerating}) {
    final logs = widget.message.logs;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117), // Deep dark GitHub terminal background
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Terminal Header
          InkWell(
            onTap: () {
              setState(() {
                _showTerminal = !_showTerminal;
              });
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: const BoxDecoration(
                color: Color(0xFF161B22),
                borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.terminal_rounded,
                    size: 14,
                    color: Color(0xFF7EE787),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Inference Console',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: Color(0xFFC9D1D9),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (isGenerating)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF238636).withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, size: 7, color: Color(0xFF7EE787)),
                          SizedBox(width: 4),
                          Text(
                            'LIVE',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              color: Color(0xFF7EE787),
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Text(
                      '${logs.length} lines',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Color(0xFF8B949E),
                        fontSize: 10,
                      ),
                    ),
                  const SizedBox(width: 6),
                  Icon(
                    _showTerminal ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    size: 16,
                    color: const Color(0xFF8B949E),
                  ),
                ],
              ),
            ),
          ),

          // Terminal Body (expandable)
          if (_showTerminal)
            Container(
              height: 130,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: logs.isEmpty
                  ? const Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        '> Initializing compute graph... _',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color: Color(0xFF8B949E),
                          fontSize: 10.5,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _terminalScrollController,
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        final line = logs[index];
                        Color textColor = const Color(0xFFC9D1D9);
                        if (line.contains('[LOADER]') || line.contains('[GGUF]') || line.contains('weight')) {
                          textColor = const Color(0xFF79C0FF); // Light blue for weights
                        } else if (line.contains('[STEP]') || line.contains('Step')) {
                          textColor = const Color(0xFF7EE787); // Green for steps
                        } else if (line.contains('[INFERENCE]') || line.contains('Prompt')) {
                          textColor = const Color(0xFFD29922); // Amber for conditioning
                        } else if (line.contains('[ERROR]') || line.contains('Error') || line.contains('Failed')) {
                          textColor = const Color(0xFFFF7B72); // Red for error
                        }

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1.5),
                          child: Text(
                            '> $line',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              color: textColor,
                              height: 1.25,
                            ),
                          ),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }

  /// Completed Image Output Card
  Widget _buildCompletedCard(BuildContext context) {
    final theme = Theme.of(context);
    final msg = widget.message;
    final file = File(msg.imagePath!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _openFullscreenImage(context, file),
          child: AspectRatio(
            aspectRatio: 1.0, // 512x512
            child: file.existsSync()
                ? Image.file(
                    file,
                    fit: BoxFit.cover,
                    errorBuilder: (_, error, stack) => const Center(
                      child: Icon(Icons.broken_image_rounded, size: 48),
                    ),
                  )
                : const Center(
                    child: Text('Image file missing on disk'),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      '512x512 | CFG ${msg.cfgScale.toStringAsFixed(1)} | ${msg.totalSteps} steps',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (msg.durationSeconds != null)
                    Text(
                      '${msg.durationSeconds!.toStringAsFixed(1)}s',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                ],
              ),
              if (msg.logs.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildTerminalWidget(theme, isGenerating: false),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Generation Failed Output Card
  Widget _buildFailedCard(BuildContext context) {
    final theme = Theme.of(context);
    final msg = widget.message;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: theme.colorScheme.error,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Generation Failed',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            msg.errorMessage ?? 'An unexpected native error occurred.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (msg.logs.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildTerminalWidget(theme, isGenerating: false),
          ],
          if (widget.onRetry != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: widget.onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openFullscreenImage(BuildContext context, File file) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.file(file),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
