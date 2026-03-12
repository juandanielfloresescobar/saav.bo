-- ============================================
-- QUANTIS - Reset y carga de datos Warnes
-- ============================================
-- Ejecutar en Supabase SQL Editor (service_role)
-- Prerequisito: las tablas ya deben existir (schema.sql ejecutado previamente)
--
-- Este script:
-- 1. Limpia todos los datos existentes (Santa Cruz o lo que haya)
-- 2. Inserta datos del municipio de Warnes
-- 3. Crea usuarios de prueba
-- 4. Genera actas y votos ficticios
-- ============================================

-- ============================================
-- PASO 1: Limpiar datos existentes
-- ============================================

-- Orden importa por foreign keys (hijos primero, padres después)
DELETE FROM votos;
DELETE FROM actas;
DELETE FROM usuarios;
DELETE FROM mesas;
DELETE FROM recintos;
DELETE FROM distritos;
DELETE FROM partidos;

-- Limpiar usuarios de auth (solo los de demo @quantis.bo)
DELETE FROM auth.identities WHERE user_id IN (
  SELECT id FROM auth.users WHERE email LIKE '%@quantis.bo'
);
DELETE FROM auth.users WHERE email LIKE '%@quantis.bo';

-- ============================================
-- PASO 2: Distritos de Warnes (6)
-- ============================================

INSERT INTO distritos (numero, nombre) VALUES
  (1, 'Distrito 1 - Central (Warnes)'),
  (2, 'Distrito 2 - Norte (Juan Latino)'),
  (3, 'Distrito 3 - Sur (Los Chacos)'),
  (4, 'Distrito 4 - Este (Asusaquí)'),
  (5, 'Distrito 5 - Oeste (Clara Chuchío)'),
  (6, 'Distrito 6 - Industrial (Parque Industrial)');

-- ============================================
-- PASO 3: Recintos electorales (15, ~80 mesas)
-- ============================================

INSERT INTO recintos (nombre, codigo, direccion, distrito_id, total_mesas) VALUES
  ('Unidad Educativa Mariscal Sucre', 'R001', 'Av. Principal esq. C/ Bolívar, Warnes Centro', (SELECT id FROM distritos WHERE numero = 1), 6),
  ('Colegio Nacional Warnes', 'R002', 'C/ Sucre y C/ Comercio, Warnes Centro', (SELECT id FROM distritos WHERE numero = 1), 5),
  ('Unidad Educativa Ignacio Warnes', 'R003', 'Av. Cívica, B/ Central', (SELECT id FROM distritos WHERE numero = 1), 5),
  ('Colegio Juan Latino', 'R004', 'Comunidad Juan Latino, Zona Norte', (SELECT id FROM distritos WHERE numero = 2), 6),
  ('Unidad Educativa 24 de Septiembre', 'R005', 'Camino Juan Latino km 3', (SELECT id FROM distritos WHERE numero = 2), 5),
  ('Colegio República de Venezuela', 'R006', 'Zona Norte, B/ Nuevo Amanecer', (SELECT id FROM distritos WHERE numero = 2), 5),
  ('Unidad Educativa Los Chacos', 'R007', 'Comunidad Los Chacos, Zona Sur', (SELECT id FROM distritos WHERE numero = 3), 6),
  ('Colegio San Martín de Porres', 'R008', 'Camino Los Chacos km 5', (SELECT id FROM distritos WHERE numero = 3), 5),
  ('Unidad Educativa Asusaquí', 'R009', 'Comunidad Asusaquí, Zona Este', (SELECT id FROM distritos WHERE numero = 4), 6),
  ('Colegio Franz Tamayo', 'R010', 'Camino a Asusaquí km 4', (SELECT id FROM distritos WHERE numero = 4), 5),
  ('Unidad Educativa Clara Chuchío', 'R011', 'Comunidad Clara Chuchío, Zona Oeste', (SELECT id FROM distritos WHERE numero = 5), 5),
  ('Colegio Tocomechí', 'R012', 'Comunidad Tocomechí, Zona Oeste', (SELECT id FROM distritos WHERE numero = 5), 5),
  ('Unidad Educativa Parque Industrial', 'R013', 'Zona Parque Industrial Warnes', (SELECT id FROM distritos WHERE numero = 6), 6),
  ('Colegio Técnico Industrial', 'R014', 'Av. Industrial, Zona PI', (SELECT id FROM distritos WHERE numero = 6), 5),
  ('Unidad Educativa 6 de Agosto', 'R015', 'B/ 6 de Agosto, Zona Industrial', (SELECT id FROM distritos WHERE numero = 6), 5);

-- ============================================
-- PASO 4: Generar mesas para cada recinto
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
-- PASO 5: Partidos políticos (Warnes 2026)
-- ============================================

INSERT INTO partidos (nombre, sigla, color, orden) VALUES
  ('Movimiento al Socialismo - Instrumento Político por la Soberanía de los Pueblos', 'MAS-IPSP', '#0066CC', 1),
  ('Creemos', 'CREEMOS', '#059669', 2),
  ('Santa Cruz Para Todos', 'SPT', '#8B5CF6', 3),
  ('Unidad Cívica Solidaridad', 'UCS', '#FF6B00', 4),
  ('Acción Democrática Nacionalista', 'ADN', '#DC2626', 5),
  ('Movimiento Tercer Sistema', 'MTS', '#6B7280', 6),
  ('Nueva Generación Patriótica', 'NGP', '#0D9488', 7),
  ('Partido Demócrata Cristiano', 'PDC', '#EAB308', 8);

-- ============================================
-- PASO 6: Usuarios de prueba
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

-- Identities (requerido por Supabase Auth)
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
  ('aaaa0001-0001-0001-0001-000000000002', 'Carmen Rojas Suárez', '+591 70100002', 'delegado', (SELECT id FROM recintos WHERE codigo = 'R001')),
  ('aaaa0001-0001-0001-0001-000000000003', 'José Luis Mamani Quispe', '+591 70100003', 'delegado', (SELECT id FROM recintos WHERE codigo = 'R004')),
  ('aaaa0001-0001-0001-0001-000000000004', 'Paola Chávez Gutiérrez', '+591 70100004', 'delegado', (SELECT id FROM recintos WHERE codigo = 'R007')),
  ('aaaa0001-0001-0001-0001-000000000005', 'Marco Antonio Soliz', '+591 70100005', 'delegado', (SELECT id FROM recintos WHERE codigo = 'R009')),
  ('aaaa0001-0001-0001-0001-000000000006', 'Silvia Condori Vargas', '+591 70100006', 'delegado', (SELECT id FROM recintos WHERE codigo = 'R013')),
  ('aaaa0001-0001-0001-0001-000000000007', 'Edgar Fernández Roca', '+591 70100007', 'verificador', NULL),
  ('aaaa0001-0001-0001-0001-000000000008', 'Daniela Torrez Sandóval', '+591 70100008', 'candidato', NULL)
ON CONFLICT (auth_user_id) DO NOTHING;

-- ============================================
-- PASO 7: Generar actas y votos ficticios
-- ============================================
-- Genera ~55 actas (de 80 mesas totales) con datos realistas
-- MAS lidera (~25%), Creemos segundo (~20%), SPT tercero (~18%)

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
  v_peso_total FLOAT;
BEGIN
  -- Obtener delegados
  SELECT array_agg(id) INTO v_delegados
  FROM usuarios WHERE rol = 'delegado';

  IF v_delegados IS NULL THEN
    RAISE NOTICE 'No hay delegados registrados, abortando seed de actas';
    RETURN;
  END IF;

  -- Base time: hoy a las 08:00
  v_base_time := date_trunc('day', now()) + interval '8 hours';

  -- Pesos de distribucion por partido (orden = 1..8)
  -- MAS=25%, CREEMOS=20%, SPT=18%, UCS=12%, ADN=10%, MTS=7%, NGP=5%, PDC=3%
  v_pesos := ARRAY[0.25, 0.20, 0.18, 0.12, 0.10, 0.07, 0.05, 0.03];

  FOR v_mesa IN
    SELECT m.id, m.numero, m.total_habilitados, m.recinto_id
    FROM mesas m
    ORDER BY random()
    LIMIT 55
  LOOP
    v_mesa_count := v_mesa_count + 1;

    -- Delegado aleatorio
    v_delegado_idx := 1 + floor(random() * array_length(v_delegados, 1))::int;
    IF v_delegado_idx > array_length(v_delegados, 1) THEN
      v_delegado_idx := 1;
    END IF;

    -- Total votantes (65-90% de habilitados)
    v_total_votantes := floor(v_mesa.total_habilitados * (0.65 + random() * 0.25))::int;

    -- Nulos y blancos
    v_votos_nulos := floor(v_total_votantes * (0.01 + random() * 0.03))::int;
    v_votos_blancos := floor(v_total_votantes * (0.005 + random() * 0.02))::int;
    v_remaining := v_total_votantes - v_votos_nulos - v_votos_blancos;

    -- Estado: 70% verificadas, 15% pendientes, 10% observadas, 5% rechazadas
    IF random() < 0.70 THEN
      v_estado := 'verificada';
    ELSIF random() < 0.85 THEN
      v_estado := 'pendiente';
    ELSIF random() < 0.95 THEN
      v_estado := 'observada';
    ELSE
      v_estado := 'rechazada';
    END IF;

    -- Timestamp progresivo
    v_acta_time := v_base_time + (v_mesa_count * interval '8 minutes') + (random() * interval '5 minutes');

    -- Insertar acta
    INSERT INTO actas (mesa_id, delegado_id, total_votantes, votos_nulos, votos_blancos, estado, created_at, updated_at)
    VALUES (v_mesa.id, v_delegados[v_delegado_idx], v_total_votantes, v_votos_nulos, v_votos_blancos, v_estado, v_acta_time, v_acta_time)
    RETURNING id INTO v_acta_id;

    -- Distribuir votos entre partidos con variacion
    v_votos_asignados := 0;
    v_peso_total := 0;
    FOR i IN 1..array_length(v_pesos, 1) LOOP
      v_peso_total := v_peso_total + v_pesos[i];
    END LOOP;

    FOR v_partido IN
      SELECT id, orden FROM partidos ORDER BY orden
    LOOP
      IF v_partido.orden = 8 THEN
        -- Ultimo partido: asignar lo que queda
        v_votos_partido := v_remaining - v_votos_asignados;
      ELSE
        -- Peso base + variacion aleatoria (+/- 30%)
        v_votos_partido := floor(
          v_remaining * v_pesos[v_partido.orden] * (0.7 + random() * 0.6)
        )::int;
        -- Asegurar no negativo
        IF v_votos_partido < 0 THEN v_votos_partido := 0; END IF;
        -- No exceder lo que queda
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

  RAISE NOTICE 'Seed completado: % actas creadas con votos', v_mesa_count;
END $$;

-- ============================================
-- LISTO! Credenciales de prueba:
-- ============================================
-- Admin:       admin@quantis.bo       / Quantis2026!
-- Delegado 1:  delegado1@quantis.bo   / Delegado2026!
-- Delegado 2:  delegado2@quantis.bo   / Delegado2026!
-- Delegado 3:  delegado3@quantis.bo   / Delegado2026!
-- Delegado 4:  delegado4@quantis.bo   / Delegado2026!
-- Delegado 5:  delegado5@quantis.bo   / Delegado2026!
-- Verificador: verificador@quantis.bo / Verificador2026!
-- Candidato:   candidato@quantis.bo   / Candidato2026!
