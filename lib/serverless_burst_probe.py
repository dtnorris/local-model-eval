#!/usr/bin/env python3
"""Bounded RunPod Serverless scale-zero-to-eight latency probe."""

from __future__ import annotations

import concurrent.futures
import dataclasses
import datetime as dt
import json
import os
import pathlib
import threading
import time
import urllib.error
import urllib.request
import uuid
from typing import Any, Iterable


REST_API_BASE = "https://rest.runpod.io/v1"
JOB_API_BASE = "https://api.runpod.ai/v2"
WORKER_COUNT = 8
MODEL_NAME = "openai/gpt-oss-20b"
IMAGE_NAME = "runpod/worker-v1-vllm:v2.26.0"
GPU_TYPE = "NVIDIA GeForce RTX 4090"
GPU_PRICE_PER_SECOND_USD = 0.00031
DEFAULT_DEADLINE_SECONDS = 90
TERMINAL_STATUSES = {"COMPLETED", "FAILED", "TIMED_OUT", "CANCELLED"}


class ApiError(RuntimeError):
    def __init__(self, method: str, url: str, status: int, detail: str):
        super().__init__(f"{method} {url} -> HTTP {status}: {detail}")
        self.status = status


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds")


def load_api_key(repo_root: pathlib.Path) -> str:
    """Load RUNPOD_API_KEY without evaluating the repo-local .env as shell."""
    if os.environ.get("RUNPOD_API_KEY"):
        return os.environ["RUNPOD_API_KEY"]
    env_path = repo_root / ".env"
    if not env_path.exists():
        return ""
    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key.strip() != "RUNPOD_API_KEY":
            continue
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        return value
    return ""


def api_request(
    method: str,
    url: str,
    api_key: str,
    body: dict[str, Any] | None = None,
    timeout: float = 20,
) -> Any:
    data = json.dumps(body).encode("utf-8") if body is not None else None
    request = urllib.request.Request(url, data=data, method=method)
    request.add_header("Authorization", f"Bearer {api_key}")
    request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise ApiError(method, url, error.code, detail) from error


def extract_text(value: Any) -> str | None:
    """Find generated text in RunPod/vLLM stream payload variants."""
    if isinstance(value, str):
        # The official worker yields raw OpenAI SSE chunks, which RunPod can
        # wrap as strings inside its own JSON stream envelope. Do not mistake
        # a role-only SSE event for a generated token.
        if "data:" in value:
            for line in value.splitlines():
                line = line.strip()
                if not line.startswith("data:"):
                    continue
                nested = line[5:].strip()
                if nested == "[DONE]":
                    continue
                try:
                    found = extract_text(json.loads(nested))
                except json.JSONDecodeError:
                    found = None
                if found:
                    return found
            return None
        return value if value.strip() else None
    if isinstance(value, list):
        for item in value:
            found = extract_text(item)
            if found:
                return found
        return None
    if not isinstance(value, dict):
        return None

    for key in ("content", "text", "token", "reasoning", "reasoning_content"):
        found = extract_text(value.get(key))
        if found:
            return found
    for key in ("delta", "message", "choices", "output", "tokens"):
        found = extract_text(value.get(key))
        if found:
            return found
    return None


def iter_stream_json(lines: Iterable[bytes]) -> Iterable[Any]:
    for raw in lines:
        text = raw.decode("utf-8", errors="replace").strip()
        if not text or text.startswith(":"):
            continue
        if text.startswith("data:"):
            text = text[5:].strip()
        if text == "[DONE]":
            return
        try:
            payload = json.loads(text)
        except json.JSONDecodeError:
            continue
        if isinstance(payload, list):
            yield from payload
        else:
            yield payload


@dataclasses.dataclass
class JobObservation:
    slot: int
    job_id: str
    submit_started_ns: int
    submitted_ns: int
    first_token_ns: int | None = None
    first_text: str | None = None
    terminal_ns: int | None = None
    terminal_status: str | None = None
    worker_id: str | None = None
    error: str | None = None


class ArtifactLog:
    def __init__(self, run_root: pathlib.Path):
        self.run_root = run_root
        self.run_root.mkdir(parents=True, exist_ok=False)
        self._lock = threading.Lock()

    def jsonl(self, filename: str, event: dict[str, Any]) -> None:
        row = {"recorded_at_utc": utc_now(), **event}
        with self._lock:
            with (self.run_root / filename).open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(row, sort_keys=True) + "\n")

    def json(self, filename: str, value: Any) -> None:
        with self._lock:
            (self.run_root / filename).write_text(
                json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8"
            )


class ServerlessBurstProbe:
    def __init__(
        self,
        api_key: str,
        artifacts: ArtifactLog,
        deadline_seconds: int = DEFAULT_DEADLINE_SECONDS,
    ):
        self.api_key = api_key
        self.artifacts = artifacts
        self.deadline_seconds = deadline_seconds
        self.template_id: str | None = None
        self.endpoint_id: str | None = None
        self.submit_origin_ns: int | None = None
        self._stop = threading.Event()
        self.driver_origin_ns = time.monotonic_ns()

    def log(self, message: str) -> None:
        elapsed_seconds = (time.monotonic_ns() - self.driver_origin_ns) / 1e9
        print(f"[serverless-burst-probe +{elapsed_seconds:06.1f}s] {message}", flush=True)

    def create_resources(self, name_suffix: str) -> None:
        template_name = f"lme-burst-probe-{name_suffix}"
        started = time.monotonic()
        self.log(f"Creating disposable template {template_name}")
        template = api_request(
            "POST",
            f"{REST_API_BASE}/templates",
            self.api_key,
            {
                "name": template_name,
                "imageName": IMAGE_NAME,
                "isServerless": True,
                "containerDiskInGb": 50,
                "env": {
                    "MODEL_NAME": MODEL_NAME,
                    "MAX_MODEL_LEN": "32768",
                    "GPU_MEMORY_UTILIZATION": "0.95",
                    "MAX_CONCURRENCY": "1",
                    "TRUST_REMOTE_CODE": "true",
                    "ENFORCE_EAGER": "false",
                    "ENABLE_PREFIX_CACHING": "true",
                    "ENABLE_CHUNKED_PREFILL": "true",
                    "RAW_OPENAI_OUTPUT": "1",
                },
            },
        )
        self.template_id = template["id"]
        self._write_resource_ids()
        self.log(f"Template created in {time.monotonic() - started:.1f}s (id={self.template_id})")

        endpoint_name = f"lme-scale-zero-eight-{name_suffix}"
        started = time.monotonic()
        self.log(f"Creating scale-zero endpoint {endpoint_name}")
        endpoint = api_request(
            "POST",
            f"{REST_API_BASE}/endpoints",
            self.api_key,
            {
                "name": endpoint_name,
                "templateId": self.template_id,
                "gpuTypeIds": [GPU_TYPE],
                "gpuCount": 1,
                "workersMin": 0,
                "workersMax": WORKER_COUNT,
                "idleTimeout": 5,
                "scalerType": "REQUEST_COUNT",
                "scalerValue": 1,
                "flashboot": True,
                "allowedCudaVersions": ["13.0"],
                "executionTimeoutMs": self.deadline_seconds * 1000,
            },
        )
        self.endpoint_id = endpoint["id"]
        self._write_resource_ids()
        self.log(f"Endpoint created in {time.monotonic() - started:.1f}s (id={self.endpoint_id})")
        self.artifacts.json("created-template.json", template)
        self.artifacts.json("created-endpoint.json", endpoint)

    def _write_resource_ids(self) -> None:
        self.artifacts.json(
            "resource-ids.json",
            {
                "template_id": self.template_id,
                "endpoint_id": self.endpoint_id,
                "manual_cleanup": {
                    "endpoint": (
                        f"curl -X DELETE -H 'Authorization: Bearer $RUNPOD_API_KEY' "
                        f"{REST_API_BASE}/endpoints/{self.endpoint_id}"
                        if self.endpoint_id
                        else None
                    ),
                    "template": (
                        f"curl -X DELETE -H 'Authorization: Bearer $RUNPOD_API_KEY' "
                        f"{REST_API_BASE}/templates/{self.template_id}"
                        if self.template_id
                        else None
                    ),
                },
            },
        )

    def wait_for_scale_zero(self, timeout_seconds: int = 15) -> dict[str, Any]:
        assert self.endpoint_id
        started = time.monotonic()
        self.log("Waiting for endpoint health to confirm scale zero")
        deadline = started + timeout_seconds
        latest: dict[str, Any] = {}
        while time.monotonic() < deadline:
            latest = api_request(
                "GET", f"{JOB_API_BASE}/{self.endpoint_id}/health", self.api_key
            )
            workers = latest.get("workers") or {}
            count = int(workers.get("idle", 0)) + int(workers.get("running", 0))
            if count == 0:
                self.artifacts.json("scale-zero-health.json", latest)
                self.log(f"Scale zero confirmed in {time.monotonic() - started:.1f}s")
                return latest
            time.sleep(0.5)
        raise RuntimeError(f"Endpoint did not reach scale zero: {latest}")

    def _submit_one(self, slot: int, barrier: threading.Barrier) -> JobObservation:
        assert self.endpoint_id
        barrier.wait()
        started = time.monotonic_ns()
        response = api_request(
            "POST",
            f"{JOB_API_BASE}/{self.endpoint_id}/run",
            self.api_key,
            {
                "input": {
                    "messages": [
                        {"role": "user", "content": "Reply with exactly: OK"}
                    ],
                    "sampling_params": {
                        "temperature": 0,
                        "max_tokens": 8,
                    },
                    "stream": True,
                },
                "policy": {
                    "executionTimeout": self.deadline_seconds * 1000,
                    "ttl": (self.deadline_seconds + 30) * 1000,
                },
            },
        )
        submitted = time.monotonic_ns()
        observation = JobObservation(slot, response["id"], started, submitted)
        self.artifacts.jsonl(
            "timeline.jsonl",
            {
                "event": "job_submitted",
                "slot": slot,
                "job_id": observation.job_id,
                "elapsed_ms": self._elapsed_ms(submitted),
            },
        )
        return observation

    def submit_burst(self) -> list[JobObservation]:
        self.submit_origin_ns = time.monotonic_ns()
        self.artifacts.jsonl(
            "timeline.jsonl", {"event": "burst_submission_started", "elapsed_ms": 0.0}
        )
        self.log(f"Submitting {WORKER_COUNT} requests concurrently")
        barrier = threading.Barrier(WORKER_COUNT)
        executor = concurrent.futures.ThreadPoolExecutor(max_workers=WORKER_COUNT)
        try:
            futures = [executor.submit(self._submit_one, slot, barrier) for slot in range(1, 9)]
            observations = [future.result(timeout=30) for future in futures]
        finally:
            executor.shutdown(wait=False, cancel_futures=True)
        observations.sort(key=lambda row: row.slot)
        latest = max(row.submitted_ns for row in observations)
        self.artifacts.jsonl(
            "timeline.jsonl",
            {"event": "all_jobs_submitted", "elapsed_ms": self._elapsed_ms(latest)},
        )
        self.log(
            f"All {WORKER_COUNT} requests accepted by burst "
            f"+{self._elapsed_seconds(latest):.3f}s"
        )
        return observations

    def _observe_stream(self, observation: JobObservation, deadline_ns: int) -> None:
        assert self.endpoint_id
        url = f"{JOB_API_BASE}/{self.endpoint_id}/stream/{observation.job_id}"
        while not self._stop.is_set() and time.monotonic_ns() < deadline_ns:
            request = urllib.request.Request(url, method="GET")
            request.add_header("Authorization", f"Bearer {self.api_key}")
            try:
                remaining = max(1.0, (deadline_ns - time.monotonic_ns()) / 1e9)
                with urllib.request.urlopen(request, timeout=min(10.0, remaining)) as response:
                    for payload in iter_stream_json(response):
                        self.artifacts.jsonl(
                            "stream.jsonl",
                            {"slot": observation.slot, "job_id": observation.job_id, "payload": payload},
                        )
                        text = extract_text(payload)
                        if text and observation.first_token_ns is None:
                            observation.first_token_ns = time.monotonic_ns()
                            observation.first_text = text[:80]
                            self.log(
                                f"slot {observation.slot} first token at burst "
                                f"+{self._elapsed_seconds(observation.first_token_ns):.3f}s"
                            )
                            self.artifacts.jsonl(
                                "timeline.jsonl",
                                {
                                    "event": "first_token",
                                    "slot": observation.slot,
                                    "job_id": observation.job_id,
                                    "elapsed_ms": self._elapsed_ms(observation.first_token_ns),
                                },
                            )
                    if observation.first_token_ns is not None:
                        return
            except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError):
                time.sleep(0.2)

    def measure(self, observations: list[JobObservation]) -> tuple[int | None, int | None]:
        assert self.endpoint_id and self.submit_origin_ns
        deadline_ns = self.submit_origin_ns + int(self.deadline_seconds * 1e9)
        stream_executor = concurrent.futures.ThreadPoolExecutor(max_workers=WORKER_COUNT)
        stream_futures = [
            stream_executor.submit(self._observe_stream, observation, deadline_ns)
            for observation in observations
        ]
        all_workers_ns: int | None = None
        all_first_tokens_ns: int | None = None
        last_status_poll = 0.0
        last_progress_log = 0.0
        last_health_signature: tuple[int, ...] | None = None
        self.log(f"Monitoring burst for up to {self.deadline_seconds}s")
        try:
            while time.monotonic_ns() < deadline_ns:
                now = time.monotonic()
                health = api_request(
                    "GET", f"{JOB_API_BASE}/{self.endpoint_id}/health", self.api_key, timeout=10
                )
                workers = health.get("workers") or {}
                worker_count = int(workers.get("idle", 0)) + int(workers.get("running", 0))
                sampled_ns = time.monotonic_ns()
                self.artifacts.jsonl(
                    "health.jsonl",
                    {
                        "elapsed_ms": self._elapsed_ms(sampled_ns),
                        "worker_count": worker_count,
                        "health": health,
                    },
                )
                jobs = health.get("jobs") or {}
                health_signature = (
                    int(jobs.get("inQueue", 0)),
                    int(jobs.get("inProgress", 0)),
                    int(jobs.get("completed", 0)),
                    int(jobs.get("failed", 0)),
                    int(workers.get("idle", 0)),
                    int(workers.get("initializing", 0)),
                    int(workers.get("ready", 0)),
                    int(workers.get("running", 0)),
                    int(workers.get("throttled", 0)),
                    int(workers.get("unhealthy", 0)),
                )
                progress_now = time.monotonic()
                if (
                    health_signature != last_health_signature
                    or progress_now - last_progress_log >= 5.0
                ):
                    self.log(
                        f"burst +{self._elapsed_seconds(sampled_ns):.1f}s | "
                        f"jobs queue={health_signature[0]} progress={health_signature[1]} "
                        f"completed={health_signature[2]} failed={health_signature[3]} | "
                        f"workers idle={health_signature[4]} initializing={health_signature[5]} "
                        f"ready={health_signature[6]} running={health_signature[7]} "
                        f"throttled={health_signature[8]} unhealthy={health_signature[9]}"
                    )
                    last_health_signature = health_signature
                    last_progress_log = progress_now

                if worker_count >= WORKER_COUNT and all_workers_ns is None:
                    all_workers_ns = sampled_ns
                    self.artifacts.jsonl(
                        "timeline.jsonl",
                        {"event": "eight_workers_ready", "elapsed_ms": self._elapsed_ms(sampled_ns)},
                    )

                token_times = [row.first_token_ns for row in observations]
                if all(token_times) and all_first_tokens_ns is None:
                    all_first_tokens_ns = max(value for value in token_times if value is not None)
                    self.artifacts.jsonl(
                        "timeline.jsonl",
                        {
                            "event": "eight_first_tokens",
                            "elapsed_ms": self._elapsed_ms(all_first_tokens_ns),
                        },
                    )

                if now - last_status_poll >= 0.5:
                    for observation in observations:
                        if observation.terminal_status:
                            continue
                        status = api_request(
                            "GET",
                            f"{JOB_API_BASE}/{self.endpoint_id}/status/{observation.job_id}",
                            self.api_key,
                            timeout=10,
                        )
                        state = status.get("status")
                        if state in TERMINAL_STATUSES:
                            observation.terminal_status = state
                            observation.terminal_ns = time.monotonic_ns()
                            observation.worker_id = status.get("workerId") or status.get("worker_id")
                            self.log(
                                f"slot {observation.slot} terminal={state} at burst "
                                f"+{self._elapsed_seconds(observation.terminal_ns):.3f}s"
                            )
                            if state != "COMPLETED":
                                observation.error = json.dumps(status, sort_keys=True)[:1000]
                    last_status_poll = now

                if (
                    all_workers_ns is not None
                    and all_first_tokens_ns is not None
                    and all(row.terminal_status in TERMINAL_STATUSES for row in observations)
                ):
                    break
                time.sleep(0.25)
            if time.monotonic_ns() >= deadline_ns:
                self.log(f"Burst deadline reached at +{self.deadline_seconds}s")
        finally:
            self._stop.set()
            for future in stream_futures:
                future.cancel()
            stream_executor.shutdown(wait=False, cancel_futures=True)
        return all_workers_ns, all_first_tokens_ns

    def cancel_jobs(self, observations: list[JobObservation]) -> None:
        if not self.endpoint_id:
            return
        for observation in observations:
            if observation.terminal_status in TERMINAL_STATUSES:
                continue
            try:
                api_request(
                    "POST",
                    f"{JOB_API_BASE}/{self.endpoint_id}/cancel/{observation.job_id}",
                    self.api_key,
                    timeout=10,
                )
            except Exception as error:  # cleanup must continue
                self.artifacts.jsonl(
                    "cleanup-errors.jsonl",
                    {"resource": f"job:{observation.job_id}", "error": str(error)},
                )

    def cleanup(self) -> dict[str, Any]:
        result: dict[str, Any] = {"started_at_utc": utc_now()}
        if self.endpoint_id:
            result["endpoint"] = self._delete_and_confirm(
                "endpoint", f"{REST_API_BASE}/endpoints/{self.endpoint_id}"
            )
        if self.template_id:
            result["template"] = self._delete_and_confirm(
                "template", f"{REST_API_BASE}/templates/{self.template_id}"
            )
        result["finished_at_utc"] = utc_now()
        result["all_deleted"] = all(
            value.get("deleted", False)
            for key, value in result.items()
            if key in {"endpoint", "template"}
        )
        self.artifacts.json("cleanup.json", result)
        return result

    def _delete_and_confirm(self, kind: str, url: str) -> dict[str, Any]:
        self.log(f"Deleting disposable {kind}")
        try:
            api_request("DELETE", url, self.api_key, timeout=20)
        except ApiError as error:
            if error.status != 404:
                return {"deleted": False, "error": str(error)}
        for _ in range(10):
            try:
                api_request("GET", url, self.api_key, timeout=10)
            except ApiError as error:
                if error.status == 404:
                    return {"deleted": True, "confirmed_at_utc": utc_now()}
                return {"deleted": False, "error": str(error)}
            time.sleep(0.5)
        return {"deleted": False, "error": "resource still present after DELETE"}

    def summary(
        self,
        observations: list[JobObservation],
        all_workers_ns: int | None,
        all_first_tokens_ns: int | None,
        cleanup: dict[str, Any],
    ) -> dict[str, Any]:
        assert self.submit_origin_ns
        finished_ns = time.monotonic_ns()
        completed = sum(row.terminal_status == "COMPLETED" for row in observations)
        first_tokens = sum(row.first_token_ns is not None for row in observations)
        ready_seconds = self._elapsed_seconds(all_workers_ns)
        token_seconds = self._elapsed_seconds(all_first_tokens_ns)
        ready_to_tokens_seconds = None
        if all_workers_ns is not None and all_first_tokens_ns is not None:
            ready_to_tokens_seconds = round((all_first_tokens_ns - all_workers_ns) / 1e9, 3)
        gate = "FAIL"
        if ready_seconds is not None and ready_seconds <= 60 and first_tokens == 8 and completed == 8:
            gate = "STRONG PASS" if ready_seconds <= 30 else "PASS"
        elapsed_seconds = (finished_ns - self.submit_origin_ns) / 1e9
        summary = {
            "result": gate,
            "model": MODEL_NAME,
            "runtime_image": IMAGE_NAME,
            "behavioral_equivalence_note": (
                "Infrastructure-only proxy; this Hugging Face model is not asserted to be "
                "bit-identical to the project's Ollama digest."
            ),
            "gpu_type": GPU_TYPE,
            "requested_workers": WORKER_COUNT,
            "deadline_seconds": self.deadline_seconds,
            "measurement_origin": "immediately before the eight concurrent POST /run calls",
            "request_submitted_to_eight_workers_ready_seconds": ready_seconds,
            "request_submitted_to_eight_first_tokens_seconds": token_seconds,
            "eight_workers_ready_to_eight_first_tokens_seconds": ready_to_tokens_seconds,
            "jobs_with_first_token": first_tokens,
            "jobs_completed": completed,
            "distinct_reported_worker_ids": sorted(
                {row.worker_id for row in observations if row.worker_id}
            ),
            "jobs": [
                {
                    "slot": row.slot,
                    "job_id": row.job_id,
                    "submit_started_elapsed_seconds": self._elapsed_seconds(row.submit_started_ns),
                    "submitted_elapsed_seconds": self._elapsed_seconds(row.submitted_ns),
                    "first_token_elapsed_seconds": self._elapsed_seconds(row.first_token_ns),
                    "first_text": row.first_text,
                    "terminal_elapsed_seconds": self._elapsed_seconds(row.terminal_ns),
                    "terminal_status": row.terminal_status,
                    "worker_id": row.worker_id,
                    "error": row.error,
                }
                for row in observations
            ],
            "cache_observation": (
                "The official image and MODEL_NAME enable RunPod's managed model-cache path; "
                "this probe does not independently expose network-transfer telemetry. A cache miss "
                "is expected to surface as startup latency or the 90-second failure gate."
            ),
            "catalog_rate_usd_per_gpu_second": GPU_PRICE_PER_SECOND_USD,
            "conservative_compute_upper_bound_usd": round(
                elapsed_seconds * WORKER_COUNT * GPU_PRICE_PER_SECOND_USD,
                4,
            ),
            "cost_note": (
                "Catalog-rate upper bound assuming all eight GPUs were billed for the full "
                "submission-to-cleanup interval; not provider billing telemetry."
            ),
            "cleanup": cleanup,
        }
        self.artifacts.json("summary.json", summary)
        return summary

    def _elapsed_ms(self, value_ns: int) -> float:
        assert self.submit_origin_ns
        return round((value_ns - self.submit_origin_ns) / 1e6, 3)

    def _elapsed_seconds(self, value_ns: int | None) -> float | None:
        if value_ns is None:
            return None
        return round(self._elapsed_ms(value_ns) / 1000, 3)


def frozen_plan(deadline_seconds: int = DEFAULT_DEADLINE_SECONDS) -> dict[str, Any]:
    return {
        "provider": "RunPod Serverless",
        "model": MODEL_NAME,
        "runtime_image": IMAGE_NAME,
        "gpu_type": GPU_TYPE,
        "workers_min": 0,
        "workers_max": WORKER_COUNT,
        "scaler": {"type": "REQUEST_COUNT", "value": 1},
        "prompt": "Reply with exactly: OK",
        "max_tokens": 8,
        "deadline_seconds": deadline_seconds,
        "pass_gate_seconds": 60,
        "strong_pass_gate_seconds": 30,
        "catalog_rate_usd_per_gpu_second": GPU_PRICE_PER_SECOND_USD,
        "full_fleet_90_second_estimate_usd": round(
            deadline_seconds * WORKER_COUNT * GPU_PRICE_PER_SECOND_USD, 4
        ),
        "teardown": ["delete endpoint (terminates its jobs/workers)", "delete template"],
    }
