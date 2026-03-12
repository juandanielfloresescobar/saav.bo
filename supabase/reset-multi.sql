-- ============================================
-- QUANTIS - Reset y carga multi-municipio
-- ============================================
-- Ejecutar en Supabase SQL Editor (service_role)
-- Prerequisito: las tablas ya deben existir (schema.sql ejecutado previamente)
--
-- Este script:
-- 1. Limpia todos los datos existentes
-- 2. Crea tabla municipios y altera distritos
-- 3. Inserta datos de Warnes Y Santa Cruz de la Sierra
-- 4. Crea usuarios de prueba
-- 5. Genera actas y votos ficticios para ambos municipios
-- ============================================

-- ============================================
-- PASO 1: Limpiar datos existentes
-- ============================================

DELETE FROM votos;
DELETE FROM actas;
DELETE FROM usuarios;
DELETE FROM mesas;
DELETE FROM recintos;
DELETE FROM distritos;
DELETE FROM partidos;

-- Limpiar usuarios de auth
DELETE FROM auth.identities WHERE user_id IN (
  SELECT id FROM auth.users WHERE email LIKE '%@quantis.bo'
);
DELETE FROM auth.users WHERE email LIKE '%@quantis.bo';

-- ============================================
-- PASO 2: Crear tabla municipios (si no existe)
-- ============================================

CREATE TABLE IF NOT EXISTS municipios (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  nombre TEXT NOT NULL,
  codigo TEXT UNIQUE NOT NULL,
  departamento TEXT NOT NULL DEFAULT 'Santa Cruz',
  latitud FLOAT NOT NULL,
  longitud FLOAT NOT NULL,
  zoom_level INTEGER NOT NULL DEFAULT 12
);

-- RLS para municipios
ALTER TABLE municipios ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "read_municipios" ON municipios;
CREATE POLICY "read_municipios" ON municipios FOR SELECT TO authenticated USING (true);

-- Limpiar municipios existentes
DELETE FROM municipios;

-- Agregar columna municipio_id a distritos si no existe
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'distritos' AND column_name = 'municipio_id'
  ) THEN
    ALTER TABLE distritos ADD COLUMN municipio_id UUID REFERENCES municipios(id);
  END IF;
END $$;

-- Eliminar constraint UNIQUE solo en numero (si existe), reemplazar por (municipio_id, numero)
DO $$
BEGIN
  -- Drop the old unique constraint on just numero
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'distritos_numero_key'
  ) THEN
    ALTER TABLE distritos DROP CONSTRAINT distritos_numero_key;
  END IF;

  -- Create composite unique if not exists
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'distritos_municipio_numero_unique'
  ) THEN
    ALTER TABLE distritos ADD CONSTRAINT distritos_municipio_numero_unique UNIQUE(municipio_id, numero);
  END IF;
END $$;

-- Indice para buscar distritos por municipio
CREATE INDEX IF NOT EXISTS idx_distritos_municipio ON distritos(municipio_id);

-- ============================================
-- PASO 3: Insertar municipios
-- ============================================

INSERT INTO municipios (nombre, codigo, departamento, latitud, longitud, zoom_level) VALUES
  ('Warnes', 'WAR', 'Santa Cruz', -17.5103, -63.1647, 13),
  ('Santa Cruz de la Sierra', 'SCZ', 'Santa Cruz', -17.7833, -63.1822, 12);

-- ============================================
-- PASO 4: Distritos
-- ============================================

-- Warnes: 6 distritos
INSERT INTO distritos (numero, nombre, municipio_id) VALUES
  (1, 'Distrito 1 - Central (Warnes)', (SELECT id FROM municipios WHERE codigo = 'WAR')),
  (2, 'Distrito 2 - Norte (Juan Latino)', (SELECT id FROM municipios WHERE codigo = 'WAR')),
  (3, 'Distrito 3 - Sur (Los Chacos)', (SELECT id FROM municipios WHERE codigo = 'WAR')),
  (4, 'Distrito 4 - Este (Asusaquí)', (SELECT id FROM municipios WHERE codigo = 'WAR')),
  (5, 'Distrito 5 - Oeste (Clara Chuchío)', (SELECT id FROM municipios WHERE codigo = 'WAR')),
  (6, 'Distrito 6 - Industrial (Parque Industrial)', (SELECT id FROM municipios WHERE codigo = 'WAR'));

-- Santa Cruz: 15 distritos
INSERT INTO distritos (numero, nombre, municipio_id) VALUES
  (1, 'Distrito 1 - Casco Viejo', (SELECT id FROM municipios WHERE codigo = 'SCZ')),
  (2, 'Distrito 2 - Norte (Villa 1ro de Mayo)', (SELECT id FROM municipios WHERE codigo = 'SCZ')),
  (3, 'Distrito 3 - Noreste (Pampa de la Isla)', (SELECT id FROM municipios WHERE codigo = 'SCZ')),
  (4, 'Distrito 4 - Este (Plan 3000)', (SELECT id FROM municipios WHERE codigo = 'SCZ')),
  (5, 'Distrito 5 - Sureste (Los Lotes)', (SELECT id FROM municipios WHERE codigo = 'SCZ')),
  (6, 'Distrito 6 - Sur (El Bajío)', (SELECT id FROM municipios WHERE codigo = 'SCZ')),
  (7, 'Distrito 7 - Suroeste (UV Satelite)', (SELECT id FROM municipios WHERE codigo = 'SCZ')),
  (8, 'Distrito 8 - Oeste (Equipetrol)', (SELECT id FROM municipios WHERE codigo = 'SCZ')),
  (9, 'Distrito 9 - Noroeste (Urbarí)', (SELECT id FROM municipios WHERE codigo = 'SCZ')),
  (10, 'Distrito 10 - Norte Periurbano', (SELECT id FROM municipios WHERE codigo = 'SCZ')),
  (11, 'Distrito 11 - Este Periurbano', (SELECT id FROM municipios WHERE codigo = 'SCZ')),
  (12, 'Distrito 12 - Sur Periurbano', (SELECT id FROM municipios WHERE codigo = 'SCZ')),
  (13, 'Distrito 13 - Paurito', (SELECT id FROM municipios WHERE codigo = 'SCZ')),
  (14, 'Distrito 14 - Montero Hoyos', (SELECT id FROM municipios WHERE codigo = 'SCZ')),
  (15, 'Distrito 15 - El Palmar del Oratorio', (SELECT id FROM municipios WHERE codigo = 'SCZ'));

-- ============================================
-- PASO 5: Recintos electorales
-- ============================================

-- Warnes: 15 recintos, ~80 mesas
INSERT INTO recintos (nombre, codigo, direccion, distrito_id, total_mesas) VALUES
  ('Unidad Educativa Mariscal Sucre', 'W-R001', 'Av. Principal esq. C/ Bolívar, Warnes Centro',
    (SELECT id FROM distritos WHERE numero = 1 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'WAR')), 6),
  ('Colegio Nacional Warnes', 'W-R002', 'C/ Sucre y C/ Comercio, Warnes Centro',
    (SELECT id FROM distritos WHERE numero = 1 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'WAR')), 5),
  ('Unidad Educativa Ignacio Warnes', 'W-R003', 'Av. Cívica, B/ Central',
    (SELECT id FROM distritos WHERE numero = 1 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'WAR')), 5),
  ('Colegio Juan Latino', 'W-R004', 'Comunidad Juan Latino, Zona Norte',
    (SELECT id FROM distritos WHERE numero = 2 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'WAR')), 6),
  ('Unidad Educativa 24 de Septiembre', 'W-R005', 'Camino Juan Latino km 3',
    (SELECT id FROM distritos WHERE numero = 2 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'WAR')), 5),
  ('Colegio República de Venezuela', 'W-R006', 'Zona Norte, B/ Nuevo Amanecer',
    (SELECT id FROM distritos WHERE numero = 2 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'WAR')), 5),
  ('Unidad Educativa Los Chacos', 'W-R007', 'Comunidad Los Chacos, Zona Sur',
    (SELECT id FROM distritos WHERE numero = 3 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'WAR')), 6),
  ('Colegio San Martín de Porres', 'W-R008', 'Camino Los Chacos km 5',
    (SELECT id FROM distritos WHERE numero = 3 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'WAR')), 5),
  ('Unidad Educativa Asusaquí', 'W-R009', 'Comunidad Asusaquí, Zona Este',
    (SELECT id FROM distritos WHERE numero = 4 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'WAR')), 6),
  ('Colegio Franz Tamayo', 'W-R010', 'Camino a Asusaquí km 4',
    (SELECT id FROM distritos WHERE numero = 4 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'WAR')), 5),
  ('Unidad Educativa Clara Chuchío', 'W-R011', 'Comunidad Clara Chuchío, Zona Oeste',
    (SELECT id FROM distritos WHERE numero = 5 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'WAR')), 5),
  ('Colegio Tocomechí', 'W-R012', 'Comunidad Tocomechí, Zona Oeste',
    (SELECT id FROM distritos WHERE numero = 5 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'WAR')), 5),
  ('Unidad Educativa Parque Industrial', 'W-R013', 'Zona Parque Industrial Warnes',
    (SELECT id FROM distritos WHERE numero = 6 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'WAR')), 6),
  ('Colegio Técnico Industrial', 'W-R014', 'Av. Industrial, Zona PI',
    (SELECT id FROM distritos WHERE numero = 6 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'WAR')), 5),
  ('Unidad Educativa 6 de Agosto', 'W-R015', 'B/ 6 de Agosto, Zona Industrial',
    (SELECT id FROM distritos WHERE numero = 6 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'WAR')), 5);

-- Santa Cruz: 20 recintos, ~63 mesas
INSERT INTO recintos (nombre, codigo, direccion, distrito_id, total_mesas) VALUES
  ('Colegio Nacional Florida', 'SC-R001', 'C/ Junín esq. Ayacucho, Casco Viejo',
    (SELECT id FROM distritos WHERE numero = 1 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'SCZ')), 4),
  ('Unidad Educativa Germán Busch', 'SC-R002', 'Av. Cañoto, 2do Anillo Norte',
    (SELECT id FROM distritos WHERE numero = 2 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'SCZ')), 4),
  ('Colegio Pampa de la Isla', 'SC-R003', 'Av. Santos Dumont, 3er Anillo',
    (SELECT id FROM distritos WHERE numero = 3 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'SCZ')), 3),
  ('Unidad Educativa Plan 3000', 'SC-R004', 'Av. Virgen de Cotoca, Plan 3000',
    (SELECT id FROM distritos WHERE numero = 4 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'SCZ')), 4),
  ('Colegio Los Lotes', 'SC-R005', 'Av. Radial 26, 7mo Anillo',
    (SELECT id FROM distritos WHERE numero = 5 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'SCZ')), 3),
  ('Unidad Educativa El Bajío', 'SC-R006', 'Camino al Sur km 6',
    (SELECT id FROM distritos WHERE numero = 6 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'SCZ')), 3),
  ('Colegio UV Satélite Norte', 'SC-R007', 'Av. Banzer, 5to Anillo',
    (SELECT id FROM distritos WHERE numero = 7 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'SCZ')), 3),
  ('Unidad Educativa Equipetrol', 'SC-R008', 'Av. San Martín, Equipetrol',
    (SELECT id FROM distritos WHERE numero = 8 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'SCZ')), 4),
  ('Colegio Urbarí', 'SC-R009', 'Av. Bush, 2do Anillo Oeste',
    (SELECT id FROM distritos WHERE numero = 9 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'SCZ')), 3),
  ('Unidad Educativa Cristo Rey', 'SC-R010', 'Av. Pirai, 4to Anillo Norte',
    (SELECT id FROM distritos WHERE numero = 10 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'SCZ')), 3),
  ('Colegio Nacional Warnes SCZ', 'SC-R011', 'Av. Warnes, Villa 1ro de Mayo',
    (SELECT id FROM distritos WHERE numero = 2 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'SCZ')), 3),
  ('Unidad Educativa La Cuchilla', 'SC-R012', 'Av. Radial 13, 6to Anillo',
    (SELECT id FROM distritos WHERE numero = 4 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'SCZ')), 3),
  ('Colegio San Aurelio', 'SC-R013', 'Av. Mutualista, 3er Anillo',
    (SELECT id FROM distritos WHERE numero = 1 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'SCZ')), 3),
  ('Unidad Educativa Hamacas', 'SC-R014', 'UV Hamacas, 8vo Anillo Sur',
    (SELECT id FROM distritos WHERE numero = 11 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'SCZ')), 3),
  ('Colegio Técnico Montero Hoyos', 'SC-R015', 'Comunidad Montero Hoyos',
    (SELECT id FROM distritos WHERE numero = 14 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'SCZ')), 3),
  ('Unidad Educativa Palmar', 'SC-R016', 'Comunidad El Palmar del Oratorio',
    (SELECT id FROM distritos WHERE numero = 15 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'SCZ')), 3),
  ('Colegio Paurito', 'SC-R017', 'Comunidad Paurito',
    (SELECT id FROM distritos WHERE numero = 13 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'SCZ')), 3),
  ('Unidad Educativa Sur Periurbano', 'SC-R018', 'Km 12 Doble vía La Guardia',
    (SELECT id FROM distritos WHERE numero = 12 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'SCZ')), 3),
  ('Colegio 6 de Agosto SCZ', 'SC-R019', 'B/ 6 de Agosto, 4to Anillo',
    (SELECT id FROM distritos WHERE numero = 6 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'SCZ')), 3),
  ('Unidad Educativa Sirari', 'SC-R020', 'UV Sirari, 5to Anillo',
    (SELECT id FROM distritos WHERE numero = 8 AND municipio_id = (SELECT id FROM municipios WHERE codigo = 'SCZ')), 3);

-- ============================================
-- PASO 6: Generar mesas para cada recinto
-- ============================================

DO $$
DECLARE
  r RECORD;
  i INTEGER;
BEGIN
  FOR r IN SELECT id, total_mesas FROM recintos LOOP
    FOR i IN 1..r.total_mesas LOOP
      INSERT INTO mesas (numero, recinto_id, total_habilitados)
      VALUES (i, r.id, 250 + floor(random() * 50)::int);
    END LOOP;
  END LOOP;
END $$;

-- ============================================
-- PASO 7: Partidos políticos
-- ============================================
-- Compartidos + locales para variedad

INSERT INTO partidos (nombre, sigla, color, orden) VALUES
  ('Movimiento al Socialismo - Instrumento Político por la Soberanía de los Pueblos', 'MAS-IPSP', '#0066CC', 1),
  ('Creemos', 'CREEMOS', '#059669', 2),
  ('Santa Cruz Para Todos', 'SPT', '#8B5CF6', 3),
  ('Unidad Cívica Solidaridad', 'UCS', '#FF6B00', 4),
  ('Acción Democrática Nacionalista', 'ADN', '#DC2626', 5),
  ('Movimiento Tercer Sistema', 'MTS', '#6B7280', 6),
  ('Comunidad Autonomista', 'C-A', '#0D9488', 7),
  ('Demócratas', 'DEM', '#EAB308', 8);

-- ============================================
-- PASO 8: Usuarios de prueba
-- ============================================

INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, recovery_token
) VALUES
  ('00000000-0000-0000-0000-000000000000', 'aaaa0001-0001-0001-0001-000000000001', 'authenticated', 'authenticated',
   'admin@quantis.bo', crypt('Quantis2026!', gen_salt('bf')),
   now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', ''),
  ('00000000-0000-0000-0000-000000000000', 'aaaa0001-0001-0001-0001-000000000002', 'authenticated', 'authenticated',
   'delegado1@quantis.bo', crypt('Delegado2026!', gen_salt('bf')),
   now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', ''),
  ('00000000-0000-0000-0000-000000000000', 'aaaa0001-0001-0001-0001-000000000003', 'authenticated', 'authenticated',
   'delegado2@quantis.bo', crypt('Delegado2026!', gen_salt('bf')),
   now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', ''),
  ('00000000-0000-0000-0000-000000000000', 'aaaa0001-0001-0001-0001-000000000004', 'authenticated', 'authenticated',
   'delegado3@quantis.bo', crypt('Delegado2026!', gen_salt('bf')),
   now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', ''),
  ('00000000-0000-0000-0000-000000000000', 'aaaa0001-0001-0001-0001-000000000005', 'authenticated', 'authenticated',
   'delegado4@quantis.bo', crypt('Delegado2026!', gen_salt('bf')),
   now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', ''),
  ('00000000-0000-0000-0000-000000000000', 'aaaa0001-0001-0001-0001-000000000006', 'authenticated', 'authenticated',
   'delegado5@quantis.bo', crypt('Delegado2026!', gen_salt('bf')),
   now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', ''),
  ('00000000-0000-0000-0000-000000000000', 'aaaa0001-0001-0001-0001-000000000007', 'authenticated', 'authenticated',
   'verificador@quantis.bo', crypt('Verificador2026!', gen_salt('bf')),
   now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', ''),
  ('00000000-0000-0000-0000-000000000000', 'aaaa0001-0001-0001-0001-000000000008', 'authenticated', 'authenticated',
   'candidato@quantis.bo', crypt('Candidato2026!', gen_salt('bf')),
   now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '')
ON CONFLICT (id) DO NOTHING;

-- Identities
INSERT INTO auth.identities (id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at)
SELECT
  u.id, u.id,
  json_build_object('sub', u.id::text, 'email', u.email),
  'email', u.id::text, now(), now(), now()
FROM auth.users u
WHERE u.email LIKE '%@quantis.bo'
ON CONFLICT DO NOTHING;

-- Perfiles de usuario
INSERT INTO usuarios (auth_user_id, nombre, telefono, rol, recinto_id) VALUES
  ('aaaa0001-0001-0001-0001-000000000001', 'Ricardo Montaño Peña', '+591 70100001', 'admin', NULL),
  ('aaaa0001-0001-0001-0001-000000000002', 'Carmen Rojas Suárez', '+591 70100002', 'delegado', (SELECT id FROM recintos WHERE codigo = 'W-R001')),
  ('aaaa0001-0001-0001-0001-000000000003', 'José Luis Mamani Quispe', '+591 70100003', 'delegado', (SELECT id FROM recintos WHERE codigo = 'W-R004')),
  ('aaaa0001-0001-0001-0001-000000000004', 'Paola Chávez Gutiérrez', '+591 70100004', 'delegado', (SELECT id FROM recintos WHERE codigo = 'SC-R001')),
  ('aaaa0001-0001-0001-0001-000000000005', 'Marco Antonio Soliz', '+591 70100005', 'delegado', (SELECT id FROM recintos WHERE codigo = 'SC-R004')),
  ('aaaa0001-0001-0001-0001-000000000006', 'Silvia Condori Vargas', '+591 70100006', 'delegado', (SELECT id FROM recintos WHERE codigo = 'SC-R008')),
  ('aaaa0001-0001-0001-0001-000000000007', 'Edgar Fernández Roca', '+591 70100007', 'verificador', NULL),
  ('aaaa0001-0001-0001-0001-000000000008', 'Daniela Torrez Sandóval', '+591 70100008', 'candidato', NULL)
ON CONFLICT (auth_user_id) DO NOTHING;

-- ============================================
-- PASO 9: Generar actas y votos ficticios
-- ============================================
-- Warnes: ~55 actas (MAS lidera 25%)
-- Santa Cruz: ~45 actas (UCS lidera 28%)

DO $$
DECLARE
  v_mesa RECORD;
  v_acta_id UUID;
  v_partido RECORD;
  v_delegados UUID[];
  v_delegado_idx INT;
  v_total_votantes INT;
  v_votos_asignados INT;
  v_votos_partido INT;
  v_votos_nulos INT;
  v_votos_blancos INT;
  v_remaining INT;
  v_base_time TIMESTAMPTZ;
  v_acta_time TIMESTAMPTZ;
  v_mesa_count INT := 0;
  v_estado TEXT;
  v_pesos FLOAT[];
  v_municipio_codigo TEXT;
BEGIN
  -- Obtener delegados
  SELECT array_agg(id) INTO v_delegados
  FROM usuarios WHERE rol = 'delegado';

  IF v_delegados IS NULL THEN
    RAISE NOTICE 'No hay delegados registrados, abortando seed de actas';
    RETURN;
  END IF;

  v_base_time := date_trunc('day', now()) + interval '8 hours';

  -- ========== WARNES ==========
  v_pesos := ARRAY[0.25, 0.20, 0.18, 0.12, 0.10, 0.07, 0.05, 0.03];
  v_mesa_count := 0;

  FOR v_mesa IN
    SELECT m.id, m.numero, m.total_habilitados, m.recinto_id
    FROM mesas m
    JOIN recintos r ON m.recinto_id = r.id
    JOIN distritos d ON r.distrito_id = d.id
    JOIN municipios mu ON d.municipio_id = mu.id
    WHERE mu.codigo = 'WAR'
    ORDER BY random()
    LIMIT 55
  LOOP
    v_mesa_count := v_mesa_count + 1;
    v_delegado_idx := 1 + floor(random() * array_length(v_delegados, 1))::int;
    IF v_delegado_idx > array_length(v_delegados, 1) THEN v_delegado_idx := 1; END IF;

    v_total_votantes := floor(v_mesa.total_habilitados * (0.65 + random() * 0.25))::int;
    v_votos_nulos := floor(v_total_votantes * (0.01 + random() * 0.03))::int;
    v_votos_blancos := floor(v_total_votantes * (0.005 + random() * 0.02))::int;
    v_remaining := v_total_votantes - v_votos_nulos - v_votos_blancos;

    IF random() < 0.70 THEN v_estado := 'verificada';
    ELSIF random() < 0.85 THEN v_estado := 'pendiente';
    ELSIF random() < 0.95 THEN v_estado := 'observada';
    ELSE v_estado := 'rechazada'; END IF;

    v_acta_time := v_base_time + (v_mesa_count * interval '8 minutes') + (random() * interval '5 minutes');

    INSERT INTO actas (mesa_id, delegado_id, total_votantes, votos_nulos, votos_blancos, estado, created_at, updated_at)
    VALUES (v_mesa.id, v_delegados[v_delegado_idx], v_total_votantes, v_votos_nulos, v_votos_blancos, v_estado, v_acta_time, v_acta_time)
    RETURNING id INTO v_acta_id;

    v_votos_asignados := 0;
    FOR v_partido IN SELECT id, orden FROM partidos ORDER BY orden LOOP
      IF v_partido.orden = 8 THEN
        v_votos_partido := v_remaining - v_votos_asignados;
      ELSE
        v_votos_partido := floor(v_remaining * v_pesos[v_partido.orden] * (0.7 + random() * 0.6))::int;
        IF v_votos_partido < 0 THEN v_votos_partido := 0; END IF;
        IF v_votos_asignados + v_votos_partido > v_remaining THEN
          v_votos_partido := v_remaining - v_votos_asignados;
        END IF;
      END IF;
      IF v_votos_partido < 0 THEN v_votos_partido := 0; END IF;

      INSERT INTO votos (acta_id, partido_id, cantidad)
      VALUES (v_acta_id, v_partido.id, v_votos_partido);
      v_votos_asignados := v_votos_asignados + v_votos_partido;
    END LOOP;
  END LOOP;

  RAISE NOTICE 'Warnes: % actas creadas', v_mesa_count;

  -- ========== SANTA CRUZ ==========
  -- UCS lidera (28%), SPT segundo (22%), MAS tercero (18%)
  v_pesos := ARRAY[0.18, 0.10, 0.22, 0.28, 0.08, 0.05, 0.05, 0.04];
  v_mesa_count := 0;

  FOR v_mesa IN
    SELECT m.id, m.numero, m.total_habilitados, m.recinto_id
    FROM mesas m
    JOIN recintos r ON m.recinto_id = r.id
    JOIN distritos d ON r.distrito_id = d.id
    JOIN municipios mu ON d.municipio_id = mu.id
    WHERE mu.codigo = 'SCZ'
    ORDER BY random()
    LIMIT 45
  LOOP
    v_mesa_count := v_mesa_count + 1;
    v_delegado_idx := 1 + floor(random() * array_length(v_delegados, 1))::int;
    IF v_delegado_idx > array_length(v_delegados, 1) THEN v_delegado_idx := 1; END IF;

    v_total_votantes := floor(v_mesa.total_habilitados * (0.65 + random() * 0.25))::int;
    v_votos_nulos := floor(v_total_votantes * (0.01 + random() * 0.03))::int;
    v_votos_blancos := floor(v_total_votantes * (0.005 + random() * 0.02))::int;
    v_remaining := v_total_votantes - v_votos_nulos - v_votos_blancos;

    IF random() < 0.65 THEN v_estado := 'verificada';
    ELSIF random() < 0.82 THEN v_estado := 'pendiente';
    ELSIF random() < 0.94 THEN v_estado := 'observada';
    ELSE v_estado := 'rechazada'; END IF;

    v_acta_time := v_base_time + (v_mesa_count * interval '7 minutes') + (random() * interval '4 minutes');

    INSERT INTO actas (mesa_id, delegado_id, total_votantes, votos_nulos, votos_blancos, estado, created_at, updated_at)
    VALUES (v_mesa.id, v_delegados[v_delegado_idx], v_total_votantes, v_votos_nulos, v_votos_blancos, v_estado, v_acta_time, v_acta_time)
    RETURNING id INTO v_acta_id;

    v_votos_asignados := 0;
    FOR v_partido IN SELECT id, orden FROM partidos ORDER BY orden LOOP
      IF v_partido.orden = 8 THEN
        v_votos_partido := v_remaining - v_votos_asignados;
      ELSE
        v_votos_partido := floor(v_remaining * v_pesos[v_partido.orden] * (0.7 + random() * 0.6))::int;
        IF v_votos_partido < 0 THEN v_votos_partido := 0; END IF;
        IF v_votos_asignados + v_votos_partido > v_remaining THEN
          v_votos_partido := v_remaining - v_votos_asignados;
        END IF;
      END IF;
      IF v_votos_partido < 0 THEN v_votos_partido := 0; END IF;

      INSERT INTO votos (acta_id, partido_id, cantidad)
      VALUES (v_acta_id, v_partido.id, v_votos_partido);
      v_votos_asignados := v_votos_asignados + v_votos_partido;
    END LOOP;
  END LOOP;

  RAISE NOTICE 'Santa Cruz: % actas creadas', v_mesa_count;
END $$;

-- ============================================
-- PASO 10: Forzar recarga del schema en PostgREST
-- ============================================
-- Esto es necesario para que la API REST reconozca
-- la nueva tabla municipios y la columna municipio_id
NOTIFY pgrst, 'reload schema';

-- Seed completado. Ver credenciales en seed-demo.sql
