//! Canonical trace record schema for the Uplift Core agent stack.
//!
//! Two writers produce records in this format and append them to the
//! configured JSONL file (default: `state/uplift-trace.jsonl`):
//!
//! 1. The vLLM **instrumentation proxy** emits one `kind = LlmRequest`
//!    record per `/v1/chat/completions` HTTP roundtrip. It captures
//!    wire-level data — model, prompt/completion tokens, latency — plus
//!    treatment metadata propagated by the caller via custom HTTP
//!    headers (`X-Uplift-Treatment`, `X-Uplift-Operator-Id`,
//!    `X-Uplift-Task-Cohort`, `X-Uplift-Session-Id`, `X-Uplift-Turn-Id`).
//! 2. The zeroclaw daemon's `UpliftObserver` emits one `kind = Turn`
//!    record per agent turn. It aggregates the turn's tool calls,
//!    join-keys to the proxy records via `session_id` / `turn_id`, and
//!    carries deployment-specific outcome measurements in `outcomes`.
//!
//! Both writers re-implement this schema independently — the zeroclaw
//! submodule does not depend on this crate at compile time. When the
//! schema changes, both writers and this module must move together.
//!
//! # Versioning
//!
//! v0.2 ships [`SCHEMA_VERSION`] = 1. Breaking changes bump the version
//! and require a migration utility in [`crate::io`] before the new
//! version is emitted by any writer. Readers must reject records with
//! unknown `schema_version` rather than silently coerce.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Wire-format schema version. Incremented on breaking changes; readers
/// must reject records with unknown values.
pub const SCHEMA_VERSION: u32 = 1;

/// One JSONL record. Discriminated by [`kind`](TraceRecord::kind) into
/// either a wire-level LLM request (proxy) or an aggregated agent turn
/// (observer). Records are append-only; correlate proxy and observer
/// records via `(session_id, turn_id)`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TraceRecord {
    /// Schema version; readers reject unknown values.
    pub schema_version: u32,
    /// Unique record ID (per-row UUID).
    pub id: Uuid,
    /// Wallclock UTC timestamp at record emission.
    pub timestamp_utc: DateTime<Utc>,
    /// Discriminator — see [`TraceKind`].
    pub kind: TraceKind,
    /// Conversation/session identifier. Matches across all records
    /// belonging to the same session.
    pub session_id: Uuid,
    /// Agent-loop turn identifier. Matches across all records
    /// belonging to the same turn (typically: 1 observer record + N
    /// proxy records when the agent makes N LLM calls in the turn).
    pub turn_id: Uuid,

    // ─── Treatment metadata (causal labels) ──────────────────────────

    /// Treatment label (e.g. `"baseline"`, `"assisted"`, or a richer
    /// label per deployment). `None` means unset; estimators must
    /// either treat unset as a separate cohort or skip such records.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub treatment: Option<String>,
    /// Stable, consented operator identifier. The unit of analysis for
    /// HTE. `None` only for synthetic / unattributed runs.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub operator_id: Option<String>,
    /// Task cohort (e.g. `"alert.water_quality"`, `"intake.bulk"`).
    /// Used to match comparable runs across treatment arms.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub task_cohort: Option<String>,

    // ─── Inference attribution ───────────────────────────────────────

    /// Provider name (e.g. `"vllm"`, `"anthropic"`).
    pub provider: String,
    /// Served model name (matches `VLLM_SERVED_MODEL_NAME` for vLLM).
    pub model: String,

    // ─── Token / latency measurements ────────────────────────────────

    /// Prompt tokens billed by the provider. Always present for
    /// `LlmRequest` records; aggregated sum on `Turn` records.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub input_tokens: Option<u64>,
    /// Completion tokens billed by the provider. Aggregated on `Turn`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub output_tokens: Option<u64>,
    /// End-to-end latency in milliseconds. For `LlmRequest`: HTTP
    /// roundtrip. For `Turn`: end-to-end turn time including tool
    /// execution and sleeping waits.
    pub latency_ms: u64,

    // ─── Turn-only fields ────────────────────────────────────────────

    /// Tool calls executed during the turn. Empty on `LlmRequest`
    /// records (the proxy doesn't see tool execution; only LLM calls).
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub tool_calls: Vec<ToolCallRecord>,
    /// Number of `LlmRequest` records expected for this turn — useful
    /// for join-side validation against the proxy stream. Set on
    /// `Turn` records; ignored on `LlmRequest`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub n_llm_requests: Option<u32>,
    /// Whether the turn (or LLM request) succeeded.
    pub success: bool,
    /// Error message when `success = false`, otherwise `None`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    /// Deployment-specific outcome measurements. Free-form JSON object;
    /// schema is owned by the deployment scoping doc (see
    /// `docs/deployments/`). Set on `Turn` records when an outcome is
    /// known at turn-end. Common cases: empty `{}` (outcome attached
    /// later via a separate ETL), or populated with a single metric
    /// like `{"time_to_correct_action_ms": 8234}`.
    #[serde(default, skip_serializing_if = "is_null_or_empty_object")]
    pub outcomes: serde_json::Value,

    // ─── Free-form extension ─────────────────────────────────────────

    /// Provider/proxy-specific metadata. Used for things like the
    /// vLLM request ID (when present in response headers), retry
    /// counts, prefix-cache-hit rates, etc. Estimators should not
    /// depend on these fields.
    #[serde(default, skip_serializing_if = "is_null_or_empty_object")]
    pub metadata: serde_json::Value,
}

/// Discriminator for [`TraceRecord`]. The `lowercase` rename matches
/// the convention used by the Python reader and the Parquet column.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TraceKind {
    /// One HTTP roundtrip to the inference provider, captured by the
    /// vLLM instrumentation proxy.
    LlmRequest,
    /// One end-to-end agent turn, aggregated by the zeroclaw
    /// `UpliftObserver` from the constituent LLM calls and tool calls.
    Turn,
}

/// Per-tool-call record nested inside a [`TraceRecord`] of kind
/// [`TraceKind::Turn`]. Intentionally minimal — full tool args and
/// results live in the agent's session log, not in the trace stream.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolCallRecord {
    /// Tool name (e.g. `"shell"`, `"jetson__system"`).
    pub name: String,
    /// Tool execution wallclock latency.
    pub duration_ms: u64,
    /// Whether the tool execution returned successfully.
    pub success: bool,
    /// Error message when `success = false`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

fn is_null_or_empty_object(v: &serde_json::Value) -> bool {
    match v {
        serde_json::Value::Null => true,
        serde_json::Value::Object(map) => map.is_empty(),
        _ => false,
    }
}

impl TraceRecord {
    /// Returns true if this record carries enough fields to participate
    /// in a treatment-effect estimate (treatment + operator_id present).
    pub fn is_attributable(&self) -> bool {
        self.treatment.is_some() && self.operator_id.is_some()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_turn() -> TraceRecord {
        TraceRecord {
            schema_version: SCHEMA_VERSION,
            id: Uuid::new_v4(),
            timestamp_utc: Utc::now(),
            kind: TraceKind::Turn,
            session_id: Uuid::new_v4(),
            turn_id: Uuid::new_v4(),
            treatment: Some("assisted".into()),
            operator_id: Some("op-001".into()),
            task_cohort: Some("alert.water_quality".into()),
            provider: "vllm".into(),
            model: "gemma-4-26b-a4b".into(),
            input_tokens: Some(5620),
            output_tokens: Some(10),
            latency_ms: 3151,
            tool_calls: vec![ToolCallRecord {
                name: "jetson__system".into(),
                duration_ms: 42,
                success: true,
                error: None,
            }],
            n_llm_requests: Some(2),
            success: true,
            error: None,
            outcomes: serde_json::json!({"time_to_correct_action_ms": 8234}),
            metadata: serde_json::Value::Null,
        }
    }

    #[test]
    fn turn_record_roundtrips_jsonl() {
        let rec = sample_turn();
        let line = serde_json::to_string(&rec).unwrap();
        let back: TraceRecord = serde_json::from_str(&line).unwrap();
        assert_eq!(back.kind, TraceKind::Turn);
        assert_eq!(back.session_id, rec.session_id);
        assert_eq!(back.turn_id, rec.turn_id);
        assert_eq!(back.treatment, rec.treatment);
        assert_eq!(back.operator_id, rec.operator_id);
        assert_eq!(back.outcomes, rec.outcomes);
        assert_eq!(back.tool_calls.len(), 1);
    }

    #[test]
    fn omits_unset_optionals_in_serialization() {
        let mut rec = sample_turn();
        rec.treatment = None;
        rec.operator_id = None;
        rec.error = None;
        rec.outcomes = serde_json::Value::Null;
        rec.metadata = serde_json::Value::Null;
        let line = serde_json::to_string(&rec).unwrap();
        assert!(!line.contains("\"treatment\""));
        assert!(!line.contains("\"operator_id\""));
        assert!(!line.contains("\"error\""));
        assert!(!line.contains("\"outcomes\""));
        assert!(!line.contains("\"metadata\""));
    }

    #[test]
    fn is_attributable_requires_treatment_and_operator() {
        let mut rec = sample_turn();
        assert!(rec.is_attributable());
        rec.operator_id = None;
        assert!(!rec.is_attributable());
        rec.operator_id = Some("op-001".into());
        rec.treatment = None;
        assert!(!rec.is_attributable());
    }

    #[test]
    fn kind_serializes_as_snake_case() {
        let s = serde_json::to_string(&TraceKind::LlmRequest).unwrap();
        assert_eq!(s, "\"llm_request\"");
        let s = serde_json::to_string(&TraceKind::Turn).unwrap();
        assert_eq!(s, "\"turn\"");
    }
}
