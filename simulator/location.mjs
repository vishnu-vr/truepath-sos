#!/usr/bin/env node
/**
 * TruePath cane heartbeat simulator: stands in for the ESP32's periodic
 * location + battery report.
 *
 * Firmware behaviour this mirrors:
 *   - Every few minutes (e.g. 2-5 min while moving, longer when still, to
 *     save battery), read the GPS fix and the battery level.
 *   - If there is no GPS fix (indoors), skip the send rather than report a
 *     stale or zero position.
 *   - POST { deviceId, secretToken, lat, lng, battery, timestamp } to
 *     /location over HTTPS, using the same device secret as the SOS.
 *
 * Usage:
 *   node simulator/location.mjs --cane cane-255fde                 # one ping
 *   node simulator/location.mjs --cane cane-255fde --lat 9.97 --lng 76.28 --battery 55
 *   node simulator/location.mjs --cane cane-255fde --walk          # moving demo
 *   node simulator/location.mjs ... --url https://us-central1-truepath-sos-2611.cloudfunctions.net/location
 */
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

const here = dirname(fileURLToPath(import.meta.url));

const { values: args } = parseArgs({
  options: {
    cane: { type: "string" },
    lat: { type: "string" },
    lng: { type: "string" },
    battery: { type: "string", default: "78" },
    walk: { type: "boolean", default: false },
    interval: { type: "string", default: "3" }, // seconds between walk pings
    url: { type: "string" },
  },
});

let saved;
const file = join(here, args.cane ? `${args.cane}.json` : "device.json");
try {
  saved = JSON.parse(readFileSync(file, "utf8"));
} catch {
  console.error(`${file} not found. Provision or seed the cane first.`);
  process.exit(1);
}
const url =
  args.url ?? `http://127.0.0.1:15002/${saved.project}/us-central1/location`;

async function ping(lat, lng, battery) {
  const res = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      deviceId: saved.deviceId,
      secretToken: saved.secretToken,
      lat,
      lng,
      battery,
      timestamp: new Date().toISOString(),
    }),
  });
  const text = await res.text();
  const tag = res.ok ? "✅" : "❌";
  console.log(`${tag} ${lat.toFixed(5)}, ${lng.toFixed(5)} | battery ${battery}% → ${res.status} ${text}`);
  if (!res.ok) process.exit(1);
}

// A short walk along Marine Drive, Kochi (waypoints, interpolated below).
const ROUTE = [
  [9.9816, 76.2999],
  [9.9796, 76.2793],
  [9.9768, 76.2785],
  [9.9741, 76.2790],
  [9.9722, 76.2812],
];

function interpolate(route, stepMeters = 25) {
  const pts = [];
  for (let i = 0; i < route.length - 1; i++) {
    const [aLat, aLng] = route[i];
    const [bLat, bLng] = route[i + 1];
    const dLat = (bLat - aLat) * 111_320;
    const dLng = (bLng - aLng) * 111_320 * Math.cos((aLat * Math.PI) / 180);
    const steps = Math.max(1, Math.round(Math.hypot(dLat, dLng) / stepMeters));
    for (let s = 0; s < steps; s++) {
      pts.push([aLat + ((bLat - aLat) * s) / steps, aLng + ((bLng - aLng) * s) / steps]);
    }
  }
  pts.push(route[route.length - 1]);
  return pts;
}

if (args.walk) {
  const pts = interpolate(ROUTE);
  let battery = Number(args.battery);
  console.log(`🚶 Walking ${pts.length} points, one every ${args.interval}s (Ctrl+C to stop)`);
  for (let i = 0; i < pts.length; i++) {
    if (i > 0 && i % 5 === 0) battery = Math.max(0, battery - 1);
    await ping(pts[i][0], pts[i][1], battery);
    if (i < pts.length - 1) {
      await new Promise((r) => setTimeout(r, Number(args.interval) * 1000));
    }
  }
} else {
  await ping(
    Number(args.lat ?? ROUTE[0][0]),
    Number(args.lng ?? ROUTE[0][1]),
    Number(args.battery)
  );
}
