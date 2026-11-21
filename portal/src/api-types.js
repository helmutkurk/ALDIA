/** Shared wire models. Optional fields retain compatibility with older APIs.
 * These declarations describe data; runtime acceptance belongs to api-validation.
 * @typedef {'operator'|'supervisor'|'admin'} StaffRole
 * @typedef {{username: string, role: StaffRole}} StaffUser
 * @typedef {{user: StaffUser}} UserEnvelope
 * @typedef {{enabled: boolean, dev_tokens: boolean}} AuthConfig
 * @typedef {{code: string, message: string}} ErrorDetail
 * @typedef {{name: string, passed: boolean, detail: string, code?: string}} VerificationCheck
 * @typedef {{passed: boolean, mode: 'stub'|'heuristic'|'model', checks: VerificationCheck[], phash?: string}} Verification
 * @typedef {'pendiente_verificacion'|'rechazado_verificador'|'nuevo'|'en_revision'|'programado'|'en_proceso'|'resuelto'|'no_procede'|'fuera_de_competencia'|'duplicado'|'oculto'} CaseState
 * @typedef {'pending'|'open'|'in_work'|'resolved'|'closed'|'hidden'} StateGroup
 * @typedef {'pending'|'verified'|'rejected'} VerifierStatus
 * @typedef {'open'|'acknowledged'|'fixed'|'closed'} Resolution
 * @typedef {'accessibility'|'sidewalk'|'pothole'|'graffiti'|'open_drain'|'street_light'} Category
 * @typedef {{at: string, actor_role: 'system'|StaffRole, actor?: string, from_state: CaseState|null, to_state: CaseState, public_note: string|null, internal_note?: string|null}} ReportEvent
 */

/**
 * @typedef {object} Report
 * @property {string} id
 * @property {Category} category
 * @property {number} latitude
 * @property {number} longitude
 * @property {string} captured_at
 * @property {string} created_at
 * @property {VerifierStatus} status
 * @property {Resolution} resolution
 * @property {string|null} note
 * @property {string} photo_url
 * @property {string} [thumbnail_url]
 * @property {Verification|null} verification
 * @property {CaseState} [state]
 * @property {StateGroup} [state_group]
 * @property {string|null} [verified_at]
 * @property {string|null} [resolved_at]
 * @property {string|null} [closed_at]
 * @property {string|null} [state_changed_at]
 * @property {string|null} [assigned_at]
 * @property {string|null} [assignee]
 * @property {string|null} [duplicate_of]
 * @property {string|null} [public_note]
 * @property {ReportEvent[]} [events]
 * @property {number} [age_hours]
 */

/**
 * @typedef {{items: Report[], total: number, limit?: number, offset?: number}} ReportPage
 * @typedef {[number, number, number, number]} Bbox west, south, east, north
 * @typedef {{bbox?: Bbox, category?: Category|'', status?: VerifierStatus|'', resolution?: Resolution|'', state?: CaseState|'', state_group?: StateGroup|'', created_from?: string, created_to?: string, assignee?: string, include_old?: string|boolean, sort?: 'newest'|'oldest'|'updated'|'age_in_state'|'', offset?: number, delimiter?: 'comma'|'semicolon'}} ReportQuery
 * @typedef {{lat: number, lon: number, count: number, ids?: string[]}} Cluster
 * @typedef {{clusters: Cluster[], total: number}} ClusterPage
 * @typedef {{median: number|null, p90: number|null, n: number}} DurationSamples
 * @typedef {{week: string, recibidos: number, resueltos: number}} WeeklyStats
 * @typedef {{category: Category, total: number, resueltos: number, abiertos: number, cerrados: number, mediana_reparacion_horas: number|null, p90_reparacion_horas: number|null, n_resueltos: number}} CategoryStats
 */

/**
 * @typedef {object} Stats
 * @property {number} total
 * @property {Partial<Record<Category, number>>} by_category
 * @property {Partial<Record<VerifierStatus, number>>} by_status
 * @property {Partial<Record<Resolution, number>>} by_resolution
 * @property {number} [recibidos]
 * @property {number} [rechazados_verificador]
 * @property {number} [abiertos]
 * @property {number} [resueltos]
 * @property {number} [cerrados_sin_solucion]
 * @property {number|null} [tasa_resolucion]
 * @property {DurationSamples & {mean: number|null}} [resolucion_horas]
 * @property {DurationSamples} [primera_respuesta_horas]
 * @property {Partial<Record<'0-2'|'3-7'|'8-30'|'>30', number>>} [antiguedad_abiertos]
 * @property {number|null} [sla_cumplido]
 * @property {number} [vencidos]
 * @property {Partial<Record<CaseState, number>>} [by_state]
 * @property {Partial<Record<StateGroup, number>>} [by_state_group]
 * @property {WeeklyStats[]} [weekly]
 * @property {CategoryStats[]} [por_categoria]
 * @property {CategoryStats[]} [top_categorias]
 */

/**
 * @typedef {{signal?: AbortSignal}} ReadOptions
 * @typedef {{to: CaseState, public_note?: string, internal_note?: string, duplicate_of?: string}} TransitionRequest
 * @typedef {{username: string, password: string}|{assignee: string|null}|TransitionRequest} WriteRequest
 * @typedef {ReadOptions & {method?: 'GET'|'HEAD'|'POST', body?: WriteRequest, responseType?: 'json'|'blob'|'photo'}} RequestOptions
 * @typedef {{getUser?: () => StaffUser|null, getToken: () => string, getRole?: () => StaffRole|null, clear?: (reason?: Error) => void}} StaffIdentity
 */

export {};
