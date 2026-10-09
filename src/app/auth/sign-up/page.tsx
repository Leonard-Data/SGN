import { AuthForm } from '@/components/auth-form'
import { AuthShell } from '@/components/auth-shell'

export default function SignUpPage() { return <AuthShell title="Create your account" description="Start managing your property workspace with SGN."><AuthForm mode="sign-up" /></AuthShell> }
