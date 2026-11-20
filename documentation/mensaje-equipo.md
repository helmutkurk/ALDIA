# Mensaje para el equipo — Aldia listo para trabajar

Equipo: el MVP local de Aldia ya está en `main` y `develop` (idénticas). Pueden empezar.

**Cómo arrancar** (ver `documentation/dev-setup.md`): `mise install`, luego `make dev-all` y `make seed`. Portal en http://127.0.0.1:5173, API en :8000, verificador en :8001. Credenciales de demo: `documentation/demo-credentials.md`.

**Flujo de trabajo:** rama `feat/...` desde `develop` → PR a `develop` → CI en verde. Tras cada sprint, PR `develop` → `main`. Nada de push directo a `main` ni force push. No subir secretos, `.env`, fotos reales ni estrategia/presupuesto (repo público).

**Estado:** API v0.5 (staff auth, login por teléfono, estadísticas, CSV, Open311, miniaturas), portal estilo FixMyStreet con colores SeeClickFix, app Flutter (flujo SeeClickFix en español de Guatemala), verificador heurístico. Pruebas: API 437, portal 181, app 137, verificador 73.

**Por rol:** tareas nuevas en Notion (Tasks). Pendiente fuera del MVP local: modelo de reconocimiento real (Lorenz), proveedor de SMS, PostgreSQL en producción, cuentas y firma de Android/iOS (Helmut, `documentation/mobile-release.md`), notificaciones push (requisitos de Fernando en la rama ya fusionada).

**Límites conocidos:** no se probó Docker compose ni iOS; la vista móvil del portal no se verificó visualmente en esta ronda.
