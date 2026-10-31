//! Schema compatibility with the ZeroClaw fork's per-turn trace writer.
//!
//! The lab fork (`lhzn-io/zeroclaw`, `crates/zeroclaw-runtime/src/observability/uplift_trace.rs`)
//! writes uplift `TraceRecord` v1 lines without depending on this crate. It keeps a golden
//! fixture of its output; this test parses that fixture with the schema defined here, so a
//! drift on either side fails the build.

use std::path::PathBuf;

use uplift::schema::{TraceKind, SCHEMA_VERSION};

fn fixture_path() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../stack/zeroclaw/crates/zeroclaw-runtime/tests/fixtures/uplift_trace_v1.jsonl")
}

#[test]
fn zeroclaw_fixture_parses_as_trace_record() {
    let path = fixture_path();
    if !path.exists() {
        // The submodule is not checked out (for example a shallow CI clone).
        eprintln!("skipping: {} not found; run `git submodule update --init`", path.display());
        return;
    }

    let records = uplift::read_jsonl(&path).expect("fork fixture must parse as TraceRecord");
    assert_eq!(records.len(), 1, "fixture holds exactly one record");

    let r = &records[0];
    assert_eq!(r.schema_version, SCHEMA_VERSION);
    assert!(matches!(r.kind, TraceKind::Turn));
    assert_eq!(r.provider, "vllm");
    assert_eq!(r.input_tokens, Some(5620));
    assert_eq!(r.n_llm_requests, Some(2));
    assert_eq!(r.tool_calls.len(), 2);
    assert!(r.tool_calls.iter().any(|t| !t.success && t.error.as_deref() == Some("boom")));
    assert_eq!(r.metadata["channel"], "slack");
}
