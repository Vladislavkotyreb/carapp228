import { randomUUID } from "node:crypto";
import { CONSENT_VERSION } from "./config.ts";

/** Демо-данные для разработки: три аккаунта с машинами и поездками за две
 *  недели — через настоящий API, как их прислал бы телефон. Только для
 *  локального сервера: на боевой адрес не запускать. */
const base = process.argv[2] ?? "http://127.0.0.1:8787";
if (!/^http:\/\/(127\.0\.0\.1|localhost)(:\d+)?$/.test(base)) {
  console.error("Демо-данные — только для локального сервера.");
  process.exit(1);
}

const fleets = [
  [{ name: "Mercedes-Benz GL-класс", odometer: 112_421 }],
  [{ name: "KIA Rio", odometer: 64_230 }, { name: "Lada Vesta", odometer: 23_900 }],
  [{ name: "Toyota Camry", odometer: 158_000 }],
];

for (const [n, fleet] of fleets.entries()) {
  const reg = await fetch(`${base}/v1/accounts`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      consentVersion: CONSENT_VERSION,
      device: { model: n === 1 ? "iPhone14,5" : "iPhone16,1", os: "iOS 27.0.1", appVersion: "1.0 (42)" },
    }),
  });
  const { token } = (await reg.json()) as { token: string };
  const cars = fleet.map((c) => ({ id: randomUUID(), ...c, trackedKm: 0, updatedAt: new Date().toISOString(), deleted: false }));
  const trips = [];
  for (let day = 13; day >= 0; day--) {
    const perDay = (day * 7 + n * 3) % 4;
    for (let i = 0; i < perDay; i++) {
      const start = new Date(Date.now() - day * 86_400_000 - (8 + i * 4) * 3_600_000);
      const minutes = 12 + ((day + i) * 11) % 40;
      const meters = minutes * (450 + ((day * 13 + i) % 300));
      trips.push({
        id: randomUUID(),
        carId: cars[(day + i) % cars.length]!.id,
        startedAt: start.toISOString(),
        endedAt: new Date(start.getTime() + minutes * 60_000).toISOString(),
        meters,
        auto: (day + i) % 3 !== 0,
        updatedAt: new Date(start.getTime() + minutes * 60_000).toISOString(),
        deleted: false,
      });
    }
  }
  const res = await fetch(`${base}/v1/sync`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
    body: JSON.stringify({ cursor: null, cars, trips }),
  });
  console.log(`аккаунт ${n + 1}: ${cars.length} машин, ${trips.length} поездок → ${res.status}`);
}
