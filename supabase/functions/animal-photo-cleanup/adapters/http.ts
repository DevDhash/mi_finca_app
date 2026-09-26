import type { AdapterResult, NormalizedError } from "../types.ts";
import { withDeadline } from "./timeout.ts";

export type Fetch = (url: string, init: RequestInit) => Promise<Response>;
export const malformed = () => ({
  ok: false as const,
  error: { kind: "unknown" as const },
});
export const record = (v: unknown): v is Record<string, unknown> =>
  typeof v === "object" && v !== null && !Array.isArray(v);

/** Preserve integer tokens BEFORE JSON.parse, including values above 2^53.
 * Strings are consumed as complete tokens, so embedded numbers/escapes are untouched.
 * Validate original syntax first without using any numeric result.
 */
export function parseExactJson(text: string): unknown {
  // JSON.parse rejects unescaped U+0000..U+001F inside strings before tokenization.
  // Its numeric result is discarded; integer tokens below retain their exact text.
  JSON.parse(text);
  return JSON.parse(text.replace(
    /"(?:[^"\\]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4}))*"|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/g,
    (token) =>
      token.startsWith('"') || /[.eE]/.test(token) ? token : `"${token}"`,
  ));
}
const codes = new Set([
  "SlowDown",
  "TooManyRequests",
  "DatabaseTimeout",
  "RequestTimeout",
  "AccessDenied",
  "InvalidJWT",
  "InvalidSignature",
  "SignatureDoesNotMatch",
  "InternalError",
  "ServiceUnavailable",
]);

/** One instance per invocation; a global auth/config fault latches, blocking more I/O. */
export class HttpTransport {
  #fatal = false;
  readonly #origin: string;
  readonly #headers: Readonly<Record<string, string>>;
  readonly #fetch: Fetch;
  readonly #now: () => number;
  constructor(
    origin: string,
    headers: Record<string, string>,
    fetch: Fetch,
    now = Date.now,
  ) {
    const url = new URL(origin);
    if (
      url.protocol !== "https:" || url.username || url.password || url.search ||
      url.hash || url.pathname !== "/"
    ) {
      throw new Error("INVALID_SERVER_ORIGIN");
    }
    this.#origin = url.origin;
    this.#headers = Object.freeze({ ...headers });
    this.#fetch = fetch;
    this.#now = now;
  }
  get fatalWorkerError(): boolean {
    return this.#fatal;
  }
  async request(
    path: string,
    method: "GET" | "POST" | "DELETE",
    body: unknown,
    deadline: number,
  ): Promise<AdapterResult<unknown>> {
    if (this.#fatal) return { ok: false, error: { kind: "http", status: 403 } };
    if (!path.startsWith("/rest/v1/") && !path.startsWith("/storage/v1/")) {
      return malformed();
    }
    const reply = await withDeadline(
      async (signal) => {
        const response = await this.#fetch(this.#origin + path, {
          method,
          headers: { ...this.#headers, "Content-Type": "application/json" },
          body: body === undefined ? undefined : JSON.stringify(body),
          signal,
          redirect: "error",
        });
        // Record auth failure before reading a possibly broken/hanging response body.
        if (response.status === 401 || response.status === 403) {
          this.#fatal = true;
        }
        return {
          status: response.status,
          ok: response.ok,
          text: await response.text(),
        };
      },
      deadline,
      this.#now,
    );
    if (!reply.ok) return reply;
    let value: unknown;
    try {
      value = parseExactJson(reply.value.text);
    } catch {
      if (reply.value.ok) return malformed();
    }
    if (!reply.value.ok) {
      const rawCode = record(value) ? value.code ?? value.error : undefined;
      const code = typeof rawCode === "string" && codes.has(rawCode)
        ? rawCode
        : undefined;
      if (
        [
          "AccessDenied",
          "InvalidJWT",
          "InvalidSignature",
          "SignatureDoesNotMatch",
        ].includes(code ?? "")
      ) this.#fatal = true;
      const error: NormalizedError = {
        kind: "http",
        status: reply.value.status,
        ...(code ? { code } : {}),
      };
      return { ok: false, error };
    }
    return { ok: true, value };
  }
}
