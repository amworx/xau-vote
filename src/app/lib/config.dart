/// Global build flags for the XAU Radar app.
///
/// [mockMode] runs every screen fully offline from local fixtures
/// ([MockFixtures]) with zero Supabase/Firebase configuration. Flip to
/// `false` only when the live backend (TASK-04) and Firebase project are
/// provisioned; see [BackendService] for the guarded wiring.
const bool mockMode = true;
