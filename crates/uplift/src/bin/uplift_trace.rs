use anyhow::Result;
use clap::Parser;
use std::path::PathBuf;
use uplift::{read_jsonl, write_parquet, naive_ate};

#[derive(Parser, Debug)]
#[command(name = "uplift-trace", about = "Convert JSONL traces to Parquet and run basic ATE computation")]
struct Opts {
    #[arg(required = true, help = "Input JSONL file")]
    input: PathBuf,

    #[arg(short, long, help = "Output Parquet file")]
    output: Option<PathBuf>,

    #[arg(long, help = "Compute Naive ATE")]
    compute_ate: bool,
}

fn main() -> Result<()> {
    let opts = Opts::parse();
    println!("uplift-trace v0.2.0 starting...");
    
    let records = read_jsonl(&opts.input)?;
    println!("Read {} records.", records.len());

    if let Some(out) = opts.output {
        write_parquet(&records, &out)?;
        println!("Stored records to {}", out.display());
    }

    if opts.compute_ate {
        // Evaluate everything as control (stub metrics)
        let effect = naive_ate(&records, |_| 1.0, |_| false);
        println!("ATE Result: {:?}", effect);
    }
    
    Ok(())
}
