import type { Metadata } from 'next'
import './globals.css'
import { AppProvider } from '@/components/app-provider'

export const metadata: Metadata = {
  title: 'SGN | Real estate workspace',
  description: 'A focused workspace for property inventory, listings, and deals.',
}

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="vi"><body><AppProvider>{children}</AppProvider></body></html>
}
