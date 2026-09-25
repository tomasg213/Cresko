"use client";

import { useQuery } from "@tanstack/react-query";
import { Download, Mail, MessageCircle, Printer, X } from "lucide-react";
import { useState } from "react";

import { Button } from "@/components/ui";
import { useOrg } from "@/components/providers";
import { api } from "@/lib/api";
import { formatDocument } from "@/lib/documents";
import {
  buildEmailBody,
  downloadInvoicePdf,
  invoiceEmailSubject,
  invoiceWhatsAppMessage,
  openEmail,
  openWhatsApp,
} from "@/lib/pdf";
import type { Invoice, Organization } from "@/lib/types";
import { formatMoney, formatQty } from "@/lib/utils";

type DocType = "factura" | "nota";

export function PrintDialog({
  invoice,
  onClose,
}: {
  invoice: Invoice;
  onClose: () => void;
}) {
  const { orgId } = useOrg();
  const [docType, setDocType] = useState<DocType>("factura");

  const org = useQuery({
    queryKey: ["org", orgId],
    queryFn: () => api<Organization>(`/v1/orgs`, { orgId }),
    enabled: !!orgId,
  });

  const party = invoice.party;
  const canShare = Boolean(party?.phone || party?.email);

  function print() {
    window.print();
  }

  function downloadPdf() {
    downloadInvoicePdf(invoice, org.data, docType);
  }

  function sendWhatsApp() {
    if (!party?.phone) return;
    openWhatsApp(party.phone, invoiceWhatsAppMessage(invoice));
  }

  function sendEmail() {
    if (!party?.email) return;
    openEmail(
      party.email,
      invoiceEmailSubject(invoice),
      buildEmailBody(invoice, docType),
    );
  }

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/50 p-4 print:static print:block print:overflow-visible print:bg-white print:p-0">
      <div className="w-full max-w-sm">
        <div className="mb-3 flex flex-wrap items-center justify-between gap-2 rounded-t-xl border border-slate-200 bg-white px-4 py-3 print:hidden">
          <div className="flex items-center gap-2">
            <Button
              variant={docType === "factura" ? "primary" : "secondary"}
              onClick={() => setDocType("factura")}
            >
              Factura
            </Button>
            <Button
              variant={docType === "nota" ? "primary" : "secondary"}
              onClick={() => setDocType("nota")}
            >
              Nota de entrega
            </Button>
          </div>
          <div className="flex items-center gap-2">
            <Button onClick={print}>
              <Printer className="h-4 w-4" />
              Imprimir
            </Button>
            <Button variant="secondary" onClick={onClose}>
              <X className="h-4 w-4" />
              No imprimir
            </Button>
          </div>
        </div>

        {canShare && (
          <div className="mb-3 flex flex-wrap items-center gap-2 rounded-xl border border-slate-200 bg-white px-4 py-3 print:hidden">
            <span className="text-xs font-medium text-slate-500 dark:text-slate-400">
              Compartir:
            </span>
            <Button
              variant="secondary"
              className="px-3 py-1.5 text-xs"
              onClick={downloadPdf}
            >
              <Download className="h-4 w-4" />
              PDF
            </Button>
            {party?.phone && (
              <Button
                variant="secondary"
                className="px-3 py-1.5 text-xs"
                onClick={sendWhatsApp}
              >
                <MessageCircle className="h-4 w-4" />
                WhatsApp
              </Button>
            )}
            {party?.email && (
              <Button
                variant="secondary"
                className="px-3 py-1.5 text-xs"
                onClick={sendEmail}
              >
                <Mail className="h-4 w-4" />
                Email
              </Button>
            )}
          </div>
        )}

        <div className="print-area mx-auto w-[80mm] max-w-full rounded-lg border border-slate-300 bg-white p-3 text-[11px] leading-tight text-slate-900">
          {docType === "factura" ? (
            <Factura invoice={invoice} company={org.data} />
          ) : (
            <NotaEntrega invoice={invoice} company={org.data} />
          )}
        </div>
      </div>
    </div>
  );
}

function CompanyHeader({
  company,
  title,
}: {
  company: Organization | undefined;
  title: string;
}) {
  return (
    <div className="mb-2 text-center">
      <div className="text-sm font-bold uppercase tracking-wide">
        {company?.name ?? "Mi Comercio"}
      </div>
      {company?.tax_id && (
        <div className="text-[10px]">RIF: {company.tax_id}</div>
      )}
      {company?.legal_name && (
        <div className="text-[10px]">{company.legal_name}</div>
      )}
      <div className="text-[10px]">Tel: ----------</div>
      <div className="mt-1 text-base font-black uppercase tracking-widest">
        {title}
      </div>
      <Divider />
    </div>
  );
}

function Divider() {
  return <div className="my-1 border-t border-dashed border-slate-400" />;
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between gap-2">
      <span>{label}</span>
      <span className="font-semibold text-right">{value}</span>
    </div>
  );
}

function Factura({
  invoice,
  company,
}: {
  invoice: Invoice;
  company: Organization | undefined;
}) {
  const party = invoice.party;
  return (
    <>
      <CompanyHeader company={company} title="Factura" />
      <Row label="Nº Factura" value={invoice.number} />
      <Row label="Nº Control" value={invoice.number} />
      <Row
        label="Fecha"
        value={new Date(invoice.created_at).toLocaleDateString("es-VE")}
      />
      <Divider />
      <div className="text-[10px] font-semibold uppercase">Cliente</div>
      <div>{party?.name ?? "Consumidor final"}</div>
      <div className="text-[10px]">
        {party?.document_id
          ? formatDocument(party.document_type ?? "other", party.document_id)
          : "C.I.: ----------"}
      </div>
      <Divider />

      <table className="w-full">
        <thead>
          <tr className="border-b border-dashed border-slate-400 text-left">
            <th className="py-0.5 pr-1 font-semibold">Cant</th>
            <th className="py-0.5 pr-1 font-semibold">Descripción</th>
            <th className="py-0.5 text-right font-semibold">Importe</th>
          </tr>
        </thead>
        <tbody>
          {invoice.invoice_lines.map((line) => (
            <tr key={line.id}>
              <td className="py-0.5 pr-1 align-top">{formatQty(line.qty)}</td>
              <td className="py-0.5 pr-1 align-top">
                <div>{line.variant?.name ?? line.variant_id}</div>
                <div className="text-[10px] text-slate-600">
                  {formatMoney(line.unit_price, "VES")} c/u
                </div>
              </td>
              <td className="py-0.5 text-right align-top font-medium">
                {formatMoney(line.line_total, "VES")}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      <Divider />

      <Row label="Subtotal" value={formatMoney(invoice.subtotal, "VES")} />
      <Row
        label={`IVA (${formatQty(invoice.tax_rate)}%)`}
        value={formatMoney(invoice.tax, "VES")}
      />
      <div className="mt-1 flex justify-between border-t border-dashed border-slate-800 pt-1 text-sm font-black">
        <span>TOTAL</span>
        <span>{formatMoney(invoice.total, "VES")}</span>
      </div>

      <p className="mt-3 text-center text-[9px] text-slate-500">
        Factura reglamentaria sujeta a las disposiciones del SENIAT (Ley de IVA
        y su Reglamento).
      </p>
    </>
  );
}

function NotaEntrega({
  invoice,
  company,
}: {
  invoice: Invoice;
  company: Organization | undefined;
}) {
  const party = invoice.party;
  return (
    <>
      <CompanyHeader company={company} title="Nota de entrega" />
      <Row label="Nº" value={invoice.number} />
      <Row label="Factura" value={invoice.number} />
      <Row
        label="Fecha"
        value={new Date(invoice.created_at).toLocaleDateString("es-VE")}
      />
      <Divider />
      <div className="text-[10px] font-semibold uppercase">Entregado a</div>
      <div>{party?.name ?? "Consumidor final"}</div>
      <div className="text-[10px]">
        {party?.document_id
          ? formatDocument(party.document_type ?? "other", party.document_id)
          : "C.I.: ----------"}
      </div>
      <Divider />

      <table className="w-full">
        <thead>
          <tr className="border-b border-dashed border-slate-400 text-left">
            <th className="py-0.5 pr-1 font-semibold">Cant</th>
            <th className="py-0.5 pr-1 font-semibold">Descripción</th>
            <th className="py-0.5 text-right font-semibold">Importe</th>
          </tr>
        </thead>
        <tbody>
          {invoice.invoice_lines.map((line) => (
            <tr key={line.id}>
              <td className="py-0.5 pr-1 align-top">{formatQty(line.qty)}</td>
              <td className="py-0.5 pr-1 align-top">
                {line.variant?.name ?? line.variant_id}
              </td>
              <td className="py-0.5 text-right align-top font-medium">
                {formatMoney(line.line_total, "VES")}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      <Divider />

      <Row label="Subtotal" value={formatMoney(invoice.subtotal, "VES")} />
      <div className="mt-1 flex justify-between border-t border-dashed border-slate-800 pt-1 text-sm font-black">
        <span>TOTAL</span>
        <span>{formatMoney(invoice.total, "VES")}</span>
      </div>

      <div className="mt-3 border border-dashed border-slate-400 p-2 text-[10px] text-slate-600">
        <div className="mb-2 font-semibold uppercase text-slate-700">
          Recibí conforme
        </div>
        <div className="flex items-end justify-between gap-2">
          <div className="flex-1 border-b border-slate-400" />
          <div className="flex-1 border-b border-slate-400" />
        </div>
        <div className="mt-1 flex justify-between text-[9px] text-slate-500">
          <span>Firma y nombre</span>
          <span>Cédula</span>
        </div>
      </div>

      <p className="mt-2 text-center text-[9px] text-slate-500">
        Documento no fiscal. No constituye factura. La factura se emite por
        separado.
      </p>
    </>
  );
}
