import { NextRequest, NextResponse } from "next/server"

export function middleware(request: NextRequest) {
  const { hostname, port } = new URL(request.url)
  const host = port ? `${hostname}:${port}` : hostname

  const subdomain = hostname.split(".")[0]

  if (
    subdomain === "www" ||
    subdomain === "localhost" ||
    hostname === "localhost" ||
    !hostname.includes(".")
  ) {
    return NextResponse.next()
  }

  const requestHeaders = new Headers(request.headers)
  requestHeaders.set("X-Tenant-ID", subdomain)

  return NextResponse.next({
    request: {
      headers: requestHeaders,
    },
  })
}

export const config = {
  matcher: "/:path*",
}
