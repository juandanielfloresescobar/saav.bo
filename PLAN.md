# SAAV Electoral - Plataforma de Conteo Rápido Electoral

## Visión General

Plataforma web para conteo rápido electoral donde delegados de recintos electorales suben fotos de actas y datos de conteo en tiempo real. Un panel operativo permite al candidato y su equipo visualizar los resultados consolidados.

---

## Arquitectura del Sistema

```
┌─────────────────────────────────────────────────────────┐
│                    FRONTEND (SPA)                        │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │  App Delegado │  │Panel Operativo│  │  Admin Panel  │  │
│  │  (Móvil-first)│  │ (Candidato)  │  │  (Comando)    │  │
│  └──────┬───────┘  └──────┬───────┘  └──────┬────────┘  │
│         │                  │                  │           │
├─────────┴──────────────────┴──────────────────┴──────────┤
│                                                          │
│                    SUPABASE (Backend)                     │
│                                                          │
│  ┌─────────┐ ┌──────────┐ ┌────────┐ ┌──────────────┐   │
│  │  Auth   │ │ Database │ │Storage │ │  Realtime     │   │
│  │(Usuarios)│ │(PostgreSQL)│ │(Fotos) │ │(Subscriptions)│   │
│  └─────────┘ └──────────┘ └────────┘ └──────────────┘   │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

---

## Stack Tecnológico

| Capa | Tecnología | Justificación |
|------|-----------|---------------|
| Frontend | HTML5 + CSS3 + Vanilla JS | Simplicidad, sin build tools, coherente con el proyecto actual |
| Backend | Supabase | Ya integrado, incluye Auth, DB, Storage, Realtime |
| Base de datos | PostgreSQL (via Supabase) | Relacional, robusto, consultas complejas |
| Almacenamiento | Supabase Storage | Para fotos de actas electorales |
| Tiempo real | Supabase Realtime | Actualización en vivo del conteo |
| Charts | Chart.js | Ya usado en el proyecto, ligero y efectivo |
| Hosting | GitHub Pages / Netlify | Estático, rápido, gratis |

---

## Módulos / Vistas

### 1. App del Delegado (móvil-first)
**Archivo:** `delegado.html`

- Login con credenciales asignadas por el comando
- Selección de recinto y mesa electoral
- Formulario de carga:
  - Foto del acta (cámara directa o galería)
  - Votos por candidato/partido (campos numéricos)
  - Votos nulos y blancos
  - Total de votantes en mesa
  - Observaciones (texto libre)
- Confirmación y envío
- Estado: "Pendiente de verificación" / "Verificado" / "Observado"
- Historial de actas enviadas por el delegado

### 2. Panel Operativo del Candidato
**Archivo:** `index.html`

- Dashboard principal con KPIs en tiempo real:
  - **Total de votos** por candidato/partido
  - **Porcentaje** de votos por candidato
  - **Actas procesadas** vs. total de actas esperadas
  - **Cobertura** (% de recintos reportados)
- Gráficos:
  - Barras/dona: distribución de votos por candidato
  - Línea temporal: evolución del conteo
  - Mapa de calor por departamento/circunscripción (opcional)
- Filtros:
  - Por departamento
  - Por circunscripción
  - Por municipio
  - Por recinto
- Tabla detallada de resultados por recinto
- Indicadores de confiabilidad (actas verificadas vs pendientes)

### 3. Panel de Administración (Comando de Campaña)
**Archivo:** `admin.html`

- Gestión de delegados (crear, editar, desactivar)
- Asignación de delegados a recintos/mesas
- Verificación de actas:
  - Ver foto del acta
  - Comparar datos ingresados vs foto
  - Aprobar / Observar / Rechazar
- Gestión del catálogo electoral:
  - Departamentos, circunscripciones, municipios, recintos, mesas
  - Candidatos y partidos
- Monitoreo de actividad de delegados
- Exportación de datos (CSV/Excel)

---

## Modelo de Base de Datos

### Schema: `electoral`

```sql
-- Catálogo geográfico/electoral
departamentos (id, nombre, codigo)
circunscripciones (id, nombre, codigo, departamento_id)
municipios (id, nombre, codigo, departamento_id)
recintos (id, nombre, codigo, direccion, municipio_id, circunscripcion_id, total_mesas)
mesas (id, numero, recinto_id, total_habilitados)

-- Partidos y candidatos
partidos (id, nombre, sigla, color, logo_url, orden)
candidatos (id, nombre, partido_id, tipo_eleccion)

-- Usuarios/Delegados
delegados (id, nombre, telefono, email, auth_user_id, recinto_id, estado)

-- Datos del conteo
actas (
  id,
  mesa_id,
  delegado_id,
  foto_url,
  total_votantes,
  votos_nulos,
  votos_blancos,
  estado,           -- 'pendiente', 'verificado', 'observado', 'rechazado'
  verificado_por,
  observaciones,
  created_at,
  updated_at
)

votos (
  id,
  acta_id,
  partido_id,
  cantidad
)
```

### Relaciones principales:
```
departamentos 1──N circunscripciones
departamentos 1──N municipios
municipios    1──N recintos
recintos      1──N mesas
recintos      1──N delegados
mesas         1──1 actas (una acta por mesa)
actas         1──N votos (un registro por partido)
partidos      1──N votos
partidos      1──N candidatos
delegados     1──N actas
```

---

## Flujo de Datos

```
1. DELEGADO en recinto
   │
   ├── Abre app en celular → Login
   ├── Selecciona mesa electoral
   ├── Toma foto del acta
   ├── Ingresa votos por partido
   └── Envía datos
        │
        ▼
2. SUPABASE
   │
   ├── Storage: guarda foto del acta
   ├── Database: inserta acta + votos
   ├── Realtime: notifica cambios
   │
   ▼
3. PANEL OPERATIVO (Candidato)
   │
   ├── Recibe actualización en tiempo real
   ├── Recalcula totales y porcentajes
   └── Actualiza gráficos y KPIs
        │
        ▼
4. PANEL ADMIN (Comando)
   │
   ├── Recibe acta nueva
   ├── Verificador compara foto vs datos
   └── Aprueba o rechaza acta
```

---

## Seguridad y Roles (Supabase Auth + RLS)

| Rol | Permisos |
|-----|----------|
| `delegado` | INSERT actas y votos de SU recinto, READ sus propias actas |
| `verificador` | READ todas las actas, UPDATE estado de actas |
| `candidato` | READ todos los datos agregados (solo lectura) |
| `admin` | FULL ACCESS a todas las tablas |

### Row Level Security (RLS):
- Delegados solo ven/editan datos de su recinto asignado
- Verificadores pueden ver todas las actas pero solo modificar el campo `estado`
- El panel del candidato usa vistas agregadas (no accede a datos individuales de delegados)

---

## Estructura de Archivos Propuesta

```
saav.bo/
├── index.html          # Panel Operativo (Candidato) - vista principal
├── delegado.html       # App del Delegado (móvil-first)
├── admin.html          # Panel de Administración
├── css/
│   ├── common.css      # Variables, reset, tipografía, componentes compartidos
│   ├── dashboard.css   # Estilos del panel operativo
│   ├── delegado.css    # Estilos de la app del delegado
│   └── admin.css       # Estilos del panel admin
├── js/
│   ├── config.js       # Configuración de Supabase y constantes
│   ├── auth.js         # Autenticación y manejo de sesiones
│   ├── dashboard.js    # Lógica del panel operativo
│   ├── delegado.js     # Lógica de la app del delegado
│   ├── admin.js        # Lógica del panel admin
│   └── utils.js        # Funciones utilitarias compartidas
├── assets/
│   ├── logo.png        # Logo de la plataforma
│   └── icons/          # Iconos SVG
└── PLAN.md             # Este documento
```

---

## Fases de Implementación

### Fase 1 - Base y Delegado
- Limpiar repositorio actual (eliminar archivos de Saav Rent a Car)
- Crear estructura de archivos
- Configurar Supabase: schema `electoral`, tablas, storage bucket
- Implementar autenticación de delegados
- Formulario de carga de actas con foto
- Upload de foto a Supabase Storage

### Fase 2 - Panel Operativo
- Dashboard con KPIs en tiempo real
- Gráficos de distribución de votos (Chart.js)
- Suscripción Realtime para actualizaciones en vivo
- Filtros por departamento/circunscripción/municipio/recinto
- Tabla detallada de resultados

### Fase 3 - Panel Admin
- CRUD de delegados
- Asignación de delegados a recintos
- Módulo de verificación de actas (foto vs datos)
- Gestión del catálogo electoral
- Monitoreo de actividad

### Fase 4 - Refinamiento
- Optimización móvil de la app del delegado
- Exportación de datos
- Manejo offline (Service Worker para la app del delegado)
- Alertas y notificaciones
- Pruebas de carga

---

## Consideraciones Técnicas

1. **Offline-first para delegados**: Los recintos pueden tener mala conectividad. Considerar Service Worker + IndexedDB para guardar datos localmente y sincronizar cuando haya conexión.

2. **Compresión de fotos**: Las fotos de actas pueden ser pesadas. Comprimir en el cliente antes de subir (canvas resize a ~1200px de ancho, calidad 80%).

3. **Integridad de datos**: Validación doble (cliente + RLS en Supabase) para evitar datos corruptos o duplicados.

4. **Escalabilidad**: Con ~34,000 mesas electorales en Bolivia, el sistema debe manejar miles de inserciones simultáneas. Supabase con PostgreSQL escala bien para esto.

5. **Tiempo real selectivo**: No suscribirse a TODOS los cambios. Usar filtros en las suscripciones Realtime para recibir solo datos del filtro activo.

6. **Sin framework pesado**: Mantener vanilla JS para velocidad de carga en conexiones lentas (delegados en zonas rurales).
