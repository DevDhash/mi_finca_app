import { validSecret } from "./config.ts";

/** Native HMAC verification avoids comparing secret strings with an early-exit loop.
 * No network validation, logging, JWT acceptance or publishable-key fallback.
 */
export async function authenticate(
  request: Request,
  expected: string,
): Promise<boolean> {
  const supplied = request.headers.get("apikey");
  if (!validSecret(expected) || !validSecret(supplied)) return false;
  const encoder = new TextEncoder();
  const algorithm = { name: "HMAC", hash: "SHA-256" };
  const expectedKey = await crypto.subtle.importKey(
    "raw",
    encoder.encode(expected),
    algorithm,
    false,
    ["sign"],
  );
  const suppliedKey = await crypto.subtle.importKey(
    "raw",
    encoder.encode(supplied),
    algorithm,
    false,
    ["verify"],
  );
  const message = encoder.encode("animal-photo-cleanup:invocation:v1");
  const signature = await crypto.subtle.sign("HMAC", expectedKey, message);
  return crypto.subtle.verify("HMAC", suppliedKey, signature, message);
}
