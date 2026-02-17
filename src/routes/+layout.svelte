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
					{ href: '/validacion', label: 'Validación', icon: 'check' },
					{ href: '/dashboard', label: 'Dashboard', icon: 'chart' }
				];
			case 'candidato':
				return [{ href: '/dashboard', label: 'Dashboard', icon: 'chart' }];
			case 'admin':
				return [
					{ href: '/ingesta', label: 'Ingesta', icon: 'clipboard' },
					{ href: '/validacion', label: 'Validación', icon: 'check' },
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
	<div class="min-h-screen flex flex-col">
		<!-- Header -->
		<header class="bg-white border-b border-gray-200 sticky top-0 z-50">
			<div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
				<div class="flex justify-between items-center h-16">
					<div class="flex items-center gap-3">
						<a href="/" class="flex items-center gap-2">
							<div class="w-8 h-8 bg-primary-600 rounded-lg flex items-center justify-center">
								<span class="text-white font-bold text-sm">Q</span>
							</div>
							<span class="text-lg font-bold text-gray-900">Quantis</span>
						</a>
						<span class="hidden sm:inline text-xs text-gray-400 border-l border-gray-200 pl-3"
							>Control Electoral</span
						>
					</div>

					<nav class="hidden sm:flex items-center gap-1">
						{#each navItems as item}
							<a
								href={item.href}
								class="px-3 py-2 rounded-lg text-sm font-medium transition-colors {currentPath.startsWith(
									item.href
								)
									? 'bg-primary-50 text-primary-700'
									: 'text-gray-600 hover:bg-gray-50 hover:text-gray-900'}"
							>
								{item.label}
							</a>
						{/each}
					</nav>

					<div class="flex items-center gap-3">
						<div class="hidden sm:flex flex-col items-end">
							<span class="text-sm font-medium text-gray-900">{perfil?.nombre}</span>
							<span class="text-xs text-gray-500 capitalize">{perfil?.rol}</span>
						</div>
						<button
							onclick={logout}
							class="text-sm text-gray-500 hover:text-gray-700 px-3 py-1.5 rounded-lg hover:bg-gray-100 transition-colors"
						>
							Salir
						</button>
					</div>
				</div>
			</div>
		</header>

		<!-- Mobile bottom nav -->
		<nav class="sm:hidden fixed bottom-0 left-0 right-0 bg-white border-t border-gray-200 z-50">
			<div class="flex justify-around py-2">
				{#each navItems as item}
					<a
						href={item.href}
						class="flex flex-col items-center gap-0.5 px-3 py-1 rounded-lg text-xs {currentPath.startsWith(
							item.href
						)
							? 'text-primary-600 font-medium'
							: 'text-gray-500'}"
					>
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
