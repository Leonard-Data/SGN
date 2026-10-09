'use client'
import { useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'
export default function SignOutPage() { useEffect(() => { createClient().auth.signOut().finally(() => window.location.replace('/auth/sign-in')) }, []); return <main className="auth-shell"><div className="loading-card">Signing you out…</div></main> }
