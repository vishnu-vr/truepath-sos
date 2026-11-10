#!/usr/bin/env node
/**
 * The "factory": provisions a brand-new cane via the backend and prints
 * what would ship with it — the device secret (burned into the ESP32) and
 * the one-time claim code (printed as the QR in the box).
 *
 * Prereq: `firebase emulators:start --only functions` is running.
 * Usage:  node scripts/provision.mjs ["Cane name"]
 */
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const project = JSON.parse(readFileSync(join(root, ".firebaserc"), "utf8"))
  .projects.default;
const url = `http://127.0.0.1:15002/${project}/us-central1/provision`;

const res = await fetch(url, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ name: process.argv[2] || "" }),
});
if (!res.ok) {
  console.error(`Provision failed (${res.status}): ${await res.text()}`);
  process.exit(1);
}
const { deviceId, secretToken, claimCode } = await res.json();

// Keep the "ESP32 flash" contents so the simulator can play this cane.
const file = join(root, "simulator", `${deviceId}.json`);
mkdirSync(dirname(file), { recursive: true });
writeFileSync(file, JSON.stringify({ project, deviceId, secretToken }, null, 2));

console.log("🏭 New cane provisioned.");
console.log(`  Device ID    : ${deviceId}`);
console.log(`  Claim code   : ${claimCode}   ← the QR in the box; enter it in the app`);
console.log(`  Device secret: saved to simulator/${deviceId}.json (lives in the ESP32)`);
console.log("");
console.log("  Fire an SOS from this cane after it is claimed:");
console.log(`    node simulator/sos.mjs --cane ${deviceId}`);
