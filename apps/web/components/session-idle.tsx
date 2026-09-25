"use client";

import { useEffect, useRef } from "react";

import { redirectToLogin } from "@/lib/api";
import { createClient } from "@/lib/supabase/client";

const IDLE_MS = 24 * 60 * 60 * 1000; // 24 horas
const CHECK_MS = 60 * 1000; // revisar cada minuto

const EVENTS = [
  "mousemove",
  "mousedown",
  "keydown",
  "touchstart",
  "scroll",
] as const;

function lastActivity(): number {
  const stored = window.localStorage.getItem("cresko.last-activity");
  return stored ? Number(stored) : Date.now();
}

function touch() {
  window.localStorage.setItem("cresko.last-activity", String(Date.now()));
}

export function SessionIdle() {
  const timer = useRef<number | null>(null);

  useEffect(() => {
    touch();
    EVENTS.forEach((event) => window.addEventListener(event, touch));

    const check = () => {
      const elapsed = Date.now() - lastActivity();
      if (elapsed >= IDLE_MS) {
        const supabase = createClient();
        void redirectToLogin(supabase);
      }
    };
    timer.current = window.setInterval(check, CHECK_MS);

    return () => {
      EVENTS.forEach((event) => window.removeEventListener(event, touch));
      if (timer.current !== null) window.clearInterval(timer.current);
    };
  }, []);

  return null;
}
