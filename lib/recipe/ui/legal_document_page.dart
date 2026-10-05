import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';

enum LegalDocument { terms, privacy }

extension LegalDocumentDetails on LegalDocument {
  String get title => switch (this) {
    LegalDocument.terms => '利用規約',
    LegalDocument.privacy => 'プライバシーポリシー',
  };

  String get assetPath => switch (this) {
    LegalDocument.terms => 'assets/legal/terms.md',
    LegalDocument.privacy => 'assets/legal/privacy_policy.md',
  };
}

class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage({required this.document, super.key});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(document.title)),
    body: FutureBuilder<String>(
      future: rootBundle.loadString(document.assetPath),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return const Center(child: Text('文書を読み込めませんでした'));
        }
        return SelectionArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
            children: _buildBlocks(context, snapshot.data!),
          ),
        );
      },
    ),
  );

  static List<Widget> _buildBlocks(BuildContext context, String source) {
    final widgets = <Widget>[];
    for (final rawLine in source.split('\n')) {
      final line = rawLine.trimRight();
      if (line.isEmpty) {
        widgets.add(const SizedBox(height: 8));
      } else if (line.startsWith('# ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              line.substring(2),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        );
      } else if (line.startsWith('## ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 5),
            child: Text(
              line.substring(3),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        );
      } else if (line.startsWith('### ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 3),
            child: Text(
              line.substring(4),
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        );
      } else {
        final isBullet = line.startsWith('- ');
        widgets.add(
          Padding(
            padding: EdgeInsets.only(left: isBullet ? 8 : 0, bottom: 4),
            child: Text(
              isBullet ? '• ${line.substring(2)}' : line,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.65, color: ink),
            ),
          ),
        );
      }
    }
    return widgets;
  }
}

class LegalConsentCheckbox extends StatefulWidget {
  const LegalConsentCheckbox({
    required this.initiallyAccepted,
    required this.onChanged,
    super.key,
  });

  final bool initiallyAccepted;
  final ValueChanged<bool> onChanged;

  @override
  State<LegalConsentCheckbox> createState() => _LegalConsentCheckboxState();
}

class _LegalConsentCheckboxState extends State<LegalConsentCheckbox> {
  late bool _accepted;

  @override
  void initState() {
    super.initState();
    _accepted = widget.initiallyAccepted;
  }

  Future<void> _open(LegalDocument document) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocumentPage(document: document),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 2,
        children: [
          TextButton(
            onPressed: () => _open(LegalDocument.terms),
            child: const Text('利用規約'),
          ),
          const Text('と'),
          TextButton(
            onPressed: () => _open(LegalDocument.privacy),
            child: const Text('プライバシーポリシー'),
          ),
        ],
      ),
      CheckboxListTile(
        value: _accepted,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text('利用規約とプライバシーポリシーに同意します'),
        onChanged: (value) {
          final accepted = value == true;
          setState(() => _accepted = accepted);
          widget.onChanged(accepted);
        },
      ),
    ],
  );
}
