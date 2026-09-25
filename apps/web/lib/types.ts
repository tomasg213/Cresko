export type Permission =
  | "org.manage"
  | "members.manage"
  | "roles.manage"
  | "catalog.read"
  | "catalog.write"
  | "inventory.read"
  | "inventory.write"
  | "sales.read"
  | "sales.checkout"
  | "sales.credit"
  | "finance.read"
  | "finance.receive"
  | "finance.pay"
  | "purchasing.read"
  | "purchasing.write"
  | "purchasing.receive"
  | "replenishment.read"
  | "replenishment.write";

export type Membership = {
  org_id: string;
  role_id: string;
  role_name: string;
  permissions: Permission[];
};

export type CurrentUser = {
  id: string;
  memberships: Membership[];
};

export type Role = {
  id: string;
  org_id: string;
  name: string;
  permissions: Permission[];
  is_system: boolean;
};

export type PermissionInfo = {
  code: Permission;
  description: string;
};

export type Member = {
  id: string;
  org_id: string;
  user_id: string;
  email: string;
  role_id: string;
  role_name: string;
};

export type Invitation = {
  id: string;
  org_id: string;
  email: string;
  role_id: string;
  status: string;
  token: string;
  created_at: string;
};

export type Organization = {
  id: string;
  name: string;
  legal_name: string | null;
  tax_id: string | null;
  default_currency: "VES" | "USD";
  timezone: string;
};

export type FxRate = {
  rate: string;
  rate_date: string;
  source: string;
};

export type VariantRef = { id: string; name: string; sku: string };
export type WarehouseRef = { id: string; name: string; code: string };

export type Barcode = {
  id: string;
  barcode: string;
  format: string;
  is_primary: boolean;
};

export type Price = {
  price_list_id: string;
  currency: "VES" | "USD";
  amount: string;
  price_list?: { code: string } | null;
};

export type Variant = {
  id: string;
  sku: string;
  name: string;
  attributes: Record<string, unknown>;
  barcodes: Barcode[];
  variant_prices: Price[];
};

export type Product = {
  id: string;
  org_id: string;
  name: string;
  description: string | null;
  category_id: string | null;
  brand_id: string | null;
  base_unit: string;
  is_taxable: boolean;
  is_active: boolean;
  product_variants: Variant[];
};

export type StockLevel = {
  id: string;
  variant_id: string;
  warehouse_id: string;
  qty: string;
  variant: VariantRef | null;
  warehouse: WarehouseRef | null;
};

export type StockMovement = {
  id: string;
  variant_id: string;
  warehouse_id: string;
  movement_type: string;
  qty: string;
  balance_after: string;
  reason: string | null;
  created_by: string;
  created_at: string;
  variant: VariantRef | null;
  warehouse: WarehouseRef | null;
};

export type Invoice = {
  id: string;
  org_id: string;
  number: string;
  party_id: string | null;
  subtotal: string;
  tax: string;
  total: string;
  currency: "VES" | "USD";
  exchange_rate: string;
  tax_rate: string;
  status: string;
  created_by: string;
  created_at: string;
  party: PartyRef | null;
  invoice_lines: InvoiceLine[];
};

export type InvoiceLine = {
  id: string;
  variant_id: string;
  qty: string;
  unit_price: string;
  line_total: string;
  tax: string;
  currency: string;
  variant: VariantRef | null;
};

export type PartyRef = {
  id: string;
  name: string;
  document_type: string | null;
  document_id: string | null;
  phone?: string | null;
  email?: string | null;
};

export type Party = {
  id: string;
  org_id: string;
  name: string;
  document_type: string;
  document_id: string | null;
  phone: string | null;
  email: string | null;
  is_customer: boolean;
  is_supplier: boolean;
  is_active: boolean;
};

export type PurchaseOrder = {
  id: string;
  org_id: string;
  supplier_id: string;
  warehouse_id: string;
  number: string;
  status: string;
  currency: "VES" | "USD";
  exchange_rate: string;
  tax_rate: string;
  expected_at: string | null;
  notes: string | null;
  created_by: string;
  created_at: string;
  po_lines: PoLine[];
};

export type PoLine = {
  id: string;
  variant_id: string;
  qty_ordered: string;
  qty_received: string;
  unit_cost: string;
  line_total: string;
  currency: string;
  variant: VariantRef | null;
};

export type GoodsReceipt = {
  id: string;
  org_id: string;
  po_id: string;
  number: string;
  received_at: string;
  notes: string | null;
  created_by: string;
  created_at: string;
};

export type Balance = {
  party_id: string;
  party_name: string | null;
  currency: "VES" | "USD";
  balance: string;
};

export type ArReceivable = {
  invoice_id: string | null;
  invoice_number: string;
  party_id: string;
  party_name: string | null;
  currency: "VES" | "USD";
  balance: string;
  source?: "invoice" | "order";
  order_id?: string | null;
};

export type ApReceivable = {
  supplier_invoice_id: string;
  invoice_number: string;
  party_id: string;
  party_name: string | null;
  currency: "VES" | "USD";
  balance: string;
};

export type ReplenishmentItem = {
  variant_id: string;
  variant_name: string;
  variant_sku: string;
  warehouse_id: string;
  warehouse_name: string;
  on_hand: string;
  on_order: string;
  min_qty: string;
  max_qty: string;
  pack_multiple: string;
  suggested_qty: string;
  preferred_supplier_id: string | null;
};

export type ReplenishmentConfig = {
  id: string;
  variant_id: string;
  warehouse_id: string;
  min_qty: string;
  max_qty: string;
  pack_multiple: string;
  preferred_supplier_id: string | null;
  lead_time_days: number;
  is_active: boolean;
  variant: VariantRef | null;
  warehouse: WarehouseRef | null;
};

export type ArPayment = {
  id: string;
  invoice_id: string;
  invoice_number: string | null;
  party_name: string | null;
  amount: string;
  currency: "VES" | "USD";
  method: string;
  status: string;
  created_at: string;
};

export type ApPayment = {
  id: string;
  supplier_invoice_id: string;
  invoice_number: string | null;
  supplier_name: string | null;
  amount: string;
  currency: "VES" | "USD";
  created_at: string;
};

export type SpecialOrderProduct = {
  id: string;
  org_id: string;
  variant_id: string;
  unit_price: string;
  currency: "VES" | "USD";
  is_active: boolean;
  created_by: string;
  created_at: string;
  variant: VariantRef | null;
};

export type Order = {
  id: string;
  org_id: string;
  number: string;
  product_id: string;
  party_id: string;
  qty: string;
  unit_cost: string;
  unit_price: string;
  subtotal: string;
  tax: string;
  total: string;
  currency: "VES" | "USD";
  exchange_rate: string;
  tax_rate: string;
  status: "pending" | "partial" | "paid" | "cancelled";
  delivery_status: "pending" | "delivered";
  paid_amount: string;
  payment_method: string | null;
  expected_at: string | null;
  notes: string | null;
  created_by: string;
  created_at: string;
  party: PartyRef | null;
  product: SpecialOrderProduct | null;
  payments?: OrderPayment[];
};

export type OrderPayment = {
  id: string;
  order_id: string;
  amount: string;
  currency: "VES" | "USD";
  method: string;
  created_at: string;
};
