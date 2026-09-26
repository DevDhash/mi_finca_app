import { HttpTransport } from "../adapters/http.ts";
import type { Fetch } from "../adapters/http.ts";
import { job } from "./fakes.ts";
export const claimRow = {
  animal_id: job.animalId,
  user_id: job.userId,
  tombstone_sequence: job.tombstoneSequence.toString(),
  tombstone_operation_id: job.operationId,
  tombstone_deleted_at: job.deletedAt,
  status: "leased",
  generation: job.generation.toString(),
  lease_token: job.leaseToken,
  lease_expires_at: job.leaseExpiresAt,
};
export const terminalRow = {
  collection: "animals",
  entity_id: job.animalId,
  user_id: job.userId,
  sequence: job.tombstoneSequence.toString(),
  operation_id: job.operationId,
  deleted_at: job.deletedAt,
};
export const options = {
  limit: 100,
  offset: 0,
  sortBy: { column: "name", order: "asc" },
} as const;
export const folder = `${job.userId}/${job.animalId}`;
export const deadline = () => Date.now() + 1000;
export const json = (value: unknown, status = 200) =>
  new Response(JSON.stringify(value), { status });
export function transport(replies: (Response | Error | Fetch)[]) {
  const calls: { url: string; init: RequestInit }[] = [];
  const http = new HttpTransport("https://fixture.invalid", {
    apikey: "synthetic-not-a-key",
  }, (url, init) =>
    new Promise<Response>((resolve) => {
      calls.push({ url, init });
      const next = replies.shift();
      if (next instanceof Error) throw next;
      if (typeof next === "function") return resolve(next(url, init));
      if (!next) throw new Error("UNEXPECTED_MOCK_CALL");
      resolve(next);
    }));
  return { http, calls };
}
export const never: Fetch = () => new Promise<Response>(() => {});
