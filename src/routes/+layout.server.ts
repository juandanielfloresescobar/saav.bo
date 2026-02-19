export const load = async ({ locals: { safeGetSession, supabase }, cookies }) => {
	const { session } = await safeGetSession();

	let perfil: App.PageData['perfil'] = null;
	if (session) {
		const { data: usuario } = await supabase
			.from('usuarios')
			.select('id, rol, nombre, recinto_id')
			.eq('auth_user_id', session.user.id)
			.single();
		perfil = usuario;
	}

	return { session, perfil, cookies: cookies.getAll() };
};
