'use client'

import { Moon, Sun } from 'lucide-react'
import { useApp } from '@/components/app-provider'

export function AuthShell({ children, title, description }: { children: React.ReactNode; title: string; description: string }) {
  const { locale, setLocale, theme, toggleTheme, t } = useApp()
  const localizedTitle = title.includes('Create') || title.includes('Tạo') ? t.signUpTitle : t.signInTitle
  const localizedDescription = title.includes('Create') || title.includes('Tạo') ? t.signUpDescription : t.signInDescription
  return <main className="auth-shell"><section className="auth-panel"><div className="utility-bar"><label htmlFor="locale">Language</label><select id="locale" value={locale} onChange={(event) => setLocale(event.target.value as 'vi' | 'en')}><option value="vi">VN</option><option value="en">EN</option></select><button className="theme-button" type="button" onClick={toggleTheme} aria-label={theme === 'light' ? 'Switch to night mode' : 'Switch to day mode'}>{theme === 'light' ? <Moon aria-hidden="true" /> : <Sun aria-hidden="true" />}</button></div><div className="brand-mark"><img src="https://hebbkx1anhila5yf.public.blob.vercel-storage.com/logo-6oJN8h1zMZZPQ5OWp6IpYxnQRXbjrI.png" alt="SGN logo" width="64" height="54" /><span>SGN <small>REAL ESTATE CRM</small></span></div><div className="auth-copy"><p className="eyebrow">{t.eyebrow}</p><h1>{localizedTitle}</h1><p>{localizedDescription}</p></div>{children}<footer>© 2026 SGN · Property, listings, and deals in one place</footer></section></main>
}
