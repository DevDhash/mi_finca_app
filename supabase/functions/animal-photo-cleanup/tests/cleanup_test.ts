import { deepStrictEqual, equal, ok } from "node:assert/strict";
import { test } from "node:test";
import { cleanup } from "../cleanup.ts";
import type { NormalizedError, PhotoStorage, StorageEntry } from "../types.ts";
import { FakeBudget, FakeStorage, file, job, ledger, uuid } from "./fakes.ts";

for (const count of [0, 1, 3, 100, 101, 1000, 1001]) {
  test(`scale ${count}: exact paths, offset zero, two empty reads`, async () => {
    const store = new FakeStorage(count);
    deepStrictEqual(await cleanup(job, ledger, store, new FakeBudget()), {
      outcome: "observed_empty",
    });
    equal(store.entries.length, 0);
    const deleted = store.removals.flat();
    equal(deleted.length, count);
    equal(new Set(deleted).size, count);
    deepStrictEqual(
      [...deleted].sort(),
      Array.from(
        { length: count },
        (_, i) => `${job.userId}/${job.animalId}/${file(i + 100).name}`,
      ).sort(),
    );
    for (const path of deleted) {
      ok(path.startsWith(`${job.userId}/${job.animalId}/`));
    }
    for (const batch of store.removals) {
      ok(batch.length > 0 && batch.length <= 100);
    }
    for (const call of store.lists) {
      equal(call.folder, `${job.userId}/${job.animalId}`);
      deepStrictEqual(call.options, {
        limit: 100,
        offset: 0,
        sortBy: { column: "name", order: "asc" },
      });
    }
    deepStrictEqual(store.lists.slice(-2).map((c) => c.size), [0, 0]);
    equal(store.lists.length, Math.ceil(count / 100) + 2);
  });
}

test("partial removal ignores response and re-lists remaining objects", async () => {
  const store = new FakeStorage(101);
  store.deleteLimit = 40;
  equal(
    (await cleanup(job, ledger, store, new FakeBudget())).outcome,
    "observed_empty",
  );
  equal(store.removals.length, 3);
  equal(store.entries.length, 0);
});

test("disappearance between list and remove is harmless", async () => {
  const store = new FakeStorage(1);
  store.onRemove = () => {
    store.entries = [];
    return { ok: true, value: [] };
  };
  equal(
    (await cleanup(job, ledger, store, new FakeBudget())).outcome,
    "observed_empty",
  );
});

test("two sequential executions are idempotent", async () => {
  const store = new FakeStorage(3);
  for (let i = 0; i < 2; i++) {
    equal(
      (await cleanup(job, ledger, store, new FakeBudget())).outcome,
      "observed_empty",
    );
  }
  equal(store.removals.length, 1);
});

test("crash after remove: subsequent execution recovers from actual fake state", async () => {
  const store = new FakeStorage(3);
  store.beforeList = () => {
    if (store.removals.length > 0) throw new Error("simulated termination");
  };
  deepStrictEqual(await cleanup(job, ledger, store, new FakeBudget()), {
    outcome: "retry",
    errorCode: "internal_error",
  });
  equal(store.entries.length, 0);
  store.beforeList = undefined;
  equal(
    (await cleanup(job, ledger, store, new FakeBudget())).outcome,
    "observed_empty",
  );
});

test("upload in second empty check is removed before a new double-empty", async () => {
  const store = new FakeStorage(1);
  store.beforeList = () => {
    if (store.lists.length === 2) store.entries.push(file(999));
  };
  equal(
    (await cleanup(job, ledger, store, new FakeBudget())).outcome,
    "observed_empty",
  );
  deepStrictEqual(store.lists.map((c) => c.size), [1, 0, 1, 0, 0]);
  equal(store.removals.length, 2);
});

test("two consecutive cycles without disappearance produce no_progress", async () => {
  const store = new FakeStorage(100);
  store.deleteLimit = 0;
  deepStrictEqual(await cleanup(job, ledger, store, new FakeBudget()), {
    outcome: "retry",
    errorCode: "no_progress",
  });
  equal(store.removals.length, 2);
  equal(store.lists.length, 3);
});

test("disappearance plus newly arriving objects resets stalled counter", async () => {
  const store = new FakeStorage(2);
  store.onRemove = () => {
    if (store.removals.length === 2) {
      store.entries.shift();
      store.entries.push(file(999));
    } else if (store.removals.length === 4) store.entries = [];
    return { ok: true, value: [] };
  };
  equal(
    (await cleanup(job, ledger, store, new FakeBudget())).outcome,
    "observed_empty",
  );
  equal(store.removals.length, 4);
});

test("new arrivals alone do not reset stalled counter", async () => {
  const store = new FakeStorage(1);
  store.onRemove = () => {
    store.entries.push(file(900 + store.removals.length));
    return { ok: true, value: [] };
  };
  deepStrictEqual(await cleanup(job, ledger, store, new FakeBudget()), {
    outcome: "retry",
    errorCode: "no_progress",
  });
});

for (
  const stage of ["before_list", "before_remove", "second_empty", "finish"]
) {
  test(`budget exhausted ${stage} returns timeout`, async () => {
    const store = new FakeStorage(stage === "before_remove" ? 1 : 0);
    const budget = new FakeBudget();
    if (stage === "before_list") budget.lists = 0;
    if (stage === "before_remove") budget.removes = 0;
    if (stage === "second_empty") budget.lists = 1;
    if (stage === "finish") budget.finish = false;
    deepStrictEqual(await cleanup(job, ledger, store, budget), {
      outcome: "retry",
      errorCode: "timeout",
    });
    equal(store.removals.length, 0);
    if (stage === "before_list") equal(store.lists.length, 0);
  });
}

test("max batches with progress remains recoverable and is not no_progress", async () => {
  const store = new FakeStorage(101);
  deepStrictEqual(await cleanup(job, ledger, store, new FakeBudget(), 1), {
    outcome: "retry",
    errorCode: "budget_exhausted",
  });
  equal(store.entries.length, 1);
  equal(store.removals.length, 1);
  equal(
    (await cleanup(job, ledger, store, new FakeBudget())).outcome,
    "observed_empty",
  );
});

test("final allowed batch may still confirm empty", async () => {
  equal(
    (await cleanup(job, ledger, new FakeStorage(100), new FakeBudget(), 1))
      .outcome,
    "observed_empty",
  );
});

test("default 20 batches stops even while making progress", async () => {
  const store = new FakeStorage(2001);
  deepStrictEqual(await cleanup(job, ledger, store, new FakeBudget()), {
    outcome: "retry",
    errorCode: "budget_exhausted",
  });
  equal(store.removals.length, 20);
  equal(store.entries.length, 1);
});

const errors: [NormalizedError, string][] = [
  [{ kind: "timeout" }, "timeout"],
  [{ kind: "http", status: 429 }, "rate_limited"],
  [{ kind: "http", status: 503, code: "SlowDown" }, "rate_limited"],
  [{ kind: "http", status: 403 }, "permission_denied"],
  [{ kind: "network" }, "storage_unavailable"],
  [{ kind: "unknown" }, "internal_error"],
  [{ kind: "http", code: "InternalError", status: 500 }, "internal_error"],
];
for (const [error, expected] of errors) {
  for (const phase of ["list", "remove"] as const) {
    test(`${phase} error ${JSON.stringify(error)}`, async () => {
      const store = new FakeStorage(1);
      if (phase === "list") store.onList = () => ({ ok: false, error });
      else store.onRemove = () => ({ ok: false, error });
      deepStrictEqual(await cleanup(job, ledger, store, new FakeBudget()), {
        outcome: "retry",
        errorCode: expected,
      });
      if (phase === "list") equal(store.removals.length, 0);
    });
  }
}

test("error between empty reads cannot become observed_empty", async () => {
  const store = new FakeStorage();
  store.onList = () =>
    store.lists.length === 2
      ? { ok: false, error: { kind: "timeout" } }
      : { ok: true, value: [] };
  deepStrictEqual(await cleanup(job, ledger, store, new FakeBudget()), {
    outcome: "retry",
    errorCode: "timeout",
  });
});

test("null page is not an empty namespace", async () => {
  const store = new FakeStorage();
  store.onList = () => ({ ok: true, value: null as unknown as StorageEntry[] });
  deepStrictEqual(await cleanup(job, ledger, store, new FakeBudget()), {
    outcome: "retry",
    errorCode: "internal_error",
  });
});

for (const field of ["userId", "animalId"] as const) {
  for (
    const bad of [
      "",
      "../",
      "/",
      "\\",
      "%2f",
      "%5c",
      " a",
      uuid(1).toUpperCase(),
      `${uuid(1)}\n`,
    ]
  ) {
    test(`invalid ${field} ${JSON.stringify(bad)}: no I/O`, async () => {
      const store = new FakeStorage(1);
      deepStrictEqual(
        await cleanup(
          { ...job, [field]: bad },
          ledger,
          store,
          new FakeBudget(),
        ),
        {
          outcome: "quarantined",
          errorCode: "invalid_namespace",
        },
      );
      equal(store.lists.length, 0);
      equal(store.removals.length, 0);
    });
  }
}

for (
  const entry of [
    { kind: "folder", name: uuid(3) },
    { kind: "file", name: "../evil.jpg" },
    { kind: "file", name: `/${file(100).name}` },
    { kind: "file", name: `${uuid(1)}/${file(100).name}` },
    { kind: "file", name: `${uuid(1)}\\bad.jpg` },
    { kind: "file", name: `%2e%2e%2f${file(100).name}` },
    { kind: "file", name: "not-a-uuid.jpg" },
    { kind: "file", name: "" },
    { kind: "file", name: `${uuid(1)}.jp-g` },
    { kind: "file", name: `${uuid(1)}.jpg\n` },
  ] as StorageEntry[]
) {
  test(`invalid page ${JSON.stringify(entry)} prevents all removes`, async () => {
    const store = new FakeStorage(99);
    store.entries.push(entry);
    deepStrictEqual(await cleanup(job, ledger, store, new FakeBudget()), {
      outcome: "quarantined",
      errorCode: "invalid_namespace",
    });
    equal(store.removals.length, 0);
  });
}

test("wrong bound bucket cannot perform I/O", async () => {
  const store = new FakeStorage(1);
  Object.defineProperty(store, "bucket", { value: "other-bucket" });
  deepStrictEqual(
    await cleanup(job, ledger, store as PhotoStorage, new FakeBudget()),
    {
      outcome: "quarantined",
      errorCode: "invalid_namespace",
    },
  );
  equal(store.lists.length, 0);
});

test("terminal mismatch blocks all I/O", async () => {
  const store = new FakeStorage(1);
  deepStrictEqual(
    await cleanup(
      job,
      { ...ledger, userId: uuid(999) },
      store,
      new FakeBudget(),
    ),
    {
      outcome: "quarantined",
      errorCode: "terminal_mismatch",
    },
  );
  equal(store.lists.length, 0);
});

test("raw exception messages never enter result", async () => {
  const store = new FakeStorage(1);
  store.onRemove = () => {
    throw new Error("SECRET should never escape");
  };
  deepStrictEqual(await cleanup(job, ledger, store, new FakeBudget()), {
    outcome: "retry",
    errorCode: "internal_error",
  });
});

for (const max of [0, -1, 1.5, NaN, Infinity]) {
  test(`invalid maxBatches ${max} cannot start work`, async () => {
    const store = new FakeStorage(1);
    equal(
      (await cleanup(job, ledger, store, new FakeBudget(), max)).outcome,
      "retry",
    );
    equal(store.lists.length, 0);
  });
}

test("budget exhaustion after remove preserves recoverable partial state", async () => {
  const store = new FakeStorage(101);
  const budget = new FakeBudget();
  budget.lists = 1;
  deepStrictEqual(await cleanup(job, ledger, store, budget), {
    outcome: "retry",
    errorCode: "timeout",
  });
  equal(store.entries.length, 1);
  equal(store.lists.length, 1);
  equal(store.removals.length, 1);
});

test("missing ledger prevents Storage calls", async () => {
  const store = new FakeStorage(1);
  deepStrictEqual(await cleanup(job, null, store, new FakeBudget()), {
    outcome: "quarantined",
    errorCode: "terminal_mismatch",
  });
  equal(store.lists.length, 0);
  equal(store.removals.length, 0);
});

test("invalid claim metadata prevents Storage calls", async () => {
  const store = new FakeStorage(1);
  deepStrictEqual(
    await cleanup({ ...job, generation: 0n }, ledger, store, new FakeBudget()),
    {
      outcome: "retry",
      errorCode: "internal_error",
    },
  );
  equal(store.lists.length, 0);
});

test("job mutation during await cannot redirect the namespace", async () => {
  const store = new FakeStorage(101);
  const mutableJob = { ...job };
  store.beforeList = () => {
    mutableJob.userId = uuid(999);
  };
  equal(
    (await cleanup(mutableJob, ledger, store, new FakeBudget())).outcome,
    "observed_empty",
  );
  for (const paths of store.removals) {
    for (const path of paths) {
      ok(path.startsWith(`${job.userId}/${job.animalId}/`));
    }
  }
});

test("E1 mixed-case filename and long extension preserve exact remove path", async () => {
  const store = new FakeStorage();
  const name = `${uuid(77).toUpperCase()}.${"Ab9".repeat(20)}`;
  store.entries = [{ kind: "file", name }];
  equal(
    (await cleanup(job, ledger, store, new FakeBudget())).outcome,
    "observed_empty",
  );
  deepStrictEqual(store.removals, [[`${job.userId}/${job.animalId}/${name}`]]);
});
