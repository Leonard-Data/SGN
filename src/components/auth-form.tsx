'use client'

import { FormEvent, useState } from 'react'
import Link from 'next/link'
import { AtSign, LockKeyhole, ArrowRight, LoaderCircle } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'

type Mode = 'sign-in' | 'sign-up'

export function AuthForm({ mode }: { mode: Mode }) {
  const isSignUp = mode === 'sign-up'
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
      setError(isSignUp ? 'We could not create your account. Check your details and try again.' : 'Invalid email or password.')
      return
    }
    if (isSignUp) setMessage('Check your inbox to confirm your email, then return here to sign in.')
    else window.location.assign('/')
  }

  return <form className="auth-form" onSubmit={submit}>
    <div className="field"><label htmlFor="email">Email</label><div className="input-wrap"><AtSign aria-hidden="true" /><input id="email" type="email" placeholder="name@example.com" value={email} onChange={(e) => setEmail(e.target.value)} required autoComplete="email" /></div></div>
    <div className="field"><label htmlFor="password">Password</label><div className="input-wrap"><LockKeyhole aria-hidden="true" /><input id="password" type="password" placeholder="Enter your password" value={password} onChange={(e) => setPassword(e.target.value)} required minLength={6} autoComplete={isSignUp ? 'new-password' : 'current-password'} /></div></div>
    {error && <p className="form-error" role="alert">{error}</p>}
    {message && <p className="form-message" role="status">{message}</p>}
    <button className="primary-button" type="submit" disabled={pending}>{pending ? <LoaderCircle className="spin" aria-hidden="true" /> : <>{isSignUp ? 'Create account' : 'Sign in'} <ArrowRight aria-hidden="true" /></>}</button>
    <p className="switch-copy">{isSignUp ? 'Already have an account?' : 'New to SGN?'} <Link href={isSignUp ? '/auth/sign-in' : '/auth/sign-up'}>{isSignUp ? 'Sign in' : 'Create an account'}</Link></p>
  </form>
}
