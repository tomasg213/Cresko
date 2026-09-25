from decimal import Decimal
from enum import StrEnum
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

from .documents import format_document, format_rif
from .phones import format_phone


class Permission(StrEnum):
    ORG_MANAGE = "org.manage"
    MEMBERS_MANAGE = "members.manage"
    ROLES_MANAGE = "roles.manage"
    CATALOG_READ = "catalog.read"
    CATALOG_WRITE = "catalog.write"
    INVENTORY_READ = "inventory.read"
    INVENTORY_WRITE = "inventory.write"
    SALES_READ = "sales.read"
    SALES_CHECKOUT = "sales.checkout"
    SALES_CREDIT = "sales.credit"
    FINANCE_READ = "finance.read"
    FINANCE_RECEIVE = "finance.receive"
    FINANCE_PAY = "finance.pay"
    PURCHASING_READ = "purchasing.read"
    PURCHASING_WRITE = "purchasing.write"
    PURCHASING_RECEIVE = "purchasing.receive"
    REPLENISHMENT_READ = "replenishment.read"
    REPLENISHMENT_WRITE = "replenishment.write"


class Membership(BaseModel):
    model_config = ConfigDict(frozen=True)

    org_id: str
    role_id: str
    role_name: str
    permissions: list[str]


class CurrentUser(BaseModel):
    id: str
    memberships: list[Membership]


class OrganizationContext(BaseModel):
    org_id: str
    user_id: str
    role_id: str
    role_name: str
    permissions: list[Permission]


class RoleBrief(BaseModel):
    id: str
    org_id: str
    name: str
    permissions: list[str]
    is_system: bool


class RoleCreate(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    permissions: list[Permission] = Field(default_factory=list)


class RoleUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=80)
    permissions: list[Permission] | None = None


class PermissionOut(BaseModel):
    code: str
    description: str


class MemberOut(BaseModel):
    id: str
    org_id: str
    user_id: str
    email: str
    role_id: str
    role_name: str


class InvitationIn(BaseModel):
    email: str = Field(min_length=3, max_length=320)
    role_id: str


class InvitationOut(BaseModel):
    id: str
    org_id: str
    email: str
    role_id: str
    status: str
    token: str
    created_at: str


class OrganizationOut(BaseModel):
    id: str
    name: str
    legal_name: str | None = None
    tax_id: str | None = None
    default_currency: Literal["VES", "USD"]
    timezone: str


class OrganizationUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=120)
    legal_name: str | None = Field(default=None, max_length=200)
    tax_id: str | None = Field(default=None, max_length=32)
    default_currency: Literal["VES", "USD"] | None = None

    @field_validator("tax_id")
    @classmethod
    def _format_tax_id(cls, value: str | None) -> str | None:
        return format_rif(value)


class FxRateOut(BaseModel):
    rate: Decimal
    rate_date: str
    source: str


class FxRateUpdate(BaseModel):
    rate: Decimal = Field(gt=0)
    rate_date: str | None = None


class BarcodeIn(BaseModel):
    barcode: str = Field(min_length=1, max_length=64)
    format: str = "EAN13"
    is_primary: bool = False


class PriceIn(BaseModel):
    price_list_code: Literal["retail", "wholesale"]
    amount: Decimal = Field(ge=0)


class VariantIn(BaseModel):
    sku: str | None = Field(default=None, max_length=64)
    name: str | None = Field(default=None, max_length=180)
    attributes: dict[str, Any] = Field(default_factory=dict)
    barcodes: list[BarcodeIn] = Field(default_factory=list)
    prices: list[PriceIn] = Field(default_factory=list)


class ProductCreate(BaseModel):
    name: str = Field(min_length=1, max_length=180)
    description: str | None = None
    category_id: str | None = None
    brand_id: str | None = None
    base_unit: Literal["unit", "kg", "g", "l", "ml", "box", "pair", "pack"] = "unit"
    is_taxable: bool = True
    variants: list[VariantIn] = Field(min_length=1)


class VariantUpdateIn(BaseModel):
    variant_id: str
    name: str | None = Field(default=None, max_length=180)
    sku: str | None = Field(default=None, max_length=64)
    prices: list[PriceIn] = Field(default_factory=list)


class ProductUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=180)
    description: str | None = None
    base_unit: Literal["unit", "kg", "g", "l", "ml", "box", "pair", "pack"] | None = None
    is_taxable: bool | None = None
    variants: list[VariantUpdateIn] = Field(default_factory=list)


class BarcodeOut(BaseModel):
    id: str
    barcode: str
    format: str
    is_primary: bool


class PriceListCode(BaseModel):
    code: str


class PriceOut(BaseModel):
    price_list_id: str
    currency: str
    amount: Decimal
    price_list: PriceListCode | None = None


class VariantOut(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    id: str
    sku: str
    name: str
    attributes: dict[str, Any]
    barcodes: list[BarcodeOut] = Field(default_factory=list)
    prices: list[PriceOut] = Field(default_factory=list, alias="variant_prices")


class ProductOut(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    id: str
    org_id: str
    name: str
    description: str | None = None
    category_id: str | None = None
    brand_id: str | None = None
    base_unit: str
    is_taxable: bool = True
    is_active: bool
    variants: list[VariantOut] = Field(default_factory=list, alias="product_variants")


class VariantRef(BaseModel):
    id: str
    name: str
    sku: str


class WarehouseRef(BaseModel):
    id: str
    name: str
    code: str


class StockLevelOut(BaseModel):
    id: str
    variant_id: str
    warehouse_id: str
    qty: Decimal
    variant: VariantRef | None = None
    warehouse: WarehouseRef | None = None


class StockMovementOut(BaseModel):
    id: str
    variant_id: str
    warehouse_id: str
    movement_type: str
    qty: Decimal
    balance_after: Decimal
    reason: str | None = None
    created_by: str
    created_at: str
    variant: VariantRef | None = None
    warehouse: WarehouseRef | None = None


class AdjustmentIn(BaseModel):
    variant_id: str
    warehouse_id: str
    delta: Decimal
    reason: str | None = Field(default=None, max_length=500)

    @field_validator("delta")
    @classmethod
    def delta_must_not_be_zero(cls, value: Decimal) -> Decimal:
        if value == 0:
            raise ValueError("delta must not be zero")
        return value


class CheckoutLineIn(BaseModel):
    variant_id: str
    qty: Decimal = Field(gt=0)


class PaymentSplitIn(BaseModel):
    method: Literal["cash", "card", "biopago", "transfer"]
    amount: Decimal = Field(ge=0, default=Decimal(0))


class PartyIn(BaseModel):
    name: str = Field(min_length=1, max_length=180)
    document_type: Literal["rif", "ci", "passport", "other"] = "other"
    document_id: str | None = Field(default=None, max_length=32)
    phone: str | None = Field(default=None, max_length=32)
    email: str | None = None

    @field_validator("document_id")
    @classmethod
    def _format_document(cls, value: str | None, info: Any) -> str | None:
        doc_type = info.data.get("document_type", "other")
        return format_document(doc_type, value)

    @field_validator("phone")
    @classmethod
    def _format_phone(cls, value: str | None) -> str | None:
        return format_phone(value)


class CheckoutIn(BaseModel):
    warehouse_id: str
    price_list_code: Literal["retail", "wholesale"]
    tax_rate: Decimal = Field(ge=0, default=Decimal(0))
    lines: list[CheckoutLineIn] = Field(min_length=1)
    payment_method: Literal["cash", "card", "transfer", "credit", "biopago"] = "cash"
    paid_amount: Decimal = Field(ge=0, default=Decimal(0))
    payments: list[PaymentSplitIn] = Field(default_factory=list)
    party_id: str | None = None
    party: PartyIn | None = None


class PosCustomerCreate(BaseModel):
    name: str = Field(min_length=1, max_length=180)
    document_type: Literal["rif", "ci", "passport", "other"] = "other"
    document_id: str | None = Field(default=None, max_length=32)
    phone: str | None = Field(default=None, max_length=32)
    email: str | None = None

    @field_validator("document_id")
    @classmethod
    def _format_document(cls, value: str | None, info: Any) -> str | None:
        doc_type = info.data.get("document_type", "other")
        return format_document(doc_type, value)

    @field_validator("phone")
    @classmethod
    def _format_phone(cls, value: str | None) -> str | None:
        return format_phone(value)


class InvoiceLineOut(BaseModel):
    id: str
    variant_id: str
    qty: Decimal
    unit_price: Decimal
    line_total: Decimal
    tax: Decimal
    currency: str
    variant: VariantRef | None = None


class PartyRef(BaseModel):
    id: str
    name: str
    document_type: str | None = None
    document_id: str | None = None
    phone: str | None = None
    email: str | None = None


class InvoiceOut(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    id: str
    org_id: str
    number: str
    party_id: str | None = None
    subtotal: Decimal
    tax: Decimal
    total: Decimal
    currency: str
    exchange_rate: Decimal
    tax_rate: Decimal
    status: str
    created_by: str
    created_at: str
    party: PartyRef | None = None
    lines: list[InvoiceLineOut] = Field(default_factory=list, alias="invoice_lines")


class PartyOut(BaseModel):
    id: str
    org_id: str
    name: str
    document_type: str
    document_id: str | None = None
    phone: str | None = None
    email: str | None = None
    is_customer: bool
    is_supplier: bool
    is_active: bool


class PartyCreate(BaseModel):
    name: str = Field(min_length=1, max_length=180)
    document_type: Literal["rif", "ci", "passport", "other"] = "other"
    document_id: str | None = Field(default=None, max_length=32)
    phone: str | None = Field(default=None, max_length=32)
    email: str | None = None
    is_customer: bool = False
    is_supplier: bool = False

    @field_validator("document_id")
    @classmethod
    def _format_document(cls, value: str | None, info: Any) -> str | None:
        doc_type = info.data.get("document_type", "other")
        return format_document(doc_type, value)

    @field_validator("phone")
    @classmethod
    def _format_phone(cls, value: str | None) -> str | None:
        return format_phone(value)


class PoLineIn(BaseModel):
    variant_id: str
    qty: Decimal = Field(gt=0)
    unit_cost: Decimal = Field(ge=0)


class PurchaseOrderCreate(BaseModel):
    supplier_id: str
    warehouse_id: str
    currency: Literal["VES", "USD"]
    exchange_rate: Decimal = Field(gt=0, default=Decimal(1))
    tax_rate: Decimal = Field(ge=0, default=Decimal(0))
    expected_at: str | None = None
    notes: str | None = None
    lines: list[PoLineIn] = Field(min_length=1)


class PurchaseOrderOut(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    id: str
    org_id: str
    supplier_id: str
    warehouse_id: str
    number: str
    status: str
    currency: str
    exchange_rate: Decimal
    tax_rate: Decimal
    expected_at: str | None = None
    notes: str | None = None
    created_by: str
    created_at: str
    lines: list["PoLineOut"] = Field(default_factory=list, alias="po_lines")


class PoLineOut(BaseModel):
    id: str
    variant_id: str
    qty_ordered: Decimal
    qty_received: Decimal
    unit_cost: Decimal
    line_total: Decimal
    currency: str
    variant: VariantRef | None = None


class ReceiveLineIn(BaseModel):
    po_line_id: str
    qty: Decimal = Field(gt=0)


class GoodsReceiptCreate(BaseModel):
    lines: list[ReceiveLineIn] = Field(min_length=1)
    received_at: str | None = None
    notes: str | None = None


class GoodsReceiptOut(BaseModel):
    id: str
    org_id: str
    po_id: str
    number: str
    received_at: str
    notes: str | None = None
    created_by: str
    created_at: str


class PaymentIn(BaseModel):
    party_id: str | None = None
    invoice_id: str
    amount: Decimal = Field(gt=0)
    currency: Literal["VES", "USD"]
    method: Literal["cash", "card", "transfer"] = "cash"


class SupplierPaymentIn(BaseModel):
    supplier_invoice_id: str
    amount: Decimal = Field(gt=0)
    currency: Literal["VES", "USD"]
    method: Literal["cash", "card", "transfer"] = "cash"


class GeneralPaymentIn(BaseModel):
    party_id: str
    amount: Decimal = Field(gt=0)
    currency: Literal["VES", "USD"]
    method: Literal["cash", "card", "transfer"] = "cash"


class BalanceOut(BaseModel):
    party_id: str
    party_name: str | None = None
    currency: str
    balance: Decimal


class ArReceivable(BaseModel):
    invoice_id: str | None = None
    invoice_number: str
    party_id: str
    party_name: str | None = None
    currency: str
    balance: Decimal
    source: str = "invoice"
    order_id: str | None = None


class ApReceivable(BaseModel):
    supplier_invoice_id: str
    invoice_number: str
    party_id: str
    party_name: str | None = None
    currency: str
    balance: Decimal


class ReplenishmentConfigIn(BaseModel):
    variant_id: str
    warehouse_id: str
    min_qty: Decimal = Field(ge=0, default=Decimal(0))
    max_qty: Decimal = Field(ge=0, default=Decimal(0))
    pack_multiple: Decimal = Field(gt=0, default=Decimal(1))
    preferred_supplier_id: str | None = None
    lead_time_days: int = Field(ge=0, default=0)
    is_active: bool = True


class ReplenishmentItem(BaseModel):
    variant_id: str
    variant_name: str
    variant_sku: str
    warehouse_id: str
    warehouse_name: str
    on_hand: Decimal
    on_order: Decimal
    min_qty: Decimal
    max_qty: Decimal
    pack_multiple: Decimal
    suggested_qty: Decimal
    preferred_supplier_id: str | None = None


class ReplenishmentConfigOut(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    id: str
    variant_id: str
    warehouse_id: str
    min_qty: Decimal
    max_qty: Decimal
    pack_multiple: Decimal
    preferred_supplier_id: str | None = None
    lead_time_days: int
    is_active: bool
    variant: VariantRef | None = None
    warehouse: WarehouseRef | None = None


class ReplenishmentConfigUpdate(BaseModel):
    variant_id: str | None = None
    warehouse_id: str | None = None
    min_qty: Decimal | None = Field(default=None, ge=0)
    max_qty: Decimal | None = Field(default=None, ge=0)
    pack_multiple: Decimal | None = Field(default=None, gt=0)
    preferred_supplier_id: str | None = None
    lead_time_days: int | None = Field(default=None, ge=0)
    is_active: bool | None = None


class PartyUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=180)
    document_type: Literal["rif", "ci", "passport", "other"] | None = None
    document_id: str | None = Field(default=None, max_length=32)
    phone: str | None = Field(default=None, max_length=32)
    email: str | None = None
    is_customer: bool | None = None
    is_supplier: bool | None = None

    @field_validator("document_id")
    @classmethod
    def _format_document(cls, value: str | None, info: Any) -> str | None:
        doc_type = info.data.get("document_type") or "other"
        return format_document(doc_type, value)

    @field_validator("phone")
    @classmethod
    def _format_phone(cls, value: str | None) -> str | None:
        return format_phone(value)


class ArPaymentOut(BaseModel):
    id: str
    invoice_id: str
    invoice_number: str | None = None
    party_name: str | None = None
    amount: Decimal
    currency: str
    method: str
    status: str
    created_at: str


class OrderCreate(BaseModel):
    product_id: str
    party_id: str
    qty: Decimal = Field(gt=0)
    unit_price: Decimal = Field(ge=0)
    currency: Literal["VES", "USD"] = "USD"
    exchange_rate: Decimal = Field(gt=0, default=Decimal(1))
    tax_rate: Decimal = Field(ge=0, default=Decimal(0))
    paid_amount: Decimal = Field(ge=0, default=Decimal(0))
    payment_method: Literal["cash", "card", "transfer", "credit"] = "cash"
    expected_at: str | None = None
    notes: str | None = None


class SpecialOrderProductCreate(BaseModel):
    variant_id: str
    unit_price: Decimal | None = Field(default=None, ge=0)
    currency: Literal["VES", "USD"] = "USD"


class SpecialOrderProductUpdate(BaseModel):
    unit_price: Decimal | None = Field(default=None, ge=0)
    currency: Literal["VES", "USD"] | None = None
    is_active: bool | None = None


class SpecialOrderProductOut(BaseModel):
    id: str
    org_id: str
    variant_id: str
    unit_price: Decimal
    currency: str
    is_active: bool
    created_by: str
    created_at: str
    variant: VariantRef | None = None


class OrderPaymentIn(BaseModel):
    amount: Decimal = Field(gt=0)
    method: Literal["cash", "card", "transfer"] = "cash"


class OrderOut(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    id: str
    org_id: str
    number: str
    product_id: str
    party_id: str
    qty: Decimal
    unit_cost: Decimal
    unit_price: Decimal
    subtotal: Decimal
    tax: Decimal
    total: Decimal
    currency: str
    exchange_rate: Decimal
    tax_rate: Decimal
    status: str
    paid_amount: Decimal
    payment_method: str | None = None
    expected_at: str | None = None
    notes: str | None = None
    created_by: str
    created_at: str
    delivery_status: str = "pending"
    party: PartyRef | None = None
    product: SpecialOrderProductOut | None = None


class OrderReceivable(BaseModel):
    order_id: str
    number: str
    product_id: str
    product_name: str | None = None
    product_sku: str | None = None
    party_id: str
    party_name: str | None = None
    currency: str
    total: Decimal
    paid_amount: Decimal
    balance: Decimal
    status: str
    delivery_status: str = "pending"
    created_at: str


class OrderPaymentOut(BaseModel):
    id: str
    order_id: str
    amount: Decimal
    currency: str
    method: str
    created_at: str


class CashCloseOut(BaseModel):
    id: str
    org_id: str
    number: str
    opened_at: str
    closed_at: str | None = None
    status: str
    opened_by: str
    closed_by: str | None = None


class CashCloseTransactionOut(BaseModel):
    id: str
    cash_close_id: str
    source: str
    source_id: str
    number: str
    party_name: str | None = None
    total_usd: Decimal
    paid_usd: Decimal
    balance_usd: Decimal
    cash_usd: Decimal
    card_usd: Decimal
    biopago_usd: Decimal
    credit_usd: Decimal


class CashCloseSummary(BaseModel):
    cash_close_id: str
    number: str
    opened_at: str
    closed_at: str
    transactions: int
    total_usd: Decimal
    paid_usd: Decimal
    balance_usd: Decimal
    cash_usd: Decimal
    card_usd: Decimal
    biopago_usd: Decimal
    credit_usd: Decimal


class ApPaymentOut(BaseModel):
    id: str
    supplier_invoice_id: str
    invoice_number: str | None = None
    supplier_name: str | None = None
    amount: Decimal
    currency: str
    created_at: str
