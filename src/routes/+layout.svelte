<script lang="ts">
	import { invalidate, goto } from '$app/navigation';
	import { page } from '$app/stores';
	import { onMount } from 'svelte';
	import '../app.css';

	let { data, children } = $props();

	let supabase = $derived(data.supabase);
	let session = $derived(data.session);
	let perfil = $derived(data.perfil);

	onMount(() => {
		const {
			data: { subscription }
		} = supabase.auth.onAuthStateChange((_event, newSession) => {
			if (newSession?.expires_at !== session?.expires_at) {
				invalidate('supabase:auth');
			}
		});
		return () => subscription.unsubscribe();
	});

	async function logout() {
		await supabase.auth.signOut();
		goto('/auth');
	}

	const navItems = $derived.by(() => {
		if (!perfil) return [];
		switch (perfil.rol) {
			case 'delegado':
				return [{ href: '/ingesta', label: 'Ingesta', icon: 'clipboard' }];
			case 'verificador':
				return [
					{ href: '/validacion', label: 'Validacion', icon: 'shield' },
					{ href: '/dashboard', label: 'Dashboard', icon: 'chart' }
				];
			case 'candidato':
				return [{ href: '/dashboard', label: 'Dashboard', icon: 'chart' }];
			case 'admin':
				return [
					{ href: '/ingesta', label: 'Ingesta', icon: 'clipboard' },
					{ href: '/validacion', label: 'Validacion', icon: 'shield' },
					{ href: '/dashboard', label: 'Dashboard', icon: 'chart' }
				];
			default:
				return [];
		}
	});

	let currentPath = $derived($page.url.pathname);
	let isAuthPage = $derived(currentPath === '/auth');
</script>

<svelte:head>
	<link rel="icon" href="/favicon.svg" type="image/svg+xml" />
</svelte:head>

{#if session && !isAuthPage}
	<div class="min-h-screen flex flex-col bg-white">
		<!-- Header -->
		<header class="bg-white border-b border-gray-100 sticky top-0 z-50">
			<div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
				<div class="flex justify-between items-center h-14">
					<div class="flex items-center gap-8">
						<a href="/" class="flex items-center gap-2.5">
							<div class="w-8 h-8 bg-primary-600 rounded-lg flex items-center justify-center">
								<span class="text-white font-bold text-sm">Q</span>
							</div>
							<div class="flex items-center gap-2">
								<span class="text-base font-bold text-gray-900 tracking-tight">Quantis</span>
								<span class="hidden sm:inline text-[11px] text-gray-400 font-medium uppercase tracking-wider">Control Electoral</span>
							</div>
						</a>

						<nav class="hidden sm:flex items-center gap-1">
							{#each navItems as item}
								{@const active = currentPath.startsWith(item.href)}
								<a
									href={item.href}
									class="flex items-center gap-1.5 px-3 py-1.5 rounded-md text-[13px] font-medium transition-all
										{active
											? 'bg-primary-50 text-primary-700'
											: 'text-gray-500 hover:text-gray-900 hover:bg-gray-50'}"
								>
									{#if item.icon === 'clipboard'}
										<svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
											<path stroke-linecap="round" stroke-linejoin="round" d="M15.666 3.888A2.25 2.25 0 0013.5 2.25h-3c-1.03 0-1.9.693-2.166 1.638m7.332 0c.055.194.084.4.084.612v0a.75.75 0 01-.75.75H9.75a.75.75 0 01-.75-.75v0c0-.212.03-.418.084-.612m7.332 0c.646.049 1.288.11 1.927.184 1.1.128 1.907 1.077 1.907 2.185V19.5a2.25 2.25 0 01-2.25 2.25H6.75A2.25 2.25 0 014.5 19.5V6.257c0-1.108.806-2.057 1.907-2.185a48.208 48.208 0 011.927-.184" />
										</svg>
									{:else if item.icon === 'shield'}
										<svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
											<path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75m-3-7.036A11.959 11.959 0 013.598 6 11.99 11.99 0 003 9.749c0 5.592 3.824 10.29 9 11.623 5.176-1.332 9-6.03 9-11.622 0-1.31-.21-2.571-.598-3.751h-.152c-3.196 0-6.1-1.248-8.25-3.285z" />
										</svg>
									{:else if item.icon === 'chart'}
										<svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
											<path stroke-linecap="round" stroke-linejoin="round" d="M3 13.125C3 12.504 3.504 12 4.125 12h2.25c.621 0 1.125.504 1.125 1.125v6.75C7.5 20.496 6.996 21 6.375 21h-2.25A1.125 1.125 0 013 19.875v-6.75zM9.75 8.625c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125v11.25c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 01-1.125-1.125V8.625zM16.5 4.125c0-.621.504-1.125 1.125-1.125h2.25C20.496 3 21 3.504 21 4.125v15.75c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 01-1.125-1.125V4.125z" />
										</svg>
									{/if}
									{item.label}
								</a>
							{/each}
						</nav>
					</div>

					<div class="flex items-center gap-3">
						<div class="hidden sm:flex flex-col items-end">
							<span class="text-[13px] font-semibold text-gray-900">{perfil?.nombre}</span>
							<span class="text-[11px] text-gray-400 capitalize">{perfil?.rol}</span>
						</div>
						<button
							onclick={logout}
							class="text-gray-400 hover:text-gray-600 p-1.5 rounded-md hover:bg-gray-50 transition-colors"
							title="Cerrar sesion"
						>
							<svg class="w-4.5 h-4.5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
								<path stroke-linecap="round" stroke-linejoin="round" d="M15.75 9V5.25A2.25 2.25 0 0013.5 3h-6a2.25 2.25 0 00-2.25 2.25v13.5A2.25 2.25 0 007.5 21h6a2.25 2.25 0 002.25-2.25V15m3 0l3-3m0 0l-3-3m3 3H9" />
							</svg>
						</button>
					</div>
				</div>
			</div>
		</header>

		<!-- Mobile bottom nav -->
		<nav class="sm:hidden fixed bottom-0 left-0 right-0 bg-white border-t border-gray-100 z-50 safe-area-bottom">
			<div class="flex justify-around py-1.5 px-2">
				{#each navItems as item}
					{@const active = currentPath.startsWith(item.href)}
					<a
						href={item.href}
						class="flex flex-col items-center gap-0.5 px-4 py-1.5 rounded-lg text-[11px] font-medium transition-colors
							{active ? 'text-primary-600' : 'text-gray-400'}"
					>
						{#if item.icon === 'clipboard'}
							<svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
								<path stroke-linecap="round" stroke-linejoin="round" d="M15.666 3.888A2.25 2.25 0 0013.5 2.25h-3c-1.03 0-1.9.693-2.166 1.638m7.332 0c.055.194.084.4.084.612v0a.75.75 0 01-.75.75H9.75a.75.75 0 01-.75-.75v0c0-.212.03-.418.084-.612m7.332 0c.646.049 1.288.11 1.927.184 1.1.128 1.907 1.077 1.907 2.185V19.5a2.25 2.25 0 01-2.25 2.25H6.75A2.25 2.25 0 014.5 19.5V6.257c0-1.108.806-2.057 1.907-2.185a48.208 48.208 0 011.927-.184" />
							</svg>
						{:else if item.icon === 'shield'}
							<svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
								<path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75m-3-7.036A11.959 11.959 0 013.598 6 11.99 11.99 0 003 9.749c0 5.592 3.824 10.29 9 11.623 5.176-1.332 9-6.03 9-11.622 0-1.31-.21-2.571-.598-3.751h-.152c-3.196 0-6.1-1.248-8.25-3.285z" />
							</svg>
						{:else if item.icon === 'chart'}
							<svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
								<path stroke-linecap="round" stroke-linejoin="round" d="M3 13.125C3 12.504 3.504 12 4.125 12h2.25c.621 0 1.125.504 1.125 1.125v6.75C7.5 20.496 6.996 21 6.375 21h-2.25A1.125 1.125 0 013 19.875v-6.75zM9.75 8.625c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125v11.25c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 01-1.125-1.125V8.625zM16.5 4.125c0-.621.504-1.125 1.125-1.125h2.25C20.496 3 21 3.504 21 4.125v15.75c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 01-1.125-1.125V4.125z" />
							</svg>
						{/if}
						{item.label}
					</a>
				{/each}
			</div>
		</nav>

		<!-- Content -->
		<main class="flex-1 pb-16 sm:pb-0">
			{@render children()}
		</main>
	</div>
{:else}
	{@render children()}
{/if}
