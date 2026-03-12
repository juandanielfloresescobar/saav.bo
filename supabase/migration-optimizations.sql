-- ============================================
-- QUANTIS - Optimizaciones para Produccion
-- ============================================
-- Ejecutar en Supabase SQL Editor despues de schema.sql y seed-demo.sql

-- ============================================
-- RPC: Dashboard stats en una sola llamada
-- ============================================

-- Drop old single-param version if exists
DROP FUNCTION IF EXISTS get_dashboard_data(UUID);

CREATE OR REPLACE FUNCTION get_dashboard_data(
  p_municipio_id UUID DEFAULT NULL,
  p_distrito_id UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
DECLARE
  result JSON;
  v_distrito_ids UUID[];
BEGIN
  -- Resolve district IDs based on filters
  IF p_distrito_id IS NOT NULL THEN
    v_distrito_ids := ARRAY[p_distrito_id];
  ELSIF p_municipio_id IS NOT NULL THEN
    SELECT array_agg(id) INTO v_distrito_ids
    FROM public.distritos WHERE municipio_id = p_municipio_id;
  END IF;

  SELECT json_build_object(
    'total_mesas', (
      SELECT count(*) FROM public.mesas m
      JOIN public.recintos r ON m.recinto_id = r.id
      WHERE (v_distrito_ids IS NULL OR r.distrito_id = ANY(v_distrito_ids))
    ),
    'actas', (
      SELECT json_build_object(
        'procesadas', count(*),
        'verificadas', count(*) FILTER (WHERE a.estado = 'verificada'),
        'total_nulos', coalesce(sum(a.votos_nulos), 0),
        'total_blancos', coalesce(sum(a.votos_blancos), 0)
      )
      FROM public.actas a
      JOIN public.mesas m ON a.mesa_id = m.id
      JOIN public.recintos r ON m.recinto_id = r.id
      WHERE (v_distrito_ids IS NULL OR r.distrito_id = ANY(v_distrito_ids))
    ),
    'votos_partido', (
      SELECT coalesce(json_agg(row_to_json(vp.*) ORDER BY vp.orden), '[]'::json)
      FROM (
        SELECT p.id, p.sigla, p.color, p.orden,
               coalesce(sum(v.cantidad), 0)::int as votos
        FROM public.partidos p
        LEFT JOIN public.votos v ON v.partido_id = p.id
        LEFT JOIN public.actas a ON v.acta_id = a.id
        LEFT JOIN public.mesas m ON a.mesa_id = m.id
        LEFT JOIN public.recintos r ON m.recinto_id = r.id
        WHERE (v_distrito_ids IS NULL OR r.distrito_id = ANY(v_distrito_ids))
        GROUP BY p.id, p.sigla, p.color, p.orden
        ORDER BY p.orden
      ) vp
    ),
    'evolucion', (
      SELECT coalesce(json_agg(row_to_json(ev.*) ORDER BY ev.hora), '[]'::json)
      FROM (
        SELECT
          to_char(a.created_at AT TIME ZONE 'America/La_Paz', 'HH24:MI') as hora,
          count(*) OVER (ORDER BY min(a.created_at))::int as actas
        FROM public.actas a
        JOIN public.mesas m ON a.mesa_id = m.id
        JOIN public.recintos r ON m.recinto_id = r.id
        WHERE (v_distrito_ids IS NULL OR r.distrito_id = ANY(v_distrito_ids))
        GROUP BY to_char(a.created_at AT TIME ZONE 'America/La_Paz', 'HH24:MI')
        ORDER BY hora
      ) ev
    ),
    'por_distrito', CASE WHEN p_distrito_id IS NOT NULL THEN NULL ELSE (
      SELECT coalesce(json_agg(row_to_json(pd.*) ORDER BY pd.distrito_nombre), '[]'::json)
      FROM (
        SELECT
          d.nombre as distrito_nombre,
          (
            SELECT coalesce(json_object_agg(p2.sigla, coalesce(sub.votos, 0) ORDER BY p2.orden), '{}'::json)
            FROM public.partidos p2
            LEFT JOIN (
              SELECT v2.partido_id, sum(v2.cantidad)::int as votos
              FROM public.votos v2
              JOIN public.actas a2 ON v2.acta_id = a2.id
              JOIN public.mesas m2 ON a2.mesa_id = m2.id
              JOIN public.recintos r2 ON m2.recinto_id = r2.id
              WHERE r2.distrito_id = d.id
              GROUP BY v2.partido_id
            ) sub ON sub.partido_id = p2.id
          ) as votos
        FROM public.distritos d
        WHERE (v_distrito_ids IS NULL OR d.id = ANY(v_distrito_ids))
        ORDER BY d.numero
      ) pd
    ) END
  ) INTO result;

  RETURN result;
END;
$$;

-- Permisos: accesible por usuarios autenticados
GRANT EXECUTE ON FUNCTION get_dashboard_data(UUID, UUID) TO authenticated;

-- ============================================
-- RPC: Conteo de actas por estado
-- ============================================

CREATE OR REPLACE FUNCTION get_acta_counts_by_estado()
RETURNS TABLE(estado TEXT, count BIGINT)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
  SELECT a.estado, count(*)
  FROM public.actas a
  GROUP BY a.estado;
$$;

GRANT EXECUTE ON FUNCTION get_acta_counts_by_estado() TO authenticated;

-- Forzar recarga del schema en PostgREST
NOTIFY pgrst, 'reload schema';
