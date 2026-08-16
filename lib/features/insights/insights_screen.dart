import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/sellora_ui.dart';
import '../../data/insights/insight.dart';
import '../../providers.dart';

/// Severity is about urgency, not about what kind of thing happened, so it maps
/// to tone here rather than in the rules. `danger` for act-today, `warning` for
/// act-this-week, and the brand accent for anything merely worth knowing —
/// grey would read as disabled.
Color toneFor(BuildContext context, InsightSeverity severity) =>
    switch (severity) {
      InsightSeverity.critical => context.t.danger,
      InsightSeverity.warning => context.t.warning,
      InsightSeverity.info => context.t.accent,
    };

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key, required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(insightsProvider(businessId));

    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(insightsProvider(businessId));
          await ref.read(insightsProvider(businessId).future);
        },
        child: async.when(
          loading: () => const RefreshableFill(child: LoadingView()),
          error: (e, _) => RefreshableFill(
            child: ErrorView(
              error: e,
              onRetry: () => ref.invalidate(insightsProvider(businessId)),
            ),
          ),
          data: (insights) {
            if (insights.isEmpty) {
              return const RefreshableFill(
                child: EmptyState(
                  icon: Icons.lightbulb_outline,
                  title: 'Nothing to flag yet',
                  // Deliberately not a placeholder insight. Saying nothing is
                  // the honest answer when there is nothing to say, and it
                  // teaches the owner that anything appearing here is real.
                  message:
                      'Record a few more sales and expenses and patterns will '
                      'show up here — what is running out, where the money is '
                      'going, which days are slow.',
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 40),
              itemCount: insights.length + 1,
              separatorBuilder: (_, __) => Gap.h8,
              itemBuilder: (context, i) {
                if (i == insights.length) return const _Provenance();
                return InsightCard(insight: insights[i]);
              },
            );
          },
        ),
      ),
    );
  }
}

/// A footer saying where these came from.
///
/// Worth the space: an owner who assumes a black box is guessing will not act
/// on any of it, and one who assumes it is smarter than it is will over-trust
/// it. Naming the mechanism sets the right expectation for both.
class _Provenance extends StatelessWidget {
  const _Provenance();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Gap.md),
      child: Text(
        'Worked out from your own records on this device. Nothing is sent '
        'anywhere, and every number above can be checked against your sales, '
        'stock and expenses.',
        style: context.text.bodySmall,
        textAlign: TextAlign.center,
      ),
    );
  }
}

class InsightCard extends StatelessWidget {
  const InsightCard({super.key, required this.insight});

  final Insight insight;

  @override
  Widget build(BuildContext context) {
    final tone = toneFor(context, insight.severity);
    final route = insight.actionRoute;

    return SelloraCard(
      onTap: route == null ? null : () => context.push(route),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(icon: insight.icon, tone: tone),
          Gap.w12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.title,
                  style: context.text.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(insight.detail, style: context.text.bodySmall),
                if (insight.actionLabel != null) ...[
                  Gap.h8,
                  Text(
                    insight.actionLabel!,
                    style: context.text.labelMedium?.copyWith(color: tone),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
