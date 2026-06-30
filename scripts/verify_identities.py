#!/usr/bin/env python3
import urllib.request
import json
import random
import sys
import os

def generate_id(prefix):
    return f"{prefix}-{random.randint(10000, 99999)}"

def post_webhook(port, message):
    url = f"http://127.0.0.1:{port}/webhook"
    data = {"message": message}
    req = urllib.request.Request(
        url,
        data=json.dumps(data).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            return json.loads(response.read().decode("utf-8"))
    except Exception as e:
        print(f"Error calling webhook on port {port}: {e}", file=sys.stderr)
        return None

def main():
    op_workspace = "/home/uplift/Projects/lhzn-io/uplift/.zeroclaw-operator/workspace"
    op_challenge_file = os.path.join(op_workspace, "state", "operator_challenge.json")
    
    # Ensure directories are writable
    try:
        os.chmod(op_workspace, 0o700)
    except Exception:
        pass
    os.makedirs(os.path.dirname(op_challenge_file), exist_ok=True)
    try:
        os.chmod(os.path.dirname(op_challenge_file), 0o700)
    except Exception:
        pass
    
    op_id = generate_id("OP-CHALLENGE")
    print(f"[*] Generated Operator challenge ID: {op_id}")
    op_prompt = (
        f"Solve the following reasoning problem step-by-step: If you have a drawer with "
        f"4 blue socks and 6 black socks, and you randomly pull out 2 socks without replacement, "
        f"what is the probability that you get a matching pair (both blue or both black)?\n"
        f"Note: You MUST explicitly include the challenge identifier '{op_id}' in your final response."
    )
    
    print("[*] Sending challenge to Operator Agent (port 42617)...")
    op_res = post_webhook(42617, op_prompt)
    if not op_res or "response" not in op_res:
        print("[!] Operator query failed or timed out", file=sys.stderr)
        sys.exit(1)
        
    op_text = op_res["response"]
    print("[+] Operator response received.")
    
    log_data = {
        "challenge_id": op_id,
        "operator_response": op_text
    }
    with open(op_challenge_file, "w") as f:
        json.dump(log_data, f, indent=2)
    print(f"[*] Staged Operator response in Operator workspace: {op_challenge_file}")
    
    ad_id = generate_id("AD-CHALLENGE")
    print(f"[*] Generated Admin challenge ID: {ad_id}")
    
    ad_prompt = (
        f"Solve the following reasoning problem step-by-step: If a box has 5 green apples "
        f"and 7 red apples, and we draw 3 without replacement, what is the probability of "
        f"getting exactly 2 green apples and 1 red apple?\n"
        f"Operator Verification Check: Read the file `/zeroclaw-data/operator_workspace/state/operator_challenge.json`. "
        f"Extract the Operator's unique challenge identifier and its final probability result.\n"
        f"Note: You MUST explicitly include the challenge identifier '{ad_id}' in your final response."
    )
    
    print("[*] Sending challenge to Admin Agent (port 42618)...")
    ad_res = post_webhook(42618, ad_prompt)
    if not ad_res or "response" not in ad_res:
        print("[!] Admin query failed or timed out", file=sys.stderr)
        sys.exit(1)
        
    ad_text = ad_res["response"]
    print("[+] Admin response received.")
    print("\n================== ADMIN RESPONSE ==================")
    print(ad_text)
    print("====================================================\n")
    
    verified = True
    if op_id not in ad_text:
        print(f"[!] Verification FAIL: Admin did not reference the Operator challenge ID '{op_id}'")
        verified = False
    if ad_id not in ad_text:
        print(f"[!] Verification FAIL: Admin did not include its own challenge ID '{ad_id}'")
        verified = False
        
    if verified:
        print("[✓] Challenge-Response Verification SUCCESSFUL!")
        sys.exit(0)
    else:
        sys.exit(1)

if __name__ == "__main__":
    main()
