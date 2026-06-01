#!/bin/sh
# zeroclaw_entrypoint.sh - Codified Web UI patcher and entrypoint for ZeroClaw

# 1. Apply the monkey patch to the config chunk inside the container
sed -i 's/sambanova:\[/vllm:\[{value:"gemma-4-26b-a4b",label:"Gemma 4 26B (Base)"},{value:"imta-expert",label:"IMTA-Expert"},{value:"biologger-expert",label:"Biologger-Expert"}],sambanova:\[/g' /zeroclaw-data/web/dist/assets/Config-*.js

# 2. Run the original ZeroClaw entrypoint
exec zeroclaw "$@"
