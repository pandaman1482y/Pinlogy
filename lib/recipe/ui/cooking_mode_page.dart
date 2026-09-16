import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../models/recipe_models.dart';
import '../recipe_scope.dart';

class CookingModePage extends StatefulWidget {
  const CookingModePage({super.key, required this.recipeId});

  final String recipeId;

  @override
  State<CookingModePage> createState() => _CookingModePageState();
}

class _CookingModePageState extends State<CookingModePage> {
  static const _channel = MethodChannel('com.pinlogy/cooking');
  int _index = 0;
  int? _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_setAwake(true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_setAwake(false));
    super.dispose();
  }

  Future<void> _setAwake(bool value) async {
    try {
      await _channel.invokeMethod<void>('setAwake', {'enabled': value});
    } catch (_) {
      // Unsupported platforms simply use the normal screen timeout.
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = RecipeScope.of(context);
    final recipe = controller.recipeById(widget.recipeId);
    if (recipe == null) {
      return const Scaffold(body: Center(child: Text('レシピが見つかりません')));
    }
    final entries = <({String part, RecipeStep step})>[
      for (final part in recipe.parts)
        for (final step in part.steps) (part: part.name, step: step),
    ];
    if (entries.isEmpty) {
      return const Scaffold(body: Center(child: Text('工程が登録されていません')));
    }
    if (_index >= entries.length) _index = entries.length - 1;
    final entry = entries[_index];

    return Scaffold(
      appBar: AppBar(
        title: const Text('料理モード'),
        actions: [
          Center(child: Text('${_index + 1} / ${entries.length}')),
          const SizedBox(width: 16),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(
                value: (_index + 1) / entries.length,
                minHeight: 6,
                borderRadius: BorderRadius.circular(99),
                backgroundColor: mint,
              ),
              const SizedBox(height: 24),
              Text(entry.part, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: mossDeep)),
              const SizedBox(height: 8),
              Text('STEP ${_index + 1}', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 24),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Text(
                      entry.step.instruction,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(height: 1.5),
                    ),
                  ),
                ),
              ),
              if (entry.step.durationSeconds != null) ...[
                _TimerPanel(
                  seconds: _remaining ?? entry.step.durationSeconds!,
                  running: _timer?.isActive == true,
                  onToggle: () => _toggleTimer(entry.step.durationSeconds!),
                  onReset: () => _resetTimer(entry.step.durationSeconds!),
                ),
                const SizedBox(height: 18),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _index == 0 ? null : () => _move(-1, entries),
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('前へ'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _index == entries.length - 1
                          ? () async {
                              await controller.recordCooked(recipe);
                              if (context.mounted) Navigator.pop(context);
                            }
                          : () => _move(1, entries),
                      icon: Icon(_index == entries.length - 1 ? Icons.check_rounded : Icons.arrow_forward_rounded),
                      label: Text(_index == entries.length - 1 ? '完成' : '次へ'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _move(int amount, List<({String part, RecipeStep step})> entries) {
    _timer?.cancel();
    setState(() {
      _index = (_index + amount).clamp(0, entries.length - 1).toInt();
      _remaining = null;
    });
  }

  void _toggleTimer(int initial) {
    if (_timer?.isActive == true) {
      _timer?.cancel();
      setState(() {});
      return;
    }
    _remaining ??= initial;
    if (_remaining == 0) _remaining = initial;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if ((_remaining ?? 0) <= 1) {
        timer.cancel();
        HapticFeedback.heavyImpact();
        setState(() => _remaining = 0);
      } else {
        setState(() => _remaining = _remaining! - 1);
      }
    });
    setState(() {});
  }

  void _resetTimer(int initial) {
    _timer?.cancel();
    setState(() => _remaining = initial);
  }
}

class _TimerPanel extends StatelessWidget {
  const _TimerPanel({
    required this.seconds,
    required this.running,
    required this.onToggle,
    required this.onReset,
  });

  final int seconds;
  final bool running;
  final VoidCallback onToggle;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: mintSoft, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          const Icon(Icons.timer_outlined, color: mossDeep),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$minutes:${rest.toString().padLeft(2, '0')}',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          IconButton(onPressed: onReset, tooltip: 'リセット', icon: const Icon(Icons.refresh_rounded)),
          FilledButton.icon(
            onPressed: onToggle,
            icon: Icon(running ? Icons.pause_rounded : Icons.play_arrow_rounded),
            label: Text(running ? '一時停止' : '開始'),
          ),
        ],
      ),
    );
  }
}
