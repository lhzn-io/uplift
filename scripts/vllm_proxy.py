import json
import logging
import uuid
import datetime
import uvicorn
from fastapi import FastAPI, Request, Response
from fastapi.responses import StreamingResponse
import httpx
import sys
import os

app = FastAPI()
client = httpx.AsyncClient(base_url="http://127.0.0.1:8000", timeout=None)

TRACE_FILE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "workspace/state/uplift-trace.jsonl")

logging.basicConfig(level=logging.INFO, stream=sys.stdout)
logger = logging.getLogger("vllm-proxy")

@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "PATCH"])
async def proxy_all(request: Request, path: str):
    if path == "v1/chat/completions" and request.method == "POST":
        return await handle_chat_completion(request)
    
    url = httpx.URL(path=request.url.path, query=request.url.query.encode("utf-8"))
    req = client.build_request(
        request.method,
        url,
        headers=request.headers.raw,
        content=await request.body()
    )
    res = await client.send(req, stream=True)
    return StreamingResponse(res.aiter_raw(), status_code=res.status_code, headers=res.headers)

async def handle_chat_completion(request: Request):
    body = await request.body()
    req_json = {}
    try: req_json = json.loads(body)
    except: pass
    
    is_stream = req_json.get("stream", False)
    
    url = httpx.URL(path=request.url.path, query=request.url.query.encode("utf-8"))
    req = client.build_request(
        "POST",
        url,
        headers=request.headers.raw,
        content=body
    )
    
    start_time = datetime.datetime.now(datetime.timezone.utc)
    res = await client.send(req, stream=is_stream)
    
    if is_stream:
        async def stream_generator():
            status_code = res.status_code
            if status_code == 500:
                try:
                    with open(os.path.join(os.path.dirname(TRACE_FILE), "error_500_payload_stream.json"), "w") as f:
                        json.dump(req_json, f, indent=2)
                except:
                    pass
            content_chunks = []
            async for chunk in res.aiter_bytes():
                content_chunks.append(chunk)
                yield chunk
            end_time = datetime.datetime.now(datetime.timezone.utc)
            latency_ms = int((end_time - start_time).total_seconds() * 1000)
            
            input_tokens = None
            output_tokens = None
            for chunk in reversed(content_chunks):
                if b'"usage"' in chunk:
                    try:
                        lines = chunk.decode("utf-8").split("\n")
                        for line in lines:
                            if line.startswith("data: ") and "usage" in line and line != "data: [DONE]":
                                data = json.loads(line[6:])
                                if "usage" in data and data["usage"]:
                                    input_tokens = data["usage"].get("prompt_tokens")
                                    output_tokens = data["usage"].get("completion_tokens")
                                    break
                    except:
                        pass
                if input_tokens is not None:
                    break
            
            write_trace(request, req_json, status_code, latency_ms, input_tokens, output_tokens, None)
            
        return StreamingResponse(stream_generator(), status_code=res.status_code, headers=res.headers)
            
    else:
        res_body = await res.aread()
        end_time = datetime.datetime.now(datetime.timezone.utc)
        latency_ms = int((end_time - start_time).total_seconds() * 1000)
        
        input_tokens = None
        output_tokens = None
        success = (res.status_code == 200)
        error_msg = None
        
        if success:
            try:
                res_json = json.loads(res_body)
                usage = res_json.get("usage", {})
                input_tokens = usage.get("prompt_tokens")
                output_tokens = usage.get("completion_tokens")
            except:
                pass
        else:
            error_msg = f"HTTP {res.status_code}"
            if res.status_code == 500:
                try:
                    with open(os.path.join(os.path.dirname(TRACE_FILE), "error_500_payload.json"), "w") as f:
                        json.dump(req_json, f, indent=2)
                except:
                    pass
            
        write_trace(request, req_json, res.status_code, latency_ms, input_tokens, output_tokens, error_msg)
        return Response(content=res_body, status_code=res.status_code, headers=res.headers)

def write_trace(request, req_json, status_code, latency_ms, input_tokens, output_tokens, error_msg):
    treatment = request.headers.get("X-Uplift-Treatment")
    operator_id = request.headers.get("X-Uplift-Operator-Id")
    task_cohort = request.headers.get("X-Uplift-Task-Cohort")
    session_id = request.headers.get("X-Uplift-Session-Id", str(uuid.uuid4()))
    turn_id = request.headers.get("X-Uplift-Turn-Id", str(uuid.uuid4()))
    model_name = req_json.get("model", "unknown")
    success = (status_code == 200)
    
    os.makedirs(os.path.dirname(TRACE_FILE), exist_ok=True)
    try:
        record = {
            "schema_version": 1,
            "id": str(uuid.uuid4()),
            "timestamp_utc": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z"),
            "kind": "llm_request",
            "session_id": session_id,
            "turn_id": turn_id,
            "provider": "vllm",
            "model": model_name,
            "latency_ms": latency_ms,
            "success": success,
        }
        if treatment: record["treatment"] = treatment
        if operator_id: record["operator_id"] = operator_id
        if task_cohort: record["task_cohort"] = task_cohort
        if input_tokens is not None: record["input_tokens"] = input_tokens
        if output_tokens is not None: record["output_tokens"] = output_tokens
        if error_msg: record["error"] = error_msg
        
        with open(TRACE_FILE, "a") as f:
            f.write(json.dumps(record) + "\n")
    except Exception as e:
        logger.error(f"Failed to write trace: {e}")

if __name__ == "__main__":
    uvicorn.run("vllm_proxy:app", host="0.0.0.0", port=8100)