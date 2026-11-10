#!/usr/bin/env node
/**
 * Seeds the demo caregiver + device by calling the emulator-only `seed`
 * function (which runs with the Firebase CLI's credentials), then saves the
 * device secret where the simulator expects it.
 *
 * Prereq: `firebase emulators:start --only functions` is running.
 * Usage:  node scripts/seed.mjs
 */
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const project = JSON.parse(readFileSync(join(root, ".firebaserc"), "utf8"))
  .projects.default;
const url = `http://127.0.0.1:15002/${project}/us-central1/seed`;

const res = await fetch(url, { method: "POST" });
if (!res.ok) {
  console.error(`Seed failed (${res.status}): ${await res.text()}`);
  console.error("Is the functions emulator running? → firebase emulators:start --only functions");
  process.exit(1);
}
const data = await res.json();

const deviceFile = join(root, "simulator", "device.json");
mkdirSync(dirname(deviceFile), { recursive: true });
writeFileSync(
  deviceFile,
  JSON.stringify(
    {
      project,
      deviceId: data.device.deviceId,
      secretToken: data.device.secretToken,
    },
    null,
    2
  )
);

console.log("Seeded.");
console.log(`  Caregiver login : ${data.caregiver.email} / ${data.caregiver.password}`);
console.log(`  Device          : ${data.device.deviceId}`);
console.log(`  Device secret   : saved to simulator/device.json`);
