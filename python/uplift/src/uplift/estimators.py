import pandas as pd
from typing import Callable

def naive_ate(df: pd.DataFrame, outcome_col: str, treatment_col: str) -> dict:
    if df.empty or outcome_col not in df.columns or treatment_col not in df.columns:
        return {"ate": 0.0, "control_n": 0, "treatment_n": 0}
        
    control = df[~df[treatment_col]]
    treatment = df[df[treatment_col]]
    
    control_mean = control[outcome_col].mean() if not control.empty else 0.0
    treatment_mean = treatment[outcome_col].mean() if not treatment.empty else 0.0
    
    # Simple difference in means
    ate = treatment_mean - control_mean
    
    return {
        "ate": float(ate),
        "control_n": len(control),
        "treatment_n": len(treatment)
    }
