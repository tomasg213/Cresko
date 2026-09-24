export function digitsOnly(value: string): string {
  return (value ?? "").replace(/\D/g, "");
}

export function formatCedula(value: string): string {
  const digits = digitsOnly(value);
  if (!digits) return "";
  return "V-" + digits.replace(/\B(?=(\d{3})+(?!\d))/g, ".");
}

export function formatRif(value: string): string {
  const digits = digitsOnly(value);
  if (!digits) return "";
  if (digits.length <= 1) return "J-" + digits;
  return "J-" + digits.slice(0, -1) + "-" + digits.slice(-1);
}

export function formatPassport(value: string): string {
  const digits = digitsOnly(value);
  if (!digits) return "";
  return "E-" + digits;
}

export function formatDocument(type: string, value: string): string {
  if (!value) return "";
  switch (type) {
    case "ci":
      return formatCedula(value);
    case "rif":
      return formatRif(value);
    case "passport":
      return formatPassport(value);
    default:
      return value;
  }
}
