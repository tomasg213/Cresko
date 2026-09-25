export function formatPhone(value: string, dial?: string): string {
  const code = dial ?? "58";
  const digits = (value ?? "").replace(/\D/g, "");
  if (!digits) return "";
  if (digits.startsWith("0")) return `+${code}` + digits.slice(1);
  if (digits.startsWith(code)) return "+" + digits;
  return `+${code}` + digits;
}
