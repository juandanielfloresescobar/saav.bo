-- ============================================
-- QUANTIS - Sistema de Control Electoral
-- Schema SQL para Supabase
-- ============================================

-- ============================================
-- CATÁLOGO ELECTORAL
-- ============================================

CREATE TABLE distritos (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  numero INTEGER NOT NULL UNIQUE,
  nombre TEXT NOT NULL
);

CREATE TABLE recintos (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  nombre TEXT NOT NULL,
  codigo TEXT UNIQUE,
  direccion TEXT,
  distrito_id UUID NOT NULL REFERENCES distritos(id),
  total_mesas INTEGER DEFAULT 0
);

CREATE TABLE mesas (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  numero INTEGER NOT NULL,
  recinto_id UUID NOT NULL REFERENCES recintos(id),
  total_habilitados INTEGER DEFAULT 300,
  UNIQUE(recinto_id, numero)
);

-- ============================================
-- PARTIDOS
-- ============================================

CREATE TABLE partidos (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  nombre TEXT NOT NULL,
  sigla TEXT NOT NULL UNIQUE,
  color TEXT NOT NULL,
  logo_url TEXT,
  orden INTEGER NOT NULL
);

-- ============================================
-- USUARIOS
-- ============================================

CREATE TABLE usuarios (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  auth_user_id UUID UNIQUE NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  nombre TEXT NOT NULL,
  telefono TEXT,
  rol TEXT NOT NULL CHECK (rol IN ('delegado', 'verificador', 'candidato', 'admin')),
  recinto_id UUID REFERENCES recintos(id),
  activo BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================
-- ACTAS Y VOTOS
-- ============================================

CREATE TABLE actas (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  mesa_id UUID NOT NULL REFERENCES mesas(id) UNIQUE,
  delegado_id UUID NOT NULL REFERENCES usuarios(id),
  foto_url TEXT,
  total_votantes INTEGER NOT NULL,
  votos_nulos INTEGER NOT NULL DEFAULT 0,
  votos_blancos INTEGER NOT NULL DEFAULT 0,
  estado TEXT NOT NULL DEFAULT 'pendiente'
    CHECK (estado IN ('pendiente', 'verificada', 'observada', 'rechazada')),
  verificado_por UUID REFERENCES usuarios(id),
  observaciones TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE votos (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  acta_id UUID NOT NULL REFERENCES actas(id) ON DELETE CASCADE,
  partido_id UUID NOT NULL REFERENCES partidos(id),
  cantidad INTEGER NOT NULL CHECK (cantidad >= 0),
  UNIQUE(acta_id, partido_id)
);

-- ============================================
-- ÍNDICES
-- ============================================

CREATE INDEX idx_recintos_distrito ON recintos(distrito_id);
CREATE INDEX idx_mesas_recinto ON mesas(recinto_id);
CREATE INDEX idx_usuarios_auth ON usuarios(auth_user_id);
CREATE INDEX idx_usuarios_recinto ON usuarios(recinto_id);
CREATE INDEX idx_actas_mesa ON actas(mesa_id);
CREATE INDEX idx_actas_delegado ON actas(delegado_id);
CREATE INDEX idx_actas_estado ON actas(estado);
CREATE INDEX idx_votos_acta ON votos(acta_id);
CREATE INDEX idx_votos_partido ON votos(partido_id);

-- ============================================
-- FUNCIONES HELPER PARA RLS
-- ============================================

CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS TEXT LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = '' AS $$
  SELECT rol FROM public.usuarios
  WHERE auth_user_id = (SELECT auth.uid())
$$;

CREATE OR REPLACE FUNCTION public.get_user_recinto_id()
RETURNS UUID LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = '' AS $$
  SELECT recinto_id FROM public.usuarios
  WHERE auth_user_id = (SELECT auth.uid())
$$;

CREATE OR REPLACE FUNCTION public.get_user_id()
RETURNS UUID LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = '' AS $$
  SELECT id FROM public.usuarios
  WHERE auth_user_id = (SELECT auth.uid())
$$;

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================

-- Distritos: lectura pública para autenticados
ALTER TABLE distritos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "read_distritos" ON distritos FOR SELECT TO authenticated USING (true);

-- Recintos: lectura pública para autenticados
ALTER TABLE recintos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "read_recintos" ON recintos FOR SELECT TO authenticated USING (true);

-- Mesas: lectura pública para autenticados
ALTER TABLE mesas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "read_mesas" ON mesas FOR SELECT TO authenticated USING (true);

-- Partidos: lectura pública para autenticados
ALTER TABLE partidos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "read_partidos" ON partidos FOR SELECT TO authenticated USING (true);

-- Usuarios: cada quien ve su propio perfil, admin ve todos
ALTER TABLE usuarios ENABLE ROW LEVEL SECURITY;
CREATE POLICY "read_own_profile" ON usuarios FOR SELECT TO authenticated
  USING (auth_user_id = (SELECT auth.uid()) OR (SELECT public.get_user_role()) IN ('admin', 'verificador'));
CREATE POLICY "admin_manage_usuarios" ON usuarios FOR ALL TO authenticated
  USING ((SELECT public.get_user_role()) = 'admin')
  WITH CHECK ((SELECT public.get_user_role()) = 'admin');

-- Actas: delegados insertan las suyas, verificadores/admin actualizan estado
ALTER TABLE actas ENABLE ROW LEVEL SECURITY;

CREATE POLICY "delegado_insert_acta" ON actas FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT public.get_user_role()) = 'delegado'
    AND delegado_id = (SELECT public.get_user_id())
    AND mesa_id IN (
      SELECT m.id FROM mesas m WHERE m.recinto_id = (SELECT public.get_user_recinto_id())
    )
  );

CREATE POLICY "delegado_read_own_actas" ON actas FOR SELECT TO authenticated
  USING (
    delegado_id = (SELECT public.get_user_id())
    OR (SELECT public.get_user_role()) IN ('verificador', 'candidato', 'admin')
  );

CREATE POLICY "staff_update_acta" ON actas FOR UPDATE TO authenticated
  USING ((SELECT public.get_user_role()) IN ('verificador', 'admin'))
  WITH CHECK ((SELECT public.get_user_role()) IN ('verificador', 'admin'));

-- Votos: delegados insertan junto con su acta, todos los staff leen
ALTER TABLE votos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "delegado_insert_votos" ON votos FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT public.get_user_role()) = 'delegado'
    AND acta_id IN (
      SELECT a.id FROM actas a WHERE a.delegado_id = (SELECT public.get_user_id())
    )
  );

CREATE POLICY "read_votos" ON votos FOR SELECT TO authenticated
  USING (
    acta_id IN (SELECT a.id FROM actas a WHERE a.delegado_id = (SELECT public.get_user_id()))
    OR (SELECT public.get_user_role()) IN ('verificador', 'candidato', 'admin')
  );

-- ============================================
-- STORAGE BUCKET
-- ============================================
-- Ejecutar en Supabase Dashboard > Storage:
-- 1. Crear bucket "actas-fotos" (público: false)
-- 2. Políticas:
--    - INSERT: authenticated, bucket_id = 'actas-fotos', (storage.foldername(name))[1] = auth.uid()::text
--    - SELECT: authenticated (todos los roles pueden ver fotos)

-- ============================================
-- HABILITAR REALTIME
-- ============================================
-- En Supabase Dashboard > Database > Publications:
-- Agregar tablas 'actas' y 'votos' a la publicación supabase_realtime

ALTER PUBLICATION supabase_realtime ADD TABLE actas;
ALTER PUBLICATION supabase_realtime ADD TABLE votos;

-- ============================================
-- SEED DATA: Santa Cruz de la Sierra (demo)
-- ============================================

-- 15 Distritos Municipales
INSERT INTO distritos (numero, nombre) VALUES
  (1, 'Distrito 1 - Casco Viejo'),
  (2, 'Distrito 2 - Norte'),
  (3, 'Distrito 3 - Estación Argentina'),
  (4, 'Distrito 4 - El Bajío'),
  (5, 'Distrito 5 - Pampa de la Isla'),
  (6, 'Distrito 6 - Villa 1ro de Mayo'),
  (7, 'Distrito 7 - UV Guaracachi'),
  (8, 'Distrito 8 - Plan 3000'),
  (9, 'Distrito 9 - Palmasola'),
  (10, 'Distrito 10 - El Urubó'),
  (11, 'Distrito 11 - Montero Hoyos'),
  (12, 'Distrito 12 - La Guardia'),
  (13, 'Distrito 13 - Nuevo Palmar'),
  (14, 'Distrito 14 - Paurito'),
  (15, 'Distrito 15 - Satélite Norte');

-- Recintos de ejemplo (20 recintos en distintos distritos)
INSERT INTO recintos (nombre, codigo, direccion, distrito_id, total_mesas) VALUES
  ('Unidad Educativa Germán Busch', 'R001', 'Av. Busch esq. 2do Anillo', (SELECT id FROM distritos WHERE numero = 1), 5),
  ('Colegio Nacional Florida', 'R002', 'C/ Florida y Av. Irala', (SELECT id FROM distritos WHERE numero = 1), 4),
  ('Unidad Educativa Guapay', 'R003', 'Av. Santos Dumont 3er Anillo', (SELECT id FROM distritos WHERE numero = 2), 3),
  ('Colegio Don Bosco', 'R004', 'C/ Ingavi esq. Quijarro', (SELECT id FROM distritos WHERE numero = 2), 4),
  ('Unidad Educativa Estación Argentina', 'R005', 'Av. Argentina y 3er Anillo', (SELECT id FROM distritos WHERE numero = 3), 3),
  ('Colegio Fe y Alegría', 'R006', 'C/ El Fuerte, B/ El Bajío', (SELECT id FROM distritos WHERE numero = 4), 3),
  ('Unidad Educativa Pampa de la Isla', 'R007', 'Av. Virgen de Cotoca', (SELECT id FROM distritos WHERE numero = 5), 4),
  ('Colegio Villa 1ro de Mayo', 'R008', 'B/ Villa 1ro de Mayo', (SELECT id FROM distritos WHERE numero = 6), 3),
  ('Unidad Educativa Guaracachi', 'R009', 'UV Guaracachi', (SELECT id FROM distritos WHERE numero = 7), 3),
  ('Colegio Plan 3000', 'R010', 'Av. Principal Plan 3000', (SELECT id FROM distritos WHERE numero = 8), 5),
  ('Unidad Educativa 24 de Septiembre', 'R011', 'B/ 24 de Septiembre, Plan 3000', (SELECT id FROM distritos WHERE numero = 8), 4),
  ('Colegio Palmasola', 'R012', 'Zona Palmasola', (SELECT id FROM distritos WHERE numero = 9), 2),
  ('Unidad Educativa El Urubó', 'R013', 'Zona El Urubó', (SELECT id FROM distritos WHERE numero = 10), 2),
  ('Colegio Montero Hoyos', 'R014', 'Comunidad Montero Hoyos', (SELECT id FROM distritos WHERE numero = 11), 2),
  ('Unidad Educativa La Guardia', 'R015', 'Av. Principal La Guardia', (SELECT id FROM distritos WHERE numero = 12), 3),
  ('Colegio Nuevo Palmar', 'R016', 'Comunidad Nuevo Palmar', (SELECT id FROM distritos WHERE numero = 13), 2),
  ('Unidad Educativa Paurito', 'R017', 'Comunidad Paurito', (SELECT id FROM distritos WHERE numero = 14), 2),
  ('Colegio Satélite Norte', 'R018', 'B/ Satélite Norte', (SELECT id FROM distritos WHERE numero = 15), 3),
  ('Unidad Educativa Hamacas', 'R019', 'B/ Hamacas, 4to Anillo', (SELECT id FROM distritos WHERE numero = 3), 3),
  ('Colegio Libertad', 'R020', 'UV 120, B/ Libertad', (SELECT id FROM distritos WHERE numero = 5), 3);

-- Generar mesas para cada recinto
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

-- Partidos políticos (basados en elecciones 2021 SCZ)
INSERT INTO partidos (nombre, sigla, color, orden) VALUES
  ('Unidad Cívica Solidaridad', 'UCS', '#FF6B00', 1),
  ('Comunidad Ciudadana - Autonomía', 'C-A', '#00B4D8', 2),
  ('Movimiento al Socialismo', 'MAS-IPSP', '#0066CC', 3),
  ('Santa Cruz Para Todos', 'SPT', '#8B5CF6', 4),
  ('Demócratas', 'DEM', '#059669', 5),
  ('SOL.bo', 'SOL', '#F59E0B', 6),
  ('Frente Para la Victoria', 'FPV', '#DC2626', 7),
  ('Movimiento Tercer Sistema', 'MTS', '#6B7280', 8);
