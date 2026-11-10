/**
 * TruePath backend.
 *
 * Production endpoints (HTTPS, JSON):
 *  - POST /sos    : cane sends an SOS -> verify device secret, store alert,
 *                   push to all caregivers (doc steps 9-13).
 *  - POST /claim  : signed-in user claims a brand-new cane with its one-time
 *                   pairing code -> becomes immutable owner + first/primary
 *                   caregiver.
 *  - POST /manage : owner or primary caregiver manages a cane: add/remove
 *                   caregivers, transfer primary, link/unlink the cane user's
 *                   account, rename the cane.
 *
 * Dev/ops endpoints (emulator-only, or admin for provision):
 *  - POST /provision : "factory" - creates a cane: device secret (for the
 *                      ESP32) + one-time claim code (for the box QR).
 *  - POST /setAdmin  : grants/revokes the admin custom claim by email.
 *  - POST /seed      : demo data (demo caregiver owning cane-001).
 */
const { onRequest } = require("firebase-functions/v2/https");
const { logger } = require("firebase-functions");
const admin = require("firebase-admin");
const { FieldValue, GeoPoint, Timestamp } = require("firebase-admin/firestore");
const crypto = require("node:crypto");

admin.initializeApp();
const db = admin.firestore();

const REGION = "us-central1";
const sha256 = (s) => crypto.createHash("sha256").update(s, "utf8").digest("hex");

function timingSafeEqualHex(a, b) {
  const ba = Buffer.from(a || "", "hex");
  const bb = Buffer.from(b || "", "hex");
  return ba.length === bb.length && ba.length > 0 && crypto.timingSafeEqual(ba, bb);
}

const inEmulator = () => process.env.FUNCTIONS_EMULATOR === "true";

/** Verifies the Firebase ID token in the Authorization header. */
async function requireUser(req, res) {
  const match = (req.headers.authorization || "").match(/^Bearer (.+)$/);
  if (!match) {
    res.status(401).json({ error: "missing Authorization: Bearer <idToken>" });
    return null;
  }
  try {
    return await admin.auth().verifyIdToken(match[1]);
  } catch {
    res.status(401).json({ error: "invalid or expired auth token" });
    return null;
  }
}

function postOnly(req, res) {
  if (req.method === "POST") return true;
  res.status(405).json({ error: "POST only" });
  return false;
}

/** Owner and primary caregiver may manage a cane. */
const canManage = (device, uid) =>
  device.ownerUid === uid || device.primaryCaregiverUid === uid;

/** Display info for the members map on the device doc. */
async function memberInfo(uid) {
  const [userDoc, authUser] = await Promise.all([
    db.collection("users").doc(uid).get(),
    admin.auth().getUser(uid).catch(() => null),
  ]);
  return {
    name: userDoc.data()?.name || authUser?.displayName || authUser?.email || uid,
    email: userDoc.data()?.email || authUser?.email || null,
  };
}

/* ------------------------------------------------------------------ SOS */

exports.sos = onRequest({ region: REGION, cors: true }, async (req, res) => {
  if (!postOnly(req, res)) return;
  const { deviceId, secretToken, type, timestamp, lat, lng, battery } = req.body || {};

  const bad = (msg) => res.status(400).json({ error: msg });
  if (typeof deviceId !== "string" || !deviceId) return bad("deviceId required");
  if (typeof secretToken !== "string" || !secretToken) return bad("secretToken required");
  if (typeof type !== "string" || !type) return bad("type required (e.g. 'sos')");
  if (typeof lat !== "number" || lat < -90 || lat > 90) return bad("lat must be a number in [-90, 90]");
  if (typeof lng !== "number" || lng < -180 || lng > 180) return bad("lng must be a number in [-180, 180]");
  if (typeof battery !== "number" || battery < 0 || battery > 100) return bad("battery must be 0-100");
  const sentAt = timestamp ? new Date(timestamp) : new Date();
  if (Number.isNaN(sentAt.getTime())) return bad("timestamp must be ISO 8601");

  // Verify the device (doc step 10).
  const deviceRef = db.collection("devices").doc(deviceId);
  const deviceSnap = await deviceRef.get();
  if (!deviceSnap.exists) {
    logger.warn("SOS from unknown device", { deviceId });
    res.status(401).json({ error: "unknown device" });
    return;
  }
  const device = deviceSnap.data();
  if (!timingSafeEqualHex(sha256(secretToken), device.secretHash)) {
    logger.warn("SOS with bad secret", { deviceId });
    res.status(401).json({ error: "invalid device credentials" });
    return;
  }
  if (device.status !== "active") {
    res.status(409).json({ error: "cane has not been claimed/activated yet" });
    return;
  }

  const { alertId, pushSent } = await fireAlert(deviceRef, device, {
    type, sentAt, lat, lng, battery, simulated: false,
  });
  res.status(201).json({ ok: true, alertId, pushSent });
});

/**
 * Shared alert pipeline (doc steps 11-13): store the alert, update the
 * device, push to every caregiver's phones, prune dead tokens. Used by the
 * real /sos and the admin /mockSos.
 */
async function fireAlert(deviceRef, device, { type, sentAt, lat, lng, battery, simulated }) {
  const deviceId = deviceRef.id;
  const caregiverUids = device.caregiverUids || [];
  const memberUids = [...new Set([...caregiverUids, device.caneUserUid].filter(Boolean))];

  // Store the alert (doc step 11).
  const alertRef = await db.collection("alerts").add({
    deviceId,
    deviceName: device.name || deviceId,
    caregiverUids,
    memberUids,
    type,
    status: "active",
    location: new GeoPoint(lat, lng),
    battery,
    simulated: !!simulated,
    sentAt: Timestamp.fromDate(sentAt),
    createdAt: FieldValue.serverTimestamp(),
    resolvedAt: null,
    resolvedBy: null,
  });
  await deviceRef.update({ battery, lastSeenAt: FieldValue.serverTimestamp() });

  // Push to every caregiver's devices (doc steps 12-13).
  let sent = 0;
  if (caregiverUids.length > 0) {
    const userSnaps = await db.getAll(
      ...caregiverUids.map((u) => db.collection("users").doc(u))
    );
    const tokens = [];
    const tokenOwner = new Map();
    for (const snap of userSnaps) {
      for (const t of snap.data()?.fcmTokens || []) {
        if (!tokenOwner.has(t)) {
          tokenOwner.set(t, snap.ref);
          tokens.push(t);
        }
      }
    }
    if (tokens.length > 0) {
      const result = await admin.messaging().sendEachForMulticast({
        tokens,
        notification: {
          title: simulated ? "🧪 TruePath SOS (test)" : "🆘 TruePath SOS",
          body: `${device.name || deviceId} may need help — tap to see their location`,
        },
        data: {
          alertId: alertRef.id,
          deviceId,
          type,
          lat: String(lat),
          lng: String(lng),
          battery: String(battery),
        },
        android: {
          priority: "high",
          notification: { channelId: "sos_alerts", priority: "max", sound: "default" },
        },
        apns: {
          headers: { "apns-priority": "10" },
          payload: { aps: { sound: "default" } },
        },
      });
      sent = result.successCount;
      const deadByRef = new Map();
      result.responses.forEach((r, i) => {
        const code = r.error?.code || "";
        if (code.includes("registration-token-not-registered") || code.includes("invalid-argument")) {
          const ref = tokenOwner.get(tokens[i]);
          deadByRef.set(ref, [...(deadByRef.get(ref) || []), tokens[i]]);
        }
      });
      await Promise.all(
        [...deadByRef].map(([ref, dead]) =>
          ref.update({ fcmTokens: FieldValue.arrayRemove(...dead) })
        )
      );
    } else {
      logger.warn("No FCM tokens among caregivers", { deviceId });
    }
  }

  logger.info("SOS stored", { alertId: alertRef.id, deviceId, pushSent: sent, simulated: !!simulated });
  return { alertId: alertRef.id, pushSent: sent };
}

/**
 * Admin-only demo trigger: fires the full SOS pipeline for a cane WITHOUT
 * the device secret (ID token + admin claim instead). Alerts are marked
 * `simulated: true` and the push title says "(test)".
 * Body: { deviceId, lat?, lng?, battery? }
 */
exports.mockSos = onRequest({ region: REGION, cors: true }, async (req, res) => {
  if (!postOnly(req, res)) return;
  const user = await requireUser(req, res);
  if (!user) return;
  if (user.admin !== true) {
    res.status(403).json({ error: "admin only" });
    return;
  }

  const { deviceId, lat, lng, battery } = req.body || {};
  if (typeof deviceId !== "string" || !deviceId) {
    res.status(400).json({ error: "deviceId required" });
    return;
  }
  const deviceRef = db.collection("devices").doc(deviceId);
  const deviceSnap = await deviceRef.get();
  if (!deviceSnap.exists) {
    res.status(404).json({ error: "no such cane" });
    return;
  }
  const device = deviceSnap.data();
  if (device.status !== "active") {
    res.status(409).json({ error: "cane has not been claimed/activated yet" });
    return;
  }

  // Defaults: near Marine Drive, Kochi with a little jitter; keep last battery.
  const jitter = () => (Math.random() - 0.5) * 0.004;
  const { alertId, pushSent } = await fireAlert(deviceRef, device, {
    type: "sos",
    sentAt: new Date(),
    lat: typeof lat === "number" ? lat : 9.9816 + jitter(),
    lng: typeof lng === "number" ? lng : 76.2999 + jitter(),
    battery: typeof battery === "number" ? battery : device.battery ?? 80,
    simulated: true,
  });
  res.status(201).json({ ok: true, alertId, pushSent });
});

/* ---------------------------------------------------------------- claim */

/**
 * Body: { code: "TP-<deviceId>-<pairCode>" }  (or { deviceId, pairCode }).
 * The caller becomes the immutable owner and the first/primary caregiver.
 */
exports.claim = onRequest({ region: REGION, cors: true }, async (req, res) => {
  if (!postOnly(req, res)) return;
  const user = await requireUser(req, res);
  if (!user) return;

  let { deviceId, pairCode, code } = req.body || {};
  if (typeof code === "string") {
    const m = code.trim().match(/^TP-(.+)-([a-f0-9]{10})$/i);
    if (!m) {
      res.status(400).json({ error: "invalid code format (expected TP-<cane id>-<code>)" });
      return;
    }
    deviceId = m[1];
    pairCode = m[2].toLowerCase();
  }
  if (!deviceId || !pairCode) {
    res.status(400).json({ error: "code (or deviceId + pairCode) required" });
    return;
  }

  const info = await memberInfo(user.uid);
  const deviceRef = db.collection("devices").doc(deviceId);
  try {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(deviceRef);
      if (!snap.exists) throw { status: 404, msg: "no such cane" };
      const device = snap.data();
      if (device.ownerUid || device.status !== "provisioned") {
        throw { status: 409, msg: "this cane has already been claimed" };
      }
      if (!timingSafeEqualHex(sha256(pairCode), device.pairCodeHash)) {
        throw { status: 401, msg: "wrong pairing code" };
      }
      tx.update(deviceRef, {
        status: "active",
        ownerUid: user.uid,
        primaryCaregiverUid: user.uid,
        caregiverUids: [user.uid],
        caneUserUid: null,
        members: { [user.uid]: info },
        claimedAt: FieldValue.serverTimestamp(),
        pairCodeHash: FieldValue.delete(), // one-time: can never be claimed again
      });
    });
  } catch (e) {
    if (e.status) {
      res.status(e.status).json({ error: e.msg });
      return;
    }
    throw e;
  }
  logger.info("Cane claimed", { deviceId, ownerUid: user.uid });
  res.json({ ok: true, deviceId });
});

/* --------------------------------------------------------------- manage */

/**
 * Body: { deviceId, action, email?, uid?, name? }
 * Actions: addCaregiver(email) | removeCaregiver(uid|email) |
 *          setPrimaryCaregiver(uid|email) | linkCaneUser(email) |
 *          unlinkCaneUser | setName(name)
 * Allowed for the cane's owner or primary caregiver.
 */
exports.manage = onRequest({ region: REGION, cors: true }, async (req, res) => {
  if (!postOnly(req, res)) return;
  const user = await requireUser(req, res);
  if (!user) return;

  const { deviceId, action, email, uid, name } = req.body || {};
  if (!deviceId || !action) {
    res.status(400).json({ error: "deviceId and action required" });
    return;
  }

  // Resolve the target account (by email or uid) when the action needs one.
  let target = null;
  if (["addCaregiver", "removeCaregiver", "setPrimaryCaregiver", "linkCaneUser"].includes(action)) {
    try {
      const authUser = email
        ? await admin.auth().getUserByEmail(String(email).trim().toLowerCase())
        : await admin.auth().getUser(uid);
      target = { uid: authUser.uid, info: await memberInfo(authUser.uid) };
    } catch {
      res.status(404).json({ error: "no TruePath account with that email" });
      return;
    }
  }

  const deviceRef = db.collection("devices").doc(deviceId);
  try {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(deviceRef);
      if (!snap.exists) throw { status: 404, msg: "no such cane" };
      const d = snap.data();
      if (!canManage(d, user.uid)) {
        throw { status: 403, msg: "only the owner or primary caregiver can manage this cane" };
      }

      let caregiverUids = [...(d.caregiverUids || [])];
      let primaryCaregiverUid = d.primaryCaregiverUid;
      let caneUserUid = d.caneUserUid ?? null;
      const members = { ...(d.members || {}) };
      const update = {};

      switch (action) {
        case "addCaregiver":
          if (!caregiverUids.includes(target.uid)) caregiverUids.push(target.uid);
          members[target.uid] = target.info;
          break;
        case "removeCaregiver":
          if (target.uid === d.ownerUid) throw { status: 400, msg: "the owner cannot be removed" };
          caregiverUids = caregiverUids.filter((u) => u !== target.uid);
          if (primaryCaregiverUid === target.uid) primaryCaregiverUid = d.ownerUid;
          break;
        case "setPrimaryCaregiver":
          if (!caregiverUids.includes(target.uid)) {
            throw { status: 400, msg: "that account is not a caregiver of this cane" };
          }
          primaryCaregiverUid = target.uid;
          break;
        case "linkCaneUser":
          caneUserUid = target.uid;
          members[target.uid] = target.info;
          break;
        case "unlinkCaneUser":
          caneUserUid = null;
          break;
        case "setName":
          if (typeof name !== "string" || !name.trim()) throw { status: 400, msg: "name required" };
          update.name = name.trim();
          break;
        default:
          throw { status: 400, msg: "unknown action '" + action + "'" };
      }

      // Keep the members map limited to people actually on the cane.
      const keep = new Set([d.ownerUid, caneUserUid, ...caregiverUids].filter(Boolean));
      for (const k of Object.keys(members)) if (!keep.has(k)) delete members[k];

      tx.update(deviceRef, {
        ...update,
        caregiverUids,
        primaryCaregiverUid,
        caneUserUid,
        members,
      });
    });
  } catch (e) {
    if (e.status) {
      res.status(e.status).json({ error: e.msg });
      return;
    }
    throw e;
  }
  logger.info("Cane managed", { deviceId, action, by: user.uid });
  res.json({ ok: true });
});

/* -------------------------------------------------------- registerToken */

/**
 * Claims an FCM token for the signed-in account. A phone's token must belong
 * to exactly ONE user: if another account still holds it (e.g. someone signed
 * out and a different person signed in on the same phone), it is removed
 * there — otherwise the phone would keep receiving the old account's alerts
 * it can no longer read.
 * Body: { token }
 */
exports.registerToken = onRequest({ region: REGION, cors: true }, async (req, res) => {
  if (!postOnly(req, res)) return;
  const user = await requireUser(req, res);
  if (!user) return;
  const { token } = req.body || {};
  if (typeof token !== "string" || !token) {
    res.status(400).json({ error: "token required" });
    return;
  }

  const holders = await db
    .collection("users")
    .where("fcmTokens", "array-contains", token)
    .get();
  await Promise.all(
    holders.docs
      .filter((d) => d.id !== user.uid)
      .map((d) => d.ref.update({ fcmTokens: FieldValue.arrayRemove(token) }))
  );
  await db.collection("users").doc(user.uid).set(
    { fcmTokens: FieldValue.arrayUnion(token) },
    { merge: true }
  );
  res.json({ ok: true });
});

/* ------------------------------------------------------------ provision */

/**
 * The "factory": creates a new cane. Emulator-only, or an admin account in
 * production. Returns the device secret (goes into the ESP32) and the
 * one-time claim code (goes on the box as a QR).
 */
exports.provision = onRequest({ region: REGION, cors: true }, async (req, res) => {
  if (!postOnly(req, res)) return;
  if (!inEmulator()) {
    const user = await requireUser(req, res);
    if (!user) return;
    if (user.admin !== true) {
      res.status(403).json({ error: "admin only" });
      return;
    }
  }
  const deviceId = "cane-" + crypto.randomBytes(3).toString("hex");
  const secretToken = crypto.randomBytes(24).toString("base64url");
  const pairCode = crypto.randomBytes(5).toString("hex");
  await db.collection("devices").doc(deviceId).set({
    name: (req.body?.name || "").trim() || deviceId,
    status: "provisioned",
    secretHash: sha256(secretToken),
    pairCodeHash: sha256(pairCode),
    ownerUid: null,
    caneUserUid: null,
    primaryCaregiverUid: null,
    caregiverUids: [],
    members: {},
    battery: null,
    provisionedAt: FieldValue.serverTimestamp(),
  });
  res.status(201).json({
    ok: true,
    deviceId,
    secretToken,
    claimCode: "TP-" + deviceId + "-" + pairCode,
  });
});

/* -------------------------------------------------------------- setAdmin */

exports.setAdmin = onRequest({ region: REGION }, async (req, res) => {
  if (!postOnly(req, res)) return;
  if (!inEmulator()) {
    res.status(403).json({ error: "emulator-only" });
    return;
  }
  const { email, admin: makeAdmin = true } = req.body || {};
  try {
    const user = await admin.auth().getUserByEmail(String(email).trim().toLowerCase());
    await admin.auth().setCustomUserClaims(user.uid, { admin: !!makeAdmin });
    await db.collection("users").doc(user.uid).set({ isAdmin: !!makeAdmin }, { merge: true });
    res.json({ ok: true, uid: user.uid, admin: !!makeAdmin });
  } catch {
    res.status(404).json({ error: "no account with that email" });
  }
});

/* ------------------------------------------------------------------ seed */

/** Demo data: demo caregiver owning cane-001 (claimed). Emulator-only. */
exports.seed = onRequest({ region: REGION }, async (req, res) => {
  if (!inEmulator()) {
    res.status(403).json({ error: "seed is emulator-only" });
    return;
  }
  const email = "demo@truepath.app";
  const password = "Truepath!demo1";
  const deviceId = "cane-001";

  let user;
  try {
    try {
      user = await admin.auth().getUserByEmail(email);
    } catch (e) {
      if (e.errorInfo?.code === "auth/configuration-not-found") throw e;
      user = await admin.auth().createUser({ email, password, displayName: "Demo Caregiver" });
    }
  } catch (e) {
    if (e.errorInfo?.code === "auth/configuration-not-found") {
      res.status(503).json({
        error:
          "Firebase Authentication is not set up yet. In the Firebase console, " +
          "open Authentication -> Get started -> enable Email/Password, then re-run the seed.",
      });
      return;
    }
    throw e;
  }

  await db.collection("users").doc(user.uid).set(
    { name: "Demo Caregiver", email },
    { merge: true }
  );

  // Remove this device's previous alerts so the demo starts clean.
  const old = await db.collection("alerts").where("deviceId", "==", deviceId).get();
  if (!old.empty) {
    const batch = db.batch();
    old.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
  }

  const secret = crypto.randomBytes(24).toString("base64url");
  await db.collection("devices").doc(deviceId).set({
    name: "Srehari's cane",
    status: "active",
    secretHash: sha256(secret),
    ownerUid: user.uid,
    caneUserUid: null,
    primaryCaregiverUid: user.uid,
    caregiverUids: [user.uid],
    members: { [user.uid]: { name: "Demo Caregiver", email } },
    battery: 100,
    provisionedAt: FieldValue.serverTimestamp(),
    claimedAt: FieldValue.serverTimestamp(),
  });

  res.json({
    ok: true,
    caregiver: { email, password, uid: user.uid },
    device: { deviceId, secretToken: secret },
  });
});
