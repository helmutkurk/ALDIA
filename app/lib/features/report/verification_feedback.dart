import '../../core/strings.dart';
import '../../data/report.dart';

class VerificationFeedback {
  const VerificationFeedback(this.title, this.reason, this.fix);
  final String title;
  final String reason;
  final String fix;
}

VerificationFeedback feedbackFor(VerificationCheck check, String category) {
  final title = S.checkTitles[check.name] ?? S.checks;
  if (check.passed) return VerificationFeedback(title, S.checkPassed, '');
  final (reason, fix) = switch (check.name) {
    'category' => (S.categoryReason(category), S.categoryFix),
    'place' => (S.placeReason, S.placeFix),
    'duplicate' => (S.duplicateReason, S.duplicateFix),
    'freshness' => (S.freshnessReason, S.freshnessFix),
    'image' => (S.imageReason, S.imageFix),
    _ => (S.checkUnknown, S.checkUnknownFix),
  };
  return VerificationFeedback(title, reason, fix);
}

List<VerificationCheck> orderedFailures(Verification verification) {
  // Easiest fix first: one tap, then moving the pin, then a new photo.
  const order = ['category', 'place', 'duplicate', 'freshness', 'image'];
  int rank(String name) => order.contains(name) ? order.indexOf(name) : 5;
  return verification.checks.where((c) => !c.passed).toList()
    ..sort((a, b) => rank(a.name).compareTo(rank(b.name)));
}
