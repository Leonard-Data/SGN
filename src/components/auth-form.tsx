'use client'

import { FormEvent, useState } from 'react'
import Link from 'next/link'
import { AtSign, LockKeyhole, ArrowRight, LoaderCircle } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { useApp } from '@/components/app-provider'

type Mode = 'sign-in' | 'sign-up'

export function AuthForm({ mode }: { mode: Mode }) {
  const isSignUp = mode === 'sign-up'
  const { t } = useApp()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [pending, setPending] = useState(false)

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setPending(true); setError(''); setMessage('')
    const supabase = createClient()
    const result = isSignUp
      ? await supabase.auth.signUp({ email, password, options: { emailRedirectTo: process.env.NEXT_PUBLIC_DEV_SUPABASE_REDIRECT_URL ?? `${window.location.origin}/auth/callback` } })
      : await supabase.auth.signInWithPassword({ email, password })
    setPending(false)
    if (result.error) {
      setError(isSignUp ? t.createError : t.invalid)
      return
    }
    if (isSignUp) setMessage(t.checkEmail)
    else window.location.assign('/')
  }

  return <form className="auth-form" onSubmit={submit}>
    <div className="field"><label htmlFor="email">{t.email}</label><div className="input-wrap"><AtSign aria-hidden="true" /><input id="email" type="email" placeholder={t.emailPlaceholder} value={email} onChange={(e) => setEmail(e.target.value)} required autoComplete="email" /></div></div>
    <div className="field"><label htmlFor="password">{t.password}</label><div className="input-wrap"><LockKeyhole aria-hidden="true" /><input id="password" type="password" placeholder={t.passwordPlaceholder} value={password} onChange={(e) => setPassword(e.target.value)} required minLength={6} autoComplete={isSignUp ? 'new-password' : 'current-password'} /></div></div>
    {error && <p className="form-error" role="alert">{error}</p>}
    {message && <p className="form-message" role="status">{message}</p>}
    <button className="primary-button" type="submit" disabled={pending}>{pending ? <><LoaderCircle className="spin" aria-hidden="true" /> {isSignUp ? t.signingUp : t.signingIn}</> : <>{isSignUp ? t.signUp : t.signIn} <ArrowRight aria-hidden="true" /></>}</button>
    <p className="switch-copy">{isSignUp ? t.existing : t.newUser} <Link href={isSignUp ? '/auth/sign-in' : '/auth/sign-up'}>{isSignUp ? t.switchIn : t.switchUp}</Link></p>
  </form>
}
