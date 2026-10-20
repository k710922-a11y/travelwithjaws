// 관리자 로그인 세션 (미들웨어·로그인 처리 공용, Web Crypto 만 사용 → Edge·Node 모두 동작)
// 토큰 = base64url(email) . 만료(초) . HMAC-SHA256(ADMIN_SESSION_SECRET, "email|만료")
// 비밀번호 자체는 어디에도 평문으로 두지 않는다: ADMIN_PASSWORD_HASH="pbkdf2_sha256:<반복>:<salt>:<hash>" (base64url)

export const SESSION_COOKIE = "twj_admin";
export const SESSION_HOURS = 12;

const enc = new TextEncoder();
const b64u = (buf: ArrayBuffer | Uint8Array) => {
  const bytes = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
  let s = ""; for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};
const fromB64u = (s: string) => {
  const t = s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4);
  return Uint8Array.from(atob(t), (c) => c.charCodeAt(0));
};
export function same(a: string, b: string) {
  if (a.length !== b.length) return false;
  let d = 0; for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

export function adminConfig() {
  const email = (process.env.ADMIN_EMAIL ?? "").trim().toLowerCase();
  const hash = (process.env.ADMIN_PASSWORD_HASH ?? "").trim();
  const secret = process.env.ADMIN_SESSION_SECRET ?? "";
  const staff = (process.env.ADMIN_STAFF ?? "").trim() || (process.env.CONSOLE_STAFF ?? "").split(";")[0].split("|")[0].trim();
  const on = !!(email.includes("@") && hash.startsWith("pbkdf2_sha256:") && secret.length >= 32 && staff);
  return { on, email, hash, secret, staff };
}

async function hmac(secret: string, msg: string) {
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return b64u(await crypto.subtle.sign("HMAC", key, enc.encode(msg)));
}

export async function makeSession(email: string, secret: string) {
  const exp = Math.floor(Date.now() / 1000) + SESSION_HOURS * 3600;
  return `${b64u(enc.encode(email))}.${exp}.${await hmac(secret, `${email}|${exp}`)}`;
}

export async function readSession(token: string | undefined, secret: string): Promise<string | null> {
  if (!token || !secret) return null;
  const [e, exp, sig] = token.split(".");
  if (!e || !exp || !sig || !/^\d+$/.test(exp) || Number(exp) < Date.now() / 1000) return null;
  let email = "";
  try { email = new TextDecoder().decode(fromB64u(e)); } catch { return null; }
  return same(sig, await hmac(secret, `${email}|${exp}`)) ? email : null;
}

export async function checkPassword(password: string, stored: string) {
  const [alg, iter, salt, hash] = stored.split(":");
  if (alg !== "pbkdf2_sha256" || !iter || !salt || !hash) return false;
  const key = await crypto.subtle.importKey("raw", enc.encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits({ name: "PBKDF2", hash: "SHA-256", salt: fromB64u(salt), iterations: Number(iter) }, key, 256);
  return same(b64u(bits), hash);
}
