import { authenticate } from "./auth.ts";
import { readConfig } from "./config.ts";
import type { Environment } from "./config.ts";
import { runWorker } from "./worker.ts";
import type { WorkerDependencies } from "./worker.ts";

function response(body: unknown, status: number, extra: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), {
    status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ...extra },
  });
}
export function createHandler(env: Environment, deps: WorkerDependencies) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") return response({ error: "method_not_allowed" }, 405, { Allow: "POST" });
    const config = readConfig(env);
    if (!config) return response({ error: "configuration_unavailable" }, 503);
    try {
      if (!await authenticate(request, config.secret)) return response({ error: "unauthorized" }, 401);
      // No request body, query options or caller-selected identities. Do not read streams.
      if (new URL(request.url).search || request.body !== null ||
        (request.headers.has("content-length") && request.headers.get("content-length") !== "0") ||
        request.headers.has("transfer-encoding")) return response({ error: "unexpected_input" }, 400);
      const summary = await runWorker(config, deps);
      return response(summary, summary.fatal || summary.stopped === "error" || summary.interventionRequired ? 503 : 200);
    } catch { return response({ error: "internal_error" }, 500); }
  };
}
