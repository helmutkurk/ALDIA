import { test } from "node:test";
import assert from "node:assert/strict";

import { createMockSource } from "../src/data/mock-source.js";
import { ApiError, createApiSource } from "../src/data/api-source.js";
import { parseCaseList } from "../src/domain/schema.js";
import { readConfig } from "../src/config.js";
import { NOW, rawCase } from "./helpers.js";

test("mock source: every synthetic case passes the same validation as the API", async () => {
  const source = createMockSource({ now: NOW });
  const parsed = parseCaseList(await source.listCases());
  assert.equal(parsed.ok, true);
  assert.equal(parsed.value.rejected, 0);
  assert.ok(parsed.value.cases.length >= 40);
  const dropped = parsed.value.cases.reduce((n, c) => n + c.dropped, 0);
  assert.equal(dropped, 0);
  assert.ok(parsed.value.cases.some((c) => c.status === "fixed"));
});

test("mock source is deterministic for the same seed", async () => {
  const a = await createMockSource({ now: NOW, seed: 7 }).listCases();
  const b = await createMockSource({ now: NOW, seed: 7 }).listCases();
  assert.deepEqual(
    a.cases.map((c) => [c.id, c.lat, c.status]),
    b.cases.map((c) => [c.id, c.lat, c.status]),
  );
});

test("mock source enforces the workflow and closes a case only with an after-photo", async () => {
  const source = createMockSource({ now: NOW });
  const { cases } = await source.listCases();
  const inProgress = cases.find((c) => c.status === "in_progress");
  await assert.rejects(() => source.setStatus(inProgress.id, "fixed"), /No se puede pasar/);
  const claimed = await source.setStatus(inProgress.id, "fix_claimed", "Trabajo terminado");
  assert.equal(claimed.status, "fix_claimed");
  const reopened = await source.simulateRepairCheck(inProgress.id, false);
  assert.equal(reopened.status, "reopened");
  await source.setStatus(inProgress.id, "in_progress");
  const fixed = await source.simulateRepairCheck(inProgress.id, true);
  assert.equal(fixed.status, "fixed");
  assert.equal(fixed.history.at(-1).by, "sistema");
});

function fakeFetch(responder) {
  const calls = [];
  const impl = async (url, init) => {
    calls.push({ url, init });
    return responder(url, init);
  };
  return { impl, calls };
}

const json = (status, body) => ({ ok: status >= 200 && status < 300, status, json: async () => body });

test("api source: builds URLs, sends the status change, and maps errors to Spanish messages", async () => {
  const { impl, calls } = fakeFetch((url) =>
    url.endsWith("/status") ? json(200, rawCase({ status: "in_review" })) : json(200, { cases: [rawCase()] }),
  );
  const api = createApiSource({ baseUrl: "http://127.0.0.1:8080/api/v1/", fetchImpl: impl });

  const body = await api.listCases({ since: "2026-11-19T00:00:00.000Z" });
  assert.equal(calls[0].url, "http://127.0.0.1:8080/api/v1/cases?updated_since=2026-11-19T00%3A00%3A00.000Z");
  assert.equal(parseCaseList(body).value.cases.length, 1);

  await api.setStatus("ALD-GT-00001", "in_review", "Revisar");
  assert.equal(calls[1].url, "http://127.0.0.1:8080/api/v1/cases/ALD-GT-00001/status");
  assert.equal(calls[1].init.method, "POST");
  assert.deepEqual(JSON.parse(calls[1].init.body), { status: "in_review", note: "Revisar" });
  assert.equal(calls[1].init.credentials, "include");

  const denied = createApiSource({ baseUrl: "/api/v1", fetchImpl: async () => json(403, {}) });
  await assert.rejects(() => denied.listCases(), (e) => e instanceof ApiError && e.status === 403 && /permiso/.test(e.message));
  const offline = createApiSource({ baseUrl: "/api/v1", fetchImpl: async () => { throw new TypeError("network"); } });
  await assert.rejects(() => offline.listCases(), /Sin conexión/);
});

test("config: demo by default, API only on request, unsafe api values ignored", () => {
  assert.equal(readConfig("").source, "mock");
  const api = readConfig("?source=api&api=http://127.0.0.1:8080/api/v1");
  assert.equal(api.source, "api");
  assert.equal(api.apiBaseUrl, "http://127.0.0.1:8080/api/v1");
  assert.equal(readConfig("?source=api&api=javascript:alert(1)").apiBaseUrl, "/api/v1");
});
