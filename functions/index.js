/* eslint-disable */
const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

/** ---------- Helpers ---------- */
const DAY_MS = 86400000;

const startOfDay = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate());
const pad = (n) => String(n).padStart(2, "0");
const ymd = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

function extractExpiryDate(data) {
  if (data.expiry_ts && typeof data.expiry_ts.toDate === "function") {
    return data.expiry_ts.toDate();
  }
  if (typeof data.expiry_date === "string") {
    const t = Date.parse(data.expiry_date);
    if (!Number.isNaN(t)) return new Date(t);
  }
  return null;
}

function daysLeftFromNow(expiryDate) {
  const today = startOfDay(new Date());
  const exp = startOfDay(expiryDate);
  return Math.ceil((exp - today) / DAY_MS);
}

// cache: familyId -> [uids]
const familyMembersCache = new Map();
async function getMemberUidsOfFamily(familyId) {
  if (familyMembersCache.has(familyId)) return familyMembersCache.get(familyId);
  const snap = await db.collection("users").where("familyId", "==", familyId).get();
  const uids = snap.docs.map((d) => d.id);
  familyMembersCache.set(familyId, uids);
  return uids;
}

function makeNotiId({ toUid, refPath, daysLeft }) {
  const safePath = refPath.replace(/\//g, "_");
  return `${toUid}_${safePath}_D${daysLeft}`;
}

function levelFromDaysLeft(daysLeft) {
  switch (daysLeft) {
    case 0:
      return "today";
    case 1:
      return "in_1";
    case 2:
      return "in_2";
    case 3:
      return "in_3";
    default:
      return "info";
  }
}

async function collectUserTokens(uid) {
  const colSnap = await db.collection("user_tokens").doc(uid).collection("tokens").get();
  const collectionTokens = new Set(colSnap.docs.map((d) => d.id).filter((t) => !!t));

  const userDoc = await db.collection("users").doc(uid).get();
  const mapTokens = new Set();
  if (userDoc.exists) {
    const raw = userDoc.data().fcmTokens || {};
    Object.keys(raw || {}).forEach((token) => {
      if (token) mapTokens.add(token);
    });
  }

  const all = new Set([...collectionTokens, ...mapTokens]);

  return {
    tokens: Array.from(all),
    collectionTokens,
    mapTokens,
  };
}

/** ---------- FCM: send push to all tokens of a user ---------- */
async function sendPushToUser({ uid, title, body, data = {} }) {
  const tokenInfo = await collectUserTokens(uid);
  const tokens = tokenInfo.tokens;
  if (!tokens.length) return;

  // Note: for iOS, notification keys show full banner while data-only requires client handling
  const message = {
    tokens,
    notification: { title, body },
    data, // strings only
    android: {
      notification: {
        // channelId: 'expiry_alerts', // ถ้าตั้ง channel ฝั่งแอป
        priority: 'HIGH',
        // icon: 'ic_notification',  // ถ้ามีไอคอน custom
      },
      ttl: 3600 * 1000, // 1 ชม.
    },
    apns: {
      headers: { 'apns-priority': '10' },
      payload: {
        aps: { sound: 'default', contentAvailable: true },
      },
    },
  };

  const res = await admin.messaging().sendEachForMulticast(message);
  // ลบ token เสีย
  const deletions = [];
  const userDocRef = db.collection("users").doc(uid);
  res.responses.forEach((r, idx) => {
    if (!r.success) {
      const err = r.error?.code || '';
      if (['messaging/registration-token-not-registered', 'messaging/invalid-argument'].includes(err)) {
        const dead = tokens[idx];
        if (tokenInfo.collectionTokens.has(dead)) {
          deletions.push(
            db.collection("user_tokens").doc(uid).collection("tokens").doc(dead).delete().catch(() => null)
          );
        }
        if (tokenInfo.mapTokens.has(dead)) {
          deletions.push(
            userDocRef.update({ [`fcmTokens.${dead}`]: admin.firestore.FieldValue.delete() }).catch(() => null)
          );
        }
      }
    }
  });
  if (deletions.length) await Promise.all(deletions);
}

/** ---------- Create/Update notification doc + FCM ---------- */
async function upsertNotification({ toUid, familyId, itemDocPath, itemName, daysLeft, expiryDate }) {
  const id = makeNotiId({ toUid, refPath: itemDocPath, daysLeft });
  const ref = db.collection("notifications").doc(familyId).collection("items").doc(id);
  const existing = await ref.get();

  const title = "วัตถุดิบใกล้หมดอายุ";
  const body = `${itemName || "วัตถุดิบ"} จะหมดอายุในอีก ${daysLeft} วัน (หมดอายุ ${ymd(expiryDate)})`;
  const now = admin.firestore.Timestamp.now();
  const payload = {
    toUid,
    familyId,
    type: "expiry_countdown",
    title,
    body,
    level: levelFromDaysLeft(daysLeft),
    daysLeft,
    refPath: itemDocPath, // users/{uid}/raw_materials/{itemId}
    expiresOn: admin.firestore.Timestamp.fromDate(expiryDate),
    updatedAt: now,
  };

  if (!existing.exists) {
    payload.createdAt = now;
    payload.read = false;
  }

  await ref.set(payload, { merge: true });

  // ส่ง Push (FCM)
  await sendPushToUser({
    uid: toUid,
    title,
    body,
    data: {
      type: "expiry_countdown",
      daysLeft: String(daysLeft),
      refPath: itemDocPath,
      familyId,
      notificationId: id,
    },
  });
}

/** ---------- Core Logic: run once ---------- */
async function runDailyExpiryCountdownOnce() {
  const now = new Date();
  const todayStart = startOfDay(now);
  const threeDaysAhead = new Date(todayStart.getTime() + (3 * DAY_MS));

  const candidates = [];

  // A) มี expiry_ts → query ช่วงตรง
  const qA = await db.collectionGroup("raw_materials")
    .where("expiry_ts", ">=", admin.firestore.Timestamp.fromDate(todayStart))
    .where("expiry_ts", "<=", admin.firestore.Timestamp.fromDate(threeDaysAhead))
    .get();
  qA.forEach((doc) => candidates.push(doc));

  // B) เอกสารเก่าที่ไม่มี expiry_ts → fallback จาก expiry_date (จำกัดชุดล่าสุด)
  const qB = await db.collectionGroup("raw_materials")
    .orderBy("created_at", "desc")
    .limit(2000)
    .get();
  qB.forEach((doc) => {
    const d = doc.data();
    if (!d.expiry_ts && d.expiry_date) candidates.push(doc);
  });

  const tasks = [];

  for (const doc of candidates) {
    const data = doc.data();

    const expiryDate = extractExpiryDate(data);
    if (!expiryDate) continue;

    const daysLeft = daysLeftFromNow(expiryDate);
    if (![3, 2, 1].includes(daysLeft)) continue; // แจ้งเฉพาะ D-3/D-2/D-1

    const quantity = Number(data.quantity ?? 0);
    if (!(quantity > 0)) continue;               // ปริมาณต้อง > 0

    if (startOfDay(expiryDate) < todayStart) continue; // หมดแล้วไม่แจ้ง

    const familyId = data.familyId;
    if (!familyId) continue;

    const name = data.name || data.name_key || "วัตถุดิบ";
    const path = doc.ref.path;

    tasks.push((async () => {
      const uids = await getMemberUidsOfFamily(familyId);
      const writes = uids.map((uid) =>
        upsertNotification({
          toUid: uid,
          familyId,
          itemDocPath: path,
          itemName: name,
          daysLeft,
          expiryDate,
        })
      );
      await Promise.all(writes);
    })());
  }

  await Promise.all(tasks);
  console.log(`[dailyExpiryCountdown] processed=${candidates.length} at ${new Date().toISOString()}`);
}

/** ---------- Exports ---------- */
// ใช้ตอน deploy จริง (scheduler)
exports.dailyExpiryCountdown = functions
  .region("asia-southeast1")
  .pubsub.schedule("0 9 * * *")
  .timeZone("Asia/Bangkok")
  .onRun(async () => {
    await runDailyExpiryCountdownOnce();
    return null;
  });

exports.pushExpirySample = functions
  .region("asia-southeast1")
  .https.onCall(async (data, context) => {
    const callerUid = context.auth?.uid;
    if (!callerUid) {
      throw new functions.https.HttpsError("unauthenticated", "ต้องเข้าสู่ระบบก่อนเรียกใช้งาน");
    }

    const familyId = typeof data.familyId === "string" ? data.familyId.trim() : "";
    if (!familyId) {
      throw new functions.https.HttpsError("invalid-argument", "ต้องระบุ familyId");
    }

    const members = await getMemberUidsOfFamily(familyId);
    if (!members.includes(callerUid)) {
      throw new functions.https.HttpsError("permission-denied", "คุณไม่ใช่สมาชิกของครอบครัวนี้");
    }

    const rawDaysLeft = Number.isFinite(Number(data.daysLeft))
      ? Number(data.daysLeft)
      : 2;
    const daysLeft = [1, 2, 3].includes(rawDaysLeft) ? rawDaysLeft : 2;

    const expiryDate = new Date();
    expiryDate.setDate(expiryDate.getDate() + daysLeft);

    const itemName = typeof data.itemName === "string" && data.itemName.trim()
      ? data.itemName.trim()
      : "ตัวอย่างวัตถุดิบ";
    const refPath = `families/${familyId}/samples/${Date.now()}`;

    await Promise.all(members.map((targetUid) =>
      upsertNotification({
        toUid: targetUid,
        familyId,
        itemDocPath: refPath,
        itemName,
        daysLeft,
        expiryDate,
      })
    ));

    return {
      ok: true,
      familyId,
      daysLeft,
      recipients: members.length,
    };
  });

// ใช้ทดสอบบน Emulator (HTTP)
exports.dailyExpiryCountdownDev = functions
  .region("asia-southeast1")
  .https.onRequest(async (req, res) => {
    try {
      await runDailyExpiryCountdownOnce();
      res.status(200).send("OK: ran dailyExpiryCountdown once (emulator)");
    } catch (e) {
      console.error(e);
      res.status(500).send(String(e));
    }
  });
