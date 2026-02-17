import { openDB, type IDBPDatabase } from 'idb';

const DB_NAME = 'quantis-offline';
const DB_VERSION = 1;
const STORE_NAME = 'pending-actas';

interface PendingActa {
	id: string;
	mesa_id: string;
	foto: Blob | null;
	votos: Record<string, number>;
	votos_nulos: number;
	votos_blancos: number;
	total_votantes: number;
	timestamp: number;
}

let dbPromise: Promise<IDBPDatabase> | null = null;

function getDB() {
	if (!dbPromise) {
		dbPromise = openDB(DB_NAME, DB_VERSION, {
			upgrade(db) {
				if (!db.objectStoreNames.contains(STORE_NAME)) {
					db.createObjectStore(STORE_NAME, { keyPath: 'id' });
				}
			}
		});
	}
	return dbPromise;
}

export async function savePendingActa(acta: PendingActa): Promise<void> {
	const db = await getDB();
	await db.put(STORE_NAME, acta);
}

export async function getPendingActas(): Promise<PendingActa[]> {
	const db = await getDB();
	return db.getAll(STORE_NAME);
}

export async function removePendingActa(id: string): Promise<void> {
	const db = await getDB();
	await db.delete(STORE_NAME, id);
}

export async function getPendingCount(): Promise<number> {
	const db = await getDB();
	return db.count(STORE_NAME);
}

export function isOnline(): boolean {
	return typeof navigator !== 'undefined' ? navigator.onLine : true;
}
