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
-- SEED DATA: Municipio de Warnes (demo)
-- ============================================

-- 6 Distritos Municipales de Warnes
INSERT INTO distritos (numero, nombre) VALUES
  (1, 'Distrito 1 - Central (Warnes)'),
  (2, 'Distrito 2 - Norte (Juan Latino)'),
  (3, 'Distrito 3 - Sur (Los Chacos)'),
  (4, 'Distrito 4 - Este (Asusaquí)'),
  (5, 'Distrito 5 - Oeste (Clara Chuchío)'),
  (6, 'Distrito 6 - Industrial (Parque Industrial)');

-- 15 Recintos electorales de Warnes (~80 mesas totales)
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

-- Partidos políticos (elecciones subnacionales Warnes 2026)
INSERT INTO partidos (nombre, sigla, color, orden) VALUES
  ('Movimiento al Socialismo - Instrumento Político por la Soberanía de los Pueblos', 'MAS-IPSP', '#0066CC', 1),
  ('Creemos', 'CREEMOS', '#059669', 2),
  ('Santa Cruz Para Todos', 'SPT', '#8B5CF6', 3),
  ('Unidad Cívica Solidaridad', 'UCS', '#FF6B00', 4),
  ('Acción Democrática Nacionalista', 'ADN', '#DC2626', 5),
  ('Movimiento Tercer Sistema', 'MTS', '#6B7280', 6),
  ('Nueva Generación Patriótica', 'NGP', '#0D9488', 7),
  ('Partido Demócrata Cristiano', 'PDC', '#EAB308', 8);
