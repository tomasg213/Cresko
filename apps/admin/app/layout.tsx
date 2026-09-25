import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Cresko · Administración",
  description: "Administración de cuentas de clientes Cresko",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="es">
      <body className="min-h-screen bg-slate-50 text-slate-900">
        {children}
      </body>
    </html>
  );
}