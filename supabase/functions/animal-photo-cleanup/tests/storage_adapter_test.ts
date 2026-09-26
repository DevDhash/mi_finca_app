import { deepStrictEqual, equal, ok } from "node:assert/strict";
import { test } from "node:test";
import { StorageAdapter } from "../adapters/storage_adapter.ts";
import { JobsAdapter } from "../adapters/jobs_adapter.ts";
import { classifyError } from "../errors.ts";
import { cleanup } from "../cleanup.ts";
import type { ListOptions } from "../types.ts";
import { FakeBudget, file, job, ledger, uuid } from "./fakes.ts";
import {
  deadline,
  folder,
  json,
  never,
  options,
  transport,
} from "./adapter_fakes.ts";
const entry = (i: number) => ({
  name: file(i).name,
  id: uuid(i),
  metadata: {},
});
const paths = (n: number) =>
  Array.from({ length: n }, (_, i) => `${folder}/${file(i).name}`);
for (const n of [0, 1, 100]) {
  test(`Storage list ${n}`, async () => {
    const { http, calls } = transport([
      json(Array.from({ length: n }, (_, i) => entry(i))),
    ]);
    const r = await new StorageAdapter(http, job, deadline).list(
      folder,
      options,
    );
    ok(r.ok);
    equal(r.value.length, n);
    deepStrictEqual(JSON.parse(calls[0].init.body as string), {
      prefix: folder,
      ...options,
    });
    equal(
      new URL(calls[0].url).pathname,
      "/storage/v1/object/list/animal-photos",
    );
  });
}
for (
  const suspicious of [{ name: "folder", id: null, metadata: null }, {}, null, {
    ...entry(1),
    name: "../escape",
  }]
) {
  test(`suspicious entry reaches core ${JSON.stringify(suspicious)}`, async () => {
    const { http, calls } = transport([json([entry(2), suspicious])]);
    const r = await cleanup(
      job,
      ledger,
      new StorageAdapter(http, job, deadline),
      new FakeBudget(),
    );
    deepStrictEqual(r, {
      outcome: "quarantined",
      errorCode: "invalid_namespace",
    });
    equal(calls.length, 1);
  });
}
for (const malformed of [null, {}, "bad"]) {
  test(`list malformed ${JSON.stringify(malformed)}`, async () => {
    const { http } = transport([json(malformed)]);
    equal(
      (await new StorageAdapter(http, job, deadline).list(folder, options)).ok,
      false,
    );
  });
}
for (
  const bad of [{ ...options, offset: 1 }, { ...options, limit: 101 }, {
    ...options,
    search: "x",
  }]
) {
  test(`list invalid options ${JSON.stringify(bad)}`, async () => {
    const { http, calls } = transport([]);
    equal(
      (await new StorageAdapter(http, job, deadline).list(
        folder,
        bad as ListOptions,
      )).ok,
      false,
    );
    equal(calls.length, 0);
  });
}
for (const n of [1, 100]) {
  test(`remove ${n} preserves exact paths, partial inventory ignored`, async () => {
    const { http, calls } = transport([json([])]);
    ok((await new StorageAdapter(http, job, deadline).remove(paths(n))).ok);
    equal(calls[0].init.method, "DELETE");
    deepStrictEqual(JSON.parse(calls[0].init.body as string), {
      prefixes: paths(n),
    });
  });
}
for (
  const invalid of [
    [],
    paths(101),
    [paths(1)[0], paths(1)[0]],
    [`${folder}/*`],
    [folder],
    [""],
    [`${uuid(9)}/${job.animalId}/${file(1).name}`],
    [`${folder}/../${file(1).name}`],
  ]
) {
  test(`remove rejects ${JSON.stringify(invalid).slice(0, 90)}`, async () => {
    const { http, calls } = transport([]);
    equal(
      (await new StorageAdapter(http, job, deadline).remove(invalid)).ok,
      false,
    );
    equal(calls.length, 0);
  });
}
for (const operation of ["list", "remove"] as const) {
  for (
    const [label, response, expected] of [
      ["429", json({}, 429), "rate_limited"],
      ["SlowDown", json({ code: "SlowDown" }, 503), "rate_limited"],
      ["401", json({}, 401), "permission_denied"],
      ["403", json({}, 403), "permission_denied"],
      ["timeout", never, "timeout"],
      ["network", new Error("offline"), "storage_unavailable"],
      ["InternalError", json({ code: "InternalError" }, 503), "internal_error"],
      ["502", json({}, 502), "storage_unavailable"],
      ["malformed JSON", new Response("{"), "internal_error"],
      ["404", json({}, 404), "internal_error"],
    ] as const
  ) {
    test(`${operation} error ${label}`, async () => {
      const { http } = transport([response]);
      const storage = new StorageAdapter(http, job, () => Date.now() + 10);
      const r = operation === "list"
        ? await storage.list(folder, options)
        : await storage.remove(paths(1));
      ok(!r.ok);
      equal(classifyError(r.error), expected);
    });
  }
}
test("global permission error latches and blocks further claims", async () => {
  const { http, calls } = transport([
    json({ message: "synthetic private diagnostic" }, 403),
  ]);
  const storage = new StorageAdapter(http, job, deadline);
  await storage.list(folder, options);
  ok(storage.fatalWorkerError);
  const jobs = new JobsAdapter(http, deadline);
  ok(jobs.fatalWorkerError);
  equal((await jobs.claim()).ok, false);
  equal(calls.length, 1);
});
