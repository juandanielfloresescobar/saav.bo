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
			error = 'Credenciales invalidas. Contacta al administrador.';
			loading = false;
			return;
		}

		goto('/');
	}
</script>

<svelte:head>
	<title>Quantis - Iniciar Sesion</title>
</svelte:head>

<div class="min-h-screen bg-white flex items-center justify-center px-4">
	<div class="w-full max-w-sm">
		<!-- Logo -->
		<div class="text-center mb-10">
			<div class="w-14 h-14 bg-primary-600 rounded-2xl flex items-center justify-center mx-auto mb-4">
				<span class="text-white font-extrabold text-2xl">Q</span>
			</div>
			<h1 class="text-2xl font-bold text-gray-900 tracking-tight">Quantis</h1>
			<p class="text-sm text-gray-400 mt-1">Sistema de Control Electoral</p>
		</div>

		<!-- Login Card -->
		<div class="space-y-6">
			{#if error}
				<div class="bg-danger-50 text-danger-600 text-sm rounded-lg px-4 py-3">
					{error}
				</div>
			{/if}

			<form onsubmit={handleLogin} class="space-y-4">
				<div>
					<label for="email" class="block text-sm font-medium text-gray-700 mb-1.5">
						Correo electronico
					</label>
					<input
						id="email"
						type="email"
						bind:value={email}
						required
						placeholder="delegado@quantis.bo"
						class="w-full px-3.5 py-2.5 bg-gray-50 border border-gray-200 rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-primary-500 focus:bg-white outline-none transition-all text-sm"
					/>
				</div>

				<div>
					<label for="password" class="block text-sm font-medium text-gray-700 mb-1.5">
						Contrasena
					</label>
					<input
						id="password"
						type="password"
						bind:value={password}
						required
						placeholder="Tu contrasena"
						class="w-full px-3.5 py-2.5 bg-gray-50 border border-gray-200 rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-primary-500 focus:bg-white outline-none transition-all text-sm"
					/>
				</div>

				<button
					type="submit"
					disabled={loading}
					class="w-full bg-primary-600 hover:bg-primary-700 text-white font-semibold py-2.5 px-4 rounded-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed text-sm"
				>
					{#if loading}
						<span class="flex items-center justify-center gap-2">
							<svg class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24">
								<circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
								<path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
							</svg>
							Ingresando...
						</span>
					{:else}
						Ingresar
					{/if}
				</button>
			</form>

			<p class="text-center text-gray-300 text-xs">
				Elecciones Subnacionales 2026 — Santa Cruz de la Sierra
			</p>
		</div>
	</div>
</div>
