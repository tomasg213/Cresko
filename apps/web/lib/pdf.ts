import { jsPDF } from "jspdf";

import { formatDocument } from "@/lib/documents";
import type { Invoice, Organization } from "@/lib/types";
import { formatMoney, formatQty } from "@/lib/utils";

const MM = 2.8346;
const PAGE_W = 80; // mm

function mm(v: number) {
  return Math.round(v * MM);
}

function center(doc: jsPDF, text: string, y: number) {
  const width = doc.getTextWidth(text);
  doc.text(text, (PAGE_W - width) / 2, y);
}

function lines(doc: jsPDF, y: number) {
  doc.setDrawColor(180);
  doc.line(2, y, PAGE_W - 2, y);
}

export function invoiceAsText(
  invoice: Invoice,
  company: Organization | undefined,
  type: "factura" | "nota",
): string {
  const party = invoice.party;
  const sep = "----------------------------------------";
  const linesOut: string[] = [];

  linesOut.push(company?.name ?? "Mi Comercio");
  if (company?.tax_id) linesOut.push(`RIF: ${company.tax_id}`);
  if (company?.legal_name) linesOut.push(company.legal_name);
  linesOut.push(type === "factura" ? "FACTURA" : "NOTA DE ENTREGA");
  linesOut.push(sep);
  linesOut.push(`Nº: ${invoice.number}`);
  linesOut.push(
    `Fecha: ${new Date(invoice.created_at).toLocaleDateString("es-VE")}`,
  );
  linesOut.push(sep);
  linesOut.push(`Cliente: ${party?.name ?? "Consumidor final"}`);
  if (party?.document_id) {
    linesOut.push(
      formatDocument(party.document_type ?? "other", party.document_id),
    );
  }
  if (party?.phone) linesOut.push(`Tel: ${party.phone}`);
  if (party?.email) linesOut.push(`Email: ${party.email}`);
  linesOut.push(sep);

  linesOut.push("Cant  Descripción           Importe");
  for (const line of invoice.invoice_lines) {
    const name = line.variant?.name ?? line.variant_id;
    const qty = formatQty(line.qty);
    const total = formatMoney(line.line_total, "VES");
    linesOut.push(`${qty.padEnd(5)} ${name.padEnd(22)} ${total}`);
    linesOut.push(
      `       ${formatMoney(line.unit_price, "VES")} c/u`.padEnd(30),
    );
  }
  linesOut.push(sep);
  linesOut.push(`Subtotal: ${formatMoney(invoice.subtotal, "VES")}`);
  if (type === "factura") {
    linesOut.push(
      `IVA (${formatQty(invoice.tax_rate)}%): ${formatMoney(invoice.tax, "VES")}`,
    );
  }
  linesOut.push(`TOTAL: ${formatMoney(invoice.total, "VES")}`);

  if (type === "nota") {
    linesOut.push(sep);
    linesOut.push("Recibí conforme:");
    linesOut.push("Firma: ______________  Cédula: ______________");
    linesOut.push("");
    linesOut.push("Documento no fiscal. No constituye factura.");
  } else {
    linesOut.push(sep);
    linesOut.push(
      "Factura reglamentaria sujeta a las disposiciones del SENIAT (Ley de IVA y su Reglamento).",
    );
  }

  return linesOut.join("\n");
}

export function downloadInvoicePdf(
  invoice: Invoice,
  company: Organization | undefined,
  type: "factura" | "nota",
) {
  const doc = new jsPDF({
    orientation: "portrait",
    unit: "mm",
    format: [PAGE_W, 140],
  });

  let y = 10;
  doc.setFontSize(11);
  doc.setFont("helvetica", "bold");
  center(doc, company?.name ?? "Mi Comercio", y);
  y += 5;
  doc.setFontSize(8);
  doc.setFont("helvetica", "normal");
  if (company?.tax_id) (center(doc, `RIF: ${company.tax_id}`, y), (y += 4));
  if (company?.legal_name) (center(doc, company.legal_name, y), (y += 4));
  center(doc, "Tel: ----------", y);
  y += 5;
  doc.setFontSize(10);
  doc.setFont("helvetica", "bold");
  center(doc, type === "factura" ? "FACTURA" : "NOTA DE ENTREGA", y);
  y += 5;
  lines(doc, y);
  y += 4;

  doc.setFontSize(8);
  doc.setFont("helvetica", "normal");
  const party = invoice.party;
  doc.text(`Nº: ${invoice.number}`, 3, y);
  y += 4;
  doc.text(
    `Fecha: ${new Date(invoice.created_at).toLocaleDateString("es-VE")}`,
    3,
    y,
  );
  y += 6;
  doc.setFont("helvetica", "bold");
  doc.text("Cliente", 3, y);
  y += 4;
  doc.setFont("helvetica", "normal");
  doc.text(party?.name ?? "Consumidor final", 3, y);
  y += 4;
  if (party?.document_id) {
    doc.text(
      formatDocument(party.document_type ?? "other", party.document_id),
      3,
      y,
    );
    y += 4;
  }
  y += 2;
  lines(doc, y);
  y += 4;

  // Encabezado de tabla
  doc.setFont("helvetica", "bold");
  doc.text("Cant", 3, y);
  doc.text("Descripción", 14, y);
  doc.text("Importe", 58, y);
  y += 3;
  doc.setDrawColor(180);
  doc.line(2, y, PAGE_W - 2, y);
  y += 4;
  doc.setFont("helvetica", "normal");

  for (const line of invoice.invoice_lines) {
    const name = line.variant?.name ?? line.variant_id;
    const qty = formatQty(line.qty);
    const total = formatMoney(line.line_total, "VES");
    doc.text(qty, 3, y);
    doc.text(name.length > 32 ? `${name.slice(0, 31)}…` : name, 14, y);
    doc.text(total, 58, y);
    y += 4;
    doc.setFontSize(7);
    doc.text(`${formatMoney(line.unit_price, "VES")} c/u`, 14, y);
    doc.setFontSize(8);
    y += 4;
  }

  y += 2;
  lines(doc, y);
  y += 5;
  doc.setFontSize(8);
  doc.text(`Subtotal: ${formatMoney(invoice.subtotal, "VES")}`, 3, y);
  y += 4;
  if (type === "factura") {
    doc.text(
      `IVA (${formatQty(invoice.tax_rate)}%): ${formatMoney(invoice.tax, "VES")}`,
      3,
      y,
    );
    y += 4;
  }
  doc.setFont("helvetica", "bold");
  doc.text(`TOTAL: ${formatMoney(invoice.total, "VES")}`, 3, y);
  y += 8;

  if (type === "nota") {
    doc.setFont("helvetica", "normal");
    doc.setFontSize(7);
    doc.setDrawColor(150);
    doc.roundedRect(3, y, PAGE_W - 6, 22, 1, 1);
    y += 4;
    doc.setFont("helvetica", "bold");
    center(doc, "Recibí conforme", y);
    y += 8;
    doc.setDrawColor(0);
    doc.line(8, y, 30, y);
    doc.line(50, y, 72, y);
    y += 4;
    doc.setFont("helvetica", "normal");
    doc.setFontSize(6);
    doc.text("Firma y nombre", 8, y);
    doc.text("Cédula", 50, y);
  }

  const filename = `${invoice.number}-${type === "factura" ? "factura" : "nota"}.pdf`;
  doc.save(filename);
}

export function invoiceWhatsAppMessage(
  invoice: Invoice,
  company: Organization | undefined,
  type: "factura" | "nota",
) {
  const party = invoice.party;
  const greeting = party?.name ? `Hola ${party.name},\n` : "";
  return `${greeting}${invoiceAsText(invoice, company, type)}`;
}

export function invoiceEmailSubject(invoice: Invoice) {
  return `Factura ${invoice.number} de ${formatMoney(invoice.total, "VES")}`;
}

export function openWhatsApp(phone: string, message: string) {
  const digits = phone.replace(/\D/g, "");
  const waNumber = digits.startsWith("58") ? digits : `58${digits}`;
  window.open(
    `https://wa.me/${waNumber}?text=${encodeURIComponent(message)}`,
    "_blank",
  );
}

export function openEmail(email: string, subject: string, body: string) {
  window.location.href = `mailto:${email}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
}

export function buildEmailBody(
  invoice: Invoice,
  company: Organization | undefined,
  type: "factura" | "nota",
) {
  const party = invoice.party;
  const greeting = party?.name
    ? `Estimado(a) ${party.name},\n\nLe adjuntamos su ${type === "factura" ? "factura" : "nota de entrega"}.\n\n`
    : `Le adjuntamos su ${type === "factura" ? "factura" : "nota de entrega"}.\n\n`;
  const body = invoiceAsText(invoice, company, type);
  return `${greeting}${body}\n\nGracias por su compra.`;
}
