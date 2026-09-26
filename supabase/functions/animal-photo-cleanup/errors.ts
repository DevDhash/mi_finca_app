import type { ErrorCode, NormalizedError } from "./types.ts";

/** No exception messages, headers, URLs or SDK objects enter the result. */
export function classifyError(error: NormalizedError): ErrorCode {
  switch (error.code) {
    case "SlowDown":
    case "TooManyRequests":
      return "rate_limited";
    case "DatabaseTimeout":
    case "RequestTimeout":
      return "timeout";
    case "AccessDenied":
    case "InvalidJWT":
    case "InvalidSignature":
    case "SignatureDoesNotMatch":
      return "permission_denied";
    case "InternalError":
      return "internal_error";
    case "ServiceUnavailable":
      return "storage_unavailable";
  }
  if (error.kind === "timeout") return "timeout";
  if (error.kind === "network") return "storage_unavailable";
  if (error.status === 429) return "rate_limited";
  if (error.status === 401 || error.status === 403) return "permission_denied";
  if (error.status === 408 || error.status === 504) return "timeout";
  if (error.status === 502 || error.status === 503) {
    return "storage_unavailable";
  }
  return "internal_error";
}
