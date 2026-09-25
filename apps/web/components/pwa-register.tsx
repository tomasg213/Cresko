"use client";

import { useEffect } from "react";

export function PwaRegister() {
  useEffect(() => {
    if (!("serviceWorker" in navigator)) return;

    if (process.env.NODE_ENV !== "production") {
      // En desarrollo no hay PWA. Eliminar cualquier service worker viejo
      // que quedó de un build de producción para evitar precache obsoleto.
      navigator.serviceWorker.getRegistrations().then((registrations) => {
        for (const registration of registrations) {
          void registration.unregister();
        }
      });
      return;
    }

    navigator.serviceWorker.register("/sw.js").catch(() => {
      // La instalación de la PWA sigue disponible aunque el worker falle.
    });
  }, []);

  return null;
}
