//! Trace schema and uplift estimators for the Uplift Core agent stack.
//!
//! This crate is the canonical source of truth for the trace record schema
//! emitted by the zeroclaw daemon (`UpliftObserver`) and the vLLM
//! instrumentation proxy. Both writers reproduce the wire format documented
//! in [`schema`]; they do not depend on this crate at compile time, which
//! keeps zeroclaw decoupled from the parent uplift workspace.
//!
//! Consumers — including the `uplift-trace` CLI in this crate and the
//! Python `uplift` package — read JSONL traces, materialize them as
//! [`TraceRecord`] values, and feed them into uplift estimators.
//!
//! # Modules
//!
//! - [`schema`] — wire-format types ([`TraceRecord`], [`TraceKind`],
//!   [`ToolCallRecord`], [`SCHEMA_VERSION`]).
//! - `io` *(coming in W3 body)* — JSONL reader and Parquet writer.
//! - `estimators` *(coming in W3 body)* — naive ATE, helpers for
//!   feeding scikit-uplift / upliftml / CausalML downstream.

pub mod schema;
pub mod io;
pub mod estimators;

pub use schema::{ToolCallRecord, TraceKind, TraceRecord, SCHEMA_VERSION};
pub use io::{read_jsonl, write_parquet};
pub use estimators::{naive_ate, TreatmentEffect};
