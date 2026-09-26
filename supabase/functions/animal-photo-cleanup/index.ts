import { createHandler } from "./handler.ts";

// No I/O at import. Runtime environment is read only after a POST arrives.
// Monotonic elapsed time anchored to wall time for comparison with SQL leases.
export default {
  fetch(request: Request): Promise<Response> {
    const epoch = Date.now(), started = performance.now();
    const handler = createHandler((name) => Deno.env.get(name), {
      fetch: (url, init) => fetch(url, init),
      now: () => Math.floor(epoch + performance.now() - started),
      log: (event) => console.log(JSON.stringify(event)),
    });
    return handler(request);
  },
};
