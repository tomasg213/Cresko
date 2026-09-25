export type Country = {
  code: string;
  name: string;
  dial: string;
};

export const COUNTRIES: Country[] = [
  { code: "ve", name: "Venezuela", dial: "58" },
  { code: "us", name: "Estados Unidos", dial: "1" },
  { code: "co", name: "Colombia", dial: "57" },
  { code: "ec", name: "Ecuador", dial: "593" },
  { code: "pe", name: "Perú", dial: "51" },
  { code: "cl", name: "Chile", dial: "56" },
  { code: "ar", name: "Argentina", dial: "54" },
  { code: "mx", name: "México", dial: "52" },
  { code: "br", name: "Brasil", dial: "55" },
  { code: "es", name: "España", dial: "34" },
  { code: "it", name: "Italia", dial: "39" },
  { code: "pt", name: "Portugal", dial: "351" },
  { code: "pa", name: "Panamá", dial: "507" },
  { code: "do", name: "República Dominicana", dial: "1" },
  { code: "cu", name: "Cuba", dial: "53" },
];

export function countryByDial(dial: string | null | undefined): Country {
  if (dial) {
    const normalized = dial.replace(/\D/g, "");
    const found = COUNTRIES.find((c) => c.dial === normalized);
    if (found) return found;
  }
  return COUNTRIES[0]!;
}
