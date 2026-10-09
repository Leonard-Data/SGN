import Link from 'next/link'
export default function AuthErrorPage() { return <main className="auth-shell"><div className="error-card"><p className="eyebrow">Something went wrong</p><h1>We couldn&apos;t complete that request.</h1><p>Try again, or return to the sign-in page to continue.</p><Link className="primary-button link-button" href="/auth/sign-in">Back to sign in</Link></div></main> }
