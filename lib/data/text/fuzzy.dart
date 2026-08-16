/// Fuzzy matching against a closed vocabulary.
///
/// Extracted from the Quick Entry parser so the notebook reader matches names
/// by exactly the same rules. Two matchers that disagree about whether
/// "purifed" is "Purified 5-Gallon Refill" would be a bug the user experiences
/// as the app being inconsistent with itself.
library;

/// A query must account for this much of the utterance before a match is
/// believed. Below it, decline rather than guess.
const minimumScore = 0.6;

/// Two candidates closer than this are treated as indistinguishable.
const tieMargin = 0.15;

List<String> tokenise(String input) => input
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9\s.]'), ' ')
    .split(RegExp(r'\s+'))
    .where((t) => t.isNotEmpty)
    .toList();

bool tokenMatches(String query, String target) {
  if (query == target) return true;
  // Prefixes only from three characters, so "5" does not match "5-Gallon" and
  // "a" does not match everything.
  if (query.length >= 3 && target.startsWith(query)) return true;
  if (target.length >= 3 && query.startsWith(target)) return true;
  return false;
}

/// Fraction of the query that appears in the target, weighted by token length.
///
/// Token-subset rather than edit distance over whole strings: "purified refill"
/// has to match "Purified 5-Gallon Refill", and whole-string distance scores
/// that pair badly because of the words in between. The length weighting stops
/// a stray "5" from carrying a match on its own.
double score(List<String> query, String target) {
  final targetTokens = tokenise(target);
  if (targetTokens.isEmpty) return 0;

  var matched = 0.0;
  var total = 0.0;
  for (final q in query) {
    final weight = q.length.toDouble();
    total += weight;
    if (targetTokens.any((t) => tokenMatches(q, t))) matched += weight;
  }
  return total == 0 ? 0 : matched / total;
}

/// Every candidate clearing [minimumScore], best first.
///
/// The notebook reader needs the whole shortlist rather than the winner:
/// when "refill" fits two products equally, the amount written beside it is
/// what separates them, and that check happens after this returns.
/// [threshold] can be lowered below [minimumScore] by a caller that has an
/// independent way to confirm the match. The notebook reader does — a name it
/// only half-recognises is still proved by the amount beside it adding up.
List<({T item, double score})> rank<T>(
  List<String> query,
  List<T> candidates,
  String Function(T) name, {
  double threshold = minimumScore,
}) {
  if (query.isEmpty || candidates.isEmpty) return const [];
  return candidates
      .map((c) => (item: c, score: score(query, name(c))))
      .where((s) => s.score >= threshold)
      .toList()
    ..sort((a, b) => b.score.compareTo(a.score));
}

/// Highest-scoring candidate, or null when nothing clears the bar or two
/// candidates are too close to separate.
T? bestMatch<T>(
  List<String> query,
  List<T> candidates,
  String Function(T) name,
) {
  final scored = rank(query, candidates, name);
  if (scored.isEmpty) return null;
  // "refill" matches two products equally well. Guessing between them is how
  // the wrong product ends up on a receipt, so decline instead.
  if (scored.length > 1 && (scored[0].score - scored[1].score) < tieMargin) {
    return null;
  }
  return scored.first.item;
}
