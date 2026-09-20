import { clsx, type ClassValue } from "clsx";

export function cn(...inputs: ClassValue[]) {
  return clsx(inputs);
}

export function formatMoney(amount: string, currency: string) {
  const value = Number(amount);
  const symbol = currency === "USD" ? "$" : "Bs.";
  return `${symbol} ${value.toLocaleString("es-VE", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

export function formatQty(qty: string) {
  const value = Number(qty);
  return Number.isInteger(value) ? String(value) : value.toFixed(3);
}

export function formatDate(value: string) {
  return new Date(value).toLocaleString("es-VE", { dateStyle: "short", timeStyle: "short" });
}