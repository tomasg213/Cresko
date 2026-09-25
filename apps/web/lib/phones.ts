export function formatPhone(value: string): string {
  const digits = (value ?? "").replace(/\D/g, "");
  if (!digits) return "";
  if (digits.startsWith("0")) return "+58" + digits.slice(1);
  if (digits.startsWith("58")) return "+" + digits;
  return "+58" + digits;
}
