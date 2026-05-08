import click
from .io import read_jsonl, write_parquet
from .estimators import naive_ate

@click.group()
def main():
    pass

@main.command()
@click.argument('input_file')
@click.argument('outcome_col')
@click.argument('treatment_col')
def ate(input_file, outcome_col, treatment_col):
    """Calculate naive ATE from a trace file."""
    df = read_jsonl(input_file)
    result = naive_ate(df, outcome_col, treatment_col)
    click.echo(f"ATE: {result['ate']}")
    click.echo(f"Control N: {result['control_n']}")
    click.echo(f"Treatment N: {result['treatment_n']}")

if __name__ == '__main__':
    main()
