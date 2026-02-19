<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';

	let { data } = $props();

	onMount(() => {
		if (!data.session) {
			goto('/auth');
			return;
		}
		if (!data.perfil) {
			goto('/auth');
			return;
		}
		switch (data.perfil.rol) {
			case 'delegado':
				goto('/ingesta');
				break;
			case 'verificador':
				goto('/validacion');
				break;
			case 'candidato':
			case 'admin':
				goto('/dashboard');
				break;
			default:
				goto('/auth');
		}
	});
</script>

<div class="flex items-center justify-center min-h-screen bg-white">
	<div class="text-center">
		<div class="w-10 h-10 bg-primary-600 rounded-xl flex items-center justify-center mx-auto mb-3">
			<span class="text-white font-bold text-lg">Q</span>
		</div>
		<div class="flex items-center gap-2 text-gray-400">
			<svg class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24">
				<circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
				<path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
			</svg>
			<span class="text-sm">Cargando...</span>
		</div>
	</div>
</div>
