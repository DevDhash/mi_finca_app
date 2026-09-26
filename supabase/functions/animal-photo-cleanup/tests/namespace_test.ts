import { deepStrictEqual, equal } from "node:assert/strict";
import { test } from "node:test";
import { deriveNamespace, pagePaths } from "../namespace.ts";
import { file, job, uuid } from "./fakes.ts";

test("namespace is derived exactly without normalization", () => {
  deepStrictEqual(deriveNamespace(job), {
    folder: `${job.userId}/${job.animalId}`,
    prefix: `${job.userId}/${job.animalId}/`,
  });
});
for (const extension of ["jpg", "jpeg", "png", "webp", "heic", "avif", "a1"]) {
  test(`accepts lowercase alphanumeric extension ${extension}`, () => {
    deepStrictEqual(pagePaths(job, [file(100, extension)]), [
      `${job.userId}/${job.animalId}/${uuid(100)}.${extension}`,
    ]);
  });
}
test("duplicate paths and oversized pages fail closed", () => {
  equal(pagePaths(job, [file(100), file(100)]), null);
  equal(pagePaths(job, Array.from({ length: 101 }, (_, i) => file(i))), null);
});
test("extension rejects punctuation and empty suffix", () => {
  for (const ext of ["", "jpg.png", "jp-g", "jpg_", "jpg "]) {
    equal(pagePaths(job, [file(100, ext)]), null);
  }
});

for (
  const name of [
    `${uuid(100).toUpperCase()}.JPG`,
    `${uuid(100).replace("aaaa", "AaAa")}.HeIc`,
    `${uuid(100)}.${"a".repeat(17)}`,
    `${uuid(100)}.${"Ab9".repeat(100)}`,
    "00000000-0000-0000-0000-000000000000.0",
    "ffffffff-ffff-ffff-ffff-ffffffffffff.AVIF",
  ]
) {
  test(`E1 filename shape accepted without normalization: ${name}`, () => {
    deepStrictEqual(pagePaths(job, [{ kind: "file", name }]), [
      `${job.userId}/${job.animalId}/${name}`,
    ]);
  });
}
for (
  const name of [
    `${uuid(100)}.é`,
    `${uuid(100)}.１２`,
    `${uuid(100)}.jpg\r`,
    `{${uuid(100)}}.jpg`,
    `${uuid(100).replaceAll("-", "")}.jpg`,
    `${uuid(100)}.jpg/extra`,
    `${uuid(100)}.%2f`,
  ]
) {
  test(`E1 rejects filename outside exact ASCII grammar: ${JSON.stringify(name)}`, () => {
    equal(pagePaths(job, [{ kind: "file", name }]), null);
  });
}
test("E1 UUID format does not constrain version/variant bits", () => {
  deepStrictEqual(
    deriveNamespace({
      userId: "00000000-0000-0000-0000-000000000000",
      animalId: "ffffffff-ffff-ffff-ffff-ffffffffffff",
    }),
    {
      folder:
        "00000000-0000-0000-0000-000000000000/ffffffff-ffff-ffff-ffff-ffffffffffff",
      prefix:
        "00000000-0000-0000-0000-000000000000/ffffffff-ffff-ffff-ffff-ffffffffffff/",
    },
  );
});
