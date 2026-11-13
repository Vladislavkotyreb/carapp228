import assert from "node:assert/strict";
import { test } from "node:test";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { migrate, openPglite } from "../src/db.ts";

test("миграции пропускают AppleDouble и применяют SQL только один раз", async () => {
  const folder = await mkdtemp(join(tmpdir(), "beepy-migrations-"));
  const db = await openPglite();
  try {
    await writeFile(join(folder, "._001_fixture.sql"), Buffer.from([0, 5, 22, 7, 0]));
    await writeFile(join(folder, "001_fixture.sql"), "create table fixture (id int primary key); insert into fixture values (1);");
    const url = pathToFileURL(folder + "/");
    assert.deepEqual(await migrate(db, url), ["001_fixture.sql"]);
    assert.deepEqual(await migrate(db, url), []);
    assert.deepEqual(await db.query("select * from fixture"), [{ id: 1 }]);
  } finally {
    await db.close();
    await rm(folder, { recursive: true, force: true });
  }
});
