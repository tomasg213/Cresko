---
name: replenishment
description: Implement inventory reorder calculations and supplier recommendations from min/max levels, stock, reservations, and purchase orders. Use for replenishment features.
---

# Replenishment

- Calculate per variant and warehouse, never only at parent-product level.
- Suggested quantity considers on-hand, reserved, and on-order quantities.
- Include supplier, lead time, minimum order quantity, and pack multiple when available.
- Keep recommendations explainable: show the inputs that caused an item to appear.
- Creating a purchase order is separate from calculating the recommendation.
