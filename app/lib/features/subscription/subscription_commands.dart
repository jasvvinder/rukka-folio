// The two things a subscription screen can *ask for* — cancel at period end
// (S12.3) and retry a failed payment (S12.4) — as a seam beside
// `EntitlementSource`, which only ever reads.
//
// ⛔ **No producer, and none invented.** There is no gateway SDK and no IAP
// package in this app: PLAN desk item 11 leaves the payment channel an owner
// decision (ADR 2026-09-05g §8 🔒 rules *which* channel, not *which package*).
// So the shipped implementation is [UnwiredSubscriptionCommands], which
// answers [RkCommandUnavailable] — the honest answer — and the screens render
// that as **disabled-with-reason** (07 §1 rule 6), never as a tap that
// silently does nothing and never as a fake success.
//
// 🔒 **Failure is error-with-retry, never a dead end** (08 §3.1: "Failure →
// inline error + retry or alternate method, never a dead end"). That is why
// the outcome is a *sealed* family rather than a bool: the three answers a
// screen must tell apart — it happened, it failed and may be tried again, it
// cannot be asked for at all — are three types, so no call site can collapse
// two of them by accident.
//
// No clock and no network here: `effectiveOn` is a date the *channel* states
// (the period end it has on file), not one this app works out — ADR
// 2026-09-05g §4's clock floor is the server's rule.
library;

/// What came back from a subscription command.
///
/// Sealed on purpose: `switch` over it is exhaustive, so a new outcome cannot
/// be added without every screen being made to say what it shows for it.
sealed class RkCommandOutcome {
  /// Creates an outcome.
  const RkCommandOutcome();
}

/// The channel accepted the command.
final class RkCommandDone extends RkCommandOutcome {
  /// Creates the outcome.
  const RkCommandDone({this.effectiveOn});

  /// When it takes effect, as **the channel** stated it — for
  /// [SubscriptionCommands.cancelAtPeriodEnd] this is the end of the paid
  /// period, i.e. the day access changes, which S12.3 then shows. Null where
  /// the command takes effect at once (a retried payment).
  final DateTime? effectiveOn;
}

/// The channel was reached and said no, or could not be reached. The screen
/// shows the reason and offers the same button again (08 §3.1 🔒).
final class RkCommandFailed extends RkCommandOutcome {
  /// Creates the outcome.
  const RkCommandFailed();
}

/// There is no channel to ask. Not an error and not a failure — a door that
/// has not been built (PLAN desk item 11), shown disabled with the reason
/// written beside it.
final class RkCommandUnavailable extends RkCommandOutcome {
  /// Creates the outcome.
  const RkCommandUnavailable();
}

/// The commands a subscription screen can issue.
///
/// Two methods, because these are the two verbs 07 §20 and DESIGN-PACK §11
/// give S12.3 and S12.4. Changing a *plan* is not here: that is S12.1 → S12.2
/// Checkout, a screen, not a command.
abstract interface class SubscriptionCommands {
  /// Ask that the subscription not renew: it runs to `period_end` and stops.
  ///
  /// 🔒 Nothing is deleted and nothing is locked by this (08 §1 principle 4):
  /// after the period ends the tenant is read-only — reading, exporting and
  /// closing carry on. The screen states that **before** the command is
  /// issued, never after.
  ///
  /// 🔒 On iOS this is **not** ours to issue: Apple is merchant of record and
  /// cancellation lives in the device's subscription settings (ADR
  /// 2026-09-05g §8, DESIGN-PACK §11 S12.3). S12.3 does not call this on an
  /// Apple platform at all.
  Future<RkCommandOutcome> cancelAtPeriodEnd();

  /// Ask the channel to attempt the failed renewal again (S12.4 *Retry*).
  Future<RkCommandOutcome> retryPayment();
}

/// The shipped implementation: every command answers
/// [RkCommandUnavailable].
///
/// This is not a stub standing in for behaviour — with no payment channel
/// chosen there is no command to send, and saying so is the only honest
/// answer. When the channel lands it replaces this class and nothing above it
/// changes.
class UnwiredSubscriptionCommands implements SubscriptionCommands {
  /// Creates the implementation.
  const UnwiredSubscriptionCommands();

  @override
  Future<RkCommandOutcome> cancelAtPeriodEnd() async =>
      const RkCommandUnavailable();

  @override
  Future<RkCommandOutcome> retryPayment() async => const RkCommandUnavailable();
}

/// Test double: records what was asked and answers what it was built with.
class FakeSubscriptionCommands implements SubscriptionCommands {
  /// Creates the fake.
  FakeSubscriptionCommands({RkCommandOutcome? cancel, RkCommandOutcome? retry})
    : cancelOutcome = cancel ?? const RkCommandDone(),
      retryOutcome = retry ?? const RkCommandDone();

  /// What [cancelAtPeriodEnd] answers.
  RkCommandOutcome cancelOutcome;

  /// What [retryPayment] answers.
  RkCommandOutcome retryOutcome;

  /// How many times [cancelAtPeriodEnd] was called — so a test can assert the
  /// command reached the seam, and that an iOS screen never issued it.
  int cancels = 0;

  /// How many times [retryPayment] was called.
  int retries = 0;

  @override
  Future<RkCommandOutcome> cancelAtPeriodEnd() async {
    cancels++;
    return cancelOutcome;
  }

  @override
  Future<RkCommandOutcome> retryPayment() async {
    retries++;
    return retryOutcome;
  }
}
