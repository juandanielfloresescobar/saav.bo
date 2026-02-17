<script lang="ts">
	import { goto } from '$app/navigation';

	let { data } = $props();

	let email = $state('');
	let password = $state('');
	let loading = $state(false);
	let error = $state('');

	async function handleLogin(e: Event) {
		e.preventDefault();
		loading = true;
		error = '';

		const { error: authError } = await data.supabase.auth.signInWithPassword({
			email,
			password
		});

		if (authError) {
			error = 'Credenciales inválidas. Contacta al administrador.';
			loading = false;
			return;
		}

		goto('/');
	}
</script>

<svelte:head>
	<title>Quantis - Iniciar Sesión</title>
</svelte:head>

<div class="min-h-screen bg-gradient-to-br from-primary-600 via-primary-700 to-primary-900 flex items-center justify-center px-4">
	<div class="w-full max-w-md">
		<!-- Logo -->
		<div class="text-center mb-8">
			<div class="w-16 h-16 bg-white rounded-2xl flex items-center justify-center mx-auto mb-4 shadow-lg">
				<span class="text-primary-600 font-bold text-3xl">Q</span>
			</div>
			<h1 class="text-3xl font-bold text-white">Quantis</h1>
			<p class="text-primary-200 mt-1">Sistema de Control Electoral</p>
		</div>

		<!-- Login Card -->
		<div class="bg-white rounded-2xl shadow-xl p-8">
			<h2 class="text-xl font-semibold text-gray-900 mb-6">Iniciar Sesión</h2>

			{#if error}
				<div class="bg-danger-500/10 border border-danger-500/20 text-danger-600 text-sm rounded-lg px-4 py-3 mb-4">
					{error}
				</div>
			{/if}

			<form onsubmit={handleLogin} class="space-y-4">
				<div>
					<label for="email" class="block text-sm font-medium text-gray-700 mb-1">
						Correo electrónico
					</label>
					<input
						id="email"
						type="email"
						bind:value={email}
						required
						placeholder="delegado@quantis.bo"
						class="w-full px-4 py-2.5 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-primary-500 outline-none transition-shadow text-sm"
					/>
				</div>

				<div>
					<label for="password" class="block text-sm font-medium text-gray-700 mb-1">
						Contraseña
					</label>
					<input
						id="password"
						type="password"
						bind:value={password}
						required
						placeholder="Tu contraseña"
						class="w-full px-4 py-2.5 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-primary-500 outline-none transition-shadow text-sm"
					/>
				</div>

				<button
					type="submit"
					disabled={loading}
					class="w-full bg-primary-600 hover:bg-primary-700 text-white font-medium py-2.5 px-4 rounded-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed text-sm"
				>
					{loading ? 'Ingresando...' : 'Ingresar'}
				</button>
			</form>
		</div>

		<p class="text-center text-primary-200 text-xs mt-6">
			Elecciones Subnacionales 2026 — Santa Cruz de la Sierra
		</p>
	</div>
</div>
