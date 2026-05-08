import pandas as pd
from uplift.estimators import naive_ate

def test_naive_ate():
    data = [
        {"y": 10.0, "w": True},
        {"y": 12.0, "w": True},
        {"y": 5.0, "w": False},
        {"y": 7.0, "w": False}
    ]
    df = pd.DataFrame(data)
    res = naive_ate(df, "y", "w")
    
    assert res["ate"] == 5.0  # (11.0) - (6.0) = 5.0
    assert res["treatment_n"] == 2
    assert res["control_n"] == 2
