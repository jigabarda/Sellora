import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/money.dart';
import '../../core/sellora_ui.dart';
import '../../data/models/entities.dart';
import '../../data/notebook/notebook_line.dart';
import '../../data/notebook/notebook_parser.dart';
import '../../providers.dart';

/// A measuring instrument, not a feature. Debug builds only.
///
/// The open question about Notebook Capture is not whether the parser is
/// correct — `test/notebook_parser_test.dart` settles that against fixed
/// strings. It is whether **real handwriting** survives the recogniser well
/// enough for the parser to have anything to work with. No unit test can
/// answer that, because ML Kit is a platform channel: the model only exists on
/// a device, and the input has to be a real photograph of real pen on paper.
///
/// So this shows both halves side by side for every page picked — exactly what
/// ML Kit returned, and what the parser made of it — and scores the pages. The
/// gap between the two columns is the answer:
///
/// * raw text good, rate low  → the parser or the catalogue is at fault, and
///   that is fixable and worth reporting.
/// * raw text already garbage → no parser can save it, and the recogniser has
///   to be swapped. `TextRecogniser` is an interface for exactly this reason.
///
/// It lives in the app rather than in an integration test because everything
/// else was worse. `flutter test integration_test/` uninstalls the app after
/// every run, which wipes its private storage, and scoped storage hides any
/// shared folder from an app holding no media permission — Sellora holds none
/// and must not start. The photo picker sidesteps all of it: the owner grants
/// access to the images they choose and nothing else, which is the same
/// mechanism the real capture screen uses.
///
/// Reached from the Scan screen, behind `kDebugMode`, so release builds tree
/// shake the route and the button away.
class OcrReportScreen extends ConsumerStatefulWidget {
  const OcrReportScreen({super.key, required this.businessId});

  final String businessId;

  @override
  ConsumerState<OcrReportScreen> createState() => _OcrReportScreenState();
}

class _OcrReportScreenState extends ConsumerState<OcrReportScreen> {
  List<_PageReport>? _reports;
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final products =
        ref.watch(productsProvider(widget.businessId)).valueOrNull ?? const [];
    final customers =
        ref.watch(customersProvider(widget.businessId)).valueOrNull ?? const [];
    final sellable = products.where((p) => p.active && p.price > 0).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recogniser report'),
        actions: [
          if (_reports != null && _reports!.isNotEmpty)
            IconButton(
              tooltip: 'Copy the whole report',
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: _copy,
            ),
        ],
      ),
      body: _busy
          ? const LoadingView()
          : ListView(
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 40),
              children: [
                _Preamble(products: sellable, customers: customers),
                if (_error != null) ...[
                  Gap.h12,
                  Text(_error!,
                      style: context.text.bodySmall
                          ?.copyWith(color: context.t.danger)),
                ],
                Gap.h12,
                FilledButton.icon(
                  onPressed: sellable.isEmpty
                      ? null
                      : () => _pick(sellable, customers),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Pick pages to read'),
                ),
                if (_reports != null) ...[
                  Gap.h16,
                  _Scoreboard(reports: _reports!),
                  for (final report in _reports!) ...[
                    Gap.h16,
                    _PageCard(report: report),
                  ],
                ],
              ],
            ),
    );
  }

  Future<void> _pick(List<Product> products, List<Customer> customers) async {
    final List<XFile> files;
    try {
      files = await ImagePicker().pickMultiImage(maxWidth: 2000);
    } catch (e) {
      setState(() => _error = 'Could not open the picker: $e');
      return;
    }
    if (files.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final recogniser = ref.read(textRecogniserProvider);
    final out = <_PageReport>[];

    for (final file in files) {
      final started = DateTime.now();
      try {
        final text = await recogniser.recognise(file.path);
        final took = DateTime.now().difference(started).inMilliseconds;
        out.add(_PageReport(
          name: file.name,
          milliseconds: took,
          raw: text,
          page: const NotebookParser()
              .parse(text, products: products, customers: customers),
        ));
      } catch (e) {
        out.add(_PageReport(
          name: file.name,
          milliseconds: DateTime.now().difference(started).inMilliseconds,
          raw: '',
          page: const NotebookPage.empty(),
          failure: '$e',
        ));
      }
    }

    if (!mounted) return;
    setState(() {
      _reports = out;
      _busy = false;
    });
  }

  /// The whole report as plain text, so it can leave the phone as something
  /// readable rather than as a screenshot of a screenshot.
  Future<void> _copy() async {
    final b = StringBuffer();
    final all = _Tally()..addAll(_reports!);
    b.writeln('Sellora recogniser report');
    b.writeln(all.summary);
    for (final report in _reports!) {
      b
        ..writeln()
        ..writeln('=== ${report.name} (${report.milliseconds}ms) ===');
      if (report.failure != null) {
        b.writeln('recogniser threw: ${report.failure}');
        continue;
      }
      b.writeln('--- raw ---');
      for (final line in report.rawLines) {
        b.writeln('  $line');
      }
      b.writeln('--- parsed ---');
      for (final line in report.page.lines) {
        b.writeln('  ${_plainVerdict(line)}');
      }
      b.writeln((_Tally()..add(report)).summary);
    }

    await Clipboard.setData(ClipboardData(text: b.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Report copied')));
  }
}

class _PageReport {
  _PageReport({
    required this.name,
    required this.milliseconds,
    required this.raw,
    required this.page,
    this.failure,
  });

  final String name;
  final int milliseconds;
  final String raw;
  final NotebookPage page;
  final String? failure;

  List<String> get rawLines =>
      raw.split('\n').where((l) => l.trim().isNotEmpty).toList();
}

/// Headings and totals are excluded from the rate. Skipping them is correct
/// behaviour, so counting them either way would flatter or punish the score
/// for no reason.
class _Tally {
  int reconciled = 0;
  int needsReview = 0;
  int unreadable = 0;
  int ignored = 0;
  int threw = 0;

  void addAll(List<_PageReport> reports) => reports.forEach(add);

  void add(_PageReport report) {
    if (report.failure != null) threw++;
    for (final l in report.page.lines) {
      switch (l.status) {
        case LineStatus.reconciled:
          reconciled++;
        case LineStatus.needsReview:
          needsReview++;
        case LineStatus.unreadable:
          unreadable++;
        case LineStatus.ignored:
          ignored++;
        case LineStatus.recorded:
          break;
      }
    }
  }

  int get saleLines => reconciled + needsReview + unreadable;

  int get percent =>
      saleLines == 0 ? 0 : (reconciled * 100 / saleLines).round();

  String get summary => saleLines == 0
      ? 'No sale lines found'
      : '$reconciled of $saleLines sale lines added up ($percent%) · '
          '$needsReview need checking · $unreadable unreadable';
}

class _Preamble extends StatelessWidget {
  const _Preamble({required this.products, required this.customers});

  final List<Product> products;
  final List<Customer> customers;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    if (products.isEmpty) {
      return SelloraCard(
        color: t.dangerSoft,
        border: false,
        child: Text(
          'This business has no active priced products, so nothing can be '
          'matched. Add your real price list first — the whole check depends '
          'on the amounts on the page agreeing with it.',
          style: context.text.bodySmall?.copyWith(color: t.danger),
        ),
      );
    }
    return SelloraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reading against your real price list',
              style: context.text.labelSmall),
          Gap.h8,
          Text(
            '${products.length} products, ${customers.length} customers. '
            'Pick one or more photographs of notebook pages; nothing is '
            'recorded, this only reports what was read.',
            style: context.text.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Scoreboard extends StatelessWidget {
  const _Scoreboard({required this.reports});

  final List<_PageReport> reports;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final tally = _Tally()..addAll(reports);

    final (verdict, tone) = switch (tally.percent) {
      >= 80 => ('Good enough to build on.', t.success),
      >= 50 => ('Usable for backfill, tedious for daily work.', t.warning),
      _ => ('The recogniser is the problem, not the parser.', t.danger),
    };

    return SelloraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${tally.percent}%',
                  style: context.text.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Gap.w12,
              Expanded(
                child: Text('of sale lines added up',
                    style: context.text.bodyMedium),
              ),
            ],
          ),
          Gap.h8,
          Text(verdict,
              style: context.text.bodyMedium
                  ?.copyWith(color: tone, fontWeight: FontWeight.w600)),
          Gap.h12,
          Text(
            '${reports.length} pages · ${tally.reconciled} added up · '
            '${tally.needsReview} need checking · ${tally.unreadable} '
            'unreadable · ${tally.ignored} skipped as headings'
            '${tally.threw > 0 ? ' · ${tally.threw} threw' : ''}',
            style: context.text.bodySmall?.copyWith(color: t.muted),
          ),
          Gap.h12,
          Text(
            'If the raw text below looks right but the rate is low, the parser '
            'or the price list is at fault and that is worth fixing. If the '
            'raw text is already garbage, no parser can recover it.',
            style: context.text.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PageCard extends StatelessWidget {
  const _PageCard({required this.report});

  final _PageReport report;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final tally = _Tally()..add(report);

    return SelloraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(report.name,
                    style: context.text.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Text('${report.milliseconds}ms',
                  style: context.text.bodySmall?.copyWith(color: t.muted)),
            ],
          ),
          if (report.failure != null) ...[
            Gap.h8,
            Text('Recogniser threw: ${report.failure}',
                style: context.text.bodySmall?.copyWith(color: t.danger)),
          ] else ...[
            Gap.h12,
            Text('What ML Kit returned', style: context.text.labelSmall),
            Gap.h4,
            if (report.rawLines.isEmpty)
              Text('Nothing — no text found on this image at all.',
                  style: context.text.bodySmall?.copyWith(color: t.danger))
            else
              SelectableText(
                report.rawLines.join('\n'),
                style: context.text.bodySmall?.copyWith(fontFamily: 'monospace'),
              ),
            Gap.h12,
            Text('What the parser made of it', style: context.text.labelSmall),
            Gap.h4,
            for (final line in report.page.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: _VerdictRow(line: line),
              ),
            Gap.h8,
            Text(tally.summary,
                style: context.text.bodySmall?.copyWith(color: t.muted)),
          ],
        ],
      ),
    );
  }
}

class _VerdictRow extends StatelessWidget {
  const _VerdictRow({required this.line});

  final NotebookLine line;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final (mark, colour) = switch (line.status) {
      LineStatus.reconciled => ('OK', t.success),
      LineStatus.needsReview => ('??', t.warning),
      LineStatus.unreadable => ('XX', t.danger),
      LineStatus.recorded => ('--', t.muted),
      LineStatus.ignored => ('--', t.muted),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          child: Text(mark,
              style: context.text.bodySmall
                  ?.copyWith(color: colour, fontFamily: 'monospace')),
        ),
        Expanded(
          child: Text(_verdictBody(line), style: context.text.bodySmall),
        ),
      ],
    );
  }
}

/// The reading itself, without the status marker. The on-screen row puts the
/// marker in its own column; the clipboard version prefixes it instead.
String _verdictBody(NotebookLine line) {
  final note = line.note == null ? '' : '  <- ${line.note}';
  if (line.product == null) return '${line.raw.trim()}$note';

  final who = line.customer == null ? '' : ' (${line.customer!.name})';
  return '${line.quantity} x ${line.product!.name} '
      '${formatPhp(line.total)}$who$note';
}

String _plainVerdict(NotebookLine line) {
  final mark = switch (line.status) {
    LineStatus.reconciled => 'OK',
    LineStatus.needsReview => '??',
    LineStatus.unreadable => 'XX',
    LineStatus.recorded => '--',
    LineStatus.ignored => '--',
  };
  return '$mark ${_verdictBody(line)}';
}

/// True only in debug builds, so the route and its entry point vanish from
/// release output.
bool get ocrReportEnabled => kDebugMode;
