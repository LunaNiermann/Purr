import Database from "better-sqlite3";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";

export interface PairingRow {
  id: string;
  ext_pub: string;
  phone_pub: string | null;
  ext_token_hash: string;
  phone_token_hash: string | null;
  ext_name_blob: string | null;
  phone_name_blob: string | null;
  fcm_token: string | null;
  created_at: number;
  completed_at: number | null;
  last_used_at: number | null;
}

export interface RequestRow {
  id: string;
  pairing_id: string;
  request_blob: string;
  answer_blob: string | null;
  status: "pending" | "answered";
  created_at: number;
  expires_at: number;
  answered_at: number | null;
}

export interface BackupRow {
  backup_id: string;
  auth_hash: string;
  blob: Buffer;
  digest: string;
  updated_at: number;
}

export function openDb(path: string): Database.Database {
  if (path !== ":memory:") mkdirSync(dirname(path), { recursive: true });
  const db = new Database(path);
  db.pragma("journal_mode = WAL");
  db.pragma("foreign_keys = ON");
  db.exec(`
    CREATE TABLE IF NOT EXISTS pairings (
      id TEXT PRIMARY KEY,
      ext_pub TEXT NOT NULL,
      phone_pub TEXT,
      ext_token_hash TEXT NOT NULL,
      phone_token_hash TEXT,
      ext_name_blob TEXT,
      phone_name_blob TEXT,
      fcm_token TEXT,
      created_at INTEGER NOT NULL,
      completed_at INTEGER,
      last_used_at INTEGER
    );
    CREATE TABLE IF NOT EXISTS requests (
      id TEXT PRIMARY KEY,
      pairing_id TEXT NOT NULL REFERENCES pairings(id) ON DELETE CASCADE,
      request_blob TEXT NOT NULL,
      answer_blob TEXT,
      status TEXT NOT NULL DEFAULT 'pending',
      created_at INTEGER NOT NULL,
      expires_at INTEGER NOT NULL,
      answered_at INTEGER
    );
    CREATE INDEX IF NOT EXISTS idx_requests_pairing ON requests(pairing_id, status, expires_at);
    CREATE TABLE IF NOT EXISTS backups (
      backup_id TEXT PRIMARY KEY,
      auth_hash TEXT NOT NULL,
      blob BLOB NOT NULL,
      digest TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    );
  `);
  return db;
}

/** Remove expired requests and pairings that were never completed. */
export function cleanup(db: Database.Database, now = Date.now()): void {
  db.prepare("DELETE FROM requests WHERE expires_at < ?").run(now - 120_000);
  db.prepare(
    "DELETE FROM pairings WHERE completed_at IS NULL AND created_at < ?",
  ).run(now - 10 * 60_000);
}
