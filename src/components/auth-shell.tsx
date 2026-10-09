import Image from 'next/image'

export function AuthShell({ children, title, description }: { children: React.ReactNode; title: string; description: string }) {
  return <main className="auth-shell"><section className="auth-panel"><div className="brand-mark"><Image src="https://hebbkx1anhila5yf.public.blob.vercel-storage.com/logo-6oJN8h1zMZZPQ5OWp6IpYxnQRXbjrI.png" alt="SGN logo" width={64} height={54} unoptimized /><span>SGN <small>REAL ESTATE CRM</small></span></div><div className="auth-copy"><p className="eyebrow">Your property workspace</p><h1>{title}</h1><p>{description}</p></div>{children}<footer>© 2026 SGN · Property, listings, and deals in one place</footer></section></main>
}
