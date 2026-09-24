"use client";

import {
  createContext,
  useCallback,
  useContext,
  useRef,
  useState,
} from "react";

import { Button } from "@/components/ui";

type FeedbackContextValue = {
  confirm: (message: string) => Promise<boolean>;
  notify: (message: string, type?: "success" | "error") => void;
};

const FeedbackContext = createContext<FeedbackContextValue | null>(null);

type ConfirmState = {
  message: string;
  resolve: (value: boolean) => void;
};

type Toast = {
  id: number;
  message: string;
  type: "success" | "error";
};

export function FeedbackProvider({ children }: { children: React.ReactNode }) {
  const [confirmState, setConfirmState] = useState<ConfirmState | null>(null);
  const [toasts, setToasts] = useState<Toast[]>([]);
  const toastId = useRef(0);

  const confirm = useCallback((message: string) => {
    return new Promise<boolean>((resolve) => {
      setConfirmState({ message, resolve });
    });
  }, []);

  const notify = useCallback(
    (message: string, type: "success" | "error" = "error") => {
      const id = ++toastId.current;
      setToasts((current) => [...current, { id, message, type }]);
      window.setTimeout(() => {
        setToasts((current) => current.filter((toast) => toast.id !== id));
      }, 5000);
    },
    [],
  );

  const closeConfirm = (value: boolean) => {
    confirmState?.resolve(value);
    setConfirmState(null);
  };

  return (
    <FeedbackContext.Provider value={{ confirm, notify }}>
      {children}

      {confirmState && (
        <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/40 p-4 sm:py-16">
          <div className="w-full max-w-sm min-w-0 rounded-xl bg-white shadow-xl dark:bg-slate-800">
            <div className="px-6 py-5">
              <h2 className="text-base font-semibold text-slate-900 dark:text-slate-100">
                Confirmar
              </h2>
              <p className="mt-2 text-sm text-slate-600 dark:text-slate-300">
                {confirmState.message}
              </p>
            </div>
            <div className="flex justify-end gap-3 border-t border-slate-200 px-6 py-4 dark:border-slate-700">
              <Button variant="secondary" onClick={() => closeConfirm(false)}>
                Cancelar
              </Button>
              <Button onClick={() => closeConfirm(true)}>Aceptar</Button>
            </div>
          </div>
        </div>
      )}

      <div className="fixed bottom-4 right-4 z-50 flex w-full max-w-sm flex-col gap-2">
        {toasts.map((toast) => (
          <div
            key={toast.id}
            className={`rounded-lg px-4 py-3 text-sm shadow-lg ${
              toast.type === "success"
                ? "bg-green-600 text-white"
                : "bg-red-600 text-white"
            }`}
          >
            {toast.message}
          </div>
        ))}
      </div>
    </FeedbackContext.Provider>
  );
}

export function useFeedback() {
  const ctx = useContext(FeedbackContext);
  if (!ctx) throw new Error("useFeedback must be used within FeedbackProvider");
  return ctx;
}
