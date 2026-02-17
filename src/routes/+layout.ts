import { createBrowserClient, createServerClient, isBrowser } from '@supabase/ssr';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';

export const ssr = false;

export const load = async ({ data, depends, fetch }) => {
	depends('supabase:auth');

	const supabase = isBrowser()
		? createBrowserClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY, {
				global: { fetch }
			})
		: createServerClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY, {
				global: { fetch },
				cookies: { getAll: () => [] }
			});

	const {
		data: { session }
	} = await supabase.auth.getSession();

	// Obtener perfil del usuario si está autenticado
	let perfil: { rol: string; nombre: string; recinto_id: string | null } | null = null;
	if (session) {
		const { data: usuario } = await supabase
			.from('usuarios')
			.select('rol, nombre, recinto_id')
			.eq('auth_user_id', session.user.id)
			.single();
		perfil = usuario;
	}

	return { session, supabase, perfil };
};
