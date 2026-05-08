import json
import pandas as pd

def read_jsonl(path: str) -> pd.DataFrame:
    records = []
    with open(path, 'r') as f:
        for line in f:
            if line.strip():
                records.append(json.loads(line))
    return pd.DataFrame(records)

def write_parquet(df: pd.DataFrame, path: str):
    df.to_parquet(path)
