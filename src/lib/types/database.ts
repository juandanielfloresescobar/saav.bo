// Core database entity types for Quantis electoral monitoring

export interface Partido {
	id: string;
	sigla: string;
	nombre: string;
	color: string;
	orden: number;
}

export interface Distrito {
	id: string;
	nombre: string;
	numero: number;
}

export interface Recinto {
	nombre: string;
	distrito_id: string;
	distritos?: Distrito;
}

export interface Mesa {
	id: string;
	numero: number;
	recinto_id: string;
	total_habilitados: number;
	recintos?: Recinto;
}

export interface Acta {
	id: string;
	mesa_id: string;
	delegado_id?: string;
	foto_url?: string | null;
	total_votantes: number;
	votos_nulos: number;
	votos_blancos: number;
	estado: EstadoActa;
	observaciones?: string | null;
	created_at: string;
	updated_at?: string;
	verificado_por?: string | null;
	mesas?: {
		numero: number;
		recinto_id?: string;
		recintos?: {
			nombre: string;
			distrito_id?: string;
			distritos?: { numero: number; nombre: string };
		};
	};
	usuarios?: { nombre: string };
}

export interface VotoDisplay {
	cantidad: number;
	partidos?: { sigla: string; color: string };
}

export interface ResultadoPartido {
	sigla: string;
	color: string;
	votos: number;
}

export interface EvolucionEntry {
	hora: string;
	actas: number;
}

export type EstadoActa = 'pendiente' | 'verificada' | 'observada' | 'rechazada';

export const ESTADOS: readonly EstadoActa[] = ['pendiente', 'verificada', 'observada', 'rechazada'] as const;

export interface EstadoCounts {
	[key: string]: number;
	pendiente: number;
	verificada: number;
	observada: number;
	rechazada: number;
}
