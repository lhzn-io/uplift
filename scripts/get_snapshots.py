#!/usr/bin/env python3
import os
import sys

def get_latest_snapshot(repo_name):
    for base in ["/home/lhzn/.cache/huggingface/hub", "/home/lhzn/.cache/huggingface"]:
        repo_dir = os.path.join(base, f"models--{repo_name.replace('/', '--')}")
        snapshots_dir = os.path.join(repo_dir, "snapshots")
        if os.path.exists(snapshots_dir):
            snapshots = os.listdir(snapshots_dir)
            if snapshots:
                is_hub = "hub" in base
                return snapshots[0], is_hub
    return None, False

def main():
    base_model = "cyankiwi/gemma-4-26B-A4B-it-AWQ-4bit"
    imta_lora = "lhzn-io/imta-expert-gemma4-26b-a4b-it-lora"
    biologger_lora = "lhzn-io/biologger-expert-gemma4-26b-a4b-it-lora"
    
    base_sha, base_in_hub = get_latest_snapshot(base_model)
    imta_sha, imta_in_hub = get_latest_snapshot(imta_lora)
    biologger_sha, biologger_in_hub = get_latest_snapshot(biologger_lora)
    
    if not base_sha:
        print(f"Error: Base model '{base_model}' snapshot not found in cache.", file=sys.stderr)
        sys.exit(1)
        
    base_container_path = f"/data/models/huggingface/{'hub/' if base_in_hub else ''}models--{base_model.replace('/', '--')}/snapshots/{base_sha}"
    
    print("=" * 70)
    print("COPY AND PASTE THE FOLLOWING LINES DIRECTLY INTO YOUR .env FILE:")
    print("=" * 70)
    print("REASONING_ENGINE_DIR=/home/lhzn/.cache/huggingface")
    print(f"VLLM_MODEL={base_container_path}")
    print("VLLM_SERVED_MODEL_NAME=gemma-4-26b-a4b")
    
    lora_modules = []
    if imta_sha:
        imta_container_path = f"/data/models/huggingface/{'hub/' if imta_in_hub else ''}models--{imta_lora.replace('/', '--')}/snapshots/{imta_sha}"
        lora_modules.append(f"imta-expert={imta_container_path}")
    if biologger_sha:
        biologger_container_path = f"/data/models/huggingface/{'hub/' if biologger_in_hub else ''}models--{biologger_lora.replace('/', '--')}/snapshots/{biologger_sha}"
        lora_modules.append(f"biologger-expert={biologger_container_path}")
        
    if lora_modules:
        lora_args = f"--enable-lora --lora-modules {' '.join(lora_modules)}"
        print(f'VLLM_EXTRA_ARGS="--enable-auto-tool-choice --reasoning-parser gemma4 --tool-call-parser gemma4 --quantization compressed-tensors --moe-backend triton {lora_args}"')
    else:
        print('VLLM_EXTRA_ARGS="--enable-auto-tool-choice --reasoning-parser gemma4 --tool-call-parser gemma4 --quantization compressed-tensors --moe-backend triton"')
        
    print("HF_HUB_OFFLINE=1")
    print("TRANSFORMERS_OFFLINE=1")
    print("HF_DATASETS_OFFLINE=1")
    print("=" * 70)

if __name__ == "__main__":
    main()

