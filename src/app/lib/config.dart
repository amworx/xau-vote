/// Global build flags for the XV (XAU-Vote) app.
///
/// [mockMode] selects the data source for every screen:
///   * `true`  (default) — [MockFixtures], fully offline, zero credentials.
///   * `false` — the live Supabase backend via [LiveRepository].
///
/// It is a `--dart-define` so one codebase produces both builds and a release
/// build can never silently ship fixtures as live data:
///
///   # offline demo (no configuration needed)
///   flutter run
///
///   # live backend
///   flutter run --dart-define=LIVE=true `
///     --dart-define=SUPABASE_URL=https://YOUR-REF.supabase.co `
///     --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
///
/// The Supabase URL/key are intentionally NOT baked into the repo — see
/// `docs/backend-runbook.md`. Only the publishable key belongs in a client
/// build; the service_role key never leaves the server.
library;

/// True when the app reads live Supabase data.
///
/// `bool.fromEnvironment` with a `true` default means a plain `flutter run`
/// stays offline and safe; live data requires an explicit opt-in flag.
const bool mockMode = !bool.fromEnvironment('LIVE');

/// Supabase project URL, supplied at build time in live mode.
const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

/// Supabase publishable (anon) key — safe for client builds, RLS-protected.
const String supabasePublishableKey =
    String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

/// Whether the live build was given usable Supabase configuration.
///
/// Guards the live path from throwing on a half-configured build: if the flag
/// is set but the credentials are missing, the app reports the misconfiguration
/// rather than silently falling back to fixtures (which would look like real
/// data to the user).
bool get liveConfigured =>
    supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
