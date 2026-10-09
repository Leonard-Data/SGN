'use client'

import { useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'

export default function AuthCallbackPage() {
  useEffect(() => {
    const supabase = createClient()
    supabase.auth.getSession().then(({ data }) => {
      window.location.replace(data.session ? '/' : '/auth/error')
    })
  }, [])
  return <main className="auth-shell"><div className="loading-card">Completing your sign in…</div></main>
}
