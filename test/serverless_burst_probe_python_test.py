import json
import os
import pathlib
import tempfile
import unittest
from unittest import mock

import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "lib"))

from serverless_burst_probe import (  # noqa: E402
    ArtifactLog,
    DEFAULT_DEADLINE_SECONDS,
    DEFAULT_WORKER_COUNT,
    IMAGE_NAME,
    MAX_WORKER_COUNT,
    MODEL_NAME,
    ServerlessBurstProbe,
    extract_text,
    frozen_plan,
    iter_stream_json,
    load_api_key,
)


class ServerlessBurstProbeTest(unittest.TestCase):
    def test_default_worker_count_remains_eight(self):
        self.assertEqual(8, DEFAULT_WORKER_COUNT)
        self.assertEqual(8, MAX_WORKER_COUNT)

    def test_frozen_plan_defaults_to_scale_zero_to_eight_and_is_bounded(self):
        plan = frozen_plan()
        self.assertEqual(8, plan["requested_workers"])
        self.assertEqual(0, plan["workers_min"])
        self.assertEqual(8, plan["workers_max"])
        self.assertEqual({"type": "REQUEST_COUNT", "value": 1}, plan["scaler"])
        self.assertEqual(DEFAULT_DEADLINE_SECONDS, plan["deadline_seconds"])
        expected = DEFAULT_DEADLINE_SECONDS * DEFAULT_WORKER_COUNT * 0.00031
        self.assertAlmostEqual(expected, plan["full_fleet_90_second_estimate_usd"])

    def test_frozen_plan_scales_cost_to_one_worker(self):
        plan = frozen_plan(worker_count=1)
        self.assertEqual(1, plan["requested_workers"])
        self.assertEqual(0, plan["workers_min"])
        self.assertEqual(1, plan["workers_max"])
        expected = DEFAULT_DEADLINE_SECONDS * 1 * 0.00031
        self.assertAlmostEqual(expected, plan["full_fleet_90_second_estimate_usd"])

    def test_extracts_first_text_from_openai_and_runpod_shapes(self):
        self.assertEqual("OK", extract_text({"choices": [{"delta": {"content": "OK"}}]}))
        self.assertEqual("OK", extract_text({"output": [{"text": ["OK"]}]}))
        role_only = {"output": 'data: {"choices":[{"delta":{"role":"assistant"}}]}\n\n'}
        generated = {"output": 'data: {"choices":[{"delta":{"content":"OK"}}]}\n\n'}
        reasoning = {"output": 'data: {"choices":[{"delta":{"reasoning_content":"O"}}]}\n\n'}
        self.assertIsNone(extract_text(role_only))
        self.assertEqual("OK", extract_text(generated))
        self.assertEqual("O", extract_text(reasoning))
        self.assertIsNone(extract_text({"status": "IN_QUEUE"}))

    def test_parses_sse_ndjson_and_arrays(self):
        lines = [
            b': keepalive\n',
            b'data: {"choices":[{"delta":{"content":"O"}}]}\n',
            b'[{"text":"K"}]\n',
            b'data: [DONE]\n',
        ]
        values = list(iter_stream_json(lines))
        self.assertEqual(2, len(values))
        self.assertEqual("O", extract_text(values[0]))
        self.assertEqual("K", extract_text(values[1]))

    def test_environment_wins_and_dotenv_is_not_evaluated(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / ".env").write_text(
                "IGNORED=$(touch should-not-exist)\nRUNPOD_API_KEY='from-file'\n",
                encoding="utf-8",
            )
            with mock.patch.dict(os.environ, {}, clear=True):
                self.assertEqual("from-file", load_api_key(root))
            self.assertFalse((root / "should-not-exist").exists())
            with mock.patch.dict(os.environ, {"RUNPOD_API_KEY": "from-env"}, clear=True):
                self.assertEqual("from-env", load_api_key(root))

    def test_resource_configuration_defaults_to_scale_zero_to_eight(self):
        with tempfile.TemporaryDirectory() as directory:
            artifacts = ArtifactLog(pathlib.Path(directory) / "run")
            probe = ServerlessBurstProbe("secret", artifacts)
            responses = [{"id": "template-1"}, {"id": "endpoint-1"}]
            with mock.patch("serverless_burst_probe.api_request", side_effect=responses) as request:
                probe.create_resources("unit")

            template_body = request.call_args_list[0].args[3]
            endpoint_body = request.call_args_list[1].args[3]
            self.assertEqual(IMAGE_NAME, template_body["imageName"])
            self.assertEqual(MODEL_NAME, template_body["env"]["MODEL_NAME"])
            self.assertEqual(0, endpoint_body["workersMin"])
            self.assertEqual(8, endpoint_body["workersMax"])
            self.assertEqual("REQUEST_COUNT", endpoint_body["scalerType"])
            self.assertEqual(1, endpoint_body["scalerValue"])
            self.assertEqual(5, endpoint_body["idleTimeout"])

    def test_resource_configuration_can_use_one_worker(self):
        with tempfile.TemporaryDirectory() as directory:
            artifacts = ArtifactLog(pathlib.Path(directory) / "run")
            probe = ServerlessBurstProbe("secret", artifacts, worker_count=1)
            responses = [{"id": "template-1"}, {"id": "endpoint-1"}]
            with mock.patch("serverless_burst_probe.api_request", side_effect=responses) as request:
                probe.create_resources("unit")

            endpoint_body = request.call_args_list[1].args[3]
            self.assertEqual(0, endpoint_body["workersMin"])
            self.assertEqual(1, endpoint_body["workersMax"])


if __name__ == "__main__":
    unittest.main()
