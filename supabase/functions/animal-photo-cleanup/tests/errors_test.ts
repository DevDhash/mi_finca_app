import { equal } from "node:assert/strict";
import { test } from "node:test";
import { classifyError } from "../errors.ts";
import type { ErrorCode, NormalizedError } from "../types.ts";

const cases: [NormalizedError, ErrorCode][] = [
  [{ kind: "http", status: 429 }, "rate_limited"],
  [{ kind: "http", status: 503, code: "SlowDown" }, "rate_limited"],
  [{ kind: "timeout" }, "timeout"],
  [{ kind: "http", status: 401 }, "permission_denied"],
  [{ kind: "http", status: 403 }, "permission_denied"],
  [{ kind: "http", status: 503, code: "InternalError" }, "internal_error"],
  [{ kind: "network" }, "storage_unavailable"],
  [{ kind: "unknown" }, "internal_error"],
  [{ kind: "http", status: 500 }, "internal_error"],
  [{ kind: "http", status: 502 }, "storage_unavailable"],
  [{ kind: "http", status: 503 }, "storage_unavailable"],
  [{ kind: "http", status: 504 }, "timeout"],
  [{ kind: "http", status: 408 }, "timeout"],
  [{ kind: "http", status: 403, code: "DatabaseTimeout" }, "timeout"],
  [{ kind: "http", status: 500, code: "AccessDenied" }, "permission_denied"],
  [{ kind: "http", status: 404, code: "NoSuchKey" }, "internal_error"],
  [{ kind: "http", status: 404, code: "NoSuchBucket" }, "internal_error"],
  [{ kind: "unknown", code: "arbitrary-secret-message" }, "internal_error"],
];
for (const [error, expected] of cases) {
  test(`classifier ${JSON.stringify(error)} => ${expected}`, () => {
    equal(classifyError(error), expected);
  });
}
