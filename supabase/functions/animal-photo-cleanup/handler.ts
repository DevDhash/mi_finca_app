import { authenticate } from "./auth.ts";
import { readConfig } from "./config.ts";
import type { Environment } from "./config.ts";
import { runWorker } from "./worker.ts";
import type { WorkerDependencies } from "./worker.ts";

function response(
  body: unknown,
  status: number,
  extra: Record<string, string> = {},
) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      ...extra,
    },
  });
}
/** Inspect chunks without accumulating payload. Bound both time and empty chunks. */
async function hasEmptyBody(
  request: Request,
  timeoutMs: number,
): Promise<boolean> {
  if (request.body === null) return true;
  let reader: ReadableStreamDefaultReader<Uint8Array>;
  try {
    reader = request.body.getReader();
  } catch {
    return false;
  }
  let ended = false;
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<null>((resolve) => {
    timer = setTimeout(() => resolve(null), timeoutMs);
  });
  try {
    // Empty chunks convey no bytes, but an unbounded sequence could exhaust CPU.
    for (let reads = 0; reads < 16; reads++) {
      const chunk = await Promise.race([reader.read(), timeout]);
      if (chunk === null) return false;
      if (chunk.done) {
        ended = true;
        return true;
      }
      if (chunk.value.byteLength > 0) return false;
    }
    return false;
  } catch {
    return false;
  } finally {
    clearTimeout(timer);
    // Do not wait for an untrusted source's cancellation promise.
    if (!ended) void reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}
export function createHandler(env: Environment, deps: WorkerDependencies) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") {
      return response({ error: "method_not_allowed" }, 405, { Allow: "POST" });
    }
    const config = readConfig(env);
    if (!config) return response({ error: "configuration_unavailable" }, 503);
    try {
      if (!await authenticate(request, config.secret)) {
        return response({ error: "unauthorized" }, 401);
      }
      // Transport headers and stream existence do not prove payload presence.
      if (
        new URL(request.url).search ||
        !await hasEmptyBody(request, config.requestMs)
      ) return response({ error: "unexpected_input" }, 400);
      const summary = await runWorker(config, deps);
      return response(
        summary,
        summary.fatal || summary.stopped === "error" ||
          summary.interventionRequired
          ? 503
          : 200,
      );
    } catch {
      return response({ error: "internal_error" }, 500);
    }
  };
}
