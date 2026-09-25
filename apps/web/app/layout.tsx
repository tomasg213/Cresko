import type { Metadata, Viewport } from "next";

import { PwaRegister } from "@/components/pwa-register";
import { Providers } from "@/components/providers";
import { SessionIdle } from "@/components/session-idle";
import "@/app/globals.css";

export const metadata: Metadata = {
  title: "Cresko",
  description: "ERP para comercios en Venezuela",
  applicationName: "Cresko",
  manifest: "/manifest.webmanifest",
  appleWebApp: {
    capable: true,
    statusBarStyle: "default",
    title: "Cresko",
  },
  formatDetection: {
    telephone: false,
  },
  icons: {
    icon: [
      { url: "/icon-192.png", sizes: "192x192", type: "image/png" },
      { url: "/icon-512.png", sizes: "512x512", type: "image/png" },
    ],
    apple: [{ url: "/apple-touch-icon.png", sizes: "180x180" }],
  },
};

export const viewport: Viewport = {
  themeColor: "#0f766e",
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="es">
      <body>
        <Providers>{children}</Providers>
        <SessionIdle />
        <PwaRegister />
      </body>
    </html>
  );
}
