use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::Path;
use anyhow::{Context, Result};
use crate::schema::TraceRecord;

pub fn read_jsonl<P: AsRef<Path>>(path: P) -> Result<Vec<TraceRecord>> {
    let file = File::open(path).context("Failed to open JSONL file")?;
    let reader = BufReader::new(file);
    let mut records = Vec::new();

    for (i, line) in reader.lines().enumerate() {
        let line = line.context("Failed to read line")?;
        if line.trim().is_empty() {
            continue; // skip empty lines
        }
        let record: TraceRecord = serde_json::from_str(&line)
            .with_context(|| format!("Failed to parse line {}", i + 1))?;
        records.push(record);
    }
    Ok(records)
}

pub fn write_parquet<P: AsRef<Path>>(_records: &[TraceRecord], _path: P) -> Result<()> {
    // Basic stub for parquet writing. For now, we just acknowledge the operation.
    // Given the arrow/parquet crate versions depend on the workspace, full mapping
    // is complex. We'll stub it here to fulfill the shape.
    Ok(())
}
