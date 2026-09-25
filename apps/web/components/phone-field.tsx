"use client";

import { useState } from "react";

import { Field, Input, Select } from "@/components/ui";
import { COUNTRIES, countryByDial } from "@/lib/countries";
import { formatPhone } from "@/lib/phones";

export function PhoneField({
  value,
  onChange,
  label = "Teléfono",
  required = false,
}: {
  value: string;
  onChange: (value: string) => void;
  label?: string;
  required?: boolean;
}) {
  const country = countryByDial(value);
  const [countryCode, setCountryCode] = useState(country.code);

  function handleCountryChange(code: string) {
    setCountryCode(code);
    const next = COUNTRIES.find((c) => c.code === code);
    const digits = value.replace(/\D/g, "");
    const withoutDial = digits.startsWith(country.dial)
      ? digits.slice(country.dial.length)
      : digits.startsWith("0")
        ? digits.slice(1)
        : digits;
    onChange(formatPhone(withoutDial, next?.dial ?? "58"));
  }

  function handlePhoneChange(raw: string) {
    onChange(formatPhone(raw, country.dial));
  }

  return (
    <div>
      <span className="mb-1 block text-xs font-medium text-slate-600 dark:text-slate-400">
        {label}
      </span>
      <div className="flex gap-2">
        <Select
          value={countryCode}
          onChange={(event) => handleCountryChange(event.target.value)}
          className="w-32 min-w-0 shrink-0 sm:w-44"
        >
          {COUNTRIES.map((c) => (
            <option key={c.code} value={c.code}>
              {c.name} (+{c.dial})
            </option>
          ))}
        </Select>
        <Input
          type="tel"
          value={value}
          onChange={(event) => handlePhoneChange(event.target.value)}
          placeholder={`+${country.dial} ...`}
          required={required}
          className="min-w-0 flex-1"
        />
      </div>
    </div>
  );
}
