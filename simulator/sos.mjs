#!/usr/bin/env node
/**
 * TruePath cane simulator — stands in for the ESP32 firmware and mirrors the
 * documented flow:
 *
 *   Step 1-2: user long-presses the SOS button; ESP32 debounces it.
 *             (here: you running this script IS the long press)
 *   Step 3  : buzzer + vibration confirm locally. (printed to the console)
 *   Step 4  : GPS reads latitude/longitude.       (--lat / --lng flags)
 *   Step 5-6: ESP32 joins WiFi and opens HTTPS.   (Node's fetch)
 *   Step 7  : build the small JSON message: device ID, SOS type, time,
 *             location, battery.
 *   Step 8  : HTTPS POST to the TruePath backend.
 *
 * Usage:
 *   node simulator/sos.mjs                      # the demo cane (device.json)
 *   node simulator/sos.mjs --cane cane-7f3a2b   # a provisioned cane
 *   node simulator/sos.mjs --lat 9.98 --lng 76.3 --battery 42
 *   node simulator/sos.mjs --secret WRONG       # negative test
 */
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

const here = dirname(fileURLToPath(import.meta.url));

const { values: args } = parseArgs({
  options: {
    cane: { type: "string" }, // which simulator/<cane>.json to use
    lat: { type: "string", default: "9.9816" }, // Marine Drive, Kochi
    lng: { type: "string", default: "76.2999" },
    battery: { type: "string", default: "78" },
    type: { type: "string", default: "sos" },
    url: { type: "string" },
    secret: { type: "string" },
    device: { type: "string" },
  },
});

// The "ESP32 flash": deviceId + secret written at provisioning time.
let saved = {};
const file = join(here, args.cane ? `${args.cane}.json` : "device.json");
try {
  saved = JSON.parse(readFileSync(file, "utf8"));
} catch {
  if (!(args.secret && args.device)) {
    console.error(`${file} not found — provision or seed first,`);
    console.error("or pass --device and --secret explicitly.");
    process.exit(1);
  }
}

const project =
  saved.project ??
  JSON.parse(readFileSync(join(here, "..", ".firebaserc"), "utf8")).projects
    .default;
const url = args.url ?? `http://127.0.0.1:15002/${project}/us-central1/sos`;

// Step 7: the small JSON message the ESP32 prepares.
const payload = {
  deviceId: args.device ?? saved.deviceId,
  secretToken: args.secret ?? saved.secretToken,
  type: args.type,
  timestamp: new Date().toISOString(),
  lat: Number(args.lat),
  lng: Number(args.lng),
  battery: Number(args.battery),
};

console.log("🔘 SOS button held 3s … buzzer ♪ + vibration bzzz (local confirmation)");
console.log(`📡 GPS fix: ${payload.lat}, ${payload.lng} | battery ${payload.battery}%`);
console.log(`🔐 POST ${url}  (device ${payload.deviceId})`);

// Step 8: send it.
const res = await fetch(url, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify(payload),
});
const text = await res.text();

if (res.ok) {
  console.log(`✅ Backend accepted SOS (${res.status}): ${text}`);
} else {
  console.error(`❌ Backend rejected SOS (${res.status}): ${text}`);
  process.exit(1);
}
