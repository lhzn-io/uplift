use async_trait::async_trait;
use serde_json::json;
use std::fs::OpenOptions;
use std::io::Write;
use std::path::{Path, PathBuf};
use uuid::Uuid;

use uplift::schema::{TraceKind, TraceRecord, ToolCallRecord as UpliftToolCallRecord, SCHEMA_VERSION};
use zeroclaw_runtime::hooks::{HookHandler, TurnRecord};

pub struct UpliftObserver {
    pub path: PathBuf,
}

impl UpliftObserver {
    pub fn new() -> Self {
        // Read path from env, defaulting to state/uplift-trace.jsonl
        let path = std::env::var("UPLIFT_TRACE_PATH")
            .unwrap_or_else(|_| "workspace/state/uplift-trace.jsonl".to_string());
        
        // Ensure parent directories exist
        if let Some(p) = Path::new(&path).parent() {
            let _ = std::fs::create_dir_all(p);
        }

        Self {
            path: PathBuf::from(path),
        }
    }
}

#[async_trait]
impl HookHandler for UpliftObserver {
    fn name(&self) -> &str {
        "uplift"
    }

    async fn on_turn_complete(&self, turn: &TurnRecord) {
        let session_id = turn
            .session_id
            .as_deref()
            .and_then(|id| Uuid::parse_str(id).ok())
            .unwrap_or_else(Uuid::new_v4);

        let turn_id = Uuid::parse_str(&turn.turn_id).unwrap_or_else(|_| Uuid::new_v4());

        // Extract treatment metadata from env
        let treatment = std::env::var("UPLIFT_TREATMENT").ok();
        let operator_id = std::env::var("UPLIFT_OPERATOR_ID").ok();
        let task_cohort = std::env::var("UPLIFT_TASK_COHORT").ok();

        let tool_calls = turn
            .tool_calls
            .iter()
            .map(|tc| UpliftToolCallRecord {
                name: tc.name.clone(),
                duration_ms: tc.duration_ms,
                success: tc.success,
                error: tc.error.clone(),
            })
            .collect();

        let record = TraceRecord {
            schema_version: SCHEMA_VERSION,
            id: Uuid::new_v4(),
            timestamp_utc: turn.timestamp_utc,
            kind: TraceKind::Turn,
            session_id,
            turn_id,
            treatment,
            operator_id,
            task_cohort,
            provider: turn.provider.clone(),
            model: turn.model.clone(),
            input_tokens: turn.input_tokens,
            output_tokens: turn.output_tokens,
            latency_ms: turn.latency_ms,
            tool_calls,
            n_llm_requests: None, 
            success: turn.success,
            error: turn.error.clone(),
            outcomes: json!({}),
            metadata: turn.metadata.clone(),
        };

        if let Ok(serialized) = serde_json::to_string(&record) {
            let mut file = OpenOptions::new()
                .create(true)
                .append(true)
                .open(&self.path);

            if let Ok(ref mut f) = file {
                let _ = writeln!(f, "{}", serialized);
            }
        }
    }
}

impl Default for UpliftObserver {
    fn default() -> Self {
        Self::new()
    }
}