import { NextRequest, NextResponse } from "next/server";
import { SESSION_COOKIE } from "@/lib/adminSession";

export async function POST(req: NextRequest) {
  const res = NextResponse.redirect(new URL("/", req.url), 303);
  res.cookies.set(SESSION_COOKIE, "", { httpOnly: true, path: "/", maxAge: 0 });
  return res;
}
