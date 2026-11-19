// Data source for the real backend (backend/api). Endpoints and JSON shapes are in
// portal/docs/api-contract.md. Responses are validated by the caller with domain/schema.js.

export class ApiError extends Error {
  constructor(message, status) {
    super(message);
    this.name = "ApiError";
    this.status = status;
  }
}

function messageFor(status) {
  if (status === 401 || status === 403) return "Tu sesión no tiene permiso para ver o cambiar estos casos.";
  if (status === 404) return "No se encontró el caso.";
  if (status === 409) return "El caso cambió mientras lo editabas. Actualiza e intenta otra vez.";
  if (status === 422) return "El servidor rechazó el cambio de estado.";
  return `El servidor de Aldia respondió con un error (${status}).`;
}

export function createApiSource({ baseUrl, fetchImpl = (...args) => globalThis.fetch(...args) }) {
  const base = baseUrl.replace(/\/+$/, "");

  async function request(path, init = {}) {
    let res;
    try {
      res = await fetchImpl(`${base}${path}`, {
        ...init,
        credentials: "include",
        headers: { Accept: "application/json", ...(init.body ? { "Content-Type": "application/json" } : {}) },
      });
    } catch {
      throw new ApiError("Sin conexión con el servidor de Aldia.", 0);
    }
    if (!res.ok) throw new ApiError(messageFor(res.status), res.status);
    try {
      return await res.json();
    } catch {
      throw new ApiError("El servidor de Aldia envió una respuesta que no se puede leer.", res.status);
    }
  }

  return {
    kind: "api",
    supportsSimulation: false,

    /** `GET /cases[?updated_since=ISO]` -> `{ cases, serverTime }` */
    listCases({ since } = {}) {
      const query = since ? `?updated_since=${encodeURIComponent(since)}` : "";
      return request(`/cases${query}`);
    },

    /** `POST /cases/:id/status` with `{ status, note }` -> the updated case */
    setStatus(id, status, note) {
      return request(`/cases/${encodeURIComponent(id)}/status`, {
        method: "POST",
        body: JSON.stringify({ status, note: note || undefined }),
      });
    },
  };
}
