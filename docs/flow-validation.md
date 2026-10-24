# Customer, owner and admin flow review

The follow-up review adds 20 regression cases in `test/flow_test.dart` and fixes
the client-side state/lifecycle issues they cover. The previous design and
product tests remain in place.

## Fixed

- Older visit refreshes cannot overwrite a newer result. Pagination rejects
  results from a previous account/session or an overlapping refresh, and two
  requests for the same page advance the page counter only once.
- Signing out or changing accounts clears profile drafts, unfinished business
  applications, MFA state, owner workspace data and booking receipts. Late
  action errors, enrolment secrets and notification results cannot update a
  different session, including signing back into the same account.
- Booking opens one confirmation at a time, snapshots its selected parameters
  and rejects confirmation from another session.
- Confirmation/forms are bound to the session that opened them. Sensitive
  dialogs replace their contents when access expires. This covers account
  deletion, cancellation, refund requests, private home addresses, business
  settings and protected admin decisions. Operator confirmations also require
  the current MFA session; the backend remains authoritative.
- Admin visit/refund screens do not request private data without both role and
  MFA. They hide existing private data immediately when access changes and
  ignore late responses.
- A successfully saved application has a local receipt even if account-status
  refresh fails. Refreshing status or retrying the notification never submits
  another application.
- Leaving Map drops its controller reference. Camera failures do not turn
  successful discovery into a failed search.

## Validation

- Flutter analysis: no issues.
- Flutter tests: 42 passed, including the 20 new flow regressions.
- Python bootstrap/branding/deployment tests: 9 passed.
- Web release build: passed; the existing Cupertino font warning remains.

All booking/payment/email/delete actions in the regression suite use test
backends. No real transaction, email, account deletion, database migration or
credential change was performed. Live OAuth/provider/device smoke tests are
still separate checks. Native configuration was not changed in this pass; the
previously documented Xcode dependency-graph issue and unavailable Android SDK
are not resolved by these Dart flow fixes.

Changes are committed locally for review, not pushed or deployed.
