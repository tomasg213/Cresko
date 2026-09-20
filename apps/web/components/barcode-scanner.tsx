"use client";

import { useEffect, useRef, useState } from "react";
import { BrowserMultiFormatReader } from "@zxing/library";

import { Button, Modal } from "@/components/ui";

export default function BarcodeScannerModal({
  onDetected,
  onClose,
}: {
  onDetected: (code: string) => void;
  onClose: () => void;
}) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const handledRef = useRef(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    const reader = new BrowserMultiFormatReader();
    let cancelled = false;

    async function start() {
      try {
        await reader.decodeFromVideoDevice(null, video, (result) => {
          if (result && !handledRef.current) {
            handledRef.current = true;
            reader.reset();
            onDetected(result.getText().trim());
          }
        });
      } catch (err) {
        if (!cancelled) {
          setError(
            err instanceof DOMException && err.name === "NotAllowedError"
              ? "Permiso de cámara denegado. Habilítalo en el navegador e intenta de nuevo."
              : "No se pudo acceder a la cámara del dispositivo.",
          );
        }
      }
    }

    void start();
    return () => {
      cancelled = true;
      reader.reset();
    };
  }, [onDetected]);

  return (
    <Modal title="Escanear código de barras" onClose={onClose}>
      <div className="space-y-4">
        {error ? (
          <p className="text-sm text-red-600">{error}</p>
        ) : (
          <video
            ref={videoRef}
            muted
            playsInline
            className="w-full rounded-lg border border-slate-200 bg-black dark:border-slate-700"
          />
        )}
        <p className="text-sm text-slate-500 dark:text-slate-400">
          Apunta la cámara al código de barras. Se detecta automáticamente.
        </p>
        <div className="flex justify-end">
          <Button type="button" variant="secondary" onClick={onClose}>
            Cerrar
          </Button>
        </div>
      </div>
    </Modal>
  );
}