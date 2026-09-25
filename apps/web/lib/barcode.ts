import JsBarcode from "jsbarcode";
import { jsPDF } from "jspdf";

export function isValidBarcodeFormat(format: string): boolean {
  return ["EAN13", "EAN8", "UPC_A", "UPC_E", "CODE128", "CODE39"].includes(
    format,
  );
}

/**
 * Genera un código de barras CODE128 aleatorio no vacío, adecuado para
 * productos sin código existente.
 */
export function generateBarcode(): string {
  const alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  let code = "";
  for (let i = 0; i < 12; i++) {
    code += alphabet[Math.floor(Math.random() * alphabet.length)];
  }
  return code;
}

export function generateBarcodePng(
  value: string,
  format = "CODE128",
): Promise<{ dataUrl: string; width: number; height: number }> {
  return new Promise((resolve, reject) => {
    const canvas = document.createElement("canvas");
    JsBarcode(canvas, value, {
      format: isValidBarcodeFormat(format) ? format : "CODE128",
      displayValue: true,
      width: 2,
      height: 60,
      margin: 10,
      fontSize: 18,
    });
    const width = canvas.width;
    const height = canvas.height;
    canvas.toBlob((blob) => {
      if (!blob) {
        reject(new Error("No se pudo generar la imagen del código de barras"));
        return;
      }
      const reader = new FileReader();
      reader.onload = () =>
        resolve({ dataUrl: reader.result as string, width, height });
      reader.onerror = () => reject(reader.error);
      reader.readAsDataURL(blob);
    }, "image/png");
  });
}

/**
 * Exporta el código de barras a un PDF tamaño tarjeta (o etiqueta) con el
 * valor visible bajo las barras.
 */
export async function downloadBarcodePdf(
  value: string,
  label?: string,
  format = "CODE128",
) {
  const { dataUrl, width, height } = await generateBarcodePng(value, format);
  const doc = new jsPDF({ orientation: "portrait", unit: "mm", format: "a6" });

  doc.setFontSize(12);
  doc.setFont("helvetica", "bold");
  const title = label ?? "Código de barras";
  const titleWidth = doc.getTextWidth(title);
  doc.text(title, (doc.internal.pageSize.getWidth() - titleWidth) / 2, 18);

  const pageW = doc.internal.pageSize.getWidth();
  const pageH = doc.internal.pageSize.getHeight();
  const maxW = pageW - 30;
  const maxH = 70;
  const ratio = Math.min(maxW / width, maxH / height);
  const w = width * ratio;
  const h = height * ratio;
  const x = (pageW - w) / 2;
  const y = 28;
  doc.addImage(dataUrl, "PNG", x, y, w, h);

  doc.setFontSize(14);
  doc.setFont("helvetica", "bold");
  const valueWidth = doc.getTextWidth(value);
  doc.text(value, (pageW - valueWidth) / 2, y + h + 14);

  doc.save(`${value}.pdf`);
}

export function renderBarcodeInto(
  container: HTMLElement,
  value: string,
  format = "CODE128",
) {
  container.innerHTML = "";
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  JsBarcode(svg, value, {
    format: isValidBarcodeFormat(format) ? format : "CODE128",
    displayValue: true,
    width: 2,
    height: 60,
    margin: 8,
    fontSize: 16,
  });
  container.appendChild(svg);
}
