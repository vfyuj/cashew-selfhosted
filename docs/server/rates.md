# Currency rates

Files: `server/lib/src/rates/rate_routes.dart` (read), `rate_admin_routes.dart` (overrides).
App side: `app/lib/struct/currencyFunctions.dart`.

## Why the server holds them at all

A rate is not data anyone owns — it is how everyone's data gets read. Two members of one household
looking at the same transaction have to convert it the same way, or their budgets and envelopes stop
reconciling.

They did not, before this. Each device fetched the published table itself and cached it in
`appStateSettings`, which lands in `AppSettings` row 0 — the one row deliberately excluded from the
change feed. So the cache never travelled, and two devices that last launched on different days
disagreed about every figure that crossed a currency. The reported symptom was one 18 950 ₽
transaction showing as 22 594 in one account and 22 837 in the other: not a sync bug, a rate that had
moved 1 % between two fetches.

The fix is structural rather than a sync change. **One deployment, one table, fetched once.** Nothing
has to agree because nothing is duplicated.

## Scope: instance, not dataset

Deliberately neither dataset-scoped nor user-scoped, unlike everything else the server stores. There
is no reason two households on one deployment would want different rates, and every reason a
household would break if its members had them. `exchange_rates` is a single row pinned to `id = 0` by
a `CHECK`; a second row would silently become a second answer.

## Fetching

Source is the same published feed the app used to call directly
(`@fawazahmed0/currency-api`, USD-based — which is why nothing is rebased: the app's conversion maths
already works in units-per-USD).

- Refreshed at most every `defaultRateRefreshInterval` (6 h). Household budgeting does not need
  intraday rates, and the point is that everyone agrees rather than that everyone is current.
- **Stale but present**: served immediately, refreshed behind the response. Nobody waits on a CDN
  round trip to redraw a screen.
- **Nothing cached at all**: that one request waits, then `503` if it still failed. Deliberately not
  an empty table — the app falls back to `1` on a missing rate, so an empty table would show rubles
  as dinars one for one instead of admitting it does not know.
- A failed refresh leaves `fetched_at` alone, so the next request retries rather than waiting out the
  interval on a table nobody received.
- Concurrent refreshes collapse onto one in-flight fetch.

Values that are not finite positive numbers are dropped on the way in. The app divides by a rate, so
a zero or a negative would poison every converted figure in the household at once. Same check guards
the override endpoint.

## Overrides

`exchange_rate_overrides` holds administrator-set values, folded into `GET /rates` server-side so
"what this deployment believes a currency is worth" has exactly one answer. The raw map ships
alongside so the rates screen can show which values were set by hand.

Administrator-only because a rate is a property of the deployment, and `is_admin` is the role that
owns deployment-wide decisions — see [auth.md](auth.md). This is the one place the fork has a
household-wide setting at all; the per-user mechanism cannot express one, because its rows are keyed
by user id (see [../app/settings.md](../app/settings.md)).

## The app never blocks on this

Per `specs/01-local-first-invariant.md`: an unreachable server leaves the previously fetched table in
place, and an account that has never signed in keeps calling the published feed directly. Rates are
how numbers are drawn, never a gate on reading or writing them.

---

Why: `specs/06-shared-household-data.md` (why a shared household forces a shared reading of it).
