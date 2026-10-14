import { createInterface } from "node:readline/promises";
import { hashPassword } from "./secrets.ts";

/** Хеш пароля админки для ADMIN_PASSWORD_HASH. Пароль читается из stdin,
 *  чтобы не оставаться в истории оболочки. */
const rl = createInterface({ input: process.stdin, output: process.stderr });
const password = (await rl.question("Пароль админки: ")).trim();
rl.close();
if (password.length < 12) {
  console.error("Нужно не меньше 12 символов.");
  process.exit(1);
}
console.log(await hashPassword(password));
