-- ============================================
-- QUANTIS - Seed Data para Demo/Visualizacion
-- ============================================
-- Ejecutar en Supabase SQL Editor (con permisos de service_role)
-- Prerequisito: haber ejecutado schema.sql primero
--
-- IMPORTANTE: Este script crea usuarios ficticios en auth.users
-- para poder insertar actas y votos de demostración.
-- ============================================

-- ============================================
-- 1. Crear usuarios de prueba en auth.users
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

-- ============================================
-- 2. Crear perfiles de usuario
-- ============================================

INSERT INTO usuarios (auth_user_id, nombre, telefono, rol, recinto_id) VALUES
  ('aaaa0001-0001-0001-0001-000000000001', 'Juan Daniel Flores', '+591 70000001', 'admin', NULL),
  ('aaaa0001-0001-0001-0001-000000000002', 'Carlos Mendez Rojas', '+591 70000002', 'delegado', (SELECT id FROM recintos WHERE codigo = 'R001')),
  ('aaaa0001-0001-0001-0001-000000000003', 'Maria Elena Gutierrez', '+591 70000003', 'delegado', (SELECT id FROM recintos WHERE codigo = 'R003')),
  ('aaaa0001-0001-0001-0001-000000000004', 'Roberto Suarez Paz', '+591 70000004', 'delegado', (SELECT id FROM recintos WHERE codigo = 'R007')),
  ('aaaa0001-0001-0001-0001-000000000005', 'Ana Patricia Velasco', '+591 70000005', 'delegado', (SELECT id FROM recintos WHERE codigo = 'R010')),
  ('aaaa0001-0001-0001-0001-000000000006', 'Fernando Costas Lima', '+591 70000006', 'delegado', (SELECT id FROM recintos WHERE codigo = 'R015')),
  ('aaaa0001-0001-0001-0001-000000000007', 'Lucia Roca Terrazas', '+591 70000007', 'verificador', NULL),
  ('aaaa0001-0001-0001-0001-000000000008', 'Miguel Angel Torrez', '+591 70000008', 'candidato', NULL)
ON CONFLICT (auth_user_id) DO NOTHING;

-- ============================================
-- 3. Generar actas y votos ficticios
-- ============================================
-- Genera ~45 actas (de 63 mesas totales) con datos realistas
-- UCS lidera (~32%), C-A segundo (~26%), MAS tercero (~16%)

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
  -- UCS=32%, C-A=26%, MAS=16%, SPT=9%, DEM=7%, SOL=5%, FPV=3%, MTS=2%
  v_pesos := ARRAY[0.32, 0.26, 0.16, 0.09, 0.07, 0.05, 0.03, 0.02];

  FOR v_mesa IN
    SELECT m.id, m.numero, m.total_habilitados, m.recinto_id
    FROM mesas m
    ORDER BY random()
    LIMIT 45
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

    -- Distribuir votos entre partidos con variacion por distrito
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
-- CREDENCIALES DE PRUEBA
-- ============================================
-- Admin:       admin@quantis.bo       / Quantis2026!
-- Delegado 1:  delegado1@quantis.bo   / Delegado2026!
-- Delegado 2:  delegado2@quantis.bo   / Delegado2026!
-- Delegado 3:  delegado3@quantis.bo   / Delegado2026!
-- Delegado 4:  delegado4@quantis.bo   / Delegado2026!
-- Delegado 5:  delegado5@quantis.bo   / Delegado2026!
-- Verificador: verificador@quantis.bo / Verificador2026!
-- Candidato:   candidato@quantis.bo   / Candidato2026!
