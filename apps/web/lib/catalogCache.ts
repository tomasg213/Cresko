import type { Product, Variant } from "@/lib/types";

const DB_NAME = "cresko-catalog";
const STORE = "catalog";

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, 1);
    request.onupgradeneeded = () => {
      request.result.createObjectStore(STORE, { keyPath: "org_id" });
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

export async function saveCatalog(orgId: string, products: Product[]): Promise<void> {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE, "readwrite");
    tx.objectStore(STORE).put({ org_id: orgId, products, saved_at: Date.now() });
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

export async function loadCatalog(orgId: string): Promise<Product[] | null> {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE, "readonly");
    const request = tx.objectStore(STORE).get(orgId);
    request.onsuccess = () => resolve(request.result?.products ?? null);
    request.onerror = () => reject(request.error);
  });
}

export function findVariantByBarcode(products: Product[], barcode: string): Variant | null {
  for (const product of products) {
    for (const variant of product.product_variants) {
      const match = variant.barcodes.some((b) => b.barcode === barcode);
      if (match) return variant;
    }
  }
  return null;
}

export function findVariantById(products: Product[], variantId: string): Variant | null {
  for (const product of products) {
    const variant = product.product_variants.find((v) => v.id === variantId);
    if (variant) return variant;
  }
  return null;
}