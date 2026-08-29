#!/usr/bin/env bash
# Runs the live-backend smoke in `test_live/` against a LOCAL Supabase stack.
#
# What this covers that nothing else does: the real Dart gateway
# (`SupabaseHouseholdGateway`) talking to real Postgres with the real
# migrations and the real RLS policies. pgTAP (`supabase test db`) proves the
# SQL contract but never runs a line of Dart; the widget suite drives a fake
# gateway, which agrees with whatever the code believes; and Maestro runs
# permanently signed-out. So a gateway naming the wrong RPC, passing a wrong
# parameter name, or mis-reading a result was invisible to all three.
# db.yml's own header records that gap ("a Dart-only change altering how the
# client reads an RPC does not re-run these"); this closes it.
#
# Usage:
#   supabase start          # once
#   tool/live_smoke.sh
#
# The keys are read from `supabase status`, never hardcoded — they differ per
# machine and are worthless off localhost anyway.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! supabase status >/dev/null 2>&1; then
  cat >&2 <<'MSG'
live_smoke: no local Supabase stack is running.

    supabase start

Then re-run this script. This suite deliberately refuses to run against
anything but a loopback host (see test_live/household_exit_live_test.dart) --
`lib/app/supabase_config.dart` defaults to the PRODUCTION project when no
--dart-define is passed, and these tests create and delete accounts.
MSG
  exit 1
fi

status_json="$(supabase status -o json 2>/dev/null || supabase status 2>/dev/null | grep -m1 '^{')"

read_key() {
  printf '%s' "$status_json" \
    | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
    | head -1 \
    | sed -E "s/.*:[[:space:]]*\"([^\"]*)\"/\1/"
}

API_URL="$(read_key API_URL)"
ANON_KEY="$(read_key ANON_KEY)"
SERVICE_ROLE_KEY="$(read_key SERVICE_ROLE_KEY)"

if [ -z "$API_URL" ] || [ -z "$ANON_KEY" ] || [ -z "$SERVICE_ROLE_KEY" ]; then
  echo "live_smoke: could not read API_URL/ANON_KEY/SERVICE_ROLE_KEY from" >&2
  echo "  supabase status. Output was:" >&2
  printf '%s\n' "$status_json" | cut -c1-400 >&2
  exit 1
fi

# HARNESS-ONLY GRANTS, on this throwaway local database and nowhere else.
#
# The schema grants SELECT to `authenticated` only (see
# supabase/migrations/20260731120000_initial_schema.sql) -- `service_role` is
# deliberately given nothing, which is good and is NOT changed here. But the
# suite's assertions need GROUND TRUTH: "the row is gone" and "RLS is hiding
# the row from me" are indistinguishable if you can only read as the acting
# user, and asserting the weaker of the two is how a test passes while the
# feature is broken. So the harness reads as service_role.
#
# This runs against the local container only, is never in a migration, and
# cannot reach production -- the suite refuses any non-loopback host anyway.
# It does not widen what `authenticated` can do, which is what the RLS tests
# and the gateway under test actually exercise.
echo "live_smoke: granting harness read access on the local stack"
docker exec supabase_db_chore-app psql -U postgres -d postgres -q -c "
  grant usage on schema public to service_role;
  grant select on public.households to service_role;
  grant select on public.members to service_role;
" >/dev/null

echo "live_smoke: running test_live/ against $API_URL"

# `env -u GIT_DIR -u GIT_INDEX_FILE`: git sets these for hook subprocesses and
# Flutter's tool shells out to git for its own SDK version, reading back
# 0.0.0-unknown and failing dependency resolution. Same reasoning as
# lefthook.yml's analyze job.
#
# NOTE the path: `test_live/`, not `test/`. Bare `flutter test` discovers only
# `test/`, which is what keeps the ordinary suite hermetic and offline. Do not
# move these files under `test/` -- every widget test would then need a live
# stack, and `supabaseConfigured` must stay false for the suite (see
# lefthook.yml's test job).
exec env -u GIT_DIR -u GIT_INDEX_FILE flutter test test_live/ \
  --dart-define=SUPABASE_URL="$API_URL" \
  --dart-define=SUPABASE_ANON_KEY="$ANON_KEY" \
  --dart-define=SUPABASE_SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY"
