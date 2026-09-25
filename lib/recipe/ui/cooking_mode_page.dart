import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/theme.dart';
import '../models/recipe_models.dart';
import '../recipe_scope.dart';

class CookingModePage extends StatefulWidget {
  const CookingModePage({
    super.key,
    required this.recipeId,
    this.multiplier = 1,
  });
  final String recipeId;
  final double multiplier;

  @override
  State<CookingModePage> createState() => _CookingModePageState();
}

class _CookingModePageState extends State<CookingModePage> {
  static const _channel = MethodChannel('com.pinlogy/cooking');
  int _index = 0;
  int? _remaining;
  Timer? _timer;
  int? _timerStepNumber;
  int? _timerInitialSeconds;
  DateTime? _timerEndsAt;
  final SpeechToText _speech = SpeechToText();
  bool _speechReady = false;
  bool _voiceEnabled = false;
  bool _voiceRestartScheduled = false;
  int _voiceStepCount = 0;
  int? _voiceDurationSeconds;
  String? _lastVoiceCommand;
  DateTime? _lastVoiceCommandAt;

  @override
  void initState() {
    super.initState();
    unawaited(_setAwake(true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _voiceEnabled = false;
    unawaited(_speech.stop());
    unawaited(_setAwake(false));
    super.dispose();
  }

  Future<void> _setAwake(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setAwake', {'enabled': enabled});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final controller = RecipeScope.of(context);
    final recipe = controller.recipeById(widget.recipeId);
    if (recipe == null) {
      return const Scaffold(body: Center(child: Text('レシピが見つかりません')));
    }
    final entries = <({RecipePart part, RecipeStep step})>[
      for (final part in recipe.parts)
        for (final step in part.steps) (part: part, step: step),
    ];
    if (entries.isEmpty) {
      return const Scaffold(body: Center(child: Text('工程が登録されていません')));
    }
    _index = _index.clamp(0, entries.length - 1).toInt();
    final entry = entries[_index];
    _voiceStepCount = entries.length;
    _voiceDurationSeconds = entry.step.durationSeconds;
    final ingredients = _ingredientsFor(entry.part, entry.step);
    final sourceImages = controller.legacy.hub.snapshot.sourcePosts
        .where((post) => post.id == recipe.sourcePostId)
        .expand((post) => post.imagePaths)
        .where((path) => path.trim().isNotEmpty)
        .toList(growable: false);
    final imagePath = _imageFor(
      recipe,
      entry.step,
      sourceImages,
      stepIndex: _index,
      stepCount: entries.length,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('料理モード'),
        actions: [
          IconButton(
            onPressed: _toggleVoice,
            tooltip: _voiceEnabled ? '音声操作を停止' : '音声操作を開始',
            color: _voiceEnabled ? mossDeep : null,
            icon: Icon(
              _voiceEnabled ? Icons.mic_rounded : Icons.mic_none_rounded,
            ),
          ),
          Center(child: Text('${_index + 1} / ${entries.length}')),
          const SizedBox(width: 16),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (details) => _handleSwipe(details, entries.length),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              final compact = box.maxHeight < 720;
              final imageHeight = compact
                  ? 142.0
                  : (box.maxHeight * 0.34).clamp(190.0, 240.0).toDouble();
              return Padding(
                padding: EdgeInsets.fromLTRB(16, compact ? 8 : 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LinearProgressIndicator(
                      value: (_index + 1) / entries.length,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(99),
                      backgroundColor: mint,
                    ),
                    SizedBox(height: compact ? 8 : 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'STEP ${_index + 1}',
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                              ),
                              Text(
                                entry.part.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(color: mossDeep),
                              ),
                            ],
                          ),
                        ),
                        if (entry.step.durationSeconds != null)
                          _InfoChip(
                            label: _durationLabel(entry.step.durationSeconds!),
                          ),
                      ],
                    ),
                    SizedBox(height: compact ? 7 : 10),
                    if (imagePath != null) ...[
                      SizedBox(
                        height: imageHeight,
                        width: double.infinity,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: _CookingImage(path: imagePath),
                        ),
                      ),
                      SizedBox(height: compact ? 7 : 10),
                    ],
                    if (ingredients.isNotEmpty) ...[
                      _StepIngredients(
                        ingredients: ingredients,
                        multiplier: widget.multiplier,
                        compact: compact,
                      ),
                      SizedBox(height: compact ? 7 : 10),
                    ],
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.all(compact ? 12 : 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F8F5),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: mint),
                        ),
                        child: LayoutBuilder(
                          builder: (context, instructionBox) {
                            final hasTimer =
                                _timerStepNumber != null ||
                                entry.step.durationSeconds != null;
                            final fontSize = hasTimer
                                ? (compact ? 12.5 : 14.0)
                                : (compact ? 14.0 : 16.0);
                            return FittedBox(
                              alignment: Alignment.centerLeft,
                              fit: BoxFit.scaleDown,
                              child: SizedBox(
                                width: instructionBox.maxWidth,
                                child: Text(
                                  // 詳細画面と同じRecipeStepの原文をそのまま表示する。
                                  entry.step.instruction,
                                  softWrap: true,
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(
                                        height: 1.35,
                                        fontSize: fontSize,
                                      ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    if (_timerStepNumber != null ||
                        entry.step.durationSeconds != null) ...[
                      SizedBox(height: compact ? 7 : 9),
                      _TimerPanel(
                        label: _timerStepNumber == null
                            ? 'この工程のタイマー'
                            : 'STEP $_timerStepNumber のタイマー',
                        seconds:
                            _remaining ??
                            _timerInitialSeconds ??
                            entry.step.durationSeconds!,
                        running: _timer?.isActive == true,
                        compact: compact,
                        onToggle: () => _toggleTimer(
                          _timerInitialSeconds ?? entry.step.durationSeconds!,
                        ),
                        onReset: () => _resetTimer(
                          _timerInitialSeconds ?? entry.step.durationSeconds!,
                        ),
                        onClear: _clearTimer,
                      ),
                    ],
                    SizedBox(height: compact ? 7 : 9),
                    if (controller.cookingAssistantAvailable)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _showAssistant(
                                recipe,
                                entry.part,
                                entry.step,
                                ingredients,
                              ),
                              icon: const Icon(
                                Icons.auto_awesome_rounded,
                                size: 18,
                              ),
                              label: const Text('AIに聞く'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _showAssistant(
                                recipe,
                                entry.part,
                                entry.step,
                                ingredients,
                                withCamera: true,
                              ),
                              icon: const Icon(
                                Icons.photo_camera_outlined,
                                size: 18,
                              ),
                              label: const Text('写真で確認'),
                            ),
                          ),
                        ],
                      ),
                    SizedBox(height: compact ? 7 : 9),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: _footerButtonStyle(compact),
                            onPressed: _index == 0
                                ? null
                                : () => _move(-1, entries.length),
                            icon: const Icon(Icons.arrow_back_rounded),
                            label: const Text('前へ'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            style: _footerButtonStyle(compact),
                            onPressed: _index == entries.length - 1
                                ? () async {
                                    await controller.recordCooked(recipe);
                                    if (context.mounted) Navigator.pop(context);
                                  }
                                : () => _move(1, entries.length),
                            icon: Icon(
                              _index == entries.length - 1
                                  ? Icons.check_rounded
                                  : Icons.arrow_forward_rounded,
                            ),
                            label: Text(
                              _index == entries.length - 1 ? '完成' : '次へ',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  List<RecipeIngredient> _ingredientsFor(RecipePart part, RecipeStep step) {
    final indexed = step.ingredientIndexes
        .where((index) => index >= 0 && index < part.ingredients.length)
        .map((index) => part.ingredients[index])
        .take(4)
        .toList(growable: false);
    if (indexed.isNotEmpty) return indexed;

    final text = step.instruction.toLowerCase();
    final matches =
        part.ingredients
            .where((item) => text.contains(item.name.toLowerCase()))
            .toList(growable: false)
          ..sort((left, right) {
            final leftIndex = text.indexOf(left.name.toLowerCase());
            final rightIndex = text.indexOf(right.name.toLowerCase());
            return leftIndex.compareTo(rightIndex);
          });
    return matches.take(4).toList(growable: false);
  }

  void _handleSwipe(DragEndDetails details, int stepCount) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 250) return;
    if (velocity < 0 && _index < stepCount - 1) {
      _move(1, stepCount);
    } else if (velocity > 0 && _index > 0) {
      _move(-1, stepCount);
    }
  }

  Future<void> _toggleVoice() async {
    if (_voiceEnabled) {
      _voiceEnabled = false;
      await _speech.stop();
      if (mounted) setState(() {});
      return;
    }

    if (!_speechReady) {
      _speechReady = await _speech.initialize(
        onStatus: _handleSpeechStatus,
        onError: _handleSpeechError,
      );
    }
    if (!_speechReady) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('設定でマイクと音声認識を許可してください')));
      }
      return;
    }
    _voiceEnabled = true;
    if (mounted) setState(() {});
    await _startVoiceListening();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('音声操作ON：「次・Next」「前・Back」「タイマー開始」が使えます'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _startVoiceListening() async {
    if (!_voiceEnabled || !_speechReady || _speech.isListening) return;
    await _speech.listen(
      onResult: _handleSpeechResult,
      listenOptions: SpeechListenOptions(
        localeId: 'ja_JP',
        listenFor: Duration(minutes: 2),
        pauseFor: Duration(seconds: 3),
        partialResults: true,
        cancelOnError: false,
      ),
    );
    if (mounted) setState(() {});
  }

  void _handleSpeechStatus(String status) {
    if (!_voiceEnabled ||
        _voiceRestartScheduled ||
        (status != 'done' && status != 'notListening')) {
      return;
    }
    _voiceRestartScheduled = true;
    Future<void>.delayed(const Duration(milliseconds: 200), () async {
      _voiceRestartScheduled = false;
      if (mounted && _voiceEnabled) await _startVoiceListening();
    });
  }

  void _handleSpeechError(SpeechRecognitionError error) {
    if (!error.permanent) {
      _handleSpeechStatus('done');
      return;
    }
    _voiceEnabled = false;
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('音声操作を開始できませんでした')));
  }

  void _handleSpeechResult(SpeechRecognitionResult result) {
    final phrase = result.recognizedWords.toLowerCase().replaceAll(
      RegExp(r'[\s、。,.!！?？]'),
      '',
    );
    String? command;
    if (phrase.contains('タイマーリセット') || phrase.contains('タイマー戻して')) {
      command = 'timerReset';
    } else if (phrase.contains('タイマー停止') ||
        phrase.contains('タイマーストップ') ||
        phrase.contains('タイマー止めて') ||
        phrase.contains('タイマーとめて')) {
      command = 'timerStop';
    } else if (phrase.contains('タイマー開始') ||
        phrase.contains('タイマースタート') ||
        phrase.contains('タイマー始めて') ||
        phrase.contains('タイマーはじめて')) {
      command = 'timerStart';
    } else if (phrase.contains('next') ||
        phrase.contains('ネクスト') ||
        phrase.contains('次') ||
        phrase.contains('つぎ') ||
        phrase.contains('次へ') ||
        phrase.contains('進んで') ||
        phrase.contains('進めて')) {
      command = 'next';
    } else if (phrase.contains('back') ||
        phrase.contains('バック') ||
        phrase.contains('前') ||
        phrase.contains('まえ') ||
        phrase.contains('前へ') ||
        phrase.contains('戻って') ||
        phrase.contains('戻して')) {
      command = 'previous';
    }
    if (command == null || _isDuplicateVoiceCommand(command)) return;

    switch (command) {
      case 'next':
        if (_index < _voiceStepCount - 1) _move(1, _voiceStepCount);
      case 'previous':
        if (_index > 0) _move(-1, _voiceStepCount);
      case 'timerStart':
        final duration = _timerInitialSeconds ?? _voiceDurationSeconds;
        if (duration != null && _timer?.isActive != true) {
          _toggleTimer(duration);
        }
      case 'timerStop':
        if (_timer?.isActive == true) {
          _pauseTimer();
        }
      case 'timerReset':
        final duration = _timerInitialSeconds ?? _voiceDurationSeconds;
        if (duration != null) _resetTimer(duration);
    }
    unawaited(_speech.stop());
  }

  bool _isDuplicateVoiceCommand(String command) {
    final now = DateTime.now();
    final duplicate =
        _lastVoiceCommand == command &&
        _lastVoiceCommandAt != null &&
        now.difference(_lastVoiceCommandAt!) < const Duration(seconds: 2);
    if (!duplicate) {
      _lastVoiceCommand = command;
      _lastVoiceCommandAt = now;
    }
    return duplicate;
  }

  ButtonStyle _footerButtonStyle(bool compact) => OutlinedButton.styleFrom(
    minimumSize: Size(0, compact ? 38 : 42),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
  );

  String? _imageFor(
    Recipe recipe,
    RecipeStep step,
    List<String> sourceImages, {
    required int stepIndex,
    required int stepCount,
  }) {
    final directIndex = step.imageIndex;
    if (directIndex != null &&
        directIndex >= 0 &&
        directIndex < sourceImages.length) {
      return sourceImages[directIndex];
    }
    for (final evidence in recipe.evidence) {
      if (evidence.id == step.evidenceId &&
          (evidence.kind == EvidenceKind.image ||
              evidence.kind == EvidenceKind.video) &&
          evidence.imagePath?.isNotEmpty == true) {
        return evidence.imagePath;
      }
    }
    if (sourceImages.isNotEmpty) {
      final imageIndex = stepCount <= 1
          ? 0
          : (stepIndex * (sourceImages.length - 1) / (stepCount - 1)).round();
      final boundedIndex = imageIndex.clamp(0, sourceImages.length - 1).toInt();
      return sourceImages[boundedIndex];
    }
    return recipe.coverImagePath;
  }

  Future<void> _showAssistant(
    Recipe recipe,
    RecipePart part,
    RecipeStep step,
    List<RecipeIngredient> ingredients, {
    bool withCamera = false,
  }) async {
    String? imagePath;
    if (withCamera) {
      final image = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 72,
        maxWidth: 1280,
      );
      if (image == null || !mounted) return;
      imagePath = image.path;
    }
    if (!mounted) return;
    final controller = RecipeScope.of(context);
    final input = TextEditingController(
      text: withCamera ? '写真を見て、今の状態から次にどうすればいい？' : '',
    );
    String? answer;
    String? error;
    var sending = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) {
          Future<void> send() async {
            if (sending || input.text.trim().isEmpty) return;
            update(() {
              sending = true;
              error = null;
            });
            try {
              final value = await controller.askCookingAssistant(
                recipe: recipe,
                part: part,
                step: step,
                ingredients: ingredients,
                multiplier: widget.multiplier,
                question: input.text,
                imagePath: imagePath,
              );
              if (sheetContext.mounted) update(() => answer = value);
            } catch (exception) {
              if (sheetContext.mounted) {
                update(
                  () => error = exception.toString().replaceFirst(
                    'Bad state: ',
                    '',
                  ),
                );
              }
            } finally {
              if (sheetContext.mounted) update(() => sending = false);
            }
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              MediaQuery.viewInsetsOf(context).bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'この工程をAIに相談',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    step.instruction,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (imagePath != null) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 110,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(File(imagePath), fit: BoxFit.cover),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final value in const [
                        '焼き加減はこれでいい？',
                        '次はどうしたらいい？',
                        '失敗したかも。直せる？',
                      ])
                        ActionChip(
                          label: Text(value),
                          onPressed: () => input.text = value,
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: input,
                    autofocus: !withCamera,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      hintText: 'ここ、どうしたらいい？',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (answer != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: mintSoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(answer!),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (error != null) ...[
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  FilledButton.icon(
                    onPressed: sending ? null : send,
                    icon: sending
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome_rounded),
                    label: Text(sending ? '確認中…' : 'AIに聞く'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '写真だけでは肉や魚の加熱完了・安全性を断定できません。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    input.dispose();
  }

  void _move(int amount, int length) {
    setState(() {
      _index = (_index + amount).clamp(0, length - 1).toInt();
    });
  }

  void _toggleTimer(int initial) {
    if (_timer?.isActive == true) {
      _pauseTimer();
      return;
    }
    _timerStepNumber ??= _index + 1;
    _timerInitialSeconds ??= initial;
    _remaining ??= _timerInitialSeconds;
    if (_remaining == 0) _remaining = _timerInitialSeconds;
    _timerEndsAt = DateTime.now().add(Duration(seconds: _remaining!));
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      final milliseconds = _timerEndsAt!
          .difference(DateTime.now())
          .inMilliseconds;
      final seconds = (milliseconds / 1000).ceil().clamp(0, 86400).toInt();
      if (seconds <= 0) {
        timer.cancel();
        _timerEndsAt = null;
        HapticFeedback.heavyImpact();
        setState(() => _remaining = 0);
      } else {
        setState(() => _remaining = seconds);
      }
    });
    setState(() {});
  }

  void _pauseTimer() {
    final end = _timerEndsAt;
    _timer?.cancel();
    _timerEndsAt = null;
    if (!mounted) return;
    setState(() {
      if (end != null) {
        _remaining = (end.difference(DateTime.now()).inMilliseconds / 1000)
            .ceil()
            .clamp(0, 86400)
            .toInt();
      }
    });
  }

  void _resetTimer(int initial) {
    _timer?.cancel();
    setState(() {
      _timer = null;
      _timerEndsAt = null;
      _timerStepNumber ??= _index + 1;
      _timerInitialSeconds ??= initial;
      _remaining = _timerInitialSeconds;
    });
  }

  void _clearTimer() {
    _timer?.cancel();
    setState(() {
      _timer = null;
      _timerEndsAt = null;
      _remaining = null;
      _timerStepNumber = null;
      _timerInitialSeconds = null;
    });
  }
}

class _StepIngredients extends StatelessWidget {
  const _StepIngredients({
    required this.ingredients,
    required this.multiplier,
    required this.compact,
  });

  final List<RecipeIngredient> ingredients;
  final double multiplier;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 7 : 9),
    decoration: BoxDecoration(
      color: mintSoft,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'この工程で使う材料',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: mossDeep,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: compact ? 3 : 5),
        for (var index = 0; index < ingredients.length; index++)
          Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : 3),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: mossDeep,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    ingredients[index].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: compact ? 12 : 14),
                  ),
                ),
                const SizedBox(width: 8),
                Builder(
                  builder: (context) {
                    final quantity = ingredients[index]
                        .quantityFor(multiplier)
                        .trim();
                    final missing = quantity.isEmpty;
                    return Text(
                      missing ? '分量不明' : quantity,
                      style: TextStyle(
                        fontSize: compact ? 12 : 14,
                        fontWeight: FontWeight.w700,
                        color: missing ? warningColor : ink,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _CookingImage extends StatelessWidget {
  const _CookingImage({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(path);
    if (uri?.scheme == 'https') {
      return ColoredBox(
        color: const Color(0xFFF2F3F0),
        child: Image.network(path, fit: BoxFit.contain, errorBuilder: _error),
      );
    }
    final local = uri?.scheme == 'file' ? uri!.toFilePath() : path;
    return ColoredBox(
      color: const Color(0xFFF2F3F0),
      child: Image.file(File(local), fit: BoxFit.contain, errorBuilder: _error),
    );
  }

  Widget _error(BuildContext context, Object error, StackTrace? stack) =>
      const ColoredBox(
        color: mintSoft,
        child: Center(child: Icon(Icons.restaurant_rounded, size: 36)),
      );
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: mintSoft,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.timer_outlined, size: 17, color: mossDeep),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

class _TimerPanel extends StatelessWidget {
  const _TimerPanel({
    required this.label,
    required this.seconds,
    required this.running,
    required this.compact,
    required this.onToggle,
    required this.onReset,
    required this.onClear,
  });
  final String label;
  final int seconds;
  final bool running;
  final bool compact;
  final VoidCallback onToggle;
  final VoidCallback onReset;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 6 : 9),
      decoration: BoxDecoration(
        color: mintSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer_outlined, color: mossDeep),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                Text(
                  '$minutes:${rest.toString().padLeft(2, '0')}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onReset,
            tooltip: 'リセット',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh_rounded),
          ),
          FilledButton.icon(
            onPressed: onToggle,
            icon: Icon(
              running ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 18,
            ),
            label: Text(running ? '停止' : '開始'),
          ),
          IconButton(
            onPressed: onClear,
            tooltip: 'タイマーを終了',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

String _durationLabel(int seconds) {
  if (seconds < 60) return '$seconds秒';
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return rest == 0 ? '$minutes分' : '$minutes分$rest秒';
}
