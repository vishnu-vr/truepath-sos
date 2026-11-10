#!/usr/bin/env node
/**
 * Grants (or revokes) the admin role for the fleet website.
 * Usage: node scripts/make-admin.mjs someone@example.com [--revoke]
 * The person must sign out/in afterwards for the new role to take effect.
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const email = process.argv[2];
if (!email) {
  console.error("Usage: node scripts/make-admin.mjs <email> [--revoke]");
  process.exit(1);
}
const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const project = JSON.parse(readFileSync(join(root, ".firebaserc"), "utf8"))
  .projects.default;
const res = await fetch(
  `http://127.0.0.1:15002/${project}/us-central1/setAdmin`,
  {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ email, admin: !process.argv.includes("--revoke") }),
  }
);
const body = await res.text();
if (!res.ok) {
  console.error(`Failed (${res.status}): ${body}`);
  process.exit(1);
}
console.log(`OK: ${body}`);
console.log("Note: the account must sign out and back in to pick up the role.");
