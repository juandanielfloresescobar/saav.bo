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

<div class="min-h-screen flex">
	<!-- Left panel - Brand -->
	<div class="hidden lg:flex lg:w-[45%] relative bg-gradient-to-br from-primary-800 via-primary-900 to-primary-900 overflow-hidden">
		<!-- Decorative elements -->
		<div class="absolute inset-0">
			<div class="absolute top-0 left-0 w-96 h-96 bg-primary-600/20 rounded-full -translate-x-1/2 -translate-y-1/2 blur-3xl"></div>
			<div class="absolute bottom-0 right-0 w-80 h-80 bg-primary-500/15 rounded-full translate-x-1/3 translate-y-1/3 blur-3xl"></div>
			<div class="absolute top-1/2 left-1/2 w-64 h-64 bg-primary-400/10 rounded-full -translate-x-1/2 -translate-y-1/2 blur-2xl"></div>
			<!-- Grid pattern -->
			<div class="absolute inset-0 opacity-[0.04]" style="background-image: radial-gradient(circle, white 1px, transparent 1px); background-size: 32px 32px;"></div>
		</div>

		<div class="relative z-10 flex flex-col justify-between p-12 w-full">
			<!-- Logo top -->
			<div class="flex items-center gap-3">
				<div class="w-10 h-10 rounded-xl bg-white/10 backdrop-blur flex items-center justify-center border border-white/10">
					<span class="text-white font-extrabold text-base">Q</span>
				</div>
				<span class="text-white/90 font-bold text-lg tracking-tight">Quantis</span>
			</div>

			<!-- Center content -->
			<div class="space-y-6">
				<div>
					<h2 class="text-4xl font-extrabold text-white leading-tight tracking-tight">
						Control Electoral<br/>
						<span class="text-primary-300">en tiempo real</span>
					</h2>
					<p class="text-primary-200/70 text-base mt-4 max-w-sm leading-relaxed">
						Plataforma de monitoreo y verificacion de actas electorales para garantizar la transparencia del proceso democratico.
					</p>
				</div>

				<!-- Stats preview -->
				<div class="flex gap-8 pt-4">
					<div>
						<div class="text-2xl font-extrabold text-white tabular-nums">15</div>
						<div class="text-xs text-primary-300/60 font-medium mt-0.5">Distritos</div>
					</div>
					<div class="w-px bg-white/10"></div>
					<div>
						<div class="text-2xl font-extrabold text-white tabular-nums">4</div>
						<div class="text-xs text-primary-300/60 font-medium mt-0.5">Roles</div>
					</div>
					<div class="w-px bg-white/10"></div>
					<div>
						<div class="text-2xl font-extrabold text-white tabular-nums">24/7</div>
						<div class="text-xs text-primary-300/60 font-medium mt-0.5">Monitoreo</div>
					</div>
				</div>
			</div>

			<!-- Footer -->
			<p class="text-primary-300/40 text-xs font-medium">
				Elecciones Subnacionales 2026 — Santa Cruz de la Sierra
			</p>
		</div>
	</div>

	<!-- Right panel - Form -->
	<div class="flex-1 flex items-center justify-center px-6 py-12 auth-pattern">
		<div class="w-full max-w-sm animate-in">
			<!-- Mobile logo -->
			<div class="text-center mb-10">
				<div class="w-14 h-14 rounded-2xl bg-gradient-to-br from-primary-600 to-primary-800 flex items-center justify-center mx-auto mb-5 shadow-lg shadow-primary-600/20">
					<span class="text-white font-extrabold text-2xl">Q</span>
				</div>
				<h1 class="text-2xl font-extrabold text-slate-900 tracking-tight">Bienvenido</h1>
				<p class="text-sm text-slate-400 mt-1.5">Ingresa a tu cuenta para continuar</p>
			</div>

			<!-- Error -->
			{#if error}
				<div class="flex items-center gap-2.5 bg-danger-50 border border-danger-100 text-danger-600 text-sm rounded-xl px-4 py-3 mb-6">
					<svg class="w-4 h-4 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
						<path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m9-.75a9 9 0 11-18 0 9 9 0 0118 0zm-9 3.75h.008v.008H12v-.008z" />
					</svg>
					{error}
				</div>
			{/if}

			<!-- Form -->
			<form onsubmit={handleLogin} class="space-y-5">
				<div>
					<label for="email" class="block text-[13px] font-semibold text-slate-700 mb-2">
						Correo electronico
					</label>
					<input
						id="email"
						type="email"
						bind:value={email}
						required
						placeholder="delegado@quantis.bo"
						class="input"
					/>
				</div>

				<div>
					<label for="password" class="block text-[13px] font-semibold text-slate-700 mb-2">
						Contrasena
					</label>
					<input
						id="password"
						type="password"
						bind:value={password}
						required
						placeholder="Tu contrasena"
						class="input"
					/>
				</div>

				<button
					type="submit"
					disabled={loading}
					class="w-full btn-primary py-3"
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

			<p class="text-center text-slate-300 text-xs mt-8 lg:hidden">
				Elecciones Subnacionales 2026 — Santa Cruz de la Sierra
			</p>
		</div>
	</div>
</div>
